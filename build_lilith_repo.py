#!/usr/bin/env python3
import os
import sys
import shutil
import urllib.request
import hashlib
import subprocess
import json

# Paths
REPO_ROOT = "/home/aegon/Lilith-Repo"
LIL_BUILD = "/home/aegon/lil-build"
CORE_FILE = os.path.join(LIL_BUILD, "pkgs/lil-core.txt")
XTRA_FILE = os.path.join(LIL_BUILD, "xtra-pks.txt")
UBUNTU_LIST = os.path.join(LIL_BUILD, "ubuntu-26.04-desktop-amd64.list")
MANIFEST_OUT = os.path.join(REPO_ROOT, "lilith-distro-manifest.json")

print("=== Starting Lilith Linux Repo Builder ===")

# Create directory structure
def init_dirs():
    for comp in ["main", "xtra"]:
        os.makedirs(os.path.join(REPO_ROOT, "dists/stable", comp, "binary-amd64"), exist_ok=True)
        os.makedirs(os.path.join(REPO_ROOT, "pool", comp), exist_ok=True)
    print("[+] Repository directory structure created")

# Helper to calculate SHA256
def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as file:
        while True:
            chunk = file.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()

# Helper to run shell commands
def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd)
    if res.returncode != 0:
        print(f"[-] Command failed: {cmd}\nError: {res.stderr}")
        return None
    return res.stdout

# Temporary download and extract control metadata
def get_deb_metadata(url, pkg_name):
    temp_dir = "/tmp/lilith-deb-temp"
    os.makedirs(temp_dir, exist_ok=True)
    deb_path = os.path.join(temp_dir, f"{pkg_name}.deb")
    
    print(f"[*] Downloading {pkg_name} from {url}...")
    try:
        urllib.request.urlretrieve(url, deb_path)
    except Exception as e:
        print(f"[-] Failed to download {url}: {e}")
        return None
        
    size = os.path.getsize(deb_path)
    sha256 = get_sha256(deb_path)
    
    # Extract control info
    control_out = run_cmd(f"dpkg-deb -I {deb_path}")
    os.remove(deb_path)
    
    if not control_out:
        return None
        
    metadata = {}
    for line in control_out.splitlines():
        line = line.strip()
        if line.startswith("Package:"):
            metadata["Package"] = line.split(":", 1)[1].strip()
        elif line.startswith("Version:"):
            metadata["Version"] = line.split(":", 1)[1].strip()
        elif line.startswith("Architecture:"):
            metadata["Architecture"] = line.split(":", 1)[1].strip()
        elif line.startswith("Depends:"):
            metadata["Depends"] = line.split(":", 1)[1].strip()
        elif line.startswith("Description:"):
            metadata["Description"] = line.split(":", 1)[1].strip()
        elif line.startswith("Maintainer:"):
            metadata["Maintainer"] = line.split(":", 1)[1].strip()
            
    metadata["Size"] = str(size)
    metadata["SHA256"] = sha256
    metadata["Filename"] = url  # Absolute Redirect URL!
    
    # Defaults if missing
    if "Package" not in metadata: metadata["Package"] = pkg_name
    if "Version" not in metadata: metadata["Version"] = "1.0.0"
    if "Architecture" not in metadata: metadata["Architecture"] = "amd64"
    if "Description" not in metadata: metadata["Description"] = "Lilith Linux package redirect"
    
    return metadata

