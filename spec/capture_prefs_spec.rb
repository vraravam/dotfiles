# encoding: utf-8
# frozen_string_literal: true

require 'tempfile'
require 'tmpdir'
require_relative '../scripts/capture-prefs'

RSpec.describe CapturePrefs do
  around do |example|
    Dir.mktmpdir('capture-prefs-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:defaults_dir) { @tmp.join('configs', 'defaults') }
  let(:events) { [] }

  before do
    Logging.state.reset!
    stub_const('EnvVars::PERSONAL_CONFIGS_DIR', @tmp.join('configs'))
    stub_const('EnvVars::DOTFILES_DIR', @tmp)
    # Nothing here may touch the real home repo or the real export record.
    stub_const('EnvVars::XDG_CACHE_HOME', @tmp.join('cache'))
    default_git = instance_double(GitProcessor, repo?: false)
    allow(default_git).to receive(:add).and_return(['', '', instance_double(Process::Status, success?: true)])
    allow(GitProcessor).to receive(:new) { |*_args, &block| block ? block.call(default_git) : default_git }
    # The data-file paths are constants computed when the script loads (under the real
    # ${DOTFILES_DIR}, which does not exist on a CI runner), so point them at stand-ins.
    %w[ALLOWED_LIST_FILE DENIED_LIST_FILE EXCLUDED_KEYS_FILE].each do |const|
      data_file = @tmp.join("#{const.downcase}.txt")
      data_file.write('')
      stub_const("CapturePrefs::#{const}", data_file)
    end
    allow(LaunchServices).to receive(:export_handlers).and_return(true)
    allow(LaunchServices).to receive(:import_handlers).and_return(true)
    allow(MacOS).to receive(:reload_macos_prefs)
    allow(MacOS).to receive(:running_processes).and_return([])
    allow(Core).to receive(:running_in_tty?).and_return(false)
    allow(MacOS).to receive(:suspend_softwareupdate_schedule) { events << :suspend }
    allow(MacOS).to receive(:resume_softwareupdate_schedule) { events << :resume }
    allow(MacOS).to receive(:kill_login_item_apps) { events << :kill_apps }
    allow(MacOS).to receive(:restart_login_item_apps) { events << :restart_apps }
    # No domains: the run does its set-up and clean-up but processes nothing.
    allow(Plist).to receive(:load_denied_list).and_return(Set.new)
    allow(Plist).to receive(:load_excluded_keys).and_return({})
    allow(Plist).to receive(:load_domains_list).and_return(Set.new)
  end

  after { Logging.state.reset! }

  def run_quietly(operation)
    original = $stdout
    $stdout = StringIO.new
    described_class.run(operation: operation)
  ensure
    $stdout = original
  end

  describe 'running more than once in the same process' do
    it 'does not treat an import that follows an export as an export' do
      defaults_dir.mkpath
      defaults_dir.join('a.plist').write('x')

      run_quietly('export')
      expect(defaults_dir.join('a.plist')).not_to exist # an export clears the old files first

      defaults_dir.join('a.plist').write('x')
      run_quietly('import')

      expect(defaults_dir.join('a.plist')).to exist
    end

    it 'treats an export that follows an import as an export' do
      defaults_dir.mkpath
      run_quietly('import')

      defaults_dir.join('a.plist').write('x')
      run_quietly('export')

      expect(defaults_dir.join('a.plist')).not_to exist
    end
  end

  describe 'importing a domain' do
    let(:xml) { "<?xml version=\"1.0\"?>\n<plist version=\"1.0\">\n<dict>\n\t<key>Keep</key>\n\t<true/>\n\t<key>Drop</key>\n\t<true/>\n</dict>\n</plist>\n" }

    before do
      defaults_dir.mkpath
      defaults_dir.join('com.example.plist').write(xml)
      allow(Plist).to receive(:load_domains_list).and_return(Set['com.example'])
      allow(Plist).to receive(:load_excluded_keys).and_return('com.example' => ['Drop'])
      allow(LaunchServices).to receive(:import_handlers)
      allow(MacOS).to receive(:reload_macos_prefs)
      allow(MacOS).to receive(:running_processes).and_return([])
    end

    it 'strips excluded keys in memory and imports through stdin, without temp files' do
      expect(Tempfile).not_to receive(:new)
      expect(Plist).to receive(:import_xml) do |domain, imported|
        expect(domain).to eq('com.example')
        expect(imported).to include('<key>Keep</key>')
        expect(imported).not_to include('Drop')
        true
      end

      run_quietly('import')

      expect(defaults_dir.join('com.example.plist').read).to eq(xml) # the stored file is untouched
    end

    it 'records a warning when the import fails' do
      allow(Plist).to receive(:import_xml).and_return(false)
      expect(Logging).to receive(:record_warning).with(/Failed to import/)

      run_quietly('import')
    end
  end

  describe 'restoring what it changed' do
    it 'resumes the software update schedule right after the run, not at process exit' do
      expect(described_class).not_to receive(:at_exit)

      run_quietly('export')

      expect(events).to eq(%i[suspend resume])
    end

    it 'stops the login-item apps for an interactive import and restarts them before resuming the schedule' do
      allow(Core).to receive(:running_in_tty?).and_return(true)

      run_quietly('import')

      expect(events).to eq(%i[suspend kill_apps restart_apps resume])
    end

    it 'leaves the login-item apps alone for an export, and for a non-interactive import' do
      allow(Core).to receive(:running_in_tty?).and_return(true)
      run_quietly('export')
      allow(Core).to receive(:running_in_tty?).and_return(false)
      run_quietly('import')

      expect(events).to eq(%i[suspend resume suspend resume])
    end

    it 'restores everything, and lets the error through, when the run raises' do
      allow(Core).to receive(:running_in_tty?).and_return(true)
      allow(Plist).to receive(:load_denied_list).and_raise('denied list missing')

      expect { run_quietly('import') }.to raise_error(RuntimeError, 'denied list missing')

      expect(events).to eq(%i[suspend kill_apps restart_apps resume])
    end

    it 'does not suspend anything for an invalid operation' do
      expect { run_quietly('sideways') }.to raise_error(RuntimeError, /Invalid operation/)

      expect(events).to be_empty
    end

    it 'restores nothing it did not start when the set-up fails first' do
      stub_const('EnvVars::DOTFILES_DIR', @tmp.join('missing'))

      expect { run_quietly('export') }.to raise_error(RuntimeError, /DOTFILES_DIR not found/)

      expect(events).to be_empty
    end
  end

  describe 'being bracketed by the caller' do
    it 'does not suspend, stop, restart, resume or reload anything with manage_apps: false' do
      allow(Core).to receive(:running_in_tty?).and_return(true)
      allow(MacOS).to receive(:reload_macos_prefs) { events << :reload }
      allow(MacOS).to receive(:running_processes).and_return([])
      allow(LaunchServices).to receive(:import_handlers)
      defaults_dir.mkpath

      described_class.send(:run, operation: 'import', manage_apps: false)

      expect(events).to be_empty
    end

    it 'does the same when DOTFILES_APPS_BRACKETED is set' do
      allow(Core).to receive(:running_in_tty?).and_return(true)
      allow(MacOS).to receive(:reload_macos_prefs) { events << :reload }
      allow(MacOS).to receive(:running_processes).and_return([])
      allow(LaunchServices).to receive(:import_handlers)

      with_env('DOTFILES_APPS_BRACKETED' => '1') { run_quietly('import') }

      expect(events).to be_empty
    end

    it 'still brackets, and reloads, on its own when run standalone' do
      allow(Core).to receive(:running_in_tty?).and_return(true)
      allow(MacOS).to receive(:reload_macos_prefs) { events << :reload }
      allow(MacOS).to receive(:running_processes).and_return([])
      allow(LaunchServices).to receive(:import_handlers)
      allow(Plist).to receive(:load_domains_list).and_return(Set['com.example'])
      defaults_dir.mkpath
      allow(Plist).to receive(:import_xml).and_return(true)
      defaults_dir.join('com.example.plist').write("<plist><dict>\n</dict></plist>\n")

      with_env('DOTFILES_APPS_BRACKETED' => nil) { run_quietly('import') }

      expect(events).to eq(%i[suspend kill_apps reload restart_apps resume])
    end
  end

  describe '.parallel_map' do
    it 'returns the results in the order of the items, whatever order the workers finish in' do
      items = (0...8).to_a
      outcomes = described_class.parallel_map(items, 4) do |item|
        sleep((8 - item) * 0.005)
        item * 10
      end

      expect(outcomes.map(&:value)).to eq(items.map { |item| item * 10 })
      expect(outcomes.map(&:error)).to all(be_nil)
    end

    it 'really runs the items concurrently up to the number of jobs' do
      arrived = Queue.new
      release = Queue.new
      gate = Thread.new do
        3.times { arrived.pop }
        3.times { release << true }
      end

      outcomes = described_class.parallel_map(%w[a b c], 3) do |item|
        arrived << item
        release.pop # returns only once all three workers have arrived
        item.upcase
      end

      expect(gate.join(5)).not_to be_nil
      expect(outcomes.map(&:value)).to eq(%w[A B C])
    end

    it 'never runs more than the given number of workers at once' do
      running = 0
      peak = 0
      lock = Mutex.new
      described_class.parallel_map((1..12).to_a, 3) do |_item|
        lock.synchronize { peak = [peak, running += 1].max }
        sleep 0.01
        lock.synchronize { running -= 1 }
      end

      expect(peak).to be <= 3
      expect(peak).to be > 1
    end

    it 'runs in the calling thread with one job' do
      threads = described_class.parallel_map([1, 2, 3], 1) { Thread.current }.map(&:value)

      expect(threads.uniq).to eq([Thread.current])
    end

    it 'gives the same results serially and in parallel' do
      items = (1..20).to_a

      serial = described_class.parallel_map(items, 1) { |item| item + 100 }.map(&:value)
      pooled = described_class.parallel_map(items, 6) { |item| item + 100 }.map(&:value)

      expect(pooled).to eq(serial)
    end

    it 'captures an exception per item instead of losing the worker' do
      outcomes = described_class.parallel_map([1, 2, 3], 2) { |item| item == 2 ? raise('boom') : item }

      expect(outcomes.map(&:value)).to eq([1, nil, 3])
      expect(outcomes[1].error.message).to eq('boom')
    end

    it 'handles no items' do
      expect(described_class.parallel_map([], 4) { raise 'unused' }).to eq([])
    end
  end

  describe 'exporting and importing domains on the pool' do
    let(:domains) { %w[com.a com.b com.c com.d com.e] }
    let(:xml) { "<?xml version=\"1.0\"?>\n<plist version=\"1.0\">\n<dict>\n\t<key>K</key>\n\t<true/>\n</dict>\n</plist>\n" }

    before do
      allow(Plist).to receive(:load_domains_list).and_return(Set.new(domains))
      allow(LaunchServices).to receive(:export_handlers).and_return(true)
      allow(LaunchServices).to receive(:import_handlers)
      allow(MacOS).to receive(:reload_macos_prefs)
      allow(MacOS).to receive(:running_processes).and_return([])
      allow(GitProcessor).to receive(:new)
      allow(EnvVars).to receive(:capture_prefs_jobs).and_return(4)
    end

    def stub_export(failing: [], empty: [])
      allow(Plist).to receive(:export_domain) do |domain, file|
        next false if failing.include?(domain)

        Pathname(file).write(empty.include?(domain) ? "<plist><dict/></plist>\n" : xml)
        true
      end
    end

    it 'logs the warnings of failed exports in the order of the domains and keeps the successes' do
      stub_export(failing: %w[com.e com.b])
      warnings = []
      allow(Logging).to receive(:record_warning) { |message| warnings << message }

      run_quietly('export')

      expect(warnings.grep(/Failed to export/).map { |warning| warning[/com\.\w/] }).to eq(%w[com.b com.e])
      expect(defaults_dir.children.map(&:basename).map(&:to_s).sort).to eq(%w[com.a.plist com.c.plist com.d.plist])
    end

    it 'deletes the plists that have no keys left' do
      stub_export(empty: %w[com.c])

      run_quietly('export')

      expect(defaults_dir.join('com.c.plist')).not_to exist
      expect(defaults_dir.join('com.a.plist')).to exist
    end

    it 'produces byte-identical files serially and pooled' do
      stub_export
      allow(EnvVars).to receive(:capture_prefs_jobs).and_return(1)
      run_quietly('export')
      serial = defaults_dir.children.sort.to_h { |file| [file.basename.to_s, file.read] }
      defaults_dir.children.each(&:delete)

      allow(EnvVars).to receive(:capture_prefs_jobs).and_return(5)
      run_quietly('export')
      pooled = defaults_dir.children.sort.to_h { |file| [file.basename.to_s, file.read] }

      expect(pooled).to eq(serial)
    end

    it 'logs the failed imports in the order of the domains, and the result is the same as with one job' do
      defaults_dir.mkpath
      domains.each { |domain| defaults_dir.join("#{domain}.plist").write(xml) }
      defaults_dir.join('com.c.plist').delete
      allow(Plist).to receive(:import_xml) { |domain, _xml| !%w[com.d com.a].include?(domain) }
      warnings = []
      allow(Logging).to receive(:record_warning) { |message| warnings << message }

      run_quietly('import')

      expect(warnings.grep(/Failed to import/).map { |warning| warning[/com\.\w/] }).to eq(%w[com.a com.d])
    end

    it 'lets an exception from a domain through, as the serial run always did' do
      allow(Plist).to receive(:export_domain).and_raise('plist exploded')

      expect { run_quietly('export') }.to raise_error('plist exploded')
    end
  end

  describe 'recording when this machine last exported' do
    let(:cache) { @tmp.join('cache') }

    before do
      stub_const('EnvVars::XDG_CACHE_HOME', cache)
      allow(LaunchServices).to receive(:export_handlers).and_return(true)
    end

    it 'has no record before the first export' do
      expect(described_class.last_export_time).to be_nil
    end

    it 'writes the record, under a name delete_caches keeps, after a successful export' do
      git = instance_double(GitProcessor, repo?: true, smart_commit: true)
      allow(git).to receive(:add).and_return(['', '', instance_double(Process::Status, success?: true)])
      allow(GitProcessor).to receive(:new).and_yield(git)

      run_quietly('export')

      expect(described_class::EXPORT_STAMP_NAME).to include('stamp')
      expect(cache.join(described_class::EXPORT_STAMP_NAME)).to exist
      expect(described_class.last_export_time).to be_within(5).of(Time.now)
    end

    it 'does not write it when the commit failed (the backup in the repo is not up to date)' do
      git = instance_double(GitProcessor, repo?: true, smart_commit: false)
      allow(git).to receive(:add).and_return(['', '', instance_double(Process::Status, success?: true)])
      allow(GitProcessor).to receive(:new).and_yield(git)

      run_quietly('export')

      expect(cache.join(described_class::EXPORT_STAMP_NAME)).not_to exist
    end

    it 'does not write it for an import' do
      allow(MacOS).to receive(:reload_macos_prefs)
      allow(MacOS).to receive(:running_processes).and_return([])
      allow(LaunchServices).to receive(:import_handlers)

      run_quietly('import')

      expect(cache.join(described_class::EXPORT_STAMP_NAME)).not_to exist
    end
  end
end
