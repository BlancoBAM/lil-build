#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — Master Build Orchestrator
# =============================================================================
# The single entry point for all Lilith Linux build operations.
#
# Usage:
#   bash /home/aegon/lil-build/lilith-build.sh [OPTIONS]
#
# Options:
#   --all              Run ALL stages in sequence (full build)
#   --fetch-versions   Query GitHub API, update lilith-debrep.toml versions
#   --build-repo       Build Packages/Release indexes (apt repo)
#   --deploy-pages     Push built repo to BlancoBAM/lilith-packages GitHub Pages
#   --stage-assets     Run pre-build-host.sh (fetch debs/appimages/binaries)
#   --configure-chroot Run configure-lilith-os.sh on custom-root chroot
#   --brand-chroot     Apply Lilith branding (fonts, cursors, SDDM, Plymouth, etc.)
#   --dry-run          Show what would be done without making changes
#   --help             Show this help message
#
# Examples:
#   # Full production build:
#   sudo bash lilith-build.sh --all
#
#   # Update package versions only:
#   bash lilith-build.sh --fetch-versions
#
#   # Rebuild repo + deploy:
#   bash lilith-build.sh --build-repo --deploy-pages
#
#   # Apply branding to chroot only:
#   sudo bash lilith-build.sh --brand-chroot
#
#   # Preview what --all would do:
#   bash lilith-build.sh --all --dry-run
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROOT="/home/aegon/Lilith/custom-root"
REPO_DIR="$SCRIPT_DIR/Lilith-Repo"
PAGES_REPO_DIR="/home/aegon/lilith-packages"
LOG_FILE="$SCRIPT_DIR/lilith-build-$(date +%Y%m%d-%H%M%S).log"

# ── Colors & Helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'
info()    { echo -e "${GREEN}[✔]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
err()     { echo -e "${RED}[✘]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
step()    { echo -e "\n${MAGENTA}╔══════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
            echo -e "${MAGENTA}║  $*${NC}" | tee -a "$LOG_FILE"
            echo -e "${MAGENTA}╚══════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"; }
note()    { echo -e "${CYAN}  →${NC} $*" | tee -a "$LOG_FILE"; }

: > "$LOG_FILE"

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════╗
║        Lilith Linux — Master Build Orchestrator              ║
╚══════════════════════════════════════════════════════════════╝

Usage: bash lilith-build.sh [OPTIONS]

STAGE OPTIONS:
  --all              Run ALL stages in sequence (requires root)
  --fetch-versions   Query GitHub API, update package versions in TOML
  --build-repo       Build apt Packages/Release indexes
  --deploy-pages     Push repo to BlancoBAM/lilith-packages (GitHub Pages)
  --stage-assets     Fetch all debs/appimages/binaries (pre-build-host.sh)
  --configure-chroot Configure chroot OS settings (requires root)
  --brand-chroot     Apply Lilith branding to chroot (requires root)

MODIFIERS:
  --dry-run          Preview changes without modifying anything
  --help             Show this help

EXAMPLES:
  # Full rebuild (recommended workflow):
  sudo bash lilith-build.sh --all

  # Quick: just update versions + rebuild repo + deploy:
  bash lilith-build.sh --fetch-versions --build-repo --deploy-pages

  # Apply branding only (after updating assets):
  sudo bash lilith-build.sh --brand-chroot

  # Preview everything without changes:
  bash lilith-build.sh --all --dry-run

STAGE SEQUENCE (when using --all):
  1. fetch-versions    (auto-update TOML from GitHub API)
  2. stage-assets      (download all packages to staging/)
  3. build-repo        (generate apt Packages/Release indexes)
  4. deploy-pages      (push to GitHub Pages)
  5. configure-chroot  (apply OS configuration to chroot)
  6. brand-chroot      (apply Lilith branding to chroot)

NOTES:
  - Stages 5 & 6 require root (sudo)
  - After running --configure-chroot and/or --brand-chroot,
    open Cubic and rebuild the ISO to capture changes
  - Log file: ~/lil-build/lilith-build-YYYYMMDD-HHMMSS.log

EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
DO_FETCH_VERSIONS=false
DO_BUILD_REPO=false
DO_DEPLOY_PAGES=false
DO_STAGE_ASSETS=false
DO_CONFIGURE_CHROOT=false
DO_BRAND_CHROOT=false
DO_ALL=false
DRY_RUN=false

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)               DO_ALL=true ;;
        --fetch-versions)    DO_FETCH_VERSIONS=true ;;
        --build-repo)        DO_BUILD_REPO=true ;;
        --deploy-pages)      DO_DEPLOY_PAGES=true ;;
        --stage-assets)      DO_STAGE_ASSETS=true ;;
        --configure-chroot)  DO_CONFIGURE_CHROOT=true ;;
        --brand-chroot)      DO_BRAND_CHROOT=true ;;
        --dry-run)           DRY_RUN=true ;;
        --help|-h)           usage; exit 0 ;;
        *)                   echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# Expand --all
