# encoding: utf-8
# frozen_string_literal: true

require_relative '../scripts/install-ruby26-gems'

RSpec.describe InstallRuby26Gems do
  describe '.run' do
    it 'touches the stamp the .envrc compares against the script after a successful run' do
      allow(described_class).to receive(:_run).with(false).and_return(true)
      expect(Core).to receive(:mark_updated!).with(InstallRuby26Gems::STAMP_FILE)
      allow(PathUtils).to receive(:ensure_directories_exist)

      expect(described_class.run).to be true
    end

    it 'leaves the stamp alone when something failed, so the next directory entry retries' do
      allow(described_class).to receive(:_run).and_return(false)
      expect(Core).not_to receive(:mark_updated!)

      expect(described_class.run).to be false
    end

    it 'uses the stamp path the repo .envrc spells out' do
      envrc = File.read(File.expand_path('../.envrc', __dir__))

      expect(envrc).to include("${XDG_CACHE_HOME:-${HOME}/.cache}/#{InstallRuby26Gems::STAMP_FILE.basename}")
    end
  end

  describe '._toolchain_hint' do
    let(:make_error) { "make: *** No rule to make target '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/x/ruby/config.h', needed by 'cparse.o'.  Stop." }

    it 'is nil when the failure does not look toolchain related' do
      expect(described_class.send(:_toolchain_hint, 'ERROR: Could not find a valid gem')).to be_nil
    end

    it 'names the missing header and the fix when the Ruby header is absent' do
      allow(CommandUtils).to receive(:query).and_return('/nonexistent/ruby/config.h')

      hint = described_class.send(:_toolchain_hint, make_error)

      expect(hint).to include('/nonexistent/ruby/config.h', 'xcode-select --install', 'xcrun --show-sdk-path')
    end

    it 'still gives toolchain advice when the header exists' do
      allow(CommandUtils).to receive(:query).and_return(__FILE__)

      expect(described_class.send(:_toolchain_hint, make_error)).to include('could not build a native extension')
    end
  end
end
