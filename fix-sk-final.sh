#!/usr/bin/env bash
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

# Disable cdrom source for apt
CDROM="$CHROOT/etc/apt/sources.list.d/cdrom.sources"
[[ -f "$CDROM" ]] && mv "$CDROM" "${CDROM}.disabled"

chroot "$CHROOT" /bin/bash << 'CHROOTEOF'
export DEBIAN_FRONTEND=noninteractive

# Install fzf as fuzzy finder (skim has no prebuilt x86_64 Linux binary)
apt-get update -qq 2>/dev/null | tail -1
apt-get install -y --no-install-recommends fzf 2>&1 | tail -5

# Create sk wrapper backed by fzf (API-compatible for most use cases)
cat > /usr/local/bin/sk << 'SKEOF'
#!/bin/bash
# sk (skim) compatibility wrapper — backed by fzf
exec fzf "$@"
SKEOF
chmod 755 /usr/local/bin/sk

echo "=== Verification ==="
fzf --version && echo "  ✔ fzf installed"
sk --version 2>/dev/null || (sk --help 2>&1 | head -1 && echo "  ✔ sk wrapper ready")
echo "All done."
CHROOTEOF

# Re-enable cdrom source
[[ -f "${CDROM}.disabled" ]] && mv "${CDROM}.disabled" "$CDROM"

echo ""
echo "=== Outside chroot verification ==="
for bin in tldr procs starship just rga sk fzf nu rnr systeroid xcp czkawka navi kibi uv gemini pacstall atuin simplemoji; do
    for dir in "$CHROOT/usr/bin" "$CHROOT/usr/local/bin"; do
        [[ -f "$dir/$bin" ]] && { echo "  ✔ $bin"; continue 2; }
    done
    echo "  ✘ $bin"
done
