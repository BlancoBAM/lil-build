#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — System Customization and Configuration Script
# =============================================================================
# Run this from outside the chroot as root/sudo:
#
#   sudo bash /home/aegon/Lilith/configure-lilith-os.sh
#
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
CHROOT="/home/aegon/Lilith/custom-root"
LIL_BUILD="/home/aegon/lil-build"
ASSETS="$LIL_BUILD/assets"
WALLPAPERS="$ASSETS/wallpapers"
RANDOM_PHOTOS="$ASSETS/random"
CUSTICONS="$ASSETS/lil-custicons"

# ── Helpers ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
err()     { echo -e "${RED}[✘]${NC} $*"; exit 1; }
step()    { echo -e "\n${BLUE}══${NC} $* ${BLUE}══${NC}"; }

# ── Pre-flight checks ──────────────────────────────────────────────────────────
step "Pre-flight checks"
[[ $EUID -eq 0 ]] || err "Must be run as root. Use: sudo bash $0"
[[ -d "$CHROOT" ]] || err "Chroot not found at $CHROOT"
[[ -d "$LIL_BUILD" ]] || err "lil-build directory not found"
[[ -d "$WALLPAPERS" ]] || err "Wallpapers directory not found"

# ── Mount pseudo-filesystems ───────────────────────────────────────────────────
step "Mounting pseudo-filesystems"
mount --bind /proc  "$CHROOT/proc"  || true
mount --bind /sys   "$CHROOT/sys"   || true
mount --bind /dev   "$CHROOT/dev"   || true
mount --bind /dev/pts "$CHROOT/dev/pts" || true
mount --bind /run   "$CHROOT/run"   || true
info "Pseudo-filesystems mounted"

# Cleanup function — always unmount on exit
cleanup() {
    step "Unmounting pseudo-filesystems"
    umount -lf "$CHROOT/run"     2>/dev/null || true
    umount -lf "$CHROOT/dev/pts" 2>/dev/null || true
    umount -lf "$CHROOT/dev"     2>/dev/null || true
    umount -lf "$CHROOT/sys"     2>/dev/null || true
    umount -lf "$CHROOT/proc"    2>/dev/null || true
    info "Cleanup complete."
}
trap cleanup EXIT

# ── Deploys Wallpapers, Custom Icons and Pictures ──────────────────────────────
step "Deploying Wallpapers, Icons, and Photos"

