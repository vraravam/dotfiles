# frozen_string_literal: true

require_relative '../scripts/brew-update-cleanup'

RSpec.describe BrewUpdateCleanup do
  let(:events) { [] }

  before do
    Logging.state.reset!
    allow(Brew).to receive(:update) { events << :update }.and_return(true)
    allow(Brew).to receive(:cleanup) { events << :cleanup }
    allow(PathUtils).to receive(:command_exists?).with('darwin-rebuild').and_return(true)
    allow(Nix).to receive(:rebuild) { events << :rebuild }.and_return(true)
    allow(SetupLoginItem).to receive(:unregister_removed) { events << :logins_removed }.and_return(true)
    allow(SetupLoginItem).to receive(:register_managed) { events << :login_items }.and_return(true)
  end

  after { Logging.state.reset! }

  it 'removes the login items of dropped apps before the rebuild uninstalls them, and registers missing ones after it' do
    expect(described_class.run).to be true
    expect(events).to eq(%i[update logins_removed rebuild login_items cleanup])
  end

  it 'records a warning, but still registers the login items, when the rebuild fails' do
    allow(Nix).to receive(:rebuild) { events << :rebuild }.and_return(false)

    expect(described_class.run).to be false
    expect(events).to include(:login_items)
  end

  it 'still handles the login items on a machine without nix-darwin' do
    allow(PathUtils).to receive(:command_exists?).with('darwin-rebuild').and_return(false)
    expect(Nix).not_to receive(:rebuild)

    expect(described_class.run).to be true
    expect(events).to eq(%i[update logins_removed login_items cleanup])
  end
end
