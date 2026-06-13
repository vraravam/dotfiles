# frozen_string_literal: true

require 'rexml/document'
require_relative 'path_utils'

# Plist read/write helpers used by capture-prefs.rb and osx-defaults.rb.
# Wraps REXML (system Ruby, always available) and PlistBuddy
# (/usr/libexec/PlistBuddy, always present on macOS) for key-level operations,
# and the macOS `defaults` and `plutil` command-line tools for export/import.
#
# All plist files handled here are XML plists -- `defaults export` emits binary
# which is immediately converted to XML via `plutil -convert xml1`. XML plists
# are human-readable, fully diffable in git, and round-trip through
# `defaults import` without loss (unlike JSON, which is lossy for <data> and
# <date> types).
module Plist
  extend self

  # macOS system paths
  DEFAULTS_CMD = PathUtils::ROOT.join('usr', 'bin', 'defaults').to_s.freeze

  # ---------------------------------------------------------------------------
  # Defaults export / import
  # ---------------------------------------------------------------------------

  # Exports a defaults domain to +file+ as an XML plist.
  # Returns true on success, false if `defaults export` fails.
  #
  # @param domain [String] Defaults domain, e.g. 'com.apple.finder'.
  # @param file   [String] Destination file path.
  # @return [Boolean]
  def export_domain(domain, file)
    return false unless system(DEFAULTS_CMD, 'export', domain, file)
    # Convert binary plist to XML for human-readable git diffs.
    # JSON is not used: plutil -convert json is lossy for <data> and <date> types.
    system('plutil', '-convert', 'xml1', file)
  end

  # Imports a plist file into a defaults domain.
  # Returns true on success.
  #
  # @param domain [String]
  # @param file   [String] Source XML plist file path.
  # @return [Boolean]
  def import_domain(domain, file)
    system(DEFAULTS_CMD, 'import', domain, file)
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
  # @param domain             [String] The defaults domain being processed.
  # @param plist_file         [String] Path to the XML plist to modify in-place.
  # @param excluded_by_domain [Hash<String,Array<String>>] Map of domain =>
  #   array of glob patterns. Use '*' as the domain key for patterns that apply
  #   to every domain.
  def strip_excluded_keys(domain, plist_file, excluded_by_domain)
    patterns = Array(excluded_by_domain[domain]) + Array(excluded_by_domain['*'])
    plist_file = Pathname.new(plist_file) unless plist_file.is_a?(Pathname)
    return unless plist_file.file?

    begin
      doc = REXML::Document.new(plist_file.read)
    rescue StandardError
      return
    end

    dict = doc.root&.elements&.first
    return unless dict&.name == 'dict'

    children = dict.elements.to_a
    to_remove = []
    children.each_with_index do |el, i|
      next unless el.name == 'key'
      key_name = el.text.to_s
      value_el = children[i + 1]
      matched_by_pattern = !patterns.empty? &&
                           patterns.any? { |pat| File.fnmatch(pat, key_name, File::FNM_CASEFOLD) }
      # Shell version also deleted any key whose value is a <date> plist node --
      # date values are machine-stamped state that must never be exported.
      matched_by_date = value_el&.name == 'date'
      next unless matched_by_pattern || matched_by_date
      to_remove << [el, value_el].compact
    end

    return if to_remove.empty?

    to_remove.each { |pair| pair.each { |el| dict.delete_element(el) } }
    write_plist_doc(doc, plist_file)
  end

  # Returns true if +plist_file+ exists and contains at least one top-level key.
  # Used by capture-prefs.rb to detect empty plists after key stripping so they
  # can be removed before staging.
  #
  # @param plist_file [String]
  # @return [Boolean]
  def has_keys?(plist_file)
    !top_level_keys(plist_file).empty?
  end

  # ---------------------------------------------------------------------------
  # Data-file loaders
  # ---------------------------------------------------------------------------

  # Loads +file+ (capture-prefs-excluded-keys.txt) into a Hash keyed by domain
  # name whose values are Arrays of glob patterns.
  # Format: one entry per line: <domain>|<key-or-glob-pattern>
  # Lines starting with '#' and blank lines are ignored.
  #
  # @param file [String] Path to the excluded-keys file.
  # @return [Hash<String,Array<String>>]
  def load_excluded_keys(file)
    result = Hash.new { |h, k| h[k] = [] }
    each_data_line(file) do |line|
      domain, pattern = line.split('|', 2)
      next if Logging.nil_or_empty?(domain) || Logging.nil_or_empty?(pattern)
      result[domain.strip] << pattern.strip
    end
    result
  end

  # Loads +file+ (capture-prefs-denied-list.txt) into a Set-like Hash for O(1)
  # membership lookups.
  #
  # @param file [String] Path to the denied-list file.
  # @return [Hash<String,true>]
  def load_denied_list(file)
    result = {}
    each_data_line(file) { |line| result[line.strip] = true }
    result
  end

  # Loads +file+ (capture-prefs-allowed-list.txt) into an Array of domain strings.
  #
  # @param file [String]
  # @return [Array<String>]
  def load_allowed_list(file)
    result = []
    each_data_line(file) { |line| result << line.strip unless line.strip.empty? }
    result
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  # Enumerates the top-level keys of an XML plist file using REXML.
  # Returns an empty array if the file is missing, malformed, or has no dict root.
  # Handles keys with spaces correctly -- no null-byte separation needed in Ruby.
  #
  # @param plist_file [String]
  # @return [Array<String>]
  def top_level_keys(plist_file)
    plist_file = Pathname.new(plist_file) unless plist_file.is_a?(Pathname)
    return [] unless plist_file.file?
    doc = REXML::Document.new(plist_file.read)
    dict = doc.root&.elements&.first
    return [] unless dict&.name == 'dict'
    dict.elements.select { |el| el.name == 'key' }.map(&:text)
  rescue StandardError
    []
  end

  # Yields each non-blank, non-comment line from +file+.
  # Lines starting with '#' (optionally preceded by whitespace) are skipped.
  def each_data_line(file)
    file = Pathname.new(file) unless file.is_a?(Pathname)
    return unless file.file?
    file.each_line do |line|
      stripped = line.chomp
      next if stripped.strip.empty?
      next if stripped =~ /\A\s*#/
      yield stripped
    end
  end

  # Writes +doc+ back to +plist_file+ using REXML::Formatters::Pretty.
  # REXML preserves the XML declaration and DOCTYPE from the parsed document.
  # Output formatting may differ slightly from plutil, but `defaults import`
  # parses XML -- exact whitespace does not matter for correctness.
  def write_plist_doc(doc, plist_file)
    plist_file = Pathname.new(plist_file) unless plist_file.is_a?(Pathname)
    formatter = REXML::Formatters::Pretty.new(2)
    formatter.compact = true
    output = String.new
    formatter.write(doc, output)
    plist_file.write(output)
  end
end