# Generate a tiny wrapper package
def build_wrapper_deb(pkg_name, version, desc, postinst_script, component="main"):
    build_dir = f"/tmp/lilith-wrapper-{pkg_name}"
    os.makedirs(os.path.join(build_dir, "DEBIAN"), exist_ok=True)
    
    # Write control file
    control_content = f"""Package: {pkg_name}
Version: {version}
Section: misc
Priority: optional
Architecture: amd64
Maintainer: Lilith Linux Developer <packages@lilithlinux.org>
Description: {desc} (Wrapper Package)
"""
    with open(os.path.join(build_dir, "DEBIAN/control"), "w") as f:
        f.write(control_content)
        
    # Write postinst script
    with open(os.path.join(build_dir, "DEBIAN/postinst"), "w") as f:
        f.write("#!/bin/bash\nset -e\n" + postinst_script + "\nexit 0\n")
        
    os.chmod(os.path.join(build_dir, "DEBIAN/postinst"), 0o755)
    
    # Build the package
    output_pool = os.path.join(REPO_ROOT, "pool", component)
    os.makedirs(output_pool, exist_ok=True)
    deb_out_path = os.path.join(output_pool, f"{pkg_name}_{version}_amd64.deb")
    
    print(f"[*] Building wrapper DEB for {pkg_name}...")
    run_cmd(f"dpkg-deb --build {build_dir} {deb_out_path}")
    shutil.rmtree(build_dir)
    
    # Return package metadata block for Packages index
    size = os.path.getsize(deb_out_path)
    sha256 = get_sha256(deb_out_path)
    
    # Filename will be relative for hosted wrapper packages
    rel_filename = f"pool/{component}/{pkg_name}_{version}_amd64.deb"
    
    metadata = {
        "Package": pkg_name,
        "Version": version,
        "Architecture": "amd64",
        "Description": f"{desc} (Wrapper)",
        "Maintainer": "Lilith Linux Developer <packages@lilithlinux.org>",
        "Size": str(size),
        "SHA256": sha256,
        "Filename": rel_filename
    }
    return metadata

def build_repo_indexes(packages_by_comp):
    print("[*] Generating Packages.gz and Release files...")
    
    for comp, pkgs in packages_by_comp.items():
        comp_dir = os.path.join(REPO_ROOT, f"dists/stable/{comp}/binary-amd64")
        packages_txt_path = os.path.join(comp_dir, "Packages")
        
        with open(packages_txt_path, "w") as f:
            for pkg in pkgs:
                block = f"""Package: {pkg['Package']}
Version: {pkg['Version']}
Architecture: {pkg['Architecture']}
Filename: {pkg['Filename']}
Size: {pkg['Size']}
SHA256: {pkg['SHA256']}
Maintainer: {pkg.get('Maintainer', 'Lilith Developer')}
Description: {pkg['Description']}"""
                if 'Depends' in pkg:
                    block += f"\nDepends: {pkg['Depends']}"
                block += "\n\n"
                f.write(block)
                
        # Compress Packages to Packages.gz
        run_cmd(f"gzip -fk {packages_txt_path}")
        
        # Component Release file
        comp_release_content = f"""Origin: Lilith Linux
Label: Lilith Linux {comp.capitalize()}
Suite: stable
Version: 1.0.0
Component: {comp}
Architecture: amd64
Description: Lilith Linux {comp.capitalize()} Redirect Packages
"""
        with open(os.path.join(REPO_ROOT, f"dists/stable/{comp}/Release"), "w") as f:
            f.write(comp_release_content)
            
    # Main Release file
    main_release_content = f"""Origin: Lilith Linux
Label: Lilith Linux Overlay
Suite: stable
Codename: stable
Date: Mon, 18 May 2026 04:20:00 UTC
Architectures: amd64
Components: main xtra
Description: Thin package overlay for Lilith Linux
SHA256:
"""
    # Calculate checksums for Packages.gz
    for comp in ["main", "xtra"]:
        pkg_gz_path = os.path.join(REPO_ROOT, f"dists/stable/{comp}/binary-amd64/Packages.gz")
        if os.path.exists(pkg_gz_path):
            size = os.path.getsize(pkg_gz_path)
            sha256 = get_sha256(pkg_gz_path)
            main_release_content += f" {sha256} {size} {comp}/binary-amd64/Packages.gz\n"
            
        pkg_path = os.path.join(REPO_ROOT, f"dists/stable/{comp}/binary-amd64/Packages")
        if os.path.exists(pkg_path):
            size = os.path.getsize(pkg_path)
            sha256 = get_sha256(pkg_path)
            main_release_content += f" {sha256} {size} {comp}/binary-amd64/Packages\n"

    with open(os.path.join(REPO_ROOT, "dists/stable/Release"), "w") as f:
        f.write(main_release_content)
        
    print("[+] Repository index files generated successfully!")

