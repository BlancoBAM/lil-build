#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — Comprehensive Chroot Fix Script v3.0
# =============================================================================
# Fixes ALL outstanding issues:
#   1. Updates splash videos to correct files
#   2. Updates boot-splash and presplash scripts for new video names
#   3. Installs and enables splash services properly
#   4. Installs mpv inside chroot
#   5. Replaces Plymouth logo.png with Lilith official logo
#   6. Replaces ubuntu-text Plymouth theme title/branding with Lilith
#   7. Replaces Ubuntu distributor logos with Lilith official-logo
#   8. Replaces Ubuntu pixmap logos with Lilith logos
#   9. Installs lilith-spinner.webm as system spinner
#  10. Installs s8n desktop entry
#  11. Rebuilds initramfs and updates GRUB
# =============================================================================
set -euo pipefail

CHROOT="/home/aegon/Lilith/custom-root"
OFFICIAL_LOGO="/home/aegon/Pictures/official-logo.png"
BANNER="/home/aegon/Pictures/lilith-banner.png"
SPINNER="/home/aegon/Downloads/lilith-spinner.webm"
BOOT_VIDEO="/home/aegon/Downloads/lilith-burn-loading.mp4"
PRE_LOGIN_VIDEO="/home/aegon/Downloads/splash-canon.mp4"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✘]${NC} $*"; exit 1; }
step()  { echo -e "\n${BLUE}══${NC} $* ${BLUE}══${NC}"; }

[[ $EUID -eq 0 ]] || err "Must be run as root. Use: sudo bash $0"
[[ -d "$CHROOT" ]] || err "Chroot not found at $CHROOT"
[[ -f "$OFFICIAL_LOGO" ]] || err "Official logo not found: $OFFICIAL_LOGO"
[[ -f "$BANNER" ]] || err "Banner not found: $BANNER"
[[ -f "$SPINNER" ]] || err "Spinner not found: $SPINNER"
[[ -f "$BOOT_VIDEO" ]] || err "Boot video not found: $BOOT_VIDEO"
[[ -f "$PRE_LOGIN_VIDEO" ]] || err "Pre-login video not found: $PRE_LOGIN_VIDEO"

KERNEL_VERSION=$(ls "$CHROOT/boot/" | grep "vmlinuz-" | sed 's/vmlinuz-//' | sort -V | tail -1)
info "Kernel: $KERNEL_VERSION"

# ── Mount pseudo-filesystems ──────────────────────────────────────────────────
step "Mounting pseudo-filesystems"
for fs in proc sys dev dev/pts run; do
    mount --bind "/$fs" "$CHROOT/$fs" 2>/dev/null && echo "  mounted: $fs" || echo "  already mounted: $fs"
done

cleanup() {
    step "Unmounting pseudo-filesystems"
    rm -f "$CHROOT/usr/sbin/policy-rc.d" 2>/dev/null || true
    for fs in run dev/pts dev sys proc; do
        umount -lf "$CHROOT/$fs" 2>/dev/null || true
    done
    info "Cleanup complete."
}
trap cleanup EXIT

# Suppress service starts during chroot operations
cat > "$CHROOT/usr/sbin/policy-rc.d" << 'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

# =============================================================================
# PART 1 — Splash Videos (update to new files)
# =============================================================================
step "PART 1 — Installing updated splash videos"

VIDEO_DEST="$CHROOT/usr/share/lilith/splash"
mkdir -p "$VIDEO_DEST"

cp -v "$BOOT_VIDEO"      "$VIDEO_DEST/boot.mp4"
cp -v "$PRE_LOGIN_VIDEO" "$VIDEO_DEST/login-splash.mp4"

# Also install spinner video
SPINNER_DEST="$CHROOT/usr/share/lilith/splash"
cp -v "$SPINNER" "$SPINNER_DEST/lilith-spinner.webm"

chmod 644 "$VIDEO_DEST/"*
info "Splash videos installed"

# =============================================================================
# PART 2 — Update boot-splash and presplash scripts
# =============================================================================
step "PART 2 — Installing updated splash scripts"

cat > "$CHROOT/usr/local/bin/lilith-boot-splash.sh" << 'SCRIPTEOF'
#!/bin/bash
# Lilith Linux — Boot Splash (loop video during boot)
# Plays lilith-burn-loading.mp4 on a loop during the boot process via DRM/KMS.
# Killed automatically when lilith-presplash.service starts.

VIDEO="/usr/share/lilith/splash/boot.mp4"

