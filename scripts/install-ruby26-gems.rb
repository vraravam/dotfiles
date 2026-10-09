#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/install-ruby26-gems.rb
#
# Installs the static analysis gems used to develop this repository, at the versions that
# are the last ones to work with Ruby 2.6.10 (system Ruby on macOS). Newer versions have
# transitive dependencies requiring Ruby 2.7+ or Ruby 3.2+.
#
# Always installs for the system Ruby (/usr/bin/ruby), regardless of which Ruby is first
# in PATH (e.g. a mise-managed one): gems are isolated per Ruby version, and the scripts in
# this repo run under the system Ruby on a vanilla OS.
#
# Idempotent and designed to be called by .envrc:
# - First run: installs the missing gems (~2 min), logging progress
# - Subsequent runs: every tool is already installed, so it returns immediately and silently
#
# Usage:
#   Standalone: install-ruby26-gems.rb [--debug]
#   Module:     InstallRuby26Gems.run(debug: false)

require 'open3'

require_relative 'utilities/command_utils'
require_relative 'utilities/env_vars'
require_relative 'utilities/logging'
require_relative 'utilities/path_utils'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module InstallRuby26Gems
  extend self

  SYSTEM_RUBY = '/usr/bin/ruby'
  SYSTEM_GEM = '/usr/bin/gem'
  GEM_DIR = EnvVars::HOME.join('.gem', 'ruby', '2.6.0')
  GEM_BIN_DIR = GEM_DIR.join('bin')
  FIRST_UNSUPPORTED_VERSION = '2.7'

  # Tool gem => the exact version to install and its dependency gems ('name:version'),
  # which are installed first. The single source of truth for which gems this repo needs.
  GEM_SPECS = {
    'flay' => { version: '2.11.0', dependencies: %w[sexp_processor:4.15.0 ruby_parser:3.14.2] },
    'flog' => { version: '4.6.2', dependencies: %w[sexp_processor:4.15.0 ruby_parser:3.14.2] },
    'reek' => { version: '6.1.4', dependencies: %w[parser:2.7.1.5 rainbow:3.0.0 rexml:3.2.5] },
    'rubocop' => {
      version: '0.93.1',
      dependencies: %w[parser:2.7.1.5 parallel:1.20.0 rainbow:3.0.0 regexp_parser:2.1.1 rexml:3.2.5
                       rubocop-ast:1.4.0 ruby-progressbar:1.11.0 unicode-display_width:1.8.0]
    },
    'rufo' => { version: '0.13.0', dependencies: [] }
  }.freeze

  # Public API method.
  #
  # @param debug [Boolean] Log diagnostic information for troubleshooting
  # @return [Boolean] true on success (including "nothing to do"), false if any install failed
  def run(debug: false)
    missing = GEM_SPECS.keys.reject { |tool| GEM_BIN_DIR.join(tool).executable? }
    if missing.empty?
      Logging.info 'All gems already installed' if debug
      return true
    end

    return true unless _system_ruby_supported?(debug)

    PathUtils.ensure_directories_exist(GEM_DIR)
    unless CommandUtils.run_silent(SYSTEM_RUBY, '-e', "require 'rubygems'")
      Logging.warn "RubyGems not available for system Ruby #{_system_ruby_version.purple}"
      return false
    end

    installed = 0
    failed = false
    missing.each do |tool|
      if _install(tool, debug)
        installed += 1
      else
        failed = true
      end
    end

    Logging.success "Installed #{installed.to_s.purple} gem(s) successfully!" if installed.positive?
    !failed
  end

  # Whether the system Ruby is one these pinned gem versions target. A newer system Ruby
  # (possible on a future macOS) can use current gem versions instead, so it is skipped.
  #
  # @param debug [Boolean] Log the detected version
  # @return [Boolean]
  def _system_ruby_supported?(debug)
    unless File.executable?(SYSTEM_RUBY)
      Logging.warn "System Ruby not found at '#{SYSTEM_RUBY.cyan}'" if debug
      return false
    end

    version = _system_ruby_version
    Logging.info "System Ruby version: #{version.purple}; gem directory: '#{GEM_DIR.cyan}'" if debug
    return true if Gem::Version.new(version) < Gem::Version.new(FIRST_UNSUPPORTED_VERSION)

    Logging.info "Ruby #{version.purple} >= #{FIRST_UNSUPPORTED_VERSION.purple} - skipping gem installation" if debug
    false
  end

  private_class_method :_system_ruby_supported?

  # @return [String] RUBY_VERSION of the system Ruby (not necessarily the running one)
  def _system_ruby_version
    @_system_ruby_version ||= CommandUtils.query(SYSTEM_RUBY, '-e', 'print RUBY_VERSION')
  end

  private_class_method :_system_ruby_version

  # Installs one tool gem (dependencies first, in the same 'gem install' call).
  #
  # @param tool [String] Key of GEM_SPECS
  # @param debug [Boolean] Log the exact command
  # @return [Boolean] true if the tool's executable exists afterwards
  def _install(tool, debug)
    spec = GEM_SPECS.fetch(tool)
    Logging.info "Installing #{tool.yellow}..."

    # --conservative avoids needlessly updating gems that already satisfy the requirement.
    command = [SYSTEM_GEM, 'install', *spec[:dependencies], "#{tool}:#{spec[:version]}",
               '--user-install', '--no-document', '--conservative']
    Logging.info "Running: '#{command.join(' ').cyan}'" if debug

    output, status = Open3.capture2e(*command)
    unless status.success?
      Logging.warn "Failed to install #{tool.yellow} (exit code #{status.exitstatus.to_s.red})"
      warn output.lines.last(10).join
      hint = _toolchain_hint(output)
      Logging.warn hint if hint
      return false
    end

    return true if GEM_BIN_DIR.join(tool).executable?

    Logging.warn "Installation reported success but #{tool.yellow} executable not found at '#{GEM_BIN_DIR.join(tool).cyan}'"
    false
  end

  private_class_method :_install

  # Explains the most common reason a gem fails here: a native extension (reek pulls in
  # racc) cannot compile because the Ruby headers the system Ruby was built against are not
  # in the active Xcode Command Line Tools SDK, so make has no rule for 'ruby/config.h'.
  #
  # @param output [String] Combined output of the failed 'gem install'
  # @return [String, nil] Advice, or nil when the failure does not look toolchain related
  def _toolchain_hint(output)
    return unless output.match?(%r{No rule to make target|ruby/config\.h|mkmf\.rb can't find header|extconf\.rb failed})

    header = CommandUtils.query(SYSTEM_RUBY, '-rrbconfig', '-e', "print File.join(RbConfig::CONFIG['rubyarchhdrdir'], 'ruby', 'config.h')")
    missing = !File.exist?(header)
    detail = missing ? "the Ruby header '#{header.cyan}' that the build needs does not exist" : 'the toolchain could not build a native extension'
    install = 'xcode-select --install'.cyan
    reinstall = 'sudo rm -rf /Library/Developer/CommandLineTools'.cyan
    sdk = 'xcrun --show-sdk-path'.cyan
    "A native extension failed to compile: #{detail}. The Xcode Command Line Tools are probably missing or out of date: " \
    "run '#{install}' (if already installed, remove and reinstall them: '#{reinstall}' then '#{install}'), " \
    "then re-run this script. Check the active SDK with '#{sdk}'."
  end

  private_class_method :_toolchain_hint
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  CliParser.parse('[--debug]') do |opts|
    opts.separator "Installs the Ruby 2.6 compatible static analysis gems (#{InstallRuby26Gems::GEM_SPECS.keys.join(', ')})."
    opts.separator ''
    opts.on('-d', '--debug', 'Show diagnostic information for troubleshooting') { options[:debug] = true }
  end

  Logging.run_script do
    exit(InstallRuby26Gems.run(debug: options.fetch(:debug, false)) ? 0 : 1)
  end
end
