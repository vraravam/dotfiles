# frozen_string_literal: true

class File
  class << self
    def append(path, content)
      File.write(path, content, mode: 'a')
    end
  end
end
