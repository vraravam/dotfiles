# frozen_string_literal: true

require 'launch_services'

RSpec.describe LaunchServices do
  describe '.merge_handlers' do
    let(:zen_https) { { 'LSHandlerURLScheme' => 'https', 'LSHandlerRoleAll' => 'app.zen-browser.zen' } }
    let(:safari_https) { { 'LSHandlerURLScheme' => 'https', 'LSHandlerRoleAll' => 'com.apple.safari' } }
    let(:plain_text) { { 'LSHandlerContentType' => 'public.plain-text', 'LSHandlerRoleAll' => 'com.vscodium' } }

    it 'replaces an existing entry for the same URL scheme' do
      expect(described_class.merge_handlers([safari_https], [zen_https])).to eq([zen_https])
    end

    it 'keeps unrelated existing entries and appends new ones' do
      expect(described_class.merge_handlers([plain_text], [zen_https])).to eq([plain_text, zen_https])
    end

    it 'matches identities case-insensitively' do
      upper = { 'LSHandlerURLScheme' => 'HTTPS', 'LSHandlerRoleAll' => 'x' }
      expect(described_class.merge_handlers([upper], [zen_https])).to eq([zen_https])
    end

    it 'does not confuse a content type with a URL scheme of the same value' do
      scheme = { 'LSHandlerURLScheme' => 'public.html', 'LSHandlerRoleAll' => 'a' }
      type = { 'LSHandlerContentType' => 'public.html', 'LSHandlerRoleAll' => 'b' }
      expect(described_class.merge_handlers([scheme], [type])).to eq([scheme, type])
    end
  end
end
