# encoding: utf-8
# frozen_string_literal: true

require_relative '../scripts/recreate-repository'

RSpec.describe RecreateRepository do
  let(:dir) { '/tmp/spec-repo' }
  let(:git) do
    instance_double(GitProcessor, verify_pre_recreation: nil, verify_and_recreate_local_repo: true,
                                  stage_all: nil, smart_commit: nil, compress: nil, build_commit_graph: nil,
                                  current_branch: 'main')
  end
  let(:ok) { instance_double(Process::Status, success?: true) }
  let(:failed) { instance_double(Process::Status, success?: false) }
  let(:remotes) { { 'origin' => 'git@github.com:me/repo.git' } }

  before do
    Logging.state.reset!
    allow(Logging).to receive(:info)
    allow(Logging).to receive(:success)
    allow(Logging).to receive(:section_header)
    allow(GitProcessor).to receive(:repo?).with(dir).and_return(true)
    allow(GitProcessor).to receive(:new).and_yield(git)
    allow(Cron).to receive(:with_cron_suspended) { |**, &block| block.call }
    allow(git).to receive(:each_remote) { |&block| remotes.each { |name, url| block.call(name, url) } }
    allow(git).to receive(:push).and_return(['', '', ok])
    allow(git).to receive(:remote_repo_name) { |name:| remotes.fetch(name).split('/').last }
  end

  after { Logging.state.reset! }

  describe '.run' do
    it 'records an error and fails for a directory that is not a git repo' do
      allow(GitProcessor).to receive(:repo?).with(dir).and_return(false)
      expect(Logging).to receive(:record_error).with(/not a git repo/)

      expect(described_class.run(dir: dir)).to be false
    end

    it 'strips a trailing slash from the directory' do
      expect(GitProcessor).to receive(:repo?).with(dir).and_return(true)

      expect(described_class.run(dir: "#{dir}/")).to be true
    end

    context 'without force' do
      it 'commits the working tree, compresses, pushes without force, then builds the commit graph' do
        expect(git).to receive(:stage_all).ordered
        expect(git).to receive(:smart_commit).ordered
        expect(git).to receive(:compress).ordered
        expect(git).to receive(:push).with(remote: 'origin', branch: 'main', force: false).ordered.and_return(['', '', ok])
        expect(git).to receive(:build_commit_graph).ordered
        expect(git).not_to receive(:verify_and_recreate_local_repo)

        expect(described_class.run(dir: dir)).to be true
      end

      it 'runs the repository work with cron suspended' do
        expect(Cron).to receive(:with_cron_suspended).with(dry_run: false) do |**, &block|
          block.call
        end

        described_class.run(dir: dir)
      end

      it 'fails, and skips the commit graph, when a push fails' do
        allow(git).to receive(:push).and_return(['', 'rejected', failed])
        expect(Logging).to receive(:record_error).with(/Failed to push to .*origin.*rejected/)
        expect(git).not_to receive(:build_commit_graph)

        expect(described_class.run(dir: dir)).to be false
      end
    end

    context 'with force' do
      it 'squashes the local history and force-pushes' do
        expect(git).to receive(:verify_and_recreate_local_repo).and_return(true)
        expect(git).to receive(:push).with(remote: 'origin', branch: 'main', force: true).and_return(['', '', ok])
        expect(git).not_to receive(:smart_commit)

        expect(described_class.run(dir: dir, force: true)).to be true
      end

      it 'stops before pushing when the recreated repo does not match the remote' do
        allow(git).to receive(:verify_and_recreate_local_repo).and_return(false)
        expect(git).not_to receive(:push)

        expect(described_class.run(dir: dir, force: true)).to be false
      end

      it 'forces the profiles repo even when force was not requested' do
        stub_const('EnvVars::PERSONAL_PROFILES_DIR', Pathname(dir))
        expect(git).to receive(:verify_and_recreate_local_repo).and_return(true)

        expect(described_class.run(dir: dir)).to be true
      end

      it 'passes dry_run through to GitProcessor and to the cron suspension' do
        expect(GitProcessor).to receive(:new).with(dir: Pathname(dir), dry_run: true).and_yield(git)
        expect(Cron).to receive(:with_cron_suspended).with(dry_run: true) do |**, &block|
          block.call
        end

        described_class.run(dir: dir, force: true, dry_run: true)
      end

      context 'with keybase remotes' do
        let(:remotes) { { 'origin' => 'keybase://private/me/repo', 'origin2' => 'gpg-encrypt::git@host:me/repo' } }

        before do
          allow(Keybase).to receive_messages(ensure_logged_in: true, recreate_repo: true)
        end

        it 'checks the keybase login before the destructive local squash' do
          expect(Keybase).to receive(:ensure_logged_in).with(dry_run: false).ordered.and_return(true)
          expect(git).to receive(:verify_and_recreate_local_repo).ordered.and_return(true)

          described_class.run(dir: dir, force: true)
        end

        it 'does not touch the local history when the keybase login check fails' do
          allow(Keybase).to receive(:ensure_logged_in).and_return(false)
          expect(git).not_to receive(:verify_and_recreate_local_repo)
          expect(git).not_to receive(:push)

          expect(described_class.run(dir: dir, force: true)).to be false
        end

        it 'recreates the keybase repo before pushing to it, and force-pushes every other remote directly' do
          expect(Keybase).to receive(:recreate_repo).with('repo', dry_run: false).once.ordered.and_return(true)
          expect(git).to receive(:push).with(remote: 'origin', branch: 'main', force: true).ordered.and_return(['', '', ok])
          expect(git).to receive(:push).with(remote: 'origin2', branch: 'main', force: true).ordered.and_return(['', '', ok])

          expect(described_class.run(dir: dir, force: true)).to be true
        end

        it 'skips the push to a keybase remote whose recreation failed, but still pushes the others' do
          allow(Keybase).to receive(:recreate_repo).and_return(false)
          expect(Logging).to receive(:record_error).with(/Failed to recreate keybase repo/)
          expect(git).not_to receive(:push).with(hash_including(remote: 'origin'))
          expect(git).to receive(:push).with(hash_including(remote: 'origin2')).and_return(['', '', ok])

          expect(described_class.run(dir: dir, force: true)).to be false
        end

        it 'does not recreate keybase repos when not squashing' do
          expect(Keybase).not_to receive(:recreate_repo)

          expect(described_class.run(dir: dir)).to be true
        end
      end
    end
  end
end
