# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require_relative '../scripts/setup-login-item'

RSpec.describe SetupLoginItem do
  around do |example|
    Dir.mktmpdir('setup-login-item-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:brewfile) { @tmp.join('Brewfile') }
  let(:record) { @tmp.join('state', 'login-item-apps') }

  before do
    Logging.state.reset!
    allow(Logging).to receive(:info)
    allow(Logging).to receive(:record_warning)
  end

  describe '.managed_app_names' do
    it 'takes the -a names of active setup_login_items_script lines and the built-in list, once each' do
      stub_const('MacOS::LOGIN_ITEM_APPS', %w[Clocker KeyCastr].freeze)
      brewfile.write(<<~'BREWFILE')
        cask 'clocker', postinstall: "\"#{setup_login_items_script}\" -a 'Clocker'"
        cask 'keycastr', postinstall: "\"#{setup_login_items_script}\" -a 'Keycastr'"
        cask 'wobbly', trusted: true, postinstall: "\"#{setup_login_items_script}\" -a 'Wobbly'"
        cask 'protonvpn' # , postinstall: "\"#{setup_login_items_script}\" -a 'ProtonVPN'"
        # cask 'boring', postinstall: "\"#{setup_login_items_script}\" -a 'boringNotch'"
        cask 'plain'
      BREWFILE

      expect(described_class.managed_app_names(brewfile: brewfile)).to eq(%w[Clocker Keycastr Wobbly])
    end

    it 'handles a continued line like the Keybase one' do
      stub_const('MacOS::LOGIN_ITEM_APPS', [].freeze)
      brewfile.write(<<~'BREWFILE')
        cask 'keybase',
             postinstall: "\"#{setup_login_items_script}\" -a 'Keybase' && " \
                          'other'
      BREWFILE

      expect(described_class.managed_app_names(brewfile: brewfile)).to eq(%w[Keybase])
    end

    it 'falls back to the built-in list when there is no Brewfile' do
      stub_const('MacOS::LOGIN_ITEM_APPS', %w[Clocker].freeze)

      expect(described_class.managed_app_names(brewfile: @tmp.join('missing'))).to eq(%w[Clocker])
    end
  end

  describe '.register_managed' do
    before do
      stub_const('Core::ROOT', @tmp)
      %w[Clocker Thaw].each { |name| @tmp.join('Applications', "#{name}.app").mkpath }
      allow(described_class).to receive(:brewfile_app_names).and_return(%w[Clocker Thaw Absent])
      allow(CommandUtils).to receive(:query).with('sw_vers', '-productVersion').and_return(macos_version)
    end

    context 'on macOS 26 and later' do
      let(:macos_version) { '27.2' }

      def login_items(names)
        allow(CommandUtils).to receive(:query).with(MacOS::OSASCRIPT_CMD, '-e', /get the name of every login item/).and_return(names)
      end

      it 'registers only the installed apps that have no login item yet' do
        login_items('Clocker, Stats')
        expect(described_class).to receive(:run).with(app_name: 'Thaw').and_return(true)
        expect(described_class).not_to receive(:run).with(app_name: 'Clocker')
        expect(described_class).not_to receive(:run).with(app_name: 'Absent')

        expect(described_class.register_managed(brewfile: brewfile, record: record)).to be true
      end

      it 'does nothing, and prints nothing, when every installed app already has one' do
        login_items('Clocker, Thaw')
        expect(described_class).not_to receive(:run)

        expect(described_class.register_managed(brewfile: brewfile, record: record)).to be true
        expect(Logging).not_to have_received(:info)
      end

      it 'fails when an app that is missing cannot be registered' do
        login_items('')
        allow(described_class).to receive(:run).and_return(true, false)

        expect(described_class.register_managed(brewfile: brewfile, record: record)).to be false
      end

      it 'does not even ask System Events when no managed app is installed' do
        allow(described_class).to receive(:brewfile_app_names).and_return(%w[Absent])
        expect(CommandUtils).not_to receive(:query).with(MacOS::OSASCRIPT_CMD, '-e', anything)

        expect(described_class.register_managed(brewfile: brewfile, record: record)).to be true
      end
    end

    context 'on macOS 14-25' do
      let(:macos_version) { '15.2' }
      let(:clocker) { @tmp.join('Applications', 'Clocker.app').to_s }
      let(:status) { instance_double(Process::Status, success?: true) }

      it 'registers only the apps swift reports as missing, from one status lookup' do
        expect(Open3).to receive(:capture3).once.and_return(["missing #{@tmp.join('Applications', 'Thaw.app')}\n", '', status])
        expect(described_class).to receive(:run).with(app_name: 'Thaw').and_return(true)
        expect(described_class).not_to receive(:run).with(app_name: 'Clocker')

        expect(described_class.register_managed(brewfile: brewfile, record: record)).to be true
      end

      it 'registers every installed app when the status lookup fails (only the output is repeated)' do
        allow(Open3).to receive(:capture3).and_return(['', 'boom', instance_double(Process::Status, success?: false)])
        expect(described_class).to receive(:run).with(app_name: 'Clocker').and_return(true)
        expect(described_class).to receive(:run).with(app_name: 'Thaw').and_return(true)

        expect(described_class.register_managed(brewfile: brewfile, record: record)).to be true
      end

      it 'does nothing when swift reports nothing missing' do
        allow(Open3).to receive(:capture3).and_return(['', '', status])
        expect(described_class).not_to receive(:run)

        expect(described_class.register_managed(brewfile: brewfile, record: record)).to be true
      end
    end
  end

  describe '.unregister_removed' do
    before do
      stub_const('Core::ROOT', @tmp)
      %w[Clocker Thaw Gone].each { |name| @tmp.join('Applications', "#{name}.app").mkpath }
      brewfile.write(<<~'BREWFILE')
        cask 'clocker', postinstall: "\"#{setup_login_items_script}\" -a 'Clocker'"
        cask 'thaw', postinstall: "\"#{setup_login_items_script}\" -a 'Thaw'"
      BREWFILE
    end

    it 'only learns the current apps, and removes nothing, when there is no record yet' do
      expect(described_class).not_to receive(:remove)

      expect(described_class.unregister_removed(brewfile: brewfile, record: record)).to be true
      expect(record.read.lines.map(&:strip)).to eq(%w[Clocker Thaw])
    end

    it 'removes the login item of exactly the app that left the Brewfile, and records the current apps' do
      record.dirname.mkpath
      record.write("Clocker\nGone\nThaw\n")
      expect(described_class).to receive(:remove).with(app_names: %w[Gone]).and_return(true)

      expect(described_class.unregister_removed(brewfile: brewfile, record: record)).to be true
      expect(record.read.lines.map(&:strip)).to eq(%w[Clocker Thaw])
    end

    it 'does nothing when nothing left the Brewfile' do
      record.dirname.mkpath
      record.write("Clocker\nThaw\n")
      expect(described_class).not_to receive(:remove)

      expect(described_class.unregister_removed(brewfile: brewfile, record: record)).to be true
    end

    it 'does not touch an app that is no longer installed, and forgets it' do
      record.dirname.mkpath
      record.write("Clocker\nUninstalled\nThaw\n")
      expect(described_class).not_to receive(:remove)

      expect(described_class.unregister_removed(brewfile: brewfile, record: record)).to be true
      expect(record.read.lines.map(&:strip)).to eq(%w[Clocker Thaw])
    end

    it 'keeps an app whose login item could not be removed in the record, for the next run' do
      record.dirname.mkpath
      record.write("Clocker\nGone\nThaw\n")
      allow(described_class).to receive(:remove).and_return(false)

      expect(described_class.unregister_removed(brewfile: brewfile, record: record)).to be false
      expect(record.read.lines.map(&:strip)).to eq(%w[Clocker Thaw Gone])
    end

    it 'leaves everything alone when there is no Brewfile (it must not look like every app was dropped)' do
      record.dirname.mkpath
      record.write("Clocker\n")
      expect(described_class).not_to receive(:remove)

      expect(described_class.unregister_removed(brewfile: @tmp.join('missing'), record: record)).to be true
      expect(record.read).to eq("Clocker\n")
    end
  end

  describe '.brewfile_app_names' do
    it 'follows the Brewfile alone, not the built-in list' do
      stub_const('MacOS::LOGIN_ITEM_APPS', %w[ProtonVPN].freeze)
      brewfile.write("cask 'clocker', postinstall: \"\\\"\#{setup_login_items_script}\\\" -a 'Clocker'\"\n")

      expect(described_class.brewfile_app_names(brewfile: brewfile)).to eq(%w[Clocker])
    end
  end

  describe '.remove' do
    before do
      stub_const('Core::ROOT', @tmp)
      @tmp.join('Applications', 'Clocker.app').mkpath
      @tmp.join('Applications', 'Thaw.app').mkpath
      allow(CommandUtils).to receive(:query).with('sw_vers', '-productVersion').and_return(macos_version)
    end

    context 'on macOS 14-25' do
      let(:macos_version) { '15.2' }

      it 'unregisters only the installed apps, in one swift run' do
        expect(described_class).to receive(:_unregister_smappservice)
          .with([@tmp.join('Applications', 'Clocker.app').to_s, @tmp.join('Applications', 'Thaw.app').to_s]).and_return(true)

        expect(described_class.remove(app_names: %w[Clocker NotInstalled Thaw])).to be true
      end
    end

    context 'on macOS 26 and later' do
      let(:macos_version) { '27.2' }

      it 'deletes only the System Events items whose name matches a managed app' do
        allow(CommandUtils).to receive(:query).with(MacOS::OSASCRIPT_CMD, '-e', /get the name of every login item/)
                                              .and_return('Clocker, Stats, thaw')
        expect(CommandUtils).to receive(:run_silent).with(MacOS::OSASCRIPT_CMD, '-e', /delete login item "Clocker"/).and_return(true)
        expect(CommandUtils).to receive(:run_silent).with(MacOS::OSASCRIPT_CMD, '-e', /delete login item "thaw"/).and_return(true)

        expect(described_class.remove(app_names: %w[Clocker Thaw])).to be true
      end

      it 'records a warning and fails when one cannot be deleted' do
        allow(CommandUtils).to receive(:query).with(MacOS::OSASCRIPT_CMD, '-e', anything).and_return('Clocker')
        allow(CommandUtils).to receive(:run_silent).and_return(false)

        expect(described_class.remove(app_names: %w[Clocker])).to be false
        expect(Logging).to have_received(:record_warning).with(/Clocker/)
      end

      it 'succeeds without asking System Events when no managed app is installed' do
        expect(CommandUtils).not_to receive(:query).with(MacOS::OSASCRIPT_CMD, '-e', anything)

        expect(described_class.remove(app_names: %w[NotInstalled])).to be true
      end
    end
  end
end
