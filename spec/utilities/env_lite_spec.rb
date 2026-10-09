# frozen_string_literal: true

require 'env_lite'

RSpec.describe EnvLite do
  describe '.set?' do
    it 'is false for an unset variable' do
      with_env('ENV_LITE_SPEC' => nil) { expect(described_class.set?('ENV_LITE_SPEC')).to be false }
    end

    it 'is false for a blank value' do
      with_env('ENV_LITE_SPEC' => '  ') { expect(described_class.set?('ENV_LITE_SPEC')).to be false }
    end

    it 'is true for a non-blank value' do
      with_env('ENV_LITE_SPEC' => 'x') { expect(described_class.set?('ENV_LITE_SPEC')).to be true }
    end
  end

  describe '.home' do
    it 'returns HOME' do
      with_env('HOME' => '/some/home') { expect(described_class.home).to eq('/some/home') }
    end

    it "returns '' when HOME is unset" do
      with_env('HOME' => nil) { expect(described_class.home).to eq('') }
    end
  end

  describe '.force_color?' do
    it 'follows FORCE_COLOR' do
      with_env('FORCE_COLOR' => '1') { expect(described_class.force_color?).to be true }
      with_env('FORCE_COLOR' => nil) { expect(described_class.force_color?).to be false }
    end
  end

  it 'has no dependencies beyond the Ruby core (so Core/Colorizable can use it)' do
    source = File.read(File.expand_path('../../scripts/utilities/env_lite.rb', __dir__), encoding: 'UTF-8')
    expect(source).not_to match(/^\s*require/)
  end
end
