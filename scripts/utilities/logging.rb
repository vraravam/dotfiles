#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'

require_relative 'core'
require_relative 'env_vars'
require_relative 'string'

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
module Logging
  # Make the module usable both as `include Logging` and as `Logging.info(…)`.
  extend self
  include Core  # For instance methods (in blocks)
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
    { char: '·', glyph: '▪', color: :dark_gray }     # Level 4: Deep nesting (depth 5+)
  ].freeze

  # Log levels in priority order (lowest to highest severity).
  # Used for filtering based on LOG_LEVEL environment variable.
  LOG_LEVELS = {
    debug: 0,
    info: 1,
    success: 2,
    warn: 3,
    error: 4,
    user_action: 5
  }.freeze

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

  def success(message)
    return unless _should_log?(:success)
    # Suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return if EnvVars.suppress_log?
    msg = message.to_s.replace_home_path_with_tilde
    msg.each_line { |line| emit("✅ #{'**SUCCESS**'.green} #{line.chomp}", level: 0) }
  end

  # Prints an informational message (normal progress, idempotency guards, etc.).
  # Suppressed in direnv subshells to reduce noise. Use 'error' for messages
  # that must always be visible regardless of context.
  # Filtered by LOG_LEVEL environment variable.
  #
  # @param message [String] The message to log
  # @return [void]
  def info(message)
    return unless _should_log?(:info)
    # Suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return if EnvVars.suppress_log?
    msg = message.to_s.replace_home_path_with_tilde
    msg.each_line { |line| emit("ℹ️ #{'**INFO**'.cyan} #{line.chomp}", level: 0) }
  end

  # Prints a warning message (non-fatal operation failures, argument parse errors).
  # Suppressed in direnv subshells. Use 'error' for messages that must always
  # be visible.
  # Filtered by LOG_LEVEL environment variable.
  #
  # @param message [String] The warning message to log
  # @return [void]
  def warn(message)
    return unless _should_log?(:warn)
    # Suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return if EnvVars.suppress_log?
    msg = message.to_s.replace_home_path_with_tilde
    msg.each_line { |line| emit("⚠️ #{'**WARN**'.light_red} #{line.chomp}", level: 0) }
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
    return unless _should_log?(:user_action)
    return if EnvVars.suppress_log?
    msg = message.to_s.replace_home_path_with_tilde
    msg.each_line { |line| emit("➡️ #{'**ACTION**'.yellow} #{line.chomp}", level: 0) }
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
  # - Outermost script (depth 1) with level 0 → 0 spaces
  # - Outermost script (depth 1) with level 1 → 2 spaces
  # - Nested script (depth 2) with level 0 → 2 spaces
  # - Nested script (depth 2) with level 1 → 4 spaces
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

    # File output (stripped of ANSI, plain text or JSON based on LOG_FORMAT)
    # Extract log level from message prefix if present, otherwise default to :info
    log_level = case message
    when /\*\*SUCCESS\*\*/
      :success
    when /\*\*INFO\*\*/
      :info
    when /\*\*WARN\*\*/
      :warn
    when /\*\*DEBUG\*\*/
      :debug
    when /\*\*ERROR\*\*/
      :error
    when /\*\*ACTION\*\*/
      :user_action
    else
      :info
    end

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
  def _strip_ansi(str)
    # ANSI escape sequences match pattern: ESC [ ... m
    # This regex removes all such sequences to get the visual text
    str.gsub(/\e\[[0-9;]*m/, '')
  end

  private_class_method :_strip_ansi

  # Prints a section header with visual hierarchy based on current script depth.
  # Level is automatically derived from script depth (depth 1 = level 0, depth 2 = level 1, etc.).
  # Only level 0 (outermost script) updates @current_section for error attribution.
  # Output matches the shell version in .shellrc (section_header function).
  #
  # Visual styles:
  # - Level 0 (depth 1): = ⏳ light_blue (top-level sections)
  # - Level 1 (depth 2): - 🔷 cyan (sub-sections)
  # - Level 2+ (depth 3+): · ▸ yellow (nested sections)
  #
  # @param header [String] The header text
  def section_header(header)
    level = [EnvVars.script_depth - 1, 0].max  # depth 1 → level 0, depth 2 → level 1, etc.

    # Auto-set current_section if nil/empty, at initial '(init)' value, OR not manually set.
    # This provides progressively more specific context as execution descends through nested
    # operations. Manual assignments (via `current_section=`) set a flag that prevents
    # auto-updates, allowing concise error attribution while displaying descriptive headers.
    unless @current_section_manual
      # Direct assignment (not via setter) to avoid setting the manual flag
      @current_section = _strip_ansi(header.to_s)
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

  # Prints the script start timestamp, prefixed with the script name. Mirrors:
  #   echo "$(cyan "${_SCRIPT_NAME:-}") $(purple '==>') $(yellow 'Script started at:') $(light_blue "…")"
  # Returns the start time as a Unix epoch integer so the caller can pass it to
  # print_script_duration. This deviates from the shell version (which cannot
  # return a value) but eliminates the two-call pattern and ensures the logged
  # timestamp and the in-memory start time are identical.
  # Only prints when this is the outermost script -- see outermost_script?.
  #
  # @return [Integer] Unix epoch of the logged start time.
  def print_script_start
    @script_start_time = Time.now.to_i
    if outermost_script?
      emit("#{script_name.cyan} #{'==>'.purple} #{'Script started at:'.yellow} #{Core.current_timestamp.light_blue}", level: 0)
    end
    @script_start_time
  end

  # Prints the script finish timestamp and total duration.
  #
  # @param start_time [Integer] Unix epoch returned by an earlier +Time.now.to_i+.
  # @return [void]
  def print_script_duration(start_time)
    return unless outermost_script?
    human = format_duration(Core.duration_since(start_time))
    emit("#{script_name.cyan} #{'==>'.purple} #{'Script finished at:'.yellow} #{Core.current_timestamp.light_blue} " \
         "(#{'Total duration:'.yellow} #{human.light_blue} #{'seconds'.yellow}).", level: 0)
  end

  # ---------------------------------------------------------------------------
  # Deferred error/warning collection
  # These mirror _record_warning, _record_error, and print_script_summary from
  # .shellrc. Each entry is prefixed with [script_name][current_section] for
  # traceability. print_script_summary prints collected issues grouped by type.
  # No macOS notification is sent -- osascript is not appropriate for library code.
  # ---------------------------------------------------------------------------

  # Sets the current logical section name, used as context in record_warning /
  # record_error entries. Mirrors the _current_section local in shell scripts.
  # Automatically strips ANSI codes to ensure clean error messages.
  def current_section=(name)
    @current_section = _strip_ansi(name.to_s)
    @current_section_manual = true  # Mark as manually set
  end

  # Wraps a block of code with step lifecycle management (current_section, step_start, step_end).
  # Ensures step_end is called even if the block raises an exception.
  #
  # @param section_name [String] Name for current_section tracking
  # @param header [String, nil] Optional section header to print (uses section_header if provided)
  # @yield Block of code to execute within the step lifecycle
  # @return [void]
  #
  # @example
  #   Logging.with_step('Install Homebrew', "Installing Homebrew into '#{path}'") do
  #     # ... install logic ...
  #   end
  def with_step(section_name, header = nil)
    self.current_section = section_name
    step_start
    section_header(header) if header

    yield
  ensure
    step_end
  end

  # Appends a non-critical issue to the warnings collection and emits an inline
  # warn so the issue is visible in the log at the point it occurs.
  def record_warning(message)
    step_warnings << "[#{script_name || 'unknown'}][#{@current_section || 'unknown'}] #{message}"
    warn(message)
  end

  # Appends a significant non-fatal failure to the errors collection and emits
  # an inline warn so the failure is visible in the log at the point it occurs.
  def record_error(message)
    step_errors << "[#{script_name || 'unknown'}][#{@current_section || 'unknown'}] #{message}"
    warn(message)
  end

  # Prints a grouped summary of all collected warnings and errors, prefixing
  # each section header with the script name, then prints the total duration.
  # Mirrors print_script_summary in .shellrc. No macOS notification -- callers
  # that need one must handle it themselves.
  #
  # Accepts an optional +start_time+ (Unix epoch returned by +print_script_start+).
  # When provided, calls +print_script_duration+ so the caller never needs to
  # invoke it separately. This deviates from the shell version, which cannot
  # call print_script_duration from within print_script_summary because shell
  # functions cannot propagate a return value for the start time.
  # When omitted (e.g. early-exit paths inside methods that cannot access the
  # top-level start-time local), the duration line is skipped.
  #
  # Accepts an optional +message+ to print before the warnings/errors sections.
  # Mirrors the second parameter of the shell version.
  #
  # @param start_time [Integer, nil] Unix epoch of script start, or nil to skip duration.
  # @param message [String, nil] Optional success message to print before summary.
  def print_script_summary(start_time = nil, message = nil)
    # outermost_script? encapsulates the _DOTFILES_SCRIPT_DEPTH check -- see its
    # definition for the full rationale.
    return unless outermost_script?

    info(message) unless nil_or_empty?(message)
    unless nil_or_empty?(step_warnings)
      # Temporarily decrement depth so both header and warnings print one level less indented
      decrement_script_depth
      section_header("#{script_name.cyan} #{("#{step_warnings.length} warning(s)").yellow}")
      step_warnings.each { |w| warn(w) }
      increment_script_depth
    end
    unless nil_or_empty?(step_errors)
      # Temporarily decrement depth so both header and errors print one level less indented
      decrement_script_depth
      section_header("#{script_name.cyan} #{("#{step_errors.length} error(s) -- manual attention needed").red}")
      step_errors.each { |e| warn(e) }
      increment_script_depth
    end
    print_script_duration(start_time) unless start_time.nil?
  end

  # Returns a frozen copy of collected warnings. Public so callers (e.g.
  # software-updates-cron.rb notification block) can read them without
  # reaching into private state via instance_variable_get.
  def step_warnings
    @step_warnings ||= []
  end

  # Returns a frozen copy of collected errors. Public for the same reason
  # as step_warnings above.
  def step_errors
    @step_errors ||= []
  end

  # Returns true if any warnings have been recorded during script execution.
  # Prefer this over directly checking step_warnings.any? for cleaner code.
  #
  # @return [Boolean] true if warnings exist, false otherwise
  #
  # @example
  #   @has_failures = true if Logging.has_warnings?
  def has_warnings?
    step_warnings.any?
  end

  # Returns true if any errors have been recorded during script execution.
  # Prefer this over directly checking step_errors.any? for cleaner code.
  #
  # @return [Boolean] true if errors exist, false otherwise
  #
  # @example
  #   exit(1) if Logging.has_errors?
  def has_errors?
    step_errors.any?
  end

  # Formats +seconds+ as "Hh:MMm:SSs". Public so callers that build their own
  # notification or summary strings can format a duration without reaching into
  # private state via send().
  def format_duration(seconds)
    format('%02dh:%02dm:%02ds', seconds / 3600, (seconds % 3600) / 60, seconds % 60)
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
  # @param script_name [String, nil] Name to use for Logging.script_name (required for utility methods, optional for CLI scripts)
  # @param message [String, nil] Optional message to print before summary
  # @yield [start_time] Block containing the script's main logic; receives Unix epoch start time (or nil if nested)
  # @return [void]
  #
  # @example CLI entry point script (script_name inferred from $PROGRAM_NAME)
  #   if __FILE__ == $PROGRAM_NAME
  #     include Logging
  #     # ... option parsing ...
  #     Logging.run_script do
  #       success = MyModule.run(param: value)
  #       exit(success ? 0 : 1)
  #     end
  #   end
  #
  # @example Utility module method (script_name explicit)
  #   def install_mise_versions(shared_dirs: nil, first_install: false)
  #     Logging.run_script('install_mise_versions') do
  #       # ... implementation ...
  #     end
  #   end
  #
  # @example With custom summary message
  #   Logging.run_script('cleanup_profiles', 'Finished cleaning up browser profiles') do
  #     # ... main logic ...
  #   end
  def run_script(script_name = nil, message = nil)
    self.script_name = script_name if script_name
    # Initialize current_section to '(init)' for consistency with shell scripts.
    # Use direct assignment (not setter) to avoid setting the manual flag.
    @current_section = '(init)'
    @current_section_manual = false

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
  def outermost_script?
    EnvVars.script_depth == 1
  end

  # Prints a summary of processing results from a hash returned by
  # CollectionProcessor.process_items or similar iteration helpers.
  #
  # @param results [Hash] Results hash with keys:
  #   - :total [Integer] Total items processed (excludes skipped)
  #   - :successful [Array<String>] Successful item names
  #   - :failed [Array<String>] Failed item names
  #   - :skipped [Integer] Count of skipped items (optional)
  # @param item_label [String] What to call each item (default: 'repositories')
  #
  # @example
  #   results = CollectionProcessor.process_items(...) { |item| ... }
  #   print_results_summary(results)
  #   print_results_summary(results, item_label: 'files')
  def print_results_summary(results, item_label: 'repositories')
    # Only print when this is the outermost script -- suppresses nested summaries
    # when called from a wrapper script/function that prints its own final summary.
    return unless outermost_script?

    total = results[:total]
    successful = results[:successful]
    failed = results[:failed]

    puts ''
    info('Summary'.yellow)
    emit("Total #{item_label}: #{total}", level: 1)
    emit("Successful:         #{successful.length.to_s.green}", level: 1)

    unless nil_or_empty?(failed)
      singular = item_label.sub(/ies$/, 'y').sub(/s$/, '')
      plural = item_label
      count_label = failed.length == 1 ? singular : plural

      emit("Failed:             #{failed.length.to_s.red}", level: 1)
      emit("Failed #{count_label}:".red, level: 0)
      puts join_array(failed, :red)
    end

    info "Skipped: #{results[:skipped].to_s.purple}" if results[:skipped]&.positive?
  end

  # Sets the script name override. Use this in module methods that act as
  # standalone entry points (e.g., GitWorkspace.install_mise_versions) where
  # $PROGRAM_NAME would be '-e' or unhelpful. Must be public so module methods
  # can call it before increment_script_depth.
  def script_name=(name)
    @script_name = name
  end

  # Increments _DOTFILES_SCRIPT_DEPTH and registers an at_exit hook to
  # decrement it on exit (clean or error). Called internally by run_script
  # and CollectionProcessor. Mirrors the export + trap pattern in shell scripts.
  def increment_script_depth
    ENV['_DOTFILES_SCRIPT_DEPTH'] = (EnvVars.script_depth + 1).to_s
    at_exit { decrement_script_depth }
  end

  # Decrements _DOTFILES_SCRIPT_DEPTH, guarding against underflow. Called
  # automatically by the at_exit hook registered in increment_script_depth.
  # Mirrors _decrement_script_depth in .shellrc.
  def decrement_script_depth
    depth = EnvVars.script_depth
    ENV['_DOTFILES_SCRIPT_DEPTH'] = (depth - 1).to_s if depth.positive?
  end

  # ---------------------------------------------------------------------------
  # Private implementation details
  # ---------------------------------------------------------------------------

  private

  # The name of the currently running script, mirroring _SCRIPT_NAME in shell.
  # Can be overridden by setting @script_name (used by module methods that act
  # as entry points, where $PROGRAM_NAME would be '-e' or unhelpful).
  def script_name
    @script_name || File.basename($PROGRAM_NAME)
  end

  # Returns the depth-based indent string (2 spaces per depth level).
  # Used by all logging functions to auto-indent output based on script nesting.
  # Memoized to avoid repeated string multiplication for the same depth.
  def _log_indent
    @indent_cache ||= {}
    depth = EnvVars.script_depth
    # Guard against depth 0 (called before increment_script_depth) - treat as depth 1
    # to prevent negative multiplication. This can happen when print_script_summary
    # decrements depth before calling section_header.
    depth = 1 if depth < 1
    # Outermost script (depth 1) has 0 indentation, depth 2 has 2 spaces, etc.
    @indent_cache[depth] ||= '  ' * (depth - 1)
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

  # Prints +char+ repeated +length+ times for section header padding.
  #

  # Pushes the current epoch seconds onto the step timing stack. Called by
  # with_step at the start of a step. Mirrors step_start in .shellrc.
  def step_start
    @step_start_times ||= []
    @step_start_times.push(Time.now.to_i)
  end

  # Pops the most recent step start time from the stack, computes elapsed time,
  # and logs it. Called by with_step's ensure block. Mirrors step_end in .shellrc.
  def step_end
    @step_start_times ||= []
    now = Time.now.to_i

    # Pop the step start time; fall back to script start time if stack is empty
    if nil_or_empty?(@step_start_times)
      # No step timing available - skip timing output
      return
    end

    step_start_time = @step_start_times.pop
    delta_step = now - step_start_time

    # Compute total elapsed from script start if available
    script_start_time = @script_start_time || now
    delta_total = now - script_start_time

    # Format: "(Step: XXs  Total: YYs)"
    emit("(#{'Step:'.yellow} #{delta_step.to_s.light_blue}s  #{'Total:'.yellow} #{delta_total.to_s.light_blue}s)", level: 0)
  end

  # Per-includer stacks stored as instance variables so that each object (or
  # the top-level main object when `include`d at script level) has its own
  # independent stacks, matching the zsh array semantics.
  def script_start_times
    @script_start_times ||= []
  end

  # Returns the current terminal column width, falling back to COLUMNS env var or 80.
  # Reads from: 1) $stdout.winsize (ioctl), 2) EnvVars.columns (COLUMNS env var), 3) hardcoded 80
  # Matches shell behavior: ${COLUMNS:-${_FALLBACK_TERMINAL_WIDTH}}
  def terminal_width
    return @terminal_width if @terminal_width

    # Try ioctl first (real terminal attached)
    cols = $stdout.winsize[1] rescue 0

    # Fall back to COLUMNS env var (set by parent shell), then hardcoded 80
    @terminal_width = cols.nonzero? || EnvVars.columns
  end

  # Checks if a log message at the given level should be printed.
  # Compares requested level against LOG_LEVEL environment variable.
  # Returns true if message level >= configured minimum level.
  #
  # Log levels (severity order): debug < info < success < warn < error < user_action
  #
  # Examples:
  #   LOG_LEVEL=debug → show all messages
  #   LOG_LEVEL=info  → show info, success, warn, error, user_action (default)
  #   LOG_LEVEL=warn  → show only warn, error, user_action
  #   LOG_LEVEL=error → show only error
  #
  # @param level [Symbol] The log level to check (:debug, :info, :success, :warn, :error, :user_action)
  # @return [Boolean] true if message should be logged, false otherwise
  def _should_log?(level)
    # Cache the configured minimum level (avoid repeated ENV lookups)
    @_min_log_level ||= begin
      env_level = ENV.fetch('LOG_LEVEL', 'info').downcase.to_sym
      LOG_LEVELS.key?(env_level) ? LOG_LEVELS[env_level] : LOG_LEVELS[:info]
    end

    # Allow message if its priority >= configured minimum
    LOG_LEVELS[level] >= @_min_log_level
  end

  # Writes log entry to file if LOG_FILE is set.
  # Handles log rotation (keeps last 5 files, max 10MB each).
  # Format determined by LOG_FORMAT env var (json or human-readable).
  #
  # @param level [Symbol] Log level
  # @param message [String] Log message (plain text, no color codes)
  # @return [void]
  def _write_to_log_file(level, message)
    log_file = ENV.fetch('LOG_FILE', nil)
    return if nil_or_empty?(log_file)

    log_path = Pathname.new(log_file)
    _rotate_log_if_needed(log_path)

    # Determine format
    format = ENV.fetch('LOG_FORMAT', 'text').downcase

    entry = if format == 'json'
      _format_json_log_entry(level, message)
    else
      _format_text_log_entry(level, message)
    end

    File.open(log_path, 'a') do |f|
      f.puts(entry)
    end
  rescue StandardError => e
    # Log file write failures should not crash the script
    warn "Failed to write to log file: #{e.message}" if EnvVars.debug?
  end

  # Formats log entry as JSON.
  #
  # @param level [Symbol] Log level
  # @param message [String] Log message
  # @return [String] JSON-formatted log entry
  def _format_json_log_entry(level, message)
    {
      timestamp: Time.now.utc.iso8601,
      level: level.to_s.upcase,
      message: message.strip,
      script: ENV.fetch('SCRIPT_NAME', $PROGRAM_NAME),
      depth: EnvVars.script_depth,
      section: @current_section
    }.to_json
  end

  # Formats log entry as human-readable text.
  #
  # @param level [Symbol] Log level
  # @param message [String] Log message
  # @return [String] Text-formatted log entry
  def _format_text_log_entry(level, message)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    "[#{timestamp}] [#{level.to_s.upcase}] #{message.strip}"
  end

  # Rotates log file if it exceeds 10MB.
  # Keeps last 5 log files (log.1, log.2, ..., log.5).
  #
  # @param log_path [Pathname] Path to log file
  # @return [void]
  def _rotate_log_if_needed(log_path)
    return unless log_path.file?
    return if log_path.size < 10 * 1024 * 1024 # 10MB

    # Rotate existing backups (log.4 → log.5, log.3 → log.4, etc.)
    (4).downto(1) do |i|
      old_file = Pathname.new("#{log_path}.#{i}")
      new_file = Pathname.new("#{log_path}.#{i + 1}")
      FileUtils.mv(old_file.to_s, new_file.to_s) if old_file.exist?
    end

    # Move current log to .1
    FileUtils.mv(log_path.to_s, "#{log_path}.1")

    # Delete oldest backup if it exists
    oldest = Pathname.new("#{log_path}.6")
    oldest.delete if oldest.exist?
  end
end
