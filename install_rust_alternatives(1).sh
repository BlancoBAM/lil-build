#!/bin/bash
# Lilith Linux Rust Alternatives Installer
# Provides Rust alternatives with coreutils fallback

set -e

LOG_FILE="/var/log/lilith-rust-alternatives.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

install_uutils_coreutils() {
    log "Installing uutils/coreutils..."
    
    local UUTILS_DIR="/opt/lilith-linux/usr/local"
    local BIN_DIR="$UUTILS_DIR/bin"
    
    if [ -d "/opt/lilith-linux" ]; then
        # In chroot environment
        UUTILS_DIR="/usr/local"
        BIN_DIR="/usr/local/bin"
    fi
    
    mkdir -p "$BIN_DIR"
    
    # Try to install from cargo first
    if command -v cargo &> /dev/null; then
        log "Building uutils/coreutils from source..."
        cargo install coreutils --locked 2>/dev/null || {
            log "Cargo install failed, trying binary..."
            install_uutils_binary
        }
    else
        install_uutils_binary
    fi
    
    # Create wrapper scripts with fallback
    create_wrappers
    
    log "uutils/coreutils installed successfully"
}

install_uutils_binary() {
    local ARCH
    ARCH=$(uname -m)
    local VERSION="0.0.27"
    local BIN_DIR="/usr/local/bin"
    
    case "$ARCH" in
        x86_64)
            local TARBALL="coreutils-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
            ;;
        aarch64)
            local TARBALL="coreutils-${VERSION}-aarch64-unknown-linux-gnu.tar.gz"
            ;;
        *)
            log "Unsupported architecture: $ARCH"
            return 1
            ;;
    esac
    
    local URL="https://github.com/uutils/coreutils/releases/download/${VERSION}/${TARBALL}"
    
    log "Downloading uutils/coreutils from $URL"
    cd /tmp
    curl -L -o "$TARBALL" "$URL" || {
        log "Download failed, will use system coreutils"
        return 1
    }
    
    tar -xzf "$TARBALL"
    cd "coreutils-${VERSION}"
    ./install.sh || cp -r bin/* "$BIN_DIR/" 2>/dev/null || true
    cd /tmp
    rm -rf "coreutils-${VERSION}" "$TARBALL"
}

create_wrappers() {
    local WRAPPER_DIR="/opt/lilith-linux/usr/local/lib/lilith-rust-alternatives"
    local BIN_LINK_DIR="/opt/lilith-linux/usr/local/bin"
    
    if [ ! -d "/opt/lilith-linux" ]; then
        WRAPPER_DIR="/usr/local/lib/lilith-rust-alternatives"
        BIN_LINK_DIR="/usr/local/bin"
    fi
    
    mkdir -p "$WRAPPER_DIR" "$BIN_LINK_DIR"
    
    # Core utilities to wrap
    local RUST_UTILS=(
        "ls:lsd"
        "cat:bat"
        "find:fd"
        "grep:ripgrep"
        "du:dua"
        "df:coreutils-dual"
        "top:procs"
        "ps:procs"
        "tail:coreutils-tail"
        "head:coreutils-head"
        "cut:coreutils-cut"
        "sort:coreutils-sort"
        "uniq:coreutils-uniq"
        "wc:coreutils-wc"
        "date:coreutils-date"
        "echo:coreutils-echo"
        "printf:coreutils-printf"
        "test:coreutils-test"
        "true:coreutils-true"
        "false:coreutils-false"
        "sleep:coreutils-sleep"
        "seq:coreutils-seq"
        "yes:coreutils-yes"
        "pwd:coreutils-pwd"
        "id:coreutils-id"
        "groups:coreutils-groups"
        "whoami:coreutils-whoami"
        "hostname:coreutils-hostname"
        "basename:coreutils-basename"
        "dirname:coreutils-dirname"
        "pathchk:coreutils-pathchk"
        "mktemp:coreutils-mktemp"
        "mkfifo:coreutils-mkfifo"
        "readlink:coreutils-readlink"
        "realpath:coreutils-realpath"
        "ln:coreutils-ln"
        "cp:coreutils-cp"
        "mv:coreutils-mv"
        "rm:coreutils-rm"
        "mkdir:coreutils-mkdir"
        "rmdir:coreutils-rmdir"
        "touch:coreutils-touch"
        "tr:coreutils-tr"
        "chmod:coreutils-chmod"
        "chown:coreutils-chown"
        "chgrp:coreutils-chgrp"
        "nproc:coreutils-nproc"
        "env:coreutils-env"
        "nice:coreutils-nice"
        "timeout:coreutils-timeout"
    )
    
    for item in "${RUST_UTILS[@]}"; do
        local legacy_name="${item%%:*}"
        local rust_name="${item##*:}"
        
        # Skip if rust_name contains coreutils- (those need manual handling)
        if [[ "$rust_name" == "coreutils-"* ]]; then
            continue
        fi
        
        create_fallback_wrapper "$legacy_name" "$rust_name" "$WRAPPER_DIR" "$BIN_LINK_DIR"
    done
    
    # Special handling for cat -> batcat
    create_batcat_wrapper "$WRAPPER_DIR" "$BIN_LINK_DIR"
    
    log "Created fallback wrappers"
}

create_fallback_wrapper() {
    local legacy_name="$1"
    local rust_name="$2"
    local wrapper_dir="$3"
    local bin_dir="$4"
    
    local wrapper_path="$wrapper_dir/${legacy_name}.sh"
    
    cat > "$wrapper_path" << EOF
#!/bin/bash
# Fallback wrapper for $legacy_name -> $rust_name
# Falls back to system $legacy_name if Rust version fails

# Try Rust alternative first
if command -v "$rust_name" &> /dev/null; then
    exec "$rust_name" "\$@"
fi

# Fallback to system binary
if command -v "/usr/bin/$legacy_name" &> /dev/null; then
    exec "/usr/bin/$legacy_name" "\$@"
fi

# Last resort - try PATH
exec "$legacy_name" "\$@"
EOF
    
    chmod +x "$wrapper_path"
    
    # Create symlink if the rust binary exists
    if command -v "$rust_name" &> /dev/null; then
        ln -sf "$(which "$rust_name")" "$bin_dir/$legacy_name" 2>/dev/null || true
    else
        # Use wrapper as fallback
        ln -sf "$wrapper_path" "$bin_dir/$legacy_name" 2>/dev/null || true
    fi
}

create_batcat_wrapper() {
    local wrapper_dir="$1"
    local bin_dir="$2"
    
    # Create batcat as alias to bat
    if command -v bat &> /dev/null; then
        ln -sf "$(which bat)" "$bin_dir/batcat" 2>/dev/null || true
    else
        # Create wrapper that falls back to cat
        cat > "$wrapper_dir/batcat.sh" << 'EOF'
#!/bin/bash
# batcat wrapper - tries bat first, falls back to cat

if command -v bat &> /dev/null; then
    exec bat "$@"
fi

# Fallback to system cat
exec /usr/bin/cat "$@"
EOF
        chmod +x "$wrapper_dir/batcat.sh"
        ln -sf "$wrapper_dir/batcat.sh" "$bin_dir/batcat" 2>/dev/null || true
    fi
}

install_bat() {
    log "Installing bat (cat replacement)..."
    
    if command -v cargo &> /dev/null; then
        cargo install bat --locked 2>/dev/null || true
    fi
    
    # Try package manager if cargo fails
    if ! command -v bat &> /dev/null; then
        apt-get update && apt-get install -y bat 2>/dev/null || true
    fi
    
    log "bat installed: $(command -v bat || echo 'not found')"
}

install_lsd() {
    log "Installing lsd (ls replacement)..."
    
    if command -v cargo &> /dev/null; then
        cargo install lsd --locked 2>/dev/null || true
    fi
    
    if ! command -v lsd &> /dev/null; then
        apt-get install -y lsd 2>/dev/null || true
    fi
    
    log "lsd installed: $(command -v lsd || echo 'not found')"
}

install_fd() {
    log "Installing fd (find replacement)..."
    
    if command -v cargo &> /dev/null; then
        cargo install fd-find --locked 2>/dev/null || true
    fi
    
    if ! command -v fd &> /dev/null; then
        apt-get install -y fd-find 2>/dev/null || true
    fi
    
    log "fd installed: $(command -v fd || echo 'not found')"
}

install_ripgrep() {
    log "Installing ripgrep (grep replacement)..."
    
    if command -v cargo &> /dev/null; then
        cargo install ripgrep --locked 2>/dev/null || true
    fi
    
    if ! command -v rg &> /dev/null; then
        apt-get install -y ripgrep 2>/dev/null || true
    fi
    
    log "ripgrep installed: $(command -v rg || echo 'not found')"
}

install_procs() {
    log "Installing procs (ps/top replacement)..."
    
    if command -v cargo &> /dev/null; then
        cargo install procs --locked 2>/dev/null || true
    fi
    
    if ! command -v procs &> /dev/null; then
        apt-get install -y procs 2>/dev/null || true
    fi
    
    log "procs installed: $(command -v procs || echo 'not found')"
}

install_dua() {
    log "Installing dua-cli (du replacement)..."
    
    if command -v cargo &> /dev/null; then
        cargo install dua-cli --locked 2>/dev/null || true
    fi
    
    log "dua installed: $(command -v dua || echo 'not found')"
}

setup_shell_integrations() {
    log "Setting up shell integrations..."
    
    local PROFILE_FILE="/etc/profile.d/lilith-rust-alternatives.sh"
    
    cat > "$PROFILE_FILE" << 'EOF'
# Lilith Linux Rust Alternatives
# Priority: Rust binaries > Wrappers > System binaries

# Add local binaries to PATH
export PATH="/usr/local/bin:$PATH"

# Rust utility aliases (prefer these over system)
alias ls='lsd --icons always'
alias ll='lsd -l --icons always'
alias la='lsd -la --icons always'
alias lt='lsd --tree --icons always'

# Use bat for cat with fallback
alias cat='bat --style=auto --paging=auto'
alias batcat='bat'

# fd as find alternative
alias find='fdfind'

# ripgrep
alias grep='rg'
alias egrep='rg -e'
alias fgrep='rg -F'

# procs for process info
alias top='procs'
alias ps='procs'

# Modern alternatives
alias du='dua'
alias df='procs --disk'

# Cargo binaries
export PATH="$HOME/.cargo/bin:$PATH"
EOF
    
    chmod +x "$PROFILE_FILE"
    log "Shell integrations configured"
}

main() {
    log "Starting Lilith Linux Rust Alternatives installation..."
    
    install_bat
    install_lsd
    install_fd
    install_ripgrep
    install_procs
    install_dua
    install_uutils_coreutils
    setup_shell_integrations
    
    log "Installation complete!"
    log "Note: Reboot or source /etc/profile.d/lilith-rust-alternatives.sh to apply changes"
}

main "$@"
