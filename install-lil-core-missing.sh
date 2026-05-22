#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — Missing lil-core.txt Package Installer
# =============================================================================
# Installs everything from lil-core.txt that's missing from the chroot.
#
# Run as:   sudo bash /home/aegon/lil-build/install-lil-core-missing.sh
#
# Categories:
#   1. apt packages (tealdeer, procs, atuin, starship, just, ripgrep-all, etc.)
#   2. GitHub binary installs (nushell, rnr, systeroid, xcp, skim, czkawka)
#   3. Script-based installs (uv, gemini-cli via npm, pacstall, simplemoji)
#   4. libfuse2t64 (required for AppImages)
# =============================================================================
set -euo pipefail

CHROOT="/home/aegon/Lilith/custom-root"
TMPSTAGE="$(mktemp -d /tmp/lil-core-install-XXXXXX)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✘]${NC} $* (non-fatal, continuing)"; }
step()  { echo -e "\n${BLUE}══${NC} $* ${BLUE}══${NC}"; }

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }
[[ -d "$CHROOT" ]] || { echo "Chroot not found: $CHROOT"; exit 1; }

cleanup() {
    rm -rf "$TMPSTAGE" 2>/dev/null || true
    rm -f "$CHROOT/usr/sbin/policy-rc.d" 2>/dev/null || true
    step "Unmounting pseudo-filesystems"
    for fs in run dev/pts dev sys proc; do
        umount -lf "$CHROOT/$fs" 2>/dev/null || true
    done
    info "Done."
}
trap cleanup EXIT

# ── Mount pseudo-filesystems ──────────────────────────────────────────────────
step "Mounting pseudo-filesystems"
for fs in proc sys dev dev/pts run; do
    mount --bind "/$fs" "$CHROOT/$fs" 2>/dev/null && echo "  mounted: $fs" || echo "  already: $fs"
done

# Suppress service starts
cat > "$CHROOT/usr/sbin/policy-rc.d" << 'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

# =============================================================================
# PART 1 — apt packages (all available in Ubuntu apt)
# =============================================================================
step "PART 1 — Installing apt packages"

chroot "$CHROOT" /bin/bash << 'CHROOTEOF'
export DEBIAN_FRONTEND=noninteractive
echo ">>> Updating apt cache..."
apt-get update -qq 2>&1 | tail -3

echo ">>> Installing Rust CLI tools available in apt..."
apt-get install -y --no-install-recommends \
    tealdeer \
    procs \
    atuin \
    starship \
    just \
    ripgrep-all \
    nushell \
    libfuse2t64 \
    2>&1

echo ">>> Initializing tealdeer cache..."
tldr --update 2>/dev/null || true

echo ">>> Checking installed versions..."
tldr --version 2>/dev/null && echo "  ✔ tealdeer" || echo "  ✘ tealdeer"
procs --version 2>/dev/null | head -1 && echo "  ✔ procs" || echo "  ✘ procs"
atuin --version 2>/dev/null | head -1 && echo "  ✔ atuin" || echo "  ✘ atuin"
starship --version 2>/dev/null | head -1 && echo "  ✔ starship" || echo "  ✘ starship"
just --version 2>/dev/null | head -1 && echo "  ✔ just" || echo "  ✘ just"
rga --version 2>/dev/null | head -1 && echo "  ✔ rga (ripgrep-all)" || echo "  ✘ rga"
nu --version 2>/dev/null | head -1 && echo "  ✔ nushell" || echo "  ✘ nushell"
CHROOTEOF
info "apt packages installed"

# =============================================================================
# PART 2 — GitHub binary installs
# =============================================================================
step "PART 2 — Installing GitHub-released binaries"

install_github_binary() {
    local name="$1" url="$2" binary="$3" strip_components="${4:-1}"
    local archive="$TMPSTAGE/$(basename "$url" | sed 's/?.*//')"

    echo "  Downloading $name..."
    if ! curl -fsSL -o "$archive" "$url"; then
        warn "Failed to download $name from $url"
        return 1
    fi

    local tmpdir="$TMPSTAGE/${name}-extract"
    mkdir -p "$tmpdir"

    if [[ "$archive" == *.tar.gz ]] || [[ "$archive" == *.tgz ]]; then
        tar -xzf "$archive" -C "$tmpdir" 2>/dev/null || tar -xzf "$archive" -C "$tmpdir" --strip-components="$strip_components" 2>/dev/null
    elif [[ "$archive" == *.tar.xz ]]; then
        tar -xJf "$archive" -C "$tmpdir" 2>/dev/null
    elif [[ "$archive" == *.zip ]]; then
        unzip -q "$archive" -d "$tmpdir" 2>/dev/null
    else
        # Plain binary
        cp "$archive" "$tmpdir/$binary"
    fi

    # Find the binary
    local found
    found=$(find "$tmpdir" -name "$binary" -type f 2>/dev/null | head -1)
    if [[ -z "$found" ]]; then
        # Try without path specifics
        found=$(find "$tmpdir" -type f -perm /111 ! -name "*.so" 2>/dev/null | head -1)
    fi

    if [[ -n "$found" ]]; then
        cp "$found" "$CHROOT/usr/local/bin/$binary"
        chmod 755 "$CHROOT/usr/local/bin/$binary"
        info "$name installed → /usr/local/bin/$binary"
    else
        warn "$name: binary '$binary' not found in archive"
    fi

    rm -rf "$tmpdir" "$archive" 2>/dev/null
}

