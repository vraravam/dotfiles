# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'homebrew_install'

RSpec.describe HomebrewInstall do
  around do |example|
    Dir.mktmpdir('homebrew-install-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:prefix) { @tmp.join('opt', 'homebrew') }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOMEBREW_PREFIX', prefix)
    stub_const('EnvVars::HOME', @tmp)
    stub_const('EnvVars::USER', 'someuser')
    prefix.mkpath
    allow(CommandUtils).to receive(:run_interactive).and_return(true)
  end

  after { Logging.state.reset! }

  def run_quietly
    original = $stdout
    $stdout = StringIO.new
    described_class.run
  ensure
    $stdout = original
  end

  def install_fake_brew
    prefix.join('bin').mkpath
    prefix.join('bin', 'brew').tap { |f| f.write("#!/bin/sh\n") }.chmod(0o755)
  end

  describe '.run' do
    it 'does nothing when brew is already installed' do
      install_fake_brew
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(run_quietly).to be true
    end

    it 'prepares the prefix, downloads the installer and runs it non-interactively' do
      expect(CommandUtils).to receive(:run_interactive).with('sudo', 'mkdir', '-p', *%w[tmp repository plugins bin].map { |d| prefix.join(d).to_s }).ordered.and_return(true)
      expect(CommandUtils).to receive(:run_interactive).with('sudo', 'chown', '-fR', 'someuser:admin', prefix.to_s).ordered.and_return(true)
      expect(CommandUtils).to receive(:run_interactive).with('curl', *described_class.curl_opts, '-fsSL', %r{\Ahttps://raw\.githubusercontent\.com/Homebrew/install/HEAD/install\.sh\?\d+\z}, '-o', String).ordered.and_return(true)
      expect(CommandUtils).to receive(:run_interactive).with({ 'NONINTERACTIVE' => '1' }, 'bash', String).ordered.and_return(true)

      expect(run_quietly).to be true
    end

    it 'removes the downloaded installer afterwards' do
      path = nil
      allow(CommandUtils).to receive(:run_interactive).with('curl', any_args) do |*args|
        path = args.last
        true
      end

      run_quietly

      expect(path).not_to be_nil
      expect(File).not_to exist(path)
    end

    it 'is false when the directories cannot be created' do
      allow(CommandUtils).to receive(:run_interactive).with('sudo', 'mkdir', any_args).and_return(false)
      expect(CommandUtils).not_to receive(:run_interactive).with('curl', any_args)

      expect(run_quietly).to be false
      expect(Logging.issue_summary_parts).not_to be_empty
    end

    it 'is false when the prefix cannot be chowned' do
      allow(CommandUtils).to receive(:run_interactive).with('sudo', 'chown', any_args).and_return(false)

      expect(run_quietly).to be false
    end

    it 'is false when the download fails, without running the installer' do
      allow(CommandUtils).to receive(:run_interactive).with('curl', any_args).and_return(false)
      expect(CommandUtils).not_to receive(:run_interactive).with(hash_including('NONINTERACTIVE'), any_args)

      expect(run_quietly).to be false
    end

    it 'is false when the installer fails' do
      allow(CommandUtils).to receive(:run_interactive).with(hash_including('NONINTERACTIVE'), any_args).and_return(false)

      expect(run_quietly).to be false
    end

    it 'is false when HOMEBREW_PREFIX is empty' do
      stub_const('EnvVars::HOMEBREW_PREFIX', Pathname.new(''))
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(run_quietly).to be false
    end
  end

  describe '.curl_opts' do
    before do
      allow(EnvVars).to receive(:cache_bust_headers?).and_return(false)
      allow(EnvVars).to receive(:curl_retry_opts?).and_return(false)
    end

    it 'adds the retry flags while ~/.curlrc is not linked' do
      expect(described_class.curl_opts).to eq(HomebrewInstall::RETRY_OPTS)
    end

    it 'adds nothing when ~/.curlrc exists and nothing is requested' do
      @tmp.join('.curlrc').write('')

      expect(described_class.curl_opts).to eq([])
    end

    it 'adds the retry flags when CURL_RETRY_OPTS is set even with ~/.curlrc' do
      @tmp.join('.curlrc').write('')
      allow(EnvVars).to receive(:curl_retry_opts?).and_return(true)

      expect(described_class.curl_opts).to eq(HomebrewInstall::RETRY_OPTS)
    end

    it 'puts the cache-busting headers first when CACHE_BUST_HEADERS is set' do
      allow(EnvVars).to receive(:cache_bust_headers?).and_return(true)
      @tmp.join('.curlrc').write('')

      expect(described_class.curl_opts).to eq(HomebrewInstall::CACHE_BUST_OPTS)
    end
  end
end
