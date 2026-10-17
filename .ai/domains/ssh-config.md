---
applyTo: "**/ssh/config,**/.ssh/config,**/.ssh/*,**/global_config,**/*ssh*config*"
name: dotfiles-ssh-config
description: Use when editing SSH config files in this dotfiles repo (~/.ssh/config, files/--HOME--/.ssh/global_config, templates/ssh-config.template) -- SSH config does not support `${VAR:-default}` expansion, so hardcoded paths with `~` are required, with a mandatory warning comment. This file OVERRIDES the global "never hardcode paths" and "defensive ${VAR:-} default" rules for these files.
---

# SSH Config Rules -- Variable Expansion Limitations

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

SSH config has limited variable expansion. Read this before editing any SSH config file.

## Precedence -- This File Overrides The Global Rules

For every SSH config file (`~/.ssh/config`, `files/--HOME--/.ssh/config`, `files/--HOME--/.ssh/global_config`,
any other file under `.ssh/` that ssh parses, and `templates/ssh-config.template`) the rules below take
priority over **both**:

1. **"Never hardcode paths"** (`AGENTS.md` mistake #3, `path-constants.md`, `shell-scripting.md`): ssh
   has no access to `${DOTFILES_DIR}`, `${XDG_CONFIG_HOME}` and friends (many tools start ssh without the
   zsh environment), so literal `~/.ssh/...` is the **required** form here, not a violation.
2. **The defensive "variable might be unset" idiom** (`${VAR:-default}`, `${VAR:-}`, `set -u` guards and
   the `shell-functions-autoload.md` scan rule): ssh fails on it (`vdollar_percent_expand`). Never add it
   to an ssh config, and never treat the absence of a default as a bug there.

When a scan rule from another domain file would rewrite something in an ssh config (replace a path with
a variable, add a default value), **skip the ssh config**. Do not "fix" `~/.ssh/cm-%n-%C` or
`~/.ssh/id_rsa-personal` into variables.

**Related files**:
- [`path-constants.md`](./path-constants.md) - Path constants (does **not** apply to SSH config; this file wins)

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

## `Match all` Above The `Include`

ssh scopes every directive to the nearest preceding `Host` or `Match` block, and an `Include` is no
exception: with `Host github-work ...` as the last block of `~/.ssh/config`, a bare
`Include ~/.ssh/global_config` below it applies `global_config` (`Host *`, connection multiplexing,
...) **only to that one alias** -- `ssh -G github.com` shows none of it. `Match all` directly above
the `Include` ends that scope. `install-dotfiles.rb` (`_ensure_ssh_include_line`) maintains it
programmatically: it appends `Match all` + the `Include` to a config that lacks the `Include`, and
inserts a missing `Match all` directly above an existing one (blank lines and comments between are
fine; the check is case-insensitive). It is idempotent, and `-n` only reports what it would do. Do
not put `Match all` inside `global_config` itself -- it has no effect there.

## Host Key Checking And Agent Forwarding Defaults

`global_config` sets, under `Host *`, `StrictHostKeyChecking accept-new` and `ForwardAgent no`:

- **`accept-new`, not `no`.** An unknown host's key is added on first connection (unattended clones
  never stop at a prompt), but a *changed* key is refused. `no` connected anyway after a changed key --
  what a man-in-the-middle looks like -- printing a warning that cron and scripts never show. Verified
  against a throwaway `sshd`: unknown host rc=0 for both; changed host key rc=0 for `no`, rc=255 for
  `accept-new`. After a legitimate reinstall (or a cloud IP reused by another instance) run
  `ssh-keygen -R <host>` once.
- **No agent forwarding by default.** A forwarded agent gives the remote machine a live socket to
  every key loaded locally (verified: the server could list and use the key). Git over ssh does not
  need it. Opt in per host (`Host my-bastion` / `ForwardAgent yes` in `~/.ssh/config` above the
  `Match all` + `Include`, where the first value wins) or per connection with `ssh -A`.

Do not move either back under `Host *` as `no`/`yes`.

## Compression

`Compression no` is set in the git-host block (`github.com gitlab.com codeberg.org github-* gitlab-* codeberg-*`) and
`Compression yes` under `Host *`. ssh uses the **first** value it finds, so the git block, which comes
first, wins for those hosts. Git already zlib-compresses its packs: measured on a real clone from
GitHub, `Compression=no` 5.1s vs `yes` 5.2s with identical bytes, so compressing again only costs CPU on
both ends. Other hosts (interactive shells, file copies to servers) keep `yes` because this repo is
shared with people who do ssh to servers, where compressing text helps on a slow link -- that part is a
reasoned default, not measured. The first install's bootstrap `GIT_SSH_COMMAND` already uses
`Compression=no`, so it agrees with the git block.

## Enforcement

**When editing any SSH config file:**
1. **NEVER** introduce `${VAR:-default}` syntax
2. **NEVER** use `${SSH_CONFIGS_DIR}` or other custom env vars
3. **ALWAYS** use `~/.ssh/` hardcoded paths
4. **VERIFY** the config parses correctly: `ssh -G github.com`
