# frozen_string_literal: true

require 'tmpdir'
require 'git_workspace'

RSpec.describe GitWorkspace do
  around do |example|
    Dir.mktmpdir('git-workspace-spec-') do |dir|
      @tmp = Pathname.new(File.realpath(dir))
      GitProcessor.repo_cache = {}
      example.run
    end
  end

  let(:tmp) { @tmp }

  before { Logging.state.reset! }
  after { Logging.state.reset! }

  def make_repo(*parts)
    dir = tmp.join(*parts)
    dir.mkpath
    system('git', '-C', dir.to_s, 'init', '--quiet')
    dir
  end

  describe '.find_git_repos' do
    it 'finds repo roots, ignores non-repos, and skips repos nested inside another repo' do
      outer = make_repo('proj')
      make_repo('proj', 'vendored')
      other = make_repo('group', 'other')
      tmp.join('plain').mkpath
      GitProcessor.repo_cache = {}

      expect(described_class.find_git_repos(dirs: tmp)).to eq([other.to_s, outer.to_s].sort)
    end

    it 'prunes the default noise directories' do
      make_repo('node_modules', 'pkg')
      kept = make_repo('real')
      GitProcessor.repo_cache = {}

      expect(described_class.find_git_repos(dirs: tmp)).to eq([kept.to_s])
    end

    it 'honours maxdepth' do
      make_repo('a', 'b', 'c')
      GitProcessor.repo_cache = {}

      expect(described_class.find_git_repos(dirs: tmp, maxdepth: 2)).to be_empty
    end
  end

  describe '.collect_ancestors' do
    it 'walks up from each repo root to just below the stop directory, without duplicates' do
      roots = [tmp.join('a', 'b', 'r1').to_s, tmp.join('a', 'c', 'r2').to_s]

      result = described_class.collect_ancestors(roots, stop_at: tmp)

      expect(result).to contain_exactly(tmp.join('a', 'b').to_s, tmp.join('a', 'c').to_s, tmp.join('a').to_s)
    end

    it 'includes the repo root and the stop boundary when asked' do
      result = described_class.collect_ancestors([tmp.join('a', 'r').to_s], stop_at: tmp, include_repo_root: true, include_stop_boundary: true)

      expect(result).to contain_exactly(tmp.join('a', 'r').to_s, tmp.join('a').to_s, tmp.to_s)
    end
  end

  describe '.status_repo' do
    it 'is false for a directory that is not a git repo' do
      expect(described_class.status_repo(tmp)).to be false
    end

    it 'is true for a clean repo' do
      repo = make_repo('r')
      GitProcessor.repo_cache = {}

      expect { expect(described_class.status_repo(repo)).to be true }.to output.to_stdout
    end
  end

  describe '.status_all_repos' do
    it 'checks HOME, the dotfiles dir, the profiles dir and every chrome folder' do
      chrome = Pathname.new('/chrome')
      allow(ProfilesRepo).to receive(:find_chrome_folders).and_return([chrome])
      checked = []
      allow(described_class).to receive(:status_repo) { |dir| checked << dir && true }

      expect(described_class.status_all_repos).to be true
      expect(checked).to eq([EnvVars::HOME, EnvVars::DOTFILES_DIR, EnvVars::PERSONAL_PROFILES_DIR, chrome])
    end

    it 'is false when any repo fails' do
      allow(ProfilesRepo).to receive(:find_chrome_folders).and_return([])
      allow(described_class).to receive(:status_repo).and_return(true, false, true)

      expect(described_class.status_all_repos).to be false
    end
  end

  describe '.update_repo' do
    it 'warns and returns false for a directory that is not a git repo' do
      expect { expect(described_class.update_repo(tmp)).to be false }.to output.to_stdout.or output.to_stderr
    end

    it "returns commit_all's result, passing the paths through" do
      git = instance_double(GitProcessor, commit_all: true)
      allow(GitProcessor).to receive(:repo?).with(tmp).and_return(true)
      allow(GitProcessor).to receive(:new).with(dir: tmp).and_yield(git).and_return(git)

      expect { expect(described_class.update_repo(tmp, paths: ['x'])).to be true }.to output.to_stdout
      expect(git).to have_received(:commit_all).with(paths: ['x'])
    end

    it 'returns false when git raises' do
      allow(GitProcessor).to receive(:repo?).and_return(true)
      allow(GitProcessor).to receive(:new).and_raise(RuntimeError, 'boom')

      expect { expect(described_class.update_repo(tmp)).to be false }.to output.to_stdout.or output.to_stderr
    end
  end

  describe '.update_all_repos' do
    it 'commits only the defaults folder in HOME and everything in the profiles repo' do
      expect(described_class).to receive(:update_repo).with(EnvVars::HOME, paths: [EnvVars::PERSONAL_CONFIGS_DIR.join('defaults')]).and_return(true)
      expect(described_class).to receive(:update_repo).with(EnvVars::PERSONAL_PROFILES_DIR, paths: nil).and_return(true)

      expect(described_class.update_all_repos).to be true
    end
  end

  describe '.regenerate_repo_aliases' do
    it 'writes an alias per ancestor directory of each repo and skips a fresh cache' do
      make_repo('oss', 'tools', 'repo1')
      cache_home = tmp.join('cache')
      cache_home.mkpath
      stub_const('EnvVars::PROJECTS_BASE_DIR', tmp.join('oss'))
      stub_const('EnvVars::XDG_CACHE_HOME', cache_home)
      GitProcessor.repo_cache = {}

      described_class.regenerate_repo_aliases(force: true)

      content = cache_home.join('repo-aliases-cache.zsh').read
      expect(content).to include("alias tools=\"FOLDER='#{tmp.join('oss', 'tools')}' MAXDEPTH=4 rug\"")

      cache_home.join('repo-aliases-cache.zsh').write('sentinel')
      FileUtils.touch(cache_home.join('repo-aliases-cache.zsh'), mtime: Time.now + 60)
      described_class.regenerate_repo_aliases
      expect(cache_home.join('repo-aliases-cache.zsh').read).to eq('sentinel')
    end
  end
end
