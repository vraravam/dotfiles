# 🚀 macos backup and restore strategy

> **Automated macOS backup and restore strategy for techies**

[![macOS](https://img.shields.io/badge/macOS-11%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Zsh-green?logo=zsh)](https://zsh.sourceforge.io/)

A comprehensive, idempotent backup and restore strategy that configures your mac for modern software development. Supports both **Intel** and **Apple Silicon** macs with automatic architecture detection.

The script is **idempotent** — every step checks whether its work is already done before executing, so you can safely re-run after a partial failure without undoing completed steps. Each skipped step logs the reason, so you can see at a glance what was already in place.

All of the folder structures and the setup/backup operations are governed by the environment variables [defined here](files/--HOME--/.shellrc). Please read the explanation of each variable in the same and edit appropriately.

# ✨ Features

- 🔍 **Auto-detects architecture** - supports both Intel x86_64 and Apple Silicon arm64
- 🔄 **Idempotent** — safe to run multiple times
- 📝 **Comprehensive logging** — shows all logs with colors for ease of debugging and checking status
- 🛡️ **Safe** — retains your pre-existing configs instead of overwriting them

# 📋 What Gets Installed

## 🛠️ Essential Development Tools

- **Homebrew** — Package manager
- **Modern CLI and GUI tools** — See the full list in the [Brewfile](files/--HOME--/Brewfile)

## 🐚 Shell Configuration

- **antidote** — Static zsh plugin manager
- **Starship** — Modern cross-shell prompt
- **Plugins** — autosuggestions, syntax highlighting, selected OMZ libs and plugins managed via [antidote](./files/--ZDOTDIR--/.zsh_plugins.txt)
- **Aliases** — Convenient shortcuts and functions
- **Per-repository customizations** — Add custom git hooks and command overrides for specific projects (see [Extras.md § Git hook customizations](Extras.md#git-hook-customizations))

# 🛠️ How to Adopt This System

Want to use this dotfiles system for your own setup? See the **[Adoption Guide](Adoption.md)** for complete step-by-step instructions covering:

- **Preparing your existing machine** — capturing preferences, repo catalogs, and Brewfile
- **Forking and customizing** — required username changes, optional path adjustments, Keybase setup
- **First-time setup** — running the bootstrap command on a fresh machine
- **Ongoing maintenance** — keeping backups current with regular snapshots
- **Staying up-to-date** — syncing with upstream improvements while preserving your customizations

For a quick summary of files you'll typically customize, see the [customization checklist below](#customization-checklist).

# 📝 Quick Start

**New to this system?** Follow these steps:

1. **Prepare** (optional) — If migrating from an existing machine, see [Adoption.md § Phase 1](Adoption.md#phase-1-prepare-your-existing-machine) to capture your current setup
2. **Adopt** — Fork and customize for your setup (see [Adoption.md § Phase 2](Adoption.md#phase-2-fork-and-customize) for complete guide)
3. **Install** — Run the [bootstrap command](Adoption.md#32-run-bootstrap-command) (copy-paste the `curl` command)
4. **Maintain** — Keep backups current (see [Adoption.md § Phase 4](Adoption.md#phase-4-ongoing-maintenance))

> **⚡ Already forked and customized?** Jump straight to the [bootstrap command](Adoption.md#32-run-bootstrap-command) to copy-paste and run.

**For contributors:** See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting improvements.

# 🎯 What the Script Does

The [fresh-install-of-osx.sh](scripts/fresh-install-of-osx.sh) script runs in an **idempotent manner**, meaning it's safe to run multiple times without breaking anything. It automatically:

1. Downloads and sources `.shellrc` (provides logging and utilities)
2. Installs **Homebrew** (or updates if already present)
3. Clones your **dotfiles fork** to `~/.config/dotfiles`
4. Runs **install-dotfiles.rb** to symlink config files
5. Installs packages from your **Brewfile**
6. Runs **post-brew-install.rb** (antidote setup, mise language versions)
7. Seeds macOS preferences via **osx-defaults.sh -s** (baseline settings)
8. Imports your custom preferences via **capture-prefs.rb -i** (UI-configured overrides)
9. Sets up **cron jobs** for automated maintenance
10. Resurrects tracked git repositories from catalogs

### Two-Phase Preference Restoration

The script automatically applies macOS preferences in two ordered phases:

1. **`osx-defaults.sh -s`** — Seeds a partial baseline of known-good starting values
2. **`capture-prefs.rb -i`** — Imports preferences exported from your previous machine, overriding the baseline where they overlap

If you haven't exported preferences from a previous machine yet, the script skips step 2 and you can run `capture-prefs.rb -i` later. See [Extras.md — osx-defaults.sh](Extras.md#osx-defaultssh) for details.

### Shell Optimization

All scripts are optimized for **fast shell loading** — startup time is typically **30-50ms** on modern hardware (Apple Silicon M1+: ~30ms, Intel 2019+: ~40-50ms). The shell is ready to use instantly upon opening the terminal.

# 🏗️ Complete setup

The backup strategy is split into 2 stages - both of which are run by the [same script](scripts/fresh-install-of-osx.sh). See [Adoption.md](Adoption.md) for the complete adoption workflow covering basic setup (Phase 1-3) and advanced features (Phase 4-5).

The "advanced" setup captures application preferences (both system and custom apps) and backs them up into an _encrypted remote repository_. This requires [Keybase](https://keybase.io/) for the encrypted private storage. **Keybase is entirely optional** — if you skip it, everything else (dotfiles, Homebrew packages, zsh config, mise language versions, cron jobs) still works. Simply comment out the `KEYBASE_*` environment variables in `files/--HOME--/.shellrc` and the script will skip the Keybase-dependent steps silently.

If you want to automate the repetitive running of these scripts/commands, you can use the system-level cronjobs to set this up, the details of which can be found in the [Extras](Extras.md#software-updates-cronrb) file, by which you can reduce more manual efforts.

# 🎯 Post-Setup

After running `fresh-install-of-osx.sh`, see [Adoption.md § Phase 3.3](Adoption.md#33-post-setup-manual-steps) for remaining configuration (git includes, SSH config, system preferences, commit squashing).

## Customization Checklist

**Quick summary** of files you'll typically customize in your fork (see [Adoption.md § Phase 2](Adoption.md#phase-2-fork-and-customize) for detailed instructions):

- `Adoption.md` — Update bootstrap command in Phase 3.2 to reference YOUR_USERNAME instead of vraravam
- `files/--HOME--/.shellrc` — Change `GH_USERNAME`, `UPSTREAM_GH_USERNAME`, `KEYBASE_USERNAME`, and path env vars (`PROJECTS_BASE_DIR`, `PERSONAL_CONFIGS_DIR`, `PERSONAL_BIN_DIR`, `PERSONAL_PROFILES_DIR`)
- `scripts/utilities/env_vars.rb` — Update Ruby fallback defaults for `GH_USERNAME`, `UPSTREAM_GH_USERNAME`, `KEYBASE_USERNAME`
- `files/--HOME--/Brewfile` — Remove unwanted packages or merge with your exported Brewfile
- `scripts/data/capture-prefs-allowed-list.txt` — Add/remove preference domains to match your installed apps
- `scripts/data/capture-prefs-denied-list.txt` — Add newly discovered unsafe domains (do not remove existing entries)
- `files/--HOME--/custom.gitignore` — Update if you changed `PROJECTS_BASE_DIR` from default `~/dev`

For troubleshooting environment variable issues, see [Adoption.md § Troubleshooting](Adoption.md#troubleshooting).

For a deeper understanding of how the scripts work internally — the logging system, startup optimisation, `.shellrc` vs `${ZDOTDIR}/.aliases` architecture, cron safety, and more — see the [Technical Deep Dive](TechnicalDeepDive.md).

# 🔄 Ongoing Maintenance

See **[Adoption.md § Phase 4](Adoption.md#phase-4-ongoing-maintenance)** for complete maintenance workflow including:

- Exporting preferences after changes
- Updating repository catalogs
- Maintaining the Brewfile
- Automating tasks via cron (see [Extras.md § software-updates-cron.rb](Extras.md#software-updates-cronrb))

# 🧰 Documentation

- **[Adoption.md](Adoption.md)** — Complete adoption guide (preparation, fork customization, first-time setup, maintenance, staying up-to-date, troubleshooting)
- **[Extras.md](Extras.md)** — Reference documentation for all utility scripts
- **[TechnicalDeepDive.md](TechnicalDeepDive.md)** — Internal architecture, design decisions, and implementation details
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Guidelines for contributing code, documentation, and reporting issues
- **[CHANGELOG.md](CHANGELOG.md)** — Version history and upgrade notes

# 🙏 Attributions & Thanks

These folks have contributed to this codebase till date:

- @arunvelsriram
- @shaz-ahammed
- @jotheeswaran-dev
