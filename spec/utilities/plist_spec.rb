# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'plist'

RSpec.describe Plist do
  def plist(body)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      #{body}
      </plist>
    XML
  end

  let(:tabbed) do
    plist(<<~BODY.chomp)
      <dict>
      \t<key>Keep</key>
      \t<string>value</string>
      \t<key>SULastCheckTime</key>
      \t<string>when</string>
      \t<key>Nested</key>
      \t<dict>
      \t\t<key>SULastCheckTime</key>
      \t\t<date>2026-01-01T00:00:00Z</date>
      \t</dict>
      \t<key>Stamp</key>
      \t<date>2026-01-01T00:00:00Z</date>
      \t<key>Blob</key>
      \t<data>
      \tAAEC
      \t</data>
      \t<key>List</key>
      \t<array>
      \t\t<string>a</string>
      \t</array>
      \t<key>Multi</key>
      \t<string>one
      two</string>
      \t<key>Flag</key>
      \t<true/>
      </dict>
    BODY
  end

  describe '.load_excluded_keys' do
    it 'maps domains to frozen pattern arrays and keeps a plain hash' do
      Dir.mktmpdir do |dir|
        file = Pathname(dir).join('excluded.txt')
        file.write("# comment\n\na.b|One\na.b|Two*\n*|Global\n")

        result = described_class.load_excluded_keys(file)

        expect(result).to eq('a.b' => %w[One Two*], '*' => %w[Global])
        expect(result['a.b']).to be_frozen
        expect(result['missing']).to be_nil
        expect(result).not_to have_key('missing')
      end
    end
  end

  describe '.stripped_xml' do
    it 'returns the very same object when nothing matches (fast path, no parse)' do
      xml = plist("<dict>\n\t<key>Keep</key>\n\t<string>x</string>\n</dict>")

      expect(described_class).not_to receive(:_strip_with_rexml)
      expect(described_class.stripped_xml('d', xml, { 'd' => ['Other*'] })).to equal(xml)
    end

    it 'does not load REXML on the fast and match paths' do
      expect(described_class).not_to receive(:require).with('rexml/document')

      described_class.stripped_xml('d', tabbed, { 'd' => ['SU*'] })
    end

    it 'removes pattern-matched and date-valued top-level keys with their values' do
      result = described_class.stripped_xml('d', tabbed, { 'd' => ['SULast*'] })

      expect(result).not_to include("SULastCheckTime</key>\n\t<string>")
      expect(result).not_to include('<key>Stamp</key>')
      expect(result).to include('<key>Keep</key>', '<key>Blob</key>', 'AAEC', '<key>List</key>', "<string>one\ntwo</string>", '<key>Flag</key>')
    end

    it 'leaves date values nested in other containers alone' do
      result = described_class.stripped_xml('d', tabbed, {})

      expect(result).to include("\t\t<key>SULastCheckTime</key>\n\t\t<date>")
    end

    it 'removes a multi-line dict value together with its key' do
      result = described_class.stripped_xml('d', tabbed, { 'd' => ['Nested'] })

      expect(result).not_to include('Nested')
      expect(result).to include('<key>Stamp</key>').or include('<key>Blob</key>')
    end

    it 'applies global * patterns together with the domain patterns' do
      result = described_class.stripped_xml('d', tabbed, { 'd' => ['Keep'], '*' => ['Flag'] })

      expect(result).not_to include('<key>Keep</key>')
      expect(result).not_to include('<key>Flag</key>')
      expect(result).to include('<key>List</key>')
    end

    it 'matches key names containing escaped entities and colons' do
      xml = plist("<dict>\n\t<key>a:b &amp; c</key>\n\t<string>x</string>\n\t<key>z</key>\n\t<true/>\n</dict>")

      result = described_class.stripped_xml('d', xml, { 'd' => ['a:b & c'] })

      expect(result).not_to include('a:b')
      expect(result).to include('<key>z</key>')
    end

    it 'writes an empty root dict as <dict/> when every key is removed' do
      xml = plist("<dict>\n\t<key>Only</key>\n\t<string>x</string>\n</dict>")

      expect(described_class.stripped_xml('d', xml, { 'd' => ['Only'] })).to include("<dict/>\n")
    end

    it 'gives the same result through the REXML fallback as through the text path' do
      allow(described_class).to receive(:_normalize_xml) { |xml| xml }
      patterns = { 'd' => ['SULast*'] }
      text_result = described_class.stripped_xml('d', tabbed, patterns)

      fallback = described_class.send(:_strip_with_rexml, tabbed, patterns['d'])

      expect(fallback).not_to include('<key>Stamp</key>')
      expect(fallback.scan(%r{<key>(.*?)</key>}).flatten).to eq(text_result.scan(%r{<key>(.*?)</key>}).flatten)
    end

    context 'when the plist is not tab-indented' do
      let(:spaced) { plist("<dict>\n    <key>Keep</key>\n    <string>x</string>\n    <key>Drop</key>\n    <string>y</string>\n</dict>") }

      it 'parses with REXML and removes the matching pair in one pass' do
        allow(described_class).to receive(:_normalize_xml) { |xml| xml }

        result = described_class.stripped_xml('d', spaced, { 'd' => ['Drop'] })

        expect(result).to include('<key>Keep</key>')
        expect(result).not_to include('Drop')
        expect(result).not_to include('<string>y</string>')
      end

      it 'returns the input unchanged when nothing matches' do
        expect(described_class.stripped_xml('d', spaced, { 'd' => ['Nope'] })).to equal(spaced)
      end

      it 'returns the input unchanged for malformed XML' do
        bad = "<plist><dict>\n    <key>a</key"

        expect(described_class.stripped_xml('d', bad, { 'd' => ['a'] })).to eq(bad)
      end
    end

    it 'falls back to REXML when the text layout is unexpected' do
      odd = plist("<dict>\n\t<key>Drop</key>\n\t<string>y</string>\n\tstray\n</dict>")
      allow(described_class).to receive(:_normalize_xml) { |xml| xml }

      expect(described_class).to receive(:_strip_with_rexml).and_call_original

      described_class.stripped_xml('d', odd, { 'd' => ['Drop'] })
    end
  end

  describe '.strip_excluded_keys' do
    it 'rewrites the file only when something was removed' do
      Dir.mktmpdir do |dir|
        file = Pathname(dir).join('x.plist')
        file.write(tabbed)
        described_class.strip_excluded_keys('d', file, { 'd' => ['Keep'] })
        expect(file.read).not_to include('<key>Keep</key>')

        file.write(plist("<dict>\n\t<key>Keep</key>\n\t<true/>\n</dict>"))
        mtime = file.mtime
        sleep 0.01
        described_class.strip_excluded_keys('d', file, {})
        expect(file.mtime).to eq(mtime)
      end
    end

    it 'ignores a missing file' do
      expect { described_class.strip_excluded_keys('d', '/nonexistent/x.plist', {}) }.not_to raise_error
    end
  end

  describe '.export_domain' do
    it 'streams `defaults export <domain> -` to the file in a single command' do
      expect(CommandUtils).to receive(:run_silent)
                                .with(MacOS::DEFAULTS_CMD, 'export', 'com.example', '-', out: '/tmp/x.plist').and_return(true)

      expect(described_class.export_domain('com.example', '/tmp/x.plist')).to be(true)
    end

    it 'removes the empty file and returns false when the export fails' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'x.plist')
        File.write(file, '')
        allow(CommandUtils).to receive(:run_silent).and_return(false)

        expect(described_class.export_domain('com.example', file)).to be(false)
        expect(File.exist?(file)).to be(false)
      end
    end

    it 'rejects a blank domain' do
      expect(described_class.export_domain('', '/tmp/x.plist')).to be(false)
    end
  end

  describe '.import_xml' do
    it 'pipes the XML to `defaults import <domain> -`' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3)
                         .with(MacOS::DEFAULTS_CMD, 'import', 'com.example', '-', stdin_data: '<plist/>').and_return(['', '', status])

      expect(described_class.import_xml('com.example', '<plist/>')).to be(true)
    end
  end
end
