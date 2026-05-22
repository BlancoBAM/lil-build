#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — Host Pre-Build Script
# =============================================================================
# Run this on the HOST machine BEFORE opening Cubic.
# It fetches all release artifacts, compiles Rust apps from source,
# and populates /home/aegon/lil-build/staging/ for use by configure-lilith-os.sh
#
#   bash /home/aegon/lil-build/pre-build-host.sh [--dry-run]
#
# =============================================================================

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ── Configuration ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING="$SCRIPT_DIR/staging"
DEBS="$STAGING/debs"
APPIMAGES="$STAGING/appimages"
BINARIES="$STAGING/binaries"
BUILD_DIR="$STAGING/build"
MANIFEST="$STAGING/manifest.json"
LOG_FILE="$STAGING/prebuild.log"

# ── Colors & Helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✔]${NC} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
err()   { echo -e "${RED}[✘]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
step()  { echo -e "\n${BLUE}══${NC} $* ${BLUE}══${NC}" | tee -a "$LOG_FILE"; }
dryrun(){ echo -e "${CYAN}[DRY-RUN]${NC} $*"; }

# ── Staging directory init ─────────────────────────────────────────────────────
mkdir -p "$DEBS" "$APPIMAGES" "$BINARIES" "$BUILD_DIR"
: > "$LOG_FILE"
echo "{ \"build_date\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"artifacts\": [] }" > "$MANIFEST"

# ── Manifest helpers ───────────────────────────────────────────────────────────
manifest_add() {
    local name="$1" url="$2" dest="$3" sha256="$4"
    local tmp
    tmp=$(cat "$MANIFEST")
    echo "$tmp" | python3 -c "
import sys, json
data = json.load(sys.stdin)
data['artifacts'].append({'name': '$name', 'url': '$url', 'dest': '$dest', 'sha256': '$sha256'})
print(json.dumps(data, indent=2))
" > "$MANIFEST"
}

# ── GitHub latest release fetcher ─────────────────────────────────────────────
# Usage: github_latest_deb <owner/repo> <output_dir> [asset_pattern]
github_latest_deb() {
    local repo="$1"
    local outdir="$2"
    local pattern="${3:-amd64.deb}"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"

    step "Fetching latest .deb from github.com/${repo}"

    local release_json
    release_json=$(curl -fsSL "$api_url") || {
        warn "Failed to reach GitHub API for ${repo}"
        return 1
    }

    local download_url
    download_url=$(echo "$release_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assets = data.get('assets', [])
pattern = '$pattern'
# Prefer non-beta/non-rc assets when multiple match
stable = [a for a in assets if pattern in a['name'] and not any(x in a['name'] for x in ['beta','rc','alpha','pre'])]
fallback = [a for a in assets if pattern in a['name']]
pick = stable or fallback
if pick:
    print(pick[0]['browser_download_url'])
" 2>/dev/null || true)

    if [[ -z "$download_url" ]]; then
        warn "No matching asset (*${pattern}) found in latest release of ${repo}"
        return 1
    fi

    local filename
    filename=$(basename "$download_url")
    local dest="$outdir/$filename"

    if [[ "$DRY_RUN" == "true" ]]; then
        dryrun "Would download: $download_url → $dest"
        return 0
    fi

    if [[ -f "$dest" ]]; then
        info "Already cached: $filename"
    else
        curl -fsSL -o "$dest" "$download_url"
        info "Downloaded: $filename"
    fi

    local sha256
    sha256=$(sha256sum "$dest" | awk '{print $1}')
    manifest_add "$repo" "$download_url" "$dest" "$sha256"
}

# Usage: download_appimage <url> <output_name>
download_appimage() {
    local url="$1"
    local name="$2"
    local dest="$APPIMAGES/$name"

    step "Downloading AppImage: $name"

    if [[ "$DRY_RUN" == "true" ]]; then
        dryrun "Would download: $url → $dest"
        return 0
    fi

    if [[ -f "$dest" ]]; then
        info "Already cached: $name"
    else
        curl -fsSL -L -o "$dest" "$url"
        chmod +x "$dest"
        info "Downloaded + chmod +x: $name"
    fi

    local sha256
    sha256=$(sha256sum "$dest" | awk '{print $1}')
    manifest_add "$name" "$url" "$dest" "$sha256"
}

# ── Rust source build ──────────────────────────────────────────────────────────
build_rust_repo() {
    local repo_url="$1"
    local repo_name="$2"
    local binary_name="$3"
    local dest="$BINARIES/$binary_name"

    step "Building Rust app: $repo_name"

    if ! command -v cargo &>/dev/null; then
        err "Cargo not found on host. Install Rust: https://rustup.rs"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        dryrun "Would clone $repo_url and run: cargo build --release"
        dryrun "Would copy target/release/$binary_name → $dest"
        return 0
    fi

    local clone_dir="$BUILD_DIR/$repo_name"
    if [[ -d "$clone_dir" ]]; then
        info "Repo already cloned, pulling latest..."
        git -C "$clone_dir" fetch --all && git -C "$clone_dir" reset --hard origin/HEAD || true
    else
        git clone --depth 1 "$repo_url" "$clone_dir"
    fi

    pushd "$clone_dir" > /dev/null
    cargo build --release 2>&1 | tee -a "$LOG_FILE"
    popd > /dev/null

    # Find the built binary — try exact name first, then any executable
    local built_binary
    if [[ -f "$clone_dir/target/release/$binary_name" ]]; then
        built_binary="$clone_dir/target/release/$binary_name"
    else
        built_binary=$(find "$clone_dir/target/release" -maxdepth 1 -type f -executable \
            ! -name '*.d' ! -name '*.so' ! -name '*.rlib' 2>/dev/null | head -n1)
    fi

    if [[ -z "$built_binary" ]]; then
        warn "No binary found in $clone_dir/target/release/ — skipping $repo_name"
        return 1
    fi

    cp "$built_binary" "$dest"
    chmod +x "$dest"
    info "Built and copied: $(basename $built_binary) → $dest"

    local sha256
    sha256=$(sha256sum "$dest" | awk '{print $1}')
    manifest_add "$repo_name" "$repo_url" "$dest" "$sha256"
}

# ── cosmic-app-library: uses justfile ─────────────────────────────────────────
build_cosmic_app_library() {
    local repo_url="https://github.com/pop-os/cosmic-app-library"
    local dest_dir="$BINARIES/cosmic-app-library"

    step "Building cosmic-app-library from source"

    if ! command -v cargo &>/dev/null; then
        err "Cargo not found on host."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        dryrun "Would clone $repo_url and build with cargo build --release"
        return 0
    fi

    local clone_dir="$BUILD_DIR/cosmic-app-library"
    if [[ -d "$clone_dir" ]]; then
        info "cosmic-app-library already cloned, pulling latest..."
        git -C "$clone_dir" fetch --all && git -C "$clone_dir" reset --hard origin/HEAD || true
    else
        git clone --depth 1 "$repo_url" "$clone_dir"
    fi

    pushd "$clone_dir" > /dev/null

    # Install build dependencies if needed
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y \
            libssl-dev libxkbcommon-dev \
            libwayland-dev wayland-protocols \
            libseat-dev libinput-dev \
            pkg-config 2>&1 | tee -a "$LOG_FILE" || true
    fi

    cargo build --release 2>&1 | tee -a "$LOG_FILE"
    popd > /dev/null

    mkdir -p "$dest_dir"
    # Copy binary and any data files
    find "$clone_dir/target/release" -maxdepth 1 -type f -executable ! -name '*.d' ! -name '*.so' \
        -exec cp {} "$dest_dir/" \;

    # Copy any data/icons/desktop files
    [[ -d "$clone_dir/data" ]] && cp -r "$clone_dir/data" "$dest_dir/" || true

    info "cosmic-app-library built → $dest_dir"

    local sha256
    sha256=$(find "$dest_dir" -type f -executable | head -n1 | xargs sha256sum | awk '{print $1}')
    manifest_add "cosmic-app-library" "$repo_url" "$dest_dir" "$sha256"
}

# =============================================================================
# MAIN — Run all fetch/build steps
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
echo "  Lilith Linux — Host Pre-Build" | tee -a "$LOG_FILE"
echo "  $(date)" | tee -a "$LOG_FILE"
echo "  Staging: $STAGING" | tee -a "$LOG_FILE"
[[ "$DRY_RUN" == "true" ]] && echo "  MODE: DRY RUN (no changes)" | tee -a "$LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"

# ── BlancoBAM .deb releases ────────────────────────────────────────────────────
github_latest_deb "BlancoBAM/Offerings"  "$DEBS" "amd64.deb"
github_latest_deb "BlancoBAM/Tweakers"   "$DEBS" "amd64.deb"
github_latest_deb "BlancoBAM/Stake"      "$DEBS" "amd64.deb"
github_latest_deb "BlancoBAM/Ouija-Pad"  "$DEBS" "amd64.deb"
github_latest_deb "BlancoBAM/Lilim"      "$DEBS" "amd64.deb"

# ── Rust tool .deb releases ────────────────────────────────────────────────────
# bat: use plain amd64.deb (NOT musl variant — musl conflicts with installed packages)
github_latest_deb "sharkdp/bat"          "$DEBS" "bat_"
github_latest_deb "lsd-rs/lsd"           "$DEBS" "amd64.deb"
github_latest_deb "ajeetdsouza/zoxide"   "$DEBS" "amd64.deb"
# fd: use plain amd64.deb (NOT fd-musl — conflicts with pop-launcher's fd-find dep)
github_latest_deb "sharkdp/fd"           "$DEBS" "fd_"
github_latest_deb "BurntSushi/ripgrep"   "$DEBS" "amd64.deb"
github_latest_deb "topgrade-rs/topgrade" "$DEBS" "amd64.deb"

# ── s8n system CLI tool (BlancoBAM) ─────────────────────────────────────────
step "Fetching s8n CLI binary"
S8N_URL="https://github.com/BlancoBAM/S8n-System/releases/download/v0.1.3/s8n-linux-amd64"
S8N_DEST="$BINARIES/s8n"
if [[ -f "$S8N_DEST" ]]; then
    info "Already cached: s8n"
elif [[ "$DRY_RUN" == "true" ]]; then
    dryrun "Would download: $S8N_URL → $S8N_DEST"
else
    if curl -fsSL -o "$S8N_DEST" "$S8N_URL"; then
        chmod 755 "$S8N_DEST"
        info "s8n downloaded: $(du -sh "$S8N_DEST" | cut -f1)"
    else
        warn "s8n download failed from $S8N_URL"
    fi
fi

# ── AppImages ──────────────────────────────────────────────────────────────────
# Vicinae: get latest AppImage URL from GitHub releases
step "Fetching Vicinae latest AppImage"
VICINAE_JSON=$(curl -fsSL "https://api.github.com/repos/vicinaehq/vicinae/releases/latest" 2>/dev/null || echo "{}")
VICINAE_URL=$(echo "$VICINAE_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for a in data.get('assets', []):
    if 'x86_64.AppImage' in a['name'] or 'AppImage' in a['name']:
        print(a['browser_download_url'])
        break
" 2>/dev/null || echo "https://github.com/vicinaehq/vicinae/releases/download/v0.21.0/Vicinae-x86_64.AppImage")
download_appimage "$VICINAE_URL" "Vicinae.AppImage"

# Hyper Terminal AppImage (from BlancoBAM/Lilith-Linux repo)
step "Fetching Hyper AppImage"
HYPER_URL=$(curl -fsSL "https://api.github.com/repos/BlancoBAM/Lilith-Linux/contents/" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for f in data:
    if f.get('name','').startswith('Hyper') and f.get('name','').endswith('.AppImage'):
        print(f.get('download_url',''))
        break
" 2>/dev/null || echo "")

if [[ -n "$HYPER_URL" ]]; then
    download_appimage "$HYPER_URL" "Hyper.AppImage"
else
    warn "Could not auto-detect Hyper AppImage URL. Checking existing AppImage..."
    # Fall back to known URL pattern
    HYPER_URL="https://github.com/BlancoBAM/Lilith-Linux/raw/main/Hyper-3.4.1.AppImage"
    download_appimage "$HYPER_URL" "Hyper.AppImage" || warn "Hyper AppImage fetch failed — add manually to $APPIMAGES/"
fi

# BrowserOS AppImage
step "Fetching BrowserOS AppImage"
BROWSEROS_URL=$(curl -fsSL "https://api.github.com/repos/BlancoBAM/Lilith-Linux/contents/" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for f in data:
    if 'BrowserOS' in f.get('name','') and f.get('name','').endswith('.AppImage'):
        print(f.get('download_url',''))
        break
" 2>/dev/null || echo "")

if [[ -n "$BROWSEROS_URL" ]]; then
    download_appimage "$BROWSEROS_URL" "BrowserOS.AppImage"
else
    warn "BrowserOS AppImage URL not found — add manually to $APPIMAGES/"
fi

# ── Rust source builds (host) ──────────────────────────────────────────────────
build_rust_repo "https://github.com/BlancoBAM/Lilith-TTS"   "Lilith-TTS"   "lilith-tts"
build_rust_repo "https://github.com/BlancoBAM/Shapeshifter" "Shapeshifter" "shapeshifter"
build_cosmic_app_library

# ── Write .gitkeep and .gitignore for staging ──────────────────────────────────
touch "$STAGING/.gitkeep"
cat > "$STAGING/.gitignore" << 'EOF'
# Ignore large binary artifacts in staging
debs/
appimages/
binaries/
build/
*.deb
*.AppImage
*.log
EOF

# ── Final report ───────────────────────────────────────────────────────────────
step "Pre-build complete!"
echo ""
echo "  Staging directory: $STAGING"
echo ""
echo "  DEBs:"
ls -lh "$DEBS"/*.deb 2>/dev/null | awk '{print "    "$NF" ("$5")"}' || echo "    (none)"
echo ""
echo "  AppImages:"
ls -lh "$APPIMAGES"/*.AppImage 2>/dev/null | awk '{print "    "$NF" ("$5")"}' || echo "    (none)"
echo ""
echo "  Binaries:"
ls -lh "$BINARIES"/ 2>/dev/null | awk '{print "    "$NF" ("$5")"}' || echo "    (none)"
echo ""
echo "  Manifest: $MANIFEST"
echo ""
info "Run configure-lilith-os.sh next (as root/sudo) to apply to the Cubic chroot."
