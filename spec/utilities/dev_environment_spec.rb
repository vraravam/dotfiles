# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'dev_environment'

RSpec.describe DevEnvironment do
  before { Logging.state.reset! }
  after { Logging.state.reset! }

  describe '.install_mise_versions' do
    it 'does nothing when mise is not installed' do
      allow(Mise).to receive(:available?).and_return(false)
      expect(Mise).not_to receive(:install)

      described_class.install_mise_versions(shared_dirs: ['/a'])
    end

    it 'trusts and installs only dirs that have a mise config, shallowest first' do
      Dir.mktmpdir do |tmp|
        deep = File.join(tmp, 'a', 'b')
        shallow = File.join(tmp, 'a')
        none = File.join(tmp, 'c')
        [deep, shallow, none].each { |d| FileUtils.mkdir_p(d) }
        File.write(File.join(deep, '.tool-versions'), "ruby 3\n")
        File.write(File.join(shallow, '.mise.toml'), "\n")

        order = []
        allow(Mise).to receive(:available?).and_return(true)
        allow(Mise).to receive(:trust) { |dir| order << [:trust, dir] && true }
        allow(Mise).to receive(:install) { |dir| order << [:install, dir] && 0 }

        described_class.install_mise_versions(shared_dirs: [deep, none, shallow])

        expect(order).to eq([[:trust, shallow], [:install, shallow], [:trust, deep], [:install, deep]])
      end
    end
  end

  describe '.activate_all_direnv_configs' do
    it 'does nothing when direnv is not installed' do
      allow(Direnv).to receive(:available?).and_return(false)
      expect(Direnv).not_to receive(:activate)

      described_class.activate_all_direnv_configs(shared_dirs: ['/a'])
    end

    it 'activates only dirs that have an .envrc, shallowest first' do
      Dir.mktmpdir do |tmp|
        deep = File.join(tmp, 'a', 'b')
        shallow = File.join(tmp, 'a')
        none = File.join(tmp, 'c')
        [deep, shallow, none].each { |d| FileUtils.mkdir_p(d) }
        File.write(File.join(deep, '.envrc'), "\n")
        File.write(File.join(shallow, '.envrc'), "\n")

        activated = []
        allow(Direnv).to receive(:available?).and_return(true)
        allow(Direnv).to receive(:activate) { |dir| activated << dir && true }

        described_class.activate_all_direnv_configs(shared_dirs: [deep, none, shallow])

        expect(activated).to eq([shallow, deep])
      end
    end
  end

  describe '.setup_dev_environment' do
    around do |example|
      Dir.mktmpdir('devenv-spec-') do |dir|
        @tmp = Pathname(dir)
        with_env('FORCE_DEV_ENV_SETUP' => nil) { example.run }
      end
    end

    before { stub_const('EnvVars::XDG_CACHE_HOME', @tmp.join('cache')) }

    let(:stamp) { @tmp.join('cache', DevEnvironment::SETUP_STAMP_NAME) }
    let(:ok_results) { { total: 1, successful: ['x'], failed: [], skipped: 0 } }

    def project_dir
      dir = @tmp.join('proj')
      dir.mkpath
      dir.join('.mise.toml').write("\n")
      dir
    end

    it 'collects the ancestor dirs once and shares them with both operations' do
      expect(described_class).to receive(:collect_ancestor_dirs).once.with(maxdepth: 3).and_return(['/x'])
      expect(described_class).to receive(:activate_all_direnv_configs).with(shared_dirs: ['/x'], maxdepth: 3)
      expect(described_class).to receive(:install_mise_versions).with(shared_dirs: ['/x'], maxdepth: 3)

      described_class.setup_dev_environment(maxdepth: 3)
    end

    it 'searches DEFAULT_MAXDEPTH deep unless told otherwise' do
      expect(described_class).to receive(:collect_ancestor_dirs).with(maxdepth: DevEnvironment::DEFAULT_MAXDEPTH).and_return([])
      allow(described_class).to receive(:activate_all_direnv_configs)
      allow(described_class).to receive(:install_mise_versions)

      described_class.setup_dev_environment
    end

    it 'skips the per-directory work while the config files are unchanged and the stamp is fresh' do
      allow(described_class).to receive(:collect_ancestor_dirs).and_return([project_dir.to_s])
      allow(described_class).to receive(:activate_all_direnv_configs).and_return(ok_results)
      allow(described_class).to receive(:install_mise_versions).and_return(ok_results)
      described_class.setup_dev_environment
      expect(stamp).to exist

      expect(described_class).not_to receive(:activate_all_direnv_configs)
      expect(described_class).not_to receive(:install_mise_versions)
      expect { described_class.setup_dev_environment }.not_to raise_error
    end

    it 'runs again when a config file changed' do
      dir = project_dir
      allow(described_class).to receive(:collect_ancestor_dirs).and_return([dir.to_s])
      allow(described_class).to receive(:activate_all_direnv_configs).and_return(ok_results)
      allow(described_class).to receive(:install_mise_versions).and_return(ok_results)
      described_class.setup_dev_environment

      File.utime(Time.now, Time.now + 5, dir.join('.mise.toml'))
      dir.join('.envrc').write("\n")

      expect(described_class).to receive(:activate_all_direnv_configs).and_return(ok_results)
      expect(described_class).to receive(:install_mise_versions).and_return(ok_results)
      described_class.setup_dev_environment
    end

    it 'runs again once the stamp is older than a day' do
      allow(described_class).to receive(:collect_ancestor_dirs).and_return([project_dir.to_s])
      allow(described_class).to receive(:activate_all_direnv_configs).and_return(ok_results)
      allow(described_class).to receive(:install_mise_versions).and_return(ok_results)
      described_class.setup_dev_environment
      old = Time.now - (DevEnvironment::SETUP_STAMP_MAX_AGE + 60)
      File.utime(old, old, stamp)

      expect(described_class).to receive(:install_mise_versions).and_return(ok_results)
      described_class.setup_dev_environment
    end

    it 'can be forced by argument or environment variable' do
      allow(described_class).to receive(:collect_ancestor_dirs).and_return([project_dir.to_s])
      allow(described_class).to receive(:activate_all_direnv_configs).and_return(ok_results)
      allow(described_class).to receive(:install_mise_versions).and_return(ok_results)
      described_class.setup_dev_environment

      expect(described_class).to receive(:install_mise_versions).twice.and_return(ok_results)
      described_class.setup_dev_environment(force: true)
      with_env('FORCE_DEV_ENV_SETUP' => '1') { described_class.setup_dev_environment }
    end

    it 'does not record the stamp when a directory failed, so the next call retries' do
      allow(described_class).to receive(:collect_ancestor_dirs).and_return([project_dir.to_s])
      allow(described_class).to receive(:activate_all_direnv_configs).and_return(ok_results)
      allow(described_class).to receive(:install_mise_versions).and_return(ok_results.merge(failed: ['/proj']))

      described_class.setup_dev_environment

      expect(stamp).not_to exist
    end
  end

  describe '.collect_ancestor_dirs' do
    it 'passes the depth to the repo search' do
      expect(GitWorkspace).to receive(:find_git_repos).with(hash_including(maxdepth: 2)).and_return([])
      allow(GitWorkspace).to receive(:collect_ancestors).and_return([])

      described_class.collect_ancestor_dirs(maxdepth: 2)
    end
  end
end
