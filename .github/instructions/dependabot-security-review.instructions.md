---
applyTo: "Gemfile,Gemfile.lock"
---

# Dependency Update Security Review

These instructions apply Copilot code review to pull requests that change
`Gemfile` or `Gemfile.lock` -- in practice, almost always a Dependabot
version-bump PR (see `.github/dependabot.yml`). They narrow the general
checklist in `.github/agents/security-reviewer.agent.md` down to what's
actually relevant for a dependency bump, since most of that checklist
(command injection, sudo usage, TOCTOU races) does not apply to a lockfile
diff.

When reviewing a `Gemfile`/`Gemfile.lock` change:

1. **Known vulnerabilities**: `bundler-audit` (run automatically by
   `.github/workflows/dependabot-audit.yml`) already checks the Ruby Advisory
   Database -- do not re-derive this from scratch, but do flag it as a
   CRITICAL finding if that workflow's `bundler-audit` step failed.

2. **Ruby 2.6 compatibility**: This repo pins `ruby '2.6.10'` in `Gemfile` as
   a hard ceiling (see `Gemfile`'s comment for the full rationale -- scripts
   under `scripts/` must run on the vanilla macOS system Ruby). Flag any gem
   version bump that would require Ruby >= 2.7 as a CRITICAL finding, even if
   Bundler's resolver accepted it (the pin should prevent this, but a
   manually-edited `Gemfile.lock` could bypass it).

3. **Unexpected transitive dependencies**: Compare the diff's added/removed
   entries in `Gemfile.lock` against the direct gems declared in `Gemfile`
   (`rubocop`, `rubocop-ast`, `rspec`, `bundler-audit`). A large, unrelated
   set of new transitive dependencies pulled in by a small version bump is
   worth flagging as MEDIUM risk -- it may indicate the new release
   significantly changed its own dependency tree.

4. **Gem source/provenance**: Confirm every gem still resolves from
   `https://rubygems.org` (the only `source` declared in `Gemfile`). A diff
   that introduces a git/path source, or changes the declared `source`, is a
   CRITICAL finding -- this is the most common supply-chain attack vector for
   a Bundler project.

5. **Version pin changes**: This repo pins exact versions for `rubocop`,
   `rubocop-ast`, `rspec`, and `bundler-audit` in `Gemfile` (not `~>` or open
   ranges) specifically to avoid `prism`-dependent releases that need Ruby
   >= 2.7 (see `Gemfile` comments). Flag any diff that loosens a pin to a
   range as MEDIUM risk -- even if the immediate bump is fine, an open range
   defeats the reason the pin exists.

Do not apply the parts of `.github/agents/security-reviewer.agent.md`'s
checklist that assume a shell/Ruby *script* under review (command injection,
privilege escalation, race conditions, temp file handling) -- none of that
is meaningful for a `Gemfile`/`Gemfile.lock` diff.
