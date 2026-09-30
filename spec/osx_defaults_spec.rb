# frozen_string_literal: true

require 'tmpdir'
require_relative '../scripts/osx-defaults'

RSpec.describe OsxDefaults do
  before do
    Logging.state.reset!
    described_class.instance_variable_set(:@silent, true)
  end

  after do
    Logging.state.reset!
    described_class.instance_variable_set(:@silent, nil)
  end

  it 'can be required without applying any setting' do
    expect(described_class).to respond_to(:run, :check_terminal, :report_outcome)
    expect(described_class).not_to respond_to(:_apply_settings)
  end

  describe '.check_terminal' do
    it 'is always true in silent mode' do
      allow($stdin).to receive(:tty?).and_return(false)

      expect(described_class.check_terminal(silent: true)).to be true
    end

    it 'is true on a terminal and false, with an explanation, when there is none' do
      allow(EnvVars).to receive(:force_color?).and_return(false)
      allow($stdin).to receive(:tty?).and_return(true)
      expect(described_class.check_terminal).to be true

      allow($stdin).to receive(:tty?).and_return(false)
      expect { expect(described_class.check_terminal).to be false }.to output(/Interactive mode requires a terminal/).to_stdout
    end
  end

  describe '.run' do
    def stub_lifecycle(events)
      allow(CommandUtils).to receive(:run_interactive).with('sudo', '-v') do
        events << :sudo
        true
      end
      allow(described_class).to receive(:_run) do
        events << :close_prefs
        true
      end
      allow(MacOS).to receive(:kill_login_item_apps) { events << :kill_apps }
      allow(MacOS).to receive(:suspend_softwareupdate_schedule) { events << :suspend_updates }
      allow(MacOS).to receive(:restart_login_item_apps) { events << :restart_apps }
      allow(MacOS).to receive(:resume_softwareupdate_schedule) { events << :resume_updates }
    end

    it 'stops the login items and suspends updates, applies the settings, then restores both' do
      events = []
      stub_lifecycle(events)
      allow(described_class).to receive(:_apply_settings) { events << :apply }

      expect { expect(described_class.run(silent: true)).to be true }.to output.to_stdout

      expect(events).to eq(%i[sudo close_prefs kill_apps suspend_updates apply restart_apps resume_updates])
    end

    it 'records an unexpected failure, still restores everything, and does not fail the run' do
      events = []
      stub_lifecycle(events)
      allow(described_class).to receive(:_apply_settings).and_raise('plist exploded')

      expect { expect(described_class.run(silent: true)).to be true }.to output(/plist exploded/).to_stderr.and output.to_stdout

      expect(Logging.step_errors.last).to match(/Unexpected failure in osx-defaults\.rb: plist exploded/)
      expect(events.last(2)).to eq(%i[restart_apps resume_updates])
    end

    it 'restores the login items and update schedule even when suspending them fails' do
      events = []
      stub_lifecycle(events)
      allow(MacOS).to receive(:suspend_softwareupdate_schedule).and_raise('no sudo')

      expect { expect { described_class.run(silent: true) }.to raise_error('no sudo') }.to output.to_stdout

      expect(events.last(2)).to eq(%i[restart_apps resume_updates])
    end

    it 'does nothing and returns false when an interactive run has no terminal' do
      allow(EnvVars).to receive(:force_color?).and_return(false)
      allow($stdin).to receive(:tty?).and_return(false)
      expect(MacOS).not_to receive(:kill_login_item_apps)

      expect { expect(described_class.run(silent: false)).to be false }.to output.to_stdout
    end
  end

  describe '.report_outcome' do
    it 'sends no notification when nothing was recorded' do
      expect(MacOS).not_to receive(:notify)

      described_class.report_outcome
    end

    it 'counts the errors and warnings in one notification' do
      Logging.script_name = 'demo'
      expect do
        Logging.record_warning('w')
        Logging.record_error('e1')
        Logging.record_error('e2')
      end.to output.to_stdout

      expect(MacOS).to receive(:notify).with('osx-defaults.rb: completed with 2 error(s) and 1 warning(s).', /osx-defaults\.rb/)

      described_class.report_outcome
    end
  end

  describe 'helpers' do
    it 'answers every question with its default in silent mode' do
      expect(described_class.send(:_ask, 'q', 'Y')).to be true
      expect(described_class.send(:_ask, 'q', 'N')).to be false
      expect(described_class.send(:_ask, 'q')).to be true
    end

    it 'reads the answer from the terminal in interactive mode' do
      described_class.instance_variable_set(:@silent, false)
      allow($stdin).to receive(:gets).and_return("maybe\n", "n\n")

      expect { expect(described_class.send(:_ask, 'q', 'Y')).to be false }.to output.to_stdout
    end

    it 'sets an existing PlistBuddy key without adding it' do
      allow(CommandUtils).to receive(:run_silent).and_return(true)
      expect(described_class).not_to receive(:_pb)

      expect(described_class.send(:_pb_set_or_add, '/p.plist', ':k', 'v', 'string')).to be true
    end

    it 'refuses to add a missing PlistBuddy key without a type' do
      allow(CommandUtils).to receive(:run_silent).and_return(false)
      expect(described_class).not_to receive(:_pb)

      expect { expect(described_class.send(:_pb_set_or_add, '/p.plist', ':k', 'v', '')).to be false }.to output.to_stdout
      expect(Logging.step_errors.last).to match(/type required for Add when Set fails/)
    end

    describe '._write_user_js' do
      around do |example|
        Dir.mktmpdir('osx-defaults-spec-') do |dir|
          @root = Pathname.new(dir)
          example.run
        end
      end

      it 'does nothing when the profiles directory is absent' do
        expect { described_class.send(:_write_user_js, @root.join('missing')) }.not_to raise_error
      end

      it 'writes user.js into every profile directory, in order' do
        %w[b a].each { |name| @root.join(name).mkpath }
        @root.join('stray-file').write('x')

        expect { described_class.send(:_write_user_js, @root) }.to output(/Wrote user.js/).to_stdout

        expect(@root.join('a', 'user.js').read).to eq(OsxDefaults::FIREFOX_USER_JS)
        expect(@root.join('b', 'user.js')).to exist
        expect(@root.join('stray-file', 'user.js')).not_to exist
      end

      it 'records the failed profile and carries on with the next one' do
        @root.join('a').mkpath
        @root.join('b').mkpath
        @root.join('a').chmod(0o555)

        begin
          expect { described_class.send(:_write_user_js, @root) }.to output.to_stdout
        ensure
          @root.join('a').chmod(0o755)
        end

        expect(Logging.step_errors.last).to match(/Failed to write user.js in/)
        expect(@root.join('b', 'user.js')).to exist
      end
    end
  end
end
