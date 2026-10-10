#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'core'
require_relative 'env_vars'
require_relative 'logging_sinks'
require_relative 'logging_state'
require_relative 'logging_summary'
require_relative 'string_ext'

# Logging helpers that replicate the shell functions defined in .shellrc
# (success/info/warn/debug/error, section_header, print_script_start,
# print_script_duration, print_script_summary, record_warning, record_error).
#
# Structured logging support:
#   Set LOG_FORMAT=json to enable JSON-formatted log output
#   Set LOG_FILE=/path/to/file to write logs to file (with rotation)
#   Default: human-readable console output
#
# Color rendering is handled by the String extensions in string.rb and is
# automatically suppressed when stdout is not a TTY.
#
# Usage:
#   require 'logging'
#   include Logging
#
# Or call methods directly on the module:
#   Logging.info('hello')
#
# Layout: this file holds the console emitters, section headers, script lifecycle
# (run_script, depth tracking) and indentation. The other concerns are mixed in from
# logging_summary.rb (timing, deferred warnings/errors, summaries), logging_sinks.rb
# (LOG_LEVEL filtering, LOG_FILE sink) and logging_state.rb (the shared run state).
module Logging
  # The mixins must be included BEFORE `extend self`: `extend self` snapshots Logging's
  # ancestors at that moment, so modules included afterwards would be missing from the
  # module-method (`Logging.info`) side.
  include Core  # For instance methods (in blocks)
  include Sinks
  include Summary

  # Make the module usable both as `include Logging` and as `Logging.info(...)`.
  extend self
  extend Core   # For module methods

  # Section header styles by level. Each level has a distinct visual style
  # (character, glyph, color) to create a clear visual hierarchy.
  #
  # Level 0: Top-level sections (main workflow steps)
  # Level 1: Sub-sections within a top-level section
  # Level 2+: Further nesting (extensible)
  SECTION_STYLES = [
    { char: '=', glyph: '⏳', color: :light_blue },  # Level 0: Top-level sections (depth 1)
    { char: '-', glyph: '🔷', color: :cyan },        # Level 1: Sub-sections (depth 2)
    { char: '·', glyph: '▸', color: :yellow },       # Level 2: Collection items (depth 3)
    { char: '·', glyph: '▫', color: :purple },       # Level 3: Operations within items (depth 4)
    { char: '·', glyph: '▪', color: :dark_gray },    # Level 4: Deep nesting (depth 5+)
  ].freeze

  # Log levels in priority order (lowest to highest severity).

  # ---------------------------------------------------------------------------
  # Semantic log-level helpers
  # These mirror success/info/warn/debug/error from .shellrc.
  #
  # All logging functions automatically prepend indentation based on
  # _DOTFILES_SCRIPT_DEPTH. Multi-line messages have each line indented.
  #
  # Log level filtering:
  #   Set LOG_LEVEL=warn to show only warn/error/user_action messages
  #   Set LOG_LEVEL=info to show info and above (default)
  #   Set LOG_LEVEL=debug to show all messages
  #
  # These methods do NOT apply tilde substitution -- color methods (.yellow,
  # .cyan, etc.) do so automatically on their arguments. Logging methods are
  # pure formatters: prefix + message. Bare puts/print call sites that display
  # paths without a color method must call replace_home_path_with_tilde explicitly.
  #
  # The shell's `error` calls `osascript` for a macOS notification; that
  # behaviour is omitted here since it is inappropriate for library code.
  # ---------------------------------------------------------------------------

  # Prints a success message (an operation completed successfully).
  # Suppressed in direnv subshells to reduce noise. Use 'error' for messages
  # that must always be visible regardless of context.
  # Filtered by LOG_LEVEL environment variable.
  #
  # @param message [String] The message to log
  # @return [void]
  def success(message)
    _emit_log(:success, message, "✅ #{'**SUCCESS**'.green}")
  end

  # Prints an informational message (normal progress, idempotency guards, etc.).
  # Suppressed in direnv subshells to reduce noise. Use 'error' for messages
  # that must always be visible regardless of context.
  # Filtered by LOG_LEVEL environment variable.
  #
  # @param message [String] The message to log
  # @return [void]
  def info(message)
    _emit_log(:info, message, "ℹ️ #{'**INFO**'.cyan}")
  end

  # Prints a warning message (non-fatal operation failures, argument parse errors).
  # Suppressed in direnv subshells. Use 'error' for messages that must always
  # be visible.
  # Filtered by LOG_LEVEL environment variable.
  #
  # @param message [String] The warning message to log
  # @return [void]
  def warn(message)
    _emit_log(:warn, message, "⚠️ #{'**WARN**'.light_red}")
  end

  # Prints a debug message (only visible when DEBUG=true or LOG_LEVEL=debug).
  # Hidden by default. Use for expected-absent tools or optional steps that
  # are silently skipped. Suppressed in direnv subshells.
  # Filtered by LOG_LEVEL environment variable.
  #
  # @param message [String] The debug message to log
  # @return [void]
  def debug(message)
    return unless _should_log?(:debug)
    # Hidden by default; only visible when DEBUG env var is set or LOG_LEVEL=debug.
    # Also suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return unless EnvVars.debug?
    return if EnvVars.suppress_log?

    msg = message.to_s.replace_home_path_with_tilde
    msg.each_line { |line| emit("⚙️ #{'**DEBUG**'.light_purple} #{line.chomp}", level: 0) }
  end

  # Prints a message prompting the user to perform a manual step (e.g. restart
  # an app, run a command, open a URL). Distinct from warn (unexpected problem)
  # and info (purely informational). Suppressed in direnv subshells -- direnv
  # runs headlessly and cannot act on prompts. Mirrors user_action() in .shellrc.
  # Filtered by LOG_LEVEL environment variable.
  #
  # @param message [String] The action message to log
  # @return [void]
  def user_action(message)
    _emit_log(:user_action, message, "➡️ #{'**ACTION**'.yellow}")
  end

  # Prints the error message and raises a +RuntimeError+ with that message,
  # terminating the current execution path unless rescued by the caller.
  # error() always prints regardless of context -- critical failures must be visible.
  # Never filtered by LOG_LEVEL (errors always shown).
  #
  # @param message [String] The error message to log
  # @raise [RuntimeError]
  def error(message)
    msg = message.to_s.replace_home_path_with_tilde
    msg.each_line { |line| emit("❌ #{'**ERROR**'.red} #{line.chomp} 🤓", level: 0) }
    raise msg
  end

  # Formats an array as a bulleted, indented list with color and quotes applied to each item.
  # Each item is indented by current depth + N levels, prefixed with '- ', wrapped in
  # single quotes, and has color applied. Items are joined with newlines.
  #
  # The indent is depth-aware (current script depth) + level additional spaces, so list
  # items can be positioned at any desired nesting level relative to their context.
  #
  # @param arr [Array] The array to format.
  # @param color [Symbol] Color method to apply (:red, :cyan, :yellow, etc.).
  # @param level [Integer] Subordinate nesting level (default: 1 for typical label + list pattern).
  # @return [String] The formatted list string, or empty string if array is empty.
  #
  # Example:
  #   # At depth 1 (outermost script):
  #   join_array(['file1.rb', 'file2.rb'], :red)
  #   # => "  - 'file1.rb'\n  - 'file2.rb'" (2 spaces + bullet, level defaults to 1)
  #
  #   join_array(['file1.rb', 'file2.rb'], :red, level: 2)
  #   # => "    - 'file1.rb'\n    - 'file2.rb'" (4 spaces + bullet)
  #
  #   # At depth 2 (nested script):
  #   join_array(['file1.rb', 'file2.rb'], :red)
  #   # => "    - 'file1.rb'\n    - 'file2.rb'" (4 spaces + bullet)
  def join_array(arr, color, level: 1)
    return '' if nil_or_empty?(arr)

    # Compute indentation: base depth + level subordination.
    # Base depth is captured at construction time, ensuring the list indents
    # correctly even if parent message is printed at a different depth later
    # (e.g., deferred warnings). All lines in multi-line messages must have their
    # own indentation baked in since logging functions only indent the first line.
    indent = _subordinate_indent(level)
    arr.map { |item| "#{indent}- '#{item.to_s.send(color)}'" }.join("\n")
  end

  # Prints a line with depth-aware indentation + N levels of additional nesting.
  # Each level adds 2 spaces. Use this for content that should be indented relative
  # to a parent message (stats, timing info, etc.) but not bulleted like join_array items.
  #
  # Named 'emit' instead of 'puts' to avoid confusion with standard puts.
  #
  # Indentation formula: (depth - 1 + level) * 2 spaces
  # - Outermost script (depth 1) with level 0 -> 0 spaces
  # - Outermost script (depth 1) with level 1 -> 2 spaces
  # - Nested script (depth 2) with level 0 -> 2 spaces
  # - Nested script (depth 2) with level 1 -> 4 spaces
  #
  # @param message [String] The message to print
  # @param level [Integer] Number of subordinate nesting levels (required, no default)
  # @return [void]
  #
  # Example:
  #   # At depth 1 (outermost):
  #   Logging.emit("Total: 10", level: 0)
  #   # => "Total: 10" (0 spaces)
  #
  #   Logging.emit("Total: 10", level: 1)
  #   # => "  Total: 10" (2 spaces)
  #
  #   # At depth 2 (nested):
  #   Logging.emit("Total: 10", level: 0)
  #   # => "  Total: 10" (2 spaces)
  #
  #   Logging.emit("Details:", level: 1)
  #   # => "    Details:" (4 spaces)
  def emit(message, level:)
    # Console output (with colors/indentation)
    puts "#{_subordinate_indent(level)}#{message}"

    # Skip the log-level regex detection + ANSI-stripping work below when file logging
    # is disabled (the common case -- LOG_FILE is opt-in). This is a cheap ENV lookup;
    # _write_to_log_file would discard the expensive work via its own early return, but
    # only after that work has already been done on every single log call.
    return unless EnvVars.log_file

    # File output (stripped of ANSI, plain text or JSON based on LOG_FORMAT); the level is
    # recovered from the severity marker in the console prefix.
    log_level = _log_level_for(message)

    # Strip ANSI codes for file output
    plain_message = _strip_ansi(message)
    _write_to_log_file(log_level, plain_message)
  end

  # ---------------------------------------------------------------------------
  # Section / script timing helpers
  # These mirror section_header, print_script_start, and print_script_duration
  # from .shellrc.
  # ---------------------------------------------------------------------------

  # Strips ANSI escape codes from a string to get visual length.
  # Used by section_header to calculate padding correctly when header contains colors.
  #
  # @param str [String] String potentially containing ANSI escape codes
  # @return [String] String with all ANSI codes removed
  # :reek:UtilityFunction -- Stateless string transformation utility
  def _strip_ansi(str)
    # ANSI escape sequences match pattern: ESC [ ... m
    # This regex removes all such sequences to get the visual text
    str.gsub(/\e\[[0-9;]*m/, '')
  end

  private_class_method :_strip_ansi

  # Prints a section header with visual hierarchy based on current script depth.
  # Level is automatically derived from script depth (depth 1 = level 0, depth 2 = level 1, etc.).
  # Only level 0 (outermost script) updates the current section for error attribution.
  # Output matches the shell version in .shellrc (section_header function).
  #
  # Visual styles:
  # rubocop:disable Style/AsciiComments
  # - Level 0 (depth 1): = ⏳ light_blue (top-level sections)
  # - Level 1 (depth 2): - 🔷 cyan (sub-sections)
  # - Level 2+ (depth 3+): · ▸ yellow (nested sections)
  # rubocop:enable Style/AsciiComments
  #
  # @param header [String] The header text
  def section_header(header)
    level = [EnvVars.script_depth - 1, 0].max # depth 1 -> level 0, depth 2 -> level 1, etc.

    # Auto-set current_section if nil/empty, at initial '(init)' value, OR not manually set.
    # This provides progressively more specific context as execution descends through nested
    # operations. Manual assignments (via `current_section=`) set a flag that prevents
    # auto-updates, allowing concise error attribution while displaying descriptive headers.
    unless state.current_section_manual
      # Direct assignment (not via setter) to avoid setting the manual flag
      state.current_section = _strip_ansi(header.to_s)
    end

    # Get style for this level (fallback to highest defined level if out of bounds)
    style = SECTION_STYLES[level] || SECTION_STYLES.last

    # Extract style components
    char = style[:char]
    glyph = style[:glyph]
    color = style[:color]

    # Section headers use only base depth indentation (no subordinate levels).
    # The level variable selects the visual style (char/glyph/color), not indentation.
    header_str = header.replace_home_path_with_tilde
    indent_length = _log_indent.length

    # Strip ANSI codes to get visual length (header may contain color codes from caller)
    header_visual = _strip_ansi(header_str)
    header_length = header_visual.length

    # Left-aligned headers: text starts at fixed position for vertical scanability
    # Left padding: 5 chars min (prevents touching left edge)
    # Right padding: fills remaining width minus 10 chars (prevents touching right edge)
    left_padding_length = [5 - indent_length, 1].max
    right_padding_length = [terminal_width - indent_length - left_padding_length - 3 - header_length - 10, 1].max
    left_pad = _repeat_char(char, left_padding_length).send(color)
    right_pad = _repeat_char(char, right_padding_length).send(color)

    # Emit the formatted header at level 0 (base indent only)
    emit("#{left_pad} #{glyph} #{header_str} #{right_pad}", level: 0)
  end

  # Wraps the standard script lifecycle: increment depth, print start banner,
  # execute block, print summary. Use this instead of manually calling
  # increment_script_depth + print_script_start + print_script_summary.
  #
  # When called from a nested context (script_depth >= 1), skips depth increment
  # and banner output -- the module runs at the current depth as if called directly.
  # This allows shell functions to call Ruby scripts without double-nesting.
  #
  # Ensures print_script_summary is always called (even on error) via ensure block.
  # The at_exit hook registered by increment_script_depth ensures depth is
  # decremented on both clean and error exits.
  #
  # Auto-detects script name from caller's filename (File.basename(caller, '.rb')).
  # Performance: negligible overhead (~1 microsecond from caller_locations(1,1) per script).
  #
  # @param script_name [String, nil] Optional override for script name (auto-detected if omitted)
  # @param message [String, nil] Optional message to print before summary
  # @yield [start_time] Block containing the script's main logic; receives Unix epoch start time (or nil if nested)
  # @return [void]
  #
  # @example CLI entry point script (script_name auto-detected from filename)
  #   if __FILE__ == $PROGRAM_NAME
  #     include Logging
  #     # ... option parsing ...
  #     Logging.run_script do
  #       success = MyModule.run(param: value)
  #       exit(success ? 0 : 1)
  #     end
  #   end
  #
  # @example Utility module method (script_name auto-detected from caller)
  #   def install_mise_versions(shared_dirs: nil, first_install: false)
  #     Logging.run_script do
  #       # ... implementation ...
  #     end
  #   end
  #
  # @example Override script name explicitly (rare, for custom naming)
  #   Logging.run_script('custom-name') do
  #     # ... main logic ...
  #   end
  #
  # @example With custom summary message
  #   Logging.run_script(nil, 'Finished cleaning up browser profiles') do
  #     # ... main logic ...
  #   end
  def run_script(script_name = nil, message = nil)
    # Save the previous script name so we can restore it on exit.
    # This prevents nested run_script calls from leaking their script name
    # to the outer script's print_script_summary call.
    previous_script_name = state.script_name

    # Auto-detect script name from caller if not provided.
    # caller_locations(1, 1) fetches exactly one frame (the immediate caller).
    # Performance: negligible overhead (~1 microsecond), called once per script execution.
    if nil_or_empty?(script_name)
      caller_path = caller_locations(1, 1)&.first&.path
      script_name = caller_path ? File.basename(caller_path, '.rb') : 'unknown'
    end

    self.script_name = script_name
    # Initialize current_section to '(init)' for consistency with shell scripts.
    # Use direct assignment (not setter) to avoid setting the manual flag.
    state.current_section = '(init)'
    state.current_section_manual = false

    # When already nested (called from shell function at depth >= 1), increment
    # depth for the module execution to ensure outermost_script? returns false,
    # then return early to skip banners and summary. The increment ensures that
    # print_results_summary and other checks correctly identify this as nested.
    if EnvVars.script_depth >= 1
      increment_script_depth
      begin
        yield nil
      ensure
        decrement_script_depth
        # Restore the previous script name (nested call cleanup)
        state.script_name = previous_script_name
      end
      return
    end

    # Standalone mode (depth 0): increment depth and print banners
    increment_script_depth
    start_time = print_script_start

    yield start_time
  ensure
    # Only print summary in standalone mode (depth <= 1).
    # The early return above ensures this only runs for standalone calls.
    print_script_summary(start_time, message) if start_time
    # Restore the previous script name (standalone call cleanup)
    state.script_name = previous_script_name
  end

  # ---------------------------------------------------------------------------
  # Script depth tracking -- public query method
  # ---------------------------------------------------------------------------

  # Returns true when this is the outermost script in a nested call chain.
  # Mirrors is_outermost_script in .shellrc. _DOTFILES_SCRIPT_DEPTH is exported
  # and incremented by each script's main() via run_script; subprocess increments
  # do not propagate back to the parent. Depth starts at 0 (no script running),
  # outermost script increments to 1, nested scripts to 2+.
  #
  # Used by print_script_start, print_script_summary, and print_results_summary
  # to suppress output from nested scripts so only the outermost script prints
  # banners and summaries.
  #
  # @return [Boolean] true if this is the outermost script, false otherwise
  # :reek:UtilityFunction -- Stateless query of global state
  def outermost_script?
    EnvVars.script_depth == 1
  end

  # Sets the script name override. Use this in module methods that act as
  # standalone entry points (e.g., DevEnvironment.install_mise_versions) where
  # $PROGRAM_NAME would be '-e' or unhelpful. Must be public so module methods
  # can call it before increment_script_depth.
  #
  # @param name [String] The script name to use in log output
  def script_name=(name)
    state.script_name = name
  end

  # Increments _DOTFILES_SCRIPT_DEPTH and registers an at_exit hook to
  # decrement it on exit (clean or error). Called internally by run_script
  # and CollectionProcessor. Mirrors the export + trap pattern in shell scripts.
  def increment_script_depth
    EnvVars.script_depth = EnvVars.script_depth + 1
    at_exit { decrement_script_depth }
  end

  # Decrements _DOTFILES_SCRIPT_DEPTH, guarding against underflow. Called
  # automatically by the at_exit hook registered in increment_script_depth.
  # Mirrors _decrement_script_depth in .shellrc.
  # :reek:UtilityFunction -- Stateless modifier of global state
  def decrement_script_depth
    depth = EnvVars.script_depth
    EnvVars.script_depth = depth - 1 if depth.positive?
  end

  # The shared run state (see Logging::State). One object for the whole process, so
  # `include Logging` receivers and `Logging.` callers always see the same data.
  #
  # @return [Logging::State]
  def state
    STATE
  end

  # ---------------------------------------------------------------------------
  # Private implementation details
  # ---------------------------------------------------------------------------

  private

  # Common logging implementation for success/info/warn/user_action methods.
  # Handles filtering, suppression, message processing, and emission.
  #
  # @param level [Symbol] Log level (:success, :info, :warn, :user_action)
  # @param message [String] Message to log
  # @param prefix [String] Formatted prefix with emoji and color
  # @return [void]
  def _emit_log(level, message, prefix)
    return unless _should_log?(level)
    # Suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return if EnvVars.suppress_log?

    msg = message.to_s.replace_home_path_with_tilde
    msg.each_line { |line| emit("#{prefix} #{line.chomp}", level: 0) }
  end

  # The name of the currently running script, mirroring _SCRIPT_NAME in shell.
  # Can be overridden by setting script_name= (used by module methods that act
  # as entry points, where $PROGRAM_NAME would be '-e' or unhelpful).
  #
  # @return [String] The current script name
  def script_name
    state.script_name || File.basename($PROGRAM_NAME)
  end

  # Returns the depth-based indent string (2 spaces per depth level).
  # Used by all logging functions to auto-indent output based on script nesting.
  # Memoized to avoid repeated string multiplication for the same depth.
  #
  # @return [String] The indentation string for the current script depth
  def _log_indent
    depth = EnvVars.script_depth
    # Guard against depth 0 (called before increment_script_depth) - treat as depth 1
    # to prevent negative multiplication. This can happen when print_script_summary
    # decrements depth before calling section_header.
    depth = 1 if depth < 1
    # Outermost script (depth 1) has 0 indentation, depth 2 has 2 spaces, etc.
    state.indent_cache[depth] ||= '  ' * (depth - 1)
  end

  # Returns the subordinate indent string (depth-based indent + N levels of nesting).
  # Each nesting level adds 2 spaces. Used for content that should be indented
  # relative to parent messages (stats, timing, list items).
  #
  # @param level [Integer] Number of subordinate nesting levels (default: 0)
  # @return [String] The indented string
  def _subordinate_indent(level = 0)
    _log_indent + ('  ' * level)
  end

  # Repeats a character N times for section header padding.
  #
  # @param char [String] The character to repeat.
  # @param length [Integer] Number of repetitions.
  # @return [String] The repeated character string.
  def _repeat_char(char, length)
    char * length
  end

  # Returns the current terminal column width, falling back to COLUMNS env var or 80.
  # Reads from: 1) $stdout.winsize (ioctl), 2) EnvVars.columns (COLUMNS env var), 3) hardcoded 80
  # Matches shell behavior: ${COLUMNS:-${_FALLBACK_TERMINAL_WIDTH}}
  #
  # @return [Integer] Terminal column width
  def terminal_width
    return state.terminal_width if state.terminal_width

    # Try ioctl first (real terminal attached)
    cols = begin
      $stdout.winsize[1]
    rescue StandardError
      0
    end

    # Fall back to COLUMNS env var (set by parent shell), then hardcoded 80
    state.terminal_width = cols.nonzero? || EnvVars.columns
  end
end
