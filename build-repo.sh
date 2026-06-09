#!/usr/bin/env bash
# =============================================================================
# Lilith Linux Repository Builder (Shell wrapper)
# =============================================================================
# A lightweight shell-based repo builder that wraps build_lilith_repo.py.
# For low-level package index management without the full Python script.
#
# Usage:
#   bash build-repo.sh [command]
#
# Commands:
#   init              Initialize repository directory structure
#   build             Build Packages/Release indexes from pool/
#   add <file> [comp] Add a .deb to pool (comp: core|xtra|desktop, default: core)
#   apt-source        Print the APT source line for this repo
#   all               Full rebuild: init → build
#
# For the full build with TOML-driven package fetching, use:
#   python3 build_lilith_repo.py
# or:
#   bash lilith-build.sh --build-repo
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/Lilith-Repo"
DIST_NAME="stable"
ARCH="amd64"
REPO_URL="https://blancobam.github.io/lilith-packages"
COMPONENTS="core xtra desktop"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---------------------------------------------------------------------------
# init: create directory structure
# ---------------------------------------------------------------------------
init_repo() {
    log "Initializing Lilith-Repo structure at $REPO_ROOT ..."
    for comp in $COMPONENTS; do
        mkdir -p "$REPO_ROOT/pool/$comp"
        mkdir -p "$REPO_ROOT/dists/$DIST_NAME/$comp/binary-$ARCH"
    done
    log "Repository structure created"
}

# ---------------------------------------------------------------------------
# build: scan pool/ and generate Packages + Release indexes
# ---------------------------------------------------------------------------
build_packages() {
    log "Building package indexes..."
    command -v dpkg-scanpackages &>/dev/null || err "dpkg-scanpackages not found. Install: sudo apt install dpkg-dev"

    for comp in $COMPONENTS; do
        local pool_dir="$REPO_ROOT/pool/$comp"
        local dist_dir="$REPO_ROOT/dists/$DIST_NAME/$comp/binary-$ARCH"

        mkdir -p "$dist_dir"

        if [[ -d "$pool_dir" ]] && [[ -n "$(ls -A "$pool_dir" 2>/dev/null)" ]]; then
            log "  Scanning $comp ($(ls "$pool_dir"/*.deb 2>/dev/null | wc -l) debs)..."

            # Create uncompressed Packages (for path references)
            dpkg-scanpackages --multiversion "$pool_dir" /dev/null 2>/dev/null \
                | sed "s|$REPO_ROOT/||g" \
                > "$dist_dir/Packages"

            # Compressed variants
            gzip -9 -c "$dist_dir/Packages" > "$dist_dir/Packages.gz"
            xz -c "$dist_dir/Packages" > "$dist_dir/Packages.xz" 2>/dev/null || true

            # Per-component Release
            cat > "$dist_dir/Release" <<EOF
Origin: Lilith Linux
Label: Lilith Linux
Suite: $DIST_NAME
Codename: $DIST_NAME
Component: $comp
Architecture: $ARCH
Description: Lilith Linux $comp packages
EOF
            log "  ✔ $comp: Packages, Packages.gz, Release written"
        else
            warn "  No .deb files in $comp, writing empty Packages"
            : > "$dist_dir/Packages"
            gzip -9 -c "$dist_dir/Packages" > "$dist_dir/Packages.gz"
        fi
    done

    build_release
}

# ---------------------------------------------------------------------------
# build_release: generate the top-level Release file with SHA256 sums
# ---------------------------------------------------------------------------
build_release() {
    local release_file="$REPO_ROOT/dists/$DIST_NAME/Release"
    log "Building main Release file..."

    cat > "$release_file" <<EOF
Origin: Lilith Linux
Label: Lilith Linux
Suite: $DIST_NAME
Codename: $DIST_NAME
Version: 1.0.0
Date: $(date -Ru)
Architectures: $ARCH
Components: $COMPONENTS
Description: Lilith Linux Overlay Package Repository
EOF

    echo "SHA256:" >> "$release_file"
    for comp in $COMPONENTS; do
        local bin_dir="$REPO_ROOT/dists/$DIST_NAME/$comp/binary-$ARCH"
        for f in Packages Packages.gz Packages.xz Release; do
            local fp="$bin_dir/$f"
            [[ -f "$fp" ]] || continue
            local size hash rel_path
            size=$(stat -c%s "$fp")
            hash=$(sha256sum "$fp" | cut -d' ' -f1)
            rel_path="$comp/binary-$ARCH/$f"
            printf " %s %s %s\n" "$hash" "$size" "$rel_path" >> "$release_file"
        done
    done

    log "Release file written: $release_file"

    # Sign if GPG key is available
    if gpg --list-secret-keys blancobam@protonmail.com &>/dev/null 2>&1; then
        log "Signing Release..."
        gpg --batch --yes --clearsign \
            --default-key blancobam@protonmail.com \
            -o "$REPO_ROOT/dists/$DIST_NAME/InRelease" \
            "$release_file" 2>/dev/null && log "  ✔ InRelease (inline-signed)"
        gpg --batch --yes -abs \
            --default-key blancobam@protonmail.com \
            -o "${release_file}.gpg" \
            "$release_file" 2>/dev/null && log "  ✔ Release.gpg (detached sig)"
    else
        warn "GPG key not found for blancobam@protonmail.com — skipping signing"
    fi
}

# ---------------------------------------------------------------------------
# add_package: copy a .deb into the pool
# ---------------------------------------------------------------------------
add_package() {
    local deb_file="${1:-}"
    local comp="${2:-core}"
    [[ -f "$deb_file" ]] || err "Package not found: $deb_file"
    [[ " $COMPONENTS " =~ " $comp " ]] || err "Unknown component: $comp (must be one of: $COMPONENTS)"
    local pool_dir="$REPO_ROOT/pool/$comp"
    mkdir -p "$pool_dir"
    cp -f "$deb_file" "$pool_dir/"
    log "Added $(basename "$deb_file") to $comp"
}

# ---------------------------------------------------------------------------
# apt_source: print the APT source line
# ---------------------------------------------------------------------------
apt_source() {
    echo ""
    echo "Add to /etc/apt/sources.list.d/lilith-linux.list:"
    echo ""
    echo "  deb [arch=$ARCH signed-by=/usr/share/keyrings/lilith-archive-keyring.gpg] $REPO_URL $DIST_NAME core xtra"
    echo ""
    echo "Install signing key:"
    echo "  curl -fsSL $REPO_URL/public-key.asc | sudo gpg --dearmor -o /usr/share/keyrings/lilith-archive-keyring.gpg"
    echo ""
}

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Lilith Linux Repository Builder (shell wrapper)

Usage: $0 <command> [options]

Commands:
  init              Initialize Lilith-Repo directory structure
  build             Build Packages/Release indexes from pool/
  add <file> [comp] Add a .deb package (comp: core|xtra|desktop)
  apt-source        Print APT source configuration
  all               init + build (full rebuild)

Repository URL: $REPO_URL
Components:     $COMPONENTS
Output:         $REPO_ROOT

For full TOML-driven build (fetches packages from GitHub):
  python3 build_lilith_repo.py
or:
  bash lilith-build.sh --build-repo
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "${1:-}" in
    init)        init_repo ;;
    build)       build_packages ;;
    add)         add_package "${2:-}" "${3:-core}" ;;
    apt-source)  apt_source ;;
    all)
        init_repo
        build_packages
        log "Repository build complete → $REPO_ROOT"
        ;;
    *)
        usage
        ;;
esac
