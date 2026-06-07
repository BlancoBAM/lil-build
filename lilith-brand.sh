#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — Branding Script
# =============================================================================
# Applies all Lilith branding to the chroot at ~/Lilith/custom-root:
#   1. Plymouth logo + theme branding
#   2. SDDM custom Lilith theme
#   3. COSMIC desktop defaults (wallpaper, accent color, icons)
#   4. Font installation (/usr/share/fonts/Lilith/)
#   5. Cursor installation (/usr/share/icons/Lilith/)
#   6. Ubuntu pixmap/logo replacement
#   7. Calamares install + Lilith branding
#
# Run from host as root after pre-build-host.sh:
#   sudo bash /home/aegon/lil-build/lilith-brand.sh [--dry-run]
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROOT="/home/aegon/Lilith/custom-root"
LIL_BUILD="$SCRIPT_DIR"
ASSETS="$LIL_BUILD/assets"
BRAND_ASSETS_DIR="$LIL_BUILD/branding-assets"

# Brand asset sources
OFFICIAL_LOGO="/home/aegon/Downloads/off-lil.png"
BANNER="/home/aegon/Downloads/lilith-banner-nobg.png"
ALT_LOGO="/home/aegon/Downloads/lil-logo7.png"
SPINNER_MP4="/home/aegon/Downloads/lil-spinner.mp4"
FONT_ZIP="/home/aegon/lilith-font-collection.zip"
CURSORS_DIR="/home/aegon/lil-curses"
WALLPAPERS_DIR="$ASSETS/wallpapers"
SDDM_THEME_DIR="$LIL_BUILD/sddm-theme/lilith"
CAL_BRAND_DIR="$LIL_BUILD/calamares-branding/lilith"

