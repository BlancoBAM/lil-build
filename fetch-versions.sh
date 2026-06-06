#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — GitHub Release Version Fetcher
# =============================================================================
# Queries GitHub Releases API for all packages with auto_update = true
# and updates version/upstream fields in lilith-debrep.toml.
#
# Usage:
#   bash /home/aegon/lil-build/fetch-versions.sh [--dry-run]
#
# Requires: gh CLI authenticated as BlancoBAM, or GH_TOKEN env var set
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOML="$SCRIPT_DIR/lilith-debrep.toml"
LOG_FILE="$SCRIPT_DIR/fetch-versions-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✔]${NC} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
err()   { echo -e "${RED}[✘]${NC} $*" | tee -a "$LOG_FILE"; }
step()  { echo -e "\n${BLUE}══${NC} $* ${BLUE}══${NC}" | tee -a "$LOG_FILE"; }

: > "$LOG_FILE"
step "Lilith Linux — Release Version Fetcher"
[[ -f "$TOML" ]] || { err "TOML not found: $TOML"; exit 1; }

# ── GitHub API helper ─────────────────────────────────────────────────────────
# Usage: gh_latest_release <owner/repo>
# Returns: tag name (e.g. v1.2.3)
gh_latest_release() {
    local repo="$1"
    local tag
    # Prefer gh CLI (handles auth automatically), fall back to curl + GH_TOKEN
    if command -v gh &>/dev/null; then
        tag=$(GH_TOKEN="" gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null) || true
    fi
    if [[ -z "${tag:-}" ]] && [[ -n "${GH_TOKEN:-}" ]]; then
        tag=$(curl -fsSL -H "Authorization: token $GH_TOKEN" \
            "https://api.github.com/repos/${repo}/releases/latest" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name',''))" 2>/dev/null) || true
    fi
    echo "${tag:-}"
}

# Usage: gh_latest_asset <owner/repo> <pattern>
# Returns: download URL matching pattern
gh_latest_asset() {
    local repo="$1"
    local pattern="$2"
    local url
    if command -v gh &>/dev/null; then
        url=$(GH_TOKEN="" gh api "repos/${repo}/releases/latest" --jq \
            ".assets[] | select(.name | test(\"${pattern}\")) | .browser_download_url" \
            2>/dev/null | head -1) || true
    fi
    echo "${url:-}"
}

# Strip leading 'v' from tag
strip_v() { echo "${1#v}"; }

# In-place TOML field update
# Usage: update_toml_field <key_pattern> <new_value>
# Updates the FIRST matching line containing key_pattern = "..."
update_field() {
    local field="$1"
    local new_val="$2"
    local pkg_section="$3"
    if $DRY_RUN; then
        echo -e "  ${CYAN}[DRY-RUN]${NC} Would update [$pkg_section] $field = \"$new_val\""
        return
    fi
    # Find the block for this package and update just that field
    python3 - "$TOML" "$pkg_section" "$field" "$new_val" <<'PYEOF'
import sys, re

toml_file, section, field, new_val = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(toml_file, 'r') as f:
    lines = f.readlines()

in_section = False
section_pattern = re.compile(r'^\[' + re.escape(section) + r'\]')
next_section_pattern = re.compile(r'^\[')
field_pattern = re.compile(r'^(' + re.escape(field) + r'\s*=\s*)"[^"]*"')
updated = False

for i, line in enumerate(lines):
    if section_pattern.match(line):
        in_section = True
    elif in_section and next_section_pattern.match(line) and not section_pattern.match(line):
        if not section_pattern.match(line):
            in_section = False
    if in_section and field_pattern.match(line):
        lines[i] = field_pattern.sub(r'\g<1>"' + new_val + '"', line)
        updated = True
        break

if updated:
    with open(toml_file, 'w') as f:
        f.writelines(lines)
    print(f"  Updated [{section}] {field} = \"{new_val}\"")
else:
    print(f"  WARNING: Could not find [{section}] {field}")
PYEOF
}

# =============================================================================
# PACKAGE DEFINITIONS — maps TOML section → GitHub repo → asset pattern
# =============================================================================

declare -A PKG_REPO PKG_ASSET_PATTERN PKG_DEB_PATTERN

# BlancoBAM packages
PKG_REPO["lilith_packages.main.offerings"]="BlancoBAM/Offerings"
PKG_ASSET_PATTERN["lilith_packages.main.offerings"]="amd64.deb"

PKG_REPO["lilith_packages.main.tweakers"]="BlancoBAM/Tweakers"
PKG_ASSET_PATTERN["lilith_packages.main.tweakers"]="amd64.deb"

PKG_REPO["lilith_packages.main.lilim"]="BlancoBAM/Lilim"
PKG_ASSET_PATTERN["lilith_packages.main.lilim"]="amd64.deb"

PKG_REPO["lilith_packages.main.stake"]="BlancoBAM/Stake"
PKG_ASSET_PATTERN["lilith_packages.main.stake"]="amd64.deb"

PKG_REPO["lilith_packages.main.ouija-pad"]="BlancoBAM/Ouija-Pad"
PKG_ASSET_PATTERN["lilith_packages.main.ouija-pad"]="amd64.deb"

# Third-party CLI tools
PKG_REPO["lilith_packages.main.lsd"]="lsd-rs/lsd"
PKG_ASSET_PATTERN["lilith_packages.main.lsd"]="amd64.deb"

PKG_REPO["lilith_packages.main.zoxide"]="ajeetdsouza/zoxide"
PKG_ASSET_PATTERN["lilith_packages.main.zoxide"]="amd64.deb"

PKG_REPO["lilith_packages.main.bat"]="sharkdp/bat"
PKG_ASSET_PATTERN["lilith_packages.main.bat"]="amd64.deb"

PKG_REPO["lilith_packages.main.topgrade"]="topgrade-rs/topgrade"
PKG_ASSET_PATTERN["lilith_packages.main.topgrade"]="amd64.deb"

PKG_REPO["lilith_packages.main.fd"]="sharkdp/fd"
PKG_ASSET_PATTERN["lilith_packages.main.fd"]="x86_64-unknown-linux-musl.tar.gz"

PKG_REPO["lilith_packages.main.xcp"]="tarka/xcp"
PKG_ASSET_PATTERN["lilith_packages.main.xcp"]="x86_64-unknown-linux-gnu.tar.gz"

PKG_REPO["lilith_packages.main.navi"]="denisidoro/navi"
PKG_ASSET_PATTERN["lilith_packages.main.navi"]="x86_64-unknown-linux-musl.tar.gz"

PKG_REPO["lilith_packages.main.systeroid"]="orhun/systeroid"
PKG_ASSET_PATTERN["lilith_packages.main.systeroid"]="x86_64-unknown-linux-musl.tar.gz"

PKG_REPO["lilith_packages.main.rnr"]="ismaelgv/rnr"
PKG_ASSET_PATTERN["lilith_packages.main.rnr"]="x86_64"

PKG_REPO["lilith_packages.main.czkawka"]="qarmin/czkawka"
PKG_ASSET_PATTERN["lilith_packages.main.czkawka"]="linux"

PKG_REPO["lilith_packages.main.astral-uv"]="astral-sh/uv"
PKG_ASSET_PATTERN["lilith_packages.main.astral-uv"]="x86_64-unknown-linux-musl.tar.gz"

PKG_REPO["lilith_packages.main.gemini-cli"]="google-gemini/gemini-cli"
PKG_ASSET_PATTERN["lilith_packages.main.gemini-cli"]="linux"

# Xtra packages
PKG_REPO["lilith_packages.xtra.ferdium"]="ferdium/ferdium-app"
PKG_ASSET_PATTERN["lilith_packages.xtra.ferdium"]="AppImage"

PKG_REPO["lilith_packages.xtra.waveterm"]="wavetermdev/waveterm"
PKG_ASSET_PATTERN["lilith_packages.xtra.waveterm"]="amd64.deb"

PKG_REPO["lilith_packages.xtra.spacedrive"]="spacedriveapp/spacedrive"
PKG_ASSET_PATTERN["lilith_packages.xtra.spacedrive"]="x86_64.AppImage"

# =============================================================================
# MAIN LOOP
# =============================================================================

step "Fetching latest release versions from GitHub API"

UPDATED=0
FAILED=0
UNCHANGED=0

for section in "${!PKG_REPO[@]}"; do
    repo="${PKG_REPO[$section]}"
    asset_pattern="${PKG_ASSET_PATTERN[$section]:-}"
    pkg_name="${section##*.}"

    echo -e "\n${BLUE}→${NC} $pkg_name ($repo)"

    tag=$(gh_latest_release "$repo")
    if [[ -z "$tag" ]]; then
        warn "  Could not get latest release for $repo"
        ((FAILED++)) || true
        continue
    fi

    version=$(strip_v "$tag")
    info "  Latest: $tag (version: $version)"

    # Get asset URL if pattern provided
    if [[ -n "$asset_pattern" ]]; then
        asset_url=$(gh_latest_asset "$repo" "$asset_pattern")
        if [[ -n "$asset_url" ]]; then
            info "  Asset: $asset_url"
            update_field "upstream" "$asset_url" "$section"
        else
            warn "  No matching asset for pattern: $asset_pattern"
        fi
    fi

    update_field "version" "$version" "$section"
    ((UPDATED++)) || true
done

step "Version Fetch Summary"
info "Updated: $UPDATED packages"
[[ $FAILED -gt 0 ]] && warn "Failed: $FAILED packages"
info "Log: $LOG_FILE"

$DRY_RUN && echo -e "\n${CYAN}[DRY-RUN MODE] No changes were written.${NC}"
