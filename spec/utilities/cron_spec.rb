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

  describe '.recron' do
    before do
      Logging.state.reset!
      stub_const('Cron::CRONTAB_FILE', tmp.join('crontab.txt'))
    end

    after { Logging.state.reset! }

    # Simulates 'crontab -l' by writing +existing+ into the capture file recron asks for.
    def stub_existing_crontab(existing)
      allow(CommandUtils).to receive(:run_silent) do |*args, **opts|
        File.write(opts[:out], existing) if args == %w[crontab -l]
        true
      end
    end

    it 'is true after loading the existing crontab' do
      stub_existing_crontab("0 * * * * echo hi\n")
      expect(described_class).to receive(:restore_cron).and_return(true)

      expect { expect(described_class.recron).to be true }.to output.to_stdout
    end

    it 'is false when the schedule could not be loaded' do
      stub_existing_crontab("0 * * * * echo hi\n")
      allow(described_class).to receive(:restore_cron).and_return(false)

      expect(described_class.recron).to be false
    end

    it 'falls back to the tracked crontab.txt when there is no active crontab' do
      stub_existing_crontab('')
      tmp.join('crontab.txt').write("0 * * * * echo hi\n")
      expect(described_class).to receive(:restore_cron).with(tmp.join('crontab.txt')).and_return(true)

      expect { expect(described_class.recron).to be true }.to output.to_stdout
    end

    it 'is true, without loading anything, when there is no schedule anywhere' do
      stub_existing_crontab('')
      expect(described_class).not_to receive(:restore_cron)

      expect { expect(described_class.recron).to be true }.to output.to_stdout
    end
  end

  describe '.with_cron_suspended' do
    let(:backup) { tmp.join('crontab_backup') }

    before do
      Logging.state.reset!
      backup.write("0 * * * * echo original\n")
      allow(EnvVars).to receive(:cron_backup_file).and_return(backup)
      allow(described_class).to receive(:suspend_cron)
    end

    after { Logging.state.reset! }

    it 'removes the backup once the crontab was reinstalled' do
      allow(described_class).to receive(:recron).and_return(true)

      described_class.with_cron_suspended { :work }

      expect(backup).not_to exist
    end

    it 'keeps the backup of the original schedule when the reinstall failed' do
      allow(described_class).to receive(:recron).and_return(false)

      expect { described_class.with_cron_suspended { :work } }.to output(/keeping the backup/).to_stdout

      expect(backup).to exist
    end

    it 'restores from the backup instead when the block raises' do
      expect(described_class).to receive(:resume_cron)
      expect(described_class).not_to receive(:recron)

      expect { described_class.with_cron_suspended { raise 'boom' } }.to raise_error('boom')
    end
  end
end
