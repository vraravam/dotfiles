# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'mise'

RSpec.describe Mise do
  describe '.config?' do
    it 'is true when any known tool-version file is present' do
      Dir.mktmpdir do |tmp|
        expect(described_class.config?(tmp)).to be false
        File.write(File.join(tmp, '.nvmrc'), "20\n")
        expect(described_class.config?(tmp)).to be true
      end
    end
  end

  describe '.trust' do
    it 'does not process anything if mise is not trusted' do
      allow(PathUtils).to receive(:command_exists?).with('mise').and_return(false)
      expect(CommandUtils).not_to receive(:capture_output)

      expect(described_class.trust('/d')).to be false
    end

    it 'returns the exit status of mise trust for the given directory' do
      allow(PathUtils).to receive(:command_exists?).with('mise').and_return(true)
      expect(CommandUtils).to receive(:capture_output).with('mise', '-C', '/d', 'trust', '-y', '-a').and_return(0)

      expect(described_class.trust('/d')).to eq(0)
    end
  end

  describe '.install' do
    it 'does not process anything if mise is not installed' do
      allow(PathUtils).to receive(:command_exists?).with('mise').and_return(false)
      expect(CommandUtils).not_to receive(:stream_command)

      expect(described_class.install('/d')).to be false
    end

    it 'returns the exit status of mise install for the given directory' do
      allow(PathUtils).to receive(:command_exists?).with('mise').and_return(true)
      expect(CommandUtils).to receive(:stream_command).with(['mise', '-C', '/d', 'install']).and_return(0)

      expect(described_class.install('/d')).to eq(0)
    end
  end
end
