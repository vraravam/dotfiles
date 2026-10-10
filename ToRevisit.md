# To Revisit

Evaluations and experiments that were **not adopted (yet)**, with what was learned, why they were parked, and what would have to change before they are worth another look. The point of this file is that nobody (including future me) has to redo the research: each entry states the findings, the decision, the date, and concrete *revisit triggers*.

Status values: **Rejected for now** (a concrete blocker exists), **Parked** (promising, undecided), **Implemented, not merged** (code exists on a branch).

| Entry | Status | Evaluated | Revisit when |
|---|---|---|---|
| [zerobrew as a faster `brew`](#1-zerobrew-as-a-faster-brew) | Rejected for now | 2026-10-10 | casks with `.app` artifacts, `HOMEBREW_BUNDLE_FILE`/Brewfile-DSL support, `bundle check` |
| [stout as a Homebrew replacement](#2-stout-as-a-homebrew-replacement) | Rejected for now | Aug-Sep 2026 | `--greedy` and `HOMEBREW_*` support, a release newer than v0.2.2 |
| [deja instead of zsh-autosuggestions](#3-deja-instead-of-zsh-autosuggestions) | Implemented, not merged | 2026-09-06 | you want to measure startup and typing latency |
| [Parked decisions](#4-parked-decisions) | Parked | 2026-10 | see the list |

Facts below that come from outside this repository (stars, releases, features) are dated; re-check them before relying on them.

---

## 1. zerobrew as a faster `brew`

**Goal:** a drop-in replacement for how `brew` manages everything in `~/Brewfile` from any directory (via `HOMEBREW_BUNDLE_FILE`), with `FIRST_INSTALL` installing only the base section first and the rest in a background job, a pre-configured machine behaving exactly like today, the typed commands changing minimally -- all for the sake of speed.

**Decision:** rejected for now. It is a fast client for *formulae*; it is not a replacement for a Brewfile-driven `brew`.

**What was checked:** the README, and the source of `zerobrewhq/zerobrew` (`main` on 2026-10-10; latest release v0.4.0, 2026-10-08). Nothing was installed or run.

### Findings against the goal

| Requirement | Finding |
|---|---|
| Manage all apps in `~/Brewfile` | Casks are supported only when they have a `binary` artifact (command-line binaries). Every other cask fails with "only casks with 'binary' artifacts are currently supported". `zb migrate` says the same: casks and formulae from non-core taps cannot be migrated. The Brewfile has 26 casks, mostly GUI apps. |
| Read the Brewfile | `zb bundle` is a line-based text parser, not a Brewfile (Ruby DSL) evaluator. It skips `tap` lines, takes the first quoted token of `brew`/`cask` lines, strips everything after `#`, and treats **any other line as a formula name**. So `if`/`end`, `vscode '...'` (30 lines), `cask_args`, `::Hardware::CPU.arm?` and multi-line entries become errors, and options such as `postinstall:` (18 in the Brewfile), `args:`, `link:` and `trusted:` are silently dropped. |
| Work from any folder via the env vars | `zb bundle` defaults to `./Brewfile` and accepts only `-f <path>`. There is no `HOMEBREW_BUNDLE_FILE` or `--global` equivalent, so a wrapper would have to pass `-f "${HOMEBREW_BUNDLE_FILE}"`. |
| `FIRST_INSTALL` base first, rest in the background | Possible only with a wrapper: no stdin convention (a temp file or `/dev/stdin` would work) and no `bundle check`. `zb bundle` installs entries one at a time and **stops at the first failure**, where `brew bundle` carries on and reports. |
| Pre-configured machine unchanged | `bupc` and the hourly cron use `bundle check`, `bundle cleanup`, `cleanup`, `autoremove` and `outdated --greedy`. zerobrew has `update`, `outdated`, `upgrade`, `gc` and `reset` but none of those, and `bundle dump` writes only `brew "name"` lines (no casks). |
| Same commands, minimal changes | Its own prefix (hints use `/opt/zerobrew`, root `~/.zerobrew`) and its own `ZEROBREW_*` environment written into the shell config by `zb init`. Everything keyed on `HOMEBREW_PREFIX` would need re-pointing: the cached `brew shellenv`, the keg-only cache, `antidote`, `git-extras`, `zsh` as the login shell. Creating its directories needs `sudo`. |
| Taps | Tap formulae are parsed with regular expressions from the tap's Ruby source and need a bottle or a source URL with a top-level `sha256`. The `vraravam/tap` formula is pinned by git `tag:`/`revision:` and would **likely** be unsupported (not tested). |
| Speed | Real for formulae: the project reports 6.6x faster cold and 68x faster warm over 100 formulae (zerobrew 0.3.5, 2026-10-08), with the caveat that it does not run post-install steps yet. Nothing it publishes speeds up `bundle check`, `update` or `outdated`, which are the commands typed most. |

The project itself says it is experimental and recommends running it **alongside** Homebrew rather than replacing it.

### Options considered

1. **Hybrid:** zerobrew installs the 44 formulae; `brew` keeps the 26 casks, the `postinstall` hooks, the DSL and the tap formula. Two package managers, so not one-to-one, and the gain applies only to formula installs.
2. **Stay on Homebrew** and speed up what is actually slow (cache `bundle check`, skip `brew update` in cron, tune the `HOMEBREW_*` settings).
3. **Revisit later.**

### Revisit triggers

- Casks with `app`/`pkg` artifacts are supported (or the Brewfile is split so that GUI apps are clearly out of scope).
- `HOMEBREW_BUNDLE_FILE` / `--global`, or evaluation of the Brewfile DSL, or `bundle check`/`cleanup`.
- Failures in `bundle` no longer abort the whole run; post-install steps run.
- Tap formulae pinned by git `tag`/`revision` work.

### How to measure first (Homebrew's maintainers want numbers, see entry 2)

Time the commands you actually type, with a tool such as `hyperfine`, before choosing anything:

```zsh
hyperfine --warmup 1 'brew bundle check' 'brew outdated --greedy' 'brew update';
```

---

## 2. stout as a Homebrew replacement

**What:** [stout](https://github.com/neul-labs/stout), a Rust CLI advertised as a drop-in replacement for the Homebrew CLI.

**Decision:** do not migrate (August 2026). It was too immature and missing things the aliases depend on.

**Why not**

- Too immature: v0.2.2 (released 2026-05-09 -- still the latest release as of 2026-10-10), 10 stars at the time of the evaluation.
- Missing `--greedy`, which `bcg` and `bcug` rely on.
- Unknowns that were never answered: `HOMEBREW_*` environment variables, keg-only paths, `shellenv`, tap support.
- Homebrew already uses its optimized JSON API (no 700 MB core-tap clone), so there is no large win left to claim.

**What the evaluation found:** Homebrew's JSON-based search is slow compared with stout's SQLite FTS5 index (`brew search json` ~470 ms versus under 50 ms; a raw query 0.3 ms versus 89 ms parsing the JSON in Ruby, about 260x). That led to a proposal to Homebrew for a SQLite FTS5 index alongside the JSON API (9 MB extra cache for an estimated 3-10x faster search). The full proposal is preserved in the appendix below.

**What came of the proposal:** [Homebrew/brew#23652](https://github.com/Homebrew/brew/issues/23652) was closed as **not planned** on 2026-08-25. The maintainer's response, in short: the project is not "compatible" (it does not run Ruby), the proposal is "a solution chasing a problem", 470 ms does not seem slow, and any search speed-up is welcome **if it comes with `brew benchmark`/`hyperfine` numbers** -- find the slow part with `brew prof`.

**Revisit triggers:** stout supports `--greedy` and the `HOMEBREW_*` environment, publishes a release newer than v0.2.2, and handles taps. The same Ruby-compatibility objection applies to any Rust client that does not evaluate Brewfiles (see entry 1).

**Another evaluated direction:** replacing Homebrew for CLI tools with Nix (`nix-darwin` + `home-manager`) is kept as the WIP branch `nix-migration`; it is not summarized here.

<details>
<summary>Appendix: the full original proposal (<code>HOMEBREW-SQLITE-PROPOSAL.md</code> from the <code>stout-migration</code> branch, 2026-09-06), preserved verbatim</summary>

````markdown
# Homebrew SQLite Search Index Proposal

## Status: Submitted to homebrew: https://github.com/Homebrew/brew/issues/23652

## Background

During evaluation of [Stout](https://github.com/neul-labs/stout) as a potential Homebrew replacement (August 2026), we discovered that Homebrew's current JSON API-based search is significantly slower than Stout's SQLite FTS5 implementation:

- **Homebrew (JSON API)**: ~470ms for `brew search json`
- **Stout (SQLite FTS5)**: <50ms for equivalent search (260x faster raw query)

While we decided NOT to migrate to Stout (too immature: v0.2.2, 2 months old, 10 stars, missing `--greedy` flag), the performance analysis revealed an actionable improvement for Homebrew itself.

## Proposal Summary

**Add SQLite FTS5 index alongside JSON API (hybrid approach)**

- Keep JSON API for metadata integrity and signed payloads
- Add 9MB SQLite search index for instant lookups
- Target: 3-10x speedup for search operations
- Zero breaking changes

## Key Findings

### Performance Comparison

| Operation | Current (JSON) | With SQLite FTS5 | Speedup |
|-----------|----------------|------------------|---------|
| `brew search <term>` | 470ms | ~150ms | **3.1x** |
| `brew info <pkg>` | 1-2s | ~200-400ms | **3-5x** |
| `brew desc -s <term>` | 500-1000ms | ~100-200ms | **5-10x** |

### Cache Size Impact

- Current: 31MB (JSON API only)
- With SQLite: 40MB (31MB JSON + 9MB SQLite)
- Trade-off: 9MB extra for 3-10x speedup

### Why SQLite is Faster

1. **Pre-built inverted index** (FTS5) - no linear scanning
2. **Compressed storage** - zstd compression in SQLite
3. **Relevance ranking** - built-in query scoring

## Technical Details

### Stout's SQLite Schema

```sql
CREATE TABLE formulas (
    name TEXT PRIMARY KEY,
    version TEXT,
    desc TEXT,
    homepage TEXT,
    deprecated BOOLEAN,
    disabled BOOLEAN
);

CREATE VIRTUAL TABLE formulas_fts USING fts5(
    name, desc,
    content='formulas',
    content_rowid='rowid'
);
```

### Benchmark Data

**Raw query performance:**
```bash
# SQLite FTS5
$ time sqlite3 stout-formulas.db "SELECT COUNT(*) FROM formulas_fts WHERE name MATCH 'json*'"
102
real 0.000342s  # 0.3ms

# Homebrew JSON (Ruby)
$ time ruby -e "data = JSON.parse(File.read(...)); data['formulae'].select {...}"
102
real 0.089s  # 89ms

Speedup: 260x
```

**End-to-end search:**
```bash
# Homebrew (current)
$ time brew search json
real 0.474s

# Stout (SQLite)
$ time stout search json
real <0.050s

Speedup: 9-10x
```

## Current Environment

**Your Homebrew setup already uses the optimized JSON API:**

```bash
$ brew config | grep "Core tap"
Core tap: N/A  # No 700MB git repo clone

$ du -sh ~/Library/Caches/Homebrew/api/
31M  # Compact JSON cache

$ ls -lh ~/Library/Caches/Homebrew/api/internal/packages.*.json.payload
-rw-r--r--  14M  packages.arm64_golden_gate.jws.json.payload  # 8,569 formulas, 7,709 casks
```

## Recommendation for Dotfiles

### Do NOT Migrate to Stout

**Reasons:**
- Too immature (v0.2.2, May 2026, 10 GitHub stars)
- Missing `--greedy` flag (breaks `bcg` and `bcug` aliases)
- Unknowns: HOMEBREW_* env vars, keg-only paths, shellenv, tap support
- Homebrew already uses optimized JSON API (no 700MB git repo)

### Monitor SQLite Progress

**If Homebrew adopts SQLite:**
- No dotfiles changes needed (transparent to users)
- Search performance improves 3-10x automatically
- Your startup optimization (78-87ms) unaffected (SQLite doesn't help startup, only search)

### Document Analysis

Added this file to track:
- Why we evaluated Stout
- Why we didn't migrate
- Why we're proposing SQLite to Homebrew
- Technical findings for future reference

## Next Steps

1. **Submit feature request** to Homebrew/brew with detailed proposal
2. **Monitor response** from Homebrew maintainers
3. **If accepted**, no dotfiles changes needed (transparent upgrade)
4. **If rejected**, document reasoning for future reference

## Files

- **Feature request draft**: `/tmp/homebrew-sqlite-feature-request.md`
- **Stout evaluation**: (covered in this document)
- **Related aliases**: `bcg` (brew outdated --greedy), `bcug` (brew upgrade --greedy -y) in `.aliases`
- **Homebrew config**: `files/--HOME--/Brewfile`, `files/--HOME--/.shellrc`

## References

- Stout source: https://github.com/neul-labs/stout
- Stout-index: https://github.com/neul-labs/stout-index
- SQLite FTS5: https://www.sqlite.org/fts5.html
- Homebrew JSON API (v4.0.0): https://brew.sh/2023/02/16/homebrew-4.0.0/

---

**Last Updated**: August 25, 2026
**Status**: Draft ready for submission to Homebrew/brew GitHub issues
````

</details>

---

## 3. deja instead of zsh-autosuggestions

**What:** [deja](https://github.com/Giammarco-Ferranti/deja), a Go tool providing predictive inline suggestions for zsh (fuzzy matching, directory-aware context, sequence prediction), daemon-based: about 0.3 ms per query after a one-time ~30 ms init that is cached to `~/.local/share/deja/init.zsh`. As of 2026-10-10: about 900 stars, v0.4.2 (2026-09-07), last push 2026-10-09, 13 open issues.

**State:** implemented on the branch `deja` (one commit, 2026-09-06, "Replace zsh-autosuggest with deja"), **not merged**. No evaluation, benchmark or decision was recorded.

**What the branch changes** (the full diff is in the appendix):

- `plugins.txt`: `zsh-users/zsh-autosuggestions` becomes `Giammarco-Ferranti/deja`; still loaded last and not deferred, so it wraps all other ZLE widgets.
- `.zshrc`: the `ZSH_AUTOSUGGEST_*` options become `DEJA_USE_ASYNC`, `DEJA_MANUAL_REBIND`, `DEJA_BUFFER_MAX_SIZE` and `DEJA_HIGHLIGHT_STYLE`; the widget re-bind after `compinit` calls `_deja_bind_widgets`. The `history` versus `completion` strategy choice and the history-ignore pattern have no `DEJA_*` equivalent in the diff.
- `.ai/domains/zsh-startup.md`: the plugin-option example uses `DEJA_*`.

**Before merging (nothing of this has been done):**

- Measure startup against the 20-run `time zsh -i -c exit` baseline (currently ~30 ms) -- required for any startup-file change.
- Measure first-keystroke and mid-typing latency against zsh-autosuggestions.
- Check the daemon: when it starts, whether it survives in cron, SSH and direnv contexts, and how it behaves on `exit`.
- Check feature parity: acceptance key bindings, the completion-based suggestions that were dropped, and `history` behavior.

<details>
<summary>Appendix: the full diff of the <code>deja</code> branch against <code>master</code> (2026-09-06)</summary>

````diff
diff --git a/.ai/domains/zsh-startup.md b/.ai/domains/zsh-startup.md
index e013bef..bb49684 100644
--- a/.ai/domains/zsh-startup.md
+++ b/.ai/domains/zsh-startup.md
@@ -222,19 +222,20 @@ source "${HOME}/.shellrc"

 ## Plugin Option Variables

-Plugin option variables (e.g. `ZSH_AUTOSUGGEST_STRATEGY`) **must be set before
+Plugin option variables (e.g. `DEJA_HIGHLIGHT_STYLE`) **must be set before
 the antidote bundle is sourced**. Plugins read these variables at load time; setting
 them after `load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"` has no effect:

 ```zsh
 # Good -- set before bundle
-export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
+export DEJA_HIGHLIGHT_STYLE='fg=8'
+export DEJA_USE_ASYNC=1
 unset ZSH ZSH_CUSTOM   # clear stale OMZ values before antidote loads OMZ libs
 load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"

 # BAD -- too late, plugin already loaded
 load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"
-export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
+export DEJA_HIGHLIGHT_STYLE='fg=8'
 ```

 ## `compinit` Caching
diff --git a/files/--XDG_CONFIG_HOME--/zsh/plugins.txt b/files/--XDG_CONFIG_HOME--/zsh/plugins.txt
index e6d8c64..6e203dc 100644
--- a/files/--XDG_CONFIG_HOME--/zsh/plugins.txt
+++ b/files/--XDG_CONFIG_HOME--/zsh/plugins.txt
@@ -152,8 +152,9 @@ ohmyzsh/ohmyzsh path:plugins/direnv
 # highlighting. It provides dynamic highlighting (invalid commands shown in red,
 # existing files underlined) and uses high-quality Sublime Text syntax definitions.

-# NOT deferred: hooks into ZLE to show ghost-text suggestions. Same reasoning
-# as FSH -- the async suggestion fetch (ZSH_AUTOSUGGEST_USE_ASYNC) means it
-# doesn't block ZLE, so the only cost is the one-time load at startup.
+# NOT deferred: hooks into ZLE via zle-line-init, precmd, and widget wrapping.
+# Provides predictive inline suggestions with fuzzy matching, directory-aware
+# context, and sequence prediction. Daemon-based (~0.3ms queries) after initial
+# ~30ms first-run init (cached to ~/.local/share/deja/init.zsh thereafter).
 # Must be last so it wraps all other ZLE widgets.
-zsh-users/zsh-autosuggestions
+Giammarco-Ferranti/deja
diff --git a/files/--ZDOTDIR--/.zshrc b/files/--ZDOTDIR--/.zshrc
index 687d69e..8443391 100644
--- a/files/--ZDOTDIR--/.zshrc
+++ b/files/--ZDOTDIR--/.zshrc
@@ -140,34 +140,29 @@ load_file_if_exists "${ANTIDOTE_ZSH}"
 # ${HOST} equals `hostname -f` on macOS and avoids the ~4ms subprocess cost on every shell start.
 iterm2_hostname="${HOST}"

-# zsh-autosuggestions -- all options must be set before the antidote bundle is
-# sourced; the plugin reads them at load time.
+# deja -- predictive inline suggestions with fuzzy matching.
+# All options must be set before the antidote bundle is sourced; deja reads them
+# at load time. See ~/.local/share/deja/init.zsh (generated by 'deja init zsh')
+# for full documentation on each option.
 #
-# USE_ASYNC: fetch suggestions in a background zpty process so ZLE never blocks
-# while waiting for a history/completion lookup -- directly reduces first-keystroke
-# and mid-typing latency.
+# DEJA_USE_ASYNC=1: fetch suggestions asynchronously (via zle -F) so the keystroke
+# path never blocks waiting for a daemon response. This is deja's default and
+# mirrors zsh-autosuggestions' USE_ASYNC behaviour.
 #
-# MANUAL_REBIND: skip the full ZLE widget rebind that autosuggestions performs on
-# every precmd call. Without this, every prompt incurs ~10-20ms of widget
-# re-registration. Widgets are bound once at plugin load and never touched again.
+# DEJA_MANUAL_REBIND=1: skip the full ZLE widget rebind that deja performs on
+# every precmd call (similar to zsh-autosuggestions' MANUAL_REBIND). Widgets are
+# bound once at plugin load and never touched again, saving ~5-10ms per prompt.
 #
-# BUFFER_MAX_SIZE: skip suggestion lookups when the command line exceeds this
-# length. Avoids expensive history DB scans for long one-liners where a
+# DEJA_BUFFER_MAX_SIZE=20: skip suggestion lookups when the command line exceeds
+# this length. Avoids expensive fuzzy-matching scans for long one-liners where a
 # suggestion is rarely useful anyway.
 #
-# HISTORY_IGNORE: skip history entries longer than 100 chars. Reduces regex
-# matching cost on large history files -- long entries (URLs, one-liners) are
-# almost never the intended suggestion target.
-#
-# STRATEGY=(history): use only the history strategy. The 'completion' strategy
-# spawns a zpty (pseudoterminal) on every suggestion request -- ~10-30ms overhead
-# per lookup. History alone is faster and covers the vast majority of useful
-# suggestions; completion suggestions are better served by pressing Tab explicitly.
-export ZSH_AUTOSUGGEST_USE_ASYNC=1
-export ZSH_AUTOSUGGEST_MANUAL_REBIND=1
-export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
-export ZSH_AUTOSUGGEST_HISTORY_IGNORE="?(#c100,)"
-export ZSH_AUTOSUGGEST_STRATEGY=(history)
+# DEJA_HIGHLIGHT_STYLE: ghost text color (fg=8 = bright black / dim gray). Unlike
+# zsh-autosuggestions which hardcodes a style, deja exposes this as a config var.
+export DEJA_USE_ASYNC=1
+export DEJA_MANUAL_REBIND=1
+export DEJA_BUFFER_MAX_SIZE=20
+export DEJA_HIGHLIGHT_STYLE='fg=8'
 # eza plugin: enable icons
 zstyle ':omz:plugins:eza' 'icons' yes
 # iterm2 plugin: disable built-in shell integration (we handle marks manually in starship.toml)
@@ -550,15 +545,15 @@ _deferred_compinit() {
     compdef ${(z)_call}
   done
   unset _compdef_queue
-  # Re-bind zsh-autosuggestions after compinit redefines completion widgets.
+  # Re-bind deja widgets after compinit redefines completion widgets.
   # compinit calls 'zle -C complete-word ...' (and similar) which replaces the
-  # ZLE widget wrappers that autosuggestions installed during its first precmd.
-  # With ZSH_AUTOSUGGEST_MANUAL_REBIND=1, autosuggestions never re-wraps on
-  # subsequent precmds -- calling bind_widgets here restores the wrapping so
-  # that the suggestion region_highlight runs after fast-syntax-highlighting
-  # and ghost text appears in the correct dim colour, not FSH's syntax colour.
-  if (($+functions[_zsh_autosuggest_bind_widgets])); then
-    _zsh_autosuggest_bind_widgets
+  # ZLE widget wrappers that deja installed during its first precmd.
+  # With DEJA_MANUAL_REBIND=1, deja never re-wraps on subsequent precmds --
+  # calling _deja_bind_widgets here restores the wrapping so that suggestion
+  # rendering runs after fast-syntax-highlighting and ghost text appears in
+  # the correct dim colour, not FSH's syntax colour.
+  if (($+functions[_deja_bind_widgets])); then
+    _deja_bind_widgets
   fi
   unfunction _deferred_compinit
 }
@@ -680,8 +675,8 @@ bindkey '\033[1;9C' forward-word

 # predict-on (Ctrl+Xp) and incremental-complete-word (Ctrl+Xi) are disabled.
 # predict-on: aggressively fills the command line from history on every keystroke
-# when toggled on -- overlaps with zsh-autosuggestions which already does this
-# non-destructively via ghost text with no toggle required.
+# when toggled on -- overlaps with deja which already does this non-destructively
+# via ghost text with fuzzy matching and sequence prediction, with no toggle required.
 # incremental-complete-word (Ctrl+Xi): narrows completions in real time as you type;
 # superseded by fzf-based tab completion. Neither adds startup overhead, but
 # predict-on adds per-keystroke cost whenever active.
````

</details>

---

## 4. Parked decisions

Decisions that were deliberately postponed (2026-10), with enough context to pick them up cold.

- **`fresh-install` bootstrap design (Ruby port, branch `fresh-install-ruby`).** The Ruby installer loads repository files at startup, so on a vanilla macOS it cannot run before the repository is cloned, and the Adoption one-liner still points at the shell script. A small self-contained first stage that fetches `.shellrc`, clones the repository and then starts the Ruby installer is the leading idea. Closely related: variables exported by `.shellrc` (`KEYBASE_*_REPO_NAME`, `ENCRYPTED_*_REPO_URL`, `UPSTREAM_GH_USERNAME`) do not reach the Ruby process, so the Keybase and encrypted-backup steps would be silently skipped.
- **Should `osx-defaults-ruby` exist at all?** `TechnicalDeepDive.md` section 13 and `ruby-scripting.md` currently say `osx-defaults.sh` stays a shell script; reversing that means updating about ten documents. Deferred to roughly the start of November 2026.
- **Shell summary protocol.** `_record_warning`, `_record_error`, `print_script_summary` and the `_has_step_*` helpers in `.shellrc` have no callers in the repository once the shell installers are gone, but personal scripts in `${PERSONAL_BIN_DIR}` still use `_record_error` and `print_script_summary`. Remove the whole protocol as one unit only after those scripts move to Ruby.
- **Optional extractions.** A `Sudo` module out of `MacOS` (after the fresh-install port settles) and a `RepoAliases` module out of `GitWorkspace`.
- **More specs.** The clone/fallback logic in `resurrect-repositories.rb`, and `git_recreate.rb`.
