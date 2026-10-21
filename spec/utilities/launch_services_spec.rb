# encoding: utf-8
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
        @tmp = Pathname(dir)
        example.run
      end
    end

    let(:tmp) { @tmp }
    let(:safari_https) { { 'LSHandlerURLScheme' => 'https', 'LSHandlerRoleAll' => 'com.apple.safari', 'LSHandlerModificationDate' => 1 } }
    let(:vscodium_text) { { 'LSHandlerContentType' => 'public.plain-text', 'LSHandlerRoleAll' => 'com.vscodium' } }
    let(:live) { [safari_https, vscodium_text] }

    def write_xml(hash, path)
      File.write(path.to_s, xml_for(hash))
    end

    def read_handlers(path)
      JSON.parse(`#{MacOS::PLUTIL_CMD} -convert json -o - #{path}`)['LSHandlers']
    end

    def success(succeeded: true)
      instance_double(Process::Status, success?: succeeded)
    end

    def plutil(stdin_data, *args)
      Open3.capture2(MacOS::PLUTIL_CMD, *args, '-o', '-', '-', stdin_data: stdin_data).first
    end

    def xml_for(hash)
      plutil(JSON.generate(hash), '-convert', 'xml1')
    end

    # 'defaults export <domain> -' returns the live handlers as XML and 'defaults import <domain> -'
    # is captured from stdin; plutil (and anything else) runs for real.
    def stub_defaults(imported:)
      allow(Open3).to receive(:capture3).and_wrap_original do |original, *args, **opts|
        if args.first == MacOS::DEFAULTS_CMD && args[1] == 'export'
          [xml_for({ 'LSHandlers' => live }), '', success]
        elsif args.first == MacOS::DEFAULTS_CMD && args[1] == 'import'
          expect(args.last).to eq('-')
          imported << JSON.parse(plutil(opts[:stdin_data], '-convert', 'json'))['LSHandlers']
          ['', '', success]
        else
          original.call(*args, **opts)
        end
      end
      allow(CommandUtils).to receive(:run_silent).and_return(true)
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
      allow(Open3).to receive(:capture3).and_return(['', '', success(succeeded: false)])

      expect(described_class.send(:_current_handlers)).to eq([])
    end
  end
end
