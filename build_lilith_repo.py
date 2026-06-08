#!/usr/bin/env python3
# =============================================================================
# Lilith Linux Repository Builder
# =============================================================================
# Builds all wrapper .deb packages and regenerates the apt Packages/Release
# indexes for the Lilith Linux custom overlay repository.
#
# Usage:
#   python3 /home/aegon/lil-build/build_lilith_repo.py
#
# Output: /home/aegon/lil-build/Lilith-Repo/
#   pool/main/*.deb
#   pool/xtra/*.deb
#   dists/stable/{main,xtra}/binary-amd64/Packages{,.gz}
#   dists/stable/Release
#   lilith-distro-manifest.json
# =============================================================================

import os
import sys
import shutil
import urllib.request
import urllib.error
import hashlib
import subprocess
import json
import datetime

# ── Paths ─────────────────────────────────────────────────────────────────────
REPO_ROOT = "/home/aegon/lil-build/Lilith-Repo"
LIL_BUILD = "/home/aegon/lil-build"
CORE_FILE = os.path.join(LIL_BUILD, "pkgs/lil-core.txt")
XTRA_FILE = os.path.join(LIL_BUILD, "xtra-pks.txt")
UBUNTU_LIST = os.path.join(LIL_BUILD, "ubuntu-26.04-desktop-amd64.list")
MANIFEST_OUT = os.path.join(REPO_ROOT, "lilith-distro-manifest.json")
MAINTAINER = "BlancoBAM <blancobam@protonmail.com>"
REPO_URL = "https://blancobam.github.io/lilith-packages"

print("=== Lilith Linux Repository Builder ===")
print(f"Output: {REPO_ROOT}")

# ── Helpers ───────────────────────────────────────────────────────────────────
def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()

def run_cmd(cmd, cwd=None, check=False):
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd)
    if res.returncode != 0:
        if check:
            print(f"  [-] Command failed: {cmd}\n  Error: {res.stderr.strip()}")
        return None
    return res.stdout

def download_file(url, dest, label=""):
    label = label or os.path.basename(dest)
    try:
        print(f"  [*] Downloading {label}...", end=" ", flush=True)
        urllib.request.urlretrieve(url, dest)
        size_mb = os.path.getsize(dest) / 1024 / 1024
        print(f"OK ({size_mb:.1f} MB)")
        return True
    except Exception as e:
        print(f"FAILED: {e}")
        return False

def init_dirs():
    for comp in ["main", "xtra", "desktop"]:
        os.makedirs(os.path.join(REPO_ROOT, "dists/stable", comp, "binary-amd64"), exist_ok=True)
        os.makedirs(os.path.join(REPO_ROOT, "pool", comp), exist_ok=True)
    print("[+] Repository directory structure ready")

# ── DEB redirect (point apt to upstream URL) ──────────────────────────────────
def get_deb_metadata(url, pkg_name):
    """Download a .deb from url and extract its metadata for the Packages index."""
    cache_dir = "/home/aegon/lil-build/deb-cache"
    os.makedirs(cache_dir, exist_ok=True)
    cache_path = os.path.join(cache_dir, f"{pkg_name}.deb")

    temp_dir = "/tmp/lilith-deb-temp"
    os.makedirs(temp_dir, exist_ok=True)
    deb_path = os.path.join(temp_dir, f"{pkg_name}.deb")

    print(f"  [*] Fetching metadata for {pkg_name}...")
    if os.path.exists(cache_path):
        print(f"    [+] Using cached DEB: {cache_path}")
        shutil.copy2(cache_path, deb_path)
    else:
        try:
            urllib.request.urlretrieve(url, deb_path)
            # Cache it for future runs
            shutil.copy2(deb_path, cache_path)
            print(f"    [+] Cached DEB to: {cache_path}")
        except Exception as e:
            print(f"  [-] Download failed for {url}: {e}")
            return None

    size = os.path.getsize(deb_path)
    sha256 = get_sha256(deb_path)
    control_out = run_cmd(f"dpkg-deb -I {deb_path}")
    os.remove(deb_path)

    metadata = {
        "Package": pkg_name, "Version": "1.0.0",
        "Architecture": "amd64", "Maintainer": MAINTAINER,
        "Description": f"{pkg_name} — Lilith Linux package redirect",
        "Size": str(size), "SHA256": sha256,
        "Filename": url,  # apt will redirect to this URL
    }
    if control_out:
        for line in control_out.splitlines():
            line = line.strip()
            for field in ("Package", "Version", "Architecture", "Maintainer", "Description", "Depends"):
                if line.startswith(f"{field}:"):
                    metadata[field] = line.split(":", 1)[1].strip()

    print(f"    Package={metadata['Package']} Version={metadata['Version']}")
    return metadata

# ── Wrapper deb builder ────────────────────────────────────────────────────────
def build_wrapper_deb(pkg_name, version, desc, postinst_script,
                      component="main", depends=None, preinst=None):
    """Build a minimal wrapper .deb with a postinst that downloads/installs the tool."""
    build_dir = f"/tmp/lilith-wrapper-{pkg_name}"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(os.path.join(build_dir, "DEBIAN"), exist_ok=True)

    depends_str = f"\nDepends: {depends}" if depends else ""
    control = (
        f"Package: {pkg_name}\nVersion: {version}\nSection: misc\n"
        f"Priority: optional\nArchitecture: amd64\nMaintainer: {MAINTAINER}\n"
        f"Description: {desc}{depends_str}\n"
    )
    with open(os.path.join(build_dir, "DEBIAN/control"), "w") as f:
        f.write(control)

    postinst_content = "#!/bin/bash\nset -e\n" + postinst_script + "\nexit 0\n"
    with open(os.path.join(build_dir, "DEBIAN/postinst"), "w") as f:
        f.write(postinst_content)
    os.chmod(os.path.join(build_dir, "DEBIAN/postinst"), 0o755)

    if preinst:
        with open(os.path.join(build_dir, "DEBIAN/preinst"), "w") as f:
            f.write("#!/bin/bash\nset -e\n" + preinst + "\nexit 0\n")
        os.chmod(os.path.join(build_dir, "DEBIAN/preinst"), 0o755)

    output_pool = os.path.join(REPO_ROOT, "pool", component)
    os.makedirs(output_pool, exist_ok=True)
    deb_out_path = os.path.join(output_pool, f"{pkg_name}_{version}_amd64.deb")

    print(f"  [*] Building wrapper deb: {pkg_name}_{version}_amd64.deb")
    run_cmd(f"dpkg-deb --build {build_dir} {deb_out_path}", check=True)
    shutil.rmtree(build_dir, ignore_errors=True)

    size = os.path.getsize(deb_out_path)
    sha256 = get_sha256(deb_out_path)
    rel_filename = f"pool/{component}/{pkg_name}_{version}_amd64.deb"

    return {
        "Package": pkg_name, "Version": version,
        "Architecture": "amd64", "Maintainer": MAINTAINER,
        "Description": f"{desc} (Lilith Wrapper)",
        "Size": str(size), "SHA256": sha256, "Filename": rel_filename,
        **({"Depends": depends} if depends else {}),
    }