# Wait for a DRM device to become available (up to 10 seconds)
for i in $(seq 1 20); do
    ls /dev/dri/card* >/dev/null 2>&1 && break
    sleep 0.5
done

# Turn off the text cursor
printf '\033[?25l' > /dev/tty1 2>/dev/null || true

# Blank the console
setterm --blank 0 --powerdown 0 --cursor off --clear all > /dev/tty1 2>/dev/null || true

# Suppress kernel messages
dmesg -n 1 2>/dev/null || true

exec mpv \
    --vo=drm \
    --drm-connector=0 \
    --really-quiet \
    --no-terminal \
    --no-osc \
    --no-osd-bar \
    --loop=inf \
    --hwdec=auto \
    --audio-device=auto \
    --volume=100 \
    "$VIDEO"
SCRIPTEOF
chmod 755 "$CHROOT/usr/local/bin/lilith-boot-splash.sh"

cat > "$CHROOT/usr/local/bin/lilith-presplash.sh" << 'SCRIPTEOF'
#!/bin/bash
# Lilith Linux — Pre-Login Splash (plays full splash-canon.mp4 before greeter)
# Plays the full login splash video on DRM/KMS before the greeter starts.
# This runs AFTER boot, completely replacing the looping boot splash.

VIDEO="/usr/share/lilith/splash/login-splash.mp4"

# Ensure the console cursor is hidden
printf '\033[?25l' > /dev/tty1 2>/dev/null || true

# Stop the boot splash service if still running
systemctl stop lilith-boot-splash.service 2>/dev/null || true

# Wait briefly for DRM release from the previous player
sleep 0.3

# Play the full login splash video — no loop, no skip
mpv \
    --vo=drm \
    --drm-connector=0 \
    --really-quiet \
    --no-terminal \
    --no-osc \
    --no-osd-bar \
    --loop=no \
    --hwdec=auto \
    --audio-device=auto \
    --volume=100 \
    "$VIDEO"

# Restore cursor after video ends
printf '\033[?25h' > /dev/tty1 2>/dev/null || true
SCRIPTEOF
chmod 755 "$CHROOT/usr/local/bin/lilith-presplash.sh"
info "Splash scripts updated"

# =============================================================================
# PART 3 — Install systemd services and enable them
# =============================================================================
step "PART 3 — Installing and enabling splash systemd services"

cat > "$CHROOT/etc/systemd/system/lilith-boot-splash.service" << 'EOF'
[Unit]
Description=Lilith Boot Splash (Looping Video)
Documentation=https://lilith.linux
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target display-manager.service lilith-presplash.service graphical.target
Conflicts=lilith-presplash.service

[Service]
Type=simple
ExecStart=/usr/local/bin/lilith-boot-splash.sh
Restart=on-failure
RestartSec=1
TimeoutStopSec=3
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=sysinit.target
EOF

cat > "$CHROOT/etc/systemd/system/lilith-presplash.service" << 'EOF'
[Unit]
Description=Lilith Pre-Login Splash (Full splash-canon.mp4)
Documentation=https://lilith.linux
DefaultDependencies=no
After=sysinit.target local-fs.target multi-user.target lilith-boot-splash.service
Before=display-manager.service graphical.target
Conflicts=lilith-boot-splash.service

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/usr/local/bin/lilith-presplash.sh
Restart=no
TimeoutStartSec=300
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=display-manager.service
EOF

# Enable the services by creating symlinks manually (since systemctl enable can't run headlessly)
mkdir -p "$CHROOT/etc/systemd/system/sysinit.target.wants"
mkdir -p "$CHROOT/etc/systemd/system/display-manager.service.wants"

ln -sf /etc/systemd/system/lilith-boot-splash.service \
    "$CHROOT/etc/systemd/system/sysinit.target.wants/lilith-boot-splash.service" 2>/dev/null || true
ln -sf /etc/systemd/system/lilith-presplash.service \
    "$CHROOT/etc/systemd/system/display-manager.service.wants/lilith-presplash.service" 2>/dev/null || true

info "Splash services installed and enabled"

# =============================================================================
# PART 4 — Install mpv inside chroot
# =============================================================================
step "PART 4 — Installing mpv inside chroot"

chroot "$CHROOT" /bin/bash << 'CHROOTEOF'
export DEBIAN_FRONTEND=noninteractive
echo ">>> Updating apt cache..."
apt-get update -qq 2>&1
echo ">>> Installing mpv..."
apt-get install -y --no-install-recommends mpv 2>&1
echo ">>> mpv: $(mpv --version 2>/dev/null | head -1 || echo FAILED)"
CHROOTEOF
info "mpv installed"

