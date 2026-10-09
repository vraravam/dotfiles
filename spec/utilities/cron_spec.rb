# frozen_string_literal: true

require 'cron'
require 'tmpdir'

RSpec.describe Cron do
  around do |example|
    Dir.mktmpdir('cron-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }

  describe '._valid_crontab?' do
    def valid?(content)
      file = tmp.join('crontab.txt')
      file.write(content)
      described_class.send(:_valid_crontab?, file)
    end

    it 'accepts comments, environment assignments and cron entries' do
      expect(valid?("# comment\nPATH=/usr/bin\n\n0 * * * * /bin/echo hi\n*/5 1 * * 1 cmd arg\n")).to be true
    end

    it 'rejects an entry with too few fields' do
      expect(valid?("0 * * * *\n")).to be false
    end

    it 'rejects an empty file and a missing file' do
      expect(valid?('')).to be false
      expect(described_class.send(:_valid_crontab?, tmp.join('missing'))).to be false
    end

    it 'reads UTF-8 content even when the default external encoding is US-ASCII (as under cron)' do
      original = Encoding.default_external
      verbose = $VERBOSE
      begin
        $VERBOSE = nil
        Encoding.default_external = Encoding::US_ASCII
        expect(valid?("# caf\u00e9 \u2014 comment\n0 * * * * echo \u2713\n")).to be true
      ensure
        Encoding.default_external = original
        $VERBOSE = verbose
      end
    end
  end

  describe '._cleanup_old_backups' do
    before { stub_const('EnvVars::TMPDIR', tmp) }

    it 'keeps only the 5 newest crontab_backup files' do
      (1..8).each do |i|
        file = tmp.join("crontab_backup#{i}")
        file.write(i.to_s)
        File.utime(Time.at(1_000_000 + i), Time.at(1_000_000 + i), file.to_s)
      end
      unrelated = tmp.join('other.txt')
      unrelated.write('keep')

      described_class.send(:_cleanup_old_backups)

      remaining = Dir[tmp.join('crontab_backup*').to_s].map { |f| File.basename(f) }
      expect(remaining).to contain_exactly('crontab_backup4', 'crontab_backup5', 'crontab_backup6', 'crontab_backup7', 'crontab_backup8')
      expect(unrelated).to exist
    end

    it 'does nothing when there are 5 or fewer' do
      3.times { |i| tmp.join("crontab_backup#{i}").write('x') }

      expect { described_class.send(:_cleanup_old_backups) }.not_to(change { Dir[tmp.join('crontab_backup*').to_s].size })
    end
  end
end
