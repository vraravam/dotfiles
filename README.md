# 🚀 macos backup and restore strategy

> **Automated macOS backup and restore strategy for techies**

[![macOS](https://img.shields.io/badge/macOS-11%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Zsh-green?logo=zsh)](https://zsh.sourceforge.io/)

[![Lint](https://github.com/vraravam/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/vraravam/dotfiles/actions/workflows/lint.yml)
[![RSpec](https://github.com/vraravam/dotfiles/actions/workflows/rspec.yml/badge.svg)](https://github.com/vraravam/dotfiles/actions/workflows/rspec.yml)
[![codecov](https://codecov.io/gh/vraravam/dotfiles/branch/master/graph/badge.svg)](https://codecov.io/gh/vraravam/dotfiles)
[![Bundler Audit](https://github.com/vraravam/dotfiles/actions/workflows/bundler-audit.yml/badge.svg)](https://github.com/vraravam/dotfiles/actions/workflows/bundler-audit.yml)

A comprehensive, idempotent backup and restore strategy that configures your mac for modern software development. Supports both **Intel** and **Apple Silicon** macs with automatic architecture detection.

The script is **idempotent** — every step checks whether its work is already done before executing, so you can safely re-run after a partial failure without undoing completed steps. Each skipped step logs the reason, so you can see at a glance what was already in place.

# ✨ Features

- 🔍 **Auto-detects architecture** - supports both Intel x86_64 and Apple Silicon arm64
- 🔄 **Idempotent** — safe to run multiple times
- 📝 **Comprehensive logging** — shows all logs with colors for ease of debugging and checking status
- 🛡️ **Safe** — retains your pre-existing configs instead of overwriting them
- ⚡ **Fast shell startup** — typically ~30ms on Apple Silicon, under 100ms on Intel

# 📋 What Gets Installed

- **Homebrew** and a curated set of modern CLI/GUI tools — see the [Brewfile](files/--HOME--/Brewfile)
- **Zsh shell config** — [antidote](https://antidote.sh/) plugin manager, [Starship](https://starship.rs/) prompt, aliases and functions
- **macOS system preferences** — seeded with sane defaults, then optionally overlaid with your own exported backup

# 🛠️ Getting Started

Setup is split into two guides:

1. **[Adoption.md](Adoption.md)** (basic, start here) — fork the repo, set your GitHub username, and run the bootstrap command. This alone gets you a fully working machine: Homebrew, shell config, and macOS preferences.
2. **[Advanced.md](Advanced.md)** — once you're up and running: keeping backups current, encrypted preference backups via `gpg` + `git bundle` (optional), per-repository git customizations, and staying in sync with upstream.

> **⚡ Already forked and customized?** Jump straight to the [bootstrap command](Adoption.md#32-run-bootstrap-command) to copy-paste and run.

**For contributors:** See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting improvements.

# 🧰 Documentation

- **[Adoption.md](Adoption.md)** — Basic setup: preparing your machine, forking, and the bootstrap command
- **[Advanced.md](Advanced.md)** — Ongoing maintenance, encrypted preference backups (`gpg` + `git bundle`), per-repo customizations, and staying up-to-date with upstream
- **[Extras.md](Extras.md)** — Reference documentation for every utility script
- **[TechnicalDeepDive.md](TechnicalDeepDive.md)** — Internal architecture, design decisions, and implementation details
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Guidelines for contributing code, documentation, and reporting issues
- **[CHANGELOG.md](CHANGELOG.md)** — Version history and upgrade notes

# 🙏 Attributions & Thanks

These folks have contributed to this codebase till date:

- @arunvelsriram
- @shaz-ahammed
- @jotheeswaran-dev
