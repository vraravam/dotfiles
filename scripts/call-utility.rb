#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/call-utility.rb
#
# Calls one public method of a utility module (scripts/utilities/*.rb) with arguments
# taken from ARGV. This is the bridge shell functions use to reach Ruby utilities:
# arguments travel as real argv entries, so no shell value is ever spliced into Ruby
# source (no quoting or injection hazards), and no RUBYLIB setup is needed.
#
# Only the modules listed in UTILITIES can be called. Arguments are passed positionally
# as strings; '--name=value' arguments become keyword arguments, with 'true'/'false'
# converted to booleans. Everything after a literal '--' is positional, even if it
# starts with '--'.
#
# Exit status is 0 unless the call raises. With '--truthy', a nil/false return value
# also exits 1 (for predicate-style methods such as Keybase.username).
#
# Usage:
#   Standalone: call-utility.rb [--truthy] <Module.method> [arg ...] [--key=value ...]
#   Module:     CallUtility.run(target: 'Cron.recron', args: [], truthy: false)
#
# Examples:
#   call-utility.rb Cron.create_crontab "${PERSONAL_CONFIGS_DIR}/crontab.txt"
#   call-utility.rb DevEnvironment.setup_dev_environment --first_install=true
#   call-utility.rb --truthy Keybase.username

# Modules callable from the command line, mapped to the utility file that defines each.
# An explicit allow-list (rather than a name-derived require) keeps ARGV from being able
# to load or invoke anything else.
UTILITIES = {
  'Antidote' => 'antidote',
  'BrewBundle' => 'brew_bundle',
  'Cron' => 'cron',
  'DefaultShell' => 'default_shell',
  'DevEnvironment' => 'dev_environment',
  'GenerateBootstrapRepositoriesYaml' => 'generate_bootstrap_repositories_yaml',
  'GitWorkspace' => 'git_workspace',
  'HomebrewInstall' => 'homebrew_install',
  'Keybase' => 'keybase',
  'MacOS' => 'macos',
  'ShellrcCheck' => 'shellrc_check'
}.freeze

# Module contains the business logic.
# Returns true/false instead of calling exit().
module CallUtility
  extend self

  KEYWORD_ARG = /\A--([a-z_][a-z0-9_]*)=(.*)\z/m.freeze

  # Public API method.
  #
  # @param target [String] '<Module>.<method>', e.g. 'Cron.recron'
  # @param args [Array<String>] Positional and '--key=value' keyword arguments
  # @param truthy [Boolean] When true, a nil/false return value counts as failure
  # @return [Boolean] true unless +truthy+ and the method returned nil/false
  def run(target:, args: [], truthy: false)
    module_name, method_name = target.to_s.split('.', 2)
    utility_file = UTILITIES[module_name]
    raise ArgumentError, "Unknown utility module '#{module_name}' (allowed: #{UTILITIES.keys.join(', ')})" unless utility_file
    raise ArgumentError, "Expected <Module>.<method>, got '#{target}'" if method_name.to_s.empty?

    require_relative "utilities/#{utility_file}"
    utility = Object.const_get(module_name)
    raise ArgumentError, "#{module_name} has no public method '#{method_name}'" unless utility.respond_to?(method_name)

    positional, keywords = _split_args(args)
    # An empty '**{}' would be passed as a stray positional Hash to methods that take no
    # keywords on Ruby 2.6, so only splat keywords when there are some.
    result = if keywords.empty?
               utility.public_send(method_name, *positional)
             else
               utility.public_send(method_name, *positional, **keywords)
             end

    truthy ? !!result : true
  end

  # Splits raw argv entries into positional values and a keyword Hash.
  #
  # @param args [Array<String>]
  # @return [Array(Array<String>, Hash{Symbol => Object})]
  # :reek:UtilityFunction -- Stateless argument parser
  def _split_args(args)
    positional = []
    keywords = {}
    literal_rest = false
    args.each do |arg|
      if literal_rest
        positional << arg
      elsif arg == '--'
        literal_rest = true
      elsif (match = KEYWORD_ARG.match(arg))
        keywords[match[1].to_sym] = _coerce(match[2])
      else
        positional << arg
      end
    end
    [positional, keywords]
  end

  private_class_method :_split_args

  # Converts the literal strings 'true'/'false' to booleans; everything else stays a String.
  #
  # @param value [String]
  # @return [String, Boolean]
  # :reek:UtilityFunction -- Stateless converter
  def _coerce(value)
    case value
    when 'true' then true
    when 'false' then false
    else value
    end
  end

  private_class_method :_coerce
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  truthy = ARGV.first == '--truthy'
  ARGV.shift if truthy
  target = ARGV.shift

  if target.nil? || %w[-h --help].include?(target)
    warn "Usage: #{File.basename($PROGRAM_NAME)} [--truthy] <Module.method> [arg ...] [--key=value ...]"
    warn "Modules: #{UTILITIES.keys.join(', ')}"
    exit(target.nil? ? 1 : 0)
  end

  exit(CallUtility.run(target: target, args: ARGV, truthy: truthy) ? 0 : 1)
end