# nushell
NU_URL=$(curl -fsSL "https://api.github.com/repos/nushell/nushell/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
# nushell already attempted via apt above, only try binary if apt failed
if ! command -v nu &>/dev/null && [[ -z "$(ls "$CHROOT/usr/bin/nu" 2>/dev/null)" ]]; then
    [[ -n "$NU_URL" ]] && install_github_binary "nushell" "$NU_URL" "nu" 1 || warn "nushell: no URL found"
fi

# rnr (batch rename)
RNR_URL=$(curl -fsSL "https://api.github.com/repos/ismaelgv/rnr/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
[[ -n "$RNR_URL" ]] && install_github_binary "rnr" "$RNR_URL" "rnr" 1 || warn "rnr: no URL found"

# systeroid (sysctl TUI)
SYSTEROID_URL=$(curl -fsSL "https://api.github.com/repos/orhun/systeroid/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
[[ -n "$SYSTEROID_URL" ]] && install_github_binary "systeroid" "$SYSTEROID_URL" "systeroid" 1 || warn "systeroid: no URL found"

# xcp (cp replacement) — use linux-gnu binary (no musl release)
XCP_URL=$(curl -fsSL "https://api.github.com/repos/tarka/xcp/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-gnu' in a['name'] and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
[[ -n "$XCP_URL" ]] && install_github_binary "xcp" "$XCP_URL" "xcp" 1 || warn "xcp: no URL found"

# rip (rm improved) — build from cargo or find release
RIP_URL=$(curl -fsSL "https://api.github.com/repos/nivekuil/rip/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'linux' in a['name'].lower() and ('x86_64' in a['name'] or 'amd64' in a['name']):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$RIP_URL" ]]; then
    install_github_binary "rip" "$RIP_URL" "rip" 0
else
    warn "rip: no prebuilt binary available — install via cargo at first boot"
fi

# skim (fuzzy finder — sk binary)
SK_URL=$(curl -fsSL "https://api.github.com/repos/skim-rs/skim/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'linux' in a['name'].lower() and 'x86_64' in a['name'] and '.tar.gz' in a['name']:
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$SK_URL" ]]; then
    install_github_binary "skim" "$SK_URL" "sk" 1
else
    # Try apt
    chroot "$CHROOT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --no-install-recommends skim 2>/dev/null && echo 'skim installed via apt' || true
    " 2>&1 || warn "skim: could not install via apt or GitHub"
fi

# czkawka (duplicate file finder)
CZKAWKA_URL=$(curl -fsSL "https://api.github.com/repos/qarmin/czkawka/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'linux_gui' in a['name'] or ('linux' in a['name'] and 'gui' not in a['name'].lower() and 'x86' in a['name']):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$CZKAWKA_URL" ]]; then
    install_github_binary "czkawka" "$CZKAWKA_URL" "czkawka" 0
else
    chroot "$CHROOT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --no-install-recommends czkawka 2>/dev/null && echo 'czkawka installed via apt' || true
    " 2>&1 || warn "czkawka: not available"
fi

# navi (interactive cheatsheet)
NAVI_URL=$(curl -fsSL "https://api.github.com/repos/denisidoro/navi/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and '.tar.gz' in a['name']:
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
[[ -n "$NAVI_URL" ]] && install_github_binary "navi" "$NAVI_URL" "navi" 1 || {
    chroot "$CHROOT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --no-install-recommends navi 2>/dev/null || true
    " 2>&1
    warn "navi: trying apt fallback"
}

# kibi (text editor)
KIBI_URL=$(curl -fsSL "https://api.github.com/repos/ilai-deutel/kibi/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and '.tar.gz' in a['name']:
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$KIBI_URL" ]]; then
    install_github_binary "kibi" "$KIBI_URL" "kibi" 1
else
    chroot "$CHROOT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --no-install-recommends kibi 2>/dev/null || true
    " 2>&1
fi

# atuin (shell history)
ATUIN_URL=$(curl -fsSL "https://api.github.com/repos/atuinsh/atuin/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and '.tar.gz' in a['name']:
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
# atuin already attempted via apt; only use binary if apt version is old/missing
if [[ -z "$(ls "$CHROOT/usr/bin/atuin" 2>/dev/null)" ]]; then
    [[ -n "$ATUIN_URL" ]] && install_github_binary "atuin" "$ATUIN_URL" "atuin" 1 || warn "atuin: no URL"
fi

info "GitHub binaries processed"

# =============================================================================
# PART 3 — uv (Python package manager from astral.sh)
# =============================================================================
step "PART 3 — Installing uv (astral.sh)"

UV_URL=$(curl -fsSL "https://api.github.com/repos/astral-sh/uv/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'x86_64-unknown-linux-musl' in a['name'] and '.tar.gz' in a['name'] and 'uv-x86_64' in a['name']:
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$UV_URL" ]]; then
    install_github_binary "uv" "$UV_URL" "uv" 1
    # Also install uvx
    UV_ARCHIVE="$TMPSTAGE/uv.tar.gz"
    curl -fsSL -o "$UV_ARCHIVE" "$UV_URL" 2>/dev/null || true
    if [[ -f "$UV_ARCHIVE" ]]; then
        UVDIR="$TMPSTAGE/uv-ext"
        mkdir -p "$UVDIR"
        tar -xzf "$UV_ARCHIVE" -C "$UVDIR" 2>/dev/null
        uvx_bin=$(find "$UVDIR" -name "uvx" -type f 2>/dev/null | head -1)
        [[ -n "$uvx_bin" ]] && { cp "$uvx_bin" "$CHROOT/usr/local/bin/uvx"; chmod 755 "$CHROOT/usr/local/bin/uvx"; info "uvx installed"; }
        rm -rf "$UVDIR" "$UV_ARCHIVE"
    fi
else
    warn "uv: no URL found, trying apt"
    chroot "$CHROOT" /bin/bash -c "apt-get install -y --no-install-recommends uv 2>/dev/null || true" 2>&1
fi
info "uv processed"

# =============================================================================
# PART 4 — gemini-cli via npm
# =============================================================================
step "PART 4 — Installing @google/gemini-cli via npm"

chroot "$CHROOT" /bin/bash << 'CHROOTEOF'
export DEBIAN_FRONTEND=noninteractive
export HOME=/root

# Check npm is available
if command -v npm &>/dev/null; then
    echo ">>> npm version: $(npm --version)"
    echo ">>> Installing @google/gemini-cli globally..."
    npm install -g npm@latest 2>&1 | tail -3
    npm install -g @google/gemini-cli 2>&1 | tail -5
    # Create wrapper if installed in node_modules
    GEMINI_BIN=$(npm root -g 2>/dev/null)/@google/gemini-cli/bin/gemini 2>/dev/null
    if [[ -f "$GEMINI_BIN" ]]; then
        ln -sf "$GEMINI_BIN" /usr/local/bin/gemini 2>/dev/null || true
        echo ">>> gemini-cli installed: $(gemini --version 2>/dev/null || echo 'installed')"
    else
        # Check if npm put it in PATH already
        which gemini 2>/dev/null && echo ">>> gemini-cli: $(gemini --version 2>/dev/null)" || echo ">>> gemini-cli: binary location unclear, may need PATH"
    fi
else
    echo ">>> npm not found — installing nodejs + npm first"
    apt-get install -y --no-install-recommends nodejs npm 2>&1 | tail -5
    npm install -g @google/gemini-cli 2>&1 | tail -5
fi
CHROOTEOF
info "gemini-cli processed"

# =============================================================================
# PART 5 — pacstall
# =============================================================================
step "PART 5 — Installing pacstall"

chroot "$CHROOT" /bin/bash << 'CHROOTEOF'
export DEBIAN_FRONTEND=noninteractive
export HOME=/root
echo ">>> Installing pacstall dependencies..."
apt-get install -y --no-install-recommends \
    curl wget git sudo apt-utils bc lsb-release 2>&1 | tail -3
echo ">>> Installing pacstall via script..."
# Pacstall install script
if curl -fsSL "https://pacstall.dev/q/install" -o /tmp/pacstall-install.sh 2>/dev/null; then
    # Run non-interactively
    bash /tmp/pacstall-install.sh 2>&1 | tail -10
    rm -f /tmp/pacstall-install.sh
    command -v pacstall && echo ">>> pacstall installed" || echo ">>> pacstall: install may need reboot"
else
    echo ">>> Could not download pacstall installer"
fi
CHROOTEOF
info "pacstall processed"

# =============================================================================
# PART 6 — simplemoji
# =============================================================================
step "PART 6 — Installing simplemoji"

SIMPLEMOJI_URL="https://github.com/SergioRibera/Simplemoji/releases/latest"
SM_DL=$(curl -fsSL "https://api.github.com/repos/SergioRibera/Simplemoji/releases/latest" | \
    python3 -c "
import sys,json; data=json.load(sys.stdin)
for a in data.get('assets',[]):
    if 'linux' in a['name'].lower() and ('x86_64' in a['name'] or 'amd64' in a['name']) and not a['name'].endswith('.sha256'):
        print(a['browser_download_url']); break
" 2>/dev/null || echo "")
if [[ -n "$SM_DL" ]]; then
    install_github_binary "simplemoji" "$SM_DL" "simplemoji" 0
else
    warn "simplemoji: no prebuilt binary found, may need manual install"
fi

# =============================================================================
# PART 7 — starship config in /etc/skel
# =============================================================================
step "PART 7 — Deploying starship.toml to /etc/skel"

mkdir -p "$CHROOT/etc/skel/.config"
cat > "$CHROOT/etc/skel/.config/starship.toml" << 'TOMLEOF'
# Lilith Linux — Starship Prompt Configuration
# Purple flame aesthetic

format = """
[╭─](bold purple)$username$hostname$directory$git_branch$git_status$cmd_duration
[╰─](bold purple)$character"""

[character]
success_symbol = "[⛧](bold purple)"
error_symbol = "[✘](bold red)"

[username]
style_user = "bold purple"
style_root = "bold red"
format = "[$user]($style)[@](dimmed purple)"
show_always = false

[hostname]
ssh_only = false
style = "bold purple"
format = "[$hostname]($style) "

[directory]
style = "bold violet"
truncation_length = 4
truncate_to_repo = true
format = "in [$path]($style)[$read_only]($read_only_style) "

[git_branch]
symbol = " "
style = "bold purple"
format = "on [$symbol$branch]($style) "

[git_status]
style = "bold red"

[cmd_duration]
min_time = 500
style = "dimmed purple"
format = "took [$duration]($style) "

[battery]
disabled = true
TOMLEOF
chmod 644 "$CHROOT/etc/skel/.config/starship.toml"
info "starship.toml deployed to /etc/skel/.config/"

# Ensure starship init is in profile.d
cat > "$CHROOT/etc/profile.d/lilith-starship.sh" << 'PROFILEOF'
# Lilith Linux — Starship prompt initialization
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
PROFILEOF
chmod 644 "$CHROOT/etc/profile.d/lilith-starship.sh"
info "Starship profile.d hook installed"

# =============================================================================
# PART 8 — atuin shell integration in /etc/skel
# =============================================================================
step "PART 8 — Deploying atuin config to /etc/skel"

mkdir -p "$CHROOT/etc/skel/.config/atuin"
cat > "$CHROOT/etc/skel/.config/atuin/config.toml" << 'ATUINEOF'
# Lilith Linux — Atuin shell history config
auto_sync = false
update_check = false
search_mode = "fuzzy"
style = "compact"
show_preview = true
max_preview_height = 4
ATUINEOF
chmod 644 "$CHROOT/etc/skel/.config/atuin/config.toml"

cat >> "$CHROOT/etc/profile.d/lilith-rust-alternatives.sh" << 'ATEOF'

# atuin shell history
command -v atuin >/dev/null 2>&1 && eval "$(atuin init bash --disable-up-arrow)" || true
ATEOF
info "atuin config deployed"

# =============================================================================
# SUMMARY
# =============================================================================
step "=== VERIFICATION ==="
echo ""
CHROOT_INNER="$CHROOT"

for bin in tldr procs atuin starship just rga nu rnr systeroid xcp rip sk czkawka navi kibi uv gemini pacstall simplemoji; do
    found=false
    for dir in "$CHROOT_INNER/usr/bin" "$CHROOT_INNER/usr/local/bin"; do
        [[ -f "$dir/$bin" ]] && { echo "  ✔ $bin"; found=true; break; }
    done
    $found || echo "  ✘ $bin — still missing"
done

echo ""
info "lil-core.txt missing package installation complete."
echo "  Note: 'rip', 'sk', and 'czkawka' may fall back to apt."
echo "  Note: homebrew is intentionally excluded (not suitable for live image base)."
echo "  Note: COSMIC cosmic-utils extras (wizard, forecast, cosmicding, cosmic-color-picker)"
echo "        must be installed post-boot as they require a running COSMIC session to build."
