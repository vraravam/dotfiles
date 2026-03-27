# frozen_string_literal: true

require 'pathname'  # Note: This has been added explicitly due to the default version of ruby (2.6) on a vanilla macos. Once the default ruby upgrades to 3.x, we can remove

# Cached once at load time; HOME does not change during the lifetime of a script.
HOME_PATH_STR = Pathname.new(ENV.fetch('HOME')).expand_path.to_s.freeze

class String
  # colorization
  #
  # @param color_code [Integer] The color code to apply.
  # @return [String] The colorized string.
  def colorize(color_code)
    "\x1b[#{color_code}m#{self}\x1b[0m"
  end
  private :colorize

  # replace the value of the 'HOME' variable with '~' to shorten the text length
  def replace_home_path_with_tilde
    gsub(HOME_PATH_STR, '~')
  end

  # @return [String] The string in red.
  def red
    colorize(31)
  end

  # @return [String] The string in green.
  def green
    colorize(32)
  end

  # @return [String] The string in yellow.
  def yellow
    colorize(33)
  end

  # @return [String] The string in blue.
  def blue
    colorize(34)
  end

  # @return [String] The string in pink.
  def pink
    colorize(35)
  end

  # @return [String] The string in light blue.
  def light_blue
    colorize(36)
  end

  alias cyan light_blue
end
