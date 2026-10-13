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
    # The data-file paths are constants computed when the script loads (under the real
    # ${DOTFILES_DIR}, which does not exist on a CI runner), so point them at stand-ins.
    %w[ALLOWED_LIST_FILE DENIED_LIST_FILE EXCLUDED_KEYS_FILE].each do |const|
      data_file = @tmp.join("#{const.downcase}.txt")
      data_file.write('')
      stub_const("CapturePrefs::#{const}", data_file)
    end
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
end
