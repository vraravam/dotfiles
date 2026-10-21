# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require_relative '../scripts/install-dotfiles'

RSpec.describe InstallDotfiles do
  around do |example|
    Dir.mktmpdir('install-dotfiles-spec-') do |dir|
      @tmp = Pathname(dir).realpath
      example.run
    end
  end

  let(:tmp) { @tmp }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOME', tmp)
    stub_const('EnvVars::XDG_CONFIG_HOME', tmp.join('.config'))
  end

  after { Logging.state.reset! }

  def quietly
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe '.run reminder about the copied custom.git* files' do
    before do
      stub_const('EnvVars::DOTFILES_DIR', tmp.join('dotfiles'))
      tmp.join('dotfiles', 'files').mkpath
      %i[_ensure_ssh_include_line _ensure_gitconfig_tool_symlink].each { |name| allow(described_class).to receive(name) }
      allow(Logging).to receive(:warn)
    end

    it 'is given on a re-run' do
      with_env('FIRST_INSTALL' => nil) { quietly { described_class.run } }

      expect(Logging).to have_received(:warn).with(/custom\.git\*' files are COPIED/)
    end

    it 'is not given on a first install, where nothing can be stale' do
      with_env('FIRST_INSTALL' => '1') { quietly { described_class.run } }

      expect(Logging).not_to have_received(:warn)
    end
  end

  describe '._ensure_ssh_include_line' do
    let(:ssh_dir) { tmp.join('.ssh') }
    let(:config) { ssh_dir.join('config') }

    before do
      ssh_dir.mkpath
      target = tmp.join('global_config_source')
      target.write("Host *\n")
      File.symlink(target.to_s, ssh_dir.join('global_config').to_s)
    end

    it 'appends the Include line to an existing config' do
      config.write("Host x\n")

      quietly { described_class.send(:_ensure_ssh_include_line) }

      expect(config.read).to eq("Host x\n\nMatch all\nInclude ~/.ssh/global_config\n")
    end

    it 'inserts Match all directly above an Include that has none, leaving everything else untouched' do
      config.write("Host x\n  HostName a\n\n# global settings\nInclude ~/.ssh/global_config\nHost y\n")

      output = quietly { described_class.send(:_ensure_ssh_include_line) }

      expect(config.read).to eq("Host x\n  HostName a\n\n# global settings\nMatch all\nInclude ~/.ssh/global_config\nHost y\n")
      expect(output).to match(/Inserting/)
    end

    it 'leaves an Include that already follows Match all alone, even with a comment or blank lines between' do
      content = "Host x\n\nMatch all\n# why\n\nInclude ~/.ssh/global_config\n"
      config.write(content)

      output = quietly { described_class.send(:_ensure_ssh_include_line) }

      expect(config.read).to eq(content)
      expect(output).to match(/already present/)
    end

    it 'matches Match all case-insensitively and ignores surrounding whitespace' do
      content = "Host x\n  match ALL  \nInclude ~/.ssh/global_config\n"
      config.write(content)

      quietly { described_class.send(:_ensure_ssh_include_line) }

      expect(config.read).to eq(content)
    end

    it 'also inserts Match all after a Match block, which scopes the Include just like a Host block does' do
      config.write("Match host foo\nInclude ~/.ssh/global_config\n")

      quietly { described_class.send(:_ensure_ssh_include_line) }

      expect(config.read).to eq("Match host foo\nMatch all\nInclude ~/.ssh/global_config\n")
    end

    it 'is idempotent: a second run changes nothing' do
      config.write("Host x\n")
      quietly { described_class.send(:_ensure_ssh_include_line) }
      first = config.read

      quietly { described_class.send(:_ensure_ssh_include_line) }

      expect(config.read).to eq(first)
    end

    it 'does not rewrite an Include without Match all in dry-run mode' do
      config.write("Host x\nInclude ~/.ssh/global_config\n")

      output = quietly { described_class.send(:_ensure_ssh_include_line, dry_run: true) }

      expect(config.read).to eq("Host x\nInclude ~/.ssh/global_config\n")
      expect(output).to match(/Would insert/)
    end

    it 'creates a missing config with the Include line' do
      quietly { described_class.send(:_ensure_ssh_include_line) }

      expect(config.read).to include('Include ~/.ssh/global_config')
    end

    it 'does not write anything in dry-run mode, and says what it would do' do
      config.write("Host x\n")

      output = quietly { described_class.send(:_ensure_ssh_include_line, dry_run: true) }

      expect(config.read).to eq("Host x\n")
      expect(output).to match(/Would add/)
    end

    it 'does not even create a missing config in dry-run mode' do
      output = quietly { described_class.send(:_ensure_ssh_include_line, dry_run: true) }

      expect(config).not_to exist
      expect(output).to match(/Would create/)
    end

    it 'reports an already present line the same way in dry-run mode' do
      config.write("Match all\nInclude ~/.ssh/global_config\n")

      output = quietly { described_class.send(:_ensure_ssh_include_line, dry_run: true) }

      expect(output).to match(/already present/)
    end
  end

  describe '._ensure_gitconfig_tool_symlink' do
    let(:git_dir) { tmp.join('.config', 'git') }
    let(:link) { git_dir.join('config-delta-enabled.inc') }

    before do
      git_dir.mkpath
      git_dir.join('config-delta.inc').write("[delta]\n")
    end

    it 'creates the enabled symlink when the tool is installed' do
      allow(PathUtils).to receive(:command_exists?).with('delta').and_return(true)

      quietly { described_class.send(:_ensure_gitconfig_tool_symlink, 'delta') }

      expect(link).to be_symlink
    end

    it 'creates nothing in dry-run mode' do
      allow(PathUtils).to receive(:command_exists?).with('delta').and_return(true)

      output = quietly { described_class.send(:_ensure_gitconfig_tool_symlink, 'delta', dry_run: true) }

      expect(link).not_to be_symlink
      expect(output).to match(/Would create/)
    end

    it 'removes a stale symlink when the tool is gone' do
      File.symlink(git_dir.join('config-delta.inc').to_s, link.to_s)
      allow(PathUtils).to receive(:command_exists?).with('delta').and_return(false)

      quietly { described_class.send(:_ensure_gitconfig_tool_symlink, 'delta') }

      expect(link).not_to be_symlink
    end

    it 'keeps a stale symlink in dry-run mode' do
      File.symlink(git_dir.join('config-delta.inc').to_s, link.to_s)
      allow(PathUtils).to receive(:command_exists?).with('delta').and_return(false)

      output = quietly { described_class.send(:_ensure_gitconfig_tool_symlink, 'delta', dry_run: true) }

      expect(link).to be_symlink
      expect(output).to match(/Would remove/)
    end
  end

  describe '.run in dry-run mode' do
    it 'passes dry_run on to the ssh and gitconfig helpers' do
      stub_const('EnvVars::DOTFILES_DIR', tmp.join('dotfiles'))
      tmp.join('dotfiles', 'files').mkpath
      expect(described_class).to receive(:_ensure_ssh_include_line).with(dry_run: true)
      expect(described_class).to receive(:_ensure_gitconfig_tool_symlink).exactly(4).times.with(anything, hash_including(dry_run: true))

      quietly { described_class.run(dry_run: true) }
    end
  end
end