# Parse the lists and populate repository
def main():
    init_dirs()
    
    packages_by_comp = {"main": [], "xtra": []}
    
    # 1. Custom core apps from lil-core.txt (main component)
    # Define DEB redirects
    deb_redirects = [
        ("offerings", "https://github.com/BlancoBAM/Offerings/releases/download/v1.1.0/offerings_1.0.2-beta-1_amd64.deb"),
        ("tweakers", "https://github.com/BlancoBAM/Tweakers/releases/download/v1.0.1/tweakers-v1.0.1-amd64.deb"),
        ("lilim", "https://github.com/BlancoBAM/Lilim/releases/download/build-31/lilim_0.1.0_amd64.deb"),
        ("stake", "https://github.com/BlancoBAM/Stake/releases/download/v0.2.3/stake-v0.2.3-amd64.deb"),
        ("ouija-pad", "https://github.com/BlancoBAM/Ouija-Pad/releases/download/v1.1.0/ouija-pad_1.1.0_amd64.deb"),
        ("topgrade", "https://github.com/topgrade-rs/topgrade/releases/download/v17.5.0/topgrade_17.5.0_amd64.deb"),
        ("lsd", "https://github.com/lsd-rs/lsd/releases/download/v1.2.0/lsd_1.2.0_amd64.deb"),
        ("zoxide", "https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.9/zoxide_0.9.9-1_amd64.deb"),
        ("bat", "https://github.com/sharkdp/bat/releases/download/v0.26.1/bat_0.26.1_amd64.deb")
    ]
    
    for name, url in deb_redirects:
        meta = get_deb_metadata(url, name)
        if meta:
            packages_by_comp["main"].append(meta)
            
    # Define wrapper debs for AppImages and git builds
    # s8n system CLI wrapper
    s8n_script = """
echo "Downloading s8n-system binary..."
mkdir -p /usr/local/bin
curl -sSL -o /usr/local/bin/s8n https://github.com/BlancoBAM/S8n-System/releases/download/v0.1.3/s8n-linux-amd64
chmod +x /usr/local/bin/s8n
"""
    packages_by_comp["main"].append(build_wrapper_deb("s8n-system", "0.1.3", "Lilith System Package Manager CLI wrapper", s8n_script))

    # BrowserOS AppImage
    browseros_script = """
echo "Downloading BrowserOS AppImage..."
mkdir -p /opt/browseros
curl -sSL -o /opt/browseros/BrowserOS.AppImage https://github.com/BlancoBAM/Lilith-Linux/raw/main/BrowserOS_v0.42.0.1_x64.AppImage
chmod +x /opt/browseros/BrowserOS.AppImage
ln -sf /opt/browseros/BrowserOS.AppImage /usr/local/bin/browseros

# Create desktop entry
mkdir -p /usr/share/applications
cat > /usr/share/applications/browseros.desktop << 'EOF'
[Desktop Entry]
Name=BrowserOS
Comment=Lilith Linux Default Web Browser OS
Exec=browseros
Icon=web-browser
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOF
"""
    packages_by_comp["main"].append(build_wrapper_deb("browseros", "0.42.0", "Lilith Default Web Browser OS AppImage", browseros_script))

    # Hyper Terminal AppImage wrapper
    hyper_script = """
echo "Downloading Hyper terminal AppImage..."
mkdir -p /opt/hyper
curl -sSL -o /opt/hyper/Hyper.AppImage https://github.com/BlancoBAM/Lilith-Linux/raw/main/Hyper-3.4.1.AppImage
chmod +x /opt/hyper/Hyper.AppImage
ln -sf /opt/hyper/Hyper.AppImage /usr/local/bin/hyper

# Create desktop entry
mkdir -p /usr/share/applications
cat > /usr/share/applications/hyper.desktop << 'EOF'
[Desktop Entry]
Name=Hyper
Comment=Default Terminal of Lilith Linux
Exec=hyper
Icon=terminal
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF
"""
    packages_by_comp["main"].append(build_wrapper_deb("hyper-terminal", "3.4.1", "Hyper terminal emulator for Lilith Linux", hyper_script))

    # Vicinae AppImage
    vicinae_script = """
echo "Downloading Vicinae AppImage..."
mkdir -p /opt/vicinae
curl -sSL -o /opt/vicinae/Vicinae.AppImage https://github.com/vicinaehq/vicinae/releases/download/v0.21.0/Vicinae-x86_64.AppImage
chmod +x /opt/vicinae/Vicinae.AppImage
ln -sf /opt/vicinae/Vicinae.AppImage /usr/local/bin/vicinae

# Create desktop entry
mkdir -p /usr/share/applications
cat > /usr/share/applications/vicinae.desktop << 'EOF'
[Desktop Entry]
Name=Vicinae
Comment=Curated visual workspace
Exec=vicinae
Icon=workspace
Terminal=false
Type=Application
Categories=Utility;
EOF
"""
    packages_by_comp["main"].append(build_wrapper_deb("vicinae", "0.21.0", "Vicinae Visual Workspace AppImage", vicinae_script))

    # Lilith-TTS Git Repo
    tts_script = """
echo "Cloning and building Lilith-TTS..."
cd /tmp
git clone https://github.com/BlancoBAM/Lilith-TTS.git
cd Lilith-TTS
if command -v cargo &> /dev/null; then
    cargo build --release
    cp target/release/lilith-tts /usr/local/bin/
else
    echo "Cargo not found, skipping compile"
fi
"""
    packages_by_comp["main"].append(build_wrapper_deb("lilith-tts", "1.0.0", "Text-to-Speech Engine", tts_script))

    # HellFire Git Repo
    hellfire_script = """
echo "Cloning and installing HellFire..."
cd /tmp
git clone https://github.com/CYFARE/HellFire.git
cd HellFire
if command -v cargo &> /dev/null; then
    cargo build --release
    cp target/release/hellfire /usr/local/bin/ || cp target/release/hell-fire /usr/local/bin/ || true
fi
"""
    packages_by_comp["main"].append(build_wrapper_deb("hellfire", "1.0.0", "HellFire Distro Tool", hellfire_script))

    # Soar Package Manager
    soar_script = """
echo "Installing soar..."
curl -fsSL "https://raw.githubusercontent.com/pkgforge/soar/main/install.sh" | sh
"""
    packages_by_comp["main"].append(build_wrapper_deb("soar", "1.0.0", "Soar Package Manager wrapper", soar_script))

    # Astral UV
    uv_script = """
echo "Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh
"""
    packages_by_comp["main"].append(build_wrapper_deb("astral-uv", "1.0.0", "Astral uv python package manager wrapper", uv_script))

    # Pacstall
    pacstall_script = """
echo "Installing pacstall..."
export DEBIAN_FRONTEND=noninteractive
sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install)" || true
"""
    packages_by_comp["main"].append(build_wrapper_deb("pacstall-wrapper", "1.0.0", "Pacstall Package Manager wrapper", pacstall_script))

    # Fluent-icon-theme Git wrapper
    fluent_script = """
echo "Installing Fluent-icon-theme..."
cd /tmp
git clone https://github.com/vinceliuice/Fluent-icon-theme.git
cd Fluent-icon-theme
./install.sh -d /usr/share/icons
"""
    packages_by_comp["main"].append(build_wrapper_deb("fluent-icon-theme-installer", "1.0.0", "Fluent icon theme installer wrapper", fluent_script))

    # Pling-store
    pling_script = """
echo "Installing Pling-Store AppImage..."
mkdir -p /opt/pling-store
curl -sSL -o /opt/pling-store/PlingStore.AppImage "https://ocs-dl.fra1.cdn.digitaloceanspaces.com/data/files/1673754093/pling-store-5.0.2-1-x86-64.AppImage"
chmod +x /opt/pling-store/PlingStore.AppImage
ln -sf /opt/pling-store/PlingStore.AppImage /usr/local/bin/pling-store
"""
    packages_by_comp["main"].append(build_wrapper_deb("pling-store-wrapper", "5.0.2", "Pling-Store Client wrapper", pling_script))

    # Script-Kit
    sk_script = """
echo "Installing Script-Kit AppImage..."
mkdir -p /opt/script-kit
curl -sSL -o /opt/script-kit/ScriptKit.AppImage "https://github.com/johnlindquist/kit/releases/download/v3.45.1/Script-Kit-Linux-3.45.1-x86_64.AppImage" || true
chmod +x /opt/script-kit/ScriptKit.AppImage || true
ln -sf /opt/script-kit/ScriptKit.AppImage /usr/local/bin/script-kit || true
"""
    packages_by_comp["main"].append(build_wrapper_deb("script-kit-wrapper", "3.45.1", "Script-Kit Desktop Application wrapper", sk_script))

    # Cosmic Uniform Glass Theme
    glass_script = """
echo "Cloning and installing cosmic-uniform-glass-theme..."
cd /tmp
git clone https://github.com/xarbit/cosmic-uniform-glass-theme.git
mkdir -p /usr/share/cosmic/themes
cp -r cosmic-uniform-glass-theme /usr/share/cosmic/themes/
"""
    packages_by_comp["main"].append(build_wrapper_deb("cosmic-uniform-glass-theme-installer", "1.0.0", "Cosmic Uniform Glass Theme installer", glass_script))

    # 2. Curated optional recommended packages from xtra-pks.txt (xtra component)
    xtra_debs = [
        ("ferdium", "https://github.com/ferdium/ferdium-app/releases/download/v7.1.2/Ferdium-linux-Portable-7.1.2-x86_64.AppImage", "Ferdium Desktop multi-service visual app"),
        ("nixite", "https://github.com/aspizu/nixite", "Nixite Text Editor"),
        ("linuxtoys", "https://github.com/psygreg/linuxtoys", "Collection of toys for terminal"),
        ("homepage", "https://github.com/gethomepage/homepage", "Homepage browser start page dashboard"),
        ("bashsenpai", "https://github.com/BashSenpai/cli", "BashSenpai Terminal AI assistant"),
        ("open-interpreter", "https://github.com/openinterpreter/open-interpreter", "Open Interpreter local AI agent executor"),
        ("keygeist", "https://github.com/mudler/Keygeist", "Keygeist SSH agent UI manager")
    ]
    
    for name, url, desc in xtra_debs:
        # Build simple custom wrappers for extra apps
        if "releases/download" in url and url.endswith(".AppImage"):
            # AppImage wrapper
            script = f"""
echo "Installing {name} AppImage..."
mkdir -p /opt/{name}
curl -sSL -o /opt/{name}/{name}.AppImage {url}
chmod +x /opt/{name}/{name}.AppImage
ln -sf /opt/{name}/{name}.AppImage /usr/local/bin/{name}
"""
            packages_by_comp["xtra"].append(build_wrapper_deb(name, "1.0.0", desc, script, component="xtra"))
        else:
            # Git wrapper
            script = f"""
echo "Cloning {name}..."
cd /tmp
git clone {url}.git
# Build/install actions as needed
"""
            packages_by_comp["xtra"].append(build_wrapper_deb(name, "1.0.0", desc, script, component="xtra"))
            
    # Generate indexes
    build_repo_indexes(packages_by_comp)
    
    # 3. Create the Unified Distro Manifest
    print("[*] Generating Unified Distro Manifest...")
    manifest = {
        "distro_name": "Lilith Linux",
        "base_ubuntu_codename": "resolute",
        "custom_repository_overlay": {
            "name": "Lilith Custom Repo",
            "url": "https://packages.lilithlinux.org/",
            "components": {
                "core": [p["Package"] for p in packages_by_comp["main"]],
                "xtra": [p["Package"] for p in packages_by_comp["xtra"]]
            }
        },
        "upstream_ubuntu_resolute_packages": []
    }
    
    # Read upstream packages list
    if os.path.exists(UBUNTU_LIST):
        with open(UBUNTU_LIST, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("/pool/"):
                    # Extract package name from relative pool path
                    filename = os.path.basename(line)
                    pkg_name = filename.split("_", 1)[0]
                    manifest["upstream_ubuntu_resolute_packages"].append(pkg_name)
                    
        # Remove duplicates
        manifest["upstream_ubuntu_resolute_packages"] = sorted(list(set(manifest["upstream_ubuntu_resolute_packages"])))
        print(f"[+] Loaded {len(manifest['upstream_ubuntu_resolute_packages'])} upstream Resolute Raccoon packages")
    else:
        print("[!] Warning: ubuntu-26.04-desktop-amd64.list not found, upstream packages skipped in manifest")
        
    with open(MANIFEST_OUT, "w") as f:
        json.dump(manifest, f, indent=4)
    print(f"[+] Unified Distro Manifest written to {MANIFEST_OUT}")
    
    # Copy spec and list to Lilith-Repo
    shutil.copy(os.path.join(LIL_BUILD, "lilith-debrep.toml"), os.path.join(REPO_ROOT, "lilith-debrep.toml"))
    shutil.copy(os.path.join(LIL_BUILD, "packages.list"), os.path.join(REPO_ROOT, "packages.list"))
    print("[+] Copied specs and lists to static repo folder")
    print("=== Repo build completed successfully! ===")

if __name__ == "__main__":
    main()
