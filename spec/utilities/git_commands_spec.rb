# frozen_string_literal: true

require 'git_commands'

RSpec.describe GitCommands do
  let(:folder) { '/work/repo' }

  before do
    allow(Logging).to receive(:section_header)
    allow(Logging).to receive(:info)
    allow(Logging).to receive(:debug)
    allow(Logging).to receive(:warn)
    allow(Logging).to receive(:record_warning)
  end

  describe '.parse_args' do
    it 'takes the first non-switch argument as the folder and the rest of the --switches' do
      folder, switches = described_class.parse_args(['--force-with-lease', '/a/b', '--expire=now', '/ignored'])

      expect(folder).to eq('/a/b')
      expect(switches).to eq(['--force-with-lease', '--expire=now'])
    end

    it 'defaults the folder to the current directory' do
      folder, switches = described_class.parse_args(['--x'])

      expect(folder).to eq(Dir.pwd)
      expect(switches).to eq(['--x'])
    end
  end

  describe '.run' do
    it 'rejects a command it does not implement' do
      expect { described_class.run(command: 'rebase') }.to raise_error(ArgumentError, /Unknown command 'rebase'/)
    end

    it 'hands over to the override script (with only the switches) when one exists' do
      override = Pathname.new('/bin/cc-repo.rb')
      allow(GitOverrides).to receive(:skip?).and_return(false)
      allow(GitOverrides).to receive(:script_for).with('cc', folder).and_return(override)
      expect(described_class).to receive(:exec_override).with(override, folder, ['--expire=now'])
      allow(described_class).to receive(:cc)

      described_class.run(command: 'cc', args: [folder, '--expire=now'])
    end

    it 'runs the default implementation, with a header, when there is no override' do
      allow(GitOverrides).to receive(:skip?).and_return(false)
      allow(GitOverrides).to receive(:script_for).and_return(nil)
      expect(described_class).to receive(:push).with(args: [folder], header: true)

      expect(described_class.run(command: 'push', args: [folder])).to be true
    end

    it 'never looks for an override when override detection is switched off' do
      allow(GitOverrides).to receive(:skip?).and_return(true)
      expect(GitOverrides).not_to receive(:script_for)
      allow(described_class).to receive(:pull)

      described_class.run(command: 'pull', args: [folder])
    end
  end

  describe 'commands on a folder that is not a git repo' do
    before { allow(GitProcessor).to receive(:repo?).with(folder).and_return(false) }

    %i[push pull cc].each do |command|
      it "#{command} warns and runs no git command" do
        expect(CommandUtils).not_to receive(:run_interactive)
        expect(Logging).to receive(:warn).with(/is not a git repo/)

        expect(described_class.public_send(command, args: [folder])).to be true
      end
    end
  end

  describe '.push' do
    before { allow(GitProcessor).to receive(:repo?).and_return(true) }

    it 'runs git push under with-retry using a wall-clock timeout, forwarding switches' do
      expect(CommandUtils).to receive(:run_interactive) do |env, *cmd|
        expect(env).to include(GitOverrides::SKIP_ENV_VAR => '1')
        expect(cmd).to eq(['git', 'with-retry', '60', '3', File::NULL, '-', 'git', '-C', folder, 'push', '--force-with-lease'])
        true
      end

      described_class.push(args: [folder, '--force-with-lease'], header: false)
    end

    it 'records a warning, but still returns true, when the push fails' do
      allow(CommandUtils).to receive(:run_interactive).and_return(false)
      expect(Logging).to receive(:record_warning).with(/Failed to push/)

      expect(described_class.push(args: [folder], header: false)).to be true
    end
  end

  describe '.pull' do
    before { allow(GitProcessor).to receive(:repo?).and_return(true) }

    def stub_config_flag(value)
      git = instance_double(GitProcessor)
      allow(GitProcessor).to receive(:new).with(dir: folder).and_return(git)
      allow(git).to receive(:config_bool).with('pull.allowResetOnDivergedHistory').and_return(value == 'true')
    end

    it 'does nothing further when the pull succeeds' do
      allow(CommandUtils).to receive(:run_interactive).and_return(true)
      expect(GitProcessor).not_to receive(:new)

      described_class.pull(args: [folder], header: false)
    end

    it 'leaves a failed pull alone when the repo has not opted in to reset-on-diverged-history' do
      allow(CommandUtils).to receive(:run_interactive).and_return(false)
      stub_config_flag('false')
      expect(described_class).not_to receive(:_git).with(folder, 'fo', '--rebase')

      described_class.pull(args: [folder], header: false)
    end

    it 'falls back to fo --rebase for a repo that opted in, and warns if that fails too' do
      allow(CommandUtils).to receive(:run_interactive).and_return(false)
      stub_config_flag('true')
      expect(described_class).to receive(:_git).with(folder, 'fo', '--rebase').and_return(false)
      expect(Logging).to receive(:record_warning).with(/Failed to reconcile/)

      described_class.pull(args: [folder], header: false)
    end
  end

  describe '.cc' do
    before { allow(GitProcessor).to receive(:repo?).and_return(true) }

    it "forwards the switches to the 'git cc' alias" do
      expect(described_class).to receive(:_git).with(folder, 'cc', '--expire=now').and_return(true)

      described_class.cc(args: [folder, '--expire=now'], header: false)
    end
  end

  describe '.upreb' do
    it 'rebases every other branch first and finishes on the branch that was checked out' do
      git = instance_double(GitProcessor, current_branch: 'main', local_branches: %w[main feature fix])
      allow(GitProcessor).to receive(:new).with(dir: folder).and_yield(git)
      switched = []
      allow(described_class).to receive(:_git) do |_dir, *args, **_opts|
        switched << args.last if args.first == 'switch'
        true
      end
      allow(described_class).to receive(:_rebase_if_symmetric_divergence)

      described_class.upreb(args: [folder], header: false)

      expect(switched).to eq(%w[feature fix main])
    end
  end
end
