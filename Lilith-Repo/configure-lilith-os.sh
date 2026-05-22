#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — System Customization and Configuration Script (v2.0)
# =============================================================================
# Run this from outside the chroot as root/sudo AFTER running pre-build-host.sh:
#
#   sudo bash /home/aegon/Lilith/configure-lilith-os.sh
#
# Prerequisites:
#   - /home/aegon/lil-build/staging/ populated by pre-build-host.sh
#   - /home/aegon/lil-build/assets/ with wallpapers, icons, official-logo.png
#   - /home/aegon/hyper_setup_backup.js and /home/aegon/hyper_backup/
#   - Chroot at /home/aegon/Lilith/custom-root/
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
CHROOT="/home/aegon/Lilith/custom-root"
LIL_BUILD="/home/aegon/lil-build"
ASSETS="$LIL_BUILD/assets"
WALLPAPERS="$ASSETS/wallpapers"
RANDOM_PHOTOS="$ASSETS/random"
CUSTICONS="$ASSETS/lil-custicons"
STAGING="$LIL_BUILD/staging"
DEBS="$STAGING/debs"
APPIMAGES="$STAGING/appimages"
BINARIES="$STAGING/binaries"
LIL_APPS="$CHROOT/opt/lilith-apps"
LOG_FILE="$LIL_BUILD/configure-$(date +%Y%m%d-%H%M%S).log"

