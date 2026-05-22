#!/usr/bin/env bash
# =============================================================================
# install_flame_prompt.sh
# Installs Starship and configures a flaming powerline-style prompt for
# Pop!_OS / Ubuntu, exactly matching the "flames (flamey)" color scheme from:
#   https://github.com/ryanoasis/powerline-extra-symbols/blob/master/milkbikis/themes/flames.py
#
# Flame separator glyphs (Nerd Fonts / Powerline Extra Symbols):
#   U+E0C0  — filled flame separator  (used for ALL transitions, doubled for width)
#
# Color scheme — converted from xterm-256 indices in flames.py:
#   Username  bg 226 → #ffff00  fg 250 → #bcbcbc  (yellow bg, light-grey text)
#   Home/~    bg 208 → #ff8700  fg  15 → #ffffff  (orange bg, white text)
#   Path      bg 166 → #d75f00  fg  15 → #ffffff  (burnt-orange bg, white text)
#   💀 prompt  bg 160 → #d70000  fg  15 → #ffffff  (red bg, white text)
#   Separator fg  15 → #ffffff  (white glyph, bg = next segment's colour)
#
# Key design notes:
#   1. ALL separators use U+E0C0 (filled flame) — including the trailing one.
#      U+E0C1 (thin/outline) is intentionally NOT used; it renders as an outline
#      which looks visually inconsistent with the filled flames.
#   2. Each separator is DOUBLED (two U+E0C0 glyphs side-by-side) to make the
#      flame transition wider, matching the original screenshot proportions.
#   3. Glyphs are placed INSIDE [] brackets so they inherit the correct fg/bg
#      colours and fill the full terminal cell height without gaps.
#   4. A skull emoji 💀 replaces the dollar sign (avoids Starship format-string
#      parser issues with literal "$" characters).
#   5. Directory uses truncation_length = 100 + absolute_path = true for full
#      absolute path display.
#   6. Config is written via Python so UTF-8 glyphs are embedded as real bytes.
# =============================================================================

set -euo pipefail

BOLD='\033[1m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