LOG_FILE="$LIL_BUILD/brand-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✔]${NC} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
err()   { echo -e "${RED}[✘]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
step()  { echo -e "\n${BLUE}══════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
          echo -e "${BLUE}  $*${NC}" | tee -a "$LOG_FILE"
          echo -e "${BLUE}══════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"; }
note()  { echo -e "${CYAN}  →${NC} $*" | tee -a "$LOG_FILE"; }

: > "$LOG_FILE"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
step "Pre-flight checks"
[[ $EUID -eq 0 ]] || err "Must be run as root: sudo bash $0"
[[ -d "$CHROOT" ]] || err "Chroot not found at $CHROOT"
[[ -f "$OFFICIAL_LOGO" ]] || err "Official logo not found: $OFFICIAL_LOGO"
[[ -f "$BANNER" ]] || err "Banner not found: $BANNER"
[[ -f "$FONT_ZIP" ]] || err "Font zip not found: $FONT_ZIP"
[[ -d "$CURSORS_DIR" ]] || err "Cursors dir not found: $CURSORS_DIR"
info "All asset checks passed"

$DRY_RUN && note "DRY-RUN MODE: No files will be modified"

# ── Helpers ───────────────────────────────────────────────────────────────────
chr() {
    # Run a command inside the chroot
    chroot "$CHROOT" /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive "$@"
}

cp_brand() {
    local src="$1" dst_in_chroot="$2"
    local dst="$CHROOT/$dst_in_chroot"
    if $DRY_RUN; then
        note "[DRY-RUN] cp $src → $dst"
        return
    fi
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    info "Copied: $src → $dst_in_chroot"
}

# ── Mount pseudo-filesystems ──────────────────────────────────────────────────
step "Mounting pseudo-filesystems"
for fs in proc sys dev dev/pts run; do
    mount --bind "/$fs" "$CHROOT/$fs" 2>/dev/null && note "mounted: $fs" || note "already mounted: $fs"
done

# Suppress service starts during chroot ops
cat > "$CHROOT/usr/sbin/policy-rc.d" << 'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

cleanup() {
    step "Cleanup"
    rm -f "$CHROOT/usr/sbin/policy-rc.d" 2>/dev/null || true
    for fs in run dev/pts dev sys proc; do
        umount -lf "$CHROOT/$fs" 2>/dev/null || true
    done
    info "Unmounted pseudo-filesystems"
}
trap cleanup EXIT

# =============================================================================
# STEP 1 — Plymouth Branding
# =============================================================================
step "STEP 1 — Plymouth Branding"

# Replace all ubuntu logo PNGs in plymouth themes
PLYMOUTH_DIR="$CHROOT/usr/share/plymouth/themes"
if [[ -d "$PLYMOUTH_DIR" ]]; then
    # Find all logo.png or ubuntu-logo.png variants
    while IFS= read -r -d '' logo_file; do
        rel_path="${logo_file#$CHROOT}"
        note "Replacing Plymouth logo: $rel_path"
        $DRY_RUN || cp -f "$OFFICIAL_LOGO" "$logo_file"
    done < <(find "$PLYMOUTH_DIR" \( -name "logo.png" -o -name "ubuntu-logo.png" -o -name "*ubuntu*logo*.png" \) -print0 2>/dev/null)
    info "Plymouth logos replaced"
else
    warn "Plymouth themes directory not found, skipping"
fi

# Replace plymouth ubuntu-text theme's branding
UBUNTU_TEXT_SCRIPT="$CHROOT/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.script"
if [[ -f "$UBUNTU_TEXT_SCRIPT" ]]; then
    $DRY_RUN || sed -i \
        -e 's/Ubuntu/Lilith Linux/g' \
        -e 's/ubuntu/lilith/g' \
        "$UBUNTU_TEXT_SCRIPT"
    info "Plymouth ubuntu-text script updated"
fi

# Install spinner video (convert MP4 to webm for mpv)
if [[ -f "$SPINNER_MP4" ]]; then
    SPINNER_WEBM="$CHROOT/usr/share/lilith/lilith-spinner.webm"
    note "Converting spinner MP4 → webm"
    if ! $DRY_RUN; then
        mkdir -p "$CHROOT/usr/share/lilith"
        if command -v ffmpeg &>/dev/null; then
            ffmpeg -y -i "$SPINNER_MP4" -c:v libvpx-vp9 -b:v 0 -crf 30 -an "$SPINNER_WEBM" 2>/dev/null \
                && info "Spinner converted: $SPINNER_WEBM" \
                || { warn "ffmpeg conversion failed, copying MP4 as-is"; cp -f "$SPINNER_MP4" "$CHROOT/usr/share/lilith/lilith-spinner.mp4"; }
        else
            warn "ffmpeg not found, copying MP4 as-is"
            cp -f "$SPINNER_MP4" "$CHROOT/usr/share/lilith/lilith-spinner.mp4"
        fi
    fi
fi

# =============================================================================
# STEP 2 — Ubuntu Pixmap Logo Replacement
# =============================================================================
step "STEP 2 — Ubuntu Pixmap Logo Replacement"

PIXMAPS="$CHROOT/usr/share/pixmaps"
if [[ -d "$PIXMAPS" ]]; then
    while IFS= read -r -d '' pix_file; do
        rel_path="${pix_file#$CHROOT}"
        fname=$(basename "$pix_file")
        # Use banner for text-variant logos, official for small square logos
        if echo "$fname" | grep -qi "text\|wordmark\|banner\|wide"; then
            $DRY_RUN || cp -f "$BANNER" "$pix_file"
        else
            $DRY_RUN || cp -f "$OFFICIAL_LOGO" "$pix_file"
        fi
        note "Replaced pixmap: $rel_path"
    done < <(find "$PIXMAPS" \( -name "*ubuntu*" -o -name "*Ubuntu*" \) -name "*.png" -print0 2>/dev/null)
    info "Pixmap logos replaced"
fi

# Replace distributor-logo
for logo_path in \
    "$CHROOT/usr/share/icons/hicolor/256x256/apps/distributor-logo.png" \
    "$CHROOT/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg" \
    "$CHROOT/usr/share/icons/hicolor/48x48/apps/distributor-logo.png"; do
    if [[ -f "$logo_path" ]]; then
        $DRY_RUN || cp -f "$OFFICIAL_LOGO" "${logo_path%.svg}.png" 2>/dev/null || true
        note "Replaced: ${logo_path#$CHROOT}"
    fi
done

# =============================================================================
# STEP 3 — Wallpaper Setup
# =============================================================================
step "STEP 3 — Wallpaper Setup"

if ! $DRY_RUN; then
    mkdir -p "$CHROOT/usr/share/backgrounds/lilith"
fi

# Copy all wallpapers from assets
if [[ -d "$WALLPAPERS_DIR" ]]; then
    $DRY_RUN || cp -r "$WALLPAPERS_DIR"/. "$CHROOT/usr/share/backgrounds/lilith/"
    info "Wallpapers copied to chroot"
fi

# Set a default wallpaper symlink
DEFAULT_WALLPAPER="$CHROOT/usr/share/backgrounds/lilith/default.png"
if ! $DRY_RUN; then
    # Find first jpg/png as default if not already set
    if [[ ! -f "$DEFAULT_WALLPAPER" ]]; then
        first_wp=$(find "$CHROOT/usr/share/backgrounds/lilith" -maxdepth 1 \( -name "*.jpg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null | head -1)
        [[ -n "$first_wp" ]] && cp -f "$first_wp" "$DEFAULT_WALLPAPER" && info "Default wallpaper set: $(basename $first_wp)"
    fi
fi

# =============================================================================
# STEP 4 — COSMIC Desktop Defaults
# =============================================================================
step "STEP 4 — COSMIC Desktop Defaults"

COSMIC_CONF="$CHROOT/etc/cosmic"
if ! $DRY_RUN; then
    mkdir -p "$COSMIC_CONF" || true
fi

# COSMIC theme config via ron files (System76 COSMIC uses RON format)
# Set dark mode and flame accent color for all new users via /etc/skel
SKEL_COSMIC="$CHROOT/etc/skel/.config/cosmic"
if ! $DRY_RUN; then
    mkdir -p "$SKEL_COSMIC/com.system76.CosmicTheme.Dark/v1" || true
    mkdir -p "$SKEL_COSMIC/com.system76.CosmicBackground/v1" || true
    mkdir -p "$SKEL_COSMIC/com.system76.CosmicTk/v1" || true

    # Accent color: flame red (#E74C3C → RGB 231, 76, 60)
    {
    cat > "$SKEL_COSMIC/com.system76.CosmicTheme.Dark/v1/accent" << 'RONEOF'
(
    red: 0.906,
    green: 0.298,
    blue: 0.235,
    alpha: 1.0,
)
RONEOF
    } || warn "Could not write CosmicTheme accent"

    # Background wallpaper
    {
    cat > "$SKEL_COSMIC/com.system76.CosmicBackground/v1/entry" << 'RONEOF'
(
    wallpaper_path: "/usr/share/backgrounds/lilith/default.png",
    scaling_mode: Zoom,
    sampling_filter: Lanczos,
    output: "all",
)
RONEOF
    } || warn "Could not write CosmicBackground entry"

    # Force dark mode
    {
    cat > "$SKEL_COSMIC/com.system76.CosmicTk/v1/is_dark" << 'RONEOF'
(true)
RONEOF
    } || warn "Could not write CosmicTk is_dark"

    info "COSMIC dark mode + flame accent configured via /etc/skel"
fi

# Also set Fluent-dark icon theme via dconf profile
SKEL_DCONF="$CHROOT/etc/skel/.config"
if ! $DRY_RUN; then
    mkdir -p "$SKEL_DCONF/dconf" || true
    # Ensure dconf profile dir exists before writing
    mkdir -p "$CHROOT/etc/dconf/profile" || true
    {
    cat > "/tmp/lilith-dconf-profile" << 'EOF'
user-db:user
system-db:local
EOF
    cp "/tmp/lilith-dconf-profile" "$CHROOT/etc/dconf/profile/user" 2>/dev/null
    } || warn "dconf profile write skipped (dir may not exist in chroot yet)"
fi

# =============================================================================
# STEP 5 — SDDM Theme
# =============================================================================
step "STEP 5 — SDDM Theme Installation"

SDDM_THEMES="$CHROOT/usr/share/sddm/themes"
SDDM_DEST="$SDDM_THEMES/lilith"

if [[ -d "$SDDM_THEME_DIR" ]]; then
    if ! $DRY_RUN; then
        mkdir -p "$SDDM_DEST"
        cp -r "$SDDM_THEME_DIR"/. "$SDDM_DEST/"
        # Copy banner into theme
        cp -f "$BANNER" "$SDDM_DEST/banner.png" 2>/dev/null || true
        cp -f "$OFFICIAL_LOGO" "$SDDM_DEST/logo.png" 2>/dev/null || true
    fi
    info "SDDM Lilith theme installed"
else
    warn "SDDM theme source not found: $SDDM_THEME_DIR"
fi

# Configure SDDM to use Lilith theme
SDDM_CONF="$CHROOT/etc/sddm.conf.d"
if ! $DRY_RUN; then
    mkdir -p "$SDDM_CONF"
    cat > "$SDDM_CONF/lilith.conf" << 'EOF'
[Theme]
Current=lilith

[Autologin]
Relogin=false

[General]
Numlock=none

[Wayland]
EnableHiDPI=true
EOF
    info "SDDM configured to use Lilith theme"
fi

# =============================================================================
# STEP 6 — Font Installation
# =============================================================================
step "STEP 6 — Font Installation"

FONTS_DEST="$CHROOT/usr/share/fonts/Lilith"
FONT_TMP="/tmp/lilith-fonts-extract"

if ! $DRY_RUN; then
    mkdir -p "$FONTS_DEST"
    rm -rf "$FONT_TMP" || true
    mkdir -p "$FONT_TMP"

    note "Extracting font collection..."
    unzip -q "$FONT_ZIP" -d "$FONT_TMP" || { warn "Font zip extraction failed: $FONT_ZIP"; }

    # Copy all font files (TTF/OTF) to the Lilith fonts directory
    find "$FONT_TMP" \( -name "*.ttf" -o -name "*.otf" -o -name "*.woff" -o -name "*.woff2" \) | while read -r font_file; do
        cp -f "$font_file" "$FONTS_DEST/" && note "  Font: $(basename "$font_file")" || true
    done

    # Also install NerdFonts symbols if present
    NERDFONT_ZIP="/home/aegon/Downloads/NerdFontsSymbolsOnly.zip"
    if [[ -f "$NERDFONT_ZIP" ]]; then
        unzip -q "$NERDFONT_ZIP" -d "$FONT_TMP/nerd" || true
        find "$FONT_TMP/nerd" \( -name "*.ttf" -o -name "*.otf" \) -exec cp -f {} "$FONTS_DEST/" \;
        info "NerdFonts Symbols Only installed"
    fi

    # Update font cache inside chroot
    note "Running fc-cache inside chroot..."
    chr fc-cache -f /usr/share/fonts/Lilith && info "Font cache updated" || warn "fc-cache skipped (may not be available in chroot yet)"

    rm -rf "$FONT_TMP" || true
else
    note "[DRY-RUN] Would extract $FONT_ZIP → $FONTS_DEST"
fi

# =============================================================================
# STEP 7 — Cursor Installation
# =============================================================================
step "STEP 7 — Cursor Installation"

CURSORS_DEST="$CHROOT/usr/share/icons/Lilith"
CURSOR_TMP="/tmp/lilith-cursor-extract"

if ! $DRY_RUN; then
    mkdir -p "$CURSORS_DEST"
    # Create index.theme for the Lilith cursor collection directory
    cat > "$CURSORS_DEST/index.theme" << 'EOF'
[Icon Theme]
Name=Lilith
Comment=Lilith Linux Custom Cursor Collection
Directories=cursors

[cursors]
Context=Cursors
Type=Cursor
EOF

    # Sub-directory for Windows cursor reference files
    mkdir -p "$CURSORS_DEST/windows-cursors"
    mkdir -p "$CURSORS_DEST/xcursor-themes"
fi

note "Processing cursor sets from $CURSORS_DIR"
cursor_count=0

while IFS= read -r -d '' cursor_file; do
    fname=$(basename "$cursor_file")
    ext="${fname##*.}"

    if [[ "$ext" == "zip" ]]; then
        # Extract zip and check for xcursor structure
        rm -rf "$CURSOR_TMP" && mkdir -p "$CURSOR_TMP"
        unzip -q "$cursor_file" -d "$CURSOR_TMP" 2>/dev/null || { warn "Failed to extract: $fname"; continue; }

        # Get clean theme name from zip (strip extension)
        theme_name="${fname%.zip}"
        # Sanitize: replace & with and, strip special chars
        theme_name=$(echo "$theme_name" | sed 's/ & / and /g; s/[^a-zA-Z0-9 _-]//g; s/  */ /g; s/^ *//; s/ *$//')
        theme_name_clean=$(echo "$theme_name" | tr ' ' '-')

        # Check if extracted zip has a 'cursors' subfolder (XCursor format)
        xcursor_dir=$(find "$CURSOR_TMP" -type d -name "cursors" 2>/dev/null | head -1)
        if [[ -n "$xcursor_dir" ]]; then
            # Has XCursor format — install as proper theme
            theme_parent=$(dirname "$xcursor_dir")
            if ! $DRY_RUN; then
                dest_theme="$CURSORS_DEST/xcursor-themes/$theme_name_clean"
                mkdir -p "$dest_theme"
                cp -r "$theme_parent/." "$dest_theme/"
                note "XCursor theme: $theme_name_clean"
            fi
        else
            # No XCursor structure — store raw files for reference
            if ! $DRY_RUN; then
                dest_ref="$CURSORS_DEST/windows-cursors/$theme_name_clean"
                mkdir -p "$dest_ref"
                find "$CURSOR_TMP" \( -name "*.cur" -o -name "*.ani" \) -exec cp -f {} "$dest_ref/" \;
            fi
            note "Windows cursor (ref): $theme_name_clean"
        fi
        ((cursor_count++)) || true

    elif [[ "$ext" == "cur" ]] || [[ "$ext" == "ani" ]]; then
        # Raw .cur/.ani files — store in windows-cursors
        if ! $DRY_RUN; then
            cp -f "$cursor_file" "$CURSORS_DEST/windows-cursors/"
        fi
        note "Windows cursor file: $fname"
        ((cursor_count++)) || true
    fi

done < <(find "$CURSORS_DIR" -maxdepth 1 \( -name "*.zip" -o -name "*.cur" -o -name "*.ani" \) -print0 2>/dev/null)

$DRY_RUN || rm -rf "$CURSOR_TMP"
info "Processed $cursor_count cursor sets → $CURSORS_DEST"

# =============================================================================
# STEP 8 — Calamares Installation + Branding
# =============================================================================
step "STEP 8 — Calamares Installation + Branding"

if ! $DRY_RUN; then
    # Install Calamares inside chroot
    note "Installing Calamares inside chroot..."
    chr apt-get update -qq 2>/dev/null || warn "apt-get update had warnings"
    chr apt-get install -y --no-install-recommends \
        calamares \
        calamares-settings-ubuntu \
        qml-module-qtquick2 \
        qml-module-qtquick-layouts \
        qml-module-qtquick-controls2 \
        2>/dev/null && info "Calamares installed" || warn "Calamares install had errors (may already be installed)"
fi

# Install Lilith Calamares branding
CAL_DEST="$CHROOT/usr/share/calamares/branding/lilith"
if [[ -d "$CAL_BRAND_DIR" ]]; then
    if ! $DRY_RUN; then
        mkdir -p "$CAL_DEST"
        cp -r "$CAL_BRAND_DIR"/. "$CAL_DEST/"
        cp -f "$OFFICIAL_LOGO" "$CAL_DEST/logo.png" 2>/dev/null || true
        cp -f "$BANNER" "$CAL_DEST/banner.png" 2>/dev/null || true
    fi
    info "Calamares Lilith branding installed"
else
    warn "Calamares branding source not found: $CAL_BRAND_DIR"
fi

# Configure Calamares to use Lilith branding
CAL_CONF="$CHROOT/etc/calamares"
if ! $DRY_RUN; then
    mkdir -p "$CAL_CONF"
    cat > "$CAL_CONF/settings.conf" << 'CALEOF'
---
# Calamares settings — Lilith Linux
modules-search: [ local, /usr/lib/calamares/modules ]

instances: []

sequence:
  - show:
    - welcome
    - locale
    - keyboard
    - partition
    - users
    - summary
  - exec:
    - partition
    - mount
    - unpackfs
    - machineid
    - fstab
    - locale
    - keyboard
    - localecfg
    - users
    - displaymanager
    - networkcfg
    - hwclock
    - services-systemd
    - grubcfg
    - bootloader
    - packages
    - umount
  - show:
    - finished

branding: lilith
prompt-install: false
dont-chroot: false
CALEOF
    info "Calamares settings.conf configured"
fi

# =============================================================================
# STEP 9 — Initramfs Rebuild
# =============================================================================
step "STEP 9 — Rebuilding initramfs"

if ! $DRY_RUN; then
    KERNEL_VER=$(ls "$CHROOT/boot/" 2>/dev/null | grep "vmlinuz-" | sed 's/vmlinuz-//' | sort -V | tail -1)
    if [[ -n "$KERNEL_VER" ]]; then
        note "Kernel version: $KERNEL_VER"
        chr update-initramfs -u -k "$KERNEL_VER" && info "initramfs rebuilt" || warn "initramfs rebuild had warnings (non-fatal)"
    else
        warn "Could not detect kernel version, skipping initramfs rebuild"
    fi
fi

# =============================================================================
# DONE
# =============================================================================
step "Branding Complete"
info "All Lilith branding applied to chroot at $CHROOT"
info "Log: $LOG_FILE"
echo -e "\n${GREEN}✔ Ready to re-open in Cubic and rebuild ISO${NC}"
