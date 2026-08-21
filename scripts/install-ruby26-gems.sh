#!/usr/bin/env zsh
# shellcheck shell=zsh
# file location: ${DOTFILES_DIR}/scripts/install-ruby26-gems.sh
#
# Install Ruby 2.6 compatible static analysis gems for dotfiles repository
#
# These versions are the last ones that work with Ruby 2.6.10 (system Ruby on macOS).
# Newer versions have transitive dependencies requiring Ruby 2.7+ or Ruby 3.2+.
#
# Usage:
#   install-ruby26-gems.sh    # Idempotent: install missing gems, silent if already present
#
# This script is idempotent and designed to be called by .envrc:
# - First run: installs gems (~2 min), outputs progress via info/success logging
# - Subsequent runs: gems already installed, exits instantly with no output
# - .envrc calls this script then adds gem bin directory to PATH

set -euo pipefail

# Re-source guard is inside .shellrc itself -- safe to call unconditionally.
source "${HOME}/.shellrc"

# ---------------------------------------------------------------------------
# Constants

_GEM_DIR="${HOME}/.gem/ruby/2.6.0"
_SYSTEM_RUBY="/usr/bin/ruby"

# Associative array: "tool:version" => "dependencies"
# Key is the main tool gem spec (executable name extracted from "tool:version")
# Value is space-separated dependency gem specs (installed before the tool)
# Keys sorted alphabetically for maintainability
typeset -A _GEM_SPECS
_GEM_SPECS=(
  "flay:2.11.0"    "sexp_processor:4.15.0 ruby_parser:3.14.2"
  "flog:4.6.2"     "sexp_processor:4.15.0 ruby_parser:3.14.2"
  "reek:6.1.4"     "parser:2.7.1.5 rainbow:3.0.0 rexml:3.2.5"
  "rubocop:0.93.1" "parser:2.7.1.5 parallel:1.20.0 rainbow:3.0.0 regexp_parser:2.1.1 rexml:3.2.5 rubocop-ast:1.4.0 ruby-progressbar:1.11.0 unicode-display_width:1.8.0"
  "rufo:0.13.0"    ""
)

# ---------------------------------------------------------------------------
# Private helpers

# Installs a gem and its dependencies if the gem executable is not present.
# Args: $1 = gem spec (tool:version), $2 = space-separated dependency specs
_install_gem_if_missing() {
  local gem_spec="${1}"
  local dependencies="${2}"
  local gem_bin_dir="${_GEM_DIR}/bin"

  # Extract executable name from "tool:version"
  local gem_name="${gem_spec%%:*}"

  if ! is_executable "${gem_bin_dir}/${gem_name}"; then
    info "Installing $(yellow "${gem_name}")..."
    # Install dependencies first, then the tool itself
    if [[ -n "${dependencies}" ]]; then
      gem install ${dependencies} ${gem_spec} --user-install --no-document
    else
      gem install ${gem_spec} --user-install --no-document
    fi
    return 0  # Indicate installation occurred
  fi
  return 1  # Indicate gem already present
}

# ---------------------------------------------------------------------------
# Main

main() {
  # Check system Ruby version (not mise Ruby in PATH)
  # System Ruby is what dotfiles scripts use (#!/usr/bin/env ruby resolves to system Ruby
  # on vanilla OS). Gems must be installed for system Ruby 2.6 regardless of whether
  # user has mise Ruby installed, due to per-version gem isolation.
  if ! is_executable "${_SYSTEM_RUBY}"; then
    # No system Ruby - nothing to do
    return 0
  fi

  # Only install if system Ruby is 2.6.x (macOS default)
  # Skip if system Ruby is already > 2.6 (unexpected but possible on future macOS versions)
  local ruby_version="$("${_SYSTEM_RUBY}" -e 'print RUBY_VERSION')"
  if [[ "${ruby_version}" > "2.6" && "${ruby_version}" != "2.6"* ]]; then
    # Ruby > 2.6 doesn't need our pinned gems
    return 0
  fi

  # Install only missing gems (granular, per-tool check)
  local installed_count=0
  local gem_spec

  for gem_spec in "${(@k)_GEM_SPECS}"; do
    if _install_gem_if_missing "${gem_spec}" "${_GEM_SPECS[${gem_spec}]}"; then
      ((installed_count += 1)) || true
    fi
  done

  if [[ ${installed_count} -gt 0 ]]; then
    success "Installed $(purple "${installed_count}") gem(s) successfully!"
  fi
}

main "$@"
