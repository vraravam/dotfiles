class File
  class << self
    def append(path, content)
      File.open(path, 'a') { |f| f << content }
    end
  end
end