if $DO_ALL; then
    DO_FETCH_VERSIONS=true
    DO_STAGE_ASSETS=true
    DO_BUILD_REPO=true
    DO_DEPLOY_PAGES=true
    DO_CONFIGURE_CHROOT=true
    DO_BRAND_CHROOT=true
fi

# ── Root check for chroot operations ─────────────────────────────────────────
if ($DO_CONFIGURE_CHROOT || $DO_BRAND_CHROOT) && [[ $EUID -ne 0 ]]; then
    err "Stages --configure-chroot and --brand-chroot require root. Use: sudo bash $0 $*"
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "
${MAGENTA}
  ██╗     ██╗██╗     ██╗████████╗██╗  ██╗
  ██║     ██║██║     ██║╚══██╔══╝██║  ██║
  ██║     ██║██║     ██║   ██║   ███████║
  ██║     ██║██║     ██║   ██║   ██╔══██║
  ███████╗██║███████╗██║   ██║   ██║  ██║
  ╚══════╝╚═╝╚══════╝╚═╝   ╚═╝   ╚═╝  ╚═╝
  Linux Build System — Master Orchestrator${NC}
" | tee -a "$LOG_FILE"

echo -e "  Log: ${CYAN}$LOG_FILE${NC}\n" | tee -a "$LOG_FILE"
$DRY_RUN && echo -e "  ${YELLOW}[DRY-RUN MODE] No changes will be made${NC}\n" | tee -a "$LOG_FILE"

START_TIME=$(date +%s)

# =============================================================================
# STAGE 1 — Fetch Latest Versions
# =============================================================================
if $DO_FETCH_VERSIONS; then
    step "STAGE 1 — Fetch Latest Package Versions"
    FETCH_ARGS=""
    $DRY_RUN && FETCH_ARGS="--dry-run"
    bash "$SCRIPT_DIR/fetch-versions.sh" $FETCH_ARGS
    info "Version fetch complete"
fi

# =============================================================================
# STAGE 2 — Stage Assets (pre-build-host.sh)
# =============================================================================
if $DO_STAGE_ASSETS; then
    step "STAGE 2 — Stage Assets (Download Packages)"
    STAGE_ARGS=""
    $DRY_RUN && STAGE_ARGS="--dry-run"
    bash "$SCRIPT_DIR/pre-build-host.sh" $STAGE_ARGS
    info "Asset staging complete"
fi

# =============================================================================
# STAGE 3 — Build APT Repository
# =============================================================================
if $DO_BUILD_REPO; then
    step "STAGE 3 — Build APT Package Repository"
    if $DRY_RUN; then
        note "[DRY-RUN] Would run: python3 $SCRIPT_DIR/build_lilith_repo.py"
    else
        python3 "$SCRIPT_DIR/build_lilith_repo.py"
        info "Repository build complete"
        note "Output: $REPO_DIR"
    fi
fi

