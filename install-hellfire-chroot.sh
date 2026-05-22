#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — HellFire Headless Chroot Installer
# =============================================================================
# Downloads and installs HellFire Browser (Firefox-based) to the chroot.
# Uses the real release tar.xz instead of a GUI installer or cargo build.
#
# Install layout:
#   /opt/hellfire/          → extracted tar.xz
#   /usr/local/bin/hellfire → symlink to /opt/hellfire/firefox
#   /usr/share/applications/hellfire.desktop
#   /usr/share/icons/hicolor/128x128/apps/hellfire.png
# =============================================================================
set -euo pipefail

CHROOT="/home/aegon/Lilith/custom-root"
HELLFIRE_URL="https://github.com/CYFARE/HellFire/releases/download/v152.0a1_FP2/hellfire-152.0a1.en-US.linux-x86_64.tar.xz"
HELLFIRE_TARBALL="/tmp/hellfire-152.0a1.tar.xz"
HELLFIRE_VERSION="152.0a1"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[✔]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✘]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }
[[ -d "$CHROOT" ]] || { echo "Chroot not found: $CHROOT"; exit 1; }

cleanup() {
    rm -f "$CHROOT/usr/sbin/policy-rc.d" 2>/dev/null || true
    for fs in run dev/pts dev sys proc; do
        umount -lf "$CHROOT/$fs" 2>/dev/null || true
    done
}
trap cleanup EXIT

# Mount pseudo-filesystems
for fs in proc sys dev dev/pts run; do
    mount --bind "/$fs" "$CHROOT/$fs" 2>/dev/null || true
done
cat > "$CHROOT/usr/sbin/policy-rc.d" << 'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

echo "══ Installing HellFire Browser v${HELLFIRE_VERSION} into chroot ══"

# Download the tarball
if [[ -f "$HELLFIRE_TARBALL" ]]; then
    info "Using cached tarball: $HELLFIRE_TARBALL"
else
    echo ">>> Downloading HellFire ${HELLFIRE_VERSION} (≈100 MB)..."
    curl -fL --progress-bar -o "$HELLFIRE_TARBALL" "$HELLFIRE_URL"
    info "Downloaded: $(du -sh "$HELLFIRE_TARBALL" | cut -f1)"
fi

# Verify the tarball
echo ">>> Verifying tarball..."
if ! tar -tJf "$HELLFIRE_TARBALL" 2>/dev/null | head -5; then
    err "Tarball appears corrupt. Removing and re-downloading..."
    rm -f "$HELLFIRE_TARBALL"
    curl -fL --progress-bar -o "$HELLFIRE_TARBALL" "$HELLFIRE_URL"
fi

# Create install dir in chroot
mkdir -p "$CHROOT/opt/hellfire"

# Check if already extracted
if [[ -f "$CHROOT/opt/hellfire/firefox" ]]; then
    info "HellFire binary already present in chroot — skipping extract"
else
    echo ">>> Extracting HellFire to chroot (this takes a while)..."
    # The tar.xz extracts to a 'firefox/' directory
    tar -xJf "$HELLFIRE_TARBALL" \
        --strip-components=1 \
        -C "$CHROOT/opt/hellfire/" 2>&1 | tail -3
    info "Extraction complete"
fi

# Verify firefox binary exists
if [[ ! -f "$CHROOT/opt/hellfire/firefox" ]]; then
    err "firefox binary not found after extraction — checking structure..."
    ls "$CHROOT/opt/hellfire/" | head -5
    exit 1
fi

# Create /usr/local/bin/hellfire symlink
ln -sf /opt/hellfire/firefox "$CHROOT/usr/local/bin/hellfire"
info "Created symlink: /usr/local/bin/hellfire → /opt/hellfire/firefox"

# Install icon (use the bundled one from the extracted browser)
ICON_SRC="$CHROOT/opt/hellfire/browser/chrome/icons/default/default128.png"
if [[ -f "$ICON_SRC" ]]; then
    mkdir -p "$CHROOT/usr/share/icons/hicolor/128x128/apps"
    cp "$ICON_SRC" "$CHROOT/usr/share/icons/hicolor/128x128/apps/hellfire.png"
    info "Icon installed"
