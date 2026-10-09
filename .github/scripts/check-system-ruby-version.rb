#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Compares the macOS system Ruby version against the 'ruby' directive pinned in
# Gemfile, and files a GitHub issue if they've drifted apart.
#
# Run on a schedule (see .github/workflows/system-ruby-version-check.yml) so
# drift is caught even during periods with no pushes -- 'bundle install'
# already fails loudly on every push/PR if the two mismatch (see
# .github/workflows/lint.yml and rspec.yml), but that only fires when someone
# actually pushes. This script exists to catch drift proactively in between.
#
# Deliberately dependency-free (no scripts/utilities): it runs on a bare CI runner.
#
# Requires: 'gh' CLI, authenticated via a GH_TOKEN env var with 'issues: write'
# permission (set by the calling workflow), run from inside a checkout of this repo.
#
# Usage:
#   Standalone: check-system-ruby-version.rb [path-to-gemfile]
#   Module:     CheckSystemRubyVersion.run(gemfile: 'Gemfile')

require 'open3'
require 'tempfile'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module CheckSystemRubyVersion
  extend self

  SYSTEM_RUBY = '/usr/bin/ruby'
  LABEL = 'ruby-version-drift'

  # Public API method.
  #
  # @param gemfile [String] Path to the Gemfile holding the 'ruby' pin
  # @return [Boolean] false only if the pin could not be read or a gh call failed
  def run(gemfile: 'Gemfile')
    pinned = File.read(gemfile, encoding: 'UTF-8')[/^ruby '([0-9.]+)'/, 1]
    unless pinned
      warn "#{script_name}: could not find a 'ruby' version pin in '#{gemfile}'."
      return false
    end

    actual = `#{SYSTEM_RUBY} -e 'print RUBY_VERSION'`
    actual_full = `#{SYSTEM_RUBY} -v`.strip
    puts "Gemfile pin: #{pinned}"
    puts "System Ruby: #{actual} (#{actual_full})"

    if pinned == actual
      puts 'In sync -- nothing to do.'
      return true
    end

    title = "System Ruby version drift: Gemfile pins #{pinned}, runner has #{actual}"
    open_issue(title, pinned, actual_full)
  end

  # Opens the drift issue unless an open one already reports this exact pairing.
  #
  # @return [Boolean] whether the gh calls succeeded
  def open_issue(title, pinned, actual_full)
    existing, = Open3.capture2('gh', 'issue', 'list', '--search', "#{title} in:title", '--state', 'open',
                               '--json', 'number', '--jq', '.[0].number // empty')
    unless existing.strip.empty?
      puts "Issue ##{existing.strip} already open for this drift -- skipping."
      return true
    end

    # Idempotent: a no-op (non-zero exit, ignored) if the label already exists.
    system('gh', 'label', 'create', LABEL, '--color', 'd93f0b',
           '--description', 'macOS system Ruby no longer matches the Gemfile pin', err: File::NULL)

    Tempfile.create('drift-issue-body') do |body|
      body.write(issue_body(pinned, actual_full))
      body.flush
      system('gh', 'issue', 'create', '--title', title, '--body-file', body.path, '--label', LABEL)
    end
  end

  private_class_method :open_issue

  # @return [String] Markdown body of the drift issue
  def issue_body(pinned, actual_full)
    <<~BODY
      The macOS system Ruby (`/usr/bin/ruby`) used by this repo's tooling and CI
      no longer matches the version pinned in `Gemfile` (`ruby '#{pinned}'`).

      - Detected system Ruby: `#{actual_full}`
      - Gemfile pin: `#{pinned}`

      This most likely means Apple shipped a new macOS/Xcode Command Line Tools
      release with a different bundled Ruby, or the GitHub `macos-latest` runner
      image changed. `bundle install` will fail on every push/PR until this is
      resolved (see `.github/workflows/lint.yml` / `rspec.yml`).

      **Action needed:**
      1. Decide whether to update the `ruby '#{pinned}'` pin in `Gemfile`
         to match the new version, or whether this drift is unexpected/transient.
      2. If updating: re-run `bundle install` to regenerate `Gemfile.lock`'s
         `RUBY VERSION` section, and review whether `.rubocop.yml`'s
         `TargetRubyVersion` and the Ruby-2.6-compatibility rules in
         `.ai/domains/ruby-scripting.md` still apply, or need updating too.
      3. Re-run this workflow (or push a commit) to confirm the drift is resolved.
    BODY
  end

  private_class_method :issue_body

  # @return [String]
  def script_name
    File.basename($PROGRAM_NAME)
  end

  private_class_method :script_name
end

if __FILE__ == $PROGRAM_NAME
  exit(CheckSystemRubyVersion.run(gemfile: ARGV.first || 'Gemfile') ? 0 : 1)
end
