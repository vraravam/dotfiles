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
end
