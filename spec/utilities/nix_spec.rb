# frozen_string_literal: true

require 'nix'

RSpec.describe Nix do
  describe '.flake' do
    it 'points at the default flake under DOTFILES_DIR/nix' do
      stub_const('EnvVars::DOTFILES_DIR', Pathname.new('/dots'))

      expect(described_class.flake).to eq('/dots/nix#default')
    end
  end

  describe '.rebuild' do
    it 'switches to the flake impurely (the flake reads .shellrc)' do
      stub_const('EnvVars::DOTFILES_DIR', Pathname.new('/dots'))
      command = ['darwin-rebuild', 'switch', '--flake', '/dots/nix#default', '--impure']
      expect(CommandUtils).to receive(:run_interactive).with(*command).and_return(true)

      expect(described_class.rebuild).to be true
    end
  end
end
