#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Lilith OS  –  From-Scratch Build Script                                ║
# ║  Base   : Ubuntu 26.04 LTS (Resolute Raccoon)                          ║
# ║  Desktop: COSMIC DE + Soulless Launcher + cosmic-ext-applet-logomenu   ║
# ║  Shell  : fish (user) / brush (bash compatibility layer)               ║
# ║  Author : BlancoBAM                                                     ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# Usage:
#   sudo ./build-lilith.sh                    # full build
#   sudo ./build-lilith.sh --phase N          # resume from phase N (1-18)
#   sudo ./build-lilith.sh --phase N --to M   # run phases N through M
#   sudo ./build-lilith.sh --iso-only         # jump straight to ISO generation
#   sudo ./build-lilith.sh --clean            # wipe build dir and start fresh
#
# Output:  $OUTPUT_DIR/lilith-<version>-amd64.iso
# Log:     $BUILD_DIR/build.log
#
# Phases:
#   1  – Bootstrap Ubuntu 26.04 rootfs (debootstrap)
#   2  – Base system packages & build toolchain
#   3  – Rust toolchain (rustup, stable, cargo-binstall)
#   4  – uutils/coreutils (replaces GNU coreutils)
#   5  – Rust CLI tool stack (bat, lsd, fd, ripgrep, …)
#   6  – Additional package managers (AM, soar, pacstall, npm, astral-uv)
#   7  – COSMIC desktop (minus cosmic-launcher, cosmic-term, cosmic-store)
#   8  – Soulless Launcher (replaces cosmic-launcher)
#   9  – cosmic-ext-applet-logomenu (panel logo applet)
#   10 – Hyper.js terminal (replaces cosmic-term)
#   11 – Browsers: BrowserOS + Hellfire
#   12 – BlancoBAM custom apps (Offerings, s8n, Tweakers, Lilim, …)
#   13 – Shell environment (fish default, brush as bash compat, starship, …)
#   14 – Themes, wallpapers, fonts, icons
#   15 – GRUB theme (lil-grub) + boot splash videos
#   16 – System services, display manager, final config
#   17 – Lilith repos & topgrade auto-update wiring
#   18 – ISO generation
# ══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────
# 0. GLOBAL CONFIG
# ──────────────────────────────────────────────────────────────────────────
DISTRO_NAME="Lilith"
DISTRO_VERSION="1.0.0"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-resolute}"  # Ubuntu 26.04 LTS (Resolute Raccoon)
UBUNTU_MIRROR="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
ARCH="${ARCH:-amd64}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-/opt/lilith-build}"
ROOTFS="$BUILD_DIR/rootfs"
CACHE_DIR="$BUILD_DIR/cache"
OUTPUT_DIR="$BUILD_DIR/output"
LOG_FILE="$BUILD_DIR/build.log"
PHASE_DIR="$BUILD_DIR/phases"          # phase completion stamps

BLANCO="https://github.com/BlancoBAM"
JOBS="$(nproc)"

START_PHASE="${START_PHASE:-1}"
END_PHASE="${END_PHASE:-18}"

# Local asset paths (host-side, copied into rootfs during phase 14)
ASSETS_DIR="${ASSETS_DIR:-/home/aegon/workspace/Lilith-Linux/assets}"
LOGO_SVG="${LOGO_SVG:-/home/aegon/Downloads/lil-logo2.svg}"
SPLASH_VIDEO_1="${SPLASH_VIDEO_1:-/home/aegon/workspace/Lilith-Linux/Lilith-Splash/splash-final.mp4}"
SPLASH_VIDEO_2="${SPLASH_VIDEO_2:-/home/aegon/workspace/Lilith-Linux/splash-final/0cc1h6yv6xrmt0cwvz4rqa7ybw_result_V1.mp4}"
SOULLESS_BG="${SOULLESS_BG:-/home/aegon/workspace/Lilith-Linux/assets/wallpapers/lil-logo4.jpeg}"

# ──────────────────────────────────────────────────────────────────────────
# COLOUR HELPERS
# ──────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'
CYN='\033[0;36m'; PRP='\033[0;35m'; BLD='\033[1m'; RST='\033[0m'

# All stdout/stderr is already captured by the exec tee redirect below.
# These helpers just add colour tagging — no manual tee needed here.
info()  { echo -e "${CYN}[INFO]${RST}  $*"; }
ok()    { echo -e "${GRN}[ OK ]${RST}  $*"; }
warn()  { echo -e "${YEL}[WARN]${RST}  $*"; }
err()   { echo -e "${RED}[ERR ]${RST}  $*" >&2; exit 1; }

phase_banner() {
    local n="$1"; shift
    echo -e "\n${BLD}${PRP}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
    echo -e "${BLD}${PRP}  Phase $n │ $*${RST}"
    echo -e "${BLD}${PRP}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}\n"
}

progress() { echo -e "  ${CYN}▶${RST} $*"; }

# Mark a phase done (idempotency stamp)
stamp_done()  { touch "$PHASE_DIR/phase-${1}.done"; }
phase_done()  { [[ -f "$PHASE_DIR/phase-${1}.done" ]]; }

# Run a shell snippet inside the rootfs via systemd-nspawn.
# stdout/stderr flow into the exec-level tee already — no extra tee needed.
nspawn() {
    systemd-nspawn \
        --directory="$ROOTFS" \
        --bind-ro=/etc/resolv.conf:/etc/resolv.conf \
        --setenv=DEBIAN_FRONTEND=noninteractive \
        --setenv=CARGO_HOME=/usr/local/cargo \
        --setenv=RUSTUP_HOME=/usr/local/rustup \
        --setenv=RUSTUP_INIT_SKIP_PATH_CHECK=yes \
        --setenv=PATH=/usr/local/cargo/bin:/usr/local/lib/uutils:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        --pipe \
        -- bash -lc "$*"
}

# Resilient nspawn — logs warning but does NOT abort build on failure
nspawn_soft() {
    nspawn "$@" || warn "Command failed (non-fatal): $*"
}

# Clone or fast-forward a git repo
git_sync() {
    local url="$1" dest="$2" extra="${3:-}"
    if [[ -d "$dest/.git" ]]; then
        info "Updating $(basename "$dest")…"
        git -C "$dest" pull --ff-only || true
    else
        info "Cloning $(basename "$dest")…"
        # shellcheck disable=SC2086
        git clone --depth=1 $extra "$url" "$dest"
    fi
}

# Resolve latest GitHub release download URL matching a pattern
gh_latest_url() {
    local repo="$1" pattern="$2"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
      | grep -o '"browser_download_url": *"[^"]*"' \
      | grep "$pattern" \
      | head -1 \
      | cut -d'"' -f4
}

require_root() { [[ $EUID -eq 0 ]] || err "Run as root (sudo)."; }
require_cmd()  { command -v "$1" &>/dev/null || err "Host dependency missing: $1 – install it and re-run."; }

# ──────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ──────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)    START_PHASE="$2"; shift 2 ;;
        --to)       END_PHASE="$2";   shift 2 ;;
        --iso-only) START_PHASE=18;   shift   ;;
        --clean)
            warn "Wiping $BUILD_DIR …"
            rm -rf "$BUILD_DIR"
            shift
            ;;
        *) shift ;;
    esac
done

# ──────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT
# ──────────────────────────────────────────────────────────────────────────
require_root
mkdir -p "$BUILD_DIR" "$CACHE_DIR" "$OUTPUT_DIR" "$PHASE_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo -e "${BLD}${PRP}╔══════════════════════════════════════════════════════════╗${RST}"
echo -e "${BLD}${PRP}║       Lilith OS  –  From-Scratch Build                   ║${RST}"
echo -e "${BLD}${PRP}║  Phases $START_PHASE–$END_PHASE  │  $(date)         ║${RST}"
echo -e "${BLD}${PRP}╚══════════════════════════════════════════════════════════╝${RST}"
echo ""

for cmd in debootstrap systemd-nspawn git curl wget gpg mksquashfs xorriso; do
    require_cmd "$cmd"
done

# ══════════════════════════════════════════════════════════════════════════
# PHASE 1 – Bootstrap Ubuntu 26.04 rootfs
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 1 && $END_PHASE -ge 1 ]]; then
    phase_banner 1 "Bootstrap Ubuntu 26.04 rootfs"

    if [[ -d "$ROOTFS/usr" ]]; then
        warn "Rootfs already exists – skipping debootstrap. (Delete $ROOTFS to redo.)"
    else
        progress "Running debootstrap …"
        debootstrap \
            --arch="$ARCH" \
            --include=ca-certificates,apt-transport-https,curl,wget,gnupg,\
lsb-release,locales,tzdata,sudo,systemd,systemd-sysv,udev,dbus,\
network-manager,pipewire,pipewire-pulse,wireplumber,\
xwayland,libpam-runtime,software-properties-common \
            "$UBUNTU_CODENAME" \
            "$ROOTFS" \
            "$UBUNTU_MIRROR"
    fi

    # APT sources — Ubuntu main + Lilith custom repo
    cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $UBUNTU_MIRROR $UBUNTU_CODENAME main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-security main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-backports main restricted universe multiverse
EOF

    # Lilith custom package repo (GitHub Pages — Debian APT format)
    mkdir -p "$ROOTFS/etc/apt/sources.list.d"
    cat > "$ROOTFS/etc/apt/sources.list.d/lilith.list" <<'EOF'
