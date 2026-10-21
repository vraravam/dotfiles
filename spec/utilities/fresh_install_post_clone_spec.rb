# encoding: utf-8
# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'fresh_install_post_clone'

RSpec.describe FreshInstallPostClone do
  around do |example|
    Dir.mktmpdir('post-clone-spec-') do |dir|
      @tmp = Pathname(dir)
      # A standalone Logging.run_script (depth 0) raises _DOTFILES_SCRIPT_DEPTH and never lowers it
      # again, which is harmless in a one-shot script but would leak into later examples here.
      with_env('_DOTFILES_SCRIPT_DEPTH' => nil) { example.run }
    end
  end

  let(:tmp) { @tmp }
  let(:events) { [] }
  let(:ok_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failed_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:git) { instance_double(GitProcessor) }
  let(:cron_backup) { tmp.join('crontab_backup') }

  before do
    Logging.state.reset!
    EnvVars.remove_instance_variable(:@_issues_file) if EnvVars.instance_variable_defined?(:@_issues_file)
    %w[HOME XDG_CACHE_HOME HOMEBREW_PREFIX].each { |name| stub_const("EnvVars::#{name}", tmp.join(name.downcase)) }
    stub_const('EnvVars::ZDOTDIR', tmp.join('zdotdir'))
    stub_const('EnvVars::DOTFILES_DIR', tmp.join('dotfiles'))
    allow(EnvVars).to receive(:first_install?).and_return(false)
    allow(EnvVars).to receive(:cron_backup_file).and_return(cron_backup)

    allow(PathUtils).to receive(:append_to_path)
    allow(AddUpstreamGitConfig).to receive(:run).and_return(true)
    allow(ShellrcCheck).to receive(:matches_repo?).and_return(true)
    allow(InstallDotfiles).to receive(:run).and_return(true)
    allow(CommandUtils).to receive(:run_interactive).and_return(true)
    allow(CommandUtils).to receive(:run_silent).and_return(true)
    allow(git).to receive(:run_alias).and_return(['', '', ok_status])
    allow(GitProcessor).to receive(:new) { |*_args, &block| block ? block.call(git) : git }
    allow(HomebrewInstall).to receive(:run).and_return(true)
    allow(MacOS).to receive(:load_brew_shellenv)
    allow(MacOS).to receive(:notify)
    allow(BrewBundle).to receive(:run).and_return(true)
    allow(Keybase).to receive(:bootstrap_login).and_return(true)
    allow(GpgEncrypt).to receive(:bootstrap_setup).and_return(true)
    allow(BootstrapRepos).to receive(:run).and_return(true)
    allow(PreferencesRestore).to receive(:run).and_return(true)
    allow(PreferencesRestore).to receive(:start_baseline_in_background).and_return(true)
    allow(PreferencesRestore).to receive(:finish_pending)
    allow(BrewBundle).to receive(:report_full_install).and_return(:none)
    allow(BrewBundle).to receive(:full_install_state).and_return(:none)
    allow(Cron).to receive(:recron).and_return(true)
    allow(Cron).to receive(:retire_backup) { |backup| backup.delete if backup.file? }
    allow(Cron).to receive(:resume_cron)
    allow(ResurrectRepositories).to receive(:run).and_return(true)
    allow(DefaultShell).to receive(:run).and_return(true)
    allow(Logging).to receive(:user_action)
  end

  after do
    Logging.state.reset!
    EnvVars.remove_instance_variable(:@_issues_file) if EnvVars.instance_variable_defined?(:@_issues_file)
  end

  def run_quietly(**kwargs)
    original = $stdout
    $stdout = StringIO.new
    @output = $stdout
    described_class.run(**kwargs)
  ensure
    $stdout = original
  end

  def printed
    @output.string
  end

  describe 'the order of the steps' do
    it 'runs every step once, in order' do
      allow(ShellrcCheck).to receive(:matches_repo?) { events << :shellrc_check }
      allow(InstallDotfiles).to receive(:run) { events << :install_dotfiles }
      allow(HomebrewInstall).to receive(:run) { events << :homebrew }
      allow(BrewBundle).to receive(:run) { events << :brew_bundle }
      allow(Keybase).to receive(:bootstrap_login) { events << :keybase }
      allow(GpgEncrypt).to receive(:bootstrap_setup) { events << :gpg }
      allow(BootstrapRepos).to receive(:run) { events << :bootstrap_repos }
      allow(PreferencesRestore).to receive(:run) { events << :preferences }
      allow(Cron).to receive(:recron) { events << :cron }
      allow(ResurrectRepositories).to receive(:run).with(resurrect_all: true) { events << :tracked_repos }
      allow(DefaultShell).to receive(:run) { events << :default_shell }

      expect(run_quietly(steps_done: 6)).to be true
      expect(events).to eq(%i[shellrc_check install_dotfiles homebrew brew_bundle keybase gpg bootstrap_repos preferences tracked_repos cron default_shell])
    end

    it 'installs the cron schedule only after the clones, and before the cache refresh and the default shell' do
      allow(ResurrectRepositories).to receive(:run).with(resurrect_all: true) { events << :tracked_repos }
      allow(Cron).to receive(:recron) { events << :cron }
      allow(CommandUtils).to receive(:run_interactive).with({}, 'zsh', '-c', /delete_caches/) { events << :caches }
      allow(DefaultShell).to receive(:run) { events << :default_shell }

      run_quietly

      expect(events).to eq(%i[tracked_repos cron caches default_shell])
    end

    it 'puts the repo scripts on PATH and sets up the upstream remote first' do
      expect(PathUtils).to receive(:append_to_path).with(tmp.join('dotfiles', 'scripts')).ordered
      expect(AddUpstreamGitConfig).to receive(:run).with(dir: tmp.join('dotfiles'), upstream_owner: EnvVars::UPSTREAM_GH_USERNAME).ordered.and_return(true)
      expect(ShellrcCheck).to receive(:matches_repo?).ordered.and_return(true)

      run_quietly
    end

    it 'exports the Homebrew environment into this process between the install and the Brewfile' do
      expect(HomebrewInstall).to receive(:run).ordered.and_return(true)
      expect(MacOS).to receive(:load_brew_shellenv).with(EnvVars::HOMEBREW_PREFIX.join('bin', 'brew')).ordered
      expect(BrewBundle).to receive(:run).ordered.and_return(true)

      run_quietly
    end

    it 'stops overriding core.sshCommand once the git config is linked' do
      with_env('GIT_SSH_COMMAND' => 'ssh -o X=1') do
        run_quietly

        expect(ENV['GIT_SSH_COMMAND']).to be_nil
      end
    end
  end

  describe 'step numbering' do
    it 'continues after the steps the shell already numbered, up to the total' do
      run_quietly(steps_done: 6)

      (7..14).each { |n| expect(printed).to include("Step #{n} of 14") }
      expect(printed).not_to include('Step 6 of')
      expect(printed).not_to include('Step 15 of')
    end

    it 'accepts the count as the string call-utility passes' do
      run_quietly(steps_done: '6')

      expect(printed).to include('Step 7 of 14')
    end

    it 'declares as many numbered steps as it runs' do
      run_quietly(steps_done: 0)

      expect(printed.scan(/Step \d+ of #{FreshInstallPostClone::POST_CLONE_STEPS}\b/).length).to eq(FreshInstallPostClone::POST_CLONE_STEPS)
    end
  end

  describe 'the macOS defaults baseline' do
    it 'is not started in the background on a pre-configured machine' do
      expect(PreferencesRestore).not_to receive(:start_baseline_in_background)

      run_quietly
    end

    it 'is started in the background on a first install, right after install-dotfiles and before Homebrew' do
      allow(EnvVars).to receive(:first_install?).and_return(true)
      allow(InstallDotfiles).to receive(:run) { events << :install_dotfiles }
      allow(PreferencesRestore).to receive(:start_baseline_in_background) { events << :baseline_started }
      allow(HomebrewInstall).to receive(:run) { events << :homebrew }
      allow(PreferencesRestore).to receive(:run) { events << :preferences }

      run_quietly

      expect(events).to eq(%i[install_dotfiles baseline_started homebrew preferences])
    end

    it 'is joined and its bracket closed when the run is aborted before the preferences step' do
      allow(HomebrewInstall).to receive(:run).and_return(false)
      expect(PreferencesRestore).to receive(:finish_pending)

      expect(run_quietly).to be false
    end

    it 'does not let a failure of that clean-up hide the outcome' do
      allow(PreferencesRestore).to receive(:finish_pending).and_raise('stuck')

      result = nil
      expect { result = run_quietly }.to output(/could not wrap up the background work: stuck/).to_stderr
      expect(result).to be true
    end
  end

  describe 'zsh steps' do
    it 'recompiles the core startup files in one zsh that has sourced .shellrc' do
      expect(CommandUtils).to receive(:run_interactive)
          .with({}, 'zsh', '-c', /\Asource \S*\.shellrc; recompile_zsh_script \S*\.zshenv; recompile_zsh_script \S*\.zshrc; recompile_zsh_script \S*\.zlogin; recompile_zsh_script \S*\.shellrc; recompile_zsh_script \S*\.aliases\z/).and_return(true)

      run_quietly
    end

    it 'loads the zsh configs with DEBUG set, after install-dotfiles, after Homebrew and after the clones' do
      expect(CommandUtils).to receive(:run_interactive).with({ 'DEBUG' => 'true' }, 'zsh', '-c', /load_zsh_configs\z/).exactly(3).times.and_return(true)

      run_quietly
    end

    it 'records a warning, and carries on, when the zsh configs cannot be loaded' do
      allow(CommandUtils).to receive(:run_interactive).with({ 'DEBUG' => 'true' }, 'zsh', '-c', /load_zsh_configs/).and_return(false)

      expect(run_quietly).to be true
      expect(Logging.step_warnings.join).to match(/Failed to load the zsh configs/)
    end

    it 'refreshes the zsh caches through delete_caches, and warns when that fails' do
      allow(CommandUtils).to receive(:run_interactive).with({}, 'zsh', '-c', /delete_caches/).and_return(false)

      expect(run_quietly).to be true
      expect(Logging.step_warnings.join).to match(/Failed to run 'delete_caches'/)
    end

    it 'rebuilds the completions cache and removes the old dump files' do
      cache = tmp.join('xdg_cache_home')
      cache.mkpath
      cache.join('zcompdump').write('x')
      cache.join('zcompdump.zwc').write('x')
      expect(CommandUtils).to receive(:run_silent).with('zsh', '-c', /compinit -C -d \S*zcompdump/).and_return(true)

      run_quietly

      expect(cache.children).to be_empty
    end
  end

  describe 'the .shellrc restore after install-dotfiles' do
    it 'does nothing on a pre-configured machine' do
      expect(git).not_to receive(:run_alias).with('diff', any_args)

      run_quietly
    end

    context 'on a first install' do
      before { allow(EnvVars).to receive(:first_install?).and_return(true) }

      it 'leaves the file alone when install-dotfiles did not change it' do
        expect(git).to receive(:run_alias).with('diff', '--quiet', '--', ShellrcCheck::REPO_SHELLRC_RELATIVE).and_return(['', '', ok_status])
        expect(git).not_to receive(:run_alias).with('checkout', any_args)

        run_quietly
      end

      it 'checks the committed version out, recompiles it and validates that it sources' do
        allow(git).to receive(:run_alias).with('diff', any_args).and_return(['', '', failed_status])
        expect(git).to receive(:run_alias).with('checkout', '--', ShellrcCheck::REPO_SHELLRC_RELATIVE).and_return(['', '', ok_status])
        expect(CommandUtils).to receive(:run_interactive).with({}, 'zsh', '-c', /recompile_zsh_script \S*\.shellrc\z/).at_least(:once).and_return(true)
        expect(CommandUtils).to receive(:run_interactive).with({ 'DEBUG' => 'true' }, 'zsh', '-c', /\Asource \S*\.shellrc\z/).and_return(true)

        expect(run_quietly).to be true
      end

      it 'records a warning when the restored file does not source' do
        allow(git).to receive(:run_alias).with('diff', any_args).and_return(['', '', failed_status])
        allow(CommandUtils).to receive(:run_interactive).with({ 'DEBUG' => 'true' }, 'zsh', '-c', /\Asource \S*\.shellrc\z/).and_return(false)

        run_quietly

        expect(Logging.step_warnings.join).to match(%r{restored ~/\.shellrc})
      end
    end
  end

  describe 'fatal failures' do
    it 'aborts, without running anything else, when the .shellrc check fails' do
      allow(ShellrcCheck).to receive(:matches_repo?).and_return(false)
      expect(InstallDotfiles).not_to receive(:run)

      expect(run_quietly).to be false
      expect(MacOS).to have_received(:notify).with(/Installation failed/, '❌ Error')
    end

    it 'aborts when install-dotfiles fails, recording why' do
      allow(InstallDotfiles).to receive(:run).and_return(false)
      expect(HomebrewInstall).not_to receive(:run)

      expect(run_quietly).to be false
      expect(Logging.step_errors.join).to match(/install-dotfiles encountered errors/)
    end

    it 'aborts when Homebrew cannot be installed, without trying the Brewfile' do
      allow(HomebrewInstall).to receive(:run).and_return(false)
      expect(BrewBundle).not_to receive(:run)
      expect(Keybase).not_to receive(:bootstrap_login)

      expect(run_quietly).to be false
    end

    it 'reports an unexpected exception as a failure instead of raising' do
      allow(PreferencesRestore).to receive(:run).and_raise('disk on fire')

      result = nil
      expect { result = run_quietly }.to output(/Installation failed with unhandled exception: disk on fire/).to_stderr
      expect(result).to be false
      expect(MacOS).to have_received(:notify).with(/disk on fire/, '❌ Error')
    end

    it 'prints no manual-step reminders after a failure' do
      allow(HomebrewInstall).to receive(:run).and_return(false)
      expect(Logging).not_to receive(:user_action)

      run_quietly
    end
  end

  describe 'non-fatal failures' do
    it 'carries on and still succeeds when the Brewfile, Keybase, preferences or default shell fail' do
      allow(BrewBundle).to receive(:run).and_return(false)
      allow(Keybase).to receive(:bootstrap_login).and_return(false)
      allow(PreferencesRestore).to receive(:run).and_return(false)
      allow(DefaultShell).to receive(:run).and_return(false)

      expect(run_quietly).to be true
      expect(DefaultShell).to have_received(:run)
    end

    it 'records a warning when the upstream remote cannot be added' do
      allow(AddUpstreamGitConfig).to receive(:run).and_return(false)

      expect(run_quietly).to be true
      expect(Logging.step_warnings.join).to match(/Failed to add upstream git config/)
    end

    it 'records an error when the reftable migration fails' do
      allow(git).to receive(:run_alias).with('migrate-reftable', stream: true).and_return(['', '', failed_status])

      expect(run_quietly).to be true
      expect(Logging.step_errors.join).to match(/git migrate-reftable.*failed/)
    end

    it 'records a warning when the tracked repos are not fully resurrected' do
      allow(ResurrectRepositories).to receive(:run).and_return(false)

      expect(run_quietly).to be true
      expect(Logging.step_warnings.join).to match(/Failed to fully resurrect tracked repos/)
    end
  end

  describe 'cron' do
    before { cron_backup.write("0 * * * * job\n") }

    it 'retires the backup once the schedule is reinstalled, and does not resume it' do
      expect(Cron).to receive(:retire_backup).with(cron_backup).and_call_original
      expect(Cron).not_to receive(:resume_cron)

      expect(run_quietly).to be true
      expect(cron_backup).not_to exist
    end

    it 'keeps the backup and records an error when recron fails, then restores the original schedule' do
      allow(Cron).to receive(:recron).and_return(false)
      expect(Cron).not_to receive(:retire_backup)
      expect(Cron).to receive(:resume_cron)

      expect(run_quietly).to be true
      expect(cron_backup).to exist
      expect(Logging.step_errors.join).to match(/recron failed/)
    end

    it 'records an error when recron raises' do
      allow(Cron).to receive(:recron).and_raise('crontab missing')
      expect(Cron).to receive(:resume_cron)

      expect(run_quietly).to be true
      expect(Logging.step_errors.join).to match(/Failed to set up cron jobs: crontab missing/)
    end

    it 'restores the original schedule when the run is aborted before the cron step' do
      allow(HomebrewInstall).to receive(:run).and_return(false)
      expect(Cron).to receive(:resume_cron)

      run_quietly
    end
  end

  describe 'the closing summary and notification' do
    it 'prints the summary at depth 1 (run by the shell script), with the duration, and notifies success' do
      with_env('_DOTFILES_SCRIPT_DEPTH' => '1') do
        expect(Logging).to receive(:print_script_summary).with(1_700_000_000, FreshInstallPostClone::FINISHED_MESSAGE)

        expect(run_quietly(start_time: '1700000000')).to be true
      end

      expect(MacOS).to have_received(:notify).with('Fresh install completed successfully.', '✅ Fresh Install Done')
    end

    it 'counts the Total column of the step lines from the start epoch the shell passed' do
      with_env('_DOTFILES_SCRIPT_DEPTH' => '1') do
        allow(Logging).to receive(:print_script_summary)

        run_quietly(start_time: '1700000000')
      end

      expect(Logging.state.script_start_time).to eq(1_700_000_000)
    end

    it 'runs its own banner and summary when started at depth 0' do
      expect(Logging).to receive(:run_script).with(FreshInstallPostClone::SCRIPT_NAME, FreshInstallPostClone::FINISHED_MESSAGE).and_yield

      expect(run_quietly).to be true
    end

    it 'lists every recorded issue in the notification' do
      allow(Keybase).to receive(:bootstrap_login) do
        Logging.record_warning('keybase trouble')
        false
      end
      allow(PreferencesRestore).to receive(:run) do
        Logging.record_error('prefs trouble')
        false
      end

      run_quietly

      expect(MacOS).to have_received(:notify).with(/Install done -- 1 error\(s\): .*prefs trouble \| 1 warning\(s\): .*keybase trouble/, '⚠️ Fresh Install')
    end

    it 'reminds about the shallow clones only on a first install' do
      expect(Logging).to receive(:user_action).with(/Review System Settings/).once
      expect(Logging).not_to receive(:user_action).with(/cloned shallow/)

      run_quietly
    end

    it 'says the history is being fetched in the background, not that the user must unshallow everything' do
      allow(EnvVars).to receive(:first_install?).and_return(true)
      allow(Logging).to receive(:user_action)

      run_quietly

      expect(Logging).to have_received(:user_action).with(/cloned shallow.*background job is fetching their complete history/)
    end

    it 'adds the shallow-clone reminder on a first install' do
      allow(EnvVars).to receive(:first_install?).and_return(true)
      expect(Logging).to receive(:user_action).with(/Review System Settings/)
      expect(Logging).to receive(:user_action).with(/cloned shallow/)

      run_quietly
    end
  end

  describe 'the background full Brewfile install' do
    it 'is reported on before the summary, and a successful run with nothing running says so plainly' do
      expect(BrewBundle).to receive(:report_full_install).and_return(:succeeded)

      run_quietly

      expect(MacOS).to have_received(:notify).with('Fresh install completed successfully.', '✅ Fresh Install Done')
    end

    it 'never claims everything is installed while it is still running' do
      allow(BrewBundle).to receive(:report_full_install).and_return(:running)
      allow(Logging).to receive(:user_action)

      run_quietly

      expect(MacOS).not_to have_received(:notify).with(/completed successfully/, anything)
      expect(MacOS).to have_received(:notify).with('Install done -- the full Brewfile install is still running in the background', 'Fresh Install')
      expect(Logging).to have_received(:user_action).with(/full Brewfile install is still running/)
    end

    it 'lists it together with the recorded issues' do
      allow(BrewBundle).to receive(:report_full_install).and_return(:running)
      allow(Keybase).to receive(:bootstrap_login) do
        Logging.record_warning('keybase trouble')
        false
      end

      run_quietly

      expect(MacOS).to have_received(:notify).with(/1 warning\(s\): .*keybase trouble \| the full Brewfile install is still running/, '⚠️ Fresh Install')
    end

    it 'shows a failure of it as a warning in the notification' do
      allow(BrewBundle).to receive(:report_full_install) do
        Logging.record_warning('background bundle failed')
        :failed
      end

      run_quietly

      expect(MacOS).to have_received(:notify).with(/1 warning\(s\): .*background bundle failed/, '⚠️ Fresh Install')
    end

    it 'is reported even when the run is aborted' do
      allow(HomebrewInstall).to receive(:run).and_return(false)
      expect(BrewBundle).to receive(:report_full_install)

      run_quietly
    end

    it 'notes that the first hourly run may overlap it when cron is installed while it runs' do
      allow(BrewBundle).to receive(:full_install_state).and_return(:running)

      expect(run_quietly).to be true
      expect(printed).to match(/first hourly software-updates run may overlap it/)
    end
  end

  describe 'the issues hand-off from the shell and from child processes' do
    let(:issues) { tmp.join('issues') }

    it 'includes the issues the shell recorded before the hand-off and those children recorded during it' do
      issues.write("warning\t[fresh-install-of-osx.sh][Xcode] softwareupdate failed\n")
      allow(PreferencesRestore).to receive(:run) do
        issues.open('a') { |file| file.puts("error\t[git-fo][rebase] bad ref") }
        true
      end

      with_env('_DOTFILES_ISSUES_FILE' => issues.to_s) { run_quietly }

      expect(MacOS).to have_received(:notify).with(/1 error\(s\): \[git-fo\]\[rebase\] bad ref \| 1 warning\(s\): \[fresh-install-of-osx.sh\]\[Xcode\] softwareupdate failed/, '⚠️ Fresh Install')
      expect(issues).not_to exist
    end

    it 'does not count its own issues twice' do
      allow(Keybase).to receive(:bootstrap_login) do
        Logging.record_warning('own warning')
        true
      end

      with_env('_DOTFILES_ISSUES_FILE' => issues.to_s) { run_quietly }

      expect(Logging.step_warnings.grep(/own warning/).length).to eq(1)
    end

    it 'merges the child issues even when the run is aborted' do
      allow(HomebrewInstall).to receive(:run) do
        issues.open('a') { |file| file.puts("warning\t[child][x] late") }
        false
      end

      with_env('_DOTFILES_ISSUES_FILE' => issues.to_s) { run_quietly }

      expect(Logging.step_warnings.join).to match(/late/)
    end
  end
end
