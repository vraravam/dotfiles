# frozen_string_literal: true

require 'tmpdir'
require 'macos'

RSpec.describe MacOS do
  describe '.load_brew_shellenv' do
    around do |example|
      Dir.mktmpdir('macos-spec-') do |dir|
        @tmp = Pathname.new(dir)
        example.run
      end
    end

    # A fake brew whose 'shellenv' exports one variable, even when the path to it contains a space.
    def fake_brew(dir_name)
      dir = @tmp.join(dir_name)
      dir.mkpath
      brew = dir.join('brew')
      brew.write("#!/bin/sh\necho 'export MACOS_SPEC_BREW_VAR=from-brew'\n")
      brew.chmod(0o755)
      brew
    end

    around do |example|
      with_env('MACOS_SPEC_BREW_VAR' => nil) { example.run }
    end

    it 'merges the variables brew shellenv exports into this process' do
      described_class.load_brew_shellenv(fake_brew('bin'))

      expect(ENV['MACOS_SPEC_BREW_VAR']).to eq('from-brew')
    end

    it 'handles a brew path containing spaces' do
      described_class.load_brew_shellenv(fake_brew('with space'))

      expect(ENV['MACOS_SPEC_BREW_VAR']).to eq('from-brew')
    end

    it 'does not copy back variables the throwaway shell changes by itself' do
      with_env('SHLVL' => '7') do
        described_class.load_brew_shellenv(fake_brew('bin'))

        expect(ENV['SHLVL']).to eq('7')
      end
    end

    it 'does nothing when brew is not executable' do
      described_class.load_brew_shellenv(@tmp.join('missing', 'brew'))

      expect(ENV['MACOS_SPEC_BREW_VAR']).to be_nil
    end
  end
end
