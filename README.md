# lil-build — Lilith Linux Build System

> **Master build system for [Lilith Linux](https://github.com/BlancoBAM/Lilith-Linux)** — a custom Ubuntu 26.04–based distribution with COSMIC Desktop.

---

## Overview

`lil-build` contains all scripts, configuration, and branding assets for building and maintaining Lilith Linux. The central entry point is **`lilith-build.sh`**, which orchestrates all build stages.

```
lilith-build.sh [OPTIONS]

STAGE OPTIONS:
  --all              Run ALL stages in sequence (requires root)
  --fetch-versions   Query GitHub API, update package versions in TOML
  --build-repo       Build APT Packages/Release indexes
  --deploy-pages     Push built repo to BlancoBAM/lilith-packages (GitHub Pages)
  --stage-assets     Fetch all debs/appimages/binaries (pre-build-host.sh)
  --configure-chroot Configure chroot OS settings (requires root)
  --brand-chroot     Apply Lilith branding to chroot (requires root)

MODIFIERS:
  --dry-run          Preview changes without modifying anything
```

## Package Repository

The built APT repository is published at:
**[https://blancobam.github.io/lilith-packages](https://blancobam.github.io/lilith-packages)**

```bash
# Add to /etc/apt/sources.list.d/lilith-linux.list:
deb [arch=amd64 signed-by=/usr/share/keyrings/lilith-archive-keyring.gpg] \
  https://blancobam.github.io/lilith-packages stable main xtra
```

## Scripts

| Script | Purpose |
|---|---|
| [`lilith-build.sh`](lilith-build.sh) | Master orchestrator — all stages via flags |
| [`fetch-versions.sh`](fetch-versions.sh) | GitHub API version updater for `lilith-debrep.toml` |
| [`build_lilith_repo.py`](build_lilith_repo.py) | Python APT repo builder (TOML-driven, generates .deb wrappers) |
| [`build-repo.sh`](build-repo.sh) | Shell APT repo builder (lightweight, uses pool/) |
| [`lilith-brand.sh`](lilith-brand.sh) | Branding applier for chroot (Plymouth, SDDM, COSMIC, fonts, cursors, Calamares) |
| [`pre-build-host.sh`](pre-build-host.sh) | Downloads all packages to staging/ |
| [`configure-chroot-apt-sources.sh`](configure-chroot-apt-sources.sh) | Configures APT sources inside chroot |

## Configuration

| File | Purpose |
|---|---|
| [`lilith-debrep.toml`](lilith-debrep.toml) | Package specification (all 154+ packages, sources, versions) |
| [`lilith-theme.toml`](lilith-theme.toml) | Color palette, fonts, SDDM/COSMIC/Plymouth settings |
| [`.github/workflows/build-repo.yml`](.github/workflows/build-repo.yml) | GitHub Actions CI (auto-build + deploy on TOML changes) |

## Assets

| Directory | Contents |
|---|---|
| `assets/wallpapers/` | Desktop wallpapers (default: `def.png`) |
| `sddm-theme/lilith/` | SDDM login screen theme (QML + background.webp) |
| `calamares-branding/lilith/` | Calamares installer branding (QSS, QML slideshow, logos) |
| `pkgs/` | Package lists (`lil-core.txt`, etc.) |

## Typical Workflow

```bash
# 1. Check/update package versions
bash lilith-build.sh --fetch-versions

# 2. Rebuild the APT repo
bash lilith-build.sh --build-repo

# 3. Deploy to GitHub Pages
bash lilith-build.sh --deploy-pages

# 4. Apply branding to chroot (requires root)
sudo bash lilith-build.sh --brand-chroot

# 5. Rebuild ISO via Cubic
# Open Cubic → ~/Lilith project → Generate ISO
```

## GitHub Actions

The workflow at [`.github/workflows/build-repo.yml`](.github/workflows/build-repo.yml) automatically:
- Runs on push to `lilith-debrep.toml` (package spec changes)
- Runs weekly (Monday 6AM UTC)
- Can be triggered manually via `workflow_dispatch`

Requires a `GH_TOKEN` repository secret with `repo`, `workflow` scopes.

## Signing Key

Packages are signed with the Lilith Linux GPG key (`blancobam@protonmail.com`).
Public key: [`lilith-archive-keyring.asc`](lilith-archive-keyring.asc)

---

*Lilith Linux — Built with darkness and love by [BlancoBAM](https://github.com/BlancoBAM)*
