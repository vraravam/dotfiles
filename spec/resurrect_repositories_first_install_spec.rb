# encoding: utf-8
# frozen_string_literal: true

require 'fileutils'
require 'rbconfig'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'git_processor'
require_relative '../scripts/resurrect-repositories'

# FIRST_INSTALL behavior: clones stay shallow, a repository cloned in this run is not fetched again,
# and one detached low-priority background batch completes everything after the last catalogue.
RSpec.describe ResurrectRepositories, 'first install' do
  let(:home) { EnvVars::HOME }
  let(:log) { home.join('Downloads', 'unshallow-batch.log') }
  let(:ruby) { RbConfig.ruby }

  around do |example|
    with_env('FIRST_INSTALL' => '1', 'FRESH_INSTALL_SKIP_BACKGROUND_UNSHALLOW' => nil) { example.run }
  end

  before do
    Logging.state.reset!
    described_class.instance_variable_set(:@batch_started, false)
  end

  after { Logging.state.reset! }

  describe '.unshallow_batch_command' do
    subject(:command) { described_class.unshallow_batch_command }

    it 'is the user\'s "all unshallow" (git unshallow via run-all.rb, FOLDER=HOME, MAXDEPTH=7) at the lowest priority in its own session' do
      run_all = EnvVars::DOTFILES_DIR.join('scripts', 'run-all.rb').to_s
      expect(command[:argv]).to eq(
        [ruby, '--disable-gems', '-e', 'Process.setsid; exec(*ARGV)',
         'nice', '-n', '19', ruby, '--disable-gems', run_all, 'git', 'unshallow']
      )
      expect(command[:env]).to include('FOLDER' => home.to_s, 'MAXDEPTH' => '7')
    end

    it 'runs as a fresh top-level script: no first-install mode, no depth, no issues file of the install' do
      expect(command[:env]).to include('FIRST_INSTALL' => nil, '_DOTFILES_SCRIPT_DEPTH' => '0', '_DOTFILES_ISSUES_FILE' => nil)
    end

    it 'logs to ~/Downloads/unshallow-batch.log' do
      expect(command[:log]).to eq(log)
    end

    it 'passes the resurrection FILTER on (and removes an inherited one otherwise)' do
      expect(described_class.unshallow_batch_command(filter: 'oss')[:env]).to include('FILTER' => 'oss')
      expect(described_class.unshallow_batch_command(filter: nil)[:env]).to include('FILTER' => nil)
      expect(described_class.unshallow_batch_command(filter: '')[:env]).to include('FILTER' => nil)
    end
  end

  describe '._start_unshallow_batch' do
    before do
      # Never create the real ~/Downloads.
      allow_any_instance_of(Pathname).to receive(:mkpath)
      allow(Process).to receive(:detach)
    end

    def start(filter = nil)
      described_class.send(:_start_unshallow_batch, filter)
    end

    it 'spawns the detached batch exactly once with the exact argv, env, log and no tty' do
      expected = described_class.unshallow_batch_command(filter: nil)
      redirects = { in: File::NULL, out: [log.to_s, 'a'], err: %i[child out], chdir: home.to_s }
      expect(Process).to receive(:spawn).once.with(expected[:env], *expected[:argv], **redirects).and_return(4242)
      expect(Process).to receive(:detach).with(4242)

      expect { start }.to output(%r{background unshallow batch.*4242.*~/Downloads/unshallow-batch\.log}m).to_stdout
      expect { start }.not_to output.to_stdout # a second call in the same run does nothing
    end

    it 'does nothing outside a first install' do
      expect(Process).not_to receive(:spawn)

      with_env('FIRST_INSTALL' => nil) { start }
    end

    %w[1 true yes].each do |value|
      it "does nothing when FRESH_INSTALL_SKIP_BACKGROUND_UNSHALLOW=#{value}" do
        expect(Process).not_to receive(:spawn)

        with_env('FRESH_INSTALL_SKIP_BACKGROUND_UNSHALLOW' => value) { start }
      end
    end

    it 'warns (without failing) when the batch cannot be started' do
      allow(Process).to receive(:spawn).and_raise(Errno::ENOENT)

      expect { start }.to output.to_stdout
      expect(Logging.step_warnings.last).to match(/Could not start the background unshallow batch.*all unshallow/)
    end
  end

  describe '._run_resurrect_all' do
    let(:configs) { Pathname(Dir.mktmpdir('resurrect-all-spec-')) }

    before do
      stub_const('EnvVars::PERSONAL_CONFIGS_DIR', configs)
      allow(DevEnvironment).to receive(:setup_dev_environment)
      allow(GitWorkspace).to receive(:regenerate_repo_aliases)
    end

    after { FileUtils.rm_rf(configs) }

    it 'starts the batch after the catalogues are resurrected and before the dev-environment setup' do
      configs.join('repositories-x.yml').write([].to_yaml)
      order = []
      allow(described_class).to receive(:_run_resurrect) { order << :catalogue && false }
      allow(described_class).to receive(:_start_unshallow_batch) { |filter| order << [:batch, filter] }
      allow(DevEnvironment).to receive(:setup_dev_environment) { order << :dev_environment }

      expect { described_class.send(:_run_resurrect_all, 'oss') }.to output.to_stdout

      expect(order).to eq([:catalogue, [:batch, 'oss'], :dev_environment])
    end

    it 'starts it even when no catalogue exists (the bootstrap repositories are shallow too)' do
      expect(described_class).to receive(:_start_unshallow_batch)

      expect { described_class.send(:_run_resurrect_all, nil) }.to output.to_stdout
    end
  end

  describe 'fetching a repository that was just cloned' do
    let(:valid) { { 'folder' => '/tmp/rr-spec-not-a-repo/repo', 'remote' => 'https://example.com/a/b.git' } }
    let(:repo) { ResurrectRepositories::RepositoryConfig.from_hash(valid) }
    let(:git) { instance_double(GitProcessor, delete_index_lock: nil, delete_commit_graph_lock: nil, fetch_all: ['', '', ok]) }
    let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }

    before do
      allow(PathUtils).to receive(:ensure_directories_exist)
      allow(GitProcessor).to receive(:new).and_return(git)
      allow(GitProcessor).to receive(:clone_repo_into).and_return(true)
      allow(git).to receive(:each_remote).and_yield('origin', valid['remote'])
      allow(git).to receive(:add_remote).and_return(['', '', ok])
    end

    def resurrect(config = repo)
      result = nil
      output = capture_stdout { result = described_class.send(:_resurrect_each, config) }
      [result, output]
    end

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end

    it 'skips the fetch for a fresh clone with no other remotes' do
      allow(GitProcessor).to receive(:repo?).with(valid['folder']).and_return(false)
      expect(git).not_to receive(:fetch_all)

      result, output = resurrect

      expect(result).to be true
      expect(output).to match(/Just cloned.*skipping the fetch/)
    end

    it 'still fetches a repository that already existed' do
      allow(GitProcessor).to receive(:repo?).with(valid['folder']).and_return(true)
      expect(git).to receive(:fetch_all).once.and_return(['', '', ok])

      resurrect
    end

    it 'still fetches a fresh clone that has other remotes to fetch' do
      allow(GitProcessor).to receive(:repo?).with(valid['folder']).and_return(false)
      with_other = ResurrectRepositories::RepositoryConfig.from_hash(valid.merge('other_remotes' => { 'mirror' => 'https://m/x.git' }))
      allow(git).to receive(:each_remote).and_yield('origin', valid['remote'])
      expect(git).to receive(:fetch_all).once.and_return(['', '', ok])

      resurrect(with_other)
    end

    it 'still fetches when the background batch is opted out of' do
      allow(GitProcessor).to receive(:repo?).with(valid['folder']).and_return(false)
      expect(git).to receive(:fetch_all).once.and_return(['', '', ok])

      with_env('FRESH_INSTALL_SKIP_BACKGROUND_UNSHALLOW' => '1') { resurrect }
    end

    it 'still fetches outside a first install' do
      allow(GitProcessor).to receive(:repo?).with(valid['folder']).and_return(false)
      expect(git).to receive(:fetch_all).once.and_return(['', '', ok])

      with_env('FIRST_INSTALL' => nil) { resurrect }
    end
  end
end
