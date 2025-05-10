class String
  # colorization
  def colorize(color_code)
    "\x1b[#{color_code}m#{self}\x1b[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end

  def blue
    colorize(34)
  end

  def pink
    colorize(35)
  end

  def light_blue
    colorize(36)
  end

  alias :cyan :light_blue
end