# Lilith Linux custom repository
deb [signed-by=/usr/share/keyrings/lilith-archive-keyring.gpg trusted=yes] https://blancobam.github.io/lilith-packages stable main
EOF

    # Install Lilith keyring into rootfs
    if [[ -f /home/aegon/lilith-packages/lilith-archive-keyring.gpg ]]; then
        mkdir -p "$ROOTFS/usr/share/keyrings"
        cp /home/aegon/lilith-packages/lilith-archive-keyring.gpg \
           "$ROOTFS/usr/share/keyrings/lilith-archive-keyring.gpg"
    fi

    # Locale & timezone
    nspawn "locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"
    echo "America/New_York" > "$ROOTFS/etc/timezone"
    nspawn "dpkg-reconfigure -f noninteractive tzdata"

    stamp_done 1
    ok "Phase 1 complete — rootfs bootstrapped."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 2 – Base packages & build toolchain
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 2 && $END_PHASE -ge 2 ]]; then
    phase_banner 2 "Base packages & build toolchain"

    nspawn "apt-get update -q"

    progress "Installing core build toolchain …"
    nspawn "apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build meson pkg-config \
        git curl wget gpg unzip tar xz-utils bzip2 file \
        python3 python3-pip python3-dev python3-venv \
        nodejs npm \
        libssl-dev libdbus-1-dev libdbus-glib-1-dev \
        libglib2.0-dev libgtk-3-dev libgtk-4-dev \
        libwayland-dev libxkbcommon-dev libinput-dev \
        libpixman-1-dev libseat-dev libdrm-dev \
        libgbm-dev libvulkan-dev vulkan-tools \
        libdisplay-info-dev libudev-dev \
        libglvnd-dev libgles-dev \
        libpam0g-dev libpolkit-gobject-1-dev \
        libflatpak-dev flatpak \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
        libgstreamer-plugins-bad1.0-dev gstreamer1.0-plugins-good \
        gstreamer1.0-pipewire gstreamer1.0-tools \
        gstreamer1.0-libav \
        mpv ffmpeg libavcodec-dev libavformat-dev libavutil-dev \
        libsystemd-dev \
        libfontconfig-dev libfreetype-dev libfontconfig1 \
        lld clang llvm \
        libqt6core-dev libqt6widgets-dev libqt6gui-dev \
        qt6-base-dev qt6-wayland-dev libqt6svg6-dev \
        libjpeg-dev libpng-dev libwebp-dev libavif-dev \
        libxcb1-dev libxcb-ewmh-dev libxcb-icccm4-dev \
        pipewire wireplumber pipewire-pulse pipewire-audio \
        sddm sddm-theme-breeze \
        fish \
        xdg-utils xdg-user-dirs \
        plymouth plymouth-themes \
        grub2-common grub-efi-amd64 grub-efi-amd64-signed \
        shim-signed efibootmgr grub-pc-bin \
        squashfs-tools genisoimage isolinux \
        apparmor apparmor-utils \
        fuse3 libfuse3-dev libfuse2t64 \
        bluetooth bluez bluez-tools \
        network-manager-gnome \
        polkit-kde-agent-1 \
        at-spi2-core \
        dbus-x11 \
        rsync \
        jq \
        inkscape librsvg2-bin \
        imagemagick \
        apt-utils apt-transport-https"

    # Upgrade npm to latest
    progress "Upgrading npm to latest …"
    nspawn_soft "npm install -g npm@latest"

    stamp_done 2
    ok "Phase 2 complete — base packages installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 3 – Rust toolchain
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 3 && $END_PHASE -ge 3 ]]; then
    phase_banner 3 "Rust toolchain (rustup + stable + cargo-binstall)"

    # Install rustup system-wide
    if ! nspawn "command -v rustup &>/dev/null 2>&1"; then
        progress "Installing rustup …"
        nspawn "RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo \
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
            | sh -s -- -y \
                --no-modify-path \
                --default-toolchain stable \
                --component rust-analyzer,clippy,rustfmt \
                --profile default"
    fi

    # System-wide profile snippet
    cat > "$ROOTFS/etc/profile.d/01-rust.sh" <<'PROF'
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH="$CARGO_HOME/bin:/usr/local/lib/uutils:$PATH"
PROF

    # Symlinks into /usr/local/bin
    for bin in cargo rustc rustup; do
        nspawn "ln -sf /usr/local/cargo/bin/$bin /usr/local/bin/$bin 2>/dev/null || true"
    done

    # Cargo global config — lld linker, shared cache
    mkdir -p "$ROOTFS/usr/local/cargo"
    cat > "$ROOTFS/usr/local/cargo/config.toml" <<'TOML'
[net]
git-fetch-with-cli = true

[build]
jobs = 0  # use all CPUs

[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=lld"]
TOML

    progress "Installing cargo-binstall …"
    nspawn_soft "cargo install cargo-binstall --locked"
    nspawn "ln -sf /usr/local/cargo/bin/cargo-binstall /usr/local/bin/cargo-binstall 2>/dev/null || true"

    progress "Installing just (COSMIC build system) …"
    nspawn_soft "cargo binstall just --no-confirm || cargo install just --locked"

    stamp_done 3
    ok "Phase 3 complete — Rust toolchain ready."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 4 – uutils/coreutils (replaces GNU coreutils)
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 4 && $END_PHASE -ge 4 ]]; then
    phase_banner 4 "uutils/coreutils — Rust replacement for GNU coreutils"

    progress "Installing uutils-coreutils …"
    nspawn_soft "cargo binstall uutils-coreutils --no-confirm \
        || cargo install uutils-coreutils --locked"

    # Shim directory: /usr/local/lib/uutils takes priority in PATH
    nspawn "mkdir -p /usr/local/lib/uutils"

    UUTILS_TOOLS=(
        base32 base64 basename cat chgrp chmod chown chroot cksum comm
        cp csplit cut date dd df dir dircolors dirname du echo env expand
        expr factor false fmt fold groups head hostid hostname id install
        join kill link ln logname ls md5sum mkdir mkfifo mknod mktemp mv
        nice nl nohup nproc numfmt od paste pathchk pinky pr printenv
        printf ptx pwd readlink realpath rm rmdir seq sha1sum sha224sum
        sha256sum sha3-224sum sha3-256sum sha3-384sum sha3-512sum
        sha384sum sha512sum shred shuf sleep sort split stat stdbuf sum
        sync tail tee test timeout touch tr true truncate tsort tty uname
        unexpand uniq unlink uptime users vdir wc who whoami yes
    )

    for tool in "${UUTILS_TOOLS[@]}"; do
        nspawn "ln -sf /usr/local/cargo/bin/coreutils /usr/local/lib/uutils/$tool 2>/dev/null || true"
    done

    # Wrapper script for uutils-shim so fish shell gets it too
    cat >> "$ROOTFS/etc/profile.d/01-rust.sh" <<'PROF'
export PATH="/usr/local/lib/uutils:$PATH"
PROF

    stamp_done 4
    ok "Phase 4 complete — uutils shimmed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 5 – Rust CLI tool stack
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 5 && $END_PHASE -ge 5 ]]; then
    phase_banner 5 "Rust CLI tool stack"

    # Array of: "crate_name:binary_name"  (binary_name = symlink if different)
    CARGO_TOOLS=(
        "lsd:lsd"
        "bat:bat"
        "atuin:atuin"
        "git-delta:delta"
        "du-dust:dust"
        "fd-find:fd"
        "hyperfine:hyperfine"
        "procs:procs"
        "rm-improved:rip"
        "ripgrep:rg"
        "rnr:rnr"
        "sd:sd"
        "skim:sk"
        "tealdeer:tldr"
        "kibi:kibi"
        "topgrade:topgrade"
        "xcp:xcp"
        "mprocs:mprocs"
        "starship:starship"
        "zoxide:zoxide"
        "helix:hx"
        "joshuto:joshuto"
        "gitui:gitui"
        "bottom:btm"
        "television:tv"
        "bandwhich:bandwhich"
        "systeroid:systeroid"
        "cargo-update:cargo-install-update"
        "dysk:dysk"
        "lfs:lfs"
        "ruplacer:ruplacer"
    )

    for entry in "${CARGO_TOOLS[@]}"; do
        crate="${entry%%:*}"
        bin="${entry##*:}"
        progress "Installing $crate …"
        nspawn_soft "cargo binstall '$crate' --no-confirm \
            || cargo install '$crate' --locked"
        # Ensure binary is in /usr/local/bin under its canonical name
        nspawn "ln -sf /usr/local/cargo/bin/$bin /usr/local/bin/$bin 2>/dev/null || true"
    done

    # tealdeer: pre-fetch the cache so tldr works offline immediately
    nspawn_soft "tldr --update 2>/dev/null || true"

    # atuin: initialise database
    nspawn_soft "atuin init bash --disable-up-arrow 2>/dev/null || true"

    # astral uv (Python package manager — faster pip)
    progress "Installing astral-uv …"
    nspawn "curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh"

    # ruff (Python linter from Astral)
    nspawn_soft "cargo binstall ruff --no-confirm || cargo install ruff --locked"
    nspawn "ln -sf /usr/local/cargo/bin/ruff /usr/local/bin/ruff 2>/dev/null || true"

    # brush (Rust bash compatibility shell)
    progress "Installing brush shell …"
    nspawn_soft "cargo binstall brush-shell --no-confirm || cargo install brush-shell --locked"
    nspawn "ln -sf /usr/local/cargo/bin/brush /usr/local/bin/brush 2>/dev/null || true"
    # Register brush as an available shell
    nspawn "grep -qxF '/usr/local/bin/brush' /etc/shells \
        || echo '/usr/local/bin/brush' >> /etc/shells"
    # Make brush the system bash layer (still keeps /bin/bash; brush is additive)
    cat > "$ROOTFS/etc/profile.d/02-brush.sh" <<'PROF'
# brush — Rust bash compatibility shell.
# Invoked automatically for POSIX scripts that use #!/usr/bin/env bash
# while fish remains the interactive default.
export BRUSH_COMPAT=1
PROF

    # Register all additional shells
    nspawn "grep -qxF '/usr/bin/fish' /etc/shells || echo '/usr/bin/fish' >> /etc/shells"

    stamp_done 5
    ok "Phase 5 complete — Rust CLI tools installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 6 – Additional package managers
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 6 && $END_PHASE -ge 6 ]]; then
    phase_banner 6 "Additional package managers (AM, soar, pacstall, cargo-binstall)"

    # ── AM (AppImage manager) ──────────────────────────────────────────
    progress "Installing AM (AppImage manager) …"
    nspawn_soft "curl -fsSL https://raw.githubusercontent.com/ivan-hc/AM/main/AM \
        -o /usr/local/bin/am && chmod +x /usr/local/bin/am"

    # ── soar ──────────────────────────────────────────────────────────
    progress "Installing soar …"
    nspawn_soft "curl -fsSL https://raw.githubusercontent.com/pkgforge/soar/main/install.sh \
        | SOAR_INSTALL_DIR=/usr/local/bin sh"

    # ── pacstall ──────────────────────────────────────────────────────
    progress "Installing pacstall …"
    nspawn_soft "curl -fsSL https://pacstall.dev/q/install | bash"

    # ── npm (already installed via apt; upgrade to latest) ────────────
    nspawn_soft "npm install -g npm@latest"

    # ── flatpak + flathub ─────────────────────────────────────────────
    progress "Adding Flathub remote …"
    nspawn "flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true"

    # ── pixi (conda-based, for ML/data science packages) ─────────────
    progress "Installing pixi …"
    nspawn_soft "curl -fsSL https://pixi.sh/install.sh | PIXI_HOME=/usr/local sh"

    # ── fnm (Node.js version manager) ────────────────────────────────
    progress "Installing fnm …"
    nspawn_soft "curl -fsSL https://fnm.vercel.app/install \
        | FNM_DIR=/usr/local/fnm sh"
    nspawn "ln -sf /usr/local/fnm/fnm /usr/local/bin/fnm 2>/dev/null || true"

    # Profile entries for all extra PMs
    cat > "$ROOTFS/etc/profile.d/03-package-managers.sh" <<'PROF'