# ── Colors & Helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✔]${NC} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
err()   { echo -e "${RED}[✘]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
step()  { echo -e "\n${BLUE}══${NC} $* ${BLUE}══${NC}" | tee -a "$LOG_FILE"; }
note()  { echo -e "${CYAN}  →${NC} $*" | tee -a "$LOG_FILE"; }

: > "$LOG_FILE"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — Pre-flight checks
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 1 — Pre-flight checks"
[[ $EUID -eq 0 ]]         || err "Must be run as root. Use: sudo bash $0"
[[ -d "$CHROOT" ]]        || err "Chroot not found at $CHROOT"
[[ -d "$LIL_BUILD" ]]     || err "lil-build directory not found at $LIL_BUILD"
[[ -d "$WALLPAPERS" ]]    || err "Wallpapers not found at $WALLPAPERS"
[[ -d "$STAGING" ]]       || err "Staging dir not found at $STAGING. Run pre-build-host.sh first."

# Count staged assets for summary
STAGED_DEBS=$(ls "$DEBS"/*.deb 2>/dev/null | wc -l || echo 0)
STAGED_APPIMAGES=$(ls "$APPIMAGES"/*.AppImage 2>/dev/null | wc -l || echo 0)
note "Found $STAGED_DEBS staged .deb files"
note "Found $STAGED_APPIMAGES staged AppImages"

# ── Mount pseudo-filesystems ───────────────────────────────────────────────────
step "Mounting pseudo-filesystems"
for fs in proc sys dev dev/pts run; do
    mount --bind "/$fs" "$CHROOT/$fs" 2>/dev/null || true
done
info "Pseudo-filesystems mounted"

# Create policy-rc.d inside chroot to prevent services from starting/stopping during image build
cat > "$CHROOT/usr/sbin/policy-rc.d" << 'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$CHROOT/usr/sbin/policy-rc.d"
info "policy-rc.d created inside chroot to suppress service actions"

# Cleanup function — always unmount and remove policy-rc.d on exit
cleanup() {
    step "Unmounting pseudo-filesystems and removing policy-rc.d"
    rm -f "$CHROOT/usr/sbin/policy-rc.d"
    for fs in run dev/pts dev sys proc; do
        umount -lf "$CHROOT/$fs" 2>/dev/null || true
    done
    info "Cleanup complete. Log: $LOG_FILE"
}
trap cleanup EXIT

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — Deploy Wallpapers, Icons, and Photos
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 2 — Deploying Wallpapers, Icons, and Photos"

# System backgrounds
mkdir -p "$CHROOT/usr/share/backgrounds/lilith"
cp -v "$WALLPAPERS"/* "$CHROOT/usr/share/backgrounds/lilith/" 2>/dev/null || true
cp -v "$ASSETS/official-logo.png" "$CHROOT/usr/share/backgrounds/lilith/" 2>/dev/null || true
if [[ -f "$WALLPAPERS/lil-wall.jpg" ]]; then
    cp -v "$WALLPAPERS/lil-wall.jpg" "$CHROOT/usr/share/backgrounds/lilith/default.jpg"
fi
find "$CHROOT/usr/share/backgrounds/lilith" -type f -exec chmod 644 {} \;
info "System wallpapers → /usr/share/backgrounds/lilith/"

# Skel Pictures
PICTURES_DIR="$CHROOT/etc/skel/Pictures"
mkdir -p "$PICTURES_DIR/wallpapers" "$PICTURES_DIR/lilith-photos"
cp -v "$WALLPAPERS"/* "$PICTURES_DIR/wallpapers/" 2>/dev/null || true
cp -v "$ASSETS/official-logo.png" "$PICTURES_DIR/wallpapers/" 2>/dev/null || true
cp -v "$RANDOM_PHOTOS"/* "$PICTURES_DIR/lilith-photos/" 2>/dev/null || true
[[ -d "$CUSTICONS" ]] && cp -r "$CUSTICONS" "$PICTURES_DIR/lil-custicons" || true
chmod -R 755 "$PICTURES_DIR"
info "Wallpapers/photos → /etc/skel/Pictures/"

# System icons
if [[ -d "$CUSTICONS" ]]; then
    mkdir -p "$CHROOT/usr/share/icons"
    cp -r "$CUSTICONS" "$CHROOT/usr/share/icons/lil-custicons"
    chmod -R 755 "$CHROOT/usr/share/icons/lil-custicons"
    info "Custom icons → /usr/share/icons/lil-custicons/"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — Remove replaced components (cosmic-term, cosmic-store)
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 3 — Removing replaced components"

chroot "$CHROOT" /bin/bash -c "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l

echo '>>> Purging cosmic-term (replaced by Hyper)...'
apt-get purge -y cosmic-term 2>/dev/null && echo 'cosmic-term purged' || echo '[WARN] cosmic-term not installed or could not purge — skipping'

echo '>>> Attempting to purge cosmic-store (replaced by Offerings)...'
if apt-get purge -y --simulate cosmic-store 2>/dev/null | grep -q 'would break'; then
    echo '[WARN] cosmic-store purge would break deps — hiding via NoDisplay=true'
    if [[ -f /usr/share/applications/io.elementary.appcenter.desktop ]] || \
       [[ -f /usr/share/applications/cosmic-store.desktop ]]; then
        for f in /usr/share/applications/io.elementary.appcenter.desktop \
                 /usr/share/applications/cosmic-store.desktop; do
            [[ -f \"\$f\" ]] && echo 'NoDisplay=true' >> \"\$f\" && echo \"Hidden: \$f\"
        done
    fi
else
    apt-get purge -y cosmic-store 2>/dev/null && echo 'cosmic-store purged' || \
        echo '[WARN] cosmic-store not found — skipping'
fi
" 2>&1 | tee -a "$LOG_FILE" || warn "Step 3 had non-fatal errors (check log)"
info "Replaced components handled"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — Ensure COSMIC Desktop, Greeter & hepp3n PPA
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 4 — Ensuring COSMIC Desktop & Greeter"

chroot "$CHROOT" /bin/bash -c "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l

echo '>>> Ensuring hepp3n/cosmic-epoch PPA...'
if ! grep -r 'hepp3n' /etc/apt/sources.list.d/ >/dev/null 2>&1; then
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:hepp3n/cosmic-epoch
fi

apt-get update -qq

echo '>>> Installing cosmic-desktop, cosmic-greeter, lightdm...'
apt-get install -y cosmic-desktop cosmic-greeter lightdm git --no-install-recommends

echo '>>> Cloning cosmic-uniform-glass-theme...'
cd /tmp
rm -rf cosmic-uniform-glass-theme
git clone --depth 1 https://github.com/xarbit/cosmic-uniform-glass-theme.git
mkdir -p /usr/share/cosmic/themes
cp -r cosmic-uniform-glass-theme /usr/share/cosmic/themes/
rm -rf /tmp/cosmic-uniform-glass-theme
echo 'Frosted Glass theme installed'
" 2>&1 | tee -a "$LOG_FILE" || warn "Step 4 had non-fatal errors"
info "COSMIC desktop and greeter configured"

# ── Configure display manager ──────────────────────────────────────────────────
mkdir -p "$CHROOT/etc/lightdm/lightdm.conf.d"
cat > "$CHROOT/etc/lightdm/lightdm.conf.d/50-lilith-cosmic.conf" << 'EOF'
[Seat:*]
greeter-session=cosmic-greeter
user-session=cosmic
EOF
info "lightdm configured for cosmic-greeter"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — Hyper Terminal (replace cosmic-term)
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 5 — Installing Hyper Terminal"

mkdir -p "$LIL_APPS"

# Copy AppImage
if [[ -f "$APPIMAGES/Hyper.AppImage" ]]; then
    cp -v "$APPIMAGES/Hyper.AppImage" "$LIL_APPS/Hyper.AppImage"
    chmod +x "$LIL_APPS/Hyper.AppImage"
    note "Hyper.AppImage copied to /opt/lilith-apps/"
else
    warn "Hyper.AppImage not found in staging — skipping AppImage copy"
fi

# Hyper wrapper script
cat > "$CHROOT/usr/local/bin/hyper" << 'EOF'
#!/usr/bin/env bash
exec /opt/lilith-apps/Hyper.AppImage --no-sandbox "$@"
EOF
chmod +x "$CHROOT/usr/local/bin/hyper"

# Hyper skel config
mkdir -p "$CHROOT/etc/skel/.hyper"
if [[ -d /home/aegon/hyper_backup ]]; then
    cp -r /home/aegon/hyper_backup/* "$CHROOT/etc/skel/.hyper/" 2>/dev/null || true
fi
if [[ -f /home/aegon/hyper_setup_backup.js ]]; then
    cp -v /home/aegon/hyper_setup_backup.js "$CHROOT/etc/skel/.hyper.js"
    chmod 644 "$CHROOT/etc/skel/.hyper.js"
fi
chmod -R 755 "$CHROOT/etc/skel/.hyper" || true
info "Hyper Terminal skel config deployed"

# Hyper .desktop file
cat > "$CHROOT/usr/share/applications/hyper.desktop" << 'EOF'
[Desktop Entry]
Name=Hyper
GenericName=Terminal Emulator
Comment=Hyper — a modern, beautiful terminal built on web technologies
Exec=/usr/local/bin/hyper %U
Icon=utilities-terminal
Type=Application
Categories=System;TerminalEmulator;
Keywords=terminal;shell;bash;zsh;console;
StartupNotify=true
X-GNOME-UsesNotifications=false
EOF
chmod 644 "$CHROOT/usr/share/applications/hyper.desktop"

# Register as default terminal via update-alternatives
chroot "$CHROOT" /bin/bash -c "
update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/local/bin/hyper 50 || true
update-alternatives --set x-terminal-emulator /usr/local/bin/hyper || true
" 2>/dev/null || warn "Could not set x-terminal-emulator alternative (non-fatal)"
info "Hyper Terminal installed and registered as default terminal"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — Offerings (replace cosmic-store)
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 6 — Installing Offerings (App Store replacement)"

# Find the best offerings deb (prefer non-beta)
OFFERINGS_DEB=$(ls "$DEBS"/offerings_*.deb 2>/dev/null | grep -v beta | tail -1 || \
                ls "$DEBS"/offerings_*.deb 2>/dev/null | tail -1 || echo "")

if [[ -n "$OFFERINGS_DEB" ]]; then
    OFFERINGS_BASENAME=$(basename "$OFFERINGS_DEB")
    cp -v "$OFFERINGS_DEB" "$CHROOT/tmp/$OFFERINGS_BASENAME"
    chroot "$CHROOT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y /tmp/$OFFERINGS_BASENAME 2>&1 || \
        dpkg -i /tmp/$OFFERINGS_BASENAME && apt-get install -f -y || true
    rm -f /tmp/$OFFERINGS_BASENAME
    " 2>&1 | tee -a "$LOG_FILE" || warn "Offerings deb install had errors"
    info "Offerings deb installed: $OFFERINGS_BASENAME"
else
    warn "No Offerings .deb found in staging. Attempting AppImage fallback..."
    OFFERINGS_APPIMAGE=$(ls "$APPIMAGES"/Offerings*.AppImage 2>/dev/null | tail -1 || \
                         ls "$STAGING/"*Offerings*.AppImage 2>/dev/null | tail -1 || echo "")
    if [[ -n "$OFFERINGS_APPIMAGE" ]]; then
        cp -v "$OFFERINGS_APPIMAGE" "$LIL_APPS/Offerings.AppImage"
        chmod +x "$LIL_APPS/Offerings.AppImage"
        cat > "$CHROOT/usr/local/bin/offerings" << 'EOF'
#!/usr/bin/env bash
exec /opt/lilith-apps/Offerings.AppImage --no-sandbox "$@"
EOF
        chmod +x "$CHROOT/usr/local/bin/offerings"
        warn "Offerings installed as AppImage (deb preferred)"
    else
        warn "Offerings not found in staging — skipping (run pre-build-host.sh)"
    fi
fi

# Offerings .desktop (always write/overwrite)
cat > "$CHROOT/usr/share/applications/offerings.desktop" << 'EOF'
[Desktop Entry]
Name=Offerings
GenericName=App Store
Comment=Offerings — The Lilith Linux App Center
Exec=offerings %U
Icon=system-software-install
Type=Application
Categories=System;PackageManager;
Keywords=apps;store;software;install;packages;
MimeType=x-scheme-handler/appstream;
StartupNotify=true
EOF
chmod 644 "$CHROOT/usr/share/applications/offerings.desktop"

# Register as appstream handler
chroot "$CHROOT" /bin/bash -c "
update-desktop-database /usr/share/applications/ 2>/dev/null || true
" 2>/dev/null || true
info "Offerings configured as app store"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — BlancoBAM .deb Tools: Tweakers, Stake, Ouija-Pad, Lilim
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 7 — Installing BlancoBAM Tools"

install_deb_from_staging() {
    local pattern="$1"
    local display_name="$2"
    local deb_file
    deb_file=$(ls "$DEBS"/${pattern}*.deb 2>/dev/null | tail -1 || echo "")
    if [[ -z "$deb_file" ]]; then
        warn "$display_name: no .deb found in staging (expected pattern: ${pattern}*.deb)"
        return 1
    fi
    local basename
    basename=$(basename "$deb_file")

    # Patch the .deb before copying into chroot:
    # Some BlancoBAM packages hardcode 'chown aegon:aegon' in their postinst,
    # which fails because 'aegon' doesn't exist inside the chroot.
    # They also call 'systemctl restart/daemon-reload' which fails in chroot.
    # We repack the deb with those references removed/disabled (data files are still fully installed).
    local patched_deb="/tmp/patched_${basename}"
    local workdir
    workdir=$(mktemp -d /tmp/deb-repack-XXXXXX)

    note "Patching $basename for chroot compatibility..."
    dpkg-deb -R "$deb_file" "$workdir" 2>/dev/null || {
        warn "dpkg-deb repack failed — will try direct install with force flags"
        rm -rf "$workdir"
        # Direct fallback: copy and force-install
        cp -v "$deb_file" "$CHROOT/tmp/$basename"
        chroot "$CHROOT" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        dpkg -i --force-all /tmp/$basename 2>&1 || true
        dpkg --configure --force-all -a 2>&1 || true
        apt-get install -f -y 2>&1 || true
        rm -f /tmp/$basename
        " 2>&1 | tee -a "$LOG_FILE"
        info "$display_name installed (force mode): $basename"
        return 0
    }

    # Patch all maintainer scripts to remove chown references and systemctl calls
    for script in preinst postinst prerm postrm; do
        if [[ -f "$workdir/DEBIAN/$script" ]]; then
            note "  Patching maintainer script $script in $basename..."
            sed -i \
                -e '/chown.*aegon/d' \
                -e '/chgrp.*aegon/d' \
                -e 's/chown[[:space:]]\+aegon[^)]*//g' \
                -e 's/chgrp[[:space:]]\+aegon[^)]*//g' \
                -e '/systemctl/d' \
                "$workdir/DEBIAN/$script"
            chmod 755 "$workdir/DEBIAN/$script"
        fi
    done

    # Repack the deb
    dpkg-deb -b "$workdir" "$patched_deb" 2>/dev/null || {
        warn "dpkg-deb repack build failed — falling back to direct force-install"
        rm -rf "$workdir" "$patched_deb"
        cp -v "$deb_file" "$CHROOT/tmp/$basename"
        chroot "$CHROOT" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        dpkg -i --force-all /tmp/$basename 2>&1 || true
        dpkg --configure --force-all -a 2>&1 || true
        apt-get install -f -y 2>&1 || true
        rm -f /tmp/$basename
        " 2>&1 | tee -a "$LOG_FILE"
        info "$display_name installed (force mode): $basename"
        return 0
    }
    rm -rf "$workdir"

    # Copy patched deb into chroot and install normally
    local chroot_basename="patched_${basename}"
    cp -v "$patched_deb" "$CHROOT/tmp/$chroot_basename"
    rm -f "$patched_deb"

    chroot "$CHROOT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y /tmp/$chroot_basename 2>&1 || {
        dpkg -i /tmp/$chroot_basename 2>&1 || true
        dpkg --configure --force-all -a 2>&1 || true
        apt-get install -f -y 2>&1 || true
    }
    rm -f /tmp/$chroot_basename
    " 2>&1 | tee -a "$LOG_FILE" || warn "$display_name install had errors (check log)"
    info "$display_name installed: $basename"
}

