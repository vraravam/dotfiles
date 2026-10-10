# frozen_string_literal: true

require 'git_processor'
require 'tmpdir'

RSpec.describe GitProcessor::Maintenance do
  around do |example|
    Dir.mktmpdir('git-maintenance-spec-') do |dir|
      @tmp = Pathname.new(dir)
      GitProcessor.repo_cache = {}
      example.run
    end
  end

  let(:tmp) { @tmp }
  let(:git) { GitProcessor.new(dir: tmp) }
  let(:dry) { GitProcessor.new(dir: tmp, dry_run: true) }

  before { Logging.state.reset! }
  after { Logging.state.reset! }

  def init_repo
    system('git', '-C', tmp.to_s, 'init', '--quiet', '--initial-branch=main')
  end

  describe 'lock and hook cleanup' do
    before { init_repo }

    it 'deletes a stale index.lock and tolerates its absence' do
      lock = tmp.join('.git', 'index.lock')
      lock.write('')

      git.delete_index_lock
      expect(lock).not_to exist
      expect { git.delete_index_lock }.not_to raise_error
    end

    it 'deletes a stale commit-graph chain lock and tolerates its absence' do
      lock = tmp.join('.git', 'objects', 'info', 'commit-graphs', 'commit-graph-chain.lock')
      lock.dirname.mkpath
      lock.write('')

      git.delete_commit_graph_lock
      expect(lock).not_to exist
      expect { git.delete_commit_graph_lock }.not_to raise_error
    end

    it 'removes the hooks directory' do
      expect(tmp.join('.git', 'hooks')).to be_directory

      git.delete_hooks_dir

      expect(tmp.join('.git', 'hooks')).not_to exist
    end

    it 'touches nothing in dry-run mode' do
      lock = tmp.join('.git', 'index.lock')
      lock.write('')

      expect { dry.delete_index_lock }.to output(/Would delete/).to_stdout
      expect { dry.delete_hooks_dir }.to output(/Would remove/).to_stdout
      expect(lock).to exist
      expect(tmp.join('.git', 'hooks')).to be_directory
    end
  end

  describe '#compress / #build_commit_graph' do
    it 'report success without running git in dry-run mode' do
      expect { expect(dry.compress).to be true }.to output(/Would compress/).to_stdout
      expect { expect(dry.build_commit_graph).to be true }.to output(/Would build commit graph/).to_stdout
    end

    it 'return false for a directory that is not a git repo' do
      expect(git.compress).to be false
      expect(git.build_commit_graph).to be false
    end

    it 'builds a commit graph for a real repo' do
      init_repo
      system('git', '-C', tmp.to_s, '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '--allow-empty', '-m', 'c', '--quiet')
      GitProcessor.repo_cache = {}

      expect(git.build_commit_graph).to be true
    end
  end

  describe '#bundle_create' do
    it 'is true without writing anything in dry-run mode' do
      out = tmp.join('x.bundle')

      expect { expect(dry.bundle_create(file: out)).to be true }.to output(/Would run/).to_stdout
      expect(out).not_to exist
    end

    it 'is false for a directory that is not a git repo' do
      expect(git.bundle_create(file: tmp.join('x.bundle'))).to be false
    end

    it 'writes a bundle of a real repo' do
      init_repo
      system('git', '-C', tmp.to_s, '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '--allow-empty', '-m', 'c', '--quiet')
      GitProcessor.repo_cache = {}
      out = tmp.join('out', 'x.bundle')

      expect(git.bundle_create(file: out)).to be true
      expect(out).to be_file
    end
  end

  describe '#pack_size_human / #pack_size_mb' do
    def stub_size(value)
      allow(CommandUtils).to receive(:query)
                               .with({ 'GIT_SIZE_QUIET' => '1' }, 'git', '-C', tmp.to_s, 'size').and_return(value)
    end

    it 'passes GIT_SIZE_QUIET to the child only, never to this process' do
      stub_size('2.00 GiB')

      expect(git.pack_size_human).to eq('2.00 GiB')
      expect(ENV).not_to have_key('GIT_SIZE_QUIET')
    end

    it 'converts each unit to megabytes' do
      { '2.00 GiB' => 2048.0, '1.50 MiB' => 1.5, '512 KiB' => 0.5, '1048576 bytes' => 1.0 }.each do |text, mb|
        stub_size(text)
        expect(git.pack_size_mb).to eq(mb)
      end
    end

    it 'is 0.0 when the size is empty or has an unknown unit' do
      stub_size('')
      expect(git.pack_size_mb).to eq(0.0)
      stub_size('3 parsecs')
      expect(git.pack_size_mb).to eq(0.0)
    end
  end
end
