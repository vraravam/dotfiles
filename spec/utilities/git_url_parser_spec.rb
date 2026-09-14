# frozen_string_literal: true

require 'git_processor'

RSpec.describe GitProcessor::GitUrlParser do
  describe '#initialize' do
    context 'with an scp-style SSH URL' do
      subject(:parser) { described_class.new('git@github.com:vraravam/dotfiles.git') }

      it 'extracts the host' do
        expect(parser.host).to eq('github.com')
      end

      it 'extracts the owner' do
        expect(parser.owner).to eq('vraravam')
      end

      it 'extracts the repo path with .git suffix' do
        expect(parser.repo_path).to eq('dotfiles.git')
      end

      it 'sets the format to :scp_ssh' do
        expect(parser.format).to eq(:scp_ssh)
      end
    end

    context 'with an scp-style SSH URL missing the .git suffix' do
      subject(:parser) { described_class.new('git@github.com:vraravam/dotfiles') }

      it 'appends the .git suffix' do
        expect(parser.repo_path).to eq('dotfiles.git')
      end
    end

    context 'with an HTTPS URL' do
      subject(:parser) { described_class.new('https://github.com/vraravam/dotfiles.git') }

      it 'extracts the protocol' do
        expect(parser.protocol).to eq('https')
      end

      it 'extracts the host' do
        expect(parser.host).to eq('github.com')
      end

      it 'extracts the owner' do
        expect(parser.owner).to eq('vraravam')
      end

      it 'sets the format to :https' do
        expect(parser.format).to eq(:https)
      end
    end

    context 'with a plain HTTP URL' do
      subject(:parser) { described_class.new('http://github.com/vraravam/dotfiles.git') }

      it 'extracts the http protocol' do
        expect(parser.protocol).to eq('http')
      end
    end

    context 'with a git+ssh URL (no port)' do
      subject(:parser) { described_class.new('git+ssh://git@github.com/vraravam/dotfiles.git') }

      it 'extracts the host' do
        expect(parser.host).to eq('github.com')
      end

      it 'has no port' do
        expect(parser.port).to be_nil
      end

      it 'sets the format to :git_ssh' do
        expect(parser.format).to eq(:git_ssh)
      end
    end

    context 'with a git+ssh URL including a port' do
      subject(:parser) { described_class.new('git+ssh://git@github.com:2222/vraravam/dotfiles.git') }

      it 'extracts the port' do
        expect(parser.port).to eq('2222')
      end

      it 'extracts the owner' do
        expect(parser.owner).to eq('vraravam')
      end
    end

    context 'with an ssh:// URL' do
      subject(:parser) { described_class.new('ssh://git@github.com/vraravam/dotfiles.git') }

      it 'sets the format to :ssh_url' do
        expect(parser.format).to eq(:ssh_url)
      end

      it 'extracts the owner' do
        expect(parser.owner).to eq('vraravam')
      end
    end

    context 'with an unrecognized URL format' do
      it 'raises ArgumentError' do
        expect { described_class.new('not-a-git-url') }.to raise_error(ArgumentError, /Cannot parse git URL format/)
      end
    end
  end

  describe '#with_owner' do
    it 'reconstructs an scp-style SSH URL with the new owner' do
      parser = described_class.new('git@github.com:vraravam/dotfiles.git')
      expect(parser.with_owner('my-fork-owner')).to eq('git@github.com:my-fork-owner/dotfiles.git')
    end

    it 'reconstructs an HTTPS URL with the new owner' do
      parser = described_class.new('https://github.com/vraravam/dotfiles.git')
      expect(parser.with_owner('my-fork-owner')).to eq('https://github.com/my-fork-owner/dotfiles.git')
    end

    it 'reconstructs a git+ssh URL (no port) with the new owner' do
      parser = described_class.new('git+ssh://git@github.com/vraravam/dotfiles.git')
      expect(parser.with_owner('my-fork-owner')).to eq('git+ssh://git@github.com/my-fork-owner/dotfiles.git')
    end

    it 'reconstructs a git+ssh URL (with port) with the new owner' do
      parser = described_class.new('git+ssh://git@github.com:2222/vraravam/dotfiles.git')
      expect(parser.with_owner('my-fork-owner')).to eq('git+ssh://git@github.com:2222/my-fork-owner/dotfiles.git')
    end

    it 'reconstructs an ssh:// URL with the new owner' do
      parser = described_class.new('ssh://git@github.com/vraravam/dotfiles.git')
      expect(parser.with_owner('my-fork-owner')).to eq('ssh://git@github.com/my-fork-owner/dotfiles.git')
    end

    it 'round-trips back to the original owner (this is how the upstream-owner check works)' do
      parser = described_class.new('https://github.com/some-fork-owner/dotfiles.git')
      expect(parser.with_owner(parser.owner)).to eq('https://github.com/some-fork-owner/dotfiles.git')
    end
  end
end
