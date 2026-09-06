#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Provides ANSI color methods for strings and pathnames.
# Included in both String and Pathname to allow colorization without explicit .to_s conversion.
#
# Design: When included in Pathname, color methods automatically convert to String first,
# then apply colorization. This means:
#   - pathname.cyan works (returns colored String)
#   - system('ls', pathname) still works (system calls .to_s, gets plain String)
#   - pathname.to_s.cyan can be simplified to pathname.cyan
#
# All color methods apply HOME -> ~ substitution automatically, so paths are display-ready.
module Colorizable
  # Wraps the string in the ANSI escape sequence for +code+, after replacing
  # the HOME path with '~' so any path argument is display-ready automatically.
  # Returns the string unchanged (no ANSI, no substitution) when stdout is not
  # a TTY (pipes, CI, etc.), mirroring the shell's conditional color variables.
  #
  # Design: color methods apply tilde substitution so callers never need to
  # pre-substitute before passing a path to .yellow, .cyan, etc. Logging methods
  # (success/info/warn/debug/error) do NOT apply substitution -- they rely on
  # color methods having already done so for any colorized path segments.
  # Bare puts/print call sites that display paths WITHOUT a color method must
  # still call replace_home_path_with_tilde explicitly.
  #
  # This is the Ruby equivalent of _colorize() in .shellrc -- both are the single
  # centralised implementation point that all public color functions delegate to.
  #
  # When included in Pathname, this method automatically converts to String first.
  #
  # @api private
  # @param code [String] SGR parameter sequence, e.g. "0;31" (normal red) or "1;34" (bright blue).
  # @return [String]
  def colorize(code)
    # Delegate to replace_home_path_with_tilde for the string conversion + substitution
    str = replace_home_path_with_tilde
    return str unless $stdout.tty?

    "\x1b[#{code}m#{str}\x1b[0m"
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
  # When called on Pathname, converts to String first.
  #
  # NOTE: Uses ENV.fetch('HOME') directly instead of EnvVars::HOME to avoid circular
  # dependency. This file is required by pathname_ext, which is required by core,
  # which is required by env_vars. Using EnvVars here would create:
  # core -> pathname_ext -> colorizable -> env_vars -> core (circular!)
  #
  # @return [String]
  def replace_home_path_with_tilde
    str = is_a?(String) ? self : to_s
    home_dir = ENV.fetch('HOME', '')
    # sub (not gsub) -- a path contains HOME at most once (at the start); this runs on
    # nearly every logged path in the codebase, so avoiding the full-string gsub scan matters.
    str.sub(home_dir, '~')
  end

  # rubocop:disable Style/SingleLineMethods

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

  # rubocop:enable Style/SingleLineMethods
end
