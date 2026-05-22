#!/bin/bash
# Lilith Linux Repository Builder
# Builds and maintains the Lilith Linux package repository
# Based on debrepbuild pattern from Pop!OS

set -e

REPO_ROOT="/home/aegon/Lilith-Build/repo"
DIST_NAME="stable"
ARCH="amd64"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create repository structure
init_repo() {
    log "Initializing repository structure..."
    
    mkdir -p "${REPO_ROOT}/pool/main"
    mkdir -p "${REPO_ROOT}/pool/multiverse"
    mkdir -p "${REPO_ROOT}/pool/universe"
    mkdir -p "${REPO_ROOT}/dists/${DIST_NAME}/main"
    mkdir -p "${REPO_ROOT}/dists/${DIST_NAME}/multiverse"
    mkdir -p "${REPO_ROOT}/dists/${DIST_NAME}/universe"
    mkdir -p "${REPO_ROOT}/incoming"
    
    log "Repository structure created"
}

# Scan packages and create package indexes
build_packages() {
    log "Building package indexes..."
    
    for component in main multiverse universe; do
        local pool_dir="${REPO_ROOT}/pool/${component}"
        local dist_dir="${REPO_ROOT}/dists/${DIST_NAME}/${component}"
        
        if [ -d "$pool_dir" ] && [ "$(ls -A "$pool_dir" 2>/dev/null)" ]; then
            log "  Scanning ${component}..."
            
            # Create Packages.gz
            dpkg-scanpackages -m "$pool_dir" 2>/dev/null | gzip -c > "${dist_dir}/Packages.gz"
            
            # Create Release file
            cat > "${dist_dir}/Release" << EOF
Origin: Lilith Linux
Label: Lilith Linux ${component}
Suite: ${DIST_NAME}
Version: 1.0.0
Component: ${component}
Architecture: ${ARCH}
Description: ${component} packages for Lilith Linux
EOF
            
            log "  ${component} index created"
        else
            warn "  No packages in ${component}, skipping"
        fi
    done
}

# Create main Release file
build_release() {
    log "Building main Release file..."
    
    local release_file="${REPO_ROOT}/dists/${DIST_NAME}/Release"
    
    cat > "$release_file" << EOF
Origin: Lilith Linux
Label: Lilith Linux
Suite: ${DIST_NAME}
Version: 1.0.0
Codename: stable
Date: $(date -R)
Architectures: ${ARCH}
Components: main multiverse universe
Description: Lilith Linux Package Repository
EOF
    
    # Calculate checksums
    for component in main multiverse universe; do
        local pkg_file="${REPO_ROOT}/dists/${DIST_NAME}/${component}/Packages.gz"
        if [ -f "$pkg_file" ]; then
            local size=$(stat -c%s "$pkg_file")
            local hash=$(sha256sum "$pkg_file" | cut -d' ' -f1)
            echo "SHA256:" >> "$release_file"
            echo " $(cut -d' ' -f1 <<< $hash) $size ${component}/Packages.gz" >> "$release_file"
        fi
    done
    
    log "Release file created"
}

# Add a .deb package to the repository
add_package() {
    local deb_file="$1"
    local component="${2:-main}"
    
    if [ ! -f "$deb_file" ]; then
        error "Package file not found: $deb_file"
        return 1
    fi
    
    local pool_dir="${REPO_ROOT}/pool/${component}"
    local filename=$(basename "$deb_file")
    
    cp "$deb_file" "$pool_dir/"
    log "Added $filename to ${component}"
}

# Generate APT source line
get_apt_source() {
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/lilith-archive-keyring.gpg] https://packages.lilithlinux.org/ ${DIST_NAME} main multiverse universe"
}

# Main usage
usage() {
    cat << EOF
Lilith Linux Repository Builder

Usage: $0 <command> [options]

Commands:
    init              Initialize repository structure
    build             Build package indexes
    add <file>        Add a .deb package to the repository
    release           Generate Release file
    apt-source        Print APT source configuration
    all               Full repository build

Examples:
    $0 init
    $0 add /path/to/package.deb main
    $0 build
    $0 release
    
    # Full build
    $0 all

EOF
}

# Main
case "${1:-}" in
    init)
        init_repo
        ;;
    build)
        build_packages
        ;;
    add)
        add_package "$2" "$3"
        ;;
    release)
        build_release
        ;;
    apt-source)
        get_apt_source
        ;;
    all)
        init_repo
        build_packages
        build_release
        log "Repository build complete"
        ;;
    *)
        usage
        ;;
esac
