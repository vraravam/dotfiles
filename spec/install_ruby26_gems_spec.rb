# frozen_string_literal: true

require_relative '../scripts/install-ruby26-gems'

RSpec.describe InstallRuby26Gems do
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