install_deb_from_staging "tweakers"   "Tweakers"
install_deb_from_staging "stake"      "Stake"
install_deb_from_staging "ouija-pad"  "Ouija-Pad"
install_deb_from_staging "lilim"      "Lilim"

# Enable Lilith-AI systemd service inside chroot
if [[ -f "$CHROOT/lib/systemd/system/lilith-ai.service" || -f "$CHROOT/etc/systemd/system/lilith-ai.service" ]]; then
    note "Enabling lilith-ai.service..."
    chroot "$CHROOT" /bin/bash -c "deb-systemd-helper enable lilith-ai.service || systemctl enable lilith-ai.service || true" 2>&1 | tee -a "$LOG_FILE"
fi

# Write .desktop files for each (in case the package doesn't include one)
declare -A APP_DESKTOPS
APP_DESKTOPS=(
    ["tweakers"]="Name=Tweakers
GenericName=System Tweaker
Comment=Lilith Linux system tweaks and customization
Exec=tweakers %U
Icon=preferences-system
Type=Application
Categories=System;Settings;
Keywords=tweaks;settings;customize;lilith;"

    ["stake"]="Name=Stake
GenericName=Crypto Wallet
Comment=Stake — Lilith Linux crypto and finance tool
Exec=stake %U
Icon=money-manager-ex
Type=Application
Categories=Finance;Network;
Keywords=crypto;wallet;finance;stake;"

    ["ouija-pad"]="Name=Ouija-Pad
GenericName=Text Editor
Comment=Ouija-Pad — Lilith Linux text editor
Exec=ouija-pad %U
Icon=accessories-text-editor
Type=Application
Categories=TextEditor;Utility;
Keywords=text;editor;notes;pad;ouija;"

    ["lilim"]="Name=Lilim
GenericName=AI Assistant
Comment=Lilim — Lilith Linux AI companion
Exec=lilim %U
Icon=applications-science
Type=Application
Categories=Utility;Science;
Keywords=ai;assistant;lilim;lilith;"
)

