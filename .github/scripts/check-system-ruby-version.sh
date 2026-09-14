#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# Compares the macOS system Ruby version against the 'ruby' directive pinned in
# Gemfile, and files a GitHub issue if they've drifted apart.
#
# Run on a schedule (see .github/workflows/system-ruby-version-check.yml) so
# drift is caught even during periods with no pushes -- 'bundle install'
# already fails loudly on every push/PR if the two mismatch (see
# .github/workflows/lint.yml and rspec.yml), but that only fires when someone
# actually pushes. This script exists to catch drift proactively in between.
#
# Requires: 'gh' CLI, authenticated via a GH_TOKEN env var with 'issues: write'
# permission (set by the calling workflow), run from inside a checkout of this repo.
#
# Usage: check-system-ruby-version.sh [path-to-gemfile]

set -euo pipefail

_SCRIPT_NAME="${0:t}"

main() {
  local gemfile="${1:-Gemfile}"

  local pinned_version
  pinned_version="$(grep -oE "^ruby '[0-9.]+'" "${gemfile}" | grep -oE '[0-9.]+')"
  if [[ -z "${pinned_version}" ]]; then
    echo "${_SCRIPT_NAME}: could not find a 'ruby' version pin in '${gemfile}'." >&2
    return 1
  fi

  local actual_version actual_full
  actual_version="$(/usr/bin/ruby -e 'print RUBY_VERSION')"
  actual_full="$(/usr/bin/ruby -v)"

  echo "Gemfile pin: ${pinned_version}"
  echo "System Ruby: ${actual_version} (${actual_full})"

  if [[ "${pinned_version}" == "${actual_version}" ]]; then
    echo "In sync -- nothing to do."
    return 0
  fi

  local title="System Ruby version drift: Gemfile pins ${pinned_version}, runner has ${actual_version}"

  # Idempotency: don't open a duplicate issue if one is already open reporting
  # this exact drift (pinned version vs actual version pairing).
  local existing
  existing="$(gh issue list --search "${title} in:title" --state open --json number --jq '.[0].number // empty')"
  if [[ -n "${existing}" ]]; then
    echo "Issue #${existing} already open for this drift -- skipping."
    return 0
  fi

  # Idempotent: no-op if the label already exists.
  gh label create 'ruby-version-drift' --color 'd93f0b' \
    --description 'macOS system Ruby no longer matches the Gemfile pin' 2>/dev/null || true

  local body_file
  body_file="$(mktemp)"
  trap 'rm -f "${body_file}"' EXIT

  {
    echo "The macOS system Ruby (\`/usr/bin/ruby\`) used by this repo's tooling and CI"
    echo "no longer matches the version pinned in \`Gemfile\` (\`ruby '${pinned_version}'\`)."
    echo ''
    echo "- Detected system Ruby: \`${actual_full}\`"
    echo "- Gemfile pin: \`${pinned_version}\`"
    echo ''
    echo 'This most likely means Apple shipped a new macOS/Xcode Command Line Tools'
    echo 'release with a different bundled Ruby, or the GitHub `macos-latest` runner'
    echo 'image changed. `bundle install` will fail on every push/PR until this is'
    echo 'resolved (see `.github/workflows/lint.yml` / `rspec.yml`).'
    echo ''
    echo '**Action needed:**'
    echo "1. Decide whether to update the \`ruby '${pinned_version}'\` pin in \`Gemfile\`"
    echo '   to match the new version, or whether this drift is unexpected/transient.'
    echo "2. If updating: re-run \`bundle install\` to regenerate \`Gemfile.lock\`'s"
    echo "   \`RUBY VERSION\` section, and review whether \`.rubocop.yml\`'s"
    echo "   \`TargetRubyVersion\` and the Ruby-2.6-compatibility rules in"
    echo "   \`.ai/domains/ruby-scripting.md\` still apply, or need updating too."
    echo '3. Re-run this workflow (or push a commit) to confirm the drift is resolved.'
  } >"${body_file}"

  gh issue create --title "${title}" --body-file "${body_file}" --label 'ruby-version-drift'
}

main "$@"
