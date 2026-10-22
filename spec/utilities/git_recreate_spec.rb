# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'git_processor'

# GitProcessor::Recreate is mixed into GitProcessor and leans on its public methods, so the
# examples use a real GitProcessor with those collaborators stubbed out (no git is run).
RSpec.describe GitProcessor::Recreate do
  subject(:git) { GitProcessor.new(dir: dir) }

  let(:dir) { Pathname('/tmp/spec-recreate-repo') }
  let(:ok) { instance_double(Process::Status, success?: true) }
  let(:failed) { instance_double(Process::Status, success?: false) }
  let(:remote_files) { %w[a.txt b.txt] }

  before do
    Logging.state.reset!
    allow(Logging).to receive(:info)
    allow(Logging).to receive(:success)
    allow(Logging).to receive(:warn)
    allow(Logging).to receive(:user_action)
  end

  after { Logging.state.reset! }

  describe '#verify_pre_recreation' do
    def stub_metadata(url: 'git@github.com:me/repo.git', name: 'Me', email: 'me@example.com', branch: 'main')
      allow(git).to receive_messages(remote_url: url, current_branch: branch)
      allow(git).to receive(:config_value).with('user.name').and_return(name)
      allow(git).to receive(:config_value).with('user.email').and_return(email)
    end

    it 'logs the metadata and stays quiet about errors when everything is present' do
      stub_metadata

      expect(Logging).not_to receive(:error)
      expect(Logging).to receive(:info).with(/Branch:.*main/)

      git.verify_pre_recreation(force: true)
    end

    it 'reports an error when a required value is missing' do
      stub_metadata(email: nil)

      expect(Logging).to receive(:error).with(/required git metadata values are missing/)

      git.verify_pre_recreation(force: false)
    end
  end

  describe '#verify_and_recreate_local_repo' do
    before do
      allow(git).to receive_messages(current_branch: 'main', fetch_all: ['', '', ok], ls_tree: remote_files,
                                     stage_all: ['', '', ok], ls_files: remote_files, commit_count: 1,
                                     default_commit_message: 'msg')
      allow(git).to receive(:commit).and_return(['', '', ok])
      allow(git).to receive(:_recreate).and_return(true)
      allow(git).to receive(:ls_tree).with('origin/main').and_return(remote_files)
      allow(git).to receive(:ls_tree).with('HEAD').and_return(remote_files)
    end

    it 'succeeds when the recreated repo has exactly the remote file list' do
      expect(git.verify_and_recreate_local_repo).to be true
    end

    it 'commits without running the pre-commit hooks' do
      expect(git).to receive(:commit).with('msg', no_verify: true).and_return(['', '', ok])

      git.verify_and_recreate_local_repo
    end

    it 'captures the remote file list before destroying the local repo' do
      expect(git).to receive(:ls_tree).with('origin/main').ordered.and_return(remote_files)
      expect(git).to receive(:_recreate).ordered.and_return(true)

      git.verify_and_recreate_local_repo
    end

    it 'fails on a detached HEAD without touching anything' do
      allow(git).to receive(:current_branch).and_return(nil)

      expect(git).not_to receive(:fetch_all)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'fails, before recreating, when the fetch fails' do
      allow(git).to receive(:fetch_all).and_return(['', 'offline', failed])

      expect(Logging).to receive(:record_error).with(/Failed to fetch/)
      expect(Logging).to receive(:record_error).with(/offline/)
      expect(git).not_to receive(:_recreate)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'fails, before recreating, when the remote branch has no files' do
      allow(git).to receive(:ls_tree).with('origin/main').and_return([])

      expect(Logging).to receive(:record_error).with(/Failed to get file list/)
      expect(git).not_to receive(:_recreate)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'fails when the recreation itself fails' do
      allow(git).to receive(:_recreate).and_return(false)

      expect(git).not_to receive(:stage_all)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'fails when staging fails' do
      allow(git).to receive(:stage_all).and_return(['', '', failed])

      expect(Logging).to receive(:record_error).with(/Failed to stage/)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'fails, pointing at .gitignore, when nothing ends up staged' do
      allow(git).to receive(:ls_files).and_return([])

      expect(Logging).to receive(:record_error).with(/No files staged/)
      expect(Logging).to receive(:user_action).with(/gitignore/)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'fails when the commit fails' do
      allow(git).to receive(:commit).and_return(['', 'hook said no', failed])

      expect(Logging).to receive(:record_error).with(/Failed to create commit/)
      expect(Logging).to receive(:record_error).with(/hook said no/)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'fails when the commit left no commits behind' do
      allow(git).to receive(:commit_count).and_return(0)

      expect(Logging).to receive(:record_error).with(/No commits created/)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'refuses (with a diff) when the new local file list differs from the remote one' do
      allow(git).to receive(:ls_tree).with('HEAD').and_return(%w[a.txt c.txt])

      expect(Logging).to receive(:warn).with(/Aborting without deleting remote/)
      expect(Logging).to receive(:warn).with(/Files only in new local.*1/)
      expect(Logging).to receive(:warn).with(/\+ c\.txt/)
      expect(Logging).to receive(:warn).with(/Files only in old remote.*1/)
      expect(Logging).to receive(:warn).with(/- b\.txt/)
      expect(Logging).to receive(:record_error).with(/DO NOT match/)
      expect(git.verify_and_recreate_local_repo).to be false
    end

    it 'does not compare file lists in a dry run' do
      git = GitProcessor.new(dir: dir, dry_run: true)
      allow(git).to receive_messages(current_branch: 'main', fetch_all: ['', '', ok], ls_tree: remote_files,
                                     stage_all: ['', '', ok], ls_files: remote_files, commit_count: 1,
                                     default_commit_message: 'msg', _recreate: true)
      allow(git).to receive(:commit).and_return(['', '', ok])

      expect(git).not_to receive(:ls_tree).with('HEAD')
      expect(git.verify_and_recreate_local_repo).to be true
    end
  end

  describe '#_print_file_diff' do
    it 'prints nothing for an empty list' do
      expect(Logging).not_to receive(:warn)

      git.send(:_print_file_diff, 'Files only in x', [], '+')
    end

    it 'caps the listing at ten files and summarizes the rest' do
      files = (1..13).map { |i| "f#{i}" }

      expect(Logging).to receive(:warn).with(/Files only in x/).ordered
      expect(Logging).to receive(:warn).with(/\+ f/).exactly(10).times.ordered
      expect(Logging).to receive(:warn).with(/and 3 more/).ordered

      git.send(:_print_file_diff, 'Files only in x', files, '+')
    end
  end

  describe '#_recreate' do
    around do |example|
      Dir.mktmpdir('git-recreate-spec-') do |tmp|
        @repo = Pathname(tmp)
        @repo.join('.git').mkpath
        @repo.join('.git', 'HEAD').write('ref: refs/heads/main')
        example.run
      end
    end

    let(:dir) { @repo }
    let(:remotes) { { 'origin' => 'git@github.com:me/repo.git', 'origin2' => 'gpg-encrypt::x' } }

    before do
      allow(git).to receive(:current_branch).and_return('main')
      allow(git).to receive(:each_remote) { |&block| remotes.each { |name, url| block.call(name, url) } }
      allow(git).to receive(:config_value).with('user.name').and_return('Me')
      allow(git).to receive(:config_value).with('user.email').and_return('me@example.com')
      allow(git).to receive(:init).and_return(['', '', ok])
      allow(git).to receive(:add_remote)
      allow(git).to receive(:config_set)
    end

    it 'removes .git, re-inits with the same branch and restores every remote plus the identity' do
      expect(git).to receive(:init).with(ref_format: 'reftable', initial_branch: 'main') do
        expect(@repo.join('.git')).not_to exist
        ['', '', ok]
      end
      expect(git).to receive(:add_remote).with('origin', remotes['origin'])
      expect(git).to receive(:add_remote).with('origin2', remotes['origin2'])
      expect(git).to receive(:config_set).with('user.name', 'Me')
      expect(git).to receive(:config_set).with('user.email', 'me@example.com')

      expect(git.send(:_recreate)).to be true
    end

    it 'passes a custom ref format to init' do
      expect(git).to receive(:init).with(ref_format: 'files', initial_branch: 'main').and_return(['', '', ok])

      git.send(:_recreate, ref_format: 'files')
    end

    it 'fails, restoring nothing, when init fails' do
      allow(git).to receive(:init).and_return(['', '', failed])

      expect(git).not_to receive(:add_remote)
      expect(git.send(:_recreate)).to be false
    end

    it 'does not restore blank identity values' do
      allow(git).to receive(:config_value).with('user.email').and_return(nil)

      expect(git).not_to receive(:config_set).with('user.email', anything)

      git.send(:_recreate)
    end

    it 'leaves .git alone in a dry run' do
      git = GitProcessor.new(dir: @repo, dry_run: true)
      allow(git).to receive_messages(current_branch: 'main', config_value: 'x', init: ['', '', ok])
      allow(git).to receive(:each_remote)
      allow(git).to receive(:config_set)

      git.send(:_recreate)

      expect(@repo.join('.git')).to exist
    end
  end
end