info()    { echo -e "${YELLOW}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

echo -e "${BOLD}"
echo "  🔥  Flame Prompt Installer for Pop!_OS / Ubuntu"
echo "  ================================================"
echo "  Colors sourced from: ryanoasis/powerline-extra-symbols"
echo -e "${RESET}"

# ---------------------------------------------------------------------------
# 1. Install system dependencies
# ---------------------------------------------------------------------------
info "Checking for required system packages..."

PKGS_NEEDED=()
command -v curl     &>/dev/null || PKGS_NEEDED+=(curl)
command -v wget     &>/dev/null || PKGS_NEEDED+=(wget)
command -v unzip    &>/dev/null || PKGS_NEEDED+=(unzip)
command -v python3  &>/dev/null || PKGS_NEEDED+=(python3)
command -v fc-cache &>/dev/null || PKGS_NEEDED+=(fontconfig)

if [[ ${#PKGS_NEEDED[@]} -gt 0 ]]; then
    info "Installing missing packages: ${PKGS_NEEDED[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${PKGS_NEEDED[@]}"
fi

success "System dependencies satisfied."

# ---------------------------------------------------------------------------
# 2. Install Starship
# ---------------------------------------------------------------------------
if command -v starship &>/dev/null; then
    success "Starship already installed: $(starship --version | head -1)"
else
    info "Installing Starship (latest release)..."
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
    success "Starship installed: $(starship --version | head -1)"
fi

# ---------------------------------------------------------------------------
# 3. Install FiraCode Nerd Font (provides U+E0C0 flame glyphs)
# ---------------------------------------------------------------------------
FONT_DIR="${HOME}/.local/share/fonts"
mkdir -p "${FONT_DIR}"

if ls "${FONT_DIR}"/FiraCodeNerdFont*.ttf &>/dev/null 2>&1; then
    success "FiraCode Nerd Font already installed."
else
    info "Downloading FiraCode Nerd Font..."
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip"
    TMP_ZIP="$(mktemp /tmp/FiraCode_XXXXXX.zip)"

    if wget -q --show-progress -O "${TMP_ZIP}" "${FONT_URL}"; then
        info "Extracting font files..."
        unzip -qo "${TMP_ZIP}" -d "${FONT_DIR}" '*.ttf'
        rm -f "${TMP_ZIP}"
        info "Refreshing font cache..."
        fc-cache -f "${FONT_DIR}"
        success "FiraCode Nerd Font installed to ${FONT_DIR}"
    else
        error "Font download failed. Install manually from: https://www.nerdfonts.com/font-downloads"
        error "The prompt will still work but flame glyphs may not render correctly."
    fi
fi

# ---------------------------------------------------------------------------
# 4. Write Starship configuration via Python
#
# Python is used so that:
#   a) U+E0C0 is embedded as a real UTF-8 byte (not a \uXXXX string).
#   b) Glyphs are placed INSIDE [] brackets with correct fg/bg styling.
# ---------------------------------------------------------------------------
CONFIG_DIR="${HOME}/.config"
STARSHIP_CONFIG="${CONFIG_DIR}/starship.toml"
mkdir -p "${CONFIG_DIR}"

if [[ -f "${STARSHIP_CONFIG}" ]]; then
    BACKUP="${STARSHIP_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "${STARSHIP_CONFIG}" "${BACKUP}"
    info "Existing config backed up to: ${BACKUP}"
fi

info "Writing Starship flame prompt configuration..."

python3 - "${STARSHIP_CONFIG}" << 'PYEOF'
import sys

path = sys.argv[1]

# ── Flame separator glyph ─────────────────────────────────────────────────────
# U+E0C0 = filled flame (used for ALL separators, including the trailing one)
# U+E0C1 = thin/outline flame — intentionally NOT used (renders as outline gap)
F = '\uE0C0'

# ── Exact colors from ryanoasis/powerline-extra-symbols flames.py ─────────────
# xterm-256 → hex:  226→#ffff00  208→#ff8700  166→#d75f00  160→#d70000
#                   250→#bcbcbc   15→#ffffff
USERNAME_BG = '#ffff00'
USERNAME_FG = '#bcbcbc'
HOME_BG     = '#ff8700'
HOME_FG     = '#ffffff'
PATH_BG     = '#d75f00'
PATH_FG     = '#ffffff'
CMD_BG      = '#d70000'
CMD_FG      = '#ffffff'
SEP_FG      = '#ffffff'   # separator glyph foreground (always white per flames.py)
TERM_BG     = 'none'      # terminal background (transparent — no bg on trailing sep)

# ── Separator helper ──────────────────────────────────────────────────────────
# Each separator is TWO filled flame glyphs side-by-side for extra width.
# The separator segment: [FF](fg=white bg=NEXT_SEGMENT_BG)
# This makes the white flame shapes appear on the next colour's background,
# creating a seamless wide transition between segments.
def sep(next_bg):
    """Two filled flames transitioning into next_bg."""
    return f'[{F}{F}](fg:{SEP_FG} bg:{next_bg})'

def sep_trailing():
    """Two filled flames at the end — transparent/terminal background."""
    return f'[{F}{F}](fg:{CMD_BG})'

config = f'''\
# =============================================================================
# Starship — Flames (Flamey) Prompt
# Colors: ryanoasis/powerline-extra-symbols/milkbikis/themes/flames.py
# Separator: U+E0C0 (filled flame, doubled for width) — Nerd Fonts required
# =============================================================================

"$schema" = 'https://starship.rs/config-schema.json'

format = """
[$username](bg:{USERNAME_BG} fg:{USERNAME_FG} bold){sep(HOME_BG)}[$directory](bg:{HOME_BG} fg:{HOME_FG} bold){sep(PATH_BG)}[$git_branch$git_status](bg:{PATH_BG} fg:{PATH_FG}){sep(CMD_BG)}$custom{sep_trailing()}
$character"""

add_newline = false

# ── Username ──────────────────────────────────────────────────────────────────
[username]
show_always = true
style_user  = "bg:{USERNAME_BG} fg:{USERNAME_FG} bold"
style_root  = "bg:{USERNAME_BG} fg:{CMD_BG} bold"
format      = "[ $user ]($style)"

# ── Directory — absolute path, no truncation ──────────────────────────────────
[directory]
style             = "bg:{HOME_BG} fg:{HOME_FG} bold"
format            = "[ $path ]($style)"
truncation_length = 100
truncate_to_repo  = false
use_logical_path  = false

[directory.substitutions]
"~" = "~"

# ── Git branch ────────────────────────────────────────────────────────────────
[git_branch]
symbol = " "
style  = "bg:{PATH_BG} fg:{PATH_FG}"
format = "[ $symbol$branch ]($style)"

# ── Git status ────────────────────────────────────────────────────────────────
[git_status]
style      = "bg:{PATH_BG} fg:{PATH_FG} bold"
format     = "([$all_status$ahead_behind]($style) )"
conflicted = "!"
ahead      = "⇡"
behind     = "⇣"
diverged   = "⇕"
untracked  = "?"
modified   = "*"
staged     = "+"
deleted    = "✘"

# ── Skull segment (replaces dollar sign) ─────────────────────────────────────
# A literal "$" in a Starship format text segment is parsed as a variable
# reference, causing a parse error.  The skull emoji is output via a custom
# module shell command, bypassing the format-string parser entirely.
[custom.dollar]
command = "printf ' 💀 '"
when    = "true"
style   = "bg:{CMD_BG} fg:{CMD_FG} bold"
format  = "[$output]($style)"

# ── Input cursor (second line) ────────────────────────────────────────────────
[character]
success_symbol = "[❯](bold {HOME_BG})"
error_symbol   = "[❯](bold {CMD_BG})"

# ── Command duration ──────────────────────────────────────────────────────────
[cmd_duration]
min_time = 2000
format   = " took [$duration](bold {USERNAME_BG}) "
disabled = false

# ── Disable noisy language/tool modules (re-enable as needed) ─────────────────
[package]
disabled = true

[nodejs]
disabled = true

[python]
disabled = true

[rust]
disabled = true

[golang]
disabled = true

[java]
disabled = true

[docker_context]
disabled = true
'''

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(config)

print(f"Config written to: {path}")

# Verify: count flame glyphs inside brackets
import re
start = config.find('format = """')
end   = config.find('"""', start + 12)
fmt   = config[start:end+3]
segs  = re.findall(r'\[([^\]]*)\]\([^)]+\)', fmt)
flame_segs = [s for s in segs if '\uE0C0' in s]
total_glyphs = sum(s.count('\uE0C0') for s in flame_segs)
print(f"Separator segments inside []: {len(flame_segs)} (expected 4)")
print(f"Total U+E0C0 glyphs inside []: {total_glyphs} (expected 8 — 4 separators × 2 glyphs each)")
thin_glyphs = sum(s.count('\uE0C1') for s in segs)
print(f"U+E0C1 thin/outline glyphs: {thin_glyphs} (expected 0 — none used)")
PYEOF

success "Starship configuration written to: ${STARSHIP_CONFIG}"

# ---------------------------------------------------------------------------
# 5. Hook Starship into the user's shell(s)
# ---------------------------------------------------------------------------
CURRENT_SHELL="$(basename "${SHELL:-bash}")"
info "Detected shell: ${CURRENT_SHELL}"

hook_bash() {
    local rc="${HOME}/.bashrc"
    if grep -q 'starship init bash' "${rc}" 2>/dev/null; then
        success "Starship hook already present in ${rc}"
    else
        printf '\n# Starship prompt\neval "$(starship init bash)"\n' >> "${rc}"
        success "Starship hook added to ${rc}"
    fi
}

hook_zsh() {
    local rc="${HOME}/.zshrc"
    if grep -q 'starship init zsh' "${rc}" 2>/dev/null; then
        success "Starship hook already present in ${rc}"
    else
        printf '\n# Starship prompt\neval "$(starship init zsh)"\n' >> "${rc}"
        success "Starship hook added to ${rc}"
    fi
}

hook_fish() {
    local cfg="${HOME}/.config/fish/config.fish"
    mkdir -p "$(dirname "${cfg}")"
    if grep -q 'starship init fish' "${cfg}" 2>/dev/null; then
        success "Starship hook already present in ${cfg}"
    else
        printf '\n# Starship prompt\nstarship init fish | source\n' >> "${cfg}"
        success "Starship hook added to ${cfg}"
    fi
}

hook_bash
case "${CURRENT_SHELL}" in
    zsh)  hook_zsh ;;
    fish) hook_fish ;;
esac

# ---------------------------------------------------------------------------
# 6. Final instructions
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}✅  Installation complete!${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo ""
echo "  1. Set your terminal font to 'FiraCode Nerd Font' (or any Nerd Font)"
echo "     so that the flame separator glyphs (U+E0C0) render correctly."
echo ""
echo "     Pop!_OS (GNOME Terminal):"
echo "       Preferences → Your profile → Text → Custom font"
echo "       → FiraCode Nerd Font  (size 12 or 13 recommended)"
echo ""
echo "  2. Reload your shell:"
echo "       source ~/.bashrc"
echo "     or open a new terminal window."
echo ""
echo "  3. (Optional) Re-enable language modules in ~/.config/starship.toml"
echo "     by setting  disabled = false  for nodejs, python, rust, etc."
echo ""
echo -e "${YELLOW}🔥  Enjoy your flame prompt!${RESET}"
