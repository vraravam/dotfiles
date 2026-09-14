# frozen_string_literal: true

# SimpleCov must start before any application code is required, so it must be
# the very first thing this file does. Writes coverage/.resultset.json (used
# by the Codecov upload step in .github/workflows/rspec.yml) plus a local
# coverage/index.html for `open coverage/index.html` during development.
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

# Spec helper for scripts/utilities/*.rb tests.
#
# Adds scripts/utilities to the load path so specs can 'require' the same way
# ${PERSONAL_BIN_DIR} scripts do via RUBYLIB (see files/--HOME--/.shellrc), but
# without depending on RUBYLIB being exported in the test/CI environment.
UTILITIES_DIR = File.expand_path('../scripts/utilities', __dir__)
$LOAD_PATH.unshift(UTILITIES_DIR) unless $LOAD_PATH.include?(UTILITIES_DIR)

# Shared helper for specs that exercise ENV-dependent code (Core, EnvVars).
# Temporarily sets the given variables for the duration of the block, then
# restores their previous values -- including deleting keys that were unset
# before the block ran. A nil value in `vars` deletes that key for the block.
module EnvHelpers
  def with_env(vars)
    previous = {}
    vars.each_key { |key| previous[key] = ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end

RSpec.configure do |config|
  config.include EnvHelpers

  # Enable the newer, more explicit expect(...).to syntax only (not should).
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Disallow mocking/stubbing partial doubles unless explicitly opted in --
  # catches typos in stubbed method names.
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Run specs in random order to surface accidental order-dependent state
  # (relevant here since several specs mutate ENV and must restore it).
  config.order = :random
  Kernel.srand config.seed
end
