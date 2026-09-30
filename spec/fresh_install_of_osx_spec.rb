# frozen_string_literal: true

require_relative '../scripts/fresh-install-of-osx'

RSpec.describe FreshInstallOfOsx do
  before do
    Logging.state.reset!
    allow(Cron).to receive(:suspend_cron)
    allow(Cron).to receive(:resume_cron)
    allow(MacOS).to receive(:notify)
  end

  after { Logging.state.reset! }

  it 'can be required without starting the installation' do
    expect(described_class).to respond_to(:run, :report_outcome)
    expect(described_class).not_to respond_to(:_install)
  end

  describe '.run' do
    it 'returns true after a complete run, printing the completion message, and restores cron' do
      allow(described_class).to receive(:_install)

      expect { expect(described_class.run).to be true }.to output(/Finished auto installation process/).to_stdout
      expect(Cron).to have_received(:suspend_cron).ordered
      expect(Cron).to have_received(:resume_cron).ordered
    end

    it 'returns false, with no extra message, when a helper aborted' do
      allow(described_class).to receive(:_install).and_raise(described_class::Aborted)

      expect { expect(described_class.run).to be false }.not_to output.to_stderr
      expect(Cron).to have_received(:resume_cron)
    end

    it 'returns false, reports the exception and still restores cron on an unhandled error' do
      allow(described_class).to receive(:_install).and_raise('boom')

      expect { expect(described_class.run).to be false }.to output(/Installation failed with unhandled exception: boom/).to_stderr
      expect(Cron).to have_received(:resume_cron)
    end
  end

  describe '.report_outcome' do
    it 'sends a failure notification carrying the exception message after a failed run' do
      allow(described_class).to receive(:_install).and_raise('boom')
      expect { described_class.run }.to output.to_stderr

      described_class.report_outcome(success: false)

      expect(MacOS).to have_received(:notify).with(/boom/, '❌ Error')
    end

    it 'sends a generic failure notification when the run aborted without a message' do
      allow(described_class).to receive(:_install).and_raise(described_class::Aborted)
      described_class.run

      described_class.report_outcome(success: false)

      expect(MacOS).to have_received(:notify).with(/Installation failed\. Check for error messages above\./, '❌ Error')
    end

    it 'reminds about the manual steps and reports a clean success' do
      expect { described_class.report_outcome(success: true) }.to output(/Review System Settings manually/).to_stdout

      expect(MacOS).to have_received(:notify).with('Fresh install completed successfully.', '✅ Fresh Install Done')
    end

    it 'folds recorded warnings and errors into a single notification' do
      Logging.script_name = 'demo'
      expect do
        Logging.record_warning('careful')
        Logging.record_error('bad')
      end.to output.to_stdout

      expect { described_class.report_outcome(success: true) }.to output.to_stdout

      expect(MacOS).to have_received(:notify).with(/\AInstall done -- 1 error\(s\): .*bad \| 1 warning\(s\): .*careful\z/, '⚠️ Fresh Install')
    end
  end

  describe 'helpers' do
    it 'builds the cache-busting curl headers only when CACHE_BUST_HEADERS is set' do
      with_env('CACHE_BUST_HEADERS' => nil) { expect(described_class.send(:_cache_bust_headers)).to eq([]) }
      with_env('CACHE_BUST_HEADERS' => '1') do
        expect(described_class.send(:_cache_bust_headers)).to include('Pragma: no-cache', 'Expires: 0')
      end
    end

    it 'downloads with the headers, the retry options and the target file in order' do
      with_env('CACHE_BUST_HEADERS' => nil) do
        expect(CommandUtils).to receive(:run_interactive)
                                  .with('curl', '--retry', '5', '-fsSL', 'http://example.test/x', '-o', '/tmp/x').and_return(true)

        expect(described_class.send(:_curl_download, 'http://example.test/x', Pathname.new('/tmp/x'), %w[--retry 5])).to be true
      end
    end

    it 'numbers the steps from the shared counter' do
      described_class.instance_variable_set(:@steps, StepCounter.new(3))

      expect(described_class.send(:_numbered_step_label, 'First')).to eq("#{"[#{'Step 1 of 3'.purple}] "}First")
    end

    describe '._baseline_preferences' do
      it 'runs OsxDefaults in silent mode as a module call and reports success' do
        expect(OsxDefaults).to receive(:run).with(silent: true).and_return(true)

        expect { described_class.send(:_baseline_preferences) }.to output(/Successfully baselined preferences/).to_stdout
        expect(Logging.step_errors).to be_empty
      end

      it 'records an error when the baseline reports failure' do
        allow(OsxDefaults).to receive(:run).and_return(false)

        expect { described_class.send(:_baseline_preferences) }.to output.to_stdout
        expect(Logging.step_errors.last).to match(/osx-defaults failed -- baseline preferences manually/)
      end

      it 'records an exception instead of aborting the install' do
        allow(OsxDefaults).to receive(:run).and_raise('no sudo')

        expect { expect { described_class.send(:_baseline_preferences) }.not_to raise_error }.to output.to_stdout
        expect(Logging.step_errors.last).to match(/osx-defaults failed \(no sudo\)/)
      end
    end

    it 'records a warning instead of raising when the zsh configs could not be loaded' do
      allow(CommandUtils).to receive(:run_interactive).and_return(false)

      expect { described_class.send(:_load_zsh_configs) }.to output.to_stdout
      expect(Logging.step_warnings.last).to match(/Failed to load the zsh configs/)
    end
  end
end