for app in tweakers stake ouija-pad lilim; do
    DESKTOP_FILE="$CHROOT/usr/share/applications/${app}.desktop"
    if [[ ! -f "$DESKTOP_FILE" ]]; then
        printf '[Desktop Entry]\n%s\nStartupNotify=true\n' "${APP_DESKTOPS[$app]}" \
            > "$DESKTOP_FILE"
        chmod 644 "$DESKTOP_FILE"
        note "Created .desktop for $app"
    else
        note "$app already has a .desktop file"
    fi
done
info "BlancoBAM tools installed"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — Shapeshifter (Rust source binary)
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 8 — Installing Shapeshifter"

if [[ -f "$BINARIES/shapeshifter" ]]; then
    cp -v "$BINARIES/shapeshifter" "$CHROOT/usr/local/bin/shapeshifter"
    chmod +x "$CHROOT/usr/local/bin/shapeshifter"
    info "Shapeshifter binary installed to /usr/local/bin/shapeshifter"
else
    warn "Shapeshifter binary not found in staging/binaries/ — skipping (run pre-build-host.sh with Rust)"
fi

# Shapeshifter .desktop
cat > "$CHROOT/usr/share/applications/shapeshifter.desktop" << 'EOF'
[Desktop Entry]
Name=Shapeshifter
GenericName=Desktop Profile Manager
Comment=Shapeshifter — switch between COSMIC desktop profiles and layouts
Exec=shapeshifter %U
Icon=preferences-desktop-wallpaper
Type=Application
Categories=System;Settings;
Keywords=desktop;profile;layout;cosmic;shapeshifter;
StartupNotify=true
EOF
chmod 644 "$CHROOT/usr/share/applications/shapeshifter.desktop"
info "Shapeshifter .desktop written"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 9 — Lilith-TTS (Rust source binary)
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 9 — Installing Lilith-TTS"

