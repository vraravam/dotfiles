# frozen_string_literal: true

class String
  # colorization
  #
  # @param color_code [Integer] The color code to apply.
  # @return [String] The colorized string.
  def colorize(color_code)
    "\x1b[#{color_code}m#{self}\x1b[0m"
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
