# encoding: utf-8
# frozen_string_literal: true

require_relative '../scripts/brew-update-cleanup'

RSpec.describe BrewUpdateCleanup do
  let(:events) { [] }

  before do
    Logging.state.reset!
    allow(Brew).to receive(:update) { events << :update }.and_return(true)
    allow(Brew).to receive(:cleanup) { events << :cleanup }
    allow(Brew).to receive(:sync_bundle) { events << :sync }.and_return(true)
    allow(SetupLoginItem).to receive(:unregister_removed) { events << :logins_removed }.and_return(true)
    allow(SetupLoginItem).to receive(:register_managed) { events << :login_items }.and_return(true)
    allow(Brew).to receive(:upgrade) { events << :upgrade }.and_return(true)
  end

  after { Logging.state.reset! }

  it 'removes the login items of dropped apps before the first cleanup uninstalls them, and registers missing ones after the sync' do
    expect(described_class.run).to be true
    expect(events).to eq(%i[update logins_removed cleanup sync login_items cleanup upgrade])
  end

  it 'records a warning, but still registers the login items, when the sync fails' do
    allow(Brew).to receive(:sync_bundle) { events << :sync }.and_return(false)
    expect(Logging).to receive(:record_warning).with(/Failed to sync installed packages/).and_call_original

    expect(described_class.run).to be false
    expect(events).to include(:login_items)
  end
end
