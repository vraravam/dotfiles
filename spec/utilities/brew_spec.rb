# frozen_string_literal: true

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

  describe '.cleanup' do
    it 'runs every cleanup step even when an earlier one fails' do
      calls = []
      allow(CommandUtils).to receive(:run_interactive) { |*cmd| calls << cmd.join(' ') && false }

      described_class.cleanup

      expect(calls).to eq(['brew cleanup --prune=all', 'brew autoremove'])
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
end
