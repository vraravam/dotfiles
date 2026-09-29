# frozen_string_literal: true

require 'gpg_encrypt'

RSpec.describe GpgEncrypt do
  describe '.url' do
    it 'prepends the gpg-encrypt:: pseudo-scheme to a plain https:// URL' do
      expect(described_class.url('https://github.com/example/repo.git')).to eq('gpg-encrypt::https://github.com/example/repo.git')
    end

    it 'prepends the gpg-encrypt:: pseudo-scheme to a plain ssh-style URL' do
      expect(described_class.url('git@github.com:example/repo.git')).to eq('gpg-encrypt::git@github.com:example/repo.git')
    end

    it 'uses the PROTOCOL constant as the prefix' do
      expect(described_class.url('https://example.com/repo.git')).to start_with(described_class::PROTOCOL)
    end
  end
end