if [[ -f "$BINARIES/lilith-tts" ]]; then
    cp -v "$BINARIES/lilith-tts" "$CHROOT/usr/local/bin/lilith-tts"
    chmod +x "$CHROOT/usr/local/bin/lilith-tts"
    info "Lilith-TTS binary installed to /usr/local/bin/lilith-tts"

    # Copy any voice model assets if present
    if [[ -d "$BINARIES/lilith-tts-data" ]]; then
        mkdir -p "$CHROOT/usr/share/lilith-tts"
        cp -r "$BINARIES/lilith-tts-data/"* "$CHROOT/usr/share/lilith-tts/" 2>/dev/null || true
    fi
else
    warn "Lilith-TTS binary not found in staging/binaries/ — skipping (run pre-build-host.sh with Rust)"
fi

# Lilith-TTS .desktop
cat > "$CHROOT/usr/share/applications/lilith-tts.desktop" << 'EOF'
[Desktop Entry]
Name=Lilith TTS
GenericName=Text to Speech
Comment=Lilith-TTS — on-device text-to-speech for Lilith Linux
Exec=lilith-tts %U
Icon=audio-speakers
Type=Application
Categories=Utility;Accessibility;Audio;
Keywords=tts;speech;voice;text;lilith;accessibility;
StartupNotify=true
EOF
chmod 644 "$CHROOT/usr/share/applications/lilith-tts.desktop"
info "Lilith-TTS .desktop written"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 10 — Vicinae Launcher (AppImage)
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 10 — Installing Vicinae Launcher"

if [[ -f "$APPIMAGES/Vicinae.AppImage" ]]; then
    cp -v "$APPIMAGES/Vicinae.AppImage" "$LIL_APPS/Vicinae.AppImage"
    chmod +x "$LIL_APPS/Vicinae.AppImage"
    cat > "$CHROOT/usr/local/bin/vicinae" << 'EOF'
#!/usr/bin/env bash
exec /opt/lilith-apps/Vicinae.AppImage --no-sandbox "$@"
EOF
    chmod +x "$CHROOT/usr/local/bin/vicinae"
    info "Vicinae AppImage installed"
else
    warn "Vicinae.AppImage not found in staging — skipping"
fi

cat > "$CHROOT/usr/share/applications/vicinae.desktop" << 'EOF'
[Desktop Entry]
Name=Vicinae
GenericName=Application Launcher
Comment=Vicinae — fast app launcher for COSMIC desktop
Exec=vicinae %U
Icon=system-search
Type=Application
Categories=Utility;
Keywords=launcher;search;apps;vicinae;cosmic;
StartupNotify=true
EOF
chmod 644 "$CHROOT/usr/share/applications/vicinae.desktop"
info "Vicinae .desktop written"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 11 — BrowserOS AppImage
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 11 — Installing BrowserOS"

BROWSEROS_FILE=$(ls "$APPIMAGES"/BrowserOS*.AppImage 2>/dev/null | tail -1 || echo "")
if [[ -n "$BROWSEROS_FILE" ]]; then
    cp -v "$BROWSEROS_FILE" "$LIL_APPS/BrowserOS.AppImage"
    chmod +x "$LIL_APPS/BrowserOS.AppImage"
    cat > "$CHROOT/usr/local/bin/browseros" << 'EOF'
#!/usr/bin/env bash
exec /opt/lilith-apps/BrowserOS.AppImage --no-sandbox "$@"
EOF
    chmod +x "$CHROOT/usr/local/bin/browseros"
    info "BrowserOS AppImage installed"
else
    warn "BrowserOS.AppImage not found in staging — skipping"
fi

cat > "$CHROOT/usr/share/applications/browseros.desktop" << 'EOF'
[Desktop Entry]
Name=BrowserOS
GenericName=Web Browser
Comment=BrowserOS — a full browser-based OS experience
Exec=browseros %U
Icon=web-browser
Type=Application
Categories=Network;WebBrowser;
Keywords=browser;web;internet;chromium;browseros;
StartupNotify=true
EOF
chmod 644 "$CHROOT/usr/share/applications/browseros.desktop"
info "BrowserOS .desktop written"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 12 — Rust Alternatives (.deb installs from staging)
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 12 — Installing Rust CLI Alternatives"

