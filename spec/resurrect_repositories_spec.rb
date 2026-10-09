# frozen_string_literal: true

require 'git_processor'
require_relative '../scripts/resurrect-repositories'

RSpec.describe ResurrectRepositories do
  before { Logging.state.reset! }
  after { Logging.state.reset! }

  let(:valid) { { 'folder' => '/tmp/some/repo', 'remote' => 'https://example.com/a/b.git' } }

  describe '.expand_env_vars' do
    it 'expands ${VAR} placeholders from the environment' do
      with_env('RR_SPEC_DIR' => '/base') do
        expect(described_class.expand_env_vars('${RR_SPEC_DIR}/repo')).to eq('/base/repo')
      end
    end

    it 'keeps (and warns about) a placeholder whose variable is unset' do
      with_env('RR_SPEC_MISSING' => nil) do
        expect { expect(described_class.expand_env_vars('${RR_SPEC_MISSING}/x')).to eq('${RR_SPEC_MISSING}/x') }.to output(/not set/).to_stdout
      end
    end

    it 'returns nil, non-strings and placeholder-free strings unchanged' do
      expect(described_class.expand_env_vars(nil)).to be_nil
      expect(described_class.expand_env_vars(42)).to eq(42)
      expect(described_class.expand_env_vars('/plain/path')).to eq('/plain/path')
    end
  end

  describe ResurrectRepositories::RepositoryConfig do
    describe '.from_hash' do
      it 'builds a config with empty defaults for the optional fields' do
        repo = described_class.from_hash(valid)

        expect(repo.folder).to eq('/tmp/some/repo')
        expect(repo.remote).to eq('https://example.com/a/b.git')
        expect(repo.other_remotes).to eq({})
        expect(repo.post_checkout).to eq([])
        expect(repo.post_clone).to eq([])
        expect(repo.bundle).to be_nil
      end

      it 'keeps valid optional fields and expands env vars in folder and bundle' do
        with_env('RR_SPEC_DIR' => '/base') do
          repo = described_class.from_hash(valid.merge(
                                             'folder' => '${RR_SPEC_DIR}/repo', 'bundle' => '${RR_SPEC_DIR}/repo.bundle',
                                             'other_remotes' => { 'mirror' => 'u' }, 'post_checkout' => ['a'], 'post_clone' => ['b']
                                           ))

          expect(repo.folder).to eq('/base/repo')
          expect(repo.bundle).to eq('/base/repo.bundle')
          expect(repo.other_remotes).to eq('mirror' => 'u')
          expect(repo.post_checkout).to eq(['a'])
          expect(repo.post_clone).to eq(['b'])
        end
      end

      it 'rejects, with a recorded warning, anything that is not a hash' do
        expect { expect(described_class.from_hash('nope')).to be_nil }.to output.to_stdout
        expect(Logging.step_warnings.last).to match(/not a hash/)
      end

      {
        'folder' => [{ 'remote' => 'r' }, /invalid or missing 'folder'/],
        'remote' => [{ 'folder' => '/f' }, /invalid or missing 'remote'/],
        'other_remotes' => [{ 'other_remotes' => 'x' }, /invalid 'other_remotes' \(must be a hash\)/],
        'post_checkout' => [{ 'post_checkout' => 'x' }, /invalid 'post_checkout' \(must be an array\)/],
        'post_clone' => [{ 'post_clone' => 'x' }, /invalid 'post_clone' \(must be an array\)/],
        'bundle' => [{ 'bundle' => ' ' }, /invalid 'bundle' \(must be a non-empty string\)/]
      }.each do |field, (extra, message)|
        it "rejects an invalid #{field} with a recorded warning" do
          hash = %w[folder remote].include?(field) ? extra : valid.merge(extra)

          expect { expect(described_class.from_hash(hash)).to be_nil }.to output.to_stdout
          expect(Logging.step_warnings.last).to match(message)
        end
      end
    end

    describe '#matches_filter? / #to_h' do
      let(:repo) { described_class.from_hash(valid) }

      it 'matches when there is no filter or the folder matches it' do
        expect(repo.matches_filter?(nil)).to be true
        expect(repo.matches_filter?(/repo/i)).to be true
        expect(repo.matches_filter?(/zzz/i)).to be false
      end

      it 'round-trips through to_h with string keys' do
        expect(repo.to_h).to include('folder' => '/tmp/some/repo', 'remote' => 'https://example.com/a/b.git', 'active' => true)
      end
    end
  end

  describe '._resurrect_each (clone / verify / configure orchestration)' do
    let(:repo) { ResurrectRepositories::RepositoryConfig.from_hash(valid.merge('other_remotes' => { 'mirror' => 'https://m/x.git' })) }
    let(:git) { instance_double(GitProcessor, delete_index_lock: nil, delete_commit_graph_lock: nil) }
    let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }

    before do
      allow(PathUtils).to receive(:ensure_directories_exist)
      allow(GitProcessor).to receive(:new).and_return(git)
      allow(git).to receive_messages(remote_url: valid['remote'], fetch_all: ['', '', ok])
      allow(git).to receive(:each_remote)
      allow(git).to receive(:add_remote).and_return(['', '', ok])
    end

    def resurrect
      described_class.send(:_resurrect_each, repo)
    end

    it 'succeeds when the primary clone works and origin matches' do
      expect(GitProcessor).to receive(:clone_repo_into).once.and_return(true)

      expect { expect(resurrect).to be true }.to output.to_stdout
    end

    it 'adds a configured remote that is not present yet' do
      allow(GitProcessor).to receive(:clone_repo_into).and_return(true)
      expect(git).to receive(:add_remote).with('mirror', 'https://m/x.git').and_return(['', '', ok])

      expect { resurrect }.to output.to_stdout
    end

    it 're-points a configured remote whose URL differs' do
      allow(GitProcessor).to receive(:clone_repo_into).and_return(true)
      allow(git).to receive(:each_remote).and_yield('mirror', 'https://old/x.git')
      expect(git).to receive(:set_remote_url).with('mirror', 'https://m/x.git').and_return(['', '', ok])

      expect { resurrect }.to output.to_stdout
    end

    it 'falls back to an other_remotes URL and keeps the failed primary as that remote' do
      calls = []
      allow(GitProcessor).to receive(:clone_repo_into) { |url, *_| calls << url && url == 'https://m/x.git' }
      allow(git).to receive(:remote_url).and_return('https://m/x.git')
      expect(git).to receive(:add_remote).with('mirror', valid['remote']).and_return(['', '', ok])

      expect { expect(resurrect).to be true }.to output.to_stdout
      expect(calls).to eq([valid['remote'], 'https://m/x.git'])
    end

    it 'fails (recording an error) when neither the primary nor a fallback clones' do
      allow(GitProcessor).to receive(:clone_repo_into).and_return(false)

      expect { expect(resurrect).to be false }.to output.to_stdout
      expect(Logging.step_errors.last).to match(/Failed to clone/)
    end

    it 'fails when origin points somewhere other than the configuration' do
      allow(GitProcessor).to receive(:clone_repo_into).and_return(true)
      allow(git).to receive(:remote_url).and_return('https://elsewhere/x.git')

      expect { expect(resurrect).to be false }.to output.to_stdout
      expect(Logging.step_errors.last).to match(/differs from config/)
    end

    it 'explains the mismatch when origin is a configured other_remotes URL (an earlier fallback clone)' do
      allow(GitProcessor).to receive(:clone_repo_into).and_return(true)
      allow(git).to receive(:remote_url).and_return('https://m/x.git')

      expect { expect(resurrect).to be false }.to output.to_stdout
      expect(Logging.step_errors.last).to match(/differs from config.*matches 'other_remotes' entry 'mirror'.*earlier fallback clone/)
      expect(Logging.step_errors.last).to include(valid['remote'])
    end

    it 'adds no hint when origin matches nothing in the configuration' do
      allow(GitProcessor).to receive(:clone_repo_into).and_return(true)
      allow(git).to receive(:remote_url).and_return('https://elsewhere/x.git')

      expect { resurrect }.to output.to_stdout
      expect(Logging.step_errors.last).not_to include('fallback clone')
    end

    it 'adds a missing origin from the configuration (e.g. after a bundle import)' do
      allow(GitProcessor).to receive(:clone_repo_into).and_return(true)
      allow(git).to receive(:remote_url).and_return(nil)
      expect(git).to receive(:add_remote).with('origin', valid['remote']).and_return(['', '', ok])
      allow(git).to receive(:add_remote).with('mirror', anything).and_return(['', '', ok])

      expect { expect(resurrect).to be true }.to output.to_stdout
    end

    it 'treats a failed fetch as a warning, not a failure' do
      allow(GitProcessor).to receive(:clone_repo_into).and_return(true)
      allow(git).to receive(:add_remote).and_return(['', '', ok])
      allow(git).to receive(:fetch_all).and_return(['', 'offline', instance_double(Process::Status, success?: false, exitstatus: 1)])

      expect { expect(resurrect).to be true }.to output.to_stdout
      expect(Logging.step_warnings.last).to match(/Failed to fetch all remotes/)
    end
  end
end
