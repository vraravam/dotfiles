# frozen_string_literal: true

require_relative 'env_vars'
require_relative 'string'

# Logging helpers that replicate the shell functions defined in .shellrc
# (success/info/warn/debug/error, section_header, print_script_start,
# print_script_duration, print_script_summary, record_warning, record_error).
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

  # ---------------------------------------------------------------------------
  # General-purpose utility helpers
  # ---------------------------------------------------------------------------

  # Checks if a value is nil or empty.
  #
  # @param val [nil, #empty?] The value to check. Non-nil values must respond to +#empty?+.
  # @return [true, false]
  # @raise [NoMethodError] if +val+ is not nil and does not respond to +#empty?+.
  def nil_or_empty?(val)
    val.nil? || val.empty?
  end

  # ---------------------------------------------------------------------------
  # Semantic log-level helpers
  # These mirror success/info/warn/debug/error from .shellrc.
  #
  # All logging functions automatically prepend indentation based on
  # _DOTFILES_SCRIPT_DEPTH. Multi-line messages have each line indented.
  #
  # These methods do NOT apply tilde substitution -- color methods (.yellow,
  # .cyan, etc.) do so automatically on their arguments. Logging methods are
  # pure formatters: prefix + message. Bare puts/print call sites that display
  # paths without a color method must call replace_home_path_with_tilde explicitly.
  #
  # The shell's `error` calls `osascript` for a macOS notification; that
  # behaviour is omitted here since it is inappropriate for library code.
  # ---------------------------------------------------------------------------

  # Returns the depth-based indent string (2 spaces per depth level).
  # Used by all logging functions to auto-indent output based on script nesting.
  # Memoized to avoid repeated string multiplication for the same depth.
  def log_indent
    @indent_cache ||= {}
    depth = ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
    @indent_cache[depth] ||= '  ' * depth
  end

  def success(message)
    # Suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return if EnvVars.suppress_log?
    indent = log_indent
    message.to_s.each_line { |line| puts "#{indent}✅ #{'**SUCCESS**'.green} #{line.chomp}" }
  end

  def info(message)
    # Suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return if EnvVars.suppress_log?
    indent = log_indent
    message.to_s.each_line { |line| puts "#{indent}ℹ️  #{'**INFO**'.cyan} #{line.chomp}" }
  end

  def warn(message)
    # Suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return if EnvVars.suppress_log?
    indent = log_indent
    message.to_s.each_line { |line| puts "#{indent}⚠️  #{'**WARN**'.light_red} #{line.chomp}" }
  end

  def debug(message)
    # Hidden by default; only visible when DEBUG env var is set.
    # Also suppressed when running inside a direnv subshell (see EnvVars.suppress_log?).
    # Use error for messages that must always be visible regardless of context.
    return unless EnvVars.debug?
    return if EnvVars.suppress_log?
    indent = log_indent
    message.to_s.each_line { |line| puts "#{indent}⚙️  #{'**DEBUG**'.light_purple} #{line.chomp}" }
  end

  # Prints a message prompting the user to perform a manual step (e.g. restart
  # an app, run a command, open a URL). Distinct from warn (unexpected problem)
  # and info (purely informational). Suppressed in direnv subshells -- direnv
  # runs headlessly and cannot act on prompts. Mirrors user_action() in .shellrc.
  def user_action(message)
    return if EnvVars.suppress_log?
    indent = log_indent
    message.to_s.each_line { |line| puts "#{indent}➡️  #{'**ACTION**'.yellow} #{line.chomp}" }
  end

  # Prints the error message and raises a +RuntimeError+ with that message,
  # terminating the current execution path unless rescued by the caller.
  # error() always prints regardless of context -- critical failures must be visible.
  # @raise [RuntimeError]
  def error(message)
    indent = log_indent
    msg = message.to_s.replace_home_path_with_tilde
    msg.each_line { |line| puts "#{indent}❌ #{'**ERROR**'.red} #{line.chomp} 🤓" }
    raise msg
  end

  # Joins array elements into a bulleted list string, each on a new line with
  # 2-space indent and '- ' prefix.
  #
  # Usage: join_array(my_array)
  # Example: join_array(['file1.yml', 'file2.yml'])
  #
  # Output: "  - file1.yml\n  - file2.yml"
  #
  # The 2-space indent is fixed, not depth-based, because list items should always
  # be subordinate to their parent message text by exactly 2 spaces regardless of
  # how deeply nested the parent message is.
  #
  # @param arr [Array] The array to join.
  # @return [String] The formatted list string, or empty string if array is empty.
  def join_array(arr)
    return '' if nil_or_empty?(arr)
    arr.map { |item| "  - #{item}" }.join("\n")
  end

  # ---------------------------------------------------------------------------
  # Section / script timing helpers
  # These mirror section_header, print_script_start, and print_script_duration
  # from .shellrc.
  # ---------------------------------------------------------------------------

  # Prints +char+ repeated +length+ times.
  # Defaults to '=' and terminal-width/4 columns when +length+ is not given.
  #
  # @param char [String] The character to repeat (default: '=').
  # @param length [Integer, nil] Number of repetitions; defaults to +terminal_width / 4+ when nil.
  # @return [String] The repeated character string.
  def print_chars_for_length(char: '=', length: nil)
    char * (length || terminal_width / 4)
  end

  # Prints a centred section header flanked by '=' padding, matching:
  #   echo "$(light_blue $(print_chars_for_length '=' …)) ⏳ ${header} $(light_blue …)"
  # Also sets current_section to +header+ so that subsequent record_warning /
  # record_error entries are automatically attributed to this section.
  # Automatically indents based on _DOTFILES_SCRIPT_DEPTH.
  def section_header(header)
    @current_section = header
    _section_header_impl(header, char: '=', glyph: '⏳', color: :light_blue)
  end

  # Sub-level section header for steps nested inside a top-level section_header.
  # Mirrors section_header2 in .shellrc: '-' padding, '🔷' glyph, cyan colour.
  # Indentation is automatic via log_indent in _section_header_impl.
  # Does NOT update current_section -- sub-steps belong to the enclosing
  # top-level section for record_warning / record_error attribution.
  def section_header2(header)
    _section_header_impl(header, char: '-', glyph: '🔷', color: :cyan)
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
    now = Time.now
    if outermost_script?
      puts "#{script_name.cyan} #{'==>'.purple} #{'Script started at:'.yellow} #{now.strftime('%Y-%m-%d %H:%M:%S').light_blue}"
    end
    now.to_i
  end

  # Prints the script finish timestamp and total duration.
  #
  # @param start_time [Integer] Unix epoch returned by an earlier +Time.now.to_i+.
  # @return [void]
  def print_script_duration(start_time)
    return unless outermost_script?
    now = Time.now
    human = format_duration(now.to_i - start_time)
    puts "#{script_name.cyan} #{'==>'.purple} #{'Script finished at:'.yellow} #{now.strftime('%Y-%m-%d %H:%M:%S').light_blue} " \
         "(#{'Total duration:'.yellow} #{human.light_blue} #{'seconds'.yellow})."
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
  def current_section=(name)
    @current_section = name
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

  # Filters out common noise from stderr output (permission denied, file not found, etc.)
  # and records a warning only if meaningful errors remain. Use this when a command is
  # expected to produce some non-fatal stderr noise that should not clutter the logs.
  #
  # @param stderr [String] Raw stderr output from a command.
  # @param context [String] Context message prefix for the warning (e.g., "Issues during git search").
  # @param ignore_patterns [Array<String>] Additional patterns to ignore beyond the defaults.
  # @return [void]
  #
  # @example
  #   stdout, stderr, status = Open3.capture3('find', path, '-name', '.git')
  #   filter_and_warn_stderr(stderr, context: 'Issues while searching for git repos')
  def filter_and_warn_stderr(stderr, context:, ignore_patterns: [])
    return if nil_or_empty?(stderr)

    default_noise = ['Permission denied', 'No such file or directory']
    all_patterns = default_noise + ignore_patterns

    meaningful_errors = stderr.each_line.map(&:strip).reject do |line|
      nil_or_empty?(line) || all_patterns.any? { |pattern| line.include?(pattern) }
    end

    record_warning("#{context}:\n#{meaningful_errors.join("\n")}") if meaningful_errors.any?
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

  # Formats +seconds+ as "Hh:MMm:SSs". Public so callers that build their own
  # notification or summary strings can format a duration without reaching into
  # private state via send().
  def format_duration(seconds)
    format('%02dh:%02dm:%02ds', seconds / 3600, (seconds % 3600) / 60, seconds % 60)
  end

  # ---------------------------------------------------------------------------
  # Script depth tracking -- public API called by each script's main()
  # ---------------------------------------------------------------------------

  # Returns true when this is the outermost script in a nested call chain.
  # Mirrors is_outermost_script in .shellrc. _DOTFILES_SCRIPT_DEPTH is exported
  # and incremented by each script's main(); subprocess increments do not
  # propagate back to the parent. Defaults to 0 when unset so standalone scripts
  # (which never set the counter) are treated as outermost -- consistent with the
  # ':-0' used in the increment expression in each main().
  def outermost_script?
    _script_depth <= 1
  end

  # Increments _DOTFILES_SCRIPT_DEPTH and registers an at_exit hook to
  # decrement it on exit (clean or error). Call once at script start, before
  # any logging calls. Mirrors the export + trap pattern in shell scripts.
  def increment_script_depth
    ENV['_DOTFILES_SCRIPT_DEPTH'] = (_script_depth + 1).to_s
    at_exit { decrement_script_depth }
  end

  # Decrements _DOTFILES_SCRIPT_DEPTH, guarding against underflow. Called
  # automatically by the at_exit hook registered in increment_script_depth.
  # Mirrors _decrement_script_depth in .shellrc.
  def decrement_script_depth
    depth = _script_depth
    ENV['_DOTFILES_SCRIPT_DEPTH'] = (depth - 1).to_s if depth > 0
  end

  # Prints a summary table showing total/successful/failed counts and lists failed items.
  # Used by scripts that process multiple items (repos, files, etc.).
  #
  # @param total [Integer] Total number of items processed
  # @param successful [Array<String>] List of successful items (paths, names, etc.)
  # @param failed [Array<String>] List of failed items
  # @param item_label [String] What to call each item (default: 'repositories')
  #
  # @example
  #   print_operation_summary(10, successful_repos, failed_repos)
  #   print_operation_summary(5, successful_files, failed_files, item_label: 'files')
  def print_operation_summary(total, successful, failed, item_label: 'repositories')
    # Only print when this is the outermost script -- suppresses nested summaries
    # when called from a wrapper script/function that prints its own final summary.
    return unless outermost_script?

    puts ''
    info 'Summary'.yellow
    puts "  Total #{item_label}: #{total}"
    puts "  Successful:         #{successful.length.to_s.green}"
    return unless failed.any?

    singular = item_label.sub(/ies$/, 'y').sub(/s$/, '')
    plural = item_label
    count_label = failed.length == 1 ? singular : plural

    puts "  Failed:             #{failed.length.to_s.red}"
    puts "  Failed #{count_label}:".red
    failed.each { |item| puts "    - '#{item.red}'" }
  end

  # Prints a summary of processing results from a hash returned by
  # CollectionProcessor.process_items or similar iteration helpers.
  #
  # This is a convenience wrapper around print_operation_summary that unpacks
  # the results hash and adds skipped-count display.
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
    print_operation_summary(
      results[:total],
      results[:successful],
      results[:failed],
      item_label: item_label
    )

    info "Skipped: #{results[:skipped].to_s.purple}" if results[:skipped]&.positive?
  end

  # Sets the script name override. Use this in module methods that act as
  # standalone entry points (e.g., GitWorkspace.install_mise_versions) where
  # $PROGRAM_NAME would be '-e' or unhelpful. Must be public so module methods
  # can call it before increment_script_depth.
  def script_name=(name)
    @script_name = name
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

  # Returns the current value of _DOTFILES_SCRIPT_DEPTH as an integer,
  # defaulting to 0 when unset. Single point of truth for reading the counter.
  def _script_depth
    ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
  end

  # Shared implementation for section_header and section_header2. Mirrors
  # _section_header_impl in .shellrc: centres the header between repeated-char
  # padding, coloured by +color+, prefixed with +glyph+, and optionally indented.
  # Automatically indents based on _DOTFILES_SCRIPT_DEPTH.
  #
  # @param header [String] The header text to display.
  # @param char   [String] Padding character ('=' for headers).
  # @param glyph  [String] Emoji glyph displayed before the header.
  # @param color  [Symbol] Color method to apply to padding (e.g. :light_blue).
  def _section_header_impl(header, char:, glyph:, color:)
    depth_indent = log_indent
    header_str = header.replace_home_path_with_tilde
    padding_length = [((terminal_width - header_str.length - depth_indent.length) / 2) - 10, 1].max
    pad = print_chars_for_length(char: char, length: padding_length).send(color)
    puts "#{depth_indent}#{pad} #{glyph} #{header_str} #{pad}"
  end

  # Per-includer stacks stored as instance variables so that each object (or
  # the top-level main object when `include`d at script level) has its own
  # independent stacks, matching the zsh array semantics.
  def script_start_times
    @script_start_times ||= []
  end

  # Returns the current terminal column width, falling back to 80.
  # $stdout.winsize[1] reads the terminal dimensions via ioctl -- no `tput cols` subprocess fork.
  # rescue 0 handles non-tty contexts (e.g. pipes, cron) gracefully.
  def terminal_width
    return @terminal_width if @terminal_width
    cols = $stdout.winsize[1] rescue 0
    @terminal_width = cols.nonzero? || 80
  end
end
