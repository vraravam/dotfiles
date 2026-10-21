# encoding: utf-8
# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'brew_bundle'

RSpec.describe BrewBundle do
  around do |example|
    Dir.mktmpdir('brew-bundle-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let!(:brew) do
    tmp.join('bin', 'brew').tap do |file|
      file.dirname.mkpath
      file.write("#!/bin/sh\n")
      file.chmod(0o755)
    end
  end
  let(:brewfile) { tmp.join('Brewfile') }
  let(:log) { tmp.join('Downloads', 'brew-bundle-full-install.log') }
  let(:job) { BackgroundJob::Job.new(pid: 1, log: log, waiter: waiter) }
  let(:waiter) { instance_double(Thread, alive?: true) }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOMEBREW_PREFIX', tmp)
    stub_const('EnvVars::HOMEBREW_BUNDLE_FILE', brewfile)
    stub_const('BrewBundle::FULL_INSTALL_LOG', log)
    allow(Keybase).to receive(:link_cli_into)
    allow(Brew).to receive(:bundle_check).and_return(false)
    allow(Brew).to receive(:bundle_install).and_return(true)
    allow(described_class).to receive(:bundle_in_background).and_return(job)
    allow(described_class).to receive(:sleep)
    allow(SetupLoginItem).to receive(:register_managed).and_return(true)
  end

  after { Logging.state.reset! }

  def run_quietly(**kwargs)
    original = $stdout
    $stdout = StringIO.new
    described_class.run(**kwargs)
  ensure
    $stdout = original
  end

  describe 'login items' do
    it 'registers the managed login items after the install' do
      expect(Brew).to receive(:bundle_install).ordered.and_return(true)
      expect(SetupLoginItem).to receive(:register_managed).ordered.and_return(true)

      expect(run_quietly(first_install: false)).to be true
    end

    it 'registers them even when the install reported errors, and keeps that failure as the result' do
      allow(Brew).to receive(:bundle_install).and_return(false)
      allow(Logging).to receive(:record_warning)
      expect(SetupLoginItem).to receive(:register_managed).and_return(true)

      expect(run_quietly(first_install: false)).to be false
    end

    it 'does not let a login item failure change the result of the install' do
      allow(SetupLoginItem).to receive(:register_managed).and_return(false)

      expect(run_quietly(first_install: false)).to be true
    end
  end

  context 'on a pre-configured machine' do
    it 'syncs the whole Brewfile with the brew in the Homebrew prefix and starts no background job' do
      expect(Brew).to receive(:bundle_check).with(brew_bin: brew.to_s).and_return(false).ordered
      expect(Brew).to receive(:bundle_install).with(brew_bin: brew.to_s, content: nil).and_return(true).ordered
      expect(described_class).not_to receive(:bundle_in_background)

      expect(run_quietly(first_install: false)).to be true
    end

    it 'reports failure when brew bundle fails, but still runs the Keybase safety net' do
      allow(Brew).to receive(:bundle_install).and_return(false)
      expect(Logging).to receive(:record_warning).with(/bundle install encountered errors/)
      expect(Keybase).to receive(:link_cli_into).with(brew.dirname)

      expect(run_quietly).to be false
    end

    it 'is false, without running anything, when brew is not executable' do
      stub_const('EnvVars::HOMEBREW_PREFIX', tmp.join('missing'))
      expect(Brew).not_to receive(:bundle_check)
      expect(Brew).not_to receive(:bundle_install)

      expect { expect(described_class.run).to be false }.to output(/not executable/).to_stdout
    end
  end

  context 'on a first install' do
    it 'installs the base section first and then the whole Brewfile in the background' do
      brewfile.write("brew 'git'\n# FIRST_INSTALL: stop here\nbrew 'bat'\n")
      expect(Brew).not_to receive(:bundle_check)
      expect(Brew).to receive(:bundle_install).with(brew_bin: brew.to_s, content: "brew 'git'\n").and_return(true).ordered
      expect(described_class).to receive(:bundle_in_background).with(brew_bin: brew.to_s, log: log).and_return(job).ordered

      expect { expect(described_class.run(first_install: true)).to be true }.to output(/Full Brewfile install running in background/).to_stdout
    end

    it 'still starts the background install when the base section fails, and reports the failure' do
      brewfile.write("brew 'git'\n# FIRST_INSTALL: x\n")
      allow(Brew).to receive(:bundle_install).and_return(false)
      expect(described_class).to receive(:bundle_in_background).and_return(job)

      expect(run_quietly(first_install: true)).to be false
    end

    it 'installs a Brewfile without a sentinel whole, with a warning' do
      brewfile.write("brew 'git'\nbrew 'bat'\n")
      expect(Brew).to receive(:bundle_install).with(brew_bin: brew.to_s, content: "brew 'git'\nbrew 'bat'\n").and_return(true)

      expect { described_class.run(first_install: true) }.to output(/No '# FIRST_INSTALL:' sentinel found/).to_stdout
    end

    it 'is false, without running brew, when the Brewfile does not exist' do
      expect(Brew).not_to receive(:bundle_check)
      expect(Brew).not_to receive(:bundle_install)

      expect { expect(described_class.run(first_install: true)).to be false }.to output(/Brewfile not found/).to_stdout
    end

    it 'warns instead of failing when the background job cannot be started' do
      brewfile.write("brew 'git'\n# FIRST_INSTALL: x\n")
      allow(described_class).to receive(:bundle_in_background).and_return(false)

      expect { expect(described_class.run(first_install: true)).to be true }.to output(/Could not start the background Brewfile install/).to_stdout
    end
  end

  describe 'the background full install' do
    before { brewfile.write("brew 'git'\n# FIRST_INSTALL: x\nbrew 'bat'\n") }

    def finish_with(success, exitstatus)
      allow(waiter).to receive(:alive?).and_return(false)
      allow(waiter).to receive(:value).and_return(instance_double(Process::Status, success?: success, exitstatus: exitstatus))
    end

    it 'is :none before anything was started and on a pre-configured machine' do
      run_quietly(first_install: false)

      expect(described_class.full_install_state).to eq(:none)
    end

    it 'reports it as running while the job is alive, without recording an issue' do
      run_quietly(first_install: true)

      expect { expect(described_class.report_full_install).to eq(:running) }.to output(/still running in the background/).to_stdout
      expect(Logging.issue_summary_parts).to be_empty
    end

    it 'records a warning naming the log when the job exited non-zero' do
      run_quietly(first_install: true)
      finish_with(false, 1)

      expect { expect(described_class.report_full_install).to eq(:failed) }.to output.to_stdout
      expect(Logging.issue_summary_parts.join).to match(/background full Brewfile install failed \(exit status 1\).*brew-bundle-full-install\.log/)
    end

    it 'reports success when the job finished cleanly' do
      run_quietly(first_install: true)
      finish_with(true, 0)

      expect { expect(described_class.report_full_install).to eq(:succeeded) }.to output(/finished successfully/).to_stdout
      expect(Logging.issue_summary_parts).to be_empty
    end

    it 'forgets the job of an earlier run' do
      run_quietly(first_install: true)
      run_quietly(first_install: false)

      expect(described_class.full_install_state).to eq(:none)
    end
  end

  describe 'retrying the install' do
    it 'does not run the full-file check when installing the base section, and streams it on stdin' do
      brewfile.write("brew 'git'\n# FIRST_INSTALL: x\n")
      expect(Brew).not_to receive(:bundle_check)
      expect(Brew).to receive(:bundle_install).with(brew_bin: brew.to_s, content: "brew 'git'\n").and_return(true)

      expect(run_quietly(first_install: true)).to be true
    end

    it 'retries a failed install once after the pause, and succeeds when the retry does' do
      expect(Brew).to receive(:bundle_install).twice.and_return(false, true)
      expect(described_class).to receive(:sleep).with(described_class::INSTALL_RETRY_DELAY).once

      expect(run_quietly(first_install: false)).to be true
    end

    it 'gives up after the retries are used up' do
      expect(Brew).to receive(:bundle_install).exactly(1 + described_class::INSTALL_RETRIES).times.and_return(false)
      allow(Logging).to receive(:record_warning)

      expect(run_quietly(first_install: false)).to be false
    end

    it 'does not install when the full-file check already passes' do
      allow(Brew).to receive(:bundle_check).and_return(true)
      expect(Brew).not_to receive(:bundle_install)

      expect(run_quietly(first_install: false)).to be true
    end
  end

  describe '.base_brewfile_content' do
    def sentinel_file(text)
      tmp.join('Sentinel').tap { |file| file.write(text) }
    end

    it 'returns everything above the sentinel comment, without the sentinel itself' do
      file = sentinel_file("brew 'git'\ncask 'iterm2'\n\n# FIRST_INSTALL: install only the above first\nbrew 'bat'\n")

      expect(described_class.base_brewfile_content(file)).to eq("brew 'git'\ncask 'iterm2'\n\n")
    end

    it 'matches the sentinel although it is a comment (comment lines are not skipped)' do
      file = sentinel_file("# a header comment\nbrew 'git'\n# FIRST_INSTALL: here\nbrew 'bat'\n")

      expect(described_class.base_brewfile_content(file)).to eq("# a header comment\nbrew 'git'\n")
    end

    it 'does not treat other mentions of FIRST_INSTALL as the sentinel' do
      file = sentinel_file("# see FIRST_INSTALL below\nbrew 'git'\nputs 'FIRST_INSTALL'\n# FIRST_INSTALL: stop\nbrew 'bat'\n")

      expect(described_class.base_brewfile_content(file)).to eq("# see FIRST_INSTALL below\nbrew 'git'\nputs 'FIRST_INSTALL'\n")
    end

    it 'is nil when the Brewfile has no sentinel' do
      expect(described_class.base_brewfile_content(sentinel_file("brew 'git'\n"))).to be_nil
    end

    it 'reads UTF-8 content' do
      file = sentinel_file("# caf\u00e9\nbrew 'git'\n# FIRST_INSTALL: x\n")

      expect(described_class.base_brewfile_content(file)).to eq("# caf\u00e9\nbrew 'git'\n")
    end
  end

  describe '.bundle_in_background' do
    before { allow(described_class).to receive(:bundle_in_background).and_call_original }

    it 'starts a detached full bundle with FIRST_INSTALL emptied, appending to the log' do
      fake = tmp.join('fake-brew')
      fake.write("#!/bin/sh\necho \"args=$* first_install=[${FIRST_INSTALL-unset}]\"\n")
      fake.chmod(0o755)
      out_log = tmp.join('logs', 'bundle.log')

      started = nil
      with_env('FIRST_INSTALL' => '1') do
        started = described_class.bundle_in_background(brew_bin: fake.to_s, log: out_log)
      end

      expect(started).to be_a(BackgroundJob::Job)
      expect(started.waiter.value).to be_success
      expect(out_log.read).to include('args=bundle', 'first_install=[]')
    end

    it 'gives the caller a job whose failure it can see later' do
      fake = tmp.join('fake-brew')
      fake.write("#!/bin/sh\nexit 3\n")
      fake.chmod(0o755)

      started = described_class.bundle_in_background(brew_bin: fake.to_s, log: tmp.join('bundle.log'))

      expect(BackgroundJob.wait(started, timeout: 5, poll: 0.05).exitstatus).to eq(3)
    end

    it 'is nil when the brew binary cannot be started' do
      expect(described_class.bundle_in_background(brew_bin: tmp.join('missing').to_s, log: tmp.join('bundle.log'))).to be_nil
    end
  end
end
