#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: anywhere in the PATH
#
# Clones a template repository into a new folder and retargets it to a new project name and
# Java package name. Everything that describes the template and the target comes from ONE YAML
# file, so the script itself knows nothing about any particular template.
#
# STANDALONE BY DESIGN: this script deliberately depends on NOTHING under
# scripts/utilities/ (no Logging, CliParser, EnvVars, ...) -- only the Ruby stdlib -- so
# that it can be copied and run on a machine that does not have the dotfiles checked out.
# That is why it carries its own tiny output helpers (TemplateRepositoryCloner::Log) instead
# of using the shared Logging module (and so has no color and no script-depth indentation).
# Do NOT "fix" this by requiring the utilities.
#
# Usage:
#   Standalone: template-repository-cloner.rb <config.yml>
#   Module:     TemplateRepositoryCloner.run(**TemplateRepositoryCloner.load_config('config.yml'))
#
# Config file (a YAML mapping; unknown keys are rejected so typos are caught):
#
#   source_repository_url: https://github.com/luismalamoc/springboot-template.git  # required; anything 'git clone' accepts
#   target_project_name: my-new-app                                                # required; kebab-case; the folder created under the current directory
#   target_package_name: com.myapp                                                 # required; target Java package (dot-separated lowercase)
#   source_package_name: com.example.springboottemplate                            # required; the template's Java package
#   source_application_class_name: SpringBootTemplateApplication                   # optional; the template's main class (omit if none)
#   target_application_class_name: MyNewAppApplication                             # optional; default: derived from target_package_name (segments title-cased and joined: com.acme.myapp => ComAcmeMyapp)
#   skip_git_init: false                                                           # optional; default false
#   replacements:                                                                  # optional; literal text => replacement text, applied to file CONTENTS only
#     springboot-template: ${target_project_name}                                  # ${target_project_name}, ${target_package_name} and ${target_application_class_name} expand to the target values
#     Springboot Template: My New App
#
# What it does, in order:
#   1. Shallow-clones the template into <cwd>/<target_project_name>.
#   2. Initializes git plus an initial commit unless skip_git_init, or unless the clone already
#      has a .git (which a normal clone always does, so in practice this step only acts when the
#      clone produced no .git).
#   3. Moves every directory named like source_package_name as a path (e.g.
#      src/main/java/com/example/springboottemplate) to the target package path, prunes the
#      ancestor directories left empty, and renames <source_application_class_name>.java.
#   4. Rewrites the text of every file (excluding .git/ and node_modules/ and anything that is
#      not valid UTF-8): source package, source folder path and source class name are replaced by
#      their target equivalents, then each `replacements` entry is applied, in file order. All
#      replacements are literal and match on word boundaries ('-' and '.' count as boundaries,
#      so 'springboot-template' also matches inside 'springboot-template-api').
#
# Only file CONTENTS are rewritten for `replacements`; file and folder names are not. The script
# does NOT generate any new code and does not touch tooling or dependencies.
#
# Set DEBUG=true for backtraces and verbose file operations.

require 'fileutils'
require 'find'
require 'yaml'

