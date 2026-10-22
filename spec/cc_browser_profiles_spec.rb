# encoding: utf-8
# frozen_string_literal: true

require 'cron'
require 'git_commands'
require 'logging'

# scripts/cc-browser-profiles.rb is a per-folder override with no module: loading it IS running it.
RSpec.describe 'cc-browser-profiles.rb' do
  let(:script) { File.expand_path('../scripts/cc-browser-profiles.rb', __dir__) }

  before do
    allow(Logging).to receive(:run_script) { |&block| block.call }
    allow(Cron).to receive(:with_cron_suspended) { |&block| block.call }
    allow(GitCommands).to receive(:cc)
  end

  it 'runs the default cc, without a second banner, inside cron suspension' do
    stub_const('ARGV', %w[-m message])

    expect(Cron).to receive(:with_cron_suspended).ordered do |&block|
      block.call
    end
    expect(GitCommands).to receive(:cc).with(args: %w[-m message], header: false).ordered

    load script
  end

  it 'runs under Logging.run_script' do
    expect(Logging).to receive(:run_script)

    load script
  end
end
