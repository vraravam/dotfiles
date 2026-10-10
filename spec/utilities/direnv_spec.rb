# frozen_string_literal: true

require 'tmpdir'
require 'direnv'

RSpec.describe Direnv do
  describe '.envrc?' do
    it 'is true only for a directory containing an .envrc' do
      Dir.mktmpdir do |tmp|
        expect(described_class.envrc?(tmp)).to be false
        File.write(File.join(tmp, '.envrc'), "\n")
        expect(described_class.envrc?(tmp)).to be true
      end
    end
  end

  describe '.activate' do
    it 'evaluates the .envrc with direnv exec after a successful allow' do
      expect(CommandUtils).to receive(:run_silent).with('direnv', 'allow', '/d').and_return(true).ordered
      expect(CommandUtils).to receive(:run_silent).with('direnv', 'exec', '/d', 'true').and_return(true).ordered

      expect(described_class.activate('/d')).to be true
    end

    it 'does not evaluate the .envrc when the allow failed' do
      allow(CommandUtils).to receive(:run_silent).with('direnv', 'allow', '/d').and_return(false)
      expect(CommandUtils).not_to receive(:run_silent).with('direnv', 'exec', any_args)

      expect(described_class.activate('/d')).to be false
    end
  end
end
