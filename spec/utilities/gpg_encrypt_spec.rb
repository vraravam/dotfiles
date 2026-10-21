# encoding: utf-8
# frozen_string_literal: true

require 'stringio'
require 'gpg_encrypt'

RSpec.describe GpgEncrypt do
  describe '.url' do
    it 'prepends the gpg-encrypt:: pseudo-scheme to a plain https:// URL' do
      expect(described_class.url('https://github.com/example/repo.git')).to eq('gpg-encrypt::https://github.com/example/repo.git')
    end

    it 'prepends the gpg-encrypt:: pseudo-scheme to a plain ssh-style URL' do
      expect(described_class.url('git@github.com:example/repo.git')).to eq('gpg-encrypt::git@github.com:example/repo.git')
    end

    it 'uses the PROTOCOL constant as the prefix' do
      expect(described_class.url('https://example.com/repo.git')).to start_with(described_class::PROTOCOL)
    end
  end

  describe '.configured?' do
    it 'is false when neither encrypted repo URL is set' do
      stub_const('EnvVars::ENCRYPTED_HOME_REPO_URL', nil)
      stub_const('EnvVars::ENCRYPTED_PROFILES_REPO_URL', nil)

      expect(described_class.configured?).to be false
    end

    it 'is true when either URL is set' do
      stub_const('EnvVars::ENCRYPTED_HOME_REPO_URL', nil)
      stub_const('EnvVars::ENCRYPTED_PROFILES_REPO_URL', 'git@host:p.git')

      expect(described_class.configured?).to be true
    end
  end

  describe '.bootstrap_setup' do
    before do
      allow(described_class).to receive(:configured?).and_return(true)
      allow(PathUtils).to receive(:command_exists?).with('git-gpg-encrypt-setup').and_return(true)
      allow(CommandUtils).to receive(:run_interactive).with('git-gpg-encrypt-setup').and_return(true)
      Logging.state.reset!
    end

    def quietly
      original = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = original
    end

    it 'skips, successfully, when encrypted backup is not configured' do
      allow(described_class).to receive(:configured?).and_return(false)
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(quietly { described_class.bootstrap_setup }).to be true
    end

    it 'skips, successfully, when the tool is not installed' do
      allow(PathUtils).to receive(:command_exists?).with('git-gpg-encrypt-setup').and_return(false)
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(quietly { described_class.bootstrap_setup }).to be true
    end

    it 'runs the setup command and reports success' do
      expect(CommandUtils).to receive(:run_interactive).with('git-gpg-encrypt-setup').and_return(true)

      expect(quietly { described_class.bootstrap_setup }).to be true
    end

    it 'is false, recording a warning, when the setup command fails' do
      allow(CommandUtils).to receive(:run_interactive).with('git-gpg-encrypt-setup').and_return(false)
      expect(Logging).to receive(:record_warning).with(/Encrypted backup is not configured/)

      expect(quietly { described_class.bootstrap_setup }).to be false
    end
  end
end
