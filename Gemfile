# frozen_string_literal: true

source 'https://rubygems.org'

# Pins Bundler's dependency resolution to the actual system Ruby (see
# .rubocop.yml TargetRubyVersion / Adoption.md). This is a hard ceiling, not
# just documentation: with this declared, 'bundle install'/'bundle update'
# (including Dependabot's version-update checks -- see .github/dependabot.yml)
# will refuse to resolve any gem version that requires a newer Ruby, so a
# 'prism'-dependent rubocop/rspec release (which needs Ruby >= 2.7) can never
# be proposed or installed here by accident.
ruby '2.6.10'

# Pinned to versions compatible with Ruby 2.6 (see .rubocop.yml TargetRubyVersion --
# this repo's scripts must run under the system Ruby shipped on vanilla macOS).
# Newer rubocop/rubocop-ast releases depend on the 'prism' parser gem, which
# requires Ruby >= 2.7 and cannot be installed under 2.6. Used by CI (see
# .github/workflows/lint.yml) and locally via 'bundle exec rubocop'.
gem 'rubocop', '0.93.1'
gem 'rubocop-ast', '1.4.0'

# Test framework for scripts/utilities/*.rb (see spec/). rspec 3.13 is the
# latest release line and installs cleanly under Ruby 2.6 -- unlike rubocop,
# it has no 'prism' dependency to avoid. Used by CI (see .github/workflows/rspec.yml)
# and locally via 'bundle exec rspec'.
gem 'rspec', '3.13.2'

# Line-coverage reporting for the rspec suite (see spec/spec_helper.rb). 0.22.0
# installs cleanly under Ruby 2.6 (no 'prism' dependency). Writes
# coverage/.resultset.json, which .github/workflows/rspec.yml uploads to
# Codecov for the coverage badge in README.md.
gem 'simplecov', '0.22.0', require: false

# Checks Gemfile.lock against the Ruby Advisory Database for known CVEs.
# Installs cleanly under Ruby 2.6 (no 'prism' dependency). Used by CI (see
# .github/workflows/dependabot-audit.yml and .github/workflows/bundler-audit.yml)
# to gate Dependabot's version-bump pull requests and to continuously check
# master, and locally via 'bundle exec bundler-audit check --update'.
gem 'bundler-audit', '0.9.3'