# =============================================================================
# PART 5 — Plymouth branding (replace Ubuntu with Lilith)
# =============================================================================
step "PART 5 — Replacing Plymouth Ubuntu branding with Lilith"

# Replace the main Plymouth logo.png with official-logo.png (resize to match 1056x992)
convert "$OFFICIAL_LOGO" -resize "1056x992!" "$CHROOT/usr/share/plymouth/logo.png"
info "Replaced /usr/share/plymouth/logo.png with Lilith official logo"

# Update ubuntu-text plymouth theme to show Lilith branding
cat > "$CHROOT/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth" << 'EOF'
[Plymouth Theme]
Name=Lilith Text
Description=Text mode theme for Lilith Linux
ModuleName=ubuntu-text

[ubuntu-text]
title=Lilith Linux
black=0x000000
white=0xffffff
brown=0x8b2fc9
blue=0x6b3fa0
EOF
info "Replaced ubuntu-text Plymouth theme title with Lilith Linux"

# Install Lilith-blank as the default Plymouth theme (all visuals handled by mpv)
cat > "$CHROOT/etc/plymouth/plymouthd.conf" << 'EOF'
# Administrator customizations go in this file
[Daemon]
Theme=lilith-blank
ShowDelay=0
DeviceTimeout=5
EOF
info "Plymouth configured to use lilith-blank theme"

# =============================================================================
# PART 6 — Replace Ubuntu logos system-wide with Lilith official logo
# =============================================================================
step "PART 6 — Replacing Ubuntu pixmap logos with Lilith official logo"

LOGO_SRC="$OFFICIAL_LOGO"
BANNER_SRC="$BANNER"

# Replace main Ubuntu pixmap logos
for logo in \
    "$CHROOT/usr/share/pixmaps/ubuntu-logo.png" \
    "$CHROOT/usr/share/pixmaps/ubuntu-logo-text.png" \
    "$CHROOT/usr/share/pixmaps/ubuntu-logo-text-dark.png"; do
    if [[ -f "$logo" ]]; then
        SIZE=$(identify -format "%wx%h" "$logo" 2>/dev/null || echo "512x512")
        convert "$LOGO_SRC" -resize "${SIZE}!" "$logo"
        info "Replaced: $(basename "$logo")"
    fi
done

# Replace SVG ubuntu logos with a PNG fallback (SVG can't be auto-converted easily)
for svg in \
    "$CHROOT/usr/share/pixmaps/ubuntu-logo.svg" \
    "$CHROOT/usr/share/pixmaps/ubuntu-logo-text.svg" \
    "$CHROOT/usr/share/pixmaps/ubuntu-logo-text-dark.svg"; do
    if [[ -f "$svg" ]]; then
        # Back up original and overwrite with an embedded PNG in SVG wrapper
        cp "$svg" "${svg}.bak" 2>/dev/null || true
        # Create a simple SVG that references our logo concept
        cat > "$svg" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 512 512">
  <text x="256" y="300" font-size="120" text-anchor="middle" fill="#8b2fc9" font-family="sans-serif" font-weight="bold">L</text>
  <text x="256" y="420" font-size="48" text-anchor="middle" fill="#ffffff" font-family="sans-serif">LILITH</text>
</svg>
SVGEOF
        info "Replaced SVG: $(basename "$svg")"
    fi
done

# Replace the main distributor-logo-ubuntu.svg icons used by icon themes
for f in $(find "$CHROOT/usr/share/icons" -name "distributor-logo-ubuntu.svg" 2>/dev/null); do
    cp "$f" "${f}.bak" 2>/dev/null || true
    cat > "$f" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <circle cx="256" cy="256" r="240" fill="#1a0033"/>
  <text x="256" y="310" font-size="160" text-anchor="middle" fill="#8b2fc9" font-family="sans-serif" font-weight="bold">L</text>
  <text x="256" y="420" font-size="56" text-anchor="middle" fill="#e0c0ff" font-family="sans-serif" letter-spacing="8">LILITH</text>
</svg>
SVGEOF
done