# AM (AppImages)
export PATH="$HOME/.local/bin:$PATH"
# pixi
export PATH="/usr/local/bin:$PATH"
# fnm
export PATH="/usr/local/fnm:$PATH"
eval "$(fnm env --use-on-cd 2>/dev/null)" 2>/dev/null || true
PROF

    stamp_done 6
    ok "Phase 6 complete — extra package managers installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 7 – COSMIC desktop (no cosmic-launcher, no cosmic-term, no cosmic-store)
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 7 && $END_PHASE -ge 7 ]]; then
    phase_banner 7 "COSMIC desktop environment"

    COSMIC_SRC="$ROOTFS/usr/local/src/cosmic-epoch"

    if [[ ! -d "$COSMIC_SRC/.git" ]]; then
        progress "Cloning cosmic-epoch …"
        git clone --recursive https://github.com/pop-os/cosmic-epoch "$COSMIC_SRC"
    else
        git -C "$COSMIC_SRC" pull --ff-only || true
        git -C "$COSMIC_SRC" submodule update --init --recursive || true
    fi

    # Patch the root justfile to exclude replaced components
    JUSTFILE="$COSMIC_SRC/justfile"
    cp "$JUSTFILE" "${JUSTFILE}.bak"
    for component in cosmic-launcher cosmic-term cosmic-store; do
        progress "Excluding $component from COSMIC build …"
        sed -i "s|^\(.*just.*$component.*\)$|# LILITH-EXCLUDED: \1|g" "$JUSTFILE" || true
        sed -i "s| $component||g" "$JUSTFILE" || true
    done

    progress "Building COSMIC (this will take a long time) …"
    nspawn "cd /usr/local/src/cosmic-epoch \
        && export JOBS=$JOBS \
        && just -j $JOBS all 2>&1"

    progress "Installing COSMIC …"
    nspawn "cd /usr/local/src/cosmic-epoch && just install PREFIX=/usr"

    # COSMIC panel: add logomenu slot (applied in phase 9)
    # Remove cosmic-store from MIME defaults (Offerings will replace it)
    nspawn "sed -i 's|cosmic-store.desktop|offerings.desktop|g' \
        /usr/share/applications/mimeinfo.cache 2>/dev/null || true"

    stamp_done 7
    ok "Phase 7 complete — COSMIC desktop installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 8 – Soulless Launcher (dock launcher, replaces cosmic-launcher)
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 8 && $END_PHASE -ge 8 ]]; then
    phase_banner 8 "Soulless Launcher"

    SOUL_SRC="$ROOTFS/usr/local/src/Soulless-Launcher"
    if [[ ! -d "$SOUL_SRC/.git" ]]; then
        git clone --depth=1 https://github.com/hmrdsmoke/Soulless-Launcher "$SOUL_SRC"
    else
        git -C "$SOUL_SRC" pull --ff-only || true
    fi

    # Copy the custom background into the source tree before building
    if [[ -f "$SOULLESS_BG" ]]; then
        cp "$SOULLESS_BG" "$SOUL_SRC/background.jpg" 2>/dev/null || true
        cp "$SOULLESS_BG" "$SOUL_SRC/assets/background.jpg" 2>/dev/null || true
        cp "$SOULLESS_BG" "$SOUL_SRC/assets/wallpaper.jpg" 2>/dev/null || true
        # Also install to a system location for runtime use
        mkdir -p "$ROOTFS/usr/share/soulless-launcher"
        cp "$SOULLESS_BG" "$ROOTFS/usr/share/soulless-launcher/background.jpeg"
    fi

    # Build: try Cargo → CMake → Make → Electron/npm in order
    nspawn "
        set -e
        cd /usr/local/src/Soulless-Launcher

        if [[ -f Cargo.toml ]]; then
            cargo build --release -j $JOBS
            find target/release -maxdepth 1 -type f -executable \
                ! -name '*.d' ! -name '*.so' \
                | xargs -I{} install -Dm755 {} /usr/local/bin/

        elif [[ -f package.json ]]; then
            npm ci
            npm run build 2>/dev/null || true
            npm install -g --prefix /usr/local .

        elif [[ -f CMakeLists.txt ]]; then
            cmake -B build -DCMAKE_BUILD_TYPE=Release \
                  -DCMAKE_INSTALL_PREFIX=/usr -GNinja
            ninja -C build -j $JOBS
            ninja -C build install

        elif [[ -f Makefile ]]; then
            make -j $JOBS PREFIX=/usr
            make install PREFIX=/usr
        fi
    " || warn "Soulless-Launcher build failed – will install AppImage fallback if available."

    # .desktop entry — dock/panel aware
    cat > "$ROOTFS/usr/share/applications/soulless-launcher.desktop" <<EOF
[Desktop Entry]
Name=Soulless Launcher
Comment=Lilith application launcher and dock
Exec=soulless-launcher
Icon=/usr/share/soulless-launcher/background.jpeg
Type=Application
Categories=Utility;
X-COSMIC-Priority=launcher
StartupNotify=false
EOF

    # Autostart (shown as dock before login)
    mkdir -p "$ROOTFS/etc/xdg/autostart"
    cat > "$ROOTFS/etc/xdg/autostart/soulless-launcher.desktop" <<EOF
[Desktop Entry]
Name=Soulless Launcher
Exec=soulless-launcher
Icon=/usr/share/soulless-launcher/background.jpeg
Type=Application
X-GNOME-Autostart-enabled=true
X-COSMIC-Priority=launcher
EOF

    # Disable cosmic-launcher autostart so Soulless is the only launcher
    rm -f "$ROOTFS/etc/xdg/autostart/cosmic-launcher.desktop" 2>/dev/null || true

    stamp_done 8
    ok "Phase 8 complete — Soulless Launcher installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 9 – cosmic-ext-applet-logomenu (panel logo button)
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 9 && $END_PHASE -ge 9 ]]; then
    phase_banner 9 "cosmic-ext-applet-logomenu (Lilith panel logo)"

    LOGO_SRC="$ROOTFS/usr/local/src/cosmic-ext-applet-logomenu"
    if [[ ! -d "$LOGO_SRC/.git" ]]; then
        git clone --depth=1 \
            https://github.com/cosmic-utils/cosmic-ext-applet-logomenu \
            "$LOGO_SRC"
    else
        git -C "$LOGO_SRC" pull --ff-only || true
    fi

    # Inject the Lilith SVG logo before building
    if [[ -f "$LOGO_SVG" ]]; then
        # Try common asset paths used by COSMIC applets
        for dest in \
            "$LOGO_SRC/assets/logo.svg" \
            "$LOGO_SRC/src/logo.svg" \
            "$LOGO_SRC/res/logo.svg" \
            "$LOGO_SRC/data/logo.svg"
        do
            mkdir -p "$(dirname "$dest")"
            cp "$LOGO_SVG" "$dest" 2>/dev/null || true
        done
        # Copy to system location for runtime
        mkdir -p "$ROOTFS/usr/share/cosmic-ext-applet-logomenu"
        cp "$LOGO_SVG" "$ROOTFS/usr/share/cosmic-ext-applet-logomenu/logo.svg"
    fi

    # Build the Rust applet
    nspawn "cd /usr/local/src/cosmic-ext-applet-logomenu \
        && cargo build --release -j $JOBS \
        && find target/release -maxdepth 1 -type f -executable \
            ! -name '*.d' ! -name '*.so' \
            | xargs -I{} install -Dm755 {} /usr/local/bin/" \
        || warn "logomenu applet build failed – applet may not appear in panel."

    stamp_done 9
    ok "Phase 9 complete — logomenu applet installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 10 – Hyper.js terminal (replaces cosmic-term)
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 10 && $END_PHASE -ge 10 ]]; then
    phase_banner 10 "Hyper.js terminal"

    progress "Resolving Hyper.js latest release …"
    HYPER_DEB_URL="$(gh_latest_url "vercel/hyper" "_amd64.deb")"
    if [[ -z "$HYPER_DEB_URL" ]]; then
        HYPER_DEB_URL="https://releases.hyper.is/download/deb"
        warn "Could not resolve Hyper release URL; using fallback."
    fi

    progress "Downloading Hyper: $HYPER_DEB_URL …"
    wget -q -O "$CACHE_DIR/hyper_latest_amd64.deb" "$HYPER_DEB_URL"
    cp "$CACHE_DIR/hyper_latest_amd64.deb" "$ROOTFS/tmp/hyper.deb"
    nspawn "dpkg -i /tmp/hyper.deb || apt-get install -f -y"
    rm -f "$ROOTFS/tmp/hyper.deb"

    # Set as default terminal emulator
    nspawn "update-alternatives --install /usr/bin/x-terminal-emulator \
        x-terminal-emulator /usr/bin/hyper 60 2>/dev/null || true"
    nspawn "update-alternatives --set x-terminal-emulator /usr/bin/hyper \
        2>/dev/null || true"

    # Hyper default config: fish shell, JetBrains Mono, slight transparency
    mkdir -p "$ROOTFS/etc/skel/.config/Hyper"
    cat > "$ROOTFS/etc/skel/.config/Hyper/.hyper.js" <<'HYPER'
