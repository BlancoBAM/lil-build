#!/usr/bin/env bash
# Extract fd binary directly from fd-musl deb and place it in /usr/local/bin/fd
# This bypasses the dpkg Conflicts: fd-find issue while keeping pop-launcher happy
CHROOT="/home/aegon/Lilith/custom-root"
DEB="/home/aegon/lil-build/staging/debs/fd-musl_10.4.2_amd64.deb"
TMPDIR=$(mktemp -d /tmp/fd-extract-XXXXXX)

echo "=== Extracting fd binary from fd-musl deb ==="
dpkg-deb -x "$DEB" "$TMPDIR"
ls -la "$TMPDIR/usr/bin/fd"

echo ""
echo "=== Copying fd binary to chroot /usr/local/bin/ ==="
cp -v "$TMPDIR/usr/bin/fd" "$CHROOT/usr/local/bin/fd"
chmod 755 "$CHROOT/usr/local/bin/fd"

# Also copy bash/zsh/fish completions if present
if [[ -d "$TMPDIR/usr/share/bash-completion/completions" ]]; then
    mkdir -p "$CHROOT/usr/share/bash-completion/completions"
    cp -v "$TMPDIR/usr/share/bash-completion/completions/"* "$CHROOT/usr/share/bash-completion/completions/" 2>/dev/null || true
fi

rm -rf "$TMPDIR"

echo ""
echo "=== Result ==="
ls -la "$CHROOT/usr/local/bin/fd"
echo "fd is available at: /usr/local/bin/fd (takes PATH priority over /usr/bin/fdfind)"
