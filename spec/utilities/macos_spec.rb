# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'macos'

RSpec.describe MacOS do
  describe '.load_brew_shellenv' do
    around do |example|
      Dir.mktmpdir('macos-spec-') do |dir|
        @tmp = Pathname(dir)
        example.run
      end
    end

    # A fake brew whose 'shellenv' exports one variable, even when the path to it contains a space.
    def fake_brew(dir_name)
      dir = @tmp.join(dir_name)
      dir.mkpath
      brew = dir.join('brew')
      brew.write("#!/bin/sh\necho 'export MACOS_SPEC_BREW_VAR=from-brew'\n")
      brew.chmod(0o755)
      brew
    end

    around do |example|
      with_env('MACOS_SPEC_BREW_VAR' => nil) { example.run }
    end

    it 'merges the variables brew shellenv exports into this process' do
      described_class.load_brew_shellenv(fake_brew('bin'))

      expect(ENV['MACOS_SPEC_BREW_VAR']).to eq('from-brew')
    end

    it 'handles a brew path containing spaces' do
      described_class.load_brew_shellenv(fake_brew('with space'))

      expect(ENV['MACOS_SPEC_BREW_VAR']).to eq('from-brew')
    end

    it 'does not copy back variables the throwaway shell changes by itself' do
      with_env('SHLVL' => '7') do
        described_class.load_brew_shellenv(fake_brew('bin'))

        expect(ENV['SHLVL']).to eq('7')
      end
    end

    it 'does nothing when brew is not executable' do
      described_class.load_brew_shellenv(@tmp.join('missing', 'brew'))

      expect(ENV['MACOS_SPEC_BREW_VAR']).to be_nil
    end
  end

  describe '.running_processes' do
    it 'asks pgrep once, with escaped alternation, and keeps only listed names in input order' do
      expect(CommandUtils).to receive(:query)
          .with('pgrep', '-lx', 'Brave Browser|a\\.b\\(c\\)|NoSuchApp')
          .and_return("12 a.b(c)\n34 Brave Browser\n")

      expect(described_class.running_processes(['Brave Browser', 'a.b(c)', 'NoSuchApp'])).to eq(['Brave Browser', 'a.b(c)'])
    end

    it 'does not fork for an empty list' do
      expect(CommandUtils).not_to receive(:query)

      expect(described_class.running_processes([])).to eq([])
    end

    it 'lists only the running processes (real pgrep)' do
      expect(described_class.running_processes(%w[NoSuchAppDotfilesSpec AnotherMissingOne])).to eq([])
    end
  end

  describe '.kill_login_item_apps' do
    before do
      allow(described_class).to receive(:sleep)
      allow(Logging).to receive(:debug)
      allow(Logging).to receive(:warn)
      allow(CommandUtils).to receive(:run_silent).and_return(true)
    end

    it 'terminates the running apps with one killall, one wait and one re-check' do
      allow(described_class).to receive(:running_processes).with(MacOS::LOGIN_ITEM_APPS).and_return(%w[Clocker Thaw])
      expect(described_class).to receive(:running_processes).with(%w[Clocker Thaw]).once.and_return([])
      expect(CommandUtils).to receive(:run_silent).with('killall', '-TERM', 'Clocker', 'Thaw').once.and_return(true)
      expect(CommandUtils).to receive(:run_silent).with('killall', 'Finder')
      expect(described_class).to receive(:sleep).with(2).once
      expect(described_class).to receive(:sleep).with(1).once

      described_class.kill_login_item_apps
    end

    it 'force-kills only the survivors, and warns about each' do
      allow(described_class).to receive(:running_processes).with(MacOS::LOGIN_ITEM_APPS).and_return(%w[Clocker Thaw])
      allow(described_class).to receive(:running_processes).with(%w[Clocker Thaw]).and_return(['Thaw'])
      expect(Logging).to receive(:warn).with(/Thaw.*did not terminate gracefully/)
      expect(CommandUtils).to receive(:run_silent).with('killall', '-9', 'Thaw')

      described_class.kill_login_item_apps
    end

    it 'does not wait at all when no app is running' do
      allow(described_class).to receive(:running_processes).and_return([])
      expect(described_class).not_to receive(:sleep)
      expect(CommandUtils).not_to receive(:run_silent).with('killall', '-TERM', any_args)
      expect(CommandUtils).to receive(:run_silent).with('killall', 'Finder')

      described_class.kill_login_item_apps
    end

    it 'signals apps one by one when the batch killall fails, reporting only those still running' do
      allow(described_class).to receive(:running_processes).with(MacOS::LOGIN_ITEM_APPS).and_return(%w[Clocker Thaw])
      allow(CommandUtils).to receive(:run_silent).with('killall', '-TERM', 'Clocker', 'Thaw').and_return(false)
      allow(CommandUtils).to receive(:run_silent).with('killall', '-TERM', 'Clocker').and_return(true)
      allow(CommandUtils).to receive(:run_silent).with('killall', '-TERM', 'Thaw').and_return(false)
      allow(described_class).to receive(:running_processes).with(['Thaw']).and_return(['Thaw'])
      allow(described_class).to receive(:running_processes).with(['Clocker']).and_return([])
      expect(Logging).to receive(:warn).with(/Failed to terminate .*Thaw/)

      described_class.kill_login_item_apps
    end
  end

  describe '.notify' do
    it 'posts the notification every time, even for identical consecutive messages' do
      allow(PathUtils).to receive(:command_exists?).with('terminal-notifier').and_return(true)
      expect(CommandUtils).to receive(:run_silent)
          .with('terminal-notifier', '-message', 'hi', '-title', 'T', '-sound', 'default').twice

      2.times { described_class.notify("\e[31mhi\e[0m", 'T') }
    end

    it 'falls back to osascript without terminal-notifier' do
      allow(PathUtils).to receive(:command_exists?).with('terminal-notifier').and_return(false)
      expect(CommandUtils).to receive(:run_silent).with('osascript', '-e', 'display notification "hi" with title "T"')

      described_class.notify('hi', 'T')
    end
  end
end
