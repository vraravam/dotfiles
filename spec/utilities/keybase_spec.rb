# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'keybase'

RSpec.describe Keybase do
  describe '.keybase_url?' do
    it 'is true for a keybase:// URL' do
      expect(described_class.keybase_url?('keybase://private/someuser/home')).to be true
    end

    it 'is false for a regular https:// URL' do
      expect(described_class.keybase_url?('https://github.com/someuser/dotfiles.git')).to be false
    end

    it 'is false for nil' do
      expect(described_class.keybase_url?(nil)).to be false
    end

    it 'is false for an empty string' do
      expect(described_class.keybase_url?('')).to be false
    end
  end

  describe '.username' do
    it 'is nil when keybase is not installed' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(false)

      expect(described_class.username).to be_nil
    end

    it 'is nil when keybase is installed but nobody is logged in' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(CommandUtils).to receive(:query)
        .with('keybase', 'status', '--json')
        .and_return('{"Username":"","LoggedIn":false}')

      expect(described_class.username).to be_nil
    end

    it 'returns the logged-in username when keybase is installed and logged in' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(CommandUtils).to receive(:query)
        .with('keybase', 'status', '--json')
        .and_return('{"Username":"someuser","LoggedIn":true}')

      expect(described_class.username).to eq('someuser')
    end

    it 'is nil when keybase status returns invalid JSON' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(CommandUtils).to receive(:query)
        .with('keybase', 'status', '--json')
        .and_return('not valid json')

      expect(described_class.username).to be_nil
    end
  end

  describe '.repo_url' do
    it 'builds a keybase:// URL for the given repo name, owned by the logged-in user' do
      allow(described_class).to receive(:username).and_return('someuser')

      expect(described_class.repo_url('home')).to eq('keybase://private/someuser/home')
    end

    it 'is recognized by .keybase_url? once built' do
      allow(described_class).to receive(:username).and_return('someuser')

      expect(described_class.keybase_url?(described_class.repo_url('profiles'))).to be true
    end
  end

  describe '.ensure_logged_in' do
    before { stub_const('EnvVars::KEYBASE_USERNAME', nil) }

    it 'returns false and records an error when keybase is not installed' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(false)
      expect(Logging).to receive(:record_error).with(/keybase.*not found/)

      expect(described_class.ensure_logged_in).to be false
    end

    it 'returns true without checking status when dry_run is true' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      expect(CommandUtils).not_to receive(:query)

      expect(described_class.ensure_logged_in(dry_run: true)).to be true
    end

    it 'returns true without attempting login when already logged in' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(CommandUtils).to receive(:query)
        .with('keybase', 'status', '--json')
        .and_return('{"Username":"someuser","LoggedIn":true}')
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(described_class.ensure_logged_in).to be true
    end

    it 'attempts an interactive login when not logged in, and returns its result' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(CommandUtils).to receive(:query)
        .with('keybase', 'status', '--json')
        .and_return('{"Username":"","LoggedIn":false}')
      allow(CommandUtils).to receive(:run_interactive).with('keybase', 'login').and_return(true)

      expect(described_class.ensure_logged_in).to be true
    end

    it 'passes KEYBASE_USERNAME to keybase login when it is set' do
      stub_const('EnvVars::KEYBASE_USERNAME', 'someuser')
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(CommandUtils).to receive(:query)
        .with('keybase', 'status', '--json')
        .and_return('{"Username":"","LoggedIn":false}')
      expect(CommandUtils).to receive(:run_interactive).with('keybase', 'login', 'someuser').and_return(true)

      expect(described_class.ensure_logged_in).to be true
    end

    it 'does not log in again when already logged in, even if KEYBASE_USERNAME is set' do
      stub_const('EnvVars::KEYBASE_USERNAME', 'someuser')
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(CommandUtils).to receive(:query)
        .with('keybase', 'status', '--json')
        .and_return('{"Username":"other","LoggedIn":true}')
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(described_class.ensure_logged_in).to be true
    end

    it 'records an error when the interactive login fails' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(CommandUtils).to receive(:query)
        .with('keybase', 'status', '--json')
        .and_return('{"Username":"","LoggedIn":false}')
      allow(CommandUtils).to receive(:run_interactive).with('keybase', 'login') do |&block|
        block.call
        false
      end

      expect(Logging).to receive(:record_error).with(/Could not log into keybase/)
      expect(described_class.ensure_logged_in).to be false
    end
  end

  describe '.ensure_logged_in with start_service: true' do
    before { stub_const('EnvVars::KEYBASE_USERNAME', nil) }

    it 'starts the keybase service before checking the login status' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      expect(described_class).to receive(:ensure_service_running).ordered
      expect(described_class).to receive(:_status).ordered.and_return('LoggedIn' => true, 'Username' => 'me')

      expect(described_class.ensure_logged_in(start_service: true)).to be true
    end

    it 'does not start the service by default' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      expect(described_class).not_to receive(:ensure_service_running)
      allow(described_class).to receive(:_status).and_return('LoggedIn' => true, 'Username' => 'me')

      described_class.ensure_logged_in
    end
  end

  describe '.ensure_service_running' do
    before do
      allow(described_class).to receive(:_fix_google_support_ownership)
      allow(described_class).to receive(:sleep)
    end

    it 'does nothing when keybase is not installed' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(false)
      expect(described_class).not_to receive(:_fix_google_support_ownership)
      expect(CommandUtils).not_to receive(:run_silent)

      described_class.ensure_service_running
    end

    it 'fixes the ownership but does not launch the app when the service already answers' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(described_class).to receive(:_service_up?).and_return(true)
      expect(described_class).to receive(:_fix_google_support_ownership)
      expect(CommandUtils).not_to receive(:run_silent)

      described_class.ensure_service_running
    end

    it 'launches the app hidden and polls until the service answers' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(described_class).to receive(:_service_up?).and_return(false, false, true)
      expect(CommandUtils).to receive(:run_silent).with('open', '-g', '-a', 'Keybase').and_return(true)

      expect { described_class.ensure_service_running }.to output(/Starting Keybase service/).to_stdout
      expect(described_class).to have_received(:sleep).once
    end

    it 'gives up after SERVICE_START_ATTEMPTS polls' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(described_class).to receive(:_service_up?).and_return(false)
      allow(CommandUtils).to receive(:run_silent).and_return(true)

      expect { described_class.ensure_service_running }.to output(/Starting Keybase service/).to_stdout
      expect(described_class).to have_received(:sleep).exactly(Keybase::SERVICE_START_ATTEMPTS).times
    end
  end

  describe '._fix_google_support_ownership' do
    around do |example|
      Dir.mktmpdir('keybase-spec-') do |dir|
        @tmp = Pathname.new(dir)
        example.run
      end
    end

    before do
      stub_const('EnvVars::HOME', @tmp)
      stub_const('EnvVars::USER', 'someuser')
    end

    def google_dir
      @tmp.join('Library', 'Application Support', 'Google').tap(&:mkpath)
    end

    it 'does nothing when the directory does not exist' do
      expect(CommandUtils).not_to receive(:run_silent)

      described_class.send(:_fix_google_support_ownership)
    end

    it 'does nothing when the directory is owned by the current user' do
      google_dir
      expect(CommandUtils).not_to receive(:run_silent)

      described_class.send(:_fix_google_support_ownership)
    end

    it 'takes ownership back when the directory belongs to someone else' do
      dir = google_dir
      allow(Process).to receive(:uid).and_return(dir.stat.uid + 1)
      expect(CommandUtils).to receive(:run_silent).with('sudo', 'chown', '-R', 'someuser:staff', dir.to_s).and_return(true)

      expect { described_class.send(:_fix_google_support_ownership) }.to output(/Fixing ownership/).to_stdout
    end
  end

  describe '.configured?' do
    it 'is false when neither repo name is set' do
      stub_const('EnvVars::KEYBASE_HOME_REPO_NAME', nil)
      stub_const('EnvVars::KEYBASE_PROFILES_REPO_NAME', nil)

      expect(described_class.configured?).to be false
    end

    it 'is true when either repo name is set' do
      stub_const('EnvVars::KEYBASE_HOME_REPO_NAME', nil)
      stub_const('EnvVars::KEYBASE_PROFILES_REPO_NAME', 'profiles')

      expect(described_class.configured?).to be true
    end
  end

  describe '.bootstrap_login' do
    def quietly
      original = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = original
    end

    before do
      allow(described_class).to receive(:configured?).and_return(true)
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(true)
      allow(described_class).to receive(:username).and_return(nil)
    end

    it 'skips, successfully, when Keybase is not configured' do
      allow(described_class).to receive(:configured?).and_return(false)
      expect(described_class).not_to receive(:ensure_logged_in)

      expect(quietly { described_class.bootstrap_login(first_install: true) }).to be true
    end

    it 'skips, successfully, when keybase is not installed' do
      allow(PathUtils).to receive(:command_exists?).with('keybase').and_return(false)
      expect(described_class).not_to receive(:ensure_logged_in)

      expect(quietly { described_class.bootstrap_login(first_install: true) }).to be true
    end

    it 'accepts an existing login without asking again' do
      allow(described_class).to receive(:username).and_return('someuser')
      expect(described_class).not_to receive(:ensure_logged_in)

      expect(quietly { described_class.bootstrap_login(first_install: true) }).to be true
    end

    it 'does not attempt a login on a pre-configured machine' do
      expect(described_class).not_to receive(:ensure_logged_in)

      expect(quietly { described_class.bootstrap_login(first_install: false) }).to be true
    end

    it 'logs in, starting the service, on a first install' do
      expect(described_class).to receive(:ensure_logged_in).with(start_service: true).and_return(true)

      expect(quietly { described_class.bootstrap_login(first_install: true) }).to be true
    end

    it 'is false when the first-install login fails' do
      allow(described_class).to receive(:ensure_logged_in).with(start_service: true).and_return(false)

      expect(quietly { described_class.bootstrap_login(first_install: true) }).to be false
    end
  end

  describe '.delete_repo' do
    it 'logs the intended action and does not call keybase when dry_run is true' do
      expect(CommandUtils).not_to receive(:run_silent)

      described_class.delete_repo('home', dry_run: true)
    end

    it 'records a warning when deletion fails' do
      allow(CommandUtils).to receive(:run_silent).with('keybase', 'git', 'delete', '-f', 'home').and_return(false)

      expect(Logging).to receive(:record_warning).with(/Failed to delete keybase repo/)
      described_class.delete_repo('home')
    end

    it 'does not warn when deletion succeeds' do
      allow(CommandUtils).to receive(:run_silent).with('keybase', 'git', 'delete', '-f', 'home').and_return(true)

      expect(Logging).not_to receive(:record_warning)
      described_class.delete_repo('home')
    end
  end

  describe '.create_repo' do
    it 'returns true without calling keybase when dry_run is true' do
      expect(CommandUtils).not_to receive(:run_interactive)

      expect(described_class.create_repo('home', dry_run: true)).to be true
    end

    it 'returns true when creation succeeds' do
      allow(CommandUtils).to receive(:run_interactive).with('keybase', 'git', 'create', 'home').and_return(true)

      expect(described_class.create_repo('home')).to be true
    end

    it 'returns false and records an error when creation fails' do
      allow(CommandUtils).to receive(:run_interactive).with('keybase', 'git', 'create', 'home').and_return(false)

      expect(Logging).to receive(:record_error).with(/Failed to create keybase repo/)
      expect(described_class.create_repo('home')).to be false
    end
  end

  describe '.recreate_repo' do
    it 'returns true without touching keybase when dry_run is true' do
      expect(described_class).not_to receive(:delete_repo)
      expect(described_class).not_to receive(:create_repo)

      expect(described_class.recreate_repo('home', dry_run: true)).to be true
    end

    it 'deletes then creates the repo, returning true on success' do
      expect(described_class).to receive(:delete_repo).with('home', dry_run: false)
      expect(described_class).to receive(:create_repo).with('home', dry_run: false).and_return(true)

      expect(described_class.recreate_repo('home')).to be true
    end

    it 'returns false and records an error when recreation fails' do
      allow(described_class).to receive(:delete_repo)
      allow(described_class).to receive(:create_repo).and_return(false)

      expect(Logging).to receive(:record_error).with(/Failed to recreate keybase repo/)
      expect(described_class.recreate_repo('home')).to be false
    end
  end
end
