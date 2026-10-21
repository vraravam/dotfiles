# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../scripts/cleanup-browser-profiles'

RSpec.describe CleanupBrowserProfiles do
  def call(name, *args)
    described_class.send(name, *args)
  end

  describe '._scan_profile' do
    let(:file_patterns) { ['.DS_Store', '*.log', '*.bak*', 'signons*.txt', 'compatibility.ini', '*healthreport*'] }
    let(:dir_patterns) { %w[crashes thumbnails] }

    # What the previous implementation computed: one recursive Dir.glob per pattern.
    def globbed(root, file_patterns, dir_patterns)
      items = file_patterns.flat_map { |pattern| Dir.glob(root.join('**', pattern), File::FNM_CASEFOLD) }
      dir_patterns.each do |pattern|
        Dir.glob(root.join('**', pattern), File::FNM_CASEFOLD).each { |path| items << path if File.directory?(path) }
      end
      [Dir.glob(root.join('**', '*.sqlite')), items.uniq]
    end

    it 'selects exactly what the per-pattern recursive globs selected' do
      Dir.mktmpdir('cleanup-spec-') do |dir|
        root = Pathname(dir)
        names = %w[.DS_Store x.log X.LOG a.bak1 .hidden.log foo.sqlite FOO.SQLITE .h.sqlite x.sqlite-wal Signons3.txt
                   COMPATIBILITY.INI MyHealthReport.json .healthreport keep.txt]
        ['', 'a', 'a/b', '.hid', '.hid/in', 'crashes', 'Crashes/sub', 'thumbnails/deep', 'x.bak.d/inner'].each do |sub|
          FileUtils.mkdir_p(root.join(sub))
          names.each { |name| FileUtils.touch(root.join(sub, name)) unless root.join(sub, name).exist? }
        end
        File.symlink(root.join('a').to_s, root.join('linkdir').to_s)
        File.symlink('/nonexistent', root.join('broken.log').to_s)

        sqlite, items = call(:_scan_profile, root, file_patterns, dir_patterns)
        expected_sqlite, expected_items = globbed(root, file_patterns, dir_patterns)

        expect(items).not_to be_empty
        expect(items).to match_array(expected_items)
        expect(sqlite).to match_array(expected_sqlite)
        expect(items.grep(%r{/\.hid/})).to eq(expected_items.grep(%r{/\.hid/})) # hidden dirs are not entered
        expect(items.none? { |path| path.include?('/linkdir/') }).to be(true)   # symlinked dirs are not followed
      end
    end

    it 'does not list the profile root itself' do
      Dir.mktmpdir('crashes') do |dir|
        _sqlite, items = call(:_scan_profile, Pathname(dir), [], ['crashes*'])

        expect(items).to be_empty
      end
    end
  end

  describe '._format_size' do
    {
      0 => '0', 1 => '1.0K', 500 => '500K', 1023 => '1023K', 1024 => '1.0M', 1536 => '1.5M',
      10_239 => '10M', 234 * 1024 => '234M', 1_572_864 => '1.5G', 1_048_575 => '1.0G', -2048 => '-2.0M'
    }.each do |kb, expected|
      it "formats #{kb}K as #{expected}" do
        expect(call(:_format_size, kb)).to eq(expected)
      end
    end

    it 'does not fork anything' do
      expect(CommandUtils).not_to receive(:query)

      call(:_format_size, 123_456)
    end
  end

  describe '._browser_running?' do
    it 'asks for the browser exact process names in a single lookup' do
      expect(MacOS).to receive(:running_processes).with(['Google Chrome', 'Google Chrome Beta', 'Google Chrome Canary', 'Chromium']).and_return(['Google Chrome'])

      expect(call(:_browser_running?, 'chrome')).to be(true)
    end

    it 'is false when none of the names is running' do
      allow(MacOS).to receive(:running_processes).with(%w[zen]).and_return([])

      expect(call(:_browser_running?, 'zen')).to be(false)
    end
  end

  describe 'library mode' do
    it 'has nil_or_empty? available without the CLI block (nothing to delete)' do
      expect(call(:_delete_items, [], false)).to be_nil
    end
  end
end
