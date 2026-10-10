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
    it 'collects the ancestor dirs once and shares them with both operations' do
      expect(described_class).to receive(:collect_ancestor_dirs).once.with(first_install: true).and_return(['/x'])
      expect(described_class).to receive(:activate_all_direnv_configs).with(shared_dirs: ['/x'], first_install: true)
      expect(described_class).to receive(:install_mise_versions).with(shared_dirs: ['/x'], first_install: true)

      described_class.setup_dev_environment(first_install: true)
    end
  end
end
