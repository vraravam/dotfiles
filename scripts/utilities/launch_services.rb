#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'pathname'
require 'tempfile'

require_relative 'command_utils'
require_relative 'core'
require_relative 'macos'

# Export/import of the macOS default-application handlers (default browser, mail client,
# URL scheme and file type handlers) kept in the LaunchServices 'secure' preferences.
#
# These are not an ordinary defaults domain: the plist lives in a sub-folder of
# ~/Library/Preferences (so the domain name contains a '/', which cannot be used as an
# exported file name by capture-prefs.rb's per-domain loop), and its single 'LSHandlers' key
# is an array of dicts where each entry is identified by its content type or URL scheme.
# Importing therefore merges entry-by-entry rather than replacing the whole domain, so
# handlers registered on the target machine for unrelated types/schemes are left alone.
#
# Writing the preference directly (instead of NSWorkspace.setDefaultApplication) avoids the
# interactive "Do you want to change your default browser?" confirmation, which cannot be
# answered from a non-interactive install.
module LaunchServices
  extend self

  # Domain accepted by 'defaults' (a path relative to ~/Library/Preferences, no extension).
  DOMAIN = 'com.apple.LaunchServices/com.apple.launchservices.secure'

  HANDLERS_KEY = 'LSHandlers'

  # Per-entry keys that identify what the handler is for (an entry has exactly one of these).
  IDENTITY_KEYS = %w[LSHandlerContentType LSHandlerContentTag LSHandlerURLScheme].freeze

  # Machine-specific timestamp rewritten whenever an entry changes -- dropped on export so that
  # re-exporting an unchanged setup produces no git diff.
  VOLATILE_KEYS = %w[LSHandlerModificationDate].freeze

  # Writes the current handlers to +file+ as an XML plist (volatile keys removed).
  #
  # @param file [String, Pathname] Destination plist path.
  # @return [Boolean] true on success
  def export_handlers(file)
    handlers = _current_handlers
    return false if handlers.nil?

    portable = handlers.map { |entry| entry.reject { |key, _| VOLATILE_KEYS.include?(key) } }
    _write_xml_plist({ HANDLERS_KEY => portable }, file)
  end

  # Merges the handlers in +file+ into the live preference and asks launchservices to reload.
  #
  # @param file [String, Pathname] Plist previously written by export_handlers.
  # @return [Boolean] true on success
  def import_handlers(file)
    wanted = _read_handlers(file)
    return false if wanted.nil?

    current = _current_handlers
    return false if current.nil?

    merged = merge_handlers(current, wanted)
    Tempfile.create(['launch-services-', '.plist']) do |tmp|
      return false unless _write_xml_plist({ HANDLERS_KEY => merged }, tmp.path)
      return false unless CommandUtils.run_silent(MacOS::DEFAULTS_CMD, 'import', DOMAIN, tmp.path)
    end

    # lsd caches the handler table; it relaunches on demand after being killed.
    CommandUtils.run_silent('killall', 'lsd')
    true
  end

  # Returns +current+ with every entry whose identity (content type / tag / URL scheme) is
  # also present in +wanted+ replaced by the +wanted+ entry; entries only in +wanted+ are
  # appended and entries only in +current+ are kept as-is.
  #
  # @param current [Array<Hash>] Handlers already registered on this machine.
  # @param wanted [Array<Hash>] Handlers to apply.
  # @return [Array<Hash>]
  # :reek:UtilityFunction -- Pure function over its arguments
  def merge_handlers(current, wanted)
    wanted_ids = wanted.map { |entry| _identity(entry) }
    kept = current.reject { |entry| wanted_ids.include?(_identity(entry)) }
    kept + wanted
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  private

  # Identity of an entry: [key, value] of whichever IDENTITY_KEYS it carries (lowercased value,
  # since LaunchServices matches schemes and content types case-insensitively).
  def _identity(entry)
    key = IDENTITY_KEYS.find { |k| entry.key?(k) }
    key ? [key, entry[key].to_s.downcase] : [:entry, entry.hash]
  end

  # Handlers currently registered, or nil when the domain cannot be read.
  # A machine that has never changed a default has no such plist -- treated as empty.
  def _current_handlers
    Tempfile.create(['launch-services-current-', '.plist']) do |tmp|
      return [] unless CommandUtils.run_silent(MacOS::DEFAULTS_CMD, 'export', DOMAIN, tmp.path)

      _read_handlers(tmp.path)
    end
  end

  def _read_handlers(file)
    json = CommandUtils.query(MacOS::PLUTIL_CMD, '-convert', 'json', '-o', '-', file.to_s)
    return nil if json.empty?

    parsed = JSON.parse(json)
    parsed.is_a?(Hash) ? Array(parsed[HANDLERS_KEY]) : nil
  rescue JSON::ParserError
    nil
  end

  # JSON is safe here: handler entries only hold strings, integers and nested dicts of strings
  # (plutil's JSON conversion is lossy only for <data>/<date>, which they never contain).
  def _write_xml_plist(hash, file)
    Tempfile.create(['launch-services-', '.json']) do |tmp|
      tmp.write(JSON.generate(hash))
      tmp.flush
      CommandUtils.run_silent(MacOS::PLUTIL_CMD, '-convert', 'xml1', '-o', file.to_s, tmp.path)
    end
  end
end
