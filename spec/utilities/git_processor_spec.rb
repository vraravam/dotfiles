# frozen_string_literal: true

require 'git_processor'
require 'tmpdir'

RSpec.describe GitProcessor do
  around do |example|
    Dir.mktmpdir('git-processor-spec-') do |dir|
      @tmp = Pathname.new(dir)
      # Each example gets a brand new tmpdir, but GitProcessor.repo? caches by
      # absolute path at the class level -- reset it so a path reused across
      # examples (unlikely, but not guaranteed impossible) never returns a
      # stale cached result from a previous example.
      described_class.repo_cache = {}
      example.run
    end
  end

  let(:tmp) { @tmp }

  describe '.repo?' do
    it 'is false for a plain directory' do
      expect(described_class.repo?(tmp)).to be false
    end

    it 'is true once initialized' do
      system('git', '-C', tmp.to_s, 'init', '--quiet', '--initial-branch=main')
      expect(described_class.repo?(tmp)).to be true
    end

    it 'is false for nil' do
      expect(described_class.repo?(nil)).to be false
    end

    it 'is false for an empty string' do
      expect(described_class.repo?('')).to be false
    end
  end

  describe '.clone_repo_into' do
    let(:url) { 'https://github.com/example/repo.git' }
    let(:dest) { '/tmp/example-repo' }

    # Stubs CommandUtils.run_interactive and captures its arguments -- this only tests
    # the positional-argument assembly clone_repo_into builds up before shelling out,
    # not the shell function itself (which .shellrc's own bats-style expectations, if
    # any, would cover -- there is no zsh/.shellrc dependency in this Ruby-level spec).
    def captured_call(**kwargs)
      captured = nil
      allow(CommandUtils).to receive(:run_interactive) { |*args| captured = args }
      described_class.clone_repo_into(url, dest, **kwargs)
      captured
    end

    it 'passes only url and dest when branch/bundle/post_checkout_hook are all absent' do
      _zsh, _dash_c, cmd = captured_call

      expect(cmd).to end_with("clone_repo_into #{url} #{dest}")
    end

    it 'emits only branch when just branch is given' do
      _zsh, _dash_c, cmd = captured_call(branch: 'main')

      expect(cmd).to end_with("clone_repo_into #{url} #{dest} main")
    end

    it 'emits branch (as an empty placeholder) and bundle when bundle is given without a branch' do
      _zsh, _dash_c, cmd = captured_call(bundle: '/tmp/x.bundle')

      expect(cmd).to end_with("clone_repo_into #{url} #{dest} '' /tmp/x.bundle")
    end

    it 'emits empty branch/bundle placeholders plus the hook when only post_checkout_hook is given -- ' \
       'the hook must apply regardless of whether a bundle is used for this clone' do
      _zsh, _dash_c, cmd = captured_call(post_checkout_hook: 'set_ssh_folder_permissions')

      expect(cmd).to end_with("clone_repo_into #{url} #{dest} '' '' set_ssh_folder_permissions")
    end

    it 'emits branch, the real bundle path, and the hook when all three are given' do
      _zsh, _dash_c, cmd = captured_call(branch: 'main', bundle: '/tmp/x.bundle', post_checkout_hook: 'set_ssh_folder_permissions')

      expect(cmd).to end_with("clone_repo_into #{url} #{dest} main /tmp/x.bundle set_ssh_folder_permissions")
    end
  end

  describe '#repo?' do
    subject(:git) { described_class.new(dir: tmp) }

    it 'is false for a plain directory' do
      expect(git.repo?).to be false
    end

    it 'is true once initialized' do
      system('git', '-C', tmp.to_s, 'init', '--quiet', '--initial-branch=main')
      expect(git.repo?).to be true
    end
  end

  context 'with an initialized repo' do
    subject(:git) { described_class.new(dir: tmp) }

    before do
      system('git', '-C', tmp.to_s, 'init', '--quiet', '--initial-branch=main')
      system('git', '-C', tmp.to_s, 'config', 'user.email', 'test@example.com')
      system('git', '-C', tmp.to_s, 'config', 'user.name', 'Test User')
    end

    describe '#current_branch' do
      it 'reports the initial branch name' do
        expect(git.current_branch).to eq('main')
      end
    end

    describe '#commit_count' do
      it 'is 0 for a brand new repo' do
        expect(git.commit_count).to eq(0)
      end

      it 'reflects the number of commits after committing' do
        File.write(tmp.join('file.txt'), 'content')
        git.add('file.txt')
        git.commit('first commit')

        expect(git.commit_count).to eq(1)
      end
    end

    describe '#commit_count with a range' do
      it 'counts only the commits in the range, and is 0 when it cannot be resolved' do
        File.write(tmp.join('a.txt'), 'a')
        git.add('a.txt')
        git.commit('one')
        File.write(tmp.join('b.txt'), 'b')
        git.add('b.txt')
        git.commit('two')

        expect(git.commit_count(range: 'HEAD~1..HEAD')).to eq(1)
        expect(git.commit_count(range: 'HEAD..@{u}')).to eq(0)
      end
    end

    describe '#config_bool' do
      it 'honours the default for an unset key' do
        expect(git.config_bool('some.flag')).to be false
        expect(git.config_bool('some.flag', default: true)).to be true
      end

      it 'normalises git boolean spellings' do
        system('git', '-C', tmp.to_s, 'config', 'some.flag', 'yes')
        expect(described_class.new(dir: tmp).config_bool('some.flag')).to be true

        system('git', '-C', tmp.to_s, 'config', 'some.flag', 'off')
        expect(described_class.new(dir: tmp).config_bool('some.flag')).to be false
      end
    end

    describe '#local_branches' do
      it 'lists every local branch by short name' do
        File.write(tmp.join('a.txt'), 'a')
        git.add('a.txt')
        git.commit('one')
        system('git', '-C', tmp.to_s, 'branch', 'feature')

        expect(git.local_branches).to contain_exactly('main', 'feature')
      end
    end

    describe '#same_content_as?' do
      it 'is true for an identical tree and false after a change' do
        File.write(tmp.join('a.txt'), 'a')
        git.add('a.txt')
        git.commit('one')

        expect(git.same_content_as?('HEAD')).to be true
        File.write(tmp.join('a.txt'), 'changed')
        expect(git.same_content_as?('HEAD')).to be false
      end
    end

    describe '#config_value / #config_set' do
      it 'returns nil for an unset key' do
        expect(git.config_value('some.unset.key')).to be_nil
      end

      it 'returns the value after setting it' do
        _stdout, _stderr, status = git.config_set('some.key', 'some-value')

        expect(status.success?).to be true
        expect(git.config_value('some.key')).to eq('some-value')
      end
    end

    describe '#add / #commit' do
      it 'stages and commits a file' do
        File.write(tmp.join('file.txt'), 'content')

        _stdout, _stderr, add_status = git.add('file.txt')
        expect(add_status.success?).to be true

        _stdout, _stderr, commit_status = git.commit('add file')
        expect(commit_status.success?).to be true
        expect(git.commit_count).to eq(1)
      end
    end

    describe '#stage_all' do
      it 'stages all untracked files (equivalent to git add -A .)' do
        File.write(tmp.join('a.txt'), 'a')
        File.write(tmp.join('b.txt'), 'b')

        _stdout, _stderr, status = git.stage_all

        expect(status.success?).to be true
        expect(git.ls_files).to contain_exactly('a.txt', 'b.txt')
      end

      # Regression test: stage_all's dry-run branch used to only log a message
      # without returning a value, so callers destructuring the result (e.g.
      # `_stdout, _stderr, status = git.stage_all; status.success?`) crashed
      # with a NoMethodError on nil in dry-run mode. It must return the same
      # 3-tuple shape as every other dry-run-aware method (push, compress,
      # build_commit_graph, bundle_create).
      context 'when dry_run is true' do
        subject(:git) { described_class.new(dir: tmp, dry_run: true) }

        it 'returns a successful 3-tuple instead of nil, without touching the working tree' do
          File.write(tmp.join('untouched.txt'), 'content')

          _stdout, _stderr, status = git.stage_all

          expect(status.success?).to be true
          # Verified via a raw 'git status' call rather than git.ls_files -- ls_files
          # itself goes through _execute without read_only: true, so it would be
          # dry-run-mocked to an empty result regardless of what actually happened
          # on disk, which would make this assertion pass for the wrong reason.
          expect(`git -C #{tmp} status --porcelain`.strip).to eq('?? untouched.txt')
        end
      end
    end

    describe '#tag_exists?' do
      it 'is false when the tag does not exist' do
        expect(git.tag_exists?('v1.0.0')).to be false
      end

      it 'is true once the tag is created' do
        File.write(tmp.join('file.txt'), 'content')
        git.add('file.txt')
        git.commit('first commit')
        system('git', '-C', tmp.to_s, 'tag', 'v1.0.0')

        expect(git.tag_exists?('v1.0.0')).to be true
      end
    end

    describe '#remote_url / #add_remote' do
      it 'is nil when no remote is configured' do
        expect(git.remote_url).to be_nil
      end

      it 'returns the URL once a remote is added' do
        _stdout, _stderr, status = git.add_remote('origin', '/tmp/does-not-need-to-exist.git')

        expect(status.success?).to be true
        expect(git.remote_url).to eq('/tmp/does-not-need-to-exist.git')
        expect(git.remote_url(name: 'upstream')).to be_nil
      end
    end
  end

  describe '#init' do
    subject(:git) { described_class.new(dir: tmp) }

    it 'initializes a new repo with the requested initial branch' do
      _stdout, _stderr, status = git.init(initial_branch: 'trunk')

      expect(status.success?).to be true
      expect(git.repo?).to be true
      expect(git.current_branch).to eq('trunk')
    end
  end

  describe '#commit_all' do
    subject(:git) { described_class.new(dir: '/tmp/some-repo') }

    before do
      %i[delete_index_lock delete_commit_graph_lock delete_hooks_dir].each { |m| allow(git).to receive(m) }
      allow(git).to receive(:add)
      allow(git).to receive(:smart_commit).and_return(true)
    end

    it 'clears stale locks and hooks, then stages the whole repo by default and commits' do
      expect(git).to receive(:delete_index_lock).ordered
      expect(git).to receive(:delete_commit_graph_lock).ordered
      expect(git).to receive(:delete_hooks_dir).ordered
      expect(git).to receive(:add).with('.').ordered
      expect(git).to receive(:smart_commit).ordered

      expect(git.commit_all).to be true
    end

    it 'stages only the given paths' do
      expect(git).to receive(:add).with('a')
      expect(git).to receive(:add).with('b')
      expect(git).not_to receive(:add).with('.')

      git.commit_all(paths: %w[a b])
    end

    it "returns smart_commit's result" do
      allow(git).to receive(:smart_commit).and_return(false)

      expect(git.commit_all).to be false
    end
  end

  describe 'dry_run mode' do
    subject(:git) { described_class.new(dir: tmp, dry_run: true) }

    before do
      system('git', '-C', tmp.to_s, 'init', '--quiet', '--initial-branch=main')
      system('git', '-C', tmp.to_s, 'config', 'user.email', 'test@example.com')
      system('git', '-C', tmp.to_s, 'config', 'user.name', 'Test User')
    end

    it 'does not create commits via #commit' do
      File.write(tmp.join('file.txt'), 'content')

      _stdout, _stderr, status = git.commit('would-be commit')

      expect(status.success?).to be true
      expect(git.commit_count).to eq(0)
    end
  end
end
