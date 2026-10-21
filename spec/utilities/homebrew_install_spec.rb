# encoding: utf-8
# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'homebrew_install'

RSpec.describe HomebrewInstall do
  around do |example|
    Dir.mktmpdir('homebrew-install-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:prefix) { @tmp.join('opt', 'homebrew') }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOMEBREW_PREFIX', prefix)
    stub_const('EnvVars::HOME', @tmp)
    stub_const('EnvVars::USER', 'someuser')
    prefix.mkpath
    allow(CommandUtils).to receive(:run_interactive).and_return(true)
    allow(BackgroundJob).to receive(:run_guarded).and_return(:ok)
    allow(EnvVars).to receive(:brew_install_pid).and_return(0)
    allow(EnvVars).to receive(:brew_install_log).and_return(nil)
  end

  after { Logging.state.reset! }

  def run_quietly
    original = $stdout
    $stdout = StringIO.new
    described_class.run
  ensure
    $stdout = original
  end

  def install_fake_brew
    prefix.join('bin').mkpath
    prefix.join('bin', 'brew').tap { |f| f.write("#!/bin/sh\n") }.chmod(0o755)
  end

  describe '.run' do
    it 'does nothing when brew is already installed' do
      install_fake_brew
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(run_quietly).to be true
    end

    it 'prepares the prefix, downloads the installer and runs it non-interactively' do
      expect(CommandUtils).to receive(:run_interactive).with('sudo', 'mkdir', '-p', *%w[tmp repository plugins bin].map { |d| prefix.join(d).to_s }).ordered.and_return(true)
      expect(CommandUtils).to receive(:run_interactive).with('sudo', 'chown', '-fR', 'someuser:admin', prefix.to_s).ordered.and_return(true)
      expect(CommandUtils).to receive(:curl_download).with(%r{\Ahttps://raw\.githubusercontent\.com/Homebrew/install/HEAD/install\.sh\?\d+\z}, String, bootstrap: true, interactive: true).ordered.and_return(true)
      expect(BackgroundJob).to receive(:run_guarded).with({ 'NONINTERACTIVE' => '1' }, 'bash', String, timeout: described_class::INSTALLER_TIMEOUT, inactivity: described_class::INSTALLER_INACTIVITY).ordered.and_return(:ok)

      expect(run_quietly).to be true
    end

    it 'removes the downloaded installer afterwards' do
      path = nil
      allow(CommandUtils).to receive(:run_interactive).with('curl', any_args) do |*args|
        path = args.last
        true
      end

      run_quietly

      expect(path).not_to be_nil
      expect(File).not_to exist(path)
    end

    it 'is false when the directories cannot be created' do
      allow(CommandUtils).to receive(:run_interactive).with('sudo', 'mkdir', any_args).and_return(false)
      expect(CommandUtils).not_to receive(:run_interactive).with('curl', any_args)

      expect(run_quietly).to be false
      expect(Logging.issue_summary_parts).not_to be_empty
    end

    it 'is false when the prefix cannot be chowned' do
      allow(CommandUtils).to receive(:run_interactive).with('sudo', 'chown', any_args).and_return(false)

      expect(run_quietly).to be false
    end

    it 'is false when the download fails, without running the installer' do
      allow(CommandUtils).to receive(:run_interactive).with('curl', any_args).and_return(false)
      expect(BackgroundJob).not_to receive(:run_guarded)

      expect(run_quietly).to be false
    end

    it 'is false when the installer fails' do
      allow(BackgroundJob).to receive(:run_guarded).and_return(:failed)

      expect(run_quietly).to be false
      expect(Logging.issue_summary_parts.join).to match(/Homebrew installation failed/)
    end

    it 'is false, saying why, when the installer ran too long' do
      allow(BackgroundJob).to receive(:run_guarded).and_return(:timeout)

      expect(run_quietly).to be false
      expect(Logging.issue_summary_parts.join).to match(/longer than 30 minutes/)
    end

    it 'is false, saying why, when the installer printed nothing for too long' do
      allow(BackgroundJob).to receive(:run_guarded).and_return(:stalled)

      expect(run_quietly).to be false
      expect(Logging.issue_summary_parts.join).to match(/no output for 10 minutes/)
    end

    it 'is false when HOMEBREW_PREFIX is empty' do
      stub_const('EnvVars::HOMEBREW_PREFIX', Pathname(''))
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(run_quietly).to be false
    end
  end

  describe 'the installer the shell started in the background' do
    let(:log) { @tmp.join('early.log') }
    let(:children) { [] }

    before do
      stub_const('HomebrewInstall::EARLY_INSTALL_TIMEOUT', 0.5)
      stub_const('HomebrewInstall::EARLY_INSTALL_POLL', 0.02)
      stub_const('HomebrewInstall::EARLY_INSTALL_TICK', 0.1)
      allow(EnvVars).to receive(:brew_install_log).and_return(log)
    end

    after { children.each { |pid| kill_quietly(pid) } }

    def kill_quietly(pid)
      Process.kill('KILL', pid)
    rescue SystemCallError
      nil
    end

    # A real child, reaped as soon as it exits (as the shell does) so its pid reads as gone.
    def spawn_child(script)
      pid = Process.spawn('sh', '-c', script)
      Process.detach(pid)
      children << pid
      allow(EnvVars).to receive(:brew_install_pid).and_return(pid)
      pid
    end

    let(:install_brew) { "mkdir -p #{prefix.join('bin')} && touch #{prefix.join('bin', 'brew')} && chmod +x #{prefix.join('bin', 'brew')}" }

    it 'waits for it and uses the brew it installed, without installing again' do
      log.write("==> Downloading and installing Homebrew...\n")
      spawn_child("sleep 0.3; #{install_brew}")
      expect(BackgroundJob).not_to receive(:run_guarded)
      expect(CommandUtils).not_to receive(:run_interactive)

      expect { expect(described_class.run).to be true }.to output(/waiting for it.*by the background installer/m).to_stdout
      expect(prefix.join('bin', 'brew')).to be_executable
    end

    it 'shows the tail of its log while it waits' do
      log.write("==> Cloning Homebrew\n")
      spawn_child("sleep 0.4; #{install_brew}")

      expect { described_class.run }.to output(/Still installing Homebrew in the background.*==> Cloning Homebrew/m).to_stdout
    end

    it 'falls back to its own installation when the job exited without installing brew' do
      log.write("curl: (6) Could not resolve host\n")
      spawn_child('exit 1')
      sleep 0.2
      expect(BackgroundJob).to receive(:run_guarded).and_return(:ok)

      expect { expect(described_class.run).to be true }.to output(/left no brew behind.*Could not resolve host/m).to_stdout
      expect(Logging.issue_summary_parts.join).to match(/left no brew behind/)
    end

    it 'falls back when the job has already gone before it looks' do
      spawn_child('exit 0')
      sleep 0.2
      expect(BackgroundJob).to receive(:run_guarded).and_return(:ok)

      expect(run_quietly).to be true
    end

    it 'stops a job that does not finish in time and installs on its own' do
      pid = spawn_child('sleep 30')
      expect(BackgroundJob).to receive(:run_guarded).and_return(:ok)

      expect(run_quietly).to be true
      expect(BackgroundJob.pid_alive?(pid)).to be false
      expect(Logging.issue_summary_parts.join).to match(/did not finish within/)
    end

    it 'does not wait when FRESH_INSTALL_NO_EARLY_BREW is set' do
      pid = spawn_child('sleep 30')
      expect(BackgroundJob).to receive(:run_guarded).and_return(:ok)

      with_env('FRESH_INSTALL_NO_EARLY_BREW' => '1') { expect(run_quietly).to be true }
      expect(BackgroundJob.pid_alive?(pid)).to be true
    end

    it 'still waits when bin/brew already exists, because the installer is not done with it yet' do
      install_fake_brew
      spawn_child('sleep 0.3')
      expect(BackgroundJob).to receive(:wait_for_pid).and_call_original
      expect(BackgroundJob).not_to receive(:run_guarded)

      expect { expect(described_class.run).to be true }.to output(/by the background installer/).to_stdout
    end

    it 'skips quietly when brew is there and no background installer was started' do
      install_fake_brew
      allow(EnvVars).to receive(:brew_install_pid).and_return(0)

      expect { expect(described_class.run).to be true }.to output(/already installed/).to_stdout
    end
  end
end
