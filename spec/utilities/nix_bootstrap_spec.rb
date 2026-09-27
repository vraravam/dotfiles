# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'nix_bootstrap'

RSpec.describe NixBootstrap do
  around do |example|
    Dir.mktmpdir('nix-bootstrap-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let(:flake) { "#{tmp.join('dotfiles', 'nix')}#default" }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOME', tmp)
    stub_const('EnvVars::DOTFILES_DIR', tmp.join('dotfiles'))
    stub_const('NixBootstrap::PROFILE_BIN', tmp.join('profile-bin'))
    stub_const('NixBootstrap::STALE_SUDO_LOCAL', tmp.join('sudo_local'))
    allow(CommandUtils).to receive(:run_interactive).and_return(true)
    allow(CommandUtils).to receive(:curl_opts).with(bootstrap: true).and_return(['--retry', '5'])
    allow(PathUtils).to receive(:append_to_path)
    allow(PathUtils).to receive(:command_exists?).and_return(false)
  end

  after { Logging.state.reset! }

  def quietly
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  describe '.install' do
    it 'does nothing but put nix on PATH when it is already installed' do
      allow(PathUtils).to receive(:command_exists?).with('nix').and_return(true)
      expect(CommandUtils).not_to receive(:run_interactive)
      expect(PathUtils).to receive(:append_to_path).with(tmp.join('profile-bin'))

      expect(quietly { described_class.install }).to be true
    end

    it 'downloads the installer and runs it non-interactively, then puts nix on PATH' do
      allow(PathUtils).to receive(:command_exists?).with('nix').and_return(false, true)
      expect(CommandUtils).to receive(:run_interactive).with('curl', '--retry', '5', '-fsSL', %r{\Ahttps://install\.determinate\.systems/nix\?\d+\z}, '-o', String).ordered.and_return(true)
      expect(CommandUtils).to receive(:run_interactive).with('sh', String, 'install', '--no-confirm').ordered.and_return(true)
      expect(PathUtils).to receive(:append_to_path).with(tmp.join('profile-bin'))

      expect(quietly { described_class.install }).to be true
    end

    it 'removes the downloaded installer afterwards' do
      path = nil
      allow(PathUtils).to receive(:command_exists?).with('nix').and_return(false, true)
      allow(CommandUtils).to receive(:run_interactive).with('curl', any_args) do |*args|
        path = args.last
        true
      end

      quietly { described_class.install }

      expect(path).not_to be_nil
      expect(File).not_to exist(path)
    end

    it 'is false, recording an error, when the download fails' do
      allow(CommandUtils).to receive(:run_interactive).with('curl', any_args).and_return(false)
      expect(CommandUtils).not_to receive(:run_interactive).with('sh', any_args)

      expect(quietly { described_class.install }).to be false
      expect(Logging.step_errors.join).to match(/Failed to download the Nix installation script/)
    end

    it 'is false, recording an error, when the installer fails' do
      allow(CommandUtils).to receive(:run_interactive).with('sh', any_args).and_return(false)

      expect(quietly { described_class.install }).to be false
      expect(Logging.step_errors.join).to match(/Nix installation failed/)
    end

    it 'is false, recording an error, when nix is still not on PATH after installing' do
      expect(quietly { described_class.install }).to be false
      expect(Logging.step_errors.join).to match(/'nix' command not found in PATH after installation/)
    end
  end

  describe '.apply_configuration' do
    let(:sudo) { ['sudo', '--preserve-env=USER,USERNAME,HOME,PATH,DOTFILES_DIR'] }

    before { allow(SetupLoginItem).to receive(:register_managed).and_return(true) }

    it 'registers the managed login items after the switch, even when it failed, without changing the result' do
      allow(CommandUtils).to receive(:run_interactive).and_return(false)
      expect(SetupLoginItem).to receive(:register_managed).and_return(false)

      expect(quietly { described_class.apply_configuration }).to be false
    end

    it 'switches through darwin-rebuild when it exists, keeping the needed environment through sudo' do
      allow(PathUtils).to receive(:command_exists?).with('darwin-rebuild').and_return(true)
      expect(CommandUtils).to receive(:run_interactive).with(*sudo, 'darwin-rebuild', 'switch', '--flake', flake, '--impure').and_return(true)

      expect(quietly { described_class.apply_configuration }).to be true
    end

    it 'bootstraps darwin-rebuild through nix run on the first-ever activation' do
      expect(CommandUtils).to receive(:run_interactive).with(*sudo, 'nix', '--extra-experimental-features', 'nix-command flakes', 'run', 'nix-darwin', '--', 'switch', '--flake', flake, '--impure').and_return(true)

      expect(quietly { described_class.apply_configuration }).to be true
    end

    it 'records a warning and returns false when the switch fails' do
      allow(CommandUtils).to receive(:run_interactive).and_return(false)

      expect(quietly { described_class.apply_configuration }).to be false
      expect(Logging.step_warnings.join).to match(/darwin-rebuild switch encountered errors/)
    end

    context 'with a stale /etc/pam.d/sudo_local from an older version of the setup' do
      let(:stale) { tmp.join('sudo_local') }

      it 'moves it aside once, before the switch' do
        stale.write("auth sufficient pam_tid.so\n")
        expect(CommandUtils).to receive(:run_interactive).with('sudo', 'mv', stale.to_s, "#{stale}.before-nix-darwin").ordered.and_return(true)
        expect(CommandUtils).to receive(:run_interactive).with('sudo', any_args).ordered.and_return(true)

        quietly { described_class.apply_configuration }
      end

      it 'leaves it alone once the backup exists' do
        stale.write("x\n")
        tmp.join('sudo_local.before-nix-darwin').write("y\n")
        expect(CommandUtils).not_to receive(:run_interactive).with('sudo', 'mv', any_args)

        quietly { described_class.apply_configuration }
      end

      it 'records a warning, and still tries the switch, when it cannot be moved' do
        stale.write("x\n")
        allow(CommandUtils).to receive(:run_interactive).with('sudo', 'mv', any_args).and_return(false)
        expect(CommandUtils).to receive(:run_interactive).with('sudo', '--preserve-env=USER,USERNAME,HOME,PATH,DOTFILES_DIR', any_args).and_return(true)

        quietly { described_class.apply_configuration }

        expect(Logging.step_warnings.join).to match(/Could not move/)
      end
    end

    it 'does nothing about sudo_local when there is none' do
      expect(CommandUtils).not_to receive(:run_interactive).with('sudo', 'mv', any_args)

      quietly { described_class.apply_configuration }
    end
  end
end
