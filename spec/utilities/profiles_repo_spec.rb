# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'profiles_repo'

RSpec.describe ProfilesRepo do
  around do |example|
    Dir.mktmpdir('profiles-repo-spec-') do |dir|
      @tmp = Pathname(dir)
      GitProcessor.repo_cache = {}
      example.run
    end
  end

  let(:tmp) { @tmp }

  before do
    Logging.state.reset!
    stub_const('EnvVars::PERSONAL_PROFILES_DIR', tmp)
    described_class.instance_variable_set(:@_profiles_git, nil)
  end

  after do
    described_class.instance_variable_set(:@_profiles_git, nil)
    Logging.state.reset!
  end

  describe '.check_size_limit' do
    it 'does nothing when the profiles dir is not a git repo' do
      expect(GitProcessor).not_to receive(:new)

      described_class.check_size_limit
    end

    context 'when the profiles dir is a git repo' do
      let(:git) { instance_double(GitProcessor) }

      before do
        allow(GitProcessor).to receive(:repo?).with(tmp).and_return(true)
        allow(GitProcessor).to receive(:new).with(dir: tmp).and_return(git)
      end

      it 'records an error naming the size and limit when the pack exceeds the limit' do
        allow(git).to receive_messages(pack_size_mb: 3000.0, pack_size_human: '2.93 GiB')

        expect { described_class.check_size_limit(limit_gb: 2) }.to output.to_stdout.or output.to_stderr
        expect(Logging.step_errors.last).to match(/2\.93 GiB.*exceeds 2GB threshold/)
      end

      it 'records nothing when the pack is within the limit' do
        allow(git).to receive(:pack_size_mb).and_return(10.0)
        expect(git).not_to receive(:pack_size_human)

        described_class.check_size_limit(limit_gb: 2)

        expect(Logging.step_errors).to be_empty
      end
    end
  end

  describe '.find_chrome_folders' do
    it 'returns only chrome directories that are git repos' do
      repo = tmp.join('ZenProfile', 'Profiles', 'abc.Profile', 'chrome')
      plain = tmp.join('FirefoxProfile', 'Profiles', 'def.Profile', 'chrome')
      [repo, plain].each(&:mkpath)
      system('git', '-C', repo.to_s, 'init', '--quiet')
      GitProcessor.repo_cache = {}

      expect(described_class.find_chrome_folders).to eq([repo])
    end
  end

  describe '.capture_and_commit' do
    it 'is false without touching git when the profiles dir is not a repo' do
      expect(GitProcessor).not_to receive(:new)

      expect { expect(described_class.capture_and_commit).to be false }.to output.to_stdout.or output.to_stderr
    end

    it "returns commit_all's result for a repo, reusing one GitProcessor" do
      git = instance_double(GitProcessor, commit_all: true)
      allow(GitProcessor).to receive(:repo?).with(tmp).and_return(true)
      allow(GitProcessor).to receive(:new).with(dir: tmp).and_return(git)

      expect(described_class.capture_and_commit).to be true
      expect(git).to have_received(:commit_all)
    end
  end

  describe '.prune_old_session_backups' do
    let(:backup_dir) { tmp.join('ZenProfile', 'Profiles', 'p', 'zen-sessions-backup') }

    def git(*args)
      system('git', '-C', tmp.to_s, *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(' ')} failed")
    end

    def tracked
      `git -C #{tmp} ls-files`.lines.map(&:strip)
    end

    before do
      backup_dir.mkpath
      git('init', '--quiet')
      git('config', 'user.email', 'spec@example.com')
      git('config', 'user.name', 'spec')
      GitProcessor.repo_cache = {}
    end

    it 'unpins only the backups older than the cutoff, in one git call, and keeps the files on disk' do
      today = Time.now.strftime('%Y-%m-%d')
      old = %w[2020-01-01-00 2020-01-02-13 2020-01-03-23].map { |stamp| "zen-sessions-#{stamp}.jsonlz4" }
      fresh = "zen-sessions-#{today}-10.jsonlz4"
      (old + [fresh, 'clean.jsonlz4']).each { |name| backup_dir.join(name).write('x') }
      git('add', '-A')

      expect_any_instance_of(GitProcessor).to receive(:rm_cached).once.and_call_original
      expect { described_class.prune_old_session_backups }.to output(/Pruned .*3.* session backup/).to_stdout

      names = tracked.map { |path| File.basename(path) }
      expect(names).to contain_exactly(fresh, 'clean.jsonlz4')
      old.each { |name| expect(backup_dir.join(name)).to exist }
    end

    it 'sends large sets in batches' do
      stub_const('ProfilesRepo::RM_BATCH_SIZE', 2)
      5.times { |i| backup_dir.join("zen-sessions-2020-01-0#{i + 1}-00.jsonlz4").write('x') }
      git('add', '-A')

      expect_any_instance_of(GitProcessor).to receive(:rm_cached).exactly(3).times.and_call_original
      expect { described_class.prune_old_session_backups }.to output.to_stdout

      expect(tracked).to be_empty
    end

    it 'leaves files whose name carries no date alone' do
      backup_dir.join('zen-sessions-latest.jsonlz4').write('x')
      git('add', '-A')

      expect_any_instance_of(GitProcessor).not_to receive(:rm_cached)
      described_class.prune_old_session_backups

      expect(tracked.size).to eq(1)
    end
  end
end
