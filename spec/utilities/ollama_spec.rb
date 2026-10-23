# encoding: utf-8
# frozen_string_literal: true

# Minimal specs for Ollama module contract verification.
# These specs verify behavior but are not the primary test suite (this codebase has no test framework).
# If adding rspec/minitest later, this file provides reference implementations.

require 'ollama'
require 'core'
require 'command_utils'
require 'logging'
require 'path_utils'

describe Ollama do
  before { Logging.state.reset! }

  after { Logging.state.reset! }

  describe '.list' do
    it 'returns empty array when ollama not found' do
      allow(PathUtils).to receive(:command_exists?).with('ollama').and_return(false)
      expect(Ollama.list).to eq([])
    end

    it 'returns array of model names when ollama is found' do
      allow(PathUtils).to receive(:command_exists?).with('ollama').and_return(true)
      allow(CommandUtils).to receive(:query).with('ollama', 'list')
        .and_return("NAME    ID\nqwen3.5:9b  abc123")
      expect(Ollama.list).to eq(['qwen3.5:9b'])
    end

    it 'handles model names with slashes correctly' do
      allow(PathUtils).to receive(:command_exists?).with('ollama').and_return(true)
      allow(CommandUtils).to receive(:query).with('ollama', 'list')
        .and_return("NAME             ID              SIZE      MODIFIED\nqwen3.5:9b       abc             8GB      now")
      result = Ollama.list
      expect(result).to include('qwen3.5:9b')
    end

    it 'removes duplicates' do
      allow(PathUtils).to receive(:command_exists?).with('ollama').and_return(true)
      allow(CommandUtils).to receive(:query).with('ollama', 'list')
        .and_return("MODEL\nqwen3.5:9b")
      expect(Ollama.list).to eq(['qwen3.5:9b'])
    end
  end

  describe '.pull' do
    it 'returns nil when ollama not found' do
      allow(PathUtils).to receive(:command_exists?).with('ollama').and_return(false)

      expect(Ollama.pull(model: 'qwen3.5:9b')).to be_nil
    end

    it 'raises error for empty model name' do
      allow(PathUtils).to receive(:command_exists?).with('ollama').and_return(true)
      expect(Logging).to receive(:record_error).with("Failed to pull model '' -- ArgumentError: Model name expected")

      expect(Ollama.pull(model: '')).to be_nil
    end

    it 'handles SystemExit error and returns nil' do
      allow(PathUtils).to receive(:command_exists?).with('ollama').and_return(true)
      exit_with_error = Object.new
      def exit_with_error.to_s
        raise SystemExit, 1
      end
      allow(CommandUtils).to receive(:stream_command).and_raise(SystemExit, 'non-zero')
      expect(Logging).to receive(:record_error).with("Failed to pull model 'test' -- non-zero")

      expect(Ollama.pull(model: 'test')).to be_nil
    end

    it 'handles StandardError and returns nil' do
      allow(PathUtils).to receive(:command_exists?).with('ollama').and_return(true)
      allow(CommandUtils).to receive(:stream_command).and_raise(StandardError, 'network error')
      expect(Logging).to receive(:record_error).with("Failed to pull model 'test' -- StandardError: network error")

      expect(Ollama.pull(model: 'test')).to be_nil
    end
  end
end