# Replace ubuntu.svg / start-here-ubuntu.svg in icon themes
for f in $(find "$CHROOT/usr/share/icons" -name "ubuntu.svg" -o -name "start-here-ubuntu.svg" 2>/dev/null); do
    cp "$f" "${f}.bak" 2>/dev/null || true
    cat > "$f" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <circle cx="256" cy="256" r="240" fill="#1a0033"/>
  <text x="256" y="310" font-size="160" text-anchor="middle" fill="#8b2fc9" font-family="sans-serif" font-weight="bold">L</text>
</svg>
SVGEOF
done

info "Ubuntu logo assets replaced with Lilith branding"

# =============================================================================
# PART 7 — Install Lilith banner to replace "ubuntu" text on loading screens
# =============================================================================
step "PART 7 — Installing Lilith banner for loading screens"

# Copy the banner to standard locations for splash and greeter usage
mkdir -p "$CHROOT/usr/share/lilith/branding"
cp -v "$BANNER_SRC" "$CHROOT/usr/share/lilith/branding/lilith-banner.png"
cp -v "$LOGO_SRC"   "$CHROOT/usr/share/lilith/branding/official-logo.png"
chmod 644 "$CHROOT/usr/share/lilith/branding/"*

# For COSMIC greeter — place logo where cosmic-greeter looks for it
mkdir -p "$CHROOT/usr/share/pixmaps"
convert "$LOGO_SRC" -resize "256x256" "$CHROOT/usr/share/pixmaps/lilith-logo.png"
convert "$LOGO_SRC" -resize "256x256" "$CHROOT/usr/share/pixmaps/distributor-logo.png"

# Hack the ubuntu-text Plymouth theme to show our banner image
# The ubuntu-text module has a logo image slot — point it to our banner
mkdir -p "$CHROOT/usr/share/plymouth/themes/ubuntu-text"
# Convert banner to appropriate plymouth image (200px wide is typical)
convert "$BANNER_SRC" -resize "400x" "$CHROOT/usr/share/plymouth/themes/ubuntu-text/logo.png" 2>/dev/null || \
    convert "$LOGO_SRC" -resize "200x200" "$CHROOT/usr/share/plymouth/themes/ubuntu-text/logo.png"

info "Lilith banner and logos deployed for loading screens"

# =============================================================================
# PART 8 — System-wide spinner replacement
# =============================================================================
step "PART 8 — Installing Lilith spinner system-wide"

# The Ubuntu spinner (used by GNOME shell, gdm, etc.) is typically at:
# /usr/share/gnome-shell/theme/process-working.svg or similar
# For Plymouth spinners and Wayland compositors we install in multiple places.

SPINNER_SRC="$SPINNER"

# Install to lilith splash dir (already done above)
# Install to GNOME Shell theme directory for app startup spinners
mkdir -p "$CHROOT/usr/share/gnome-shell/theme"
cp -v "$SPINNER_SRC" "$CHROOT/usr/share/gnome-shell/theme/lilith-spinner.webm"

# Install to standard media dirs that COSMIC/GTK apps may look for
mkdir -p "$CHROOT/usr/share/lilith/animations"
cp -v "$SPINNER_SRC" "$CHROOT/usr/share/lilith/animations/spinner.webm"

# For Plymouth text-based spinner: the ubuntu-text module shows a progress bar,
# but we configure it to our blank theme so mpv handles all visuals.
# For GDM/COSMIC spinner in the greeter: patch the COSMIC greeter config.

# COSMIC greeter config — set logo
COSMIC_GREETER_CONF="$CHROOT/etc/cosmic-greeter.conf"
if [[ ! -f "$COSMIC_GREETER_CONF" ]]; then
    cat > "$COSMIC_GREETER_CONF" << 'EOF'
[greeter]
logo=/usr/share/lilith/branding/official-logo.png
banner=/usr/share/lilith/branding/lilith-banner.png
EOF
fi

# Patch /usr/share/gnome-shell/extensions or similar spinner assets if present
for spinnerfile in \
    "$CHROOT/usr/share/gnome-shell/theme/process-working.svg" \
    "$CHROOT/usr/share/gnome-shell/theme/spinner.svg"; do
    if [[ -f "$spinnerfile" ]]; then
        cp "$spinnerfile" "${spinnerfile}.bak" 2>/dev/null || true
        # Replace spinner SVG with a link to our Lilith sigil concept
        cat > "$spinnerfile" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <circle cx="32" cy="32" r="28" fill="none" stroke="#8b2fc9" stroke-width="4" stroke-dasharray="44 132">
    <animateTransform attributeName="transform" type="rotate" from="0 32 32" to="360 32 32" dur="1s" repeatCount="indefinite"/>
  </circle>
  <circle cx="32" cy="32" r="16" fill="none" stroke="#6b3fa0" stroke-width="3" stroke-dasharray="25 75">
    <animateTransform attributeName="transform" type="rotate" from="360 32 32" to="0 32 32" dur="0.8s" repeatCount="indefinite"/>
  </circle>
