---
applyTo: "**/ssh/config,**/.ssh/config,**/*ssh*config*"
name: dotfiles-ssh-config
description: Use when editing SSH config files in this dotfiles repo -- SSH config does not support `${VAR:-default}` expansion, so hardcoded paths with `~` are required, with a mandatory warning comment.
---

# SSH Config Rules -- Variable Expansion Limitations

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

SSH config has limited variable expansion. Read this before editing any SSH config file.

**Related files**:
- [`path-constants.md`](./path-constants.md) - Path constants (does not apply to SSH config)

**SSH config files (`~/.ssh/config`, `templates/ssh-config.template`) have strict limitations on variable expansion.**

## What SSH Config Supports

SSH config only supports:
- **Simple variable expansion**: `${VAR}` — requires the variable to be set in the environment
- **Tilde expansion**: `~` or `~/path` — expands to home directory
- **Tokens**: `%d` (home directory), `%h` (remote hostname), `%r` (remote username)

## What SSH Config Does NOT Support

SSH config does **NOT** support:
- **Bash-style default values**: `${VAR:-default}` — causes `vdollar_percent_expand` errors
- **Nested expansion**: `${VAR:-${OTHER_VAR}}` — fails to parse
- **Command substitution**: `$(command)` — not evaluated
- **Arithmetic expansion**: `$((expr))` — not evaluated

## The Rule

**ALL paths in SSH config files MUST use hardcoded `~/.ssh/` paths or simple `~` expansion.**

```ssh-config
# BAD — causes "vdollar_percent_expand: env var has no value" errors
IdentityFile "${SSH_CONFIGS_DIR:-${HOME}/.ssh}/id_rsa-personal"
Include "${SSH_CONFIGS_DIR:-${HOME}/.ssh}/global_config"

# Good — hardcoded path with tilde expansion
IdentityFile ~/.ssh/id_rsa-personal
Include ~/.ssh/global_config
```

## Why Hardcoded Paths

1. **SSH runs without shell environment** — many tools invoke SSH without loading `.zshrc` or `.shellrc`, so `SSH_CONFIGS_DIR` and other custom env vars are not available
2. **Syntax errors break git operations** — invalid variable expansion in `~/.ssh/config` causes all git operations over SSH to fail
3. **Cron jobs fail silently** — scripts running via cron don't have the interactive shell environment

## Files This Rule Applies To

- `~/.ssh/config` — active SSH client configuration
- `templates/ssh-config.template` — template for new installs
- Any file referenced by SSH (global_config, etc.)

## Required Warning Comment

Both `~/.ssh/config` and `templates/ssh-config.template` must have this comment near the top:

```
# **IMPORTANT:** SSH config does NOT support bash-style variable expansion like ${VAR:-default}.
# SSH only understands simple ${VAR} or ~ (home directory). Since many tools invoke ssh
# commands without the zsh environment loaded, this
# file MUST use hardcoded paths like ~/.ssh/id_rsa-personal instead of variable references.
```

## Enforcement

**When editing any SSH config file:**
1. **NEVER** introduce `${VAR:-default}` syntax
2. **NEVER** use `${SSH_CONFIGS_DIR}` or other custom env vars
3. **ALWAYS** use `~/.ssh/` hardcoded paths
4. **VERIFY** the config parses correctly: `ssh -G github.com`
