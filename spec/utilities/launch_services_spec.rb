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

  describe 'export and import against a stubbed defaults domain' do
    require 'json'
    require 'tmpdir'

    around do |example|
      Dir.mktmpdir('launch-services-spec-') do |dir|
        @tmp = Pathname.new(dir)
        example.run
      end
    end

    let(:tmp) { @tmp }
    let(:live) do
      [
        { 'LSHandlerURLScheme' => 'https', 'LSHandlerRoleAll' => 'com.apple.safari', 'LSHandlerModificationDate' => 1 },
        { 'LSHandlerContentType' => 'public.plain-text', 'LSHandlerRoleAll' => 'com.vscodium' }
      ]
    end

    def write_xml(hash, path)
      json = tmp.join('in.json')
      json.write(JSON.generate(hash))
      system(MacOS::PLUTIL_CMD, '-convert', 'xml1', '-o', path.to_s, json.to_s)
    end

    def read_handlers(path)
      JSON.parse(`#{MacOS::PLUTIL_CMD} -convert json -o - #{path}`)['LSHandlers']
    end

    # 'defaults export <domain> <file>' writes the live handlers; 'defaults import' is captured;
    # plutil (and anything else) runs for real.
    def stub_defaults(imported:)
      allow(CommandUtils).to receive(:run_silent) do |*args|
        case args[1]
        when 'export' then write_xml({ 'LSHandlers' => live }, args[3]) && true
        when 'import' then imported << read_handlers(args[3]) && true
        else system(*args, out: File::NULL, err: File::NULL)
        end
      end
    end

    it 'exports the live handlers without the volatile modification date' do
      stub_defaults(imported: [])
      out = tmp.join('out.plist')

      expect(described_class.export_handlers(out)).to be true

      exported = read_handlers(out)
      expect(exported.size).to eq(2)
      expect(exported.flat_map(&:keys)).not_to include('LSHandlerModificationDate')
    end

    it 'imports by merging into the live handlers and restarts lsd' do
      imported = []
      stub_defaults(imported: imported)
      wanted = tmp.join('wanted.plist')
      write_xml({ 'LSHandlers' => [{ 'LSHandlerURLScheme' => 'https', 'LSHandlerRoleAll' => 'app.zen-browser.zen' }] }, wanted)

      expect(described_class.import_handlers(wanted)).to be true

      roles = imported.first.map { |h| [h['LSHandlerURLScheme'] || h['LSHandlerContentType'], h['LSHandlerRoleAll']] }
      expect(roles).to contain_exactly(['public.plain-text', 'com.vscodium'], ['https', 'app.zen-browser.zen'])
      expect(CommandUtils).to have_received(:run_silent).with('killall', 'lsd')
    end

    it 'fails without importing when the file to import cannot be read' do
      stub_defaults(imported: imported = [])

      expect(described_class.import_handlers(tmp.join('missing.plist'))).to be false
      expect(imported).to be_empty
    end

    it 'treats a machine with no handlers plist as having none' do
      allow(CommandUtils).to receive(:run_silent).and_return(false)

      expect(described_class.send(:_current_handlers)).to eq([])
    end
  end
end