else
    # Create a fallback icon from the 64px version
    for sz in 64 48 32; do
        ICON_FALLBACK="$CHROOT/opt/hellfire/browser/chrome/icons/default/default${sz}.png"
        if [[ -f "$ICON_FALLBACK" ]]; then
            mkdir -p "$CHROOT/usr/share/icons/hicolor/${sz}x${sz}/apps"
            cp "$ICON_FALLBACK" "$CHROOT/usr/share/icons/hicolor/${sz}x${sz}/apps/hellfire.png"
            info "Icon installed (${sz}px)"
            break
        fi
    done
    # Use Firefox stock icon as fallback
    ln -sf firefox "$CHROOT/usr/share/icons/hicolor/48x48/apps/hellfire.png" 2>/dev/null || true
fi

# Install .desktop file
cat > "$CHROOT/usr/share/applications/hellfire.desktop" << 'EOF'
[Desktop Entry]
Name=HellFire Browser
GenericName=Web Browser
Comment=Custom-compiled Firefox browser for Lilith Linux — optimized for privacy and performance
Exec=/opt/hellfire/firefox %u
Icon=hellfire
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;
StartupNotify=true
StartupWMClass=firefox
Keywords=hellfire;browser;web;firefox;cyfare;internet;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=Open a New Window
Exec=/opt/hellfire/firefox --new-window %u

[Desktop Action new-private-window]
Name=Open a New Private Window
Exec=/opt/hellfire/firefox --private-window %u
EOF
chmod 644 "$CHROOT/usr/share/applications/hellfire.desktop"
info ".desktop installed"

# Install the Python GUI installer to /opt/hellfire/ for future reinstalls
INSTALLER_DEST="$CHROOT/opt/hellfire/linux_installer.py"
if [[ ! -f "$INSTALLER_DEST" ]]; then
    echo ">>> Caching linux_installer.py..."
    curl -fsSL -o "$INSTALLER_DEST" \
        "https://github.com/CYFARE/HellFire/releases/download/v152.0a1_FP2/linux_installer.py" 2>/dev/null || true
    [[ -f "$INSTALLER_DEST" ]] && chmod 755 "$INSTALLER_DEST" && info "linux_installer.py cached"
fi

# Create a simple update/reinstall helper script
cat > "$CHROOT/usr/local/bin/hellfire-update" << 'UPDATEEOF'
#!/bin/bash
# HellFire Browser Update Helper
# Downloads and runs the HellFire GUI installer for updates
set -e

HELLFIRE_DIR="$HOME/HellFire"
INSTALLER="/opt/hellfire/linux_installer.py"

if [[ -f "$INSTALLER" ]]; then
    echo "Running HellFire installer..."
    python3 "$INSTALLER"
else
    echo "Fetching latest HellFire installer..."
    TMPINST=$(mktemp /tmp/hellfire-installer-XXXXXX.py)
    curl -fsSL -o "$TMPINST" \
        "https://github.com/CYFARE/HellFire/releases/latest/download/linux_installer.py"
    python3 "$TMPINST"
    rm -f "$TMPINST"
fi
UPDATEEOF
chmod 755 "$CHROOT/usr/local/bin/hellfire-update"
info "hellfire-update helper installed"

echo ""
echo "=== HellFire Verification ==="
ls -lh "$CHROOT/opt/hellfire/firefox" 2>/dev/null && echo "  ✔ firefox binary" || echo "  ✘ firefox binary MISSING"
ls -l "$CHROOT/usr/local/bin/hellfire" 2>/dev/null && echo "  ✔ /usr/local/bin/hellfire symlink" || echo "  ✘ symlink MISSING"
ls "$CHROOT/usr/share/applications/hellfire.desktop" 2>/dev/null && echo "  ✔ hellfire.desktop" || echo "  ✘ .desktop MISSING"
ls "$CHROOT/usr/local/bin/hellfire-update" 2>/dev/null && echo "  ✔ hellfire-update helper" || echo "  ✘ helper MISSING"

info "HellFire Browser installation complete."