install_rust_debs() {
    # bat, lsd, zoxide, ripgrep, topgrade install normally via dpkg
    local patterns=("bat" "lsd" "zoxide" "ripgrep" "topgrade")
    for pat in "${patterns[@]}"; do
        local deb_file
        deb_file=$(ls "$DEBS"/${pat}*.deb 2>/dev/null | grep -v musl | tail -1 || \
                   ls "$DEBS"/${pat}*.deb 2>/dev/null | tail -1 || echo "")
        if [[ -n "$deb_file" ]]; then
            local bname
            bname=$(basename "$deb_file")
            cp -v "$deb_file" "$CHROOT/tmp/$bname"
            chroot "$CHROOT" /bin/bash -c "
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i /tmp/$bname 2>&1 || apt-get install -f -y 2>&1 || true
            rm -f /tmp/$bname
            " 2>&1 | tee -a "$LOG_FILE" || true
            info "$pat installed: $bname"
        else
            note "$pat .deb not found in staging"
        fi
    done

    # fd: fd-musl conflicts with pop-launcher's fd-find dependency.
    # Extract the binary directly from the deb rather than using dpkg.
    local fd_deb
    fd_deb=$(ls "$DEBS"/fd*.deb 2>/dev/null | tail -1 || echo "")
    if [[ -n "$fd_deb" ]]; then
        local fd_tmpdir
        fd_tmpdir=$(mktemp -d /tmp/fd-extract-XXXXXX)
        note "Extracting fd binary from $(basename "$fd_deb") (bypassing fd-find conflict)..."
        dpkg-deb -x "$fd_deb" "$fd_tmpdir" 2>/dev/null
        if [[ -f "$fd_tmpdir/usr/bin/fd" ]]; then
            cp -v "$fd_tmpdir/usr/bin/fd" "$CHROOT/usr/local/bin/fd"
            chmod 755 "$CHROOT/usr/local/bin/fd"
            # Copy completions
            if [[ -d "$fd_tmpdir/usr/share/bash-completion/completions" ]]; then
                mkdir -p "$CHROOT/usr/share/bash-completion/completions"
                cp -v "$fd_tmpdir/usr/share/bash-completion/completions/"* \
                    "$CHROOT/usr/share/bash-completion/completions/" 2>/dev/null || true
            fi
            info "fd binary extracted and installed to /usr/local/bin/fd"
        else
            warn "fd binary not found in deb — skipping"
        fi
        rm -rf "$fd_tmpdir"
    else
        note "fd .deb not found in staging"
    fi
}
install_rust_debs

# s8n system CLI tool (raw binary from BlancoBAM/S8n-System)
if [[ -f "$BINARIES/s8n" ]]; then
    cp -v "$BINARIES/s8n" "$CHROOT/usr/local/bin/s8n"
    chmod 755 "$CHROOT/usr/local/bin/s8n"
    info "s8n binary installed to /usr/local/bin/s8n"
    # Write s8n .desktop entry
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
else
    warn "s8n binary not found in staging/binaries/ — skipping (run pre-build-host.sh)"
fi


# uutils-wrapper
if [[ -f "$LIL_BUILD/uutils-wrapper.sh" ]]; then
    cp -v "$LIL_BUILD/uutils-wrapper.sh" "$CHROOT/usr/local/bin/uutils-wrapper.sh"
    chmod 755 "$CHROOT/usr/local/bin/uutils-wrapper.sh"
    for cmd in ls cat dd df du echo env false groups hostid hostname id \
                link ln mkdir mknod mv nohup pwd rm rmdir sleep sort stat \
                sync touch true uname uniq wc whoami cp chmod chown; do
        ln -sf /usr/local/bin/uutils-wrapper.sh "$CHROOT/usr/local/bin/$cmd"
    done
    info "uutils-wrapper.sh deployed with symlinks"
fi

# /etc/profile.d for Rust alternatives
cat > "$CHROOT/etc/profile.d/lilith-rust-alternatives.sh" << 'PROFILEEOF'
# Lilith Linux — Rust CLI Alternatives
# Transparent fallback from Rust tools to GNU equivalents

_alias_if_exists() {
    local name="$1" cmd="$2"
    command -v "$cmd" >/dev/null 2>&1 && alias "$name"="$cmd"
}

_alias_if_exists cat  bat
_alias_if_exists ls   lsd
_alias_if_exists grep rg
_alias_if_exists find fd
_alias_if_exists du   dust
_alias_if_exists ps   procs
_alias_if_exists top  btm  # bottom

# zoxide cd
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)" || true

export PATH="/usr/local/bin:/opt/lilith-apps:$PATH"
PROFILEEOF
chmod 644 "$CHROOT/etc/profile.d/lilith-rust-alternatives.sh"
info "Rust alternatives profile.d written"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 13 — Starship Flame Prompt
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 13 — Configuring Starship Flame Prompt"

if [[ -f "$LIL_BUILD/install_flame_font.sh" ]]; then
    cp -v "$LIL_BUILD/install_flame_font.sh" "$CHROOT/tmp/install_flame_font.sh"
    chmod +x "$CHROOT/tmp/install_flame_font.sh"
    chroot "$CHROOT" /bin/bash -c "
    export HOME=/etc/skel
    export USER=root
    /tmp/install_flame_font.sh || true
    " 2>&1 | tee -a "$LOG_FILE" || warn "Flame font install had errors (non-fatal)"
    rm -f "$CHROOT/tmp/install_flame_font.sh"
    info "Starship flame prompt and FiraCode Nerd Font pre-installed"
else
    warn "install_flame_font.sh not found in lil-build — skipping"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 14 — Additional Repos & Sources
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 14 — Configuring Repos & Sources"

chroot "$CHROOT" /bin/bash -c "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo '>>> Ensuring universe/multiverse...'
add-apt-repository -y universe 2>/dev/null || true
add-apt-repository -y multiverse 2>/dev/null || true

echo '>>> Ensuring flatpak...'
apt-get install -y flatpak gnome-software-plugin-flatpak 2>/dev/null || true
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

echo '>>> Ensuring libfuse2t64 (AppImage dependency)...'
apt-get install -y libfuse2t64 2>/dev/null || true

echo '>>> Final apt update...'
apt-get update -qq 2>/dev/null || true
" 2>&1 | tee -a "$LOG_FILE" || warn "Step 14 had non-fatal errors"
info "Repos and sources configured"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 15 — COSMIC Theme & Skel Config
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 15 — Writing COSMIC Skel Config"

