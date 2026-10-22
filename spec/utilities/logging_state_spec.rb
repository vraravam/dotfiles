# encoding: utf-8
# frozen_string_literal: true

require 'logging'

RSpec.describe Logging::State do
  subject(:state) { described_class.new }

  it 'starts pristine' do
    expect(state.script_name).to be_nil
    expect(state.current_section).to be_nil
    expect(state.current_section_manual).to be false
    expect(state.script_start_time).to be_nil
    expect(state.issues_file_owner).to be false
    expect(state.warnings).to eq([])
    expect(state.errors).to eq([])
    expect(state.step_start_times).to eq([])
    expect(state.indent_cache).to eq({})
  end

  describe '#reset!' do
    it 'clears every piece of run state' do
      state.script_name = 'demo.rb'
      state.current_section = 'Step A'
      state.current_section_manual = true
      state.script_start_time = 123
      state.issues_file_owner = true
      state.terminal_width = 100
      state.min_log_level = 3
      state.warnings << 'w'
      state.errors << 'e'
      state.step_start_times << 1
      state.indent_cache[1] = '  '

      state.reset!

      expect(state.script_name).to be_nil
      expect(state.current_section).to be_nil
      expect(state.current_section_manual).to be false
      expect(state.script_start_time).to be_nil
      expect(state.issues_file_owner).to be false
      expect(state.terminal_width).to be_nil
      expect(state.min_log_level).to be_nil
      expect(state.warnings).to be_empty
      expect(state.errors).to be_empty
      expect(state.step_start_times).to be_empty
      expect(state.indent_cache).to be_empty
    end
  end

  it 'gives each instance its own collections' do
    other = described_class.new
    state.warnings << 'w'

    expect(other.warnings).to be_empty
  end

  it 'exposes one process-wide instance as Logging::STATE' do
    expect(Logging::STATE).to be_a(described_class)
    expect(Logging.state).to equal(Logging::STATE)
  end
end
