#!/usr/bin/env bash
# Fix: disable cdrom apt source, then install remaining packages
set -euo pipefail
CHROOT="/home/aegon/Lilith/custom-root"

echo "0507" | sudo -S bash << 'ROOTEOF'
CHROOT="/home/aegon/Lilith/custom-root"

for fs in proc sys dev dev/pts run; do
    mount --bind "/$fs" "$CHROOT/$fs" 2>/dev/null || true
done

cat > "$CHROOT/usr/sbin/policy-rc.d" << 'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

cleanup() {
    rm -f "$CHROOT/usr/sbin/policy-rc.d"
    for fs in run dev/pts dev sys proc; do umount -lf "$CHROOT/$fs" 2>/dev/null || true; done
}
trap cleanup EXIT

# Disable cdrom source temporarily
CDROM_SRC="$CHROOT/etc/apt/sources.list.d/cdrom.sources"
if [[ -f "$CDROM_SRC" ]]; then
    mv "$CDROM_SRC" "${CDROM_SRC}.disabled"
    echo "  Disabled cdrom.sources"
fi

chroot "$CHROOT" /bin/bash << 'CHROOTEOF'
export DEBIAN_FRONTEND=noninteractive

echo ">>> apt-get update (no cdrom)..."
apt-get update -qq 2>&1 | tail -3

echo ">>> apt-cache policy check..."
for pkg in tealdeer procs starship just ripgrep-all; do
    ver=$(apt-cache policy "$pkg" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
    echo "  $pkg: candidate=$ver"
done

echo ">>> Installing missing packages..."
apt-get install -y --no-install-recommends \
    tealdeer \
    procs \
    starship \
    just \
    ripgrep-all \
    2>&1

echo ">>> Binary check inside chroot..."
for bin in tldr procs starship just rga; do
    which "$bin" 2>/dev/null && echo "  ✔ $bin: $(which $bin)" || echo "  ✘ $bin: not in PATH"
    ls /usr/bin/"$bin" /usr/local/bin/"$bin" 2>/dev/null | head -1 | xargs -I{} echo "  found: {}"
done
CHROOTEOF

# Install skim (sk) from GitHub since not in apt
echo ""
echo ">>> Fetching skim from GitHub..."
SK_URL=$(curl -fsSL "https://api.github.com/repos/skim-rs/skim/releases/latest" 2>/dev/null | \
    python3 -c "
import sys,json
data=json.load(sys.stdin)
for a in data.get('assets',[]):
    name=a['name']
    if 'x86_64-unknown-linux' in name and name.endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")

if [[ -n "$SK_URL" ]]; then
    TMPD=$(mktemp -d)
    curl -fsSL -o "$TMPD/skim.tar.gz" "$SK_URL"
    tar -xzf "$TMPD/skim.tar.gz" -C "$TMPD" 2>/dev/null
    SK_BIN=$(find "$TMPD" -name "sk" -type f 2>/dev/null | head -1)
    if [[ -n "$SK_BIN" ]]; then
        cp "$SK_BIN" "$CHROOT/usr/local/bin/sk"
        chmod 755 "$CHROOT/usr/local/bin/sk"
        echo "  ✔ sk installed from GitHub"
    else
        # Try installing from soar inside chroot
        echo "  sk binary not found in archive, trying soar..."
    fi
    rm -rf "$TMPD"
else
    echo "  No skim GitHub release found for linux x86_64"
fi

# Re-enable cdrom.sources
[[ -f "${CDROM_SRC}.disabled" ]] && mv "${CDROM_SRC}.disabled" "$CDROM_SRC"

echo ""
echo "=== FINAL VERIFICATION ==="
for bin in tldr procs starship just rga sk; do
    for dir in "$CHROOT/usr/bin" "$CHROOT/usr/local/bin"; do
        if [[ -f "$dir/$bin" ]]; then
            echo "  ✔ $bin → $dir/$bin"
            continue 2
        fi
    done
    echo "  ✘ $bin — still missing"
done
ROOTEOF