module.exports = {
  config: {
    shell: '/usr/bin/fish',
    shellArgs: ['--login'],
    fontSize: 13,
    fontFamily: '"JetBrains Mono NF", "JetBrains Mono", "Fira Code", monospace',
    fontWeight: 'normal',
    fontWeightBold: 'bold',
    cursorShape: 'BEAM',
    cursorBlink: true,
    copyOnSelect: false,
    defaultSSHApp: true,
    opacity: 0.96,
    vibrancy: 'dark',
    css: '',
    termCSS: '',
    modifierKeys: { altIsMeta: false },
    scrollback: 10000,
    bell: 'SOUND',
    colors: {
      black:   '#000000',
      red:     '#ff5555',
      green:   '#50fa7b',
      yellow:  '#f1fa8c',
      blue:    '#bd93f9',
      magenta: '#ff79c6',
      cyan:    '#8be9fd',
      white:   '#bfbfbf',
      lightBlack:   '#4d4d4d',
      lightRed:     '#ff6e67',
      lightGreen:   '#5af78e',
      lightYellow:  '#f4f99d',
      lightBlue:    '#caa9fa',
      lightMagenta: '#ff92d0',
      lightCyan:    '#9aedfe',
      lightWhite:   '#e6e6e6',
    },
  },
  plugins: [],
  localPlugins: [],
  keymaps: {},
};
HYPER

    stamp_done 10
    ok "Phase 10 complete — Hyper.js installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 11 – Browsers: BrowserOS + Hellfire
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 11 && $END_PHASE -ge 11 ]]; then
    phase_banner 11 "Browsers (BrowserOS + Hellfire)"

    mkdir -p "$ROOTFS/opt/lilith-browsers"

    # ── BrowserOS AppImage ──────────────────────────────────────────────
    progress "Resolving BrowserOS AppImage …"
    BROWSEROS_URL="$(gh_latest_url "BlancoBAM/BrowserOS" "x86_64.AppImage")"
    if [[ -z "$BROWSEROS_URL" ]]; then
        # Fallback to local copy if present
        LOCAL_BROWSEROS=$(find /home/aegon/workspace/Lilith-Linux -name "BrowserOS*.AppImage" | head -1)
        if [[ -n "$LOCAL_BROWSEROS" ]]; then
            BROWSEROS_URL="local:$LOCAL_BROWSEROS"
        else
            warn "BrowserOS AppImage not found — skipping."
        fi
    fi

    if [[ -n "$BROWSEROS_URL" ]]; then
        if [[ "$BROWSEROS_URL" == local:* ]]; then
            cp "${BROWSEROS_URL#local:}" "$ROOTFS/opt/lilith-browsers/BrowserOS.AppImage"
        else
            wget -q -O "$CACHE_DIR/BrowserOS.AppImage" "$BROWSEROS_URL" \
                || warn "BrowserOS download failed"
            [[ -f "$CACHE_DIR/BrowserOS.AppImage" ]] && \
                cp "$CACHE_DIR/BrowserOS.AppImage" "$ROOTFS/opt/lilith-browsers/BrowserOS.AppImage"
        fi
    fi

    if [[ -f "$ROOTFS/opt/lilith-browsers/BrowserOS.AppImage" ]]; then
        chmod +x "$ROOTFS/opt/lilith-browsers/BrowserOS.AppImage"
        nspawn "ln -sf /opt/lilith-browsers/BrowserOS.AppImage /usr/local/bin/browseros 2>/dev/null || true"
        cat > "$ROOTFS/usr/share/applications/browseros.desktop" <<EOF
[Desktop Entry]
Name=BrowserOS
Comment=Lilith default web browser
Exec=browseros %U
Icon=browseros
Type=Application
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
StartupNotify=true
EOF
    fi

    # ── Hellfire Browser ───────────────────────────────────────────────
    progress "Resolving Hellfire browser …"
    HELLFIRE_URL="$(gh_latest_url "CYFARE/HellFire" "linux-x86_64.tar.xz" 2>/dev/null)" \
        || HELLFIRE_URL=""

    if [[ -z "$HELLFIRE_URL" ]]; then
        # Known URL pattern
        HELLFIRE_URL="https://github.com/CYFARE/HellFire/releases/download/v152.0a1_FP2/hellfire-152.0a1.en-US.linux-x86_64.tar.xz"
    fi

    progress "Downloading Hellfire: $HELLFIRE_URL …"
    wget -q -O "$CACHE_DIR/hellfire.tar.xz" "$HELLFIRE_URL" \
        || warn "Hellfire download failed"

    if [[ -f "$CACHE_DIR/hellfire.tar.xz" ]]; then
        mkdir -p "$ROOTFS/opt/lilith-browsers/hellfire"
        tar -xJf "$CACHE_DIR/hellfire.tar.xz" \
            -C "$ROOTFS/opt/lilith-browsers/hellfire" \
            --strip-components=1 2>/dev/null || true
        nspawn "ln -sf /opt/lilith-browsers/hellfire/hellfire /usr/local/bin/hellfire 2>/dev/null \
            || ln -sf /opt/lilith-browsers/hellfire/firefox /usr/local/bin/hellfire 2>/dev/null || true"
        cat > "$ROOTFS/usr/share/applications/hellfire.desktop" <<EOF
[Desktop Entry]
Name=Hellfire
Comment=Privacy-focused Firefox fork
Exec=hellfire %U
Icon=/opt/lilith-browsers/hellfire/browser/chrome/icons/default/default128.png
Type=Application
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
StartupNotify=true
EOF
    fi

    # Set BrowserOS as the MIME default, Hellfire as secondary
    cat > "$ROOTFS/usr/share/applications/defaults.list" <<EOF
[Default Applications]
x-scheme-handler/http=browseros.desktop
x-scheme-handler/https=browseros.desktop
text/html=browseros.desktop
EOF

    stamp_done 11
    ok "Phase 11 complete — browsers installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 12 – BlancoBAM custom applications
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 12 && $END_PHASE -ge 12 ]]; then
    phase_banner 12 "BlancoBAM custom applications"

    # Generic builder: clone + detect build system
    build_blanco_app() {
        local repo="$1"
        local src="$ROOTFS/usr/local/src/$repo"
        progress "Building $repo …"

        [[ -d "$src/.git" ]] || git clone --depth=1 "$BLANCO/$repo" "$src"

        nspawn "
            set -e
            SRC=/usr/local/src/$repo
            cd \$SRC

            if [[ -f Cargo.toml ]]; then
                cargo build --release -j $JOBS
                find target/release -maxdepth 1 -type f -executable \
                    ! -name '*.d' ! -name '*.so' \
                    | xargs -I{} install -Dm755 {} /usr/local/bin/
                find target/release -name '*.desktop' -exec install -Dm644 {} /usr/share/applications/ \; 2>/dev/null || true

            elif [[ -f package.json ]]; then
                npm ci
                npm run build 2>/dev/null || true
                npm install -g --prefix /usr/local .

            elif [[ -f pyproject.toml ]] || [[ -f setup.py ]]; then
                pip install --break-system-packages -e .

            elif [[ -f CMakeLists.txt ]]; then
                cmake -B build -DCMAKE_BUILD_TYPE=Release \
                      -DCMAKE_INSTALL_PREFIX=/usr -GNinja
                ninja -C build -j $JOBS
                ninja -C build install

            elif [[ -f Makefile ]]; then
                make -j $JOBS PREFIX=/usr && make install PREFIX=/usr
            fi

            # Install desktop files
            find . -maxdepth 3 -name '*.desktop' \
                -exec install -Dm644 {} /usr/share/applications/ \; 2>/dev/null || true
            # Install icons
            find . -maxdepth 4 \( -name '*.png' -o -name '*.svg' \) -path '*/icons/*' \
                -exec install -Dm644 {} /usr/share/pixmaps/ \; 2>/dev/null || true
        " || warn "Build failed for $repo – check log."
    }

    # ── Offerings (app store / replaces cosmic-store) ──────────────────
    build_blanco_app "Offerings"
    cat > "$ROOTFS/usr/share/applications/offerings.desktop" <<EOF
[Desktop Entry]
Name=Offerings
Comment=Lilith application store
Exec=offerings
Icon=offerings
Type=Application
Categories=System;PackageManager;
X-COSMIC-DefaultAppStore=true
EOF

    # ── s8n-system ────────────────────────────────────────────────────
    build_blanco_app "S8n-System"

    # ── Tweakers ──────────────────────────────────────────────────────
    build_blanco_app "Tweakers"

    # ── Lilim (AI assistant) ──────────────────────────────────────────
    build_blanco_app "Lilim"

    # ── Lilith-TTS ────────────────────────────────────────────────────
    build_blanco_app "Lilith-TTS"

    # ── Ouija-Pad (text editor) ───────────────────────────────────────
    build_blanco_app "Ouija-Pad"

    # ── Stake ─────────────────────────────────────────────────────────
    build_blanco_app "Stake"

    # ── Shapeshifter ─────────────────────────────────────────────────
    build_blanco_app "Shapeshifter"

    # ── cosmic-connect ────────────────────────────────────────────────
    progress "Building cosmic-connect …"
    CC_SRC="$ROOTFS/usr/local/src/cosmic-connect"
    [[ -d "$CC_SRC/.git" ]] || git clone --depth=1 \
        https://github.com/BlancoBAM/cosmic-connect "$CC_SRC" \
        || git clone --depth=1 \
        https://gitlab.com/BlancoBAM/cosmic-connect "$CC_SRC" || true

    if [[ -d "$CC_SRC/.git" ]]; then
        nspawn "cd /usr/local/src/cosmic-connect \
            && cargo build --release -j $JOBS \
            && find target/release -maxdepth 1 -type f -executable \
                ! -name '*.d' ! -name '*.so' \
                | xargs -I{} install -Dm755 {} /usr/local/bin/ \
            || just install 2>/dev/null || true"
    fi

    # ── s8n-fetch (afetch-powered system info) ────────────────────────
    progress "Installing afetch + s8n-fetch config …"
    nspawn_soft "cargo binstall afetch --no-confirm || cargo install afetch --locked"
    nspawn "ln -sf /usr/local/cargo/bin/afetch /usr/local/bin/afetch 2>/dev/null || true"

    S8N_FETCH_SRC="$ROOTFS/usr/local/src/S8n-Fetch"
    if [[ ! -d "$S8N_FETCH_SRC/.git" ]]; then
        git_sync "$BLANCO/S8n-Fetch" "$S8N_FETCH_SRC"
    fi
    mkdir -p "$ROOTFS/etc/skel/.config/afetch"
    # Copy everything except .git
    rsync -a --exclude='.git' "$S8N_FETCH_SRC/" \
        "$ROOTFS/etc/skel/.config/afetch/" 2>/dev/null || \
    cp -r "$S8N_FETCH_SRC/." "$ROOTFS/etc/skel/.config/afetch/" 2>/dev/null || true

    stamp_done 12
    ok "Phase 12 complete — BlancoBAM apps installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 13 – Shell environment (fish + brush + starship + aliases)
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 13 && $END_PHASE -ge 13 ]]; then
    phase_banner 13 "Shell environment"

    # ── Set fish as the default interactive shell for all users ────────
    nspawn "chsh -s /usr/bin/fish root"
    sed -i 's|^SHELL=.*|SHELL=/usr/bin/fish|' "$ROOTFS/etc/default/useradd" 2>/dev/null || true

    # ── /etc/skel/.bashrc → uses brush (Rust bash compat layer) ───────
    # Any script that runs #!/bin/bash will use the system bash;
    # interactive bash sessions are re-exec'd into fish or brush.
    cat > "$ROOTFS/etc/skel/.bashrc" <<'BASH'
