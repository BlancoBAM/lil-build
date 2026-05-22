#!/usr/bin/env bash
# Fix the apt packages that show as chroot-installed but aren't in the expected paths,
# and install skim (sk) from its installer.
set -euo pipefail

CHROOT="/home/aegon/Lilith/custom-root"

echo "0507" | sudo -S true  # auth

echo "0507" | sudo -S bash << 'ROOTEOF'
CHROOT="/home/aegon/Lilith/custom-root"

# Mount
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

# Re-install the apt packages that didn't stick
chroot "$CHROOT" /bin/bash << 'CHROOTEOF'
export DEBIAN_FRONTEND=noninteractive
echo ">>> apt-get update..."
apt-get update -qq 2>&1 | grep -v "^E: The repository 'file" || true

echo ">>> Installing tealdeer, procs, starship, just, ripgrep-all, skim..."
apt-get install -y \
    tealdeer \
    procs \
    starship \
    just \
    ripgrep-all \
    skim \
    2>&1

echo ">>> Checking binaries..."
for bin in tldr procs starship just rga sk; do
    which "$bin" 2>/dev/null && echo "  ✔ $bin: $(which $bin)" || echo "  ✘ $bin: not found"
done

echo ">>> Initializing tldr cache..."
tldr --update 2>/dev/null || true
CHROOTEOF

echo ""
echo "=== Verification from outside chroot ==="
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
