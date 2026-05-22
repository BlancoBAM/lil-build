# Lilith Linux Package Repository

This directory contains the configuration for the Lilith Linux package repository, based on the [debrepbuild](https://github.com/pop-os/debrepbuild) format from Pop!OS.

## Files

- `lilith-debrep.toml` - Full repository specification (debrepbuild format)
- `packages.list` - Simplified package list
- `build-repo.sh` - Repository builder script
- `README.md` - This file

## Repository Structure

```
repo/
├── pool/
│   ├── main/           - Core Lilith packages
│   ├── multiverse/    - Community packages
│   └── universe/      - Developer tools
├── dists/
│   └── stable/
│       ├── main/
│       ├── multiverse/
│       └── universe/
└── incoming/          - Incoming packages
```

## TOML Configuration

The main configuration file is `lilith-debrep.toml` which specifies:

### Sources
- **local** - Build from local source (Offerings, Tweakers, etc.)
- **apt** - Install from Ubuntu repositories
- **cargo** - Build and install from crates.io
- **github** - Download from GitHub releases
- **flatpak** - Reference to Flatpak apps

### Components

| Component | Description | Packages |
|-----------|-------------|----------|
| main | Core Lilith apps, COSMIC, Rust alternatives | offerings, tweakers, cosmic-comp, etc. |
| multiverse | Community packages (lil-pax.toml) | espanso, lotti, spacedrive, etc. |
| universe | Developer tools | cargo-nextest, cargo-audit, etc. |

## Usage

### 1. Initialize Repository
```bash
./build-repo.sh init
```

### 2. Add Packages

From local source:
```bash
./build-repo.sh add /path/to/package.deb main
```

### 3. Build Indexes
```bash
./build-repo.sh build
```

### 4. Generate Release
```bash
./build-repo.sh release
```

### 5. Full Build
```bash
./build-repo.sh all
```

## Package Sources

### Local Packages (Built from Source)

These are built from the Lilith-Linux source directories:

| Package | Source Path | Description |
|---------|-------------|-------------|
| offerings | /home/aegon/Offerings | Package manager GUI |
| tweakers | /home/aegon/Lilith-Linux/Tweakers | System optimization |
| shapeshifter | /home/aegon/Lilith-Linux/Shapeshifter | Profile manager |
| s8n | /home/aegon/Lilith-Linux/S8n-Rx-PackMan | CLI package manager |
| cosmic-comp | /home/aegon/Lilith-Linux/cosmic-epoch/cosmic-comp | Wayland compositor |
| cosmic-applets | cosmic-epoch/cosmic-applets | Panel applets |
| cosmic-bg | cosmic-epoch/cosmic-bg | Background service |
| cosmic-edit | cosmic-epoch/cosmic-edit | Text editor |
| cosmic-files | cosmic-epoch/cosmic-files | File manager |
| cosmic-greeter | cosmic-epoch/cosmic-greeter | Login screen |
| cosmic-launcher | cosmic-epoch/cosmic-launcher | App launcher |
| cosmic-panel | cosmic-epoch/cosmic-panel | Top panel |
| cosmic-term | cosmic-epoch/cosmic-term | Terminal |
| cosmic-settings | cosmic-epoch/cosmic-settings | System settings |

### Rust Alternatives (from lil-staRS.toml)

| Package | Type | Description |
|---------|------|-------------|
| bat | apt | cat replacement |
| lsd | apt | ls replacement |
| fd-find | apt | find replacement |
| ripgrep | apt | grep replacement |
| dust | cargo | du replacement |
| procs | cargo | ps replacement |
| broot | cargo | File navigation |
| navi | cargo | Cheat sheet |
| starship | cargo | Shell prompt |
| zoxide | cargo | Smart cd |
| just | cargo | Command runner |

### Community Packages (from lil-pax.toml)

| Package | Source | Description |
|---------|--------|-------------|
| espanso-gui | github | Text expansion |
| lotti | flatpak | Notes app |
| brief | flatpak | Markdown notes |
| wonderpen | flatpak | Writing app |
| digikam | apt | Photo management |
| spacedrive | github | File explorer |
| nushell | github | Modern shell |

## APT Source Configuration

Once the repository is built, add to `/etc/apt/sources.list.d/lilith.list`:

```
deb [arch=amd64] https://packages.lilithlinux.org/ stable main multiverse universe
```

Or for local testing:

```
deb [arch=amd64 signed-by=/path/to/key] file:///home/aegon/Lilith-Build/repo stable main multiverse universe
```

## Building with debrepbuild

For full debrepbuild integration, install debrepbuild:

```bash
git clone https://github.com/pop-os/debrepbuild
cd debrepbuild
cargo install --path .
```

Then use:

```bash
debrep build -c lilith-debrep.toml
```

## Notes

- The repository uses the debrepbuild TOML format
- Packages can be added from multiple sources (local, apt, cargo, github, flatpak)
- The builder script provides basic functionality; for production use debrepbuild
- All Lilith-specific packages are in the `main` component
- Rust alternatives provide modern replacements with GNU fallback
# lil-build
# lil-build
