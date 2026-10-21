# encoding: utf-8
# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'preferences_restore'

RSpec.describe PreferencesRestore do
  around do |example|
    Dir.mktmpdir('prefs-restore-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:scripts) { @tmp.join('scripts') }
  let(:osx_defaults) { scripts.join('osx-defaults.sh') }
  let(:events) { [] }
  let(:bracketed) { PreferencesRestore::BRACKETED_ENV }
  let(:git) { instance_double(GitProcessor) }
  let(:git_ok) { instance_double(Process::Status, success?: true) }

  def reset_state
    %i[@baseline_job @bracket_open @apps_stopped].each { |ivar| described_class.instance_variable_set(ivar, nil) }
  end

  before do
    Logging.state.reset!
    reset_state
    stub_const('EnvVars::DOTFILES_DIR', @tmp)
    stub_const('EnvVars::HOME', @tmp)
    stub_const('PreferencesRestore::BASELINE_LOG', @tmp.join('baseline.log'))
    scripts.mkpath
    osx_defaults.write("#!/bin/sh\n")
    osx_defaults.chmod(0o755)
    allow(Core).to receive(:running_in_tty?).and_return(true)
    allow(MacOS).to receive(:suspend_softwareupdate_schedule) { events << :suspend }
    allow(MacOS).to receive(:kill_login_item_apps) { events << :kill_apps }
    allow(MacOS).to receive(:reload_macos_prefs) { events << :reload }
    allow(MacOS).to receive(:restart_login_item_apps) { events << :restart_apps }
    allow(MacOS).to receive(:resume_softwareupdate_schedule) { events << :resume }
    allow(CommandUtils).to receive(:run_interactive).and_return(true)
    allow(CommandUtils).to receive(:run_silent).and_return(true)
    allow(CapturePrefs).to receive(:run).and_return(true)
    allow(CapturePrefs).to receive(:last_export_time).and_return(nil)
    allow(CapturePrefs).to receive(:defaults_dir).and_return(@tmp.join('configs', 'defaults'))
    allow(GitProcessor).to receive(:new).and_return(git)
    allow(git).to receive(:run_alias).and_return(['', '', git_ok])
  end

  after do
    reset_state
    Logging.state.reset!
  end

  def run_quietly(**kwargs)
    original = $stdout
    $stdout = StringIO.new
    described_class.run(**kwargs)
  ensure
    $stdout = original
  end

  context 'on a vanilla macOS' do
    it 'baselines the defaults and imports the backup, without exporting first' do
      expect(CommandUtils).to receive(:run_interactive).with(bracketed, osx_defaults.to_s, '-s').ordered.and_return(true)
      expect(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).ordered.and_return(true)
      expect(CapturePrefs).not_to receive(:run).with(operation: 'export', manage_apps: false)

      expect(run_quietly(first_install: true)).to be true
    end
  end

  describe 'the one bracket around the baseline and the import' do
    it 'suspends and stops once before, and reloads, restarts and resumes once after' do
      allow(CommandUtils).to receive(:run_interactive) do
        events << :baseline
        true
      end
      allow(CapturePrefs).to receive(:run) do |operation:, **|
        events << operation.to_sym
        true
      end

      run_quietly(first_install: true)

      expect(events).to eq(%i[suspend kill_apps baseline import reload restart_apps resume])
    end

    it 'never lets the children bracket on their own' do
      expect(CapturePrefs).to receive(:run).with(hash_including(manage_apps: false)).and_return(true)

      run_quietly(first_install: true)
    end

    it 'leaves the apps alone when not interactive, but still suspends, reloads and resumes' do
      allow(Core).to receive(:running_in_tty?).and_return(false)

      run_quietly(first_install: true)

      expect(events).to eq(%i[suspend reload resume])
    end

    it 'closes the bracket even when the import raises' do
      allow(CapturePrefs).to receive(:run).and_raise(Interrupt)

      expect { run_quietly(first_install: true) }.to raise_error(Interrupt)

      expect(events).to eq(%i[suspend kill_apps reload restart_apps resume])
    end

    it 'does not leave the bracket open for the next run' do
      run_quietly(first_install: true)
      events.clear

      run_quietly(first_install: true)

      expect(events).to eq(%i[suspend kill_apps reload restart_apps resume])
    end
  end

  context 'on a pre-configured machine' do
    it 'refreshes the backup and skips the import, which would only re-import what was just exported' do
      expect(CommandUtils).to receive(:run_interactive).with(bracketed, osx_defaults.to_s, '-s').ordered.and_return(true)
      expect(CapturePrefs).to receive(:run).with(operation: 'export', manage_apps: false).ordered.and_return(true)
      expect(CapturePrefs).not_to receive(:run).with(operation: 'import', manage_apps: false)

      expect { expect(described_class.run(first_install: false)).to be true }.to output(/Skipping the import/).to_stdout
    end

    it 'still imports, records a warning and returns false when the refresh fails' do
      allow(CapturePrefs).to receive(:run).with(operation: 'export', manage_apps: false).and_return(false)
      expect(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_return(true)

      expect(run_quietly).to be false
      expect(Logging.issue_summary_parts.join).to match(/Failed to refresh backup/)
    end

    it 'still imports when the refresh raises, printing why' do
      allow(CapturePrefs).to receive(:run).with(operation: 'export', manage_apps: false).and_raise('no git repo')
      expect(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_return(true)

      result = nil
      expect { result = described_class.run }.to output(/capture-prefs export failed: no git repo/).to_stdout
      expect(result).to be false
    end

    context 'when this machine has exported before' do
      let(:last_export) { Time.at(1_700_000_000) }

      before { allow(CapturePrefs).to receive(:last_export_time).and_return(last_export) }

      def backup_committed_at(time)
        allow(git).to receive(:run_alias).with('log', '-1', '--format=%ct', '--', @tmp.join('configs', 'defaults').to_s, read_only: true)
                                         .and_return(["#{time.to_i}\n", '', git_ok])
      end

      it 'imports a backup committed after that export (pulled from elsewhere) and never exports over it' do
        backup_committed_at(last_export + 3600)
        expect(CapturePrefs).not_to receive(:run).with(operation: 'export', manage_apps: false)
        expect(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_return(true)

        expect { expect(described_class.run(first_install: false)).to be true }.to output(/newer than this machine's last export/).to_stdout
      end

      it 'exports, and skips the import, when the backup is older than that export' do
        backup_committed_at(last_export - 3600)
        expect(CapturePrefs).to receive(:run).with(operation: 'export', manage_apps: false).and_return(true)
        expect(CapturePrefs).not_to receive(:run).with(operation: 'import', manage_apps: false)

        expect(run_quietly(first_install: false)).to be true
      end

      it 'exports when the backup was committed in the very second of the export' do
        backup_committed_at(last_export)
        expect(CapturePrefs).to receive(:run).with(operation: 'export', manage_apps: false).and_return(true)

        expect(run_quietly(first_install: false)).to be true
      end

      it 'exports when the age of the backup cannot be read' do
        allow(git).to receive(:run_alias).with('log', any_args).and_return(['', 'fatal', instance_double(Process::Status, success?: false)])
        expect(CapturePrefs).to receive(:run).with(operation: 'export', manage_apps: false).and_return(true)

        expect(run_quietly(first_install: false)).to be true
      end

      it 'exports when the git lookup raises' do
        allow(git).to receive(:run_alias).with('log', any_args).and_raise('git gone')
        expect(CapturePrefs).to receive(:run).with(operation: 'export', manage_apps: false).and_return(true)

        expect(run_quietly(first_install: false)).to be true
      end
    end

    it 'exports without comparing when this machine never exported (the age of the backup is unknown)' do
      expect(git).not_to receive(:run_alias)
      expect(CapturePrefs).to receive(:run).with(operation: 'export', manage_apps: false).and_return(true)

      expect(run_quietly(first_install: false)).to be true
    end
  end

  it 'takes first_install from the FIRST_INSTALL environment variable when not given' do
    expect(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_return(true)
    expect(CapturePrefs).not_to receive(:run).with(operation: 'export', manage_apps: false)

    with_env('FIRST_INSTALL' => '1') { expect(run_quietly).to be true }
  end

  it 'records an error and carries on to the import when the baseline fails' do
    allow(CommandUtils).to receive(:run_interactive).with(bracketed, osx_defaults.to_s, '-s').and_return(false)
    expect(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_return(true)

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/osx-defaults.sh exited non-zero/)
  end

  it 'records an error and skips the baseline when osx-defaults.sh is missing' do
    osx_defaults.delete
    expect(CommandUtils).not_to receive(:run_interactive)
    expect(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_return(true)

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/osx-defaults.sh not found/)
  end

  it 'records an error when the import fails' do
    allow(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_return(false)

    expect(run_quietly(first_install: true)).to be false
    expect(Logging.issue_summary_parts.join).to match(/Importing the preferences failed/)
  end

  it 'records an error, instead of raising, when the import raises' do
    allow(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_raise('domains list missing')

    result = nil
    expect { expect { result = described_class.run(first_install: true) }.not_to raise_error }.to output(/capture-prefs import failed: domains list missing/).to_stdout
    expect(result).to be false
    expect(Logging.issue_summary_parts.join).to match(/Importing the preferences failed/)
  end

  describe 'the baseline in the background' do
    let(:log) { PreferencesRestore::BASELINE_LOG }

    before do
      stub_const('PreferencesRestore::BASELINE_POLL', 0.02)
      stub_const('PreferencesRestore::BASELINE_TICK', 0.1)
    end

    def start_quietly
      original = $stdout
      $stdout = StringIO.new
      described_class.start_baseline_in_background
    ensure
      $stdout = original
    end

    it 'starts it with the bracket env and -s, output going to the log, and does not wait for it' do
      osx_defaults.write("#!/bin/sh\nsleep 0.2\necho \"args=$* bracketed=$DOTFILES_APPS_BRACKETED\"\n")
      allow(CommandUtils).to receive(:run_silent).with('sudo', '-n', 'true').and_return(true)

      started = Time.now
      expect(start_quietly).to be true

      expect(Time.now - started).to be < 0.15
      expect(events).to eq(%i[suspend kill_apps])
      described_class.finish_pending
      expect(log.read).to include('args=-s bracketed=1')
    end

    it 'is joined by run before the import, replaying its summary, and the bracket is closed once, after both' do
      osx_defaults.write("#!/bin/sh\necho 'baseline line'\necho 'Summary: all done'\n")
      allow(CapturePrefs).to receive(:run) do |operation:, **|
        events << operation.to_sym
        true
      end
      start_quietly
      events << :started

      result = nil
      output = StringIO.new
      original = $stdout
      $stdout = output
      begin
        result = described_class.run(first_install: true)
      ensure
        $stdout = original
      end

      expect(result).to be true
      expect(output.string).to include('baseline line', 'Summary: all done', 'Successfully baselined preferences')
      expect(CommandUtils).not_to have_received(:run_interactive)
      expect(events).to eq(%i[suspend kill_apps started import reload restart_apps resume])
    end

    it 'records an error naming the log when the background baseline failed' do
      osx_defaults.write("#!/bin/sh\necho boom\nexit 3\n")
      start_quietly

      expect(run_quietly(first_install: true)).to be false
      # The actual error message has a simple path (no escaped backslash), ANSI escapes are removed
      expect(Logging.issue_summary_parts.join).to match(%r{osx-defaults\.sh exited non-zero \(see '/var/.*baseline\.log'\)})
    end

    it 'still imports after a failed baseline' do
      osx_defaults.write("#!/bin/sh\nexit 3\n")
      start_quietly
      expect(CapturePrefs).to receive(:run).with(operation: 'import', manage_apps: false).and_return(true)

      run_quietly(first_install: true)
    end

    it 'stops a baseline that does not finish in time, and records an error' do
      stub_const('PreferencesRestore::BASELINE_TIMEOUT', 0.3)
      osx_defaults.write("#!/bin/sh\nsleep 30\n")
      start_quietly

      expect(run_quietly(first_install: true)).to be false
      expect(Logging.issue_summary_parts.join).to match(/did not finish within/)
    end

    it 'does not start in the background with FRESH_INSTALL_SERIAL_DEFAULTS, and run then baselines inline' do
      with_env('FRESH_INSTALL_SERIAL_DEFAULTS' => '1') do
        expect(start_quietly).to be false
        expect(events).to be_empty

        expect(CommandUtils).to receive(:run_interactive).with(bracketed, osx_defaults.to_s, '-s').and_return(true)
        expect(run_quietly(first_install: true)).to be true
      end
    end

    it 'does not start in the background without cached sudo credentials' do
      allow(CommandUtils).to receive(:run_silent).with('sudo', '-n', 'true').and_return(false)

      expect(start_quietly).to be false
      expect(events).to be_empty
    end

    it 'does not start in the background when osx-defaults.sh is missing' do
      osx_defaults.delete

      expect(start_quietly).to be false
    end

    it 'does not start in the background when the command cannot be started, and closes the bracket again' do
      allow(BackgroundJob).to receive(:start).and_return(nil)

      expect(start_quietly).to be false
      expect(events).to eq(%i[suspend kill_apps reload restart_apps resume])
    end

    it 'finish_pending waits for the baseline and closes the bracket when the run stopped early' do
      osx_defaults.write("#!/bin/sh\nsleep 0.2\necho finished\n")
      start_quietly

      original = $stdout
      $stdout = StringIO.new
      begin
        described_class.finish_pending
      ensure
        $stdout = original
      end

      expect(log.read).to include('finished')
      expect(events).to eq(%i[suspend kill_apps reload restart_apps resume])
    end

    it 'finish_pending is a no-op when nothing was started' do
      described_class.finish_pending

      expect(events).to be_empty
    end
  end
end