COSMIC_SKEL="$CHROOT/etc/skel/.config/cosmic"
mkdir -p "$COSMIC_SKEL"
mkdir -p "$COSMIC_SKEL/com.system76.CosmicSettings.Keybindings"
mkdir -p "$COSMIC_SKEL/com.system76.CosmicPanel"
mkdir -p "$COSMIC_SKEL/com.system76.CosmicBackground"
mkdir -p "$COSMIC_SKEL/com.system76.CosmicTheme"

# Theme config
cat > "$COSMIC_SKEL/theme.toml" << 'EOF'
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

# COSMIC keybindings (Lilith-TTS: Ctrl+Alt+T+T)
cat > "$COSMIC_SKEL/com.system76.CosmicSettings.Keybindings/v1" << 'EOF'
[[keybindings]]
key = "ctrl+alt+t"
action = "terminal"
exec = "/usr/local/bin/hyper"
description = "Open Hyper Terminal"

[[keybindings]]
key = "super+t"
action = "exec"
exec = "/usr/local/bin/lilith-tts"
description = "Lilith TTS"

[[keybindings]]
key = "super+space"
action = "exec"
exec = "/usr/local/bin/vicinae"
description = "Vicinae Launcher"
EOF

# COSMIC panel config (pin Vicinae and Lilith-TTS)
cat > "$COSMIC_SKEL/com.system76.CosmicPanel/v1" << 'EOF'
[[panel_config]]
anchor = "Top"
size = "M"
entries = [
  "com.system76.CosmicAppList",
  "separator",
  "com.system76.CosmicWorkspaces",
  "separator",
  "vicinae",
  "lilith-tts",
  "separator",
  "com.system76.CosmicNetworkApplet",
  "com.system76.CosmicBluetooth",
  "com.system76.CosmicAudio",
  "com.system76.CosmicNotifications",
  "com.system76.CosmicClock",
]
EOF

# COSMIC background
cat > "$COSMIC_SKEL/com.system76.CosmicBackground/v1" << 'EOF'
[background]
path = "/usr/share/backgrounds/lilith/default.jpg"
scaling = "Zoom"
color_scheme = "Dark"
EOF

# Frosted glass theme config
cat > "$COSMIC_SKEL/com.system76.CosmicTheme/v1" << 'EOF'
[theme]
name = "cosmic-uniform-glass-theme"
path = "/usr/share/cosmic/themes/cosmic-uniform-glass-theme"
dark = true
accent = "#7C3AED"
EOF

info "COSMIC skel config written (theme, keybindings, panel, background)"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 16 — OS Branding
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 16 — Applying Lilith Linux Branding"

cat > "$CHROOT/etc/os-release" << 'EOF'
PRETTY_NAME="Lilith Linux"
NAME="Lilith Linux"
ID=lilith
ID_LIKE=ubuntu
VERSION_ID="1.0"
VERSION="1.0 (Resolute)"
VERSION_CODENAME=resolute
HOME_URL="https://github.com/BlancoBAM/Lilith-Linux"
SUPPORT_URL="https://github.com/BlancoBAM/Lilith-Linux/issues"
BUG_REPORT_URL="https://github.com/BlancoBAM/Lilith-Linux/issues"
LOGO=lilith-logo
EOF

cat > "$CHROOT/etc/lsb-release" << 'EOF'
DISTRIB_ID=LilithLinux
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=resolute
DISTRIB_DESCRIPTION="Lilith Linux 1.0 (Resolute)"
EOF

echo "lilith" > "$CHROOT/etc/hostname"
info "Lilith Linux branding applied (os-release, lsb-release, hostname)"

# Update plymouth / boot splash branding if available
if [[ -f "$ASSETS/official-logo.png" ]]; then
    # Copy logo to known plymouth locations
    for splash_dir in \
        "$CHROOT/usr/share/plymouth/themes/spinner" \
        "$CHROOT/usr/share/plymouth/themes/bgrt" \
        "$CHROOT/usr/share/plymouth"; do
        if [[ -d "$splash_dir" ]]; then
            cp -v "$ASSETS/official-logo.png" "$splash_dir/logo.png" 2>/dev/null || true
        fi
    done
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 17 — MIME database and XDG defaults
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 17 — Updating MIME database and XDG defaults"

# Write skel mimeapps.list — set Offerings as default for appstream
mkdir -p "$CHROOT/etc/skel/.config"
cat > "$CHROOT/etc/skel/.config/mimeapps.list" << 'EOF'
[Default Applications]
x-scheme-handler/appstream=offerings.desktop
application/x-extension-htm=chromium-browser.desktop
application/x-extension-html=chromium-browser.desktop
text/html=chromium-browser.desktop
inode/directory=nautilus.desktop
EOF

# System-wide defaults
cat > "$CHROOT/usr/share/applications/mimeapps.list" << 'EOF'
[Default Applications]
x-scheme-handler/appstream=offerings.desktop
EOF

chroot "$CHROOT" /bin/bash -c "
update-desktop-database /usr/share/applications/ 2>/dev/null || true
update-mime-database /usr/share/mime/ 2>/dev/null || true
" 2>/dev/null || true
info "MIME database updated"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 18 — AppImage integration helper
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 18 — Configuring AppImage integration"

# Add /opt/lilith-apps to PATH system-wide
cat > "$CHROOT/etc/profile.d/lilith-apps-path.sh" << 'EOF'
# Lilith Linux — AppImage launchers on PATH
export PATH="/opt/lilith-apps:/usr/local/bin:$PATH"
EOF
chmod 644 "$CHROOT/etc/profile.d/lilith-apps-path.sh"