# ── Index builder ─────────────────────────────────────────────────────────────
def build_repo_indexes(packages_by_comp):
    print("\n[*] Generating Packages indexes and Release files...")
    now = datetime.datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S UTC")
    sha256_lines = []

    for comp, pkgs in packages_by_comp.items():
        comp_dir = os.path.join(REPO_ROOT, f"dists/stable/{comp}/binary-amd64")
        packages_path = os.path.join(comp_dir, "Packages")

        with open(packages_path, "w") as f:
            for pkg in pkgs:
                block = (
                    f"Package: {pkg['Package']}\n"
                    f"Version: {pkg['Version']}\n"
                    f"Architecture: {pkg['Architecture']}\n"
                    f"Filename: {pkg['Filename']}\n"
                    f"Size: {pkg['Size']}\n"
                    f"SHA256: {pkg['SHA256']}\n"
                    f"Maintainer: {pkg.get('Maintainer', MAINTAINER)}\n"
                    f"Description: {pkg['Description']}\n"
                )
                if "Depends" in pkg:
                    block += f"Depends: {pkg['Depends']}\n"
                block += "\n"
                f.write(block)

        run_cmd(f"gzip -fk {packages_path}")

        # Component Release
        with open(os.path.join(REPO_ROOT, f"dists/stable/{comp}/Release"), "w") as f:
            f.write(
                f"Origin: Lilith Linux\nLabel: Lilith Linux {comp.capitalize()}\n"
                f"Suite: stable\nVersion: 1.0.0\nComponent: {comp}\n"
                f"Architecture: amd64\n"
                f"Description: Lilith Linux {comp.capitalize()} overlay packages\n"
            )

        # Accumulate checksums for main Release
        for fname in ["Packages", "Packages.gz"]:
            fpath = os.path.join(comp_dir, fname)
            if os.path.exists(fpath):
                sha256_lines.append(
                    f" {get_sha256(fpath)} {os.path.getsize(fpath)}"
                    f" {comp}/binary-amd64/{fname}"
                )

    # Main Release file
    main_release = (
        f"Origin: Lilith Linux\n"
        f"Label: Lilith Linux Overlay\n"
        f"Suite: stable\n"
        f"Codename: stable\n"
        f"Date: {now}\n"
        f"Architectures: amd64\n"
        f"Components: main xtra desktop\n"
        f"Description: Thin package overlay for Lilith Linux (Ubuntu Resolute base)\n"
        f"SHA256:\n"
    ) + "\n".join(sha256_lines) + "\n"

    release_path = os.path.join(REPO_ROOT, "dists/stable/Release")
    with open(release_path, "w") as f:
        f.write(main_release)

    # Sign the Release file
    print("[*] Signing Release file with GPG key (blancobam@protonmail.com)...")
    inrelease_path = os.path.join(REPO_ROOT, "dists/stable/InRelease")
    release_gpg_path = os.path.join(REPO_ROOT, "dists/stable/Release.gpg")
    
    # Generate InRelease (clearsigned) and Release.gpg (detached signature)
    run_cmd(f"gpg --batch --yes --clearsign --default-key blancobam@protonmail.com -o {inrelease_path} {release_path}")
    run_cmd(f"gpg --batch --yes -abs --default-key blancobam@protonmail.com -o {release_gpg_path} {release_path}")

def build_grub_theme_deb():
    pkg_name = "lilith-grub-theme"
    version = "1.0.0"
    desc = "Custom grub2 bootloader theme for Lilith Linux (bundled offline)"
    
    build_dir = f"/tmp/lilith-wrapper-{pkg_name}"
    shutil.rmtree(build_dir, ignore_errors=True)
    
    os.makedirs(os.path.join(build_dir, "DEBIAN"), exist_ok=True)
    dest_dir = os.path.join(build_dir, "usr/share/grub/themes/lilith")
    os.makedirs(dest_dir, exist_ok=True)
    
    src_theme = "/home/aegon/grub2-themes"
    if os.path.exists(src_theme):
        for item in ["common", "backgrounds", "config", "install.sh"]:
            src_item = os.path.join(src_theme, item)
            dst_item = os.path.join(dest_dir, item)
            if os.path.isdir(src_item):
                shutil.copytree(src_item, dst_item)
            elif os.path.isfile(src_item):
                shutil.copy2(src_item, dst_item)
    
    control = (
        f"Package: {pkg_name}\nVersion: {version}\nSection: misc\n"
        f"Priority: optional\nArchitecture: amd64\nMaintainer: {MAINTAINER}\n"
        f"Description: {desc}\n"
    )
    with open(os.path.join(build_dir, "DEBIAN/control"), "w") as f:
        f.write(control)
        
    postinst_script = """#!/usr/bin/env bash
set -e
echo "[lilith-grub-theme] Installing grub theme..."
cd /usr/share/grub/themes/lilith
bash install.sh -t tela -i color -s 1080p -b || true
echo "[lilith-grub-theme] Grub theme successfully installed and set!"
exit 0
"""
    with open(os.path.join(build_dir, "DEBIAN/postinst"), "w") as f:
        f.write(postinst_script)
    os.chmod(os.path.join(build_dir, "DEBIAN/postinst"), 0o755)
    
    output_pool = os.path.join(REPO_ROOT, "pool/main")
    os.makedirs(output_pool, exist_ok=True)
    deb_out_path = os.path.join(output_pool, f"{pkg_name}_{version}_amd64.deb")
    
    print(f"  [*] Building grub theme deb: {pkg_name}_{version}_amd64.deb")
    run_cmd(f"dpkg-deb --build {build_dir} {deb_out_path}", check=True)
    shutil.rmtree(build_dir, ignore_errors=True)
    
    size = os.path.getsize(deb_out_path)
    sha256 = get_sha256(deb_out_path)
    rel_filename = f"pool/main/{pkg_name}_{version}_amd64.deb"
    
    return {
        "Package": pkg_name, "Version": version,
        "Architecture": "amd64", "Maintainer": MAINTAINER,
        "Description": desc,
        "Size": str(size), "SHA256": sha256, "Filename": rel_filename
    }

