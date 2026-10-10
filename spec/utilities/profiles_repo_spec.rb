# frozen_string_literal: true

require 'tmpdir'
require 'profiles_repo'

RSpec.describe ProfilesRepo do
  around do |example|
    Dir.mktmpdir('profiles-repo-spec-') do |dir|
      @tmp = Pathname.new(dir)
      GitProcessor.repo_cache = {}
      example.run
    end
  end

  let(:tmp) { @tmp }

  before do
    Logging.state.reset!
    described_class.instance_variable_set(:@_profiles_dir, tmp)
    described_class.instance_variable_set(:@_profiles_git, nil)
  end

  after do
    described_class.instance_variable_set(:@_profiles_dir, nil)
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
end
