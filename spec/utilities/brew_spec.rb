# frozen_string_literal: true

require 'tmpdir'
require 'brew'

RSpec.describe Brew do
  describe '.update' do
    it 'streams brew update by default' do
      expect(CommandUtils).to receive(:run_interactive).with('brew', 'update').and_return(true)

      expect(described_class.update).to be true
    end

    it 'suppresses stdout but keeps stderr when quiet' do
      expect(CommandUtils).to receive(:run_silent).with('brew', 'update', err: :err).and_return(true)

      expect(described_class.update(quiet: true)).to be true
    end
  end

  describe '.sync_bundle' do
    it 'skips the install when the bundle check passes' do
      expect(CommandUtils).to receive(:run_interactive).with('brew', 'bundle', 'check', '-v').and_return(true)
      expect(CommandUtils).not_to receive(:run_interactive).with('brew', 'bundle', 'install', '-q')

      expect(described_class.sync_bundle).to be true
    end

    it 'installs when the bundle check fails' do
      allow(CommandUtils).to receive(:run_interactive).with('brew', 'bundle', 'check', '-v').and_return(false)
      expect(CommandUtils).to receive(:run_interactive).with('brew', 'bundle', 'install', '-q').and_return(true)

      expect(described_class.sync_bundle).to be true
    end
  end

  describe '.cleanup' do
    it 'runs every cleanup step even when an earlier one fails' do
      calls = []
      allow(CommandUtils).to receive(:run_interactive) { |*cmd| calls << cmd.join(' ') && false }

      described_class.cleanup

      expect(calls).to eq(['brew bundle cleanup -f', 'brew cleanup --prune=all', 'brew autoremove'])
    end
  end

  describe '.upgrade' do
    it 'upgrades without prompting' do
      expect(CommandUtils).to receive(:run_interactive).with('brew', 'upgrade', '-y').and_return(true)

      expect(described_class.upgrade).to be true
    end
  end

  describe '.outdated_greedy' do
    it 'is empty when brew is not installed' do
      allow(PathUtils).to receive(:command_exists?).with('brew').and_return(false)
      expect(CommandUtils).not_to receive(:query)

      expect(described_class.outdated_greedy).to eq([])
    end

    it 'returns one stripped entry per outdated package and drops blank lines and Homebrew noise' do
      allow(PathUtils).to receive(:command_exists?).with('brew').and_return(true)
      allow(CommandUtils).to receive(:query).with('brew', 'outdated', '--greedy')
                                            .and_return("firefox (130) != 131\n\n  zoom (5) != 6  \nHomebrew is updating\nDownloading https://x\n")

      expect(described_class.outdated_greedy).to eq(['firefox (130) != 131', 'zoom (5) != 6'])
    end
  end

  describe '.sync_bundle with a brew path and Brewfile content' do
    let(:brew) { '/opt/homebrew/bin/brew' }

    it 'uses the given brew binary instead of PATH' do
      expect(CommandUtils).to receive(:run_interactive).with(brew, 'bundle', 'check', '-v').and_return(true)

      expect(described_class.sync_bundle(brew_bin: brew)).to be true
    end

    it 'installs from the given content on stdin when the check fails, and reports its exit status' do
      allow(CommandUtils).to receive(:run_interactive).with(brew, 'bundle', 'check', '-v').and_return(false)
      expect(Core).to receive(:stream_command)
                        .with([brew, 'bundle', 'install', '-q', '--file=-'], stdin_data: "brew 'git'\n").and_return(0, 1)

      expect(described_class.sync_bundle(brew_bin: brew, brewfile_content: "brew 'git'\n")).to be true
      expect(described_class.sync_bundle(brew_bin: brew, brewfile_content: "brew 'git'\n")).to be false
    end

    it 'does not install from content when the check already passes' do
      allow(CommandUtils).to receive(:run_interactive).with(brew, 'bundle', 'check', '-v').and_return(true)
      expect(Core).not_to receive(:stream_command)

      expect(described_class.sync_bundle(brew_bin: brew, brewfile_content: 'x')).to be true
    end
  end

  describe '.base_brewfile_content' do
    around do |example|
      Dir.mktmpdir('brew-spec-') do |dir|
        @tmp = Pathname.new(dir)
        example.run
      end
    end

    def brewfile(text)
      @tmp.join('Brewfile').tap { |file| file.write(text) }
    end

    it 'returns everything above the sentinel comment, without the sentinel itself' do
      file = brewfile("brew 'git'\ncask 'iterm2'\n\n# FIRST_INSTALL: install only the above first\nbrew 'bat'\n")

      expect(described_class.base_brewfile_content(file)).to eq("brew 'git'\ncask 'iterm2'\n\n")
    end

    it 'matches the sentinel although it is a comment (comment lines are not skipped)' do
      file = brewfile("# a header comment\nbrew 'git'\n# FIRST_INSTALL: here\nbrew 'bat'\n")

      expect(described_class.base_brewfile_content(file)).to eq("# a header comment\nbrew 'git'\n")
    end

    it 'does not treat other mentions of FIRST_INSTALL as the sentinel' do
      file = brewfile("# see FIRST_INSTALL below\nbrew 'git'\nputs 'FIRST_INSTALL'\n# FIRST_INSTALL: stop\nbrew 'bat'\n")

      expect(described_class.base_brewfile_content(file)).to eq("# see FIRST_INSTALL below\nbrew 'git'\nputs 'FIRST_INSTALL'\n")
    end

    it 'is nil when the Brewfile has no sentinel' do
      expect(described_class.base_brewfile_content(brewfile("brew 'git'\n"))).to be_nil
    end

    it 'reads UTF-8 content' do
      file = brewfile("# caf\u00e9\nbrew 'git'\n# FIRST_INSTALL: x\n")

      expect(described_class.base_brewfile_content(file)).to eq("# caf\u00e9\nbrew 'git'\n")
    end
  end

  describe '.bundle_in_background' do
    around do |example|
      Dir.mktmpdir('brew-spec-') do |dir|
        @tmp = Pathname.new(dir)
        example.run
      end
    end

    it 'starts a detached full bundle with FIRST_INSTALL emptied, appending to the log' do
      brew = @tmp.join('brew')
      brew.write("#!/bin/sh\necho \"args=$* first_install=[${FIRST_INSTALL-unset}]\"\n")
      brew.chmod(0o755)
      log = @tmp.join('logs', 'bundle.log')

      with_env('FIRST_INSTALL' => '1') do
        expect(described_class.bundle_in_background(brew_bin: brew.to_s, log: log)).to be true
      end

      deadline = Time.now + 5
      sleep 0.05 until (log.exist? && log.size.positive?) || Time.now > deadline
      expect(log.read).to include('args=bundle', 'first_install=[]')
    end

    it 'is false when the brew binary cannot be started' do
      expect(described_class.bundle_in_background(brew_bin: @tmp.join('missing').to_s, log: @tmp.join('bundle.log'))).to be false
    end
  end
end