# Lilith OS — .bashrc
# Interactive sessions re-launch into fish (preferred) or brush.
if [[ $- == *i* ]]; then
    if command -v fish &>/dev/null; then
        exec fish
    elif command -v brush &>/dev/null; then
        exec brush
    fi
fi
BASH

    # ── Global fish config ─────────────────────────────────────────────
    mkdir -p "$ROOTFS/etc/fish"
    cat > "$ROOTFS/etc/fish/config.fish" <<'FISH'
# ═══════════════════════════════════════════════════════════════════
#  Lilith OS — global fish shell configuration
# ═══════════════════════════════════════════════════════════════════

# PATH additions
fish_add_path /usr/local/lib/uutils   # uutils (Rust coreutils shims)
fish_add_path /usr/local/cargo/bin    # Rust binaries
fish_add_path /usr/local/bin          # General local binaries
fish_add_path "$HOME/.local/bin"      # User local binaries

# ── Starship prompt ───────────────────────────────────────────────
if command -q starship
    starship init fish | source
end

# ── Atuin (shell history) ─────────────────────────────────────────
if command -q atuin
    atuin init fish | source
end

# ── Zoxide (smart cd) ─────────────────────────────────────────────
if command -q zoxide
    zoxide init fish | source
end

# ── S8n-Fetch (system info on new shell) ─────────────────────────
if status is-interactive
    afetch 2>/dev/null || true
end

# ── Modern CLI aliases (Rust tool replacements) ───────────────────
# Listing
alias ls='lsd'
alias ll='lsd -lAh --git'
alias la='lsd -A'
alias lt='lsd --tree'
alias lsa='lsd -lAh --git'

# File viewing
alias cat='bat --paging=never'
alias less='bat --paging=always'
alias more='bat --paging=always'

# Search / find
alias find='fd'
alias grep='rg'
alias fzf='sk'

# File operations
alias rm='rip'
alias cp='xcp'
alias du='dust'
alias df='dysk'

# System / process
alias ps='procs'
alias htop='btm'
alias top='btm'

# Git diffs
alias diff='delta'

# DNS
alias dig='dog'

# Inline sed replacement
alias sed='sd'

# Rename
alias rename='rnr'

# Benchmarking
alias bench='hyperfine'

# Quick editors
alias nano='kibi'
alias vi='kibi'
alias vim='kibi'

# tldr
alias man='tldr'

# Python / UV
alias pip='uv pip'
alias pip3='uv pip'
alias venv='uv venv'

# Bulk replace in files
alias replace='ruplacer'

# Package managers
alias upgrade='topgrade'
alias update='s8n upd8'
alias install='s8n stall'
alias search='s8n srch'
alias uninstall='s8n rm'

# Sysctl
alias sysctl='systeroid'

# ── Environment variables ─────────────────────────────────────────
set -gx EDITOR kibi
set -gx VISUAL kibi
set -gx PAGER "bat --paging=always"
set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
set -gx STARSHIP_CONFIG /etc/starship/starship.toml
set -gx CARGO_HOME /usr/local/cargo
set -gx RUSTUP_HOME /usr/local/rustup

# ── fnm (Node.js version manager) ─────────────────────────────────
if command -q fnm
    fnm env --use-on-cd | source
end
FISH

    # Copy into /etc/skel so every new user inherits the config
    mkdir -p "$ROOTFS/etc/skel/.config/fish"
    cp "$ROOTFS/etc/fish/config.fish" \
       "$ROOTFS/etc/skel/.config/fish/config.fish"

    # Append afetch to skel fish config (per-user override)
    cat >> "$ROOTFS/etc/skel/.config/fish/config.fish" <<'FISH'

# ── S8n-Fetch (per-user system info) ─────────────────────────────
if status is-interactive
    if command -q afetch
        afetch --config ~/.config/afetch/config 2>/dev/null || afetch 2>/dev/null || true
    end
end
FISH

    # ── Starship configuration ─────────────────────────────────────────
    mkdir -p "$ROOTFS/etc/starship"
    cat > "$ROOTFS/etc/starship/starship.toml" <<'STAR'
