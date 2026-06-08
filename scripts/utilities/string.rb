# frozen_string_literal: true

require_relative 'env_vars'

class String
  # Wraps the string in the ANSI escape sequence for +code+, after replacing
  # the HOME path with '~' so any path argument is display-ready automatically.
  # Returns the string unchanged (no ANSI, no substitution) when stdout is not
  # a TTY (pipes, CI, etc.), mirroring the shell's conditional color variables.
  #
  # Design: color methods apply tilde substitution so callers never need to
  # pre-substitute before passing a path to .yellow, .cyan, etc. Logging methods
  # (success/info/warn/debug/error) do NOT apply substitution — they rely on
  # color methods having already done so for any colorized path segments.
  # Bare puts/print call sites that display paths WITHOUT a color method must
  # still call replace_home_path_with_tilde explicitly.
  #
  # This is the Ruby equivalent of _colorize() in .shellrc — both are the single
  # centralised implementation point that all public color functions delegate to.
  # Why call replace_home_path_with_tilde directly here rather than inlining
  # gsub(EnvVars::HOME.to_s, '~'): Ruby method calls have no fork overhead, so calling
  # the utility method keeps the substitution logic in one place. The shell's
  # _colorize inlines ${2//${HOME}/~} instead because replace_home_with_tilde
  # prints via 'echo' and capturing it would require a $(...) subshell fork.
  #
  # @api private
  # @param code [String] SGR parameter sequence, e.g. "0;31" (normal red) or "1;34" (bright blue).
  # @return [String]
  def colorize(code)
    return self unless $stdout.isatty

    "\x1b[#{code}m#{replace_home_path_with_tilde}\x1b[0m"
  end

  private :colorize

  # Replaces the expanded HOME path with '~' to produce a shorter, human-readable path.
  # Returns the string unchanged if it does not contain the home directory path.
  #
  # Design: color methods (.yellow, .cyan, etc.) call this automatically, so any
  # path passed through a color method is display-ready without an explicit call here.
  # Call this explicitly only for:
  #   - Bare puts/print call sites that display paths WITHOUT a color method.
  #   - Plain-text segments in section headers not wrapped in a color method.
  #
  # @return [String]
  def replace_home_path_with_tilde
    gsub(EnvVars::HOME.to_s, '~')
  end

  # @return [String] The string in black.
  def black; colorize('0;30'); end

  # @return [String] The string in dark gray.
  def dark_gray; colorize('1;30'); end

  # @return [String] The string in red.
  def red; colorize('0;31'); end

  # @return [String] The string in light red.
  def light_red; colorize('1;31'); end

  # @return [String] The string in green.
  def green; colorize('0;32'); end

  # @return [String] The string in light green.
  def light_green; colorize('1;32'); end

  # @return [String] The string in orange.
  def orange; colorize('0;33'); end

  # @return [String] The string in yellow.
  def yellow; colorize('1;33'); end

  # @return [String] The string in blue.
  def blue; colorize('0;34'); end

  # @return [String] The string in light blue.
  def light_blue; colorize('1;34'); end

  # @return [String] The string in purple.
  def purple; colorize('0;35'); end

  # @return [String] The string in light purple.
  def light_purple; colorize('1;35'); end

  # @return [String] The string in cyan.
  def cyan; colorize('0;36'); end

  # @return [String] The string in light cyan.
  def light_cyan; colorize('1;36'); end

  # @return [String] The string in light gray.
  def light_gray; colorize('0;37'); end

  # @return [String] The string in white.
  def white; colorize('1;37'); end
end
