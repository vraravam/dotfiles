# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'logging'

# The private helpers of Logging::Sinks. The end-to-end LOG_FILE behaviour (text, JSON, rotation
# trigger) is covered in logging_spec.rb; this file pins the pieces it does not reach.
RSpec.describe Logging::Sinks do
  subject(:sink) { Logging }

  around do |example|
    Logging.state.reset!
    with_env('LOG_FILE' => nil, 'LOG_LEVEL' => nil, 'LOG_FORMAT' => nil, 'SCRIPT_NAME' => nil,
             '_DOTFILES_SCRIPT_DEPTH' => '1') { example.run }
    Logging.state.reset!
  end

  describe '#_log_level_for' do
    {
      '**SUCCESS** done' => :success,
      '**WARN** careful' => :warn,
      '**DEBUG** detail' => :debug,
      '**ERROR** broke' => :error,
      '**ACTION** do this' => :user_action,
      'plain message' => :info
    }.each do |message, level|
      it "classifies #{message.inspect} as #{level}" do
        expect(sink.send(:_log_level_for, message)).to eq(level)
      end
    end

    it 'finds the marker inside ANSI-decorated text' do
      expect(sink.send(:_log_level_for, "\e[1;33m**WARN**\e[0m text")).to eq(:warn)
    end
  end

  describe '#_should_log?' do
    it 'allows everything at LOG_LEVEL=debug' do
      with_env('LOG_LEVEL' => 'debug') do
        expect(Logging::Sinks::LOG_LEVELS.keys.map { |level| sink.send(:_should_log?, level) }).to all(be true)
      end
    end

    it 'defaults to info: debug is hidden, info and above are shown' do
      expect(sink.send(:_should_log?, :debug)).to be false
      expect(sink.send(:_should_log?, :info)).to be true
      expect(sink.send(:_should_log?, :user_action)).to be true
    end

    it 'at LOG_LEVEL=error hides warn but shows error and user_action' do
      with_env('LOG_LEVEL' => 'error') do
        expect(sink.send(:_should_log?, :warn)).to be false
        expect(sink.send(:_should_log?, :error)).to be true
        expect(sink.send(:_should_log?, :user_action)).to be true
      end
    end

    it 'caches the configured level so a later LOG_LEVEL change is not re-read' do
      with_env('LOG_LEVEL' => 'error') { sink.send(:_should_log?, :info) }

      with_env('LOG_LEVEL' => 'debug') do
        expect(sink.send(:_should_log?, :debug)).to be false
      end
    end
  end

  describe 'log entry formats' do
    it 'formats a text entry as "[timestamp] [LEVEL] stripped message"' do
      entry = sink.send(:_format_text_log_entry, :warn, "  spaced out \n")

      expect(entry).to match(/\A\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] \[WARN\] spaced out\z/)
    end

    it 'formats a JSON entry with script, depth and the current section' do
      Logging.state.current_section = 'Step A'

      with_env('SCRIPT_NAME' => 'demo.rb') do
        entry = JSON.parse(sink.send(:_format_json_log_entry, :error, "boom\n"))

        expect(entry).to include('level' => 'ERROR', 'message' => 'boom', 'script' => 'demo.rb',
                                 'depth' => 1, 'section' => 'Step A')
      end
    end
  end

  describe '#_write_to_log_file' do
    around do |example|
      Dir.mktmpdir('sinks-spec-') do |dir|
        @log = Pathname(dir).join('out.log')
        example.run
      end
    end

    it 'does nothing when LOG_FILE is unset' do
      expect { sink.send(:_write_to_log_file, :info, 'x') }.not_to raise_error
      expect(@log).not_to exist
    end

    it 'appends entries rather than truncating' do
      with_env('LOG_FILE' => @log.to_s) do
        sink.send(:_write_to_log_file, :info, 'first')
        sink.send(:_write_to_log_file, :info, 'second')
      end

      expect(@log.readlines.map(&:chomp)).to match([/first\z/, /second\z/])
    end

    it 'never raises when the log file cannot be written' do
      with_env('LOG_FILE' => @log.join('no-such-dir', 'out.log').to_s) do
        expect { sink.send(:_write_to_log_file, :info, 'x') }.not_to raise_error
      end
    end
  end

  describe '#_rotate_log_if_needed' do
    around do |example|
      Dir.mktmpdir('rotate-spec-') do |dir|
        @log = Pathname(dir).join('out.log')
        example.run
      end
    end

    def backup(num)
      Pathname("#{@log}.#{num}")
    end

    it 'leaves a missing file alone' do
      sink.send(:_rotate_log_if_needed, @log)

      expect(backup(1)).not_to exist
    end

    it 'leaves a file below the size limit alone' do
      @log.write('small')

      sink.send(:_rotate_log_if_needed, @log)

      expect(@log.read).to eq('small')
      expect(backup(1)).not_to exist
    end

    it 'shifts existing backups up by one and moves the live log to .1' do
      @log.write('x' * Logging::Sinks::MAX_LOG_BYTES)
      backup(1).write('one')
      backup(2).write('two')

      sink.send(:_rotate_log_if_needed, @log)

      expect(@log).not_to exist
      expect(backup(1).size).to eq(Logging::Sinks::MAX_LOG_BYTES)
      expect(backup(2).read).to eq('one')
      expect(backup(3).read).to eq('two')
    end

    it 'keeps at most LOG_BACKUPS backups, dropping the oldest' do
      @log.write('x' * Logging::Sinks::MAX_LOG_BYTES)
      (1..Logging::Sinks::LOG_BACKUPS).each { |num| backup(num).write("old#{num}") }
      overflow = backup(Logging::Sinks::LOG_BACKUPS + 1)

      sink.send(:_rotate_log_if_needed, @log)

      expect(overflow).not_to exist
      expect(backup(Logging::Sinks::LOG_BACKUPS).read).to eq("old#{Logging::Sinks::LOG_BACKUPS - 1}")
    end
  end
end
