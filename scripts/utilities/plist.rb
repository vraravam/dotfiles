# frozen_string_literal: true

require 'pathname'
require 'rexml/document'
require 'set'

require_relative 'macos'

# Plist read/write helpers for macOS preference management.
# Wraps REXML (system Ruby, always available) for XML plist manipulation,
# and the macOS `defaults` and `plutil` command-line tools for export/import.
#
# All plist files handled here are XML plists -- `defaults export` emits binary
# which is immediately converted to XML via `plutil -convert xml1`. XML plists
# are human-readable, fully diffable in git, and round-trip through
# `defaults import` without loss (unlike JSON, which is lossy for <data> and
# <date> types).
module Plist
  extend self

  # ---------------------------------------------------------------------------
  # Defaults export / import
  # ---------------------------------------------------------------------------

  # Exports a defaults domain to +file+ as an XML plist.
  # Returns true on success, false if `defaults export` fails.
  #
  # @param domain [String] Defaults domain, e.g. 'com.apple.finder'.
  # @param file [String, Pathname] Destination file path.
  # @return [Boolean]
  def export_domain(domain, file)
    file_str = file.is_a?(Pathname) ? file.to_s : file
    return false unless system(MacOS::DEFAULTS_CMD, 'export', domain, file_str, out: File::NULL, err: File::NULL)
    # Convert binary plist to XML for human-readable git diffs.
    # JSON is not used: plutil -convert json is lossy for <data> and <date> types.
    system(MacOS::PLUTIL_CMD, '-convert', 'xml1', file_str, out: File::NULL, err: File::NULL)
  end

  # Imports a plist file into a defaults domain.
  # Returns true on success.
  #
  # @param domain [String]
  # @param file [String, Pathname] Source XML plist file path.
  # @return [Boolean]
  def import_domain(domain, file)
    file_str = file.is_a?(Pathname) ? file.to_s : file
    system(MacOS::DEFAULTS_CMD, 'import', domain, file_str, out: File::NULL, err: File::NULL)
  end

  # ---------------------------------------------------------------------------
  # Excluded-key stripping
  # ---------------------------------------------------------------------------

  # Strips non-portable keys from +plist_file+ in-place. Keys are removed when
  # they match a pattern in +excluded_by_domain+ (for +domain+ or the global
  # '*' entry) OR when their plist value is a <date> element (timestamps are
  # machine-specific state). Uses REXML for both enumeration and deletion so
  # key names containing ':' are handled correctly -- PlistBuddy interprets ':'
  # as a path separator and silently fails to delete such keys.
  #
  # Processes the file even when +patterns+ is empty, because date-typed values
  # must always be stripped regardless of the excluded-keys pattern list.
  #
  # @param domain [String] The defaults domain being processed.
  # @param plist_file [String, Pathname] Path to the XML plist to modify in-place.
  # @param excluded_by_domain [Hash<String,String>] Map of domain => newline-separated
  #   glob patterns. Use '*' as the domain key for patterns that apply to every domain.
  # @return [void]
  def strip_excluded_keys(domain, plist_file, excluded_by_domain)
    plist_file = Pathname.new(plist_file) unless plist_file.is_a?(Pathname)
    return unless plist_file.file?

    # Merge domain-specific patterns with global '*' patterns (applied to every domain)
    combined = []
    combined.concat(excluded_by_domain[domain].split("\n")) if excluded_by_domain.key?(domain)
    combined.concat(excluded_by_domain['*'].split("\n")) if excluded_by_domain.key?('*')

    # Load and parse the plist
    doc = REXML::Document.new(plist_file.read) rescue return
    dict = doc.root&.elements&.first
    return unless dict&.name == 'dict'

    # Delete matched key-value pairs
    # Two independent match conditions, either of which triggers deletion:
    #   1. Key name matches a shell glob pattern (File.fnmatch, '*' matches '/' and ':')
    #   2. The value element immediately following the key is a plist <date> node.
    #      Any top-level key whose value is a plist date is inherently ephemeral
    #      (ISO 8601 timestamp written by the OS/app) -- never a portable user pref.
    #      This catches date-valued keys regardless of their name, providing a
    #      type-based safety net complementary to the name-pattern list.
    modified = false
    loop do
      children = dict.to_a.select { |e| e.is_a?(REXML::Element) }
      hit = children.each_with_index.find do |e, idx|
        next unless e.name == 'key'
        value = children[idx + 1]
        combined.any? { |p| File.fnmatch(p, e.text.to_s) } || (value && value.name == 'date')
      end
      break unless hit

      el, idx = hit
      dict.delete_element(el)
      dict.delete_element(children[idx + 1]) if children[idx + 1]
      modified = true
    end

    return unless modified

    # Write back and re-normalize to Apple XML plist format
    plist_file.write(doc.to_s)
    system(MacOS::PLUTIL_CMD, '-convert', 'xml1', plist_file.to_s, out: File::NULL, err: File::NULL)
  end

  # Returns true if +plist_file+ exists and contains at least one top-level key.
  # Used to detect empty plists after key stripping so they can be removed.
  #
  # @param plist_file [String, Pathname]
  # @return [Boolean]
  def has_keys?(plist_file)
    plist_file = Pathname.new(plist_file) unless plist_file.is_a?(Pathname)
    return false unless plist_file.file?
    plist_file.read.match?(/<key>/)
  end

  # ---------------------------------------------------------------------------
  # Data-file loaders
  # ---------------------------------------------------------------------------

  # Loads +filepath+ (capture-prefs-excluded-keys.txt) into a Hash keyed by domain
  # name whose values are newline-separated glob patterns.
  # Format: one entry per line: <domain>|<key-or-glob-pattern>
  # Lines starting with '#' and blank lines are ignored.
  #
  # @param filepath [Pathname] Path to the excluded-keys file.
  # @return [Hash<String,String>] Domain → newline-separated pattern string
  def load_excluded_keys(filepath)
    result = Hash.new { |h, k| h[k] = [] }
    _each_data_line(filepath) do |line|
      domain, pattern = line.split('|', 2).map(&:strip)
      result[domain] << pattern if domain && pattern
    end
    # Convert arrays to newline-separated strings for strip_excluded_keys
    result.transform_values! { |patterns| patterns.join("\n") }
    result
  end

  # Loads +filepath+ (capture-prefs-denied-list.txt) into a Set for O(1)
  # membership lookups.
  #
  # @param filepath [Pathname] Path to the denied-list file.
  # @return [Set<String>]
  def load_denied_list(filepath)
    result = Set.new
    _each_data_line(filepath) { |line| result.add(line.strip) }
    result
  end

  # Loads +filepath+ (capture-prefs-allowed-list.txt) into a Set of domain strings,
  # filtering out entries that appear in +denied+.
  #
  # @param filepath [Pathname]
  # @param denied [Set<String>] Set of denied domain names to filter out
  # @return [Set<String>]
  def load_domains_list(filepath, denied)
    result = Set.new
    _each_data_line(filepath) do |line|
      domain = line.strip
      result.add(domain) unless denied.include?(domain)
    end
    result
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  # Enumerates the non-blank, non-comment lines from +filepath+.
  # Lines starting with '#' (optionally preceded by whitespace) are skipped.
  def _each_data_line(filepath)
    filepath = Pathname.new(filepath) unless filepath.is_a?(Pathname)
    return unless filepath.file?
    filepath.each_line do |line|
      stripped = line.chomp
      next if stripped.strip.empty?
      next if stripped =~ /\A\s*#/
      yield stripped
    end
  end
end
