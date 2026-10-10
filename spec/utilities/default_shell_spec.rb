# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'default_shell'

RSpec.describe DefaultShell do
  around do |example|
    Dir.mktmpdir('default-shell-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let!(:zsh) do
    tmp.join('bin', 'zsh').tap do |file|
      file.dirname.mkpath
      file.write("#!/bin/sh\n")
      file.chmod(0o755)
    end
  end
  let(:etc_shells) { tmp.join('shells') }
  let(:ok_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failed_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOMEBREW_PREFIX', tmp)
    stub_const('EnvVars::HOME', tmp)
    stub_const('DefaultShell::ETC_SHELLS', etc_shells)
    etc_shells.write("/bin/zsh\n")
    allow(CommandUtils).to receive(:query).with('dscl', '.', '-read', tmp.to_s, 'UserShell').and_return('UserShell: /bin/zsh')
    allow(CommandUtils).to receive(:run_interactive).with('chsh', '-s', zsh.to_s).and_return(true)
    allow(Open3).to receive(:capture3).and_return(['', '', ok_status])
  end

  after { Logging.state.reset! }

  def run_quietly
    original = $stdout
    $stdout = StringIO.new
    described_class.run
  ensure
    $stdout = original
  end

  it 'registers the shell in /etc/shells and runs chsh when neither is done yet' do
    expect(Open3).to receive(:capture3).with('sudo', 'tee', '-a', etc_shells.to_s, stdin_data: "#{zsh}\n").and_return(['', '', ok_status])
    expect(CommandUtils).to receive(:run_interactive).with('chsh', '-s', zsh.to_s).and_return(true)

    expect(run_quietly).to be true
  end

  it 'does nothing when the shell is listed and already the login shell' do
    etc_shells.write("/bin/zsh\n#{zsh}\n")
    allow(CommandUtils).to receive(:query).and_return("UserShell: #{zsh}")
    expect(Open3).not_to receive(:capture3)
    expect(CommandUtils).not_to receive(:run_interactive)

    expect(run_quietly).to be true
  end

  it 'still repairs /etc/shells when the login shell is already configured' do
    allow(CommandUtils).to receive(:query).and_return("UserShell: #{zsh}")
    expect(Open3).to receive(:capture3).with('sudo', 'tee', '-a', etc_shells.to_s, stdin_data: "#{zsh}\n").and_return(['', '', ok_status])
    expect(CommandUtils).not_to receive(:run_interactive)

    expect(run_quietly).to be true
  end

  it 'records an error and returns false when Homebrew zsh is missing' do
    zsh.delete

    expect(run_quietly).to be false
    expect(Logging.issue_summary_parts).not_to be_empty
  end

  it 'records a warning and returns false when chsh fails' do
    etc_shells.write("#{zsh}\n")
    allow(CommandUtils).to receive(:run_interactive).with('chsh', '-s', zsh.to_s).and_return(false)

    expect(run_quietly).to be false
    expect(Logging.issue_summary_parts).not_to be_empty
  end

  it 'returns false when /etc/shells cannot be updated, even if chsh then succeeds' do
    allow(Open3).to receive(:capture3).and_return(['', 'denied', failed_status])

    expect(run_quietly).to be false
  end
end
