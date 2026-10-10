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

  describe '.install' do
    it 'returns the exit status of mise install for the given directory' do
      expect(described_class).to receive(:stream_command).with(['mise', '-C', '/d', 'install']).and_return(0)

      expect(described_class.install('/d')).to eq(0)
    end
  end
end