# =============================================================================
# STAGE 4 — Deploy to GitHub Pages (lilith-packages)
# =============================================================================
if $DO_DEPLOY_PAGES; then
    step "STAGE 4 — Deploy to GitHub Pages (lilith-packages)"

    [[ -d "$PAGES_REPO_DIR" ]] || err "lilith-packages repo not found at $PAGES_REPO_DIR. Clone it first: git clone git@github.com:BlancoBAM/lilith-packages.git ~/lilith-packages"
    [[ -d "$REPO_DIR" ]] || err "Built repo not found at $REPO_DIR. Run --build-repo first."

    if $DRY_RUN; then
        note "[DRY-RUN] Would sync $REPO_DIR/dists + $REPO_DIR/pool → $PAGES_REPO_DIR and push"
    else
        # Sync only dists/ and pool/ — preserve static Pages files (index.html, README.md, etc.)
        note "Syncing dists/ to pages repo..."
        rsync -av --delete \
            --exclude='.git' \
            "$REPO_DIR/dists/" "$PAGES_REPO_DIR/dists/"

        note "Syncing pool/ to pages repo..."
        rsync -av --delete \
            --exclude='.git' \
            "$REPO_DIR/pool/" "$PAGES_REPO_DIR/pool/"

        # Copy support files (manifests, keyrings)
        cp -f "$SCRIPT_DIR/lilith-archive-keyring.asc" "$PAGES_REPO_DIR/public-key.asc" 2>/dev/null || true
        cp -f "$SCRIPT_DIR/lilith-archive-keyring.gpg" "$PAGES_REPO_DIR/lilith-archive-keyring.gpg" 2>/dev/null || true
        [[ -f "$REPO_DIR/lilith-distro-manifest.json" ]] && \
            cp -f "$REPO_DIR/lilith-distro-manifest.json" "$PAGES_REPO_DIR/" || true

        # Commit and push
        cd "$PAGES_REPO_DIR"
        git add -A
        if git diff --staged --quiet; then
            info "No changes to deploy"
        else
            git commit -m "chore: update package repository $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            GH_TOKEN="" git push origin main
            info "Deployed to GitHub Pages: https://blancobam.github.io/lilith-packages"
        fi
        cd "$SCRIPT_DIR"
    fi
fi

# =============================================================================
# STAGE 5 — Configure Chroot (configure-lilith-os.sh)
# =============================================================================
if $DO_CONFIGURE_CHROOT; then
    step "STAGE 5 — Configure Chroot OS"
    CONFIGURE_SCRIPT="/home/aegon/Lilith/configure-lilith-os.sh"

    [[ -f "$CONFIGURE_SCRIPT" ]] || err "configure-lilith-os.sh not found at $CONFIGURE_SCRIPT"

    if $DRY_RUN; then
        note "[DRY-RUN] Would run: sudo bash $CONFIGURE_SCRIPT"
    else
        bash "$CONFIGURE_SCRIPT"
        info "Chroot OS configuration complete"
    fi
fi

# =============================================================================
# STAGE 6 — Brand Chroot (lilith-brand.sh)
# =============================================================================
if $DO_BRAND_CHROOT; then
    step "STAGE 6 — Apply Lilith Branding to Chroot"

    BRAND_ARGS=""
    $DRY_RUN && BRAND_ARGS="--dry-run"
    bash "$SCRIPT_DIR/lilith-brand.sh" $BRAND_ARGS
    info "Branding complete"
fi

# =============================================================================
# SUMMARY
# =============================================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

step "Build Summary"
info "Completed in ${ELAPSED}s"
info "Log: $LOG_FILE"

if $DO_BRAND_CHROOT || $DO_CONFIGURE_CHROOT; then
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  NEXT STEPS: Rebuild ISO                            ║${NC}"
    echo -e "${GREEN}║  1. Open Cubic → select ~/Lilith project            ║${NC}"
    echo -e "${GREEN}║  2. Verify changes in chroot terminal               ║${NC}"
    echo -e "${GREEN}║  3. Generate ISO → Lilith-Linux-amd64.iso           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
fi

echo -e "\n${GREEN}✔ Lilith Linux build orchestrator complete${NC}"