# Lilith OS — Starship prompt
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[╭─](bold purple)$os$username$hostname$directory$git_branch$git_status$rust$python$nodejs$cmd_duration
[╰─](bold purple)$character"""

[os]
disabled = false
style    = "bold purple"

[os.symbols]
Linux   = "󰌽 "
Ubuntu  = " "

[username]
style_user = "bold cyan"
format     = "[$user]($style) "
show_always = false

[hostname]
style  = "bold dimmed cyan"
format = "[@$hostname]($style) "

[directory]
style             = "bold blue"
truncation_length = 4
home_symbol       = "󰠦 "

[git_branch]
style  = "bold green"
symbol = " "

[git_status]
style = "bold red"

[rust]
style  = "bold #f74c00"
symbol = " "

[python]
style  = "bold yellow"
symbol = " "

[nodejs]
style  = "bold green"
symbol = " "

[cmd_duration]
min_time = 2_000
style    = "bold yellow"
format   = " took [$duration]($style)"

[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"
STAR

    stamp_done 13
    ok "Phase 13 complete — shell environment configured."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 14 – Themes, wallpapers, fonts, icons (Fluent default)
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 14 && $END_PHASE -ge 14 ]]; then
    phase_banner 14 "Themes, wallpapers, fonts, icons"

    # ── Fonts ──────────────────────────────────────────────────────────
    progress "Installing fonts …"
    mkdir -p "$ROOTFS/usr/share/fonts/lilith"

    if [[ -d "$ASSETS_DIR/fonts" ]]; then
        find "$ASSETS_DIR/fonts" \
            \( -name "*.ttf" -o -name "*.otf" -o -name "*.woff2" -o -name "*.zip" \) \
            | while read -r f; do
            if [[ "$f" == *.zip ]]; then
                unzip -o -j "$f" "*.ttf" "*.otf" \
                    -d "$ROOTFS/usr/share/fonts/lilith/" 2>/dev/null || true
            else
                cp "$f" "$ROOTFS/usr/share/fonts/lilith/" 2>/dev/null || true
            fi
        done
    fi

    # JetBrains Mono Nerd Font (used by Hyper, terminal, starship)
    progress "Installing JetBrains Mono Nerd Font …"
    JBM_URL="$(gh_latest_url "ryanoasis/nerd-fonts" "JetBrainsMono.zip")"
    if [[ -n "$JBM_URL" ]]; then
        wget -q -O "$CACHE_DIR/JetBrainsMono.zip" "$JBM_URL" \
            && unzip -o -j "$CACHE_DIR/JetBrainsMono.zip" "*.ttf" \
                -d "$ROOTFS/usr/share/fonts/lilith/" 2>/dev/null || true
    fi

    nspawn "fc-cache -f 2>/dev/null || true"

    # ── Wallpapers ────────────────────────────────────────────────────
    progress "Installing wallpapers …"
    mkdir -p "$ROOTFS/usr/share/backgrounds/lilith"
    if [[ -d "$ASSETS_DIR/wallpapers" ]]; then
        cp "$ASSETS_DIR/wallpapers/"* \
           "$ROOTFS/usr/share/backgrounds/lilith/" 2>/dev/null || true
    fi
    # Set lil-logo4.jpeg as the default COSMIC background
    if [[ -f "$ROOTFS/usr/share/backgrounds/lilith/lil-logo4.jpeg" ]]; then
        mkdir -p "$ROOTFS/etc/skel/.local/share/gnome-background-properties" 2>/dev/null || true
        # COSMIC background via gsettings-like config
        mkdir -p "$ROOTFS/etc/skel/.config/cosmic"
        cat > "$ROOTFS/etc/skel/.config/cosmic/com.system76.CosmicBackground" <<EOF
[default]
source="Wallpaper"
wallpaper_path="/usr/share/backgrounds/lilith/lil-logo4.jpeg"
scaling_mode="Zoom"
EOF
        # Also set via skel cosmic-settings
        mkdir -p "$ROOTFS/etc/skel/.local/share/cosmic"
    fi

    # ── Icons ─────────────────────────────────────────────────────────
    progress "Installing icons …"
    mkdir -p "$ROOTFS/usr/share/icons"
    if [[ -d "$ASSETS_DIR/icons" ]]; then
        cp -r "$ASSETS_DIR/icons/"* "$ROOTFS/usr/share/icons/" 2>/dev/null || true
    fi

    # ── Fluent Icon Theme (default) ───────────────────────────────────
    progress "Installing Fluent icon theme …"
    FLUENT_SRC="$ROOTFS/usr/local/src/Fluent-icon-theme"
    if [[ ! -d "$FLUENT_SRC/.git" ]]; then
        git clone --depth=1 \
            https://github.com/vinceliuice/Fluent-icon-theme "$FLUENT_SRC"
    fi
    nspawn "cd /usr/local/src/Fluent-icon-theme \
        && bash install.sh -d /usr/share/icons 2>&1 || true"

    # Set Fluent as the default icon theme for all users
    mkdir -p "$ROOTFS/etc/skel/.icons"
    cat > "$ROOTFS/etc/skel/.icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=Fluent-dark
EOF
    # GTK settings
    mkdir -p "$ROOTFS/etc/skel/.config/gtk-4.0"
    cat > "$ROOTFS/etc/skel/.config/gtk-4.0/settings.ini" <<EOF
[Settings]
gtk-icon-theme-name=Fluent-dark
gtk-cursor-theme-name=Breeze
gtk-font-name=Inter 11
EOF
    mkdir -p "$ROOTFS/etc/skel/.config/gtk-3.0"
    cat > "$ROOTFS/etc/skel/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-icon-theme-name=Fluent-dark
gtk-cursor-theme-name=Breeze
gtk-font-name=Inter 11
EOF

    # System-wide GTK default
    cat > "$ROOTFS/etc/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-icon-theme-name=Fluent-dark
gtk-cursor-theme-name=Breeze
gtk-font-name=Inter 11
EOF

    # ── COSMIC icon/theme defaults ────────────────────────────────────
    mkdir -p "$ROOTFS/etc/cosmic"
    cat > "$ROOTFS/etc/cosmic/com.system76.CosmicTheme" <<EOF
[default]
icon_theme="Fluent-dark"
EOF

    # Inter font (for UI text)
    progress "Installing Inter font …"
    nspawn_soft "apt-get install -y fonts-inter 2>/dev/null || true"
    if ! nspawn "fc-list | grep -qi inter 2>/dev/null"; then
        INTER_URL="$(gh_latest_url "rsms/inter" "Inter.zip")"
        [[ -n "$INTER_URL" ]] && \
            wget -q -O "$CACHE_DIR/Inter.zip" "$INTER_URL" && \
            unzip -o -j "$CACHE_DIR/Inter.zip" "*.ttf" \
                -d "$ROOTFS/usr/share/fonts/lilith/" 2>/dev/null || true
    fi
    nspawn "fc-cache -f 2>/dev/null || true"

    stamp_done 14
    ok "Phase 14 complete — themes, wallpapers, fonts, icons installed."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 15 – GRUB theme (lil-grub) + boot splash videos
# ══════════════════════════════════════════════════════════════════════════
# Uses the exact services/scripts proven-working in the cubic build:
#   lilith-early-boot.service  -> video on framebuffer BEFORE Plymouth (loops)
#   lilith-presplash.service   -> video AFTER Plymouth, BEFORE display-manager
# Both use mpv; early-boot uses fbdev, presplash tries DRM then fbdev fallback.
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 15 && $END_PHASE -ge 15 ]]; then
    phase_banner 15 "GRUB theme (lil-grub) + boot splash videos"

    # Ensure mpv is available (needed for both splash services)
    nspawn "apt-get install -y mpv 2>/dev/null || true"

    # Video destination inside the rootfs
    mkdir -p "$ROOTFS/usr/share/lilith/splash"

    # Video 1 = early-boot.mp4 (loops on framebuffer during kernel init)
    if [[ -f "$SPLASH_VIDEO_1" ]]; then
        progress "Installing early-boot video (video 1: $SPLASH_VIDEO_1) ..."
        cp "$SPLASH_VIDEO_1" "$ROOTFS/usr/share/lilith/splash/boot.mp4"
        chmod 644 "$ROOTFS/usr/share/lilith/splash/boot.mp4"
    else
        warn "SPLASH_VIDEO_1 not found at: $SPLASH_VIDEO_1"
    fi

    # Video 2 = login-splash.mp4 (plays once after Plymouth, before SDDM)
    if [[ -f "$SPLASH_VIDEO_2" ]]; then
        progress "Installing pre-login video (video 2: $SPLASH_VIDEO_2) ..."
        cp "$SPLASH_VIDEO_2" "$ROOTFS/usr/share/lilith/splash/login-splash.mp4"
        chmod 644 "$ROOTFS/usr/share/lilith/splash/login-splash.mp4"
    else
        warn "SPLASH_VIDEO_2 not found at: $SPLASH_VIDEO_2"
    fi

    # ── lilith-early-boot.sh ──────────────────────────────────────────
    mkdir -p "$ROOTFS/usr/local/bin"
    cat > "$ROOTFS/usr/local/bin/lilith-early-boot.sh" <<'SH'
#!/bin/bash
# Lilith Linux -- Early Boot Video Player
# Plays boot.mp4 on the framebuffer before Plymouth starts.
# systemd kills this via Conflicts=plymouth-start.service when Plymouth starts.
VIDEO="/usr/share/lilith/splash/boot.mp4"
[ -f "$VIDEO" ] || exit 0

printf '\033[?25l' > /dev/tty1 2>/dev/null || true

# Wait up to 6 s for /dev/fb0 (udev may not have run yet)
i=0
while [ $i -lt 30 ]; do
    [ -e /dev/fb0 ] && break
    sleep 0.2
    i=$((i + 1))
done

if [ ! -e /dev/fb0 ]; then
    printf '\033[?25h' > /dev/tty1 2>/dev/null || true
    exit 0
fi

exec mpv \
    --vo=fbdev \
    --really-quiet \
    --no-terminal \
    --no-osc \
    --no-osd-bar \
    --loop=inf \
    --hwdec=no \
    --audio-device=auto \
    --volume=100 \
    "$VIDEO" >/dev/null 2>&1
SH
    chmod +x "$ROOTFS/usr/local/bin/lilith-early-boot.sh"

    # ── lilith-presplash.sh ───────────────────────────────────────────
    cat > "$ROOTFS/usr/local/bin/lilith-presplash.sh" <<'SH'
#!/bin/bash
# Lilith Linux -- Pre-Login Splash
# Plays login-splash.mp4 ONCE after Plymouth quits, before the greeter.
VIDEO="/usr/share/lilith/splash/login-splash.mp4"
[ -f "$VIDEO" ] || exit 0

pkill -x mpv 2>/dev/null || true
sleep 0.3

chvt 1 2>/dev/null || true
printf '\033[?25l' > /dev/tty1 2>/dev/null || true
sleep 0.8

MPV_COMMON="--really-quiet --no-terminal --no-osc --no-osd-bar
            --loop=no --hwdec=no --volume=100
            --no-input-default-bindings"

VIDEO_PLAYED=0

# Try DRM first (bare metal + VirtIO-GPU VMs)
if ls /dev/dri/card* >/dev/null 2>&1; then
    for CARD in /dev/dri/card*; do
        if mpv --vo=drm --drm-device="$CARD" $MPV_COMMON "$VIDEO" >/dev/null 2>&1; then
            VIDEO_PLAYED=1
            break
        fi
    done
fi

# Fallback: fbdev
if [ "$VIDEO_PLAYED" -eq 0 ] && [ -e /dev/fb0 ]; then
    mpv --vo=fbdev $MPV_COMMON "$VIDEO" >/dev/null 2>&1 || true
fi

printf '\033[?25h' > /dev/tty1 2>/dev/null || true
exit 0
SH
    chmod +x "$ROOTFS/usr/local/bin/lilith-presplash.sh"

    # ── systemd: lilith-early-boot.service ───────────────────────────
    cat > "$ROOTFS/etc/systemd/system/lilith-early-boot.service" <<'SVC'
[Unit]
Description=Lilith Early Boot Video (lil-load)
Documentation=https://lilith.linux
DefaultDependencies=no
After=systemd-vconsole-setup.service
Before=plymouth-start.service sysinit.target
Conflicts=plymouth-start.service
ConditionPathExists=/usr/share/lilith/splash/boot.mp4

[Service]
Type=simple
ExecStart=/bin/bash /usr/local/bin/lilith-early-boot.sh
Restart=no
TimeoutStartSec=120
KillMode=process
StandardOutput=null
StandardError=null

[Install]
WantedBy=sysinit.target
SVC

    # ── systemd: lilith-presplash.service ────────────────────────────
    cat > "$ROOTFS/etc/systemd/system/lilith-presplash.service" <<'SVC'
[Unit]
Description=Lilith Pre-Login Splash
Documentation=https://lilith.linux
DefaultDependencies=no
After=plymouth-quit-wait.service systemd-user-sessions.service
Before=display-manager.service
Conflicts=getty@tty1.service
ConditionPathExists=/usr/share/lilith/splash/login-splash.mp4

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /usr/local/bin/lilith-presplash.sh
Restart=no
TimeoutStartSec=60
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=display-manager.service
SVC

    # Enable via systemctl + hard symlinks (safer in chroot than systemctl enable)
    nspawn "systemctl enable lilith-early-boot.service 2>/dev/null || true"
    nspawn "systemctl enable lilith-presplash.service  2>/dev/null || true"

    mkdir -p "$ROOTFS/etc/systemd/system/sysinit.target.wants"
    mkdir -p "$ROOTFS/etc/systemd/system/display-manager.service.wants"
    ln -sf /etc/systemd/system/lilith-early-boot.service \
        "$ROOTFS/etc/systemd/system/sysinit.target.wants/lilith-early-boot.service" \
        2>/dev/null || true
    ln -sf /etc/systemd/system/lilith-presplash.service \
        "$ROOTFS/etc/systemd/system/display-manager.service.wants/lilith-presplash.service" \
        2>/dev/null || true

    # ── Plymouth: lilith-blank (solid black -- stops purple Ubuntu frames) ─
    PLYMOUTH_BLANK="$ROOTFS/usr/share/plymouth/themes/lilith-blank"
    mkdir -p "$PLYMOUTH_BLANK"

    cat > "$PLYMOUTH_BLANK/lilith-blank.plymouth" <<'PLY'
[Plymouth Theme]
Name=Lilith Blank
Description=Solid black background -- Lilith boot video plays alongside
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/lilith-blank
ScriptFile=/usr/share/plymouth/themes/lilith-blank/lilith-blank.script
PLY

    cat > "$PLYMOUTH_BLANK/lilith-blank.script" <<'PLY'
Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);
PLY

    mkdir -p "$ROOTFS/etc/plymouth"
    cat > "$ROOTFS/etc/plymouth/plymouthd.conf" <<'PLY'
[Daemon]
Theme=lilith-blank
ShowDelay=0
DeviceTimeout=5
PLY

    nspawn_soft "update-alternatives --install \
        /usr/share/plymouth/themes/default.plymouth \
        default.plymouth \
        /usr/share/plymouth/themes/lilith-blank/lilith-blank.plymouth \
        100 2>/dev/null || true"
    nspawn_soft "plymouth-set-default-theme lilith-blank 2>/dev/null || true"
    nspawn_soft "update-initramfs -u -k all 2>/dev/null || true"

    # ── GRUB: lil-grub theme + proven cmdline ────────────────────────
    progress "Installing lil-grub theme ..."
    GRUB_THEME_SRC="$ROOTFS/usr/local/src/lilith-grub-theme"
    if [[ ! -d "$GRUB_THEME_SRC" ]]; then
        git_sync "$BLANCO/lilith-grub-theme" "$GRUB_THEME_SRC" 2>/dev/null \
            || warn "lilith-grub-theme not on GitHub yet -- checking cubic snapshot."
        if [[ ! -d "$GRUB_THEME_SRC/.git" ]]; then
            GRUB_SNAP="$(find /home/aegon/Lilith -name 'theme.txt' 2>/dev/null | head -1 | xargs -I{} dirname {})"
            if [[ -n "$GRUB_SNAP" ]]; then
                mkdir -p "$GRUB_THEME_SRC"
                cp -r "$GRUB_SNAP/." "$GRUB_THEME_SRC/"
            fi
        fi
    fi

    mkdir -p "$ROOTFS/boot/grub/themes/lilith"
    [[ -d "$GRUB_THEME_SRC" ]] && cp -r "$GRUB_THEME_SRC/." "$ROOTFS/boot/grub/themes/lilith/"

    # GRUB defaults -- exact values from the working cubic snapshot
    cat > "$ROOTFS/etc/default/grub" <<'GRUB'
# Lilith Linux -- GRUB configuration
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_DISTRIBUTOR="Lilith Linux"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 rd.systemd.show_status=false systemd.show_status=false vt.global_cursor_default=0"
GRUB_CMDLINE_LINUX=""
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_THEME="/boot/grub/themes/lilith/theme.txt"
GRUB_DISABLE_RECOVERY=true
GRUB

    nspawn_soft "update-grub 2>/dev/null || true"

    stamp_done 15
    ok "Phase 15 complete -- GRUB theme + boot splash videos installed."
fi


# ══════════════════════════════════════════════════════════════════════════
# PHASE 16 – System services, display manager, final configuration
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 16 && $END_PHASE -ge 16 ]]; then
    phase_banner 16 "System services & final configuration"

    # ── Hostname & hosts ──────────────────────────────────────────────
    echo "lilith" > "$ROOTFS/etc/hostname"
    cat > "$ROOTFS/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   lilith
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

    # ── Display manager: SDDM ─────────────────────────────────────────
    nspawn "systemctl enable sddm 2>/dev/null || true"
    mkdir -p "$ROOTFS/etc/sddm.conf.d"
    cat > "$ROOTFS/etc/sddm.conf.d/lilith.conf" <<EOF
[General]
DefaultSession=cosmic.desktop
InputMethod=

[Theme]
Current=breeze

[Users]
DefaultPath=/usr/local/bin:/usr/local/lib/uutils:/usr/bin:/bin:/usr/sbin:/sbin
EOF

    # ── Core systemd services ─────────────────────────────────────────
    nspawn "systemctl enable \
        NetworkManager \
        pipewire \
        pipewire-pulse \
        wireplumber \
        bluetooth \
        apparmor \
        systemd-timesyncd \
        flatpak-system-helper \
        2>/dev/null || true"

    # ── Atuin user service ────────────────────────────────────────────
    mkdir -p "$ROOTFS/etc/systemd/user"
    cat > "$ROOTFS/etc/systemd/user/atuin.service" <<'SVC'
[Unit]
Description=Atuin shell history daemon
After=default.target

[Service]
Type=simple
ExecStart=/usr/local/cargo/bin/atuin daemon
Restart=on-failure

[Install]
WantedBy=default.target
SVC
    nspawn_soft "systemctl --global enable atuin 2>/dev/null || true"

    # ── Lilith-TTS daemon user service ────────────────────────────────
    cat > "$ROOTFS/etc/systemd/user/lilith-tts.service" <<'SVC'
[Unit]
Description=Lilith Text-to-Speech daemon
After=default.target pipewire.service

[Service]
Type=simple
ExecStart=/usr/local/bin/lilith-tts-daemon
Restart=on-failure

[Install]
WantedBy=default.target
SVC
    nspawn_soft "systemctl --global enable lilith-tts 2>/dev/null || true"

    # ── XDG MIME defaults ─────────────────────────────────────────────
    cat > "$ROOTFS/etc/xdg/mimeapps.list" <<EOF
[Default Applications]
inode/directory=cosmic-files.desktop
image/jpeg=cosmic-image-viewer.desktop
image/png=cosmic-image-viewer.desktop
image/gif=cosmic-image-viewer.desktop
image/webp=cosmic-image-viewer.desktop
image/tiff=cosmic-image-viewer.desktop
image/svg+xml=cosmic-image-viewer.desktop
text/plain=ouija-pad.desktop
text/x-shellscript=ouija-pad.desktop
x-scheme-handler/http=browseros.desktop
x-scheme-handler/https=browseros.desktop
x-scheme-handler/file=cosmic-files.desktop
application/x-compressed-tar=cosmic-files.desktop
application/zip=cosmic-files.desktop
application/pdf=browseros.desktop

[Added Associations]
terminal-emulator=hyper.desktop
x-scheme-handler/http=browseros.desktop;hellfire.desktop
x-scheme-handler/https=browseros.desktop;hellfire.desktop
EOF

    # ── XDG autostart cleanup ─────────────────────────────────────────
    rm -f "$ROOTFS/etc/xdg/autostart/cosmic-launcher.desktop" 2>/dev/null || true
    rm -f "$ROOTFS/etc/xdg/autostart/cosmic-store.desktop" 2>/dev/null || true

    # ── Release file (from cubic reference) ──────────────────────────
    if [[ -d /home/aegon/Lilith/custom-disk ]]; then
        # Copy the release metadata from the cubic build
        find /home/aegon/Lilith/custom-disk -name "os-release" | head -1 \
            | xargs -I{} cp {} "$ROOTFS/etc/os-release" 2>/dev/null || true
    fi

    # Ensure os-release is correct regardless
    cat > "$ROOTFS/etc/os-release" <<EOF
NAME="Lilith Linux"
VERSION="$DISTRO_VERSION"
ID=lilith
ID_LIKE=ubuntu debian
PRETTY_NAME="Lilith Linux $DISTRO_VERSION"
VERSION_ID="$DISTRO_VERSION"
HOME_URL="https://github.com/BlancoBAM"
SUPPORT_URL="https://github.com/BlancoBAM/S8n-System"
BUG_REPORT_URL="https://github.com/BlancoBAM/S8n-System/issues"
LOGO="lilith"
EOF

    cat > "$ROOTFS/etc/lsb-release" <<EOF
DISTRIB_ID=Lilith
DISTRIB_RELEASE=$DISTRO_VERSION
DISTRIB_CODENAME=resolute
DISTRIB_DESCRIPTION="Lilith Linux $DISTRO_VERSION"
EOF

    # ── /opt/lilith-apps PATH (AppImages: BrowserOS, Hellfire, AM apps) ─
    cat > "$ROOTFS/etc/profile.d/lilith-apps-path.sh" << 'PROF'
# Lilith Linux -- AppImage launchers on PATH
export PATH="/opt/lilith-apps:/usr/local/bin:$PATH"
PROF
    chmod 644 "$ROOTFS/etc/profile.d/lilith-apps-path.sh"
    mkdir -p "$ROOTFS/opt/lilith-apps"

    # ── Enable lilith-ai.service if Lilim shipped one ─────────────────
    if [[ -f "$ROOTFS/lib/systemd/system/lilith-ai.service" || \
          -f "$ROOTFS/etc/systemd/system/lilith-ai.service" ]]; then
        nspawn "systemctl enable lilith-ai.service 2>/dev/null || true"
    fi

    # ── First-boot permission corrector (from cubic configure) ────────
    # Runs once after install to fix Lilim/lilith-ai ownership and restart
    # the AI service now that the real user account exists.
    cat > "$ROOTFS/usr/sbin/lilith-first-boot.sh" << 'SH'
#!/usr/bin/env bash
# Lilith OS -- First-Boot Setup
LOG="/var/log/lilith-first-boot.log"
echo "=== Lilith OS First Boot: $(date) ===" > "$LOG"

for i in $(seq 1 30); do
    PRIMARY_USER="$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')"
    [[ -n "$PRIMARY_USER" ]] && break
    echo "Waiting for human user... ($i)" >> "$LOG"
    sleep 2
done

if [[ -n "$PRIMARY_USER" ]]; then
    USER_HOME="$(getent passwd "$PRIMARY_USER" | cut -d: -f6)"
    mkdir -p /var/log/lilim && chown -R "$PRIMARY_USER:$PRIMARY_USER" /var/log/lilim >> "$LOG" 2>&1
    mkdir -p "$USER_HOME/.local/share/lilim"
    chown -R "$PRIMARY_USER:$PRIMARY_USER" "$USER_HOME/.local/share/lilim" >> "$LOG" 2>&1
    systemctl daemon-reload >> "$LOG" 2>&1
    systemctl restart lilith-ai.service >> "$LOG" 2>&1 || true
fi

systemctl disable lilith-first-boot.service >> "$LOG" 2>&1 || true
echo "First-boot setup complete." >> "$LOG"
SH
    chmod +x "$ROOTFS/usr/sbin/lilith-first-boot.sh"

    mkdir -p "$ROOTFS/lib/systemd/system"
    cat > "$ROOTFS/lib/systemd/system/lilith-first-boot.service" << 'SVC'
[Unit]
Description=Lilith OS First-Boot Setup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/lilith-first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC
    nspawn "systemctl enable lilith-first-boot.service 2>/dev/null || true"

    # ── Clean apt cache ────────────────────────────────────────────────
    nspawn "apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*"

    stamp_done 16
    ok "Phase 16 complete -- services and final configuration done."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 17 – Lilith repos + topgrade auto-update wiring
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 17 && $END_PHASE -ge 17 ]]; then
    phase_banner 17 "Lilith package repos & auto-update wiring"

    # ── topgrade config (s8n upd8 calls topgrade) ─────────────────────
    mkdir -p "$ROOTFS/etc/skel/.config/topgrade"
    cat > "$ROOTFS/etc/skel/.config/topgrade/topgrade.toml" <<'TOML'
# Lilith OS — topgrade configuration
# Called by: s8n upd8

[misc]
assume_yes = true
cleanup    = true
skip_notify = false
pre_sudo = true

[git]
repos = [
    "/usr/local/src/*",
    "~/.config/nvim",
]
pull_only = true

[commands]
# Lilith custom repo sync — regenerate packages.toml from lil-build
"Lilith packages sync" = "python3 /usr/local/lib/lilith/generate-packages-toml.py > /usr/local/share/lilith/packages.toml 2>/dev/null || true"

[firmware]
upgrade = true

[linux]
enable_tlmgr = false

[npm]
use_sudo = false
TOML

    # System-wide topgrade config (for root / system-level updates)
    mkdir -p "$ROOTFS/etc/topgrade"
    cp "$ROOTFS/etc/skel/.config/topgrade/topgrade.toml" \
       "$ROOTFS/etc/topgrade/topgrade.toml"

    # ── Lilith packages manifest delivery ────────────────────────────
    # Install the generate-packages-toml.py from lil-build so the
    # manifest can be refreshed locally via topgrade
    mkdir -p "$ROOTFS/usr/local/lib/lilith"
    if [[ -f /home/aegon/lil-build/generate-packages-toml.py ]]; then
        cp /home/aegon/lil-build/generate-packages-toml.py \
           "$ROOTFS/usr/local/lib/lilith/generate-packages-toml.py"
    fi

    # Install packages.toml locally (s8n reads local copy OR fetches remote)
    mkdir -p "$ROOTFS/usr/local/share/lilith"
    if [[ -f /home/aegon/lilith-packages/packages.toml ]]; then
        cp /home/aegon/lilith-packages/packages.toml \
           "$ROOTFS/usr/local/share/lilith/packages.toml"
    fi

    # ── s8n config pointing to Lilith repo ───────────────────────────
    mkdir -p "$ROOTFS/etc/s8n"
    cat > "$ROOTFS/etc/s8n/config.toml" <<EOF
# Lilith OS — s8n system configuration
[lilith]
manifest_url = "https://blancobam.github.io/lilith-packages/packages.toml"
local_cache  = "/usr/local/share/lilith/packages.toml"
cache_ttl    = 3600

[update]
command = "topgrade"
EOF

    # ── Lilith APT repo keyring (re-add for installed system) ─────────
    if [[ -f /home/aegon/lilith-packages/public-key.asc ]]; then
        mkdir -p "$ROOTFS/usr/share/keyrings"
        cp /home/aegon/lilith-packages/public-key.asc \
           "$ROOTFS/usr/share/keyrings/lilith-archive-keyring.asc"
        nspawn "gpg --dearmor < /usr/share/keyrings/lilith-archive-keyring.asc \
            > /usr/share/keyrings/lilith-archive-keyring.gpg 2>/dev/null || true"
    fi

    # ── Bake latest versions into the image at build time ─────────────
    # Pull latest GitHub releases for key packages so they're on-disk
    # from day one (user can update later via s8n upd8 / topgrade)
    progress "Pre-downloading latest key packages …"

    pre_download_gh_binary() {
        local repo="$1" pattern="$2" dest="$3"
        local url
        url="$(gh_latest_url "$repo" "$pattern")" || return 0
        [[ -z "$url" ]] && return 0
        progress "Pre-fetching $repo …"
        wget -q -O "$CACHE_DIR/$(basename "$url")" "$url" 2>/dev/null \
            && cp "$CACHE_DIR/$(basename "$url")" "$dest" 2>/dev/null || true
    }

    pre_download_gh_binary "eza-community/eza" \
        "x86_64-unknown-linux-gnu.tar.gz" \
        "$CACHE_DIR/eza.tar.gz"

    pre_download_gh_binary "sharkdp/bat" \
        "_amd64.deb" "$CACHE_DIR/bat.deb"
    [[ -f "$CACHE_DIR/bat.deb" ]] && \
        cp "$CACHE_DIR/bat.deb" "$ROOTFS/tmp/bat.deb" && \
        nspawn "dpkg -i /tmp/bat.deb 2>/dev/null || true" && \
        rm -f "$ROOTFS/tmp/bat.deb"

    pre_download_gh_binary "ClementTsang/bottom" \
        "x86_64-unknown-linux-musl.tar.gz" \
        "$CACHE_DIR/bottom.tar.gz"

    stamp_done 17
    ok "Phase 17 complete — Lilith repos and auto-update configured."
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 18 – ISO generation
# ══════════════════════════════════════════════════════════════════════════
if [[ $START_PHASE -le 18 && $END_PHASE -ge 18 ]]; then
    phase_banner 18 "Generate installable ISO"

    ISO_NAME="$OUTPUT_DIR/${DISTRO_NAME,,}-${DISTRO_VERSION}-${ARCH}.iso"
    LIVE_DIR="$BUILD_DIR/iso-tree"

    mkdir -p "$LIVE_DIR"/{live,boot/grub,EFI/BOOT}

    # ── Compress rootfs → squashfs ────────────────────────────────────
    progress "Compressing rootfs (squashfs — this takes a while) …"
    mksquashfs "$ROOTFS" "$LIVE_DIR/live/filesystem.squashfs" \
        -comp xz -Xbcj x86 -b 1M -no-progress -noappend \
        -e boot 2>/dev/null

    # ── Filesystem size file (required by Ubiquity) ───────────────────
    du -sx --block-size=1 "$ROOTFS" | cut -f1 \
        > "$LIVE_DIR/live/filesystem.size"

    # ── Kernel & initrd ───────────────────────────────────────────────
    KERNEL="$(ls "$ROOTFS/boot"/vmlinuz-* 2>/dev/null | sort -V | tail -1)"
    INITRD="$(ls  "$ROOTFS/boot"/initrd.img-* 2>/dev/null | sort -V | tail -1)"

    [[ -n "$KERNEL" ]] || err "No kernel found in $ROOTFS/boot – did phase 2 run?"
    [[ -n "$INITRD" ]] || err "No initrd found in $ROOTFS/boot"

    cp "$KERNEL" "$LIVE_DIR/boot/vmlinuz"
    cp "$INITRD" "$LIVE_DIR/boot/initrd.img"

    # ── GRUB config for the live ISO ─────────────────────────────────
    cat > "$LIVE_DIR/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5

if loadfont /boot/grub/fonts/unicode.pf2; then
    set gfxmode=auto
    load_video
    insmod gfxterm
    terminal_output gfxterm
fi

if [ -f /boot/grub/themes/lilith/theme.txt ]; then
    set theme=/boot/grub/themes/lilith/theme.txt
fi

menuentry "${DISTRO_NAME} ${DISTRO_VERSION} — Live Session" {
    linux  /boot/vmlinuz boot=live quiet splash loglevel=3 ---
    initrd /boot/initrd.img
}

menuentry "${DISTRO_NAME} ${DISTRO_VERSION} — Install to Disk" {
    linux  /boot/vmlinuz boot=live only-ubiquity quiet splash ---
    initrd /boot/initrd.img
}

menuentry "Check disc for defects" {
    linux  /boot/vmlinuz boot=live integrity-check quiet splash ---
    initrd /boot/initrd.img
}

menuentry "Boot from first hard disk" {
    chainloader (hd0)+1
}
EOF

    # Copy GRUB theme into ISO tree
    cp -r "$ROOTFS/boot/grub/themes" "$LIVE_DIR/boot/grub/themes" 2>/dev/null || true

    # ── GRUB EFI image ────────────────────────────────────────────────
    if [[ -d "$ROOTFS/usr/lib/grub/x86_64-efi" ]]; then
        progress "Building EFI bootloader …"
        nspawn "grub-mkimage \
            -O x86_64-efi \
            -o /tmp/bootx64.efi \
            -p /boot/grub \
            part_gpt part_msdos fat iso9660 normal boot linux \
            initrd search search_label search_fs_uuid \
            gfxterm gfxmenu echo all_video video_fb \
            video_cirrus png jpeg font gfxterm_background 2>/dev/null"
        cp "$ROOTFS/tmp/bootx64.efi" "$LIVE_DIR/EFI/BOOT/BOOTx64.EFI" 2>/dev/null || true
    fi

    # ── Build ISO with xorriso ────────────────────────────────────────
    progress "Running xorriso …"
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "${DISTRO_NAME^^}" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin 2>/dev/null \
        -eltorito-boot boot/grub/i386-pc/eltorito.img \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        --efi-boot EFI/BOOT/BOOTx64.EFI \
        -efi-boot-part --efi-boot-image \
        -o "$ISO_NAME" \
        "$LIVE_DIR"

    # Checksum
    sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"
    info "ISO size:   $(du -sh "$ISO_NAME" | cut -f1)"
    info "SHA-256:    $(cat "$ISO_NAME.sha256" | cut -d' ' -f1)"
    info "Checksum:   $ISO_NAME.sha256"

    stamp_done 18
    ok "ISO written to: $ISO_NAME"
fi

# ══════════════════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BLD}${GRN}╔══════════════════════════════════════════════════════════╗${RST}"
echo -e "${BLD}${GRN}║           Lilith OS Build Complete! 🔥                   ║${RST}"
echo -e "${BLD}${GRN}║                                                          ║${RST}"
echo -e "${BLD}${GRN}║  ISO    → $OUTPUT_DIR/                                   ║${RST}"
echo -e "${BLD}${GRN}║  Log    → $LOG_FILE                                      ║${RST}"
echo -e "${BLD}${GRN}║  Rootfs → $ROOTFS                                        ║${RST}"
echo -e "${BLD}${GRN}╚══════════════════════════════════════════════════════════╝${RST}"
echo ""
echo -e "${CYN}Next steps:${RST}"
echo "  1. Test in QEMU (needs KVM + 8 GB RAM):"
echo "       qemu-system-x86_64 -enable-kvm -m 8G -smp 4 \\"
echo "         -cdrom $OUTPUT_DIR/*.iso -vga virtio"
echo ""
echo "  2. Write to USB:"
echo "       sudo dd if=$OUTPUT_DIR/*.iso of=/dev/sdX bs=4M status=progress conv=fsync"
echo ""
echo "  3. Resume a failed build at a specific phase:"
echo "       sudo BUILD_DIR=$BUILD_DIR START_PHASE=<N> $0"
echo ""
echo "  4. Build only a range of phases:"
echo "       sudo $0 --phase 7 --to 12"
