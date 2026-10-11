# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'preferences_restore'

RSpec.describe PreferencesRestore do
  around do |example|
    Dir.mktmpdir('prefs-restore-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:scripts) { @tmp.join('scripts') }
  let(:osx_defaults) { scripts.join('osx-defaults.sh') }
  let(:capture_prefs) { scripts.join('capture-prefs.rb') }

  before do
    Logging.state.reset!
    stub_const('EnvVars::DOTFILES_DIR', @tmp)
    scripts.mkpath
    osx_defaults.write("#!/bin/sh\n")
    capture_prefs.write("#!/usr/bin/env ruby\n")
    allow(EnvVars).to receive(:columns).and_return(100)
    allow(CommandUtils).to receive(:run_interactive).and_return(true)
  end

  after { Logging.state.reset! }

  def run_quietly(**kwargs)
    original = $stdout
    $stdout = StringIO.new
    described_class.run(**kwargs)
  ensure
    $stdout = original
  end

  def expect_capture(flag, result: true)
    env = { 'COLUMNS' => '100' }
    expect(CommandUtils).to receive(:run_interactive).with(env, RbConfig.ruby, capture_prefs.to_s, flag).and_return(result)
  end

  context 'on a vanilla macOS' do
    it 'baselines the defaults and imports the backup, without exporting first' do
      expect(CommandUtils).to receive(:run_interactive).with(osx_defaults.to_s, '-s').ordered.and_return(true)
      expect_capture('-i')
      expect(CommandUtils).not_to receive(:run_interactive).with(anything, anything, anything, '-e')

      expect(run_quietly(first_install: true)).to be true
    end
  end

  context 'on a pre-configured machine' do
    it 'refreshes the backup before importing it' do
      expect(CommandUtils).to receive(:run_interactive).with(osx_defaults.to_s, '-s').ordered.and_return(true)
      expect_capture('-e')
      expect_capture('-i')

      expect(run_quietly(first_install: false)).to be true
    end

    it 'still imports, records a warning and returns false when the refresh fails' do
      allow(CommandUtils).to receive(:run_interactive).with(hash_including('COLUMNS'), RbConfig.ruby, capture_prefs.to_s, '-e').and_return(false)
      expect_capture('-i')

      expect(run_quietly).to be false
      expect(Logging.issue_summary_parts.join).to match(/Failed to refresh backup/)
    end
  end

  it 'takes first_install from the FIRST_INSTALL environment variable when not given' do
    expect_capture('-i')
    expect(CommandUtils).not_to receive(:run_interactive).with(anything, anything, anything, '-e')

    with_env('FIRST_INSTALL' => '1') { expect(run_quietly).to be true }
  end

  it 'records an error and carries on to the import when the baseline fails' do
    allow(CommandUtils).to receive(:run_interactive).with(osx_defaults.to_s, '-s').and_return(false)
    expect_capture('-i')

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/osx-defaults.sh exited non-zero/)
  end

  it 'records an error and skips the baseline when osx-defaults.sh is missing' do
    osx_defaults.delete
    expect(CommandUtils).not_to receive(:run_interactive).with(osx_defaults.to_s, '-s')
    expect_capture('-i')

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/osx-defaults.sh not found/)
  end

  it 'records an error when the import fails' do
    allow(CommandUtils).to receive(:run_interactive).with(hash_including('COLUMNS'), RbConfig.ruby, capture_prefs.to_s, '-i').and_return(false)

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/capture-prefs.rb exited non-zero/)
  end

  it 'records an error, running neither capture-prefs step, when capture-prefs.rb is missing' do
    capture_prefs.delete
    expect(CommandUtils).not_to receive(:run_interactive).with(anything, RbConfig.ruby, anything, anything)

    expect(run_quietly).to be false
    expect(Logging.issue_summary_parts.join).to match(/capture-prefs.rb not found/)
  end
end