# ============================================================================
# Stdlib extensions (kept local to this script so it has no other dependencies)
# ============================================================================
class String
  # True when empty or whitespace-only. Not nil-safe: call as `value.to_s.blank?`.
  def blank?
    strip.empty?
  end

  # Upcases the first character and downcases the rest ('hELLO' => 'Hello').
  def titleize
    return self if empty?

    "#{self[0].upcase}#{self[1, length].downcase}"
  end

  # Converts a package name to kebab case ('Com.Acme.MyApp' => 'com-acme-myapp').
  def dot_to_hyphen
    tr('.', '-').downcase
  end

  # Converts a package name to a folder path ('Com.Acme.MyApp' => 'com/acme/myapp').
  # Memoized per input string (pure function, so the cache can never go stale).
  DOT_TO_FOLDER_CACHE = Hash.new { |cache, key| cache[key] = key.tr('.', '/').downcase.freeze }

  def dot_to_folder
    DOT_TO_FOLDER_CACHE[self]
  end

  # Converts a package name to a class name ('com.acme.myapp' => 'ComAcmeMyapp'). Memoized per input string.
  TO_CLASS_NAME_CACHE = Hash.new { |cache, key| cache[key] = key.dot_to_hyphen.split('-').map(&:titleize).join.freeze }

  def to_class_name
    TO_CLASS_NAME_CACHE[self]
  end

  # Replaces +old_text+ with +new_text+, on word boundaries: +old_text+ must not be directly
  # preceded or followed by a letter, digit or underscore ('-' and '.' do count as boundaries,
  # so 'my-app' matches in 'my-app-gradle'). Lookarounds are used rather than \\b so that an
  # +old_text+ starting or ending with punctuation still matches. Both strings are taken
  # literally: dots in +old_text+ are not wildcards, and +new_text+ has no backreferences.
  # The compiled pattern is memoized per +old_text+, since it is applied to every file.
  WORD_BOUNDARY_PATTERN_CACHE = Hash.new { |cache, key| cache[key] = /(?<![A-Za-z0-9_])#{Regexp.escape(key)}(?![A-Za-z0-9_])/.freeze }

  def safe_gsub(old_text, new_text)
    gsub(WORD_BOUNDARY_PATTERN_CACHE[old_text]) { new_text }
  end
end

class File
  # Writes +content+ to +file_path+ only when it differs from what is already there.
  def self.update_if_content_changed(file_path, content)
    if content == File.read(file_path, encoding: 'UTF-8')
      TemplateRepositoryCloner::Log.debug("No changes needed: #{file_path}")
    else
      File.write(file_path, content)
      TemplateRepositoryCloner::Log.success("Updated: #{file_path}")
    end
  end
end

module TemplateRepositoryCloner
  module_function

  # ===========================================================================
  # Configuration
  # ===========================================================================

  # Lowercase letters/digits, at least two hyphen-separated words, e.g. 'my-project'.
  KEBAB_STRING_PATTERN = /\A[a-z][a-z0-9]*(-[a-z][a-z0-9]*)+\z/.freeze
  # Lowercase letters/digits, at least two dot-separated segments, e.g. 'com.acme'.
  DOT_STRING_PATTERN = /\A[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+\z/.freeze

  # A Java class name (also what the application class file is named, minus '.java').
  CLASS_NAME_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/.freeze

  REQUIRED_CONFIG_KEYS = %w[source_repository_url target_project_name target_package_name source_package_name].freeze
  OPTIONAL_CONFIG_KEYS = %w[source_application_class_name target_application_class_name skip_git_init replacements].freeze
  # ${name} placeholders usable in the VALUES of `replacements` (never in the keys).
  PLACEHOLDER_PATTERN = /\$\{(\w+)\}/.freeze
  PLACEHOLDER_NAMES = %w[target_project_name target_package_name target_application_class_name].freeze
  GIT_DIR_NAME = '.git'
  NODE_MODULES_DIR_NAME = 'node_modules'
  # Shallow clone: only the template's latest snapshot is needed, never its history.
  GIT_CLONE_ARGS = %w[clone --depth 1 --single-branch].freeze
  INITIAL_COMMIT_MESSAGE = 'Initial commit'
  # Directory names never descended into when rewriting content.
  EXCLUDED_DIR_NAMES = [GIT_DIR_NAME, NODE_MODULES_DIR_NAME].freeze
  USAGE = 'Usage: template-repository-cloner.rb <config.yml>'

  # ===========================================================================
  # Output (self-contained replacement for the shared Logging module)
  # ===========================================================================

  # Minimal prefixed output; plain puts so the script has no dependencies.
  module Log
    module_function

    def info(msg)
      puts "[INFO] #{msg}"
    end

    def success(msg)
      puts "[SUCCESS] #{msg}"
    end

    def error(msg)
      puts "[ERROR] #{msg}"
    end

    # Printed only when DEBUG=true.
    def debug(msg)
      puts "[DEBUG] #{msg}" if debug?
    end

    def section(title)
      puts "\n[#{title}]"
      puts '=' * 50
    end

    # Memoized: DEBUG is read once, not on every file operation.
    def debug?
      @debug = ENV['DEBUG'] == 'true' if @debug.nil?
      @debug
    end
  end

  # ===========================================================================
  # Configuration loading and validation
  # ===========================================================================

  # Turns CLI arguments into the keyword arguments of run.
  #
  # @param argv [Array<String>] exactly one element: the path of the YAML config file
  # @return [Hash] see load_config
  # @raise [ArgumentError] on a wrong number of arguments, or an unreadable/invalid config file
  def parse_args(argv)
    raise ArgumentError, USAGE unless argv.length == 1

    load_config(argv.first)
  end

  # Reads and checks the YAML config file (see the header for the format).
  #
  # @param path [String] YAML file
  # @return [Hash] keyword arguments for run (symbol keys; optional ones defaulted)
  # @raise [ArgumentError] when the file is missing/unparsable, is not a mapping, lacks a
  #   required key, has an unknown key, or has a value of the wrong type
  def load_config(path)
    raise ArgumentError, "Config file not found: #{path}\n#{USAGE}" unless File.file?(path)

    config = begin
        YAML.safe_load(File.read(path, encoding: 'UTF-8'))
    rescue Psych::Exception => e
      raise ArgumentError, "Config file is not valid YAML: #{path}\n#{e.message}"
      end
    raise ArgumentError, "Config file must be a YAML mapping of keys to values: #{path}" unless config.is_a?(Hash)

    unknown = config.keys.map(&:to_s) - REQUIRED_CONFIG_KEYS - OPTIONAL_CONFIG_KEYS
    raise ArgumentError, "Unknown config key(s): #{unknown.join(', ')}\nValid keys: #{(REQUIRED_CONFIG_KEYS + OPTIONAL_CONFIG_KEYS).join(', ')}" unless unknown.empty?

    missing = REQUIRED_CONFIG_KEYS.select { |key| config[key].to_s.blank? }
    raise ArgumentError, "Missing required config key(s): #{missing.join(', ')}" unless missing.empty?

    (REQUIRED_CONFIG_KEYS + OPTIONAL_CONFIG_KEYS - %w[skip_git_init replacements]).each do |key|
      raise ArgumentError, "Config key '#{key}' must be a string" unless config[key].nil? || config[key].is_a?(String)
    end
    skip_git_init = config.fetch('skip_git_init', false)
    raise ArgumentError, "Config key 'skip_git_init' must be true or false" unless [true, false].include?(skip_git_init)

    {
      source_repository_url: config['source_repository_url'],
      target_project_name: config['target_project_name'],
      target_package_name: config['target_package_name'],
      source_package_name: config['source_package_name'],
      source_application_class_name: config['source_application_class_name'],
      target_application_class_name: config['target_application_class_name'],
      skip_git_init: skip_git_init,
      replacements: validated_replacements(config['replacements'])
    }
  end

  # The `replacements` mapping, or {} when absent. Keys and values must be strings; a key
  # must not be blank (it would match everywhere).
  def validated_replacements(replacements)
    return {} if replacements.nil?
    raise ArgumentError, "Config key 'replacements' must be a mapping of old text to new text" unless replacements.is_a?(Hash)

    replacements.each do |old_text, new_text|
      raise ArgumentError, "Replacement keys and values must be strings (got #{old_text.inspect} => #{new_text.inspect})" unless old_text.is_a?(String) && new_text.is_a?(String)
      raise ArgumentError, 'A replacement key must not be blank' if old_text.blank?
    end
    replacements
  end

  # Raises ArgumentError unless every input is present and well formed.
  def validate_inputs(source_repository_url:, target_project_name:, target_package_name:, source_package_name:, source_application_class_name: nil, target_application_class_name: nil)
    raise ArgumentError, 'Source repository URL is required' if source_repository_url.to_s.blank?
    raise ArgumentError, 'Project name is required' if target_project_name.to_s.blank?
    raise ArgumentError, 'Package name is required' if target_package_name.to_s.blank?
    raise ArgumentError, 'Source package name is required' if source_package_name.to_s.blank?

    unless KEBAB_STRING_PATTERN.match?(target_project_name)
      raise ArgumentError, "Invalid target project name: #{target_project_name}\nProject name must be kebab-case (lowercase letters and hyphens only). " \
                           'Examples: my-project, spring-boot-app'
    end
    unless DOT_STRING_PATTERN.match?(target_package_name)
      raise ArgumentError, "Invalid target package name: #{target_package_name}\nPackage name must be dot notation (lowercase letters and dots only). " \
                           'Examples: my.project, spring.boot.app'
    end
    raise ArgumentError, "Invalid source package name: #{source_package_name}\nIt must be the template's package in dot notation (lowercase letters and dots only)." unless DOT_STRING_PATTERN.match?(source_package_name)

    { 'source application class name' => source_application_class_name, 'application class name' => target_application_class_name }.each do |label, value|
      next if value.nil? || CLASS_NAME_PATTERN.match?(value)

      raise ArgumentError, "Invalid #{label}: #{value}\nIt must be a Java class name (letters, digits and underscores, not starting with a digit)."
    end
  end

  # Expands ${target_project_name}, ${target_package_name} and ${target_application_class_name} in the VALUES of
  # +replacements+. An unknown placeholder is an error (it would otherwise be written literally).
  def expand_replacements(replacements, values)
    replacements.map do |old_text, new_text|
      expanded = new_text.gsub(PLACEHOLDER_PATTERN) do
        name = Regexp.last_match(1)
        raise ArgumentError, "Unknown placeholder '${#{name}}' in replacement for '#{old_text}'. Valid: #{PLACEHOLDER_NAMES.join(', ')}" unless values.key?(name)

        values[name]
      end
      [old_text, expanded]
    end
  end

  # ===========================================================================
  # Main entry point
  # ===========================================================================

  # Clones the template and retargets it to the given project and package.
  #
  # @param source_repository_url [String] repository to clone (anything 'git clone' accepts)
  # @param target_project_name [String] kebab-case name; the folder created under +base_dir+
  # @param target_package_name [String] target Java package (dot-separated lowercase)
  # @param source_package_name [String] the template's Java package, replaced by +target_package_name+
  # @param source_application_class_name [String, nil] the template's main class; nil when it has none
  # @param target_application_class_name [String, nil] target main class; nil derives it from +target_package_name+
  # @param replacements [Hash{String=>String}] extra literal old => new rewrites of file contents;
  #   ${target_project_name}, ${target_package_name} and ${target_application_class_name} expand in the new text
  # @param skip_git_init [Boolean] skip the git initialization step after cloning
  # @param base_dir [String] directory in which the project folder is created (default: current directory)
  # @return [Boolean] true on success; false (after printing the error) on any failure
  def run(source_repository_url:, target_project_name:, target_package_name:, source_package_name:, source_application_class_name: nil, target_application_class_name: nil,
          replacements: {}, skip_git_init: false, base_dir: Dir.pwd)
    Log.section('Template Repository Cloner')
    validate_inputs(source_repository_url: source_repository_url, target_project_name: target_project_name, target_package_name: target_package_name, source_package_name: source_package_name,
                    source_application_class_name: source_application_class_name, target_application_class_name: target_application_class_name)

    repo_folder = File.expand_path(target_project_name, base_dir)
    target_class_name = target_application_class_name || target_package_name.to_class_name
    extra_replacements = expand_replacements(replacements, 'target_project_name' => target_project_name, 'target_package_name' => target_package_name, 'target_application_class_name' => target_class_name)
    source_folder = source_package_name.dot_to_folder
    target_folder = target_package_name.dot_to_folder

    Log.info("Template repo URL: #{source_repository_url}")
    Log.info("Target folder: #{repo_folder}")
    Log.info("Skip git init steps: #{skip_git_init}")
    Log.info("Package name changes: #{source_package_name} --> #{target_package_name}")
    Log.info("Nested folder name changes: #{source_folder} --> #{target_folder}")
    Log.info("Application class changes: #{source_application_class_name} --> #{target_class_name}") if source_application_class_name
    extra_replacements.each { |old_text, new_text| Log.info("Content replacement: '#{old_text}' --> '#{new_text}'") }

    clone_template(source_repository_url, repo_folder, skip_git_init)
    rename_files_and_folders(repo_folder, source_folder: source_folder, target_folder: target_folder,
                                          source_class_name: source_application_class_name, target_class_name: target_class_name)
    content_replacements = [[source_package_name, target_package_name], [source_folder, target_folder]]
    content_replacements << [source_application_class_name, target_class_name] if source_application_class_name
    update_contents(repo_folder, content_replacements + extra_replacements)

    Log.success("Successfully cloned and configured from template for: #{target_project_name}")
    true
  rescue StandardError => e
    Log.error("Failed to create repo from template: #{e.message}")
    Log.debug(e.backtrace.join("\n"))
    false
  end

  # ===========================================================================
  # Template cloning
  # ===========================================================================

  # Shallow-clones the template, then (unless skipped) initializes git when the clone has no .git.
  def clone_template(source_repository_url, repo_folder, skip_git_init)
    Log.section('Cloning Template Repository')
    Log.info("Cloning from: #{source_repository_url} into: '#{repo_folder}'")

    # Array form: no shell, so a URL or folder name can never be interpreted as shell syntax
    run_git!("Failed to clone template repository into: '#{repo_folder}'", *GIT_CLONE_ARGS, source_repository_url, repo_folder)

    Log.section('Initializing Git Repository')
    if skip_git_init
      Log.info('Skipping git initialization (skip_git_init is set)')
    elsif File.exist?(File.join(repo_folder, GIT_DIR_NAME))
      Log.info("Git repository already exists at: '#{repo_folder}'")
    else
      run_git!("Failed to initialize git repository at: '#{repo_folder}'", '-C', repo_folder, 'init')
      create_initial_commit(repo_folder)
    end

    Log.success('Template repository cloned and initialized')
  end

  def create_initial_commit(repo_folder)
    Log.section('Creating initial commit')
    run_git!('Failed to stage files', '-C', repo_folder, 'add', '-A')
    run_git!('Failed to create initial commit', '-C', repo_folder, 'commit', '-m', INITIAL_COMMIT_MESSAGE)
    Log.success('Initial commit created')
  end

  # Runs git without a shell; raises +failure_message+ unless it exits 0.
  def run_git!(failure_message, *git_args)
    raise failure_message unless system('git', *git_args)
  end

  # ===========================================================================
  # File/folder renaming
  # ===========================================================================

  # Moves the template's nested source folder to the target package folder (wherever it
  # occurs, e.g. under both src/main/java and src/test/java), prunes the ancestors that
  # became empty, and renames the application class file (when the template has one).
  def rename_files_and_folders(repo_folder, source_folder:, target_folder:, source_class_name:, target_class_name:)
    Log.section('Performing all file/folder renames')

    rename_source_folders(repo_folder, source_folder, target_folder) unless target_folder == source_folder
    rename_application_class_files(repo_folder, source_class_name, target_class_name) if source_class_name

    Log.success('All file/folder renames completed')
  end

  def rename_source_folders(repo_folder, source_folder, target_folder)
    Dir.glob(File.join(repo_folder, '**', source_folder)).sort.each do |old_folder|
      new_folder = old_folder.delete_suffix(source_folder) + target_folder
      raise "Cannot rename '#{old_folder}': '#{new_folder}' already exists" if File.exist?(new_folder)

      Log.info("Processing: #{old_folder} --> #{new_folder}")
      FileUtils.mkdir_p(File.dirname(new_folder), verbose: Log.debug?)
      FileUtils.mv(old_folder, new_folder, verbose: Log.debug?)
      delete_empty_ancestors(old_folder, repo_folder)
    end
  end

  def rename_application_class_files(repo_folder, source_class_name, target_class_name)
    source_file_name = "#{source_class_name}.java"
    all_files(repo_folder).select { |path| File.file?(path) && File.basename(path) == source_file_name }.each do |old_file|
      new_file = File.join(File.dirname(old_file), "#{target_class_name}.java")
      Log.info("Renaming '#{old_file}' --> '#{new_file}'")
      FileUtils.mv(old_file, new_file, verbose: Log.debug?)
    end
  end

  # Deletes each empty ancestor of +path+, nearest first, stopping at the first non-empty
  # one or at +root+ (which is never deleted).
  def delete_empty_ancestors(path, root)
    parent = File.dirname(path)
    while parent.start_with?("#{root}/") && Dir.empty?(parent)
      Log.info("Deleting: #{parent}")
      Dir.delete(parent)
      parent = File.dirname(parent)
    end
  end

  # ===========================================================================
  # Content updates
  # ===========================================================================

  # Applies +replacements+ (an ordered list of [old_text, new_text] pairs, each literal and on
  # word boundaries) to every text file under +repo_folder+. Files that are not valid UTF-8
  # (binaries) are skipped. Pairs apply in order, so a later one sees the output of an earlier one.
  def update_contents(repo_folder, replacements)
    Log.section('Performing all content changes')

    all_files(repo_folder).each do |path|
      next unless File.file?(path)

      content = File.read(path, encoding: 'UTF-8')
      unless content.valid_encoding?
        Log.debug("Skipping non-UTF-8 file: #{path}")
        next
      end

      updated = replacements.reduce(content) { |text, (old_text, new_text)| text.safe_gsub(old_text, new_text) }
      File.update_if_content_changed(path, updated)
    end

    Log.success('All content changes completed')
  end

  # Every path under +repo_folder+ except those inside an EXCLUDED_DIR_NAMES directory
  # (matched per path segment relative to the repo, so '.gitignore' and '.github' are kept).
  def all_files(repo_folder)
    Find.find(repo_folder).reject do |path|
      (path.delete_prefix(repo_folder).split('/') & EXCLUDED_DIR_NAMES).any?
    end
  end
end

# Run the script if executed directly
if __FILE__ == $PROGRAM_NAME
  begin
    options = TemplateRepositoryCloner.parse_args(ARGV)
  rescue ArgumentError => e
    warn e.message
    exit 1
  end
  exit(TemplateRepositoryCloner.run(**options) ? 0 : 1)
end