</svg>
SVGEOF
        info "Replaced spinner SVG: $(basename "$spinnerfile")"
    fi
done

info "Spinner assets installed"

# =============================================================================
# PART 9 — s8n .desktop entry
# =============================================================================
step "PART 9 — Installing s8n desktop entry"

cat > "$CHROOT/usr/share/applications/s8n.desktop" << 'EOF'
[Desktop Entry]
Name=S8n System
GenericName=Package Manager
Comment=S8n — Lilith Linux system package manager CLI
Exec=s8n %U
Icon=system-software-install
Type=Application
Categories=System;PackageManager;
Keywords=s8n;package;manager;install;lilith;system;
Terminal=true
EOF
chmod 644 "$CHROOT/usr/share/applications/s8n.desktop"
info "s8n.desktop installed"

# =============================================================================
# PART 10 — Rebuild initramfs and update GRUB
# =============================================================================
step "PART 10 — Rebuilding initramfs (this takes a while...)"

chroot "$CHROOT" /bin/bash << CHROOTEOF
export DEBIAN_FRONTEND=noninteractive

# Re-confirm Plymouth theme
echo ">>> Setting Plymouth theme to lilith-blank..."
update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
    default.plymouth \
    /usr/share/plymouth/themes/lilith-blank/lilith-blank.plymouth \
    100 2>/dev/null || true
plymouth-set-default-theme -R lilith-blank 2>/dev/null || \
    update-alternatives --set default.plymouth \
    /usr/share/plymouth/themes/lilith-blank/lilith-blank.plymouth 2>/dev/null || true

echo ">>> Rebuilding initramfs for kernel: $KERNEL_VERSION"
update-initramfs -u -k "$KERNEL_VERSION" 2>&1

echo ">>> Updating GRUB..."
update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg 2>&1 || true
echo ">>> Done."
CHROOTEOF
info "Initramfs and GRUB updated"

# =============================================================================
# SUMMARY
# =============================================================================
step "=== COMPLETE — Final Verification ==="

echo ""
echo "=== Splash Videos ==="
ls -lh "$CHROOT/usr/share/lilith/splash/"

echo ""
echo "=== Splash Scripts ==="
ls -la "$CHROOT/usr/local/bin/lilith-boot-splash.sh" \
        "$CHROOT/usr/local/bin/lilith-presplash.sh"

echo ""
echo "=== Systemd Services Enabled ==="
ls -la "$CHROOT/etc/systemd/system/sysinit.target.wants/lilith-boot-splash.service" 2>/dev/null || echo "  ✘ boot-splash NOT enabled"
ls -la "$CHROOT/etc/systemd/system/display-manager.service.wants/lilith-presplash.service" 2>/dev/null || echo "  ✘ presplash NOT enabled"

echo ""
echo "=== Plymouth Theme ==="
cat "$CHROOT/etc/plymouth/plymouthd.conf"

echo ""
echo "=== Branding Assets ==="
ls -lh "$CHROOT/usr/share/lilith/branding/"

echo ""
echo "=== mpv ==="
ls "$CHROOT/usr/bin/mpv" 2>/dev/null && echo "  ✔ mpv installed" || echo "  ✘ mpv MISSING"

echo ""
echo "=== Key Desktop Files ==="
for f in bat.desktop fd.desktop s8n.desktop lilim.desktop hyper.desktop shapeshifter.desktop; do
    ls "$CHROOT/usr/share/applications/$f" 2>/dev/null && echo "  ✔ $f" || echo "  ✘ $f — missing"
done

echo ""
echo -e "${GREEN}Lilith Linux splash and branding configuration complete!${NC}"
echo ""
echo "Boot sequence:"
echo "  1. GRUB (hidden, 0s timeout)"
echo "  2. Kernel loads silently (loglevel=0)"
echo "  3. Plymouth: black blank screen (lilith-blank theme)"
echo "  4. lilith-boot-splash.service → lilith-burn-loading.mp4 loops via DRM"
echo "  5. lilith-presplash.service → splash-canon.mp4 plays in FULL before greeter"
echo "  6. cosmic-greeter appears with Lilith branding"
echo ""
echo "  Next step: Open Cubic and generate the ISO!"
