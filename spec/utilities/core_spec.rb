# frozen_string_literal: true

require 'core'
require 'tempfile'

RSpec.describe Core do
  describe '.nil_or_empty?' do
    it 'is true for nil' do
      expect(described_class.nil_or_empty?(nil)).to be true
    end

    it 'is true for an empty string' do
      expect(described_class.nil_or_empty?('')).to be true
    end

    it 'is true for a whitespace-only string' do
      expect(described_class.nil_or_empty?('   ')).to be true
    end

    it 'is true for an empty array' do
      expect(described_class.nil_or_empty?([])).to be true
    end

    it 'is false for a non-empty string' do
      expect(described_class.nil_or_empty?('text')).to be false
    end

    it 'is false for a non-empty array' do
      expect(described_class.nil_or_empty?([1, 2])).to be false
    end

    it 'converts non-string/array values to a string before checking' do
      expect(described_class.nil_or_empty?(123)).to be false
      expect(described_class.nil_or_empty?(0)).to be false
    end
  end

  describe '.file?' do
    it 'is false for nil' do
      expect(described_class.file?(nil)).to be false
    end

    it 'is false for an empty string' do
      expect(described_class.file?('')).to be false
    end

    it 'is false for a path that does not respond to #file?' do
      expect(described_class.file?(123)).to be false
    end

    it 'is false for a directory' do
      expect(described_class.file?(Pathname.new(__dir__))).to be false
    end

    it 'is true for an existing regular file' do
      expect(described_class.file?(Pathname.new(__FILE__))).to be true
    end

    it 'is false for a non-existent path' do
      expect(described_class.file?(Pathname.new('/nonexistent/path/should/not/exist'))).to be false
    end
  end

  describe '.current_timestamp' do
    it 'formats as YYYY-MM-DD HH:MM:SS' do
      expect(described_class.current_timestamp).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/)
    end
  end

  describe '.duration_since' do
    it 'returns the elapsed seconds since the given start time' do
      start_time = Time.now.to_i - 42
      expect(described_class.duration_since(start_time)).to be >= 42
    end
  end

  describe '.elapsed?' do
    it 'is true when the threshold has been met' do
      start_time = Time.now.to_i - 100
      expect(described_class.elapsed?(start_time, 60)).to be true
    end

    it 'is false when the threshold has not been met' do
      start_time = Time.now.to_i
      expect(described_class.elapsed?(start_time, 60)).to be false
    end
  end

  describe '.running_in_tty?' do
    it 'is true when stdout is a TTY, regardless of FORCE_COLOR' do
      allow($stdout).to receive(:tty?).and_return(true)
      expect(described_class.running_in_tty?).to be true
    end

    it 'is true when FORCE_COLOR is set, even when stdout is not a TTY' do
      allow($stdout).to receive(:tty?).and_return(false)
      with_env('FORCE_COLOR' => '1') do
        expect(described_class.running_in_tty?).to be true
      end
    end

    it 'is false when stdout is not a TTY and FORCE_COLOR is unset' do
      allow($stdout).to receive(:tty?).and_return(false)
      with_env('FORCE_COLOR' => nil) do
        expect(described_class.running_in_tty?).to be false
      end
    end
  end

  describe '.read_lines_utf8' do
    it 'reads all lines from a UTF-8 file, preserving newlines' do
      Tempfile.create('core_spec') do |file|
        file.write("first\nsecond -- em dash\nthird\n")
        file.flush
        lines = described_class.read_lines_utf8(file.path)
        expect(lines).to eq(["first\n", "second -- em dash\n", "third\n"])
      end
    end
  end

  describe '.each_line_utf8' do
    it 'yields each line from the file' do
      Tempfile.create('core_spec') do |file|
        file.write("alpha\nbeta\n")
        file.flush
        yielded = []
        described_class.each_line_utf8(file.path) { |line| yielded << line }
        expect(yielded).to eq(%W[alpha\n beta\n])
      end
    end
  end
end
