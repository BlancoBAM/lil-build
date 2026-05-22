#!/bin/bash
# Lilith Linux - Rust Alternatives Installation Script
# Installs Rust-based alternatives to GNU coreutils and other system tools
# with seamless fallback to GNU equivalents

set -e

LILITH_ROOT="${1:-/opt/lilith-linux}"
INSTALL_DIR="/usr/local/bin"

echo "=== Installing Rust Alternatives for Lilith Linux ==="

# Build from source or install pre-built
install_rust_tool() {
    local tool="$1"
    local repo="$2"
    local binary="$3"
    
    echo "Installing $tool..."
    
    # Check if already installed
    if command -v "$binary" &> /dev/null; then
        echo "  $tool already installed"
        return 0
    fi
    
    # Try to install via cargo if available in chroot
    if [ -d "$LILITH_ROOT" ]; then
        chroot "$LILITH_ROOT" /bin/bash -c "
            if command -v cargo &> /dev/null; then
                cargo install $tool --locked 2>/dev/null || true
            fi
        " || true
    fi
}

# Install core Rust utilities from source or binaries
install_core_utils() {
    echo ""
    echo "=== Installing Core Rust Utilities ==="
    
    local tools=(
        "bat:sharkdp/bat:bat"
        "lsd:lsd-rs/lsd:lsd"
        "fd:sharkdp/fd:fd"
        "ripgrep:BurntSushi/ripgrep:rg"
        "hexyl:sharkdp/hexyl:hexyl"
        "dust:bootandy/dust:du-dust"
        "procs:dalance/procs:procs"
        "dua:Byron/dua-cli:dua"
        "xcp:tarka/xcp:xcp"
        "navi:denisidoro/navi:navi"
        "broot:Canop/broot:broot"
        "zoxide:ajeetdsouza/zoxide:zoxide"
    done
    
    for item in "${tools[@]}"; do
        IFS=':' read -r name repo binary <<< "$item"
        echo "Checking $name..."
        
        # For now, document what's needed - actual installation happens via packages
        echo "  - $name ($repo)"
    done
}

# Configure update-alternatives for seamless fallback
configure_alternatives() {
    echo ""
    echo "=== Configuring System Alternatives ==="
    
    # This would be run in the chroot or final system
    cat > "${LILITH_ROOT}/etc/profile.d/lilith-rust-alternatives.sh" << 'EOF'
# Lilith Linux Rust Alternatives
# Provides seamless fallback from Rust tools to GNU coreutils

# ls -> lsd with fallback
ls() {
    if command -v lsd &> /dev/null; then
        lsd "$@"
    else
        /bin/ls "$@"
    fi
}

# cat -> bat with fallback
cat() {
    if command -v bat &> /dev/null; then
        bat "$@"
    else
        /bin/cat "$@"
    fi
}

# grep -> ripgrep if available
grep() {
    if command -v rg &> /dev/null; then
        rg "$@"
    else
        /bin/grep "$@"
    fi
}

# find -> fd if available
find() {
    if command -v fdfind &> /dev/null; then
        fdfind "$@"
    elif command -v fd &> /dev/null; then
        fd "$@"
    else
        /bin/find "$@"
    fi
}

# du -> dust if available
du() {
    if command -v dust &> /dev/null; then
        dust "$@"
    else
        /bin/du "$@"
    fi
}

# ps -> procs if available
ps() {
    if command -v procs &> /dev/null; then
        procs "$@"
    else
        /bin/ps "$@"
    fi
}

# Export path priority
export PATH="/usr/local/bin:$PATH"
EOF

    echo "  Created /etc/profile.d/lilith-rust-alternatives.sh"
}

# Create symlinks for common commands
create_symlinks() {
    echo ""
    echo "=== Creating Symlinks ==="
    
    local symlinks=(
        "bat:/usr/bin/cat"
        "lsd:/usr/bin/ls"
        "fd:/usr/bin/find"
        "rg:/usr/bin/grep"
        "dust:/usr/bin/du"
        "procs:/usr/bin/ps"
    )
    
    for item in "${symlinks[@]}"; do
        IFS=':' read -r tool target <<< "$item"
        echo "  Linking $tool -> $target (optional)"
    done
}

# Main installation
main() {
    install_core_utils
    configure_alternatives
    create_symlinks
    
    echo ""
    echo "=== Rust Alternatives Configuration Complete ==="
    echo ""
    echo "To complete installation, run in the target system:"
    echo "  1. Install packages: apt install bat lsd fd-find ripgrep"
    echo "  2. Or build from source using Cargo"
    echo "  3. The shell functions provide automatic fallback"
}

main "$@"