# 1. System backgrounds directory
mkdir -p "$CHROOT/usr/share/backgrounds/lilith"
cp -v "$WALLPAPERS"/* "$CHROOT/usr/share/backgrounds/lilith/" 2>/dev/null || true
cp -v "$ASSETS/official-logo.png" "$CHROOT/usr/share/backgrounds/lilith/" || true
# Ensure default.jpg exists
if [[ -f "$WALLPAPERS/lil-wall.jpg" ]]; then
    cp -v "$WALLPAPERS/lil-wall.jpg" "$CHROOT/usr/share/backgrounds/lilith/default.jpg"
fi
chmod -R 644 "$CHROOT/usr/share/backgrounds/lilith"/*
info "System wallpapers installed to /usr/share/backgrounds/lilith/"

# 2. Skel Pictures directory (for new users)
PICTURES_DIR="$CHROOT/etc/skel/Pictures"
mkdir -p "$PICTURES_DIR/wallpapers"
mkdir -p "$PICTURES_DIR/lilith-photos"
cp -v "$WALLPAPERS"/* "$PICTURES_DIR/wallpapers/" 2>/dev/null || true
cp -v "$ASSETS/official-logo.png" "$PICTURES_DIR/wallpapers/" || true
cp -v "$RANDOM_PHOTOS"/* "$PICTURES_DIR/lilith-photos/" 2>/dev/null || true
cp -r "$CUSTICONS" "$PICTURES_DIR/lil-custicons"
chmod -R 755 "$PICTURES_DIR"
info "Wallpapers, photos, and custom icons placed in user skel /etc/skel/Pictures/"

# 3. System custom icons theme
mkdir -p "$CHROOT/usr/share/icons"
cp -r "$CUSTICONS" "$CHROOT/usr/share/icons/lil-custicons"
chmod -R 755 "$CHROOT/usr/share/icons/lil-custicons"
info "Custom icons copied to /usr/share/icons/lil-custicons"

# ── Hyper Terminal Configuration ──────────────────────────────────────────────
step "Configuring Hyper Terminal Default Settings"
mkdir -p "$CHROOT/etc/skel/.hyper"
cp -r /home/aegon/hyper_backup/* "$CHROOT/etc/skel/.hyper/" 2>/dev/null || true
cp -v /home/aegon/hyper_setup_backup.js "$CHROOT/etc/skel/.hyper.js"
chmod -R 755 "$CHROOT/etc/skel/.hyper" || true
chmod 644 "$CHROOT/etc/skel/.hyper.js"
info "Hyper Terminal presets written to user skel /etc/skel/"

# ── uutils-wrapper.sh configuration ──────────────────────────────────────────
step "Configuring uutils coreutils wrapper"
cp -v "$LIL_BUILD/uutils-wrapper.sh" "$CHROOT/usr/local/bin/uutils-wrapper.sh"
chmod 755 "$CHROOT/usr/local/bin/uutils-wrapper.sh"

# Create symlinks for each command in UTILS_MAP
# ls, cat, dd, df, du, echo, env, false, groups, hostid, hostname, id, link, ln, mkdir, mknod, mv, nohup, pwd, rm, rmdir, sleep, sort, stat, sync, touch, true, uname, uniq, wc, whoami, cp, chmod, chown
commands=(
    ls cat dd df du echo env false groups hostid hostname id link ln mkdir mknod mv nohup pwd rm rmdir sleep sort stat sync touch true uname uniq wc whoami cp chmod chown
)
for cmd in "${commands[@]}"; do
    ln -sf /usr/local/bin/uutils-wrapper.sh "$CHROOT/usr/local/bin/$cmd"
done
info "Seamless fallback wrapper symlinks created in /usr/local/bin/"

# ── Starship Flame Prompt configuration ────────────────────────────────────────
step "Pre-configuring Starship Flame Prompt"
cp -v "$LIL_BUILD/install_flame_font.sh" "$CHROOT/tmp/install_flame_font.sh"
chmod +x "$CHROOT/tmp/install_flame_font.sh"

# We run this inside the chroot, targeting /etc/skel as HOME so it preconfigures it
chroot "$CHROOT" /bin/bash -c "
export HOME=/etc/skel
export USER=root
/tmp/install_flame_font.sh || true
"
rm -f "$CHROOT/tmp/install_flame_font.sh"
info "Starship flame prompt and FiraCode Nerd Font pre-installed"

# ── COSMIC Desktop & Greeter Installation ─────────────────────────────────────
step "Entering Chroot to Install COSMIC Desktop, cosmic-greeter and themes"

chroot "$CHROOT" /bin/bash -c "
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l

echo '>>> Adding cosmic-epoch PPA...'
apt-get install -y software-properties-common
add-apt-repository -y ppa:hepp3n/cosmic-epoch

echo '>>> Updating package cache...'
apt-get update -qq

echo '>>> Installing cosmic-desktop and cosmic-greeter...'
apt-get install -y cosmic-desktop cosmic-greeter lightdm git --no-install-recommends

echo '>>> Cloninng cosmic-uniform-glass-theme...'
cd /tmp
rm -rf cosmic-uniform-glass-theme
git clone https://github.com/xarbit/cosmic-uniform-glass-theme.git
mkdir -p /usr/share/cosmic/themes
cp -r cosmic-uniform-glass-theme /usr/share/cosmic/themes/
"

# Configure lightdm / greetd default greeter to cosmic-greeter
step "Configuring Default Desktop Session & Greeter"
mkdir -p "$CHROOT/etc/lightdm/lightdm.conf.d"
cat > "$CHROOT/etc/lightdm/lightdm.conf.d/50-lilith-cosmic.conf" << 'EOF'
[Seat:*]
greeter-session=cosmic-greeter
user-session=cosmic
EOF

# Pre-configure COSMIC Frosted Glass Theme settings in SKEL
COSMIC_THEME_DIR="$CHROOT/etc/skel/.config/cosmic"
mkdir -p "$COSMIC_THEME_DIR"
cat > "$COSMIC_THEME_DIR/theme.toml" << 'EOF'
[theme]
gtk_theme = "Fluent-dark"
icon_theme = "Fluent-dark"
cursor_theme = "breeze_cursors"

[colors]
scheme = "dark"
accent = "#7C3AED"
background = "#1E1E1E"
surface = "#2D2D2D"

[desktop.cosmic]
dark_mode = true
background = "/usr/share/backgrounds/lilith/default.jpg"
show_desktop_icons = false
EOF

info "COSMIC session configured to use cosmic-greeter with Frosted Glass Theme"

step "Lilith OS Customization Complete!"
echo -e "${GREEN}Lilith Linux target system configuration successfully applied to the chroot!${NC}\n"
