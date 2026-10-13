#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'pathname'
require 'set'

require_relative 'core'
require_relative 'macos'

# Plist read/write helpers for macOS preference management.
# Wraps the macOS `defaults` and `plutil` command-line tools for export/import, and strips
# non-portable keys with a text-level pass over Apple's tab-indented XML layout. REXML
# (system Ruby, always available) is only loaded for plists that do not use that layout.
#
# All plist files handled here are XML plists -- `defaults export <domain> -` emits XML
# directly. XML plists are human-readable, fully diffable in git, and round-trip through
# `defaults import` without loss (unlike JSON, which is lossy for <data> and <date> types).
module Plist
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # ---------------------------------------------------------------------------
  # Defaults export / import
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Returns true if +plist_file+ exists and contains at least one top-level key.
  # Used to detect empty plists after key stripping so they can be removed.
  #
  # @param plist_file [String, Pathname]
  # @return [Boolean]
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def keys?(plist_file)
    plist_file = Pathname(plist_file)
    return false unless plist_file.file?

    # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII"
    # errors when reading plist XML files in cron/background environments.
    plist_file.read(encoding: 'UTF-8').match?(/<key>/)
  end

  # Loads +filepath+ (capture-prefs-excluded-keys.txt) into a Hash keyed by domain
  # name whose values are frozen arrays of glob patterns.
  # Format: one entry per line: <domain>|<key-or-glob-pattern>
  # Lines starting with '#' and blank lines are ignored.
  #
  # @param filepath [Pathname] Path to the excluded-keys file.
  # @return [Hash<String,Array<String>>] Domain -> glob patterns
  # :reek:FeatureEnvy -- Accumulates patterns from file into result hash
  def load_excluded_keys(filepath)
    result = Hash.new { |h, k| h[k] = [] }
    _each_data_line(filepath) do |line|
      domain, pattern = line.split('|', 2).map(&:strip)
      result[domain] << pattern if domain && pattern
    end
    result.default_proc = nil
    result.each_value(&:freeze)
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
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Exports a defaults domain to +file+ as an XML plist.
  # Returns true on success, false if `defaults export` fails.
  #
  # `defaults export <domain> -` writes XML to stdout even when the domain is stored as a
  # binary plist, so no separate `plutil -convert xml1` pass is needed (one fork per domain
  # instead of two). JSON is not used: it is lossy for <data> and <date> types.
  #
  # @param domain [String] Defaults domain, e.g. 'com.apple.finder'.
  # @param file [String, Pathname] Destination file path.
  # @return [Boolean]
  def export_domain(domain, file)
    return false if nil_or_empty?(domain)

    file_str = file.to_s
    return true if CommandUtils.run_silent(MacOS::DEFAULTS_CMD, 'export', domain, '-', out: file_str)

    # The shell redirection created (and emptied) the file before the command failed.
    File.delete(file_str) if File.exist?(file_str)
    false
  end

  # Imports XML plist text into a defaults domain via stdin.
  # Returns true on success.
  #
  # @param domain [String]
  # @param xml [String] XML plist text.
  # @return [Boolean]
  def import_xml(domain, xml)
    return false if nil_or_empty?(domain)

    _stdout, _stderr, status = Open3.capture3(MacOS::DEFAULTS_CMD, 'import', domain, '-', stdin_data: xml)
    status.success?
  end

  # Strips non-portable keys from +plist_file+ in-place; see #stripped_xml for the rules.
  # The file is only rewritten when something was removed.
  #
  # @param domain [String] The defaults domain being processed.
  # @param plist_file [String, Pathname] Path to the XML plist to modify in-place.
  # @param excluded_by_domain [Hash<String,Array<String>>] Map of domain => glob patterns
  #   (see #load_excluded_keys). Use '*' as the domain key for patterns that apply to every domain.
  # @return [void]
  def strip_excluded_keys(domain, plist_file, excluded_by_domain)
    plist_file = Pathname(plist_file)
    return unless plist_file.file?

    # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
    xml = plist_file.read(encoding: 'UTF-8')
    stripped = stripped_xml(domain, xml, excluded_by_domain)
    plist_file.write(stripped) unless stripped.equal?(xml)
  end

  # Returns +xml+ without its non-portable top-level keys. Keys are removed when they
  # match a pattern in +excluded_by_domain+ (for +domain+ or the global '*' entry) OR when
  # their plist value is a <date> element (timestamps are machine-specific state). Key
  # names containing ':' are handled correctly -- PlistBuddy interprets ':' as a path
  # separator and silently fails to delete such keys.
  #
  # Date-typed values are stripped even when there are no patterns. Returns the very same
  # String object when nothing is removed (callers can test with #equal?) and the input
  # when it is not parseable.
  #
  # Two independent match conditions, either of which triggers deletion:
  #   1. Key name matches a shell glob pattern (File.fnmatch, '*' matches '/' and ':')
  #   2. The value element immediately following the key is a plist <date> node.
  #      Any top-level key whose value is a plist date is inherently ephemeral
  #      (ISO 8601 timestamp written by the OS/app) -- never a portable user pref.
  #      This catches date-valued keys regardless of their name, providing a
  #      type-based safety net complementary to the name-pattern list.
  #
  # Apple's tab-indented layout (`defaults export`, `plutil`) puts every top-level key at
  # `\t<key>NAME</key>`, so a regexp scan finds the candidates without a parse (most
  # plists have none). Removal is then done on the text. Any other layout is parsed with
  # REXML, which is only loaded in that case.
  #
  # @param domain [String] The defaults domain being processed.
  # @param xml [String] XML plist text.
  # @param excluded_by_domain [Hash<String,Array<String>>]
  # @return [String]
  def stripped_xml(domain, xml, excluded_by_domain)
    patterns = excluded_by_domain.fetch(domain, EMPTY_PATTERNS) + excluded_by_domain.fetch('*', EMPTY_PATTERNS)

    return _strip_with_rexml(xml, patterns) unless _apple_layout?(xml)

    return xml unless _top_level_match?(xml, patterns)

    _strip_text(xml, patterns) || _strip_with_rexml(xml, patterns)
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  private

  # Shared empty list so lookups for unlisted domains allocate nothing.
  EMPTY_PATTERNS = [].freeze
  private_constant :EMPTY_PATTERNS

  # A depth-1 key line in Apple's layout (exactly one leading tab).
  TOP_KEY_LINE = %r{\A\t<key>(.*)</key>\n?\z}.freeze
  # A depth-1 value that opens an element without closing it on the same line.
  OPEN_VALUE_LINE = /\A\t<(\w+)>/.freeze
  # Entity references a key name can contain in an XML plist.
  KEY_ENTITIES = { '&amp;' => '&', '&lt;' => '<', '&gt;' => '>', '&quot;' => '"', '&apos;' => "'" }.freeze
  private_constant :TOP_KEY_LINE, :OPEN_VALUE_LINE, :KEY_ENTITIES

  # True when every key sits on a tab-indented line (or the plist has no keys), the layout
  # the text-level scan relies on. Numeric character references in a key name also send
  # the plist to REXML, which resolves them.
  def _apple_layout?(xml)
    return true unless xml.include?('<key>')
    return false if xml.match?(/^ +<key>/) || xml.match?(/<key>[^<]*&#/)

    xml.include?("\n\t<key>")
  end

  # True when a top-level key matches +patterns+ or has a <date> value (see #stripped_xml).
  def _top_level_match?(xml, patterns)
    return true if xml.match?(/^\t<date>/)
    return false if patterns.empty?

    xml.scan(%r{^\t<key>(.*)</key>$}).any? { |(name)| _excluded_key?(patterns, name) }
  end

  def _excluded_key?(patterns, escaped_name)
    name = escaped_name.include?('&') ? escaped_name.gsub(/&(?:amp|lt|gt|quot|apos);/, KEY_ENTITIES) : escaped_name
    patterns.any? { |pattern| File.fnmatch(pattern, name) }
  end

  # Removes the matching top-level key/value pairs from the text of a tab-indented plist.
  # Returns nil when the text does not follow the expected structure, so the caller can
  # fall back to a real parse.
  def _strip_text(xml, patterns)
    lines = xml.lines
    root = lines.index("<dict>\n")
    return nil unless root

    kept = lines[0..root]
    removed = false
    idx = root + 1
    while idx < lines.size
      line = lines[idx]
      break if line == "</dict>\n"

      match = TOP_KEY_LINE.match(line)
      return nil unless match

      value_end = _value_end(lines, idx + 1)
      return nil unless value_end

      remove = lines[idx + 1].start_with?("\t<date>") || _excluded_key?(patterns, match[1])
      if remove
        removed = true
      else
        kept.concat(lines[idx...value_end])
      end
      idx = value_end
    end
    return nil if idx >= lines.size
    return xml unless removed

    rest = lines[idx..-1]
    # plutil writes an empty root dict as <dict/>; match it so the output is identical.
    if kept.size == root + 1 && rest.first == "</dict>\n"
      kept[root] = "<dict/>\n"
      rest = rest.drop(1)
    end
    (kept + rest).join
  end

  # Index just past the depth-1 value element starting at lines[start], or nil if it
  # cannot be delimited. Text content is entity-escaped, so a line that is exactly the
  # closing tag at one tab of indentation can only be the real closing tag.
  def _value_end(lines, start)
    line = lines[start]
    return nil unless line
    return start + 1 if line.match?(%r{\A\t<\w+/>\n?\z}) || line.match?(%r{\A\t<(\w+)>.*</\1>\n?\z})

    open = OPEN_VALUE_LINE.match(line)
    return nil unless open

    tag = open[1]
    closing = %w[dict array].include?(tag) ? "\t</#{tag}>\n" : nil
    ((start + 1)...lines.size).each do |idx|
      return idx + 1 if closing ? lines[idx] == closing : lines[idx].match?(%r{</#{tag}>\n?\z})
    end
    nil
  end

  # Fallback for plists that are not in Apple's tab-indented layout: parse with REXML,
  # delete every matching key and its value in one pass, and let plutil re-normalize the
  # result to Apple XML. Loaded lazily so the common path does not pay for the require.
  def _strip_with_rexml(xml, patterns)
    require 'rexml/document'

    doc = _parse_rexml(xml)
    return xml if doc.nil?

    dict = doc.root&.elements&.first
    return xml unless dict&.name == 'dict'

    children = dict.elements.to_a
    doomed = []
    children.each_with_index do |element, idx|
      next unless element.name == 'key'

      value = children[idx + 1]
      doomed << element << value if patterns.any? { |pattern| File.fnmatch(pattern, element.text.to_s) } || value&.name == 'date'
    end
    return xml if doomed.empty?

    doomed.each { |element| dict.delete_element(element) }
    _normalize_xml(doc.to_s)
  end

  # Parses +xml+ with REXML; nil when it is malformed (the caller then leaves it untouched).
  def _parse_rexml(xml)
    REXML::Document.new(xml)
  rescue StandardError
    nil
  end

  # Re-normalizes +xml+ to Apple's XML plist layout via `plutil`; returns +xml+ unchanged
  # if plutil rejects it.
  def _normalize_xml(xml)
    normalized, _stderr, status = Open3.capture3(MacOS::PLUTIL_CMD, '-convert', 'xml1', '-o', '-', '-', stdin_data: xml)
    status.success? ? normalized : xml
  end

  # Enumerates the non-blank, non-comment lines from +filepath+.
  # Lines starting with '#' (optionally preceded by whitespace) are skipped.
  #
  # @param filepath [String, Pathname] Path to the file to enumerate.
  # @yield [line] Each stripped, non-comment, non-blank line.
  # @yieldparam line [String]
  # @return [void]
  # :reek:FeatureEnvy -- Validates file and iterates over lines with filtering
  def _each_data_line(filepath)
    filepath = Pathname(filepath)
    return unless filepath.file?

    # Use Core.each_line_utf8 to avoid "invalid byte sequence in US-ASCII" errors
    # when reading UTF-8 files in cron/background environments without UTF-8 locale.
    Core.each_line_utf8(filepath) do |line|
      stripped = line.chomp
      next if nil_or_empty?(stripped.strip)
      next if stripped =~ /\A\s*#/

      yield stripped
    end
  end
end