# =============================================================================
# MAIN
# =============================================================================
def main():
    init_dirs()
    packages_by_comp = {"main": [], "xtra": [], "desktop": []}

    # ────────────────────────────────────────────────────────────────────────
    # MAIN COMPONENT — DEB REDIRECTS
    # ────────────────────────────────────────────────────────────────────────
    print("\n── DEB Redirects ──")
    deb_redirects = [
        ("offerings",  "https://github.com/BlancoBAM/Offerings/releases/download/v1.1.0/offerings_1.0.2-beta-1_amd64.deb"),
        ("tweakers",   "https://github.com/BlancoBAM/Tweakers/releases/download/v1.0.1/tweakers-v1.0.1-amd64.deb"),
        ("lilim",      "https://github.com/BlancoBAM/Lilim/releases/download/build-31/lilim_0.1.0_amd64.deb"),
        ("stake",      "https://github.com/BlancoBAM/Stake/releases/download/v0.2.3/stake-v0.2.3-amd64.deb"),
        ("ouija-pad",  "https://github.com/BlancoBAM/Ouija-Pad/releases/download/v1.1.0/ouija-pad_1.1.0_amd64.deb"),
        ("topgrade",   "https://github.com/topgrade-rs/topgrade/releases/download/v17.5.0/topgrade_17.5.0_amd64.deb"),
        ("lsd",        "https://github.com/lsd-rs/lsd/releases/download/v1.2.0/lsd_1.2.0_amd64.deb"),
        ("zoxide",     "https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.9/zoxide_0.9.9-1_amd64.deb"),
        ("bat",        "https://github.com/sharkdp/bat/releases/download/v0.26.1/bat_0.26.1_amd64.deb"),
        ("shapeshifter", "https://github.com/BlancoBAM/Shapeshifter/releases/download/v2.0.0/shapeshifter_2.0.0_amd64.deb"),
    ]
    for name, url in deb_redirects:
        meta = get_deb_metadata(url, name)
        if meta:
            packages_by_comp["main"].append(meta)

    # Custom Grub theme package
    packages_by_comp["main"].append(build_grub_theme_deb())

    # ────────────────────────────────────────────────────────────────────────
    # MAIN COMPONENT — WRAPPER DEBS
    # ────────────────────────────────────────────────────────────────────────
    print("\n── Wrapper DEBs ──")

    # s8n — CLI system manager
    packages_by_comp["main"].append(build_wrapper_deb(
        "s8n-system", "0.1.3",
        "Lilith System Package Manager CLI (s8n)",
        """
echo "[s8n-system] Installing s8n binary..."
mkdir -p /usr/local/bin
curl -fsSL -o /usr/local/bin/s8n https://github.com/BlancoBAM/S8n-System/releases/download/v0.1.3/s8n-linux-amd64
chmod +x /usr/local/bin/s8n
s8n --version 2>/dev/null && echo "[s8n-system] s8n installed OK" || true
""",
        depends="curl"
    ))

    # HellFire Browser — download tar.xz, install to /opt/hellfire
    packages_by_comp["main"].append(build_wrapper_deb(
        "hellfire", "152.0a1",
        "HellFire Browser — privacy-focused custom Firefox for Lilith Linux",
        r"""
set -e
HELLFIRE_URL="https://github.com/CYFARE/HellFire/releases/download/v152.0a1_FP2/hellfire-152.0a1.en-US.linux-x86_64.tar.xz"
HELLFIRE_INSTALLER_URL="https://github.com/CYFARE/HellFire/releases/download/v152.0a1_FP2/linux_installer.py"
INSTALL_DIR="/opt/hellfire"
TARBALL="/tmp/hellfire-152.0a1.tar.xz"

echo "[hellfire] Installing HellFire Browser v152.0a1..."

# Skip if already installed
if [[ -f "$INSTALL_DIR/firefox" ]]; then
    echo "[hellfire] Already installed at $INSTALL_DIR"
else
    echo "[hellfire] Downloading from GitHub Releases (~100 MB)..."
    curl -fsSL -o "$TARBALL" "$HELLFIRE_URL"
    mkdir -p "$INSTALL_DIR"
    tar -xJf "$TARBALL" --strip-components=1 -C "$INSTALL_DIR"
    rm -f "$TARBALL"
fi

# Symlink
ln -sf "$INSTALL_DIR/firefox" /usr/local/bin/hellfire

# Icon
ICON_SRC="$INSTALL_DIR/browser/chrome/icons/default/default128.png"
if [[ -f "$ICON_SRC" ]]; then
    mkdir -p /usr/share/icons/hicolor/128x128/apps
    cp "$ICON_SRC" /usr/share/icons/hicolor/128x128/apps/hellfire.png
fi

# Desktop entry
mkdir -p /usr/share/applications
cat > /usr/share/applications/hellfire.desktop << 'DESKTOP'
[Desktop Entry]
Name=HellFire Browser
GenericName=Web Browser
Comment=Custom-compiled Firefox for Lilith Linux — privacy and performance optimized
Exec=/opt/hellfire/firefox %u
Icon=hellfire
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=firefox
Actions=new-window;new-private-window;
[Desktop Action new-window]
Name=New Window
Exec=/opt/hellfire/firefox --new-window %u
[Desktop Action new-private-window]
Name=New Private Window
Exec=/opt/hellfire/firefox --private-window %u
DESKTOP

# Cache installer for future per-user updates
curl -fsSL -o "$INSTALL_DIR/linux_installer.py" "$HELLFIRE_INSTALLER_URL" 2>/dev/null || true

# Update helper script
cat > /usr/local/bin/hellfire-update << 'HELPER'
#!/bin/bash
# HellFire update helper — runs the GUI installer
python3 /opt/hellfire/linux_installer.py 2>/dev/null || \
  python3 <(curl -fsSL https://github.com/CYFARE/HellFire/releases/latest/download/linux_installer.py)
HELPER
chmod 755 /usr/local/bin/hellfire-update

echo "[hellfire] HellFire Browser installation complete."
""",
        depends="curl, libfuse2t64"
    ))

    # BrowserOS AppImage
    packages_by_comp["main"].append(build_wrapper_deb(
        "browseros", "0.42.0.1",
        "Lilith Default Web Browser OS AppImage",
        """
echo "[browseros] Installing BrowserOS AppImage..."
mkdir -p /opt/browseros
curl -fsSL -o /opt/browseros/BrowserOS.AppImage \
    https://github.com/BlancoBAM/Lilith-Linux/raw/main/BrowserOS_v0.42.0.1_x64.AppImage
chmod +x /opt/browseros/BrowserOS.AppImage
ln -sf /opt/browseros/BrowserOS.AppImage /usr/local/bin/browseros
mkdir -p /usr/share/applications
cat > /usr/share/applications/browseros.desktop << 'EOF'
[Desktop Entry]
Name=BrowserOS
Comment=Lilith Linux Default Web Browser OS
Exec=/usr/local/bin/browseros %U
Icon=web-browser
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOF
echo "[browseros] BrowserOS installed."
""",
        depends="curl, libfuse2t64"
    ))

    # Hyper Terminal AppImage
    packages_by_comp["main"].append(build_wrapper_deb(
        "hyper-terminal", "3.4.1",
        "Hyper terminal emulator for Lilith Linux",
        """
echo "[hyper-terminal] Installing Hyper AppImage..."
mkdir -p /opt/hyper
curl -fsSL -o /opt/hyper/Hyper.AppImage \
    https://github.com/BlancoBAM/Lilith-Linux/raw/main/Hyper-3.4.1.AppImage
chmod +x /opt/hyper/Hyper.AppImage
ln -sf /opt/hyper/Hyper.AppImage /usr/local/bin/hyper
mkdir -p /usr/share/applications
cat > /usr/share/applications/hyper.desktop << 'EOF'
[Desktop Entry]
Name=Hyper
Comment=Lilith Linux Default Terminal Emulator
Exec=/usr/local/bin/hyper
Icon=terminal
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF
echo "[hyper-terminal] Hyper terminal installed."
""",
        depends="curl, libfuse2t64"
    ))

    # Vicinae AppImage
    packages_by_comp["main"].append(build_wrapper_deb(
        "vicinae", "0.21.0",
        "Vicinae Visual Workspace AppImage",
        """
echo "[vicinae] Installing Vicinae AppImage..."
mkdir -p /opt/vicinae
curl -fsSL -o /opt/vicinae/Vicinae.AppImage \
    https://github.com/vicinaehq/vicinae/releases/download/v0.21.0/Vicinae-x86_64.AppImage
chmod +x /opt/vicinae/Vicinae.AppImage
ln -sf /opt/vicinae/Vicinae.AppImage /usr/local/bin/vicinae
mkdir -p /usr/share/applications
cat > /usr/share/applications/vicinae.desktop << 'EOF'
[Desktop Entry]
Name=Vicinae
Comment=Curated visual workspace environment
Exec=/usr/local/bin/vicinae
Icon=workspace
Terminal=false
Type=Application
Categories=Utility;
EOF
echo "[vicinae] Vicinae installed."
""",
        depends="curl, libfuse2t64"
    ))

    # Lilith-TTS
    packages_by_comp["main"].append(build_wrapper_deb(
        "lilith-tts", "1.0.0",
        "Lilith Linux Text-to-Speech Engine",
        """
echo "[lilith-tts] Building Lilith-TTS from source..."
DEST="/usr/local/bin/lilith-tts"
if [[ -f "$DEST" ]]; then
    echo "[lilith-tts] Already installed."
else
    if command -v cargo &>/dev/null; then
        cd /tmp
        rm -rf Lilith-TTS
        git clone https://github.com/BlancoBAM/Lilith-TTS.git
        cd Lilith-TTS
        cargo build --release 2>&1 | tail -5
        cp target/release/lilith-tts-daemon "$DEST" || cp target/release/lilith-tts "$DEST" || true
        chmod 755 "$DEST" || true
    else
        echo "[lilith-tts] cargo not found — skipping compile. Install Rust first."
    fi
fi
""",
        depends="git, curl"
    ))

    # nushell
    packages_by_comp["main"].append(build_wrapper_deb(
        "nushell", "0.103.0",
        "Nu shell — structured data shell written in Rust",
        """
echo "[nushell] Installing nushell..."
if command -v apt-get &>/dev/null; then
    apt-get install -y --no-install-recommends nushell 2>/dev/null && exit 0 || true
fi
NU_URL=$(curl -fsSL https://api.github.com/repos/nushell/nushell/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$NU_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/nu.tar.gz" "$NU_URL"
    tar -xzf "$TMPD/nu.tar.gz" -C "$TMPD"
    NU_BIN=$(find "$TMPD" -name "nu" -type f | head -1)
    [[ -n "$NU_BIN" ]] && cp "$NU_BIN" /usr/local/bin/nu && chmod 755 /usr/local/bin/nu
    rm -rf "$TMPD"
    echo "[nushell] nu installed."
fi
""",
        depends="curl, python3"
    ))

    # fd (find replacement)
    packages_by_comp["main"].append(build_wrapper_deb(
        "fd-lilith", "10.2.0",
        "fd — fast and user-friendly find alternative (Lilith binary edition)",
        """
echo "[fd] Installing fd binary (direct, avoids fd-find conflict)..."
FD_URL=$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$FD_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/fd.tar.gz" "$FD_URL"
    tar -xzf "$TMPD/fd.tar.gz" -C "$TMPD"
    FD_BIN=$(find "$TMPD" -name "fd" -type f | head -1)
    [[ -n "$FD_BIN" ]] && cp "$FD_BIN" /usr/local/bin/fd && chmod 755 /usr/local/bin/fd
    rm -rf "$TMPD"
    echo "[fd] fd installed to /usr/local/bin/fd."
fi
""",
        depends="curl, python3"
    ))

    # rnr (batch rename)
    packages_by_comp["main"].append(build_wrapper_deb(
        "rnr", "0.4.1",
        "rnr — batch rename files using regex patterns",
        """
echo "[rnr] Installing rnr..."
RNR_URL=$(curl -fsSL https://api.github.com/repos/ismaelgv/rnr/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$RNR_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/rnr.tar.gz" "$RNR_URL"
    tar -xzf "$TMPD/rnr.tar.gz" -C "$TMPD"
    RNR_BIN=$(find "$TMPD" -name "rnr" -type f | head -1)
    [[ -n "$RNR_BIN" ]] && cp "$RNR_BIN" /usr/local/bin/rnr && chmod 755 /usr/local/bin/rnr
    rm -rf "$TMPD"
    echo "[rnr] rnr installed."
fi
""",
        depends="curl, python3"
    ))

    # systeroid
    packages_by_comp["main"].append(build_wrapper_deb(
        "systeroid", "0.4.5",
        "systeroid — interactive sysctl TUI manager",
        """
echo "[systeroid] Installing systeroid..."
SYSTEROID_URL=$(curl -fsSL https://api.github.com/repos/orhun/systeroid/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$SYSTEROID_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/systeroid.tar.gz" "$SYSTEROID_URL"
    tar -xzf "$TMPD/systeroid.tar.gz" -C "$TMPD"
    BIN=$(find "$TMPD" -name "systeroid" -type f | head -1)
    [[ -n "$BIN" ]] && cp "$BIN" /usr/local/bin/systeroid && chmod 755 /usr/local/bin/systeroid
    rm -rf "$TMPD"
    echo "[systeroid] systeroid installed."
fi
""",
        depends="curl, python3"
    ))

    # navi
    packages_by_comp["main"].append(build_wrapper_deb(
        "navi", "2.24.0",
        "navi — interactive cheatsheet tool for the command line",
        """
echo "[navi] Installing navi..."
NAVI_URL=$(curl -fsSL https://api.github.com/repos/denisidoro/navi/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$NAVI_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/navi.tar.gz" "$NAVI_URL"
    tar -xzf "$TMPD/navi.tar.gz" -C "$TMPD"
    BIN=$(find "$TMPD" -name "navi" -type f | head -1)
    [[ -n "$BIN" ]] && cp "$BIN" /usr/local/bin/navi && chmod 755 /usr/local/bin/navi
    rm -rf "$TMPD"
    echo "[navi] navi installed."
fi
""",
        depends="curl, python3"
    ))

    # xcp
    packages_by_comp["main"].append(build_wrapper_deb(
        "xcp", "0.24.8",
        "xcp — extended cp with progress bars and parallel copy",
        """
echo "[xcp] Installing xcp..."
XCP_URL="https://github.com/tarka/xcp/releases/download/xcp-v0.24.8/xcp-v0.24.8-x86_64-unknown-linux-gnu.tar.gz"
TMPD=$(mktemp -d)
curl -fsSL -o "$TMPD/xcp.tar.gz" "$XCP_URL"
tar -xzf "$TMPD/xcp.tar.gz" -C "$TMPD"
BIN=$(find "$TMPD" -name "xcp" -type f | head -1)
[[ -n "$BIN" ]] && cp "$BIN" /usr/local/bin/xcp && chmod 755 /usr/local/bin/xcp
rm -rf "$TMPD"
echo "[xcp] xcp installed."
""",
        depends="curl"
    ))

    # kibi
    packages_by_comp["main"].append(build_wrapper_deb(
        "kibi", "0.9.5",
        "kibi — tiny configurable text editor in < 1024 lines of Rust",
        """
echo "[kibi] Installing kibi..."
KIBI_URL=$(curl -fsSL https://api.github.com/repos/ilai-deutel/kibi/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$KIBI_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/kibi.tar.gz" "$KIBI_URL"
    tar -xzf "$TMPD/kibi.tar.gz" -C "$TMPD"
    BIN=$(find "$TMPD" -name "kibi" -type f | head -1)
    [[ -n "$BIN" ]] && cp "$BIN" /usr/local/bin/kibi && chmod 755 /usr/local/bin/kibi
    rm -rf "$TMPD"
    echo "[kibi] kibi installed."
fi
""",
        depends="curl, python3"
    ))

    # czkawka
    packages_by_comp["main"].append(build_wrapper_deb(
        "czkawka", "8.0.0",
        "czkawka — fast duplicate file finder with CLI and GUI",
        """
echo "[czkawka] Installing czkawka..."
CZKAWKA_URL=$(curl -fsSL https://api.github.com/repos/qarmin/czkawka/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    name=a['name'].lower()
    if 'linux' in name and 'gui' not in name and 'x86' in name and not name.endswith('.sha256'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$CZKAWKA_URL" ]]; then
    curl -fsSL -o /usr/local/bin/czkawka "$CZKAWKA_URL"
    chmod 755 /usr/local/bin/czkawka
    echo "[czkawka] czkawka installed."
fi
""",
        depends="curl, python3"
    ))

    # uv (Astral UV)
    packages_by_comp["main"].append(build_wrapper_deb(
        "astral-uv", "0.7.8",
        "uv — extremely fast Python package and project manager by Astral",
        """
echo "[astral-uv] Installing uv..."
UV_URL=$(curl -fsSL https://api.github.com/repos/astral-sh/uv/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and 'uv-x86_64' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$UV_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/uv.tar.gz" "$UV_URL"
    tar -xzf "$TMPD/uv.tar.gz" -C "$TMPD"
    for bin in uv uvx; do
        BIN=$(find "$TMPD" -name "$bin" -type f | head -1)
        [[ -n "$BIN" ]] && cp "$BIN" /usr/local/bin/$bin && chmod 755 /usr/local/bin/$bin
    done
    rm -rf "$TMPD"
    echo "[astral-uv] uv and uvx installed."
fi
""",
        depends="curl, python3"
    ))

    # gemini-cli
    packages_by_comp["main"].append(build_wrapper_deb(
        "gemini-cli", "0.43.0",
        "Google Gemini CLI — AI assistant in the terminal",
        """
echo "[gemini-cli] Installing @google/gemini-cli via npm..."
if ! command -v npm &>/dev/null; then
    apt-get install -y --no-install-recommends nodejs npm 2>/dev/null || true
fi
npm install -g @google/gemini-cli 2>&1 | tail -5
which gemini && echo "[gemini-cli] gemini installed: $(gemini --version 2>/dev/null || echo OK)" || true
""",
        depends="nodejs, npm"
    ))

    # pacstall
    packages_by_comp["main"].append(build_wrapper_deb(
        "pacstall-wrapper", "6.2.1",
        "pacstall — AUR-inspired package manager for Ubuntu/Debian",
        """
echo "[pacstall] Installing pacstall..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends curl wget git sudo lsb-release 2>/dev/null | tail -3
if curl -fsSL "https://pacstall.dev/q/install" -o /tmp/pacstall-install.sh 2>/dev/null; then
    bash /tmp/pacstall-install.sh 2>&1 | tail -10
    rm -f /tmp/pacstall-install.sh
fi
command -v pacstall && echo "[pacstall] installed OK" || echo "[pacstall] install may need reboot"
""",
        depends="curl, git, wget"
    ))

    # soar
    packages_by_comp["main"].append(build_wrapper_deb(
        "soar", "1.0.0",
        "soar — fast distro-agnostic SAB package manager",
        """
echo "[soar] Installing soar..."
if [[ -f /usr/local/bin/soar ]]; then
    echo "[soar] Already installed."
else
    curl -fsSL "https://raw.githubusercontent.com/pkgforge/soar/main/install.sh" | sh
    [[ -f "$HOME/.local/bin/soar" ]] && cp "$HOME/.local/bin/soar" /usr/local/bin/soar && chmod 755 /usr/local/bin/soar || true
fi
""",
        depends="curl"
    ))

    # simplemoji
    packages_by_comp["main"].append(build_wrapper_deb(
        "simplemoji", "1.2.4",
        "Simplemoji — emoji picker for COSMIC/GTK environments",
        """
echo "[simplemoji] Installing simplemoji..."
SM_URL=$(curl -fsSL https://api.github.com/repos/SergioRibera/Simplemoji/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    name=a['name'].lower()
    if 'linux' in name and ('x86_64' in name or 'amd64' in name) and not name.endswith('.sha256'):
        print(a['browser_download_url']); break
" 2>/dev/null)
if [[ -n "$SM_URL" ]]; then
    curl -fsSL -o /usr/local/bin/simplemoji "$SM_URL"
    chmod 755 /usr/local/bin/simplemoji
    echo "[simplemoji] simplemoji installed."
fi
""",
        depends="curl, python3"
    ))

    # Fluent icon theme
    packages_by_comp["main"].append(build_wrapper_deb(
        "fluent-icon-theme-installer", "2024.11.19",
        "Fluent icon theme — modern flat icon theme for Linux desktops",
        """
echo "[fluent-icon-theme] Installing Fluent icon theme..."
cd /tmp
rm -rf Fluent-icon-theme
git clone --depth=1 https://github.com/vinceliuice/Fluent-icon-theme.git
cd Fluent-icon-theme
./install.sh -d /usr/share/icons 2>&1 | tail -5
echo "[fluent-icon-theme] Fluent icons installed."
""",
        depends="git"
    ))

    # pling-store
    packages_by_comp["main"].append(build_wrapper_deb(
        "pling-store-wrapper", "5.0.2",
        "Pling Store — desktop app discovery and installation client",
        """
echo "[pling-store] Installing Pling Store AppImage..."
mkdir -p /opt/pling-store
curl -fsSL -o /opt/pling-store/PlingStore.AppImage \
    "https://ocs-dl.fra1.cdn.digitaloceanspaces.com/data/files/1673754093/pling-store-5.0.2-1-x86-64.AppImage"
chmod +x /opt/pling-store/PlingStore.AppImage
ln -sf /opt/pling-store/PlingStore.AppImage /usr/local/bin/pling-store
mkdir -p /usr/share/applications
cat > /usr/share/applications/pling-store.desktop << 'EOF'
[Desktop Entry]
Name=Pling Store
Comment=Discover and install desktop content
Exec=/usr/local/bin/pling-store
Icon=application-x-addon
Terminal=false
Type=Application
Categories=Utility;PackageManager;
EOF
echo "[pling-store] Pling Store installed."
""",
        depends="curl, libfuse2t64"
    ))

    # script-kit
    packages_by_comp["main"].append(build_wrapper_deb(
        "script-kit-wrapper", "3.45.1",
        "Script Kit — automate anything with JavaScript scripts",
        """
echo "[script-kit] Installing Script Kit AppImage..."
mkdir -p /opt/script-kit
SK_URL=$(curl -fsSL https://api.github.com/repos/johnlindquist/kit/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'Linux' in a['name'] and 'x86_64' in a['name'] and a['name'].endswith('.AppImage'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$SK_URL" ]]; then
    curl -fsSL -o /opt/script-kit/ScriptKit.AppImage "$SK_URL"
else
    curl -fsSL -o /opt/script-kit/ScriptKit.AppImage \
        "https://github.com/johnlindquist/kit/releases/download/v3.45.1/Script-Kit-Linux-3.45.1-x86_64.AppImage" || true
fi
chmod +x /opt/script-kit/ScriptKit.AppImage || true
ln -sf /opt/script-kit/ScriptKit.AppImage /usr/local/bin/script-kit || true
mkdir -p /usr/share/applications
cat > /usr/share/applications/script-kit.desktop << 'EOF'
[Desktop Entry]
Name=Script Kit
Comment=Automate anything with JavaScript
Exec=/usr/local/bin/script-kit
Icon=application-x-executable
Terminal=false
Type=Application
Categories=Development;Utility;
EOF
echo "[script-kit] Script Kit installed."
""",
        depends="curl, libfuse2t64, python3"
    ))

    # cosmic-uniform-glass-theme
    packages_by_comp["main"].append(build_wrapper_deb(
        "cosmic-uniform-glass-theme-installer", "1.0.0",
        "COSMIC Uniform Glass — frosted glass theme for COSMIC Desktop",
        """
echo "[cosmic-glass] Installing COSMIC Uniform Glass theme..."
cd /tmp
rm -rf cosmic-uniform-glass-theme
git clone --depth=1 https://github.com/xarbit/cosmic-uniform-glass-theme.git
mkdir -p /usr/share/cosmic/themes
cp -r cosmic-uniform-glass-theme /usr/share/cosmic/themes/
echo "[cosmic-glass] Theme installed to /usr/share/cosmic/themes/"
""",
        depends="git"
    ))

    # uutils coreutils wrapper
    packages_by_comp["main"].append(build_wrapper_deb(
        "uutils-coreutils-wrapper", "0.0.30",
        "uutils coreutils — Rust reimplementation of GNU coreutils (wrapper)",
        """
echo "[uutils] Installing uutils coreutils..."
if command -v apt-get &>/dev/null; then
    apt-get install -y --no-install-recommends uutils-coreutils 2>/dev/null && echo "[uutils] installed via apt" || true
fi
WRAPPER="/usr/local/bin/uutils-wrapper.sh"
if [[ ! -f "$WRAPPER" ]]; then
    cat > "$WRAPPER" << 'WRAPEOF'
#!/bin/bash
CMD="$(basename "$0")"
if command -v "uu-$CMD" &>/dev/null; then
    exec "uu-$CMD" "$@"
else
    exec "/usr/bin/$CMD" "$@"
fi
WRAPEOF
    chmod 755 "$WRAPPER"
fi
echo "[uutils] Wrapper installed at $WRAPPER"
""",
    ))

    # Noto Color Emoji
    packages_by_comp["main"].append(build_wrapper_deb(
        "noto-color-emoji", "2.047",
        "Noto Color Emoji font from Google Fonts",
        """
echo "[noto-emoji] Installing Noto Color Emoji font..."
apt-get install -y --no-install-recommends fonts-noto-color-emoji 2>/dev/null || true
echo "[noto-emoji] Done."
""",
    ))

    # flatpak + flathub
    packages_by_comp["main"].append(build_wrapper_deb(
        "flatpak-flathub", "1.15.10",
        "Flatpak with Flathub remote configured",
        """
echo "[flatpak] Configuring Flatpak with Flathub remote..."
apt-get install -y flatpak gnome-software-plugin-flatpak 2>/dev/null || true
flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
echo "[flatpak] Flatpak configured with Flathub."
""",
    ))

    # ── Minimal Desktop Environment Meta-Packages ──
    print("\n── Minimal DE Meta-Packages ──")
    de_meta_packages = [
        ("lilith-plasma", "1.0.0", "Minimal KDE Plasma Desktop Environment for Lilith Linux", "plasma-desktop, sddm, systemsettings, plasma-workspace-wayland", "Plasma"),
        ("lilith-xfce", "1.0.0", "Minimal XFCE Desktop Environment for Lilith Linux", "xfce4, xfce4-session, xfwm4, xfce4-panel", "XFCE"),
        ("lilith-lxde", "1.0.0", "Minimal LXDE Desktop Environment for Lilith Linux", "lxde-core, lxsession, openbox", "LXDE"),
        ("lilith-lxqt", "1.0.0", "Minimal LXQt Desktop Environment for Lilith Linux", "lxqt-core, openbox", "LXQt"),
        ("lilith-budgie", "1.0.0", "Minimal Budgie Desktop Environment for Lilith Linux", "budgie-desktop, budgie-indicator-applet", "Budgie"),
        ("lilith-deepin", "1.0.0", "Minimal Deepin Desktop Environment for Lilith Linux", "dde-session-ui, dde-desktop, deepin-wm", "Deepin"),
        ("lilith-trinity", "1.0.0", "Minimal Trinity Desktop Environment for Lilith Linux", "tde-trinity, tdm", "Trinity"),
        ("lilith-enlightenment", "1.0.0", "Minimal Enlightenment Desktop Environment for Lilith Linux", "enlightenment, terminology", "Enlightenment"),
        ("lilith-pantheon", "1.0.0", "Minimal Pantheon Desktop Environment for Lilith Linux", "pantheon-shell, gala, wingpanel, plank", "Pantheon"),
        ("lilith-gnome", "1.0.0", "Minimal GNOME Desktop Environment for Lilith Linux", "gnome-session, gnome-shell, gnome-control-center", "GNOME"),
        ("lilith-mate", "1.0.0", "Minimal MATE Desktop Environment for Lilith Linux", "mate-desktop-environment-core", "MATE"),
        ("lilith-i3", "1.0.0", "Minimal i3 Window Manager for Lilith Linux", "i3-wm, i3status, i3lock, dmenu", "i3"),
        ("lilith-sway", "1.0.0", "Minimal Sway Window Manager for Lilith Linux", "sway, swaylock, swayidle, swaybg, wmenu", "Sway"),
    ]
    for name, version, desc, deps, display_name in de_meta_packages:
        postinst = f"""
echo "[{name}] Installed minimal {display_name} Desktop Environment successfully!"
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database -q || true
fi
"""
        packages_by_comp["desktop"].append(build_wrapper_deb(
            name, version, desc, postinst, component="desktop", depends=deps
        ))

    # ── lilith-welcome — live session welcome app ──────────────────────────────
    packages_by_comp["desktop"].append(build_wrapper_deb(
        "lilith-welcome", "1.0.0",
        "Lilith Linux live-session welcome screen and Calamares installer launcher",
        r"""
set -e
echo "[lilith-welcome] Installing lilith-welcome live welcome app..."

INSTALL_DIR="/usr/share/lilith-welcome"
BIN_DEST="/usr/bin/lilith-welcome"
AUTOSTART_DIR="/etc/xdg/autostart"
CALAMARES_MODULES="/etc/calamares/modules"

# Download the latest lilith-welcome release binary
WELCOME_URL=$(curl -fsSL https://api.github.com/repos/BlancoBAM/lilith-welcome/releases/latest | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for a in data.get('assets', []):
    if 'amd64' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")

if [[ -n "$WELCOME_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/lilith-welcome.tar.gz" "$WELCOME_URL"
    tar -xzf "$TMPD/lilith-welcome.tar.gz" -C "$TMPD"
    BIN=$(find "$TMPD" -name "lilith-welcome" -type f | head -1)
    [[ -n "$BIN" ]] && install -Dm755 "$BIN" "$BIN_DEST"
    # Copy UI assets if bundled
    ASSETS=$(find "$TMPD" -name "assets" -type d | head -1)
    if [[ -n "$ASSETS" ]]; then
        mkdir -p "$INSTALL_DIR/assets"
        cp -r "$ASSETS/"* "$INSTALL_DIR/assets/"
        chmod -R 644 "$INSTALL_DIR/assets/"
        find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    fi
    rm -rf "$TMPD"
    echo "[lilith-welcome] Binary installed to $BIN_DEST"
else
    echo "[lilith-welcome] Could not fetch release — binary must be installed manually"
fi

# Install .desktop launcher
mkdir -p /usr/share/applications
cat > /usr/share/applications/lilith-welcome.desktop << 'DESKTOP'
[Desktop Entry]
Name=Lilith Welcome
GenericName=Welcome Screen
Comment=Lilith Linux live welcome and installer launcher
Exec=/usr/bin/lilith-welcome
Icon=lilith-welcome
Terminal=false
Type=Application
Categories=System;
Keywords=welcome;lilith;linux;install;calamares;
StartupNotify=true
DESKTOP
chmod 644 /usr/share/applications/lilith-welcome.desktop

# Install live-session guard script
cat > /usr/sbin/lilith-live-check.sh << 'GUARD'
#!/usr/bin/env bash
# Launches lilith-welcome only in Casper/live-boot sessions.
IS_LIVE=false
grep -qE "boot=(casper|live)" /proc/cmdline 2>/dev/null && IS_LIVE=true
[[ -f /usr/share/initramfs-tools/hooks/casper ]] && IS_LIVE=true
[[ -f /usr/share/initramfs-tools/hooks/live ]] && IS_LIVE=true
dpkg -s casper &>/dev/null 2>&1 && IS_LIVE=true
dpkg -s live-boot &>/dev/null 2>&1 && IS_LIVE=true
[[ -d /cdrom ]] || [[ -d /cow ]] || [[ -d /lib/live ]] && IS_LIVE=true
CURRENT_USER=$(id -un 2>/dev/null || echo "")
[[ "$CURRENT_USER" =~ ^(ubuntu|user|casper)$ ]] && IS_LIVE=true
if [[ "$IS_LIVE" == "true" ]]; then
    sleep 3; exec /usr/bin/lilith-welcome
fi
exit 0
GUARD
chmod 755 /usr/sbin/lilith-live-check.sh

# Install live-session XDG autostart entry
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/lilith-welcome-live.desktop" << 'AUTOSTART'
[Desktop Entry]
Name=Lilith Welcome
Comment=Lilith Linux welcome screen (live session only)
Exec=/usr/sbin/lilith-live-check.sh
Terminal=false
Type=Application
Icon=lilith-welcome
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=3
NotShowIn=KDE;
AUTOSTART
chmod 644 "$AUTOSTART_DIR/lilith-welcome-live.desktop"

# Install Calamares post-install cleanup module
mkdir -p "$CALAMARES_MODULES"
cat > "$CALAMARES_MODULES/lilith-welcome-cleanup.conf" << 'CALCONF'
---
# Removes lilith-welcome live autostart from the installed system
dontChroot: false
script:
    - "-": "rm -f /etc/xdg/autostart/lilith-welcome-live.desktop"
    - "-": "rm -f /usr/sbin/lilith-live-check.sh"
    - "-": "update-desktop-database /usr/share/applications/ 2>/dev/null || true"
CALCONF

update-desktop-database /usr/share/applications/ 2>/dev/null || true
echo "[lilith-welcome] Installation complete."
""",
        component="desktop",
        depends="curl, python3",
    ))

    # ────────────────────────────────────────────────────────────────────────
    # XTRA COMPONENT — wrapper debs
    # ────────────────────────────────────────────────────────────────────────
    print("\n── Xtra Wrapper DEBs ──")

    xtra_wrappers = [
        ("ferdium", "7.1.2",
         "Ferdium — all-in-one messaging desktop app",
         """
mkdir -p /opt/ferdium
curl -fsSL -o /opt/ferdium/Ferdium.AppImage \
    https://github.com/ferdium/ferdium-app/releases/download/v7.1.2/Ferdium-linux-Portable-7.1.2-x86_64.AppImage
chmod +x /opt/ferdium/Ferdium.AppImage
ln -sf /opt/ferdium/Ferdium.AppImage /usr/local/bin/ferdium
cat > /usr/share/applications/ferdium.desktop << 'EOF'
[Desktop Entry]
Name=Ferdium
Comment=All-in-one messaging app
Exec=/usr/local/bin/ferdium %U
Icon=web-browser
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
EOF
""", "curl, libfuse2t64"),

        ("waveterm", "0.10.4",
         "WaveTerm — open-source AI-native terminal with visual blocks",
         """
WAVE_URL=$(curl -fsSL https://api.github.com/repos/wavetermdev/waveterm/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'linux' in a['name'].lower() and ('x86_64' in a['name'] or 'amd64' in a['name']) and a['name'].endswith('.deb'):
        print(a['browser_download_url']); break
    elif 'linux' in a['name'].lower() and 'x86_64' in a['name'] and a['name'].endswith('.AppImage'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$WAVE_URL" ]]; then
    if [[ "$WAVE_URL" == *.deb ]]; then
        curl -fsSL -o /tmp/waveterm.deb "$WAVE_URL"
        dpkg -i /tmp/waveterm.deb 2>/dev/null || apt-get install -f -y 2>/dev/null || true
        rm -f /tmp/waveterm.deb
    else
        mkdir -p /opt/waveterm
        curl -fsSL -o /opt/waveterm/WaveTerm.AppImage "$WAVE_URL"
        chmod +x /opt/waveterm/WaveTerm.AppImage
        ln -sf /opt/waveterm/WaveTerm.AppImage /usr/local/bin/waveterm
    fi
fi
""", "curl, python3"),

        ("webi-installers", "1.0.0",
         "Webi — easy curl-based installers for developer tools",
         """
curl -fsSL https://webi.sh/webi | sh 2>/dev/null || true
[[ -f "$HOME/.local/bin/webi" ]] && cp "$HOME/.local/bin/webi" /usr/local/bin/webi && chmod 755 /usr/local/bin/webi || true
""", "curl"),

        ("open-interpreter", "0.4.2",
         "Open Interpreter — local AI agent that can execute code",
         """
pip3 install open-interpreter 2>&1 | tail -5 || pip install open-interpreter 2>&1 | tail -5 || true
""", "python3, python3-pip"),

        ("bashsenpai", "1.0.0",
         "BashSenpai — terminal AI assistant for bash commands",
         """
pip3 install bashsenpai 2>&1 | tail -3 || true
""", "python3, python3-pip"),

        ("spacedrive", "0.4.2",
         "Spacedrive — cross-platform open-source file explorer",
         """
SD_URL=$(curl -fsSL https://api.github.com/repos/spacedriveapp/spacedrive/releases/latest | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'linux' in a['name'].lower() and 'x86_64' in a['name'] and (a['name'].endswith('.AppImage') or a['name'].endswith('.deb')):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$SD_URL" ]]; then
    if [[ "$SD_URL" == *.deb ]]; then
        curl -fsSL -o /tmp/spacedrive.deb "$SD_URL"
        dpkg -i /tmp/spacedrive.deb 2>/dev/null || apt-get install -f -y 2>/dev/null || true
        rm -f /tmp/spacedrive.deb
    else
        mkdir -p /opt/spacedrive
        curl -fsSL -o /opt/spacedrive/Spacedrive.AppImage "$SD_URL"
        chmod +x /opt/spacedrive/Spacedrive.AppImage
        ln -sf /opt/spacedrive/Spacedrive.AppImage /usr/local/bin/spacedrive
    fi
fi
""", "curl, python3"),

        ("proton-pass", "1.0.0",
         "Proton Pass — end-to-end encrypted password manager",
         """
PP_URL=$(curl -fsSL https://api.github.com/repos/ProtonMail/WebClients/releases/latest 2>/dev/null | \
    python3 -c "
import sys,json
try:
    data=json.load(sys.stdin)
    for a in data.get('assets',[]):
        if 'linux' in a['name'].lower() and a['name'].endswith('.deb'):
            print(a['browser_download_url']); break
except: pass
" 2>/dev/null || echo "")
if [[ -n "$PP_URL" ]]; then
    curl -fsSL -o /tmp/protonpass.deb "$PP_URL"
    dpkg -i /tmp/protonpass.deb 2>/dev/null || apt-get install -f -y 2>/dev/null || true
    rm -f /tmp/protonpass.deb
else
    echo "[proton-pass] Could not auto-download — visit https://proton.me/pass/download/linux"
fi
""", "curl, python3"),
    ]

    for name, version, desc, script, deps in xtra_wrappers:
        packages_by_comp["xtra"].append(
            build_wrapper_deb(name, version, desc, "\n" + script, component="xtra", depends=deps)
        )

    # Git-only wrappers for xtra
    xtra_git = [
        ("nixite", "0.1.0", "Nixite — minimalist text editor", "https://github.com/aspizu/nixite"),
        ("linuxtoys", "1.0.0", "LinuxToys — collection of interactive terminal toys", "https://github.com/psygreg/linuxtoys"),
        ("keygeist", "0.1.0", "Keygeist — SSH agent UI manager", "https://github.com/mudler/Keygeist"),
        ("cosmic-connect", "1.0.0", "COSMIC Connect — KDE Connect integration applet for COSMIC Desktop", "https://github.com/BlancoBAM/cosmic-connect"),
    ]
    for name, version, desc, url in xtra_git:
        if name == "cosmic-connect":
            depends = "git, curl, cargo, rustc, libdbus-1-dev, libsecret-1-dev, pkg-config"
        else:
            depends = "git, curl"

        script = f"""
echo "[{name}] Cloning and installing {name}..."
cd /tmp
rm -rf {name}
git clone --depth=1 {url}.git {name} 2>/dev/null || git clone --depth=1 {url} {name}
cd {name}
if [[ -f install.sh ]]; then
    bash install.sh
elif command -v just &>/dev/null && [[ -f justfile || -f Justfile ]]; then
    just install
elif [[ -f justfile || -f Justfile ]]; then
    echo "[{name}] just not found. Installing just via cargo..."
    cargo install just 2>&1 | tail -3
    export PATH="$HOME/.cargo/bin:$PATH"
    just install
elif command -v cargo &>/dev/null; then
    cargo install --path . 2>&1 | tail -3
fi
echo "[{name}] Done."
"""
        packages_by_comp["xtra"].append(
            build_wrapper_deb(name, version, desc, script, component="xtra", depends=depends)
        )

    # ────────────────────────────────────────────────────────────────────────
    # Generate indexes
    # ────────────────────────────────────────────────────────────────────────
    build_repo_indexes(packages_by_comp)

    # ────────────────────────────────────────────────────────────────────────
    # Distro Manifest
    # ────────────────────────────────────────────────────────────────────────
    print("\n[*] Generating Unified Distro Manifest...")
    manifest = {
        "distro_name": "Lilith Linux",
        "base_ubuntu_codename": "resolute",
        "repo_url": REPO_URL,
        "generated": datetime.datetime.utcnow().isoformat() + "Z",
        "custom_repository_overlay": {
            "name": "Lilith Custom Repo",
            "url": f"{REPO_URL}/",
            "apt_source": f"deb [arch=amd64 trusted=yes] {REPO_URL} stable main xtra desktop",
            "components": {
                "core": [p["Package"] for p in packages_by_comp["main"]],
                "xtra": [p["Package"] for p in packages_by_comp["xtra"]],
                "desktop": [p["Package"] for p in packages_by_comp["desktop"]]
            }
        },
        "upstream_ubuntu_resolute_packages": []
    }

    if os.path.exists(UBUNTU_LIST):
        seen = set()
        with open(UBUNTU_LIST, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("/pool/"):
                    pkg_name = os.path.basename(line).split("_", 1)[0]
                    if pkg_name not in seen:
                        seen.add(pkg_name)
                        manifest["upstream_ubuntu_resolute_packages"].append(pkg_name)
        manifest["upstream_ubuntu_resolute_packages"].sort()
        print(f"[+] Loaded {len(manifest['upstream_ubuntu_resolute_packages'])} upstream packages")
    else:
        print("[!] ubuntu-26.04-desktop-amd64.list not found — upstream packages omitted")

    with open(MANIFEST_OUT, "w") as f:
        json.dump(manifest, f, indent=4)
    print(f"[+] Manifest written to {MANIFEST_OUT}")

    # Sync files to Lilith-Repo
    for fname in ["lilith-debrep.toml", "packages.list", "uutils-wrapper.sh"]:
        src = os.path.join(LIL_BUILD, fname)
        dst = os.path.join(REPO_ROOT, fname)
        if os.path.exists(src):
            shutil.copy(src, dst)
            print(f"[+] Synced {fname} → Lilith-Repo/")

    # Also sync configure-lilith-os.sh
    main_cfg = "/home/aegon/Lilith/configure-lilith-os.sh"
    if os.path.exists(main_cfg):
        shutil.copy(main_cfg, os.path.join(REPO_ROOT, "configure-lilith-os.sh"))
        print("[+] Synced configure-lilith-os.sh → Lilith-Repo/")

    print("\n=== Lilith Repository build complete! ===")
    print(f"  Main packages: {len(packages_by_comp['main'])}")
    print(f"  Xtra packages: {len(packages_by_comp['xtra'])}")
    print(f"  Desktop packages: {len(packages_by_comp['desktop'])}")
    print(f"  Output: {REPO_ROOT}")

if __name__ == "__main__":
    main()
