# frozen_string_literal: true

require 'tmpdir'
require 'shellrc_check'

RSpec.describe ShellrcCheck do
  around do |example|
    Dir.mktmpdir('shellrc-check-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:home) { @tmp.join('home').tap(&:mkpath) }
  let(:repo) { @tmp.join('dotfiles') }
  let(:repo_shellrc) { repo.join('files', '--HOME--', '.shellrc') }

  before do
    stub_const('EnvVars::HOME', home)
    stub_const('EnvVars::DOTFILES_DIR', repo)
    allow(EnvVars).to receive(:first_install?).and_return(true)
    repo_shellrc.dirname.mkpath
  end

  describe '.matches_repo?' do
    it 'is true without comparing anything on a pre-configured machine' do
      allow(EnvVars).to receive(:first_install?).and_return(false)
      home.join('.shellrc').write("old\n")
      repo_shellrc.write("new\n")

      expect(described_class.matches_repo?).to be true
    end

    it 'is true when the repository has not been cloned' do
      repo.rmtree

      expect(described_class.matches_repo?).to be true
    end

    it 'is true when the downloaded copy equals the repo copy' do
      home.join('.shellrc').write("same\n")
      repo_shellrc.write("same\n")

      expect(described_class.matches_repo?).to be true
    end

    it 'is false, printing the diff and the recovery steps, when the copies differ' do
      home.join('.shellrc').write("stale line\n")
      repo_shellrc.write("fresh line\n")

      result = nil
      expect { result = described_class.matches_repo? }.to output(/cache is stale.*-stale line.*\+fresh line.*Wait 5-10 minutes.*cp '#{Regexp.escape(repo_shellrc.to_s)}'/m).to_stderr

      expect(result).to be false
    end

    it 'is false when the downloaded copy is missing' do
      repo_shellrc.write("fresh\n")

      expect { expect(described_class.matches_repo?).to be false }.to output(/differs from the repo version/).to_stderr
    end

    it 'shows at most DIFF_LINES lines of the diff' do
      home.join('.shellrc').write((1..200).map { |i| "old #{i}\n" }.join)
      repo_shellrc.write((1..200).map { |i| "new #{i}\n" }.join)

      expect { described_class.matches_repo? }.to output(satisfy { |text| text.scan(/^[-+](?:old|new) /).length <= ShellrcCheck::DIFF_LINES }).to_stderr
    end
  end
end
