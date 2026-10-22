# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'antidote'

RSpec.describe Antidote do
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failed) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  around do |example|
    Dir.mktmpdir('antidote-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:antidote_zsh) { @tmp.join('antidote.zsh') }
  let(:plugin_txt) { @tmp.join('plugins.txt') }
  let(:plugin_zsh) { @tmp.join('plugins.zsh') }
  let(:antidote_home) { @tmp.join('home') }

  before do
    Logging.state.reset!
    allow(Logging).to receive(:debug)
    allow(Logging).to receive(:success)
    stub_const('EnvVars::ANTIDOTE_ZSH', antidote_zsh)
    stub_const('EnvVars::ANTIDOTE_PLUGIN_TXT', plugin_txt)
    stub_const('EnvVars::ANTIDOTE_PLUGIN_ZSH', plugin_zsh)
    stub_const('EnvVars::ANTIDOTE_HOME', antidote_home)
    allow(CommandUtils).to receive(:run_interactive)
    allow(Open3).to receive(:capture3).and_return(['# bundle', '', ok])
  end

  after { Logging.state.reset! }

  describe '.update_and_regenerate_bundle' do
    context 'when antidote or its plugin list is missing' do
      it 'skips everything when antidote.zsh is missing' do
        plugin_txt.write("zsh-users/zsh-autosuggestions\n")

        expect(CommandUtils).not_to receive(:run_interactive)
        expect(Open3).not_to receive(:capture3)

        described_class.update_and_regenerate_bundle

        expect(plugin_zsh).not_to exist
      end

      it 'skips everything when the plugin list is missing' do
        antidote_zsh.write('# antidote')

        expect(Open3).not_to receive(:capture3)

        described_class.update_and_regenerate_bundle
      end
    end

    context 'when antidote is installed' do
      before do
        antidote_zsh.write('# antidote')
        plugin_txt.write("zsh-users/zsh-autosuggestions\n")
      end

      it 'regenerates the bundle from the plugin list and writes it' do
        expect(Open3).to receive(:capture3)
            .with('zsh', '-fc', 'source "$1"; antidote bundle', '--', antidote_zsh.to_s,
                  stdin_data: "zsh-users/zsh-autosuggestions\n")
            .and_return(['# generated bundle', '', ok])

        described_class.update_and_regenerate_bundle

        expect(plugin_zsh.read).to eq('# generated bundle')
      end

      it 'does not overwrite the existing bundle when regeneration fails' do
        plugin_zsh.write('# old bundle')
        allow(Open3).to receive(:capture3).and_return(['', 'antidote: boom', failed])
        expect(Logging).to receive(:record_warning).with(/Failed to regenerate antidote bundle/)

        described_class.update_and_regenerate_bundle

        expect(plugin_zsh.read).to eq('# old bundle')
      end

      it 'does not run "antidote update" when the plugin cache directory does not exist yet' do
        expect(CommandUtils).not_to receive(:run_interactive)

        described_class.update_and_regenerate_bundle
      end

      context 'with a plugin cache directory' do
        let(:bundle_dir) { antidote_home.join('github.com', 'owner', 'plugin') }
        let(:git) { instance_double(GitProcessor, repo?: true, shallow?: true, config_set: nil, run_alias: nil) }

        before do
          bundle_dir.mkpath
          allow(GitProcessor).to receive(:new).and_yield(git)
        end

        it 'updates the plugins through zsh first' do
          expect(CommandUtils).to receive(:run_interactive)
              .with('zsh', '-fc', 'source "$1"; antidote update', '--', antidote_zsh.to_s)

          described_class.update_and_regenerate_bundle
        end

        it 'unshallows a shallow plugin repo, with remote fsck disabled and output streamed' do
          expect(git).to receive(:config_set).with('fetch.fsckObjects', 'false')
          expect(git).to receive(:run_alias).with('unshallow', stream: true)

          described_class.update_and_regenerate_bundle
        end

        it 'leaves a repo that is already complete alone' do
          allow(git).to receive(:shallow?).and_return(false)

          expect(git).not_to receive(:config_set)
          expect(git).not_to receive(:run_alias)

          described_class.update_and_regenerate_bundle
        end

        it 'leaves a folder that is not a git repo alone' do
          allow(git).to receive(:repo?).and_return(false)

          expect(git).not_to receive(:run_alias)

          described_class.update_and_regenerate_bundle
        end

        it 'ignores plain files at the repo level of the cache' do
          bundle_dir.rmtree
          antidote_home.join('github.com', 'owner', 'stray-file').write('x')

          expect(GitProcessor).not_to receive(:new)

          described_class.update_and_regenerate_bundle
        end
      end
    end
  end
end