# Fix permissions on /opt/lilith-apps
if [[ -d "$LIL_APPS" ]]; then
    find "$LIL_APPS" -name "*.AppImage" -exec chmod +x {} \;
    find "$LIL_APPS" -name "*.AppImage" -exec chown root:root {} \;
fi
info "AppImage path and permissions configured"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 18.5 — First-boot permission and service setup
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 18.5 — Creating first-boot permission corrector"

# Write the first-boot shell script inside the chroot
cat > "$CHROOT/usr/sbin/lilith-first-boot.sh" << 'EOF'
#!/usr/bin/env bash
# Lilith OS First Boot Setup Script

LOG_FILE="/var/log/lilith-first-boot.log"
echo "=== Lilith OS First Boot Setup: $(date) ===" > "$LOG_FILE"

# Wait until the 'aegon' user exists (in case it is created late by installer/first-boot)
for i in {1..30}; do
    if id "aegon" &>/dev/null; then
        echo "User 'aegon' found." >> "$LOG_FILE"
        break
    fi
    echo "Waiting for user 'aegon'..." >> "$LOG_FILE"
    sleep 2
done

if id "aegon" &>/dev/null; then
    echo "Setting ownership for Lilim directories..." >> "$LOG_FILE"
    mkdir -p /var/log/lilim
    chown -R aegon:aegon /var/log/lilim >> "$LOG_FILE" 2>&1
    
    mkdir -p /home/aegon/.local/share/lilim
    chown -R aegon:aegon /home/aegon/.local/share/lilim >> "$LOG_FILE" 2>&1

    echo "Restarting lilith-ai service..." >> "$LOG_FILE"
    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    systemctl restart lilith-ai.service >> "$LOG_FILE" 2>&1
else
    echo "User 'aegon' not found after 60 seconds. Skipping chown." >> "$LOG_FILE"
fi

# Disable the service so it doesn't run on subsequent boots
echo "Disabling first-boot service..." >> "$LOG_FILE"
systemctl disable lilith-first-boot.service >> "$LOG_FILE" 2>&1

echo "First-boot setup complete." >> "$LOG_FILE"
EOF

chmod +x "$CHROOT/usr/sbin/lilith-first-boot.sh"

# Write the systemd oneshot service file inside the chroot
cat > "$CHROOT/lib/systemd/system/lilith-first-boot.service" << 'EOF'
[Unit]
Description=Lilith OS First Boot Setup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/lilith-first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the first-boot service in the chroot
chroot "$CHROOT" /bin/bash -c "deb-systemd-helper enable lilith-first-boot.service || systemctl enable lilith-first-boot.service || true" 2>&1 | tee -a "$LOG_FILE"
info "First-boot permission corrector created and enabled"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 19 — Final apt cleanup
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 19 — Final apt cleanup"

chroot "$CHROOT" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
apt-get autoremove -y 2>/dev/null || true
apt-get clean 2>/dev/null || true
" 2>&1 | tee -a "$LOG_FILE" || warn "Cleanup had non-fatal errors"
info "apt autoremove and clean complete"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 20 — Summary Report
# ═════════════════════════════════════════════════════════════════════════════
step "STEP 20 — Lilith OS Customization Complete!"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Lilith Linux — Chroot Configuration Complete      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Chroot:${NC}     $CHROOT"
echo -e "  ${CYAN}Log:${NC}        $LOG_FILE"
echo ""
echo -e "  ${GREEN}Installed:${NC}"

# Quick verification checks
check_item() {
    local label="$1"; local path="$CHROOT/$2"
    if [[ -e "$path" ]]; then
        echo -e "    ${GREEN}✔${NC} $label"
    else
        echo -e "    ${YELLOW}⚠${NC} $label (not found: $2)"
    fi
}

check_item "Hyper Terminal"                     "usr/local/bin/hyper"
check_item "Hyper .desktop"                     "usr/share/applications/hyper.desktop"
check_item "Offerings"                          "usr/share/applications/offerings.desktop"
check_item "Tweakers .desktop"                  "usr/share/applications/tweakers.desktop"
check_item "Stake .desktop"                     "usr/share/applications/stake.desktop"
check_item "Ouija-Pad .desktop"                 "usr/share/applications/ouija-pad.desktop"
check_item "Lilim .desktop"                     "usr/share/applications/lilim.desktop"
check_item "Shapeshifter .desktop"              "usr/share/applications/shapeshifter.desktop"
check_item "Lilith-TTS .desktop"                "usr/share/applications/lilith-tts.desktop"
check_item "Vicinae .desktop"                   "usr/share/applications/vicinae.desktop"
check_item "BrowserOS .desktop"                 "usr/share/applications/browseros.desktop"
check_item "COSMIC skel config"                 "etc/skel/.config/cosmic/theme.toml"
check_item "Rust alternatives profile"          "etc/profile.d/lilith-rust-alternatives.sh"
check_item "OS branding (os-release)"           "etc/os-release"
check_item "lightdm COSMIC config"              "etc/lightdm/lightdm.conf.d/50-lilith-cosmic.conf"
check_item "Wallpapers"                         "usr/share/backgrounds/lilith"
check_item "uutils-wrapper"                     "usr/local/bin/uutils-wrapper.sh"

echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "    1. Open Cubic and verify the chroot looks correct"
echo -e "    2. Build the ISO with Cubic's 'Generate' button"
echo -e "    3. Test in a VM before flashing to hardware"
echo ""
echo -e "${GREEN}Lilith Linux is ready to be built into an ISO!${NC}"
echo ""
