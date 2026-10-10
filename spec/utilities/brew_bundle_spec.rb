# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'brew_bundle'

RSpec.describe BrewBundle do
  around do |example|
    Dir.mktmpdir('brew-bundle-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let!(:brew) do
    tmp.join('bin', 'brew').tap do |file|
      file.dirname.mkpath
      file.write("#!/bin/sh\n")
      file.chmod(0o755)
    end
  end
  let(:brewfile) { tmp.join('Brewfile') }
  let(:log) { tmp.join('Downloads', 'brew-bundle-full-install.log') }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOMEBREW_PREFIX', tmp)
    stub_const('EnvVars::HOMEBREW_BUNDLE_FILE', brewfile)
    stub_const('BrewBundle::FULL_INSTALL_LOG', log)
    allow(Keybase).to receive(:link_cli_into)
    allow(Brew).to receive(:sync_bundle).and_return(true)
    allow(Brew).to receive(:bundle_in_background).and_return(true)
  end

  after { Logging.state.reset! }

  def run_quietly(**kwargs)
    original = $stdout
    $stdout = StringIO.new
    described_class.run(**kwargs)
  ensure
    $stdout = original
  end

  context 'on a pre-configured machine' do
    it 'syncs the whole Brewfile with the brew in the Homebrew prefix and starts no background job' do
      expect(Brew).to receive(:sync_bundle).with(brew_bin: brew.to_s, brewfile_content: nil).and_return(true)
      expect(Brew).not_to receive(:bundle_in_background)

      expect(run_quietly(first_install: false)).to be true
    end

    it 'reports failure when brew bundle fails, but still runs the Keybase safety net' do
      allow(Brew).to receive(:sync_bundle).and_return(false)
      expect(Keybase).to receive(:link_cli_into).with(brew.dirname)

      expect(run_quietly).to be false
    end

    it 'is false, without running anything, when brew is not executable' do
      stub_const('EnvVars::HOMEBREW_PREFIX', tmp.join('missing'))
      expect(Brew).not_to receive(:sync_bundle)

      expect { expect(described_class.run).to be false }.to output(/not executable/).to_stdout
    end
  end

  context 'on a first install' do
    it 'installs the base section first and then the whole Brewfile in the background' do
      brewfile.write("brew 'git'\n# FIRST_INSTALL: stop here\nbrew 'bat'\n")
      expect(Brew).to receive(:sync_bundle).with(brew_bin: brew.to_s, brewfile_content: "brew 'git'\n").and_return(true).ordered
      expect(Brew).to receive(:bundle_in_background).with(brew_bin: brew.to_s, log: log).and_return(true).ordered

      expect { expect(described_class.run(first_install: true)).to be true }.to output(/Full Brewfile install running in background/).to_stdout
    end

    it 'still starts the background install when the base section fails, and reports the failure' do
      brewfile.write("brew 'git'\n# FIRST_INSTALL: x\n")
      allow(Brew).to receive(:sync_bundle).and_return(false)
      expect(Brew).to receive(:bundle_in_background).and_return(true)

      expect(run_quietly(first_install: true)).to be false
    end

    it 'installs a Brewfile without a sentinel whole, with a warning' do
      brewfile.write("brew 'git'\nbrew 'bat'\n")
      expect(Brew).to receive(:sync_bundle).with(brew_bin: brew.to_s, brewfile_content: "brew 'git'\nbrew 'bat'\n").and_return(true)

      expect { described_class.run(first_install: true) }.to output(/No '# FIRST_INSTALL:' sentinel found/).to_stdout
    end

    it 'is false, without running brew, when the Brewfile does not exist' do
      expect(Brew).not_to receive(:sync_bundle)

      expect { expect(described_class.run(first_install: true)).to be false }.to output(/Brewfile not found/).to_stdout
    end

    it 'warns instead of failing when the background job cannot be started' do
      brewfile.write("brew 'git'\n# FIRST_INSTALL: x\n")
      allow(Brew).to receive(:bundle_in_background).and_return(false)

      expect { expect(described_class.run(first_install: true)).to be true }.to output(/Could not start the background Brewfile install/).to_stdout
    end
  end
end
