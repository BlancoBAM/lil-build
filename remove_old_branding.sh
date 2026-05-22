#!/bin/bash
# Lilith Linux Branding Removal Script
# Removes Ubuntu/Pop!OS branding and prepares for Lilith branding

set -e

LILITH_ROOT="${1:-/opt/lilith-linux}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    warn "Run with sudo for full effect"
fi

log "Removing Ubuntu/Pop!OS branding..."

# Remove Pop!OS APT sources
rm -f "${LILITH_ROOT}/etc/apt/sources.list.d/pop-os.list" 2>/dev/null || true
rm -f "${LILITH_ROOT}/usr/share/keyrings/pop-os-archive-keyring.gpg" 2>/dev/null || true

# Remove GNOME/Ubuntu branding
rm -rf "${LILITH_ROOT}/usr/share/gnome-shell/theme/Pop*" 2>/dev/null || true
rm -rf "${LILITH_ROOT}/usr/share/gnome-shell/theme/Yaru*" 2>/dev/null || true

# Remove Yaru theme
rm -rf "${LILITH_ROOT}/usr/share/themes/Yaru*" 2>/dev/null || true
rm -rf "${LILITH_ROOT}/usr/share/gtk-engine/gnome-themes*" 2>/dev/null || true

# Remove Ubuntu branding files
rm -f "${LILITH_ROOT}/etc/issue" 2>/dev/null || true
rm -f "${LILITH_ROOT}/etc/issue.net" 2>/dev/null || true
rm -f "${LILITH_ROOT}/usr/share/pixmaps/ubuntu*" 2>/dev/null || true

# Remove Pop!OS branding
rm -f "${LILITH_ROOT}/usr/share/plymouth/themes/pop*" 2>/dev/null || true
rm -rf "${LILITH_ROOT}/usr/share/backgrounds/pop*" 2>/dev/null || true

# Clean up old greeter configs
rm -rf "${LILITH_ROOT}/etc/pop*" 2>/dev/null || true

log "Branding cleanup complete"
log "Now run: ./install_lilith_branding.sh"
