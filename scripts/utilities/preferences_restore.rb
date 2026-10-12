#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative '../capture-prefs'
require_relative 'command_utils'
require_relative 'env_vars'
require_relative 'logging'

# The 'Restore preferences' step of the machine setup: baselines the macOS defaults
# (osx-defaults.sh -s), then imports the backed-up application preferences
# (capture-prefs.rb -i), first refreshing that backup on a pre-configured machine so the
# import's git-timestamp check passes. fresh-install-of-osx.sh calls it through call-utility.rb
# once the dotfiles repository is cloned; Ruby callers can use it directly.
#
# capture-prefs runs in-process (CapturePrefs.run): it suspends the software-update schedule and
# stops the login-item apps for an import, and restores both itself in an 'ensure' right after each
# operation, so the export and the import each get an independent clean-up. osx-defaults.sh stays a
# subprocess, being a shell script.
module PreferencesRestore
  extend self

  # Public API method.
  #
  # A failing sub-step never stops the rest of the setup: it is recorded and the next one runs.
  #
  # @param first_install [Boolean] True on a vanilla macOS, where there is no backup to refresh.
  #   Defaults to FIRST_INSTALL from the environment.
  # @return [Boolean] false when any sub-step failed or osx-defaults.sh was missing; each is recorded.
  def run(first_install: EnvVars.first_install?)
    ok = false
    Logging.run_script('preferences_restore', 'Restoring preferences') do
      baselined = _baseline
      restored = _restore(first_install)
      ok = baselined && restored
    end
    ok
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @return [Boolean]
  def _baseline
    script = _script('osx-defaults.sh')
    unless script.file?
      Logging.record_error "osx-defaults.sh not found at '#{script.to_s.cyan}' -- baseline preferences manually and follow it up with a re-import of the backed-up preferences"
      return false
    end

    # A shell script: run through its own shebang, not the Ruby interpreter.
    unless CommandUtils.run_interactive(script.to_s, '-s')
      Logging.record_error "osx-defaults.sh exited non-zero -- baseline preferences manually: #{script.to_s.cyan}"
      return false
    end

    Logging.success 'Successfully baselined preferences'
    true
  end

  # @param first_install [Boolean]
  # @return [Boolean]
  def _restore(first_install)
    refreshed = first_install ? true : _refresh_backup

    unless _capture_prefs('import')
      Logging.record_error "Importing the preferences failed -- import them manually: #{'capture-prefs.rb -i'.cyan}"
      return false
    end

    Logging.success 'Successfully restored preferences from backup'
    refreshed
  end

  # Exports and commits the current preferences on a pre-configured machine, so the import that
  # follows is not rejected as older than what is on disk. The export auto-commits inside
  # CapturePrefs, so no separate commit is needed here.
  #
  # @return [Boolean] false when the refresh failed (the import still runs, from the existing backup)
  def _refresh_backup
    Logging.info 'Pre-configured machine detected -- refreshing preferences backup first'
    if _capture_prefs('export')
      Logging.success 'Successfully refreshed and committed preferences backup'
      return true
    end

    Logging.record_warning 'Failed to refresh backup -- will attempt import with existing backup'
    false
  end

  # Runs CapturePrefs in-process. An error it raises (Logging.error raises) is trapped and printed
  # here, because a failing preferences step must not stop the rest of the setup.
  #
  # @param operation [String] 'export' or 'import'
  # @return [Boolean]
  def _capture_prefs(operation)
    CapturePrefs.run(operation: operation)
  rescue StandardError => e
    Logging.warn "capture-prefs #{operation} failed: #{e.message}"
    false
  end

  # @param name [String]
  # @return [Pathname]
  def _script(name)
    EnvVars::DOTFILES_DIR.join('scripts', name)
  end

  private_class_method :_baseline, :_restore, :_refresh_backup, :_capture_prefs, :_script
end
