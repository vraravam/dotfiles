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

  before do
    Logging.state.reset!
    stub_const('EnvVars::DOTFILES_DIR', @tmp)
    scripts.mkpath
    osx_defaults.write("#!/bin/sh\n")
    allow(CommandUtils).to receive(:run_interactive).and_return(true)
    allow(CapturePrefs).to receive(:run).and_return(true)
  end

  after { Logging.state.reset! }

  def run_quietly(**kwargs)
    original = $stdout
    $stdout = StringIO.new
    described_class.run(**kwargs)
  ensure
    $stdout = original
  end

  context 'on a vanilla macOS' do
    it 'baselines the defaults and imports the backup, without exporting first' do
      expect(CommandUtils).to receive(:run_interactive).with(osx_defaults.to_s, '-s').ordered.and_return(true)
      expect(CapturePrefs).to receive(:run).with(operation: 'import').ordered.and_return(true)
      expect(CapturePrefs).not_to receive(:run).with(operation: 'export')

      expect(run_quietly(first_install: true)).to be true
    end
  end

  context 'on a pre-configured machine' do
    it 'refreshes the backup before importing it' do
      expect(CommandUtils).to receive(:run_interactive).with(osx_defaults.to_s, '-s').ordered.and_return(true)
      expect(CapturePrefs).to receive(:run).with(operation: 'export').ordered.and_return(true)
      expect(CapturePrefs).to receive(:run).with(operation: 'import').ordered.and_return(true)

      expect(run_quietly(first_install: false)).to be true
    end

    it 'still imports, records a warning and returns false when the refresh fails' do
      allow(CapturePrefs).to receive(:run).with(operation: 'export').and_return(false)
      expect(CapturePrefs).to receive(:run).with(operation: 'import').and_return(true)

      expect(run_quietly).to be false
      expect(Logging.issue_summary_parts.join).to match(/Failed to refresh backup/)
    end

    it 'still imports when the refresh raises, printing why' do
      allow(CapturePrefs).to receive(:run).with(operation: 'export').and_raise('no git repo')
      expect(CapturePrefs).to receive(:run).with(operation: 'import').and_return(true)

      result = nil
      expect { result = described_class.run }.to output(/capture-prefs export failed: no git repo/).to_stdout
      expect(result).to be false
    end
  end

  it 'takes first_install from the FIRST_INSTALL environment variable when not given' do
    expect(CapturePrefs).to receive(:run).with(operation: 'import').and_return(true)
    expect(CapturePrefs).not_to receive(:run).with(operation: 'export')

    with_env('FIRST_INSTALL' => '1') { expect(run_quietly).to be true }
  end

  it 'records an error and carries on to the import when the baseline fails' do
    allow(CommandUtils).to receive(:run_interactive).with(osx_defaults.to_s, '-s').and_return(false)
    expect(CapturePrefs).to receive(:run).with(operation: 'import').and_return(true)

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/osx-defaults.sh exited non-zero/)
  end

  it 'records an error and skips the baseline when osx-defaults.sh is missing' do
    osx_defaults.delete
    expect(CommandUtils).not_to receive(:run_interactive).with(osx_defaults.to_s, '-s')
    expect(CapturePrefs).to receive(:run).with(operation: 'import').and_return(true)

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/osx-defaults.sh not found/)
  end

  it 'records an error when the import fails' do
    allow(CapturePrefs).to receive(:run).with(operation: 'import').and_return(false)

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/Importing the preferences failed/)
  end

  it 'records an error, instead of raising, when the import raises' do
    allow(CapturePrefs).to receive(:run).with(operation: 'import').and_raise('domains list missing')

    result = nil
    expect { expect { result = described_class.run(first_install: true) }.not_to raise_error }.to output(/capture-prefs import failed: domains list missing/).to_stdout
    expect(result).to be false
    expect(Logging.issue_summary_parts.join).to match(/Importing the preferences failed/)
  end
end
