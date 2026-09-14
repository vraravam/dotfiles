# frozen_string_literal: true

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

  describe '.ensure_logged_in' do
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
