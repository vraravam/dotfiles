#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: <anywhere; advisable in the PATH>
#
# Idempotent macOS fresh-install and re-configuration script.
# Works on a vanilla macOS and on a pre-configured machine without errors.
#
# Usage: fresh-install-of-osx.rb
#
# TODO: Need to figure out scriptable commands for:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'tempfile'

require_relative 'add-upstream-git-config'
require_relative 'install-dotfiles'
require_relative 'resurrect-repositories'
require_relative 'utilities/command_utils'
require_relative 'utilities/core'
require_relative 'utilities/cron'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/git_workspace'
require_relative 'utilities/keybase'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'

include Logging

# ---------------------------------------------------------------------------
# Constants

RUBY_BIN = RbConfig.ruby.freeze

# ---------------------------------------------------------------------------
# Bootstrap helpers

# Sets DNS to 1.1.1.1 if on Jio ISP (GitHub may otherwise not resolve).
def _setup_jio_dns
  org = CommandUtils.query('curl', '-fsS', 'https://ipinfo.io/org')
  return unless org.downcase.include?('jio')

  info 'Setting DNS for Wi-Fi from Jio ISP'
  return if CommandUtils.run_silent('networksetup', '-setdnsservers', 'Wi-Fi', '1.1.1.2', '9.9.9.9')

  warn 'Failed to set DNS for Wi-Fi'
end

# Resolve GH_USERNAME without requiring it to be permanently stored anywhere. On the
# very first (vanilla OS) run there is nothing cloned yet to derive it from, so an
# explicitly exported GH_USERNAME (from the bootstrap one-liner) is required. On every
# subsequent run (pre-configured machine, re-running this script to pick up updates),
# DOTFILES_DIR already exists locally, so this derives the value from its 'origin'
# remote instead -- meaning adopters never need to remember to export GH_USERNAME
# again after the first successful run.
#
# @return [String] the resolved GitHub username
def _resolve_gh_username
  gh_username = ENV.fetch('GH_USERNAME', '')
  return gh_username unless gh_username.empty?

  dotfiles_dir = EnvVars::DOTFILES_DIR
  if GitProcessor.repo?(dotfiles_dir)
    remote_url = GitProcessor.new(dir: dotfiles_dir).remote_url.to_s
    gh_username = remote_url[%r{[:/]([^/]+)/dotfiles(\.git)?/?$}, 1].to_s
  end

  if gh_username.empty?
    warn "ERROR: GH_USERNAME is not set and could not be derived from '#{dotfiles_dir}'."
    warn "       Export it before running: export GH_USERNAME='your-github-username'"
    exit 1
  end

  ENV['GH_USERNAME'] = gh_username
  gh_username
end

# Resolves which branch of the dotfiles repo to bootstrap from/check out. Unlike
# GH_USERNAME (no safe default -- every fork's username differs, so an unresolvable
# value is a hard error), DOTFILES_BRANCH has a universally-correct default ('master')
# for everyone who hasn't deliberately switched to a different branch for testing, so
# this never errors out -- it only derives-or-falls-back.
#
# Only ever read before '${DOTFILES_DIR}' exists as a git repo (constructing the
# '.shellrc' download URL, and the initial clone of the dotfiles repo itself); on any
# later re-run, the already-cloned repo is used directly and this value is never
# consulted again. Safe to derive from the local repo's own current branch on such a
# re-run (e.g. after manually checking out a test branch there -- see Advanced.md
# section 5.6), rather than requiring it to be kept in sync anywhere else.
#
# @return [String] the resolved branch name
def _resolve_dotfiles_branch
  dotfiles_branch = ENV.fetch('DOTFILES_BRANCH', '')
  return dotfiles_branch unless dotfiles_branch.empty?

  dotfiles_dir = EnvVars::DOTFILES_DIR
  dotfiles_branch = GitProcessor.new(dir: dotfiles_dir).current_branch.to_s if GitProcessor.repo?(dotfiles_dir)
  dotfiles_branch = 'master' if dotfiles_branch.empty?

  ENV['DOTFILES_BRANCH'] = dotfiles_branch
  dotfiles_branch
end

# Downloads .shellrc from GitHub when needed and sources it.
def _download_and_source_shellrc(gh_username, dotfiles_branch, curl_opts, cache_bust_headers)
  puts "==> Ensuring '~/.shellrc' is current"

  shellrc_path = EnvVars::HOME.join('.shellrc')
  shellrc_path_str = shellrc_path.to_s
  repo_shellrc = EnvVars::DOTFILES_DIR.join('files/--HOME--/.shellrc')

  # Determine if download is needed
  reason = nil
  if EnvVars.first_install?
    # Vanilla OS: always download
    reason = 'first install'
  elsif !shellrc_path.file?
    # Pre-configured but .shellrc missing (deleted or corrupted symlink)
    reason = '.shellrc missing'
  elsif !EnvVars::DOTFILES_DIR.directory?
    # Pre-configured but DOTFILES_DIR missing (partial fresh-install or deleted repo)
    # Cannot verify staleness without repo - re-download to ensure current version
    reason = 'dotfiles repo missing'
  elsif repo_shellrc.file? && repo_shellrc.mtime > shellrc_path.mtime
    # Pre-configured: repo file is newer than existing .shellrc (git pull updated repo)
    # Downloads from GitHub to ensure fresh copy (not using potentially stale local repo file)
    reason = 'local repo file is newer'
  end

  if reason
    puts "==> Downloading .shellrc from GitHub (#{reason})"
    # Cache-busting: append timestamp to URL and add no-cache headers to ensure we bypass
    # GitHub's CDN cache and intermediate proxies to get the latest version.
    timestamp = Time.now.to_i
    url = "https://raw.githubusercontent.com/#{gh_username}/dotfiles/refs/heads/#{dotfiles_branch}/files/--HOME--/.shellrc?#{timestamp}"

    cmd = ['curl'] + cache_bust_headers + curl_opts + ['-fsSL', url, '-o', shellrc_path_str]
    Logging.error 'Failed to download .shellrc' unless system(*cmd)
  end

  # Universal validation (both first-install and pre-configured)
  # Validate: check that file is non-empty and contains the re-source guard
  # function (basic smoke test for successful download vs truncated/corrupted response).
  # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
  unless shellrc_path.file? && shellrc_path.size.positive? && shellrc_path.read(encoding: 'UTF-8').include?('is_shellrc_sourced')
    warn 'ERROR: .shellrc appears corrupted or empty'
    exit 1
  end

  puts "==> Verified '#{shellrc_path_str}'"

  # Running .shellrc in a zsh subprocess doesn't make its functions/env vars available
  # to this Ruby process (the subprocess's environment is discarded on exit) -- the
  # rest of this script uses the Ruby utility modules instead. This run validates the
  # file parses correctly and warms any on-disk caches .shellrc creates (e.g. Homebrew
  # shellenv, starship init), which benefits the next real interactive shell.
  system({ 'DEBUG' => 'true' }, 'zsh', '-c', "source #{shellrc_path_str.shellescape}")
  Logging.success "Successfully sourced '#{shellrc_path_str.cyan}'"
end

# Validates that curl-downloaded .shellrc matches the repo version.
def _validate_shellrc_matches_repo
  return unless EnvVars.first_install?
  return unless EnvVars::DOTFILES_DIR.directory?

  shellrc_home = EnvVars::HOME.join('.shellrc')
  shellrc_repo = EnvVars::DOTFILES_DIR.join('files/--HOME--/.shellrc')

  return unless shellrc_home.file? && shellrc_repo.file?

  # Use /usr/bin/diff to compare files (exit 0 = identical, exit 1 = differ)
  _stdout, _stderr, status = Open3.capture3('/usr/bin/diff', '-q', shellrc_home.to_s, shellrc_repo.to_s)

  return if status.success? # Files match, validation passed

  # Files differ -- GitHub cache is stale
  warn 'ERROR: [FIRST_INSTALL] The curl-downloaded ~/.shellrc differs from the repo version.'
  warn 'This indicates GitHub\'s raw.githubusercontent.com cache is stale.'
  warn ''
  warn 'Diff output:'
  diff_output, = Open3.capture3('/usr/bin/diff', '-u', shellrc_home.to_s, shellrc_repo.to_s)
  warn diff_output.lines.first(50).join
  warn ''
  warn 'Wait 5-10 minutes for the cache to refresh, then re-run this script.'
  warn 'Alternatively, manually copy the repo version:'
  warn "  cp '#{shellrc_repo}' '#{shellrc_home}'"
  warn "  source '#{shellrc_home}'"
  warn "  #{$PROGRAM_NAME} #{ARGV.join(' ')}"
  exit 1
end

# Force-checks and recompiles-if-needed the core zsh startup files right now,
# as their own explicit step -- deliberately not deferred to whatever recompiles
# them incidentally later (there is no Ruby equivalent of the shell version's
# load_zsh_configs in this script). Later steps in this script (e.g.
# resurrect_tracked_repos) can run for tens of minutes; establishing correct
# bytecode this early -- immediately after install-dotfiles.rb (re-)creates
# these symlinks -- means it does not depend on reaching (or the timing of)
# any later step. recompile_zsh_script (shell function, no Ruby port; called
# via a zsh subprocess since .shellrc must be sourced first to define it)
# no-ops when the .zwc is already current, so this costs a handful of stat
# calls when nothing changed. This does NOT remove the need for the
# unconditional delete_caches call near the end of this script: that call
# exists because a stale .zwc left over from an earlier partial fresh-install
# attempt can have a mtime that defeats this same is_file_older_than check
# entirely (see the comment on the 'Refresh zsh bytecode caches' step below).
def _recompile_zsh_startup_files
  shellrc_path = EnvVars::HOME.join('.shellrc')
  core_files = [
    EnvVars::ZDOTDIR.join('.zshenv'),
    EnvVars::ZDOTDIR.join('.zshrc'),
    EnvVars::ZDOTDIR.join('.zlogin'),
    shellrc_path,
    EnvVars::ZDOTDIR.join('.aliases'),
  ]
  recompile_cmds = core_files.map { |f| "recompile_zsh_script #{f.to_s.shellescape}" }.join('; ')
  system('zsh', '-c', "source #{shellrc_path.to_s.shellescape}; #{recompile_cmds}")
end

# Restores .shellrc from git after install-dotfiles.rb moves the downloaded version.
# :reek:FeatureEnvy -- Multiple sequential git operations on the same repo (intentional)
def _restore_shellrc_after_install_dotfiles
  return unless EnvVars.first_install?

  git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)
  shellrc_relative = 'files/--HOME--/.shellrc'

  # Check if install-dotfiles.rb modified .shellrc in the repo
  _stdout, _stderr, status = git.run_alias('diff', '--quiet', '--', shellrc_relative)
  return if status.success? # No changes, nothing to restore

  # Restore committed version
  git.run_alias('checkout', '--', shellrc_relative)

  shellrc_path = EnvVars::HOME.join('.shellrc')

  # Recompile again: this checkout can change .shellrc's content/mtime after
  # _recompile_zsh_startup_files already ran, making that earlier pass stale
  # relative to this specific restore. Plain 'source' (unlike the shell
  # version's load_file_if_exists) does not check .zwc staleness itself, so
  # without this the re-source below could silently load bytecode compiled
  # before this checkout, defeating the restore above entirely.
  system('zsh', '-c', "source #{shellrc_path.to_s.shellescape}; recompile_zsh_script #{shellrc_path.to_s.shellescape}")

  # Re-run the restored version through zsh to validate it parses correctly
  # (same rationale as _download_and_source_shellrc above).
  system({ 'DEBUG' => 'true' }, 'zsh', '-c', "source #{shellrc_path.to_s.shellescape}")
end

# Clones the dotfiles repo (if not already present) and configures push-over-SSH,
# PATH, and the upstream remote.
# :reek:NilCheck -- config_value returns nil when the key is unset (standard git config idiom)
def _clone_dot_files_repo(gh_username, dotfiles_branch)
  dotfiles_dir = EnvVars::DOTFILES_DIR
  Logging.with_step('Clone dotfiles repo', "Installing dotfiles into '#{dotfiles_dir.to_s.cyan}'") do
    if GitProcessor.repo?(dotfiles_dir)
      info "Skipping cloning the dotfiles repo since '#{dotfiles_dir.to_s.cyan}' already exists and is a git repo"
    else
      # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo.
      zshrc = EnvVars::ZDOTDIR.join('.zshrc')
      zshrc.rmtree if zshrc.exist?

      # Note: Cloning with https since the ssh keys will not be present at this time.
      url = "https://github.com/#{gh_username}/dotfiles"
      if GitProcessor.clone_repo_into(url, dotfiles_dir, branch: dotfiles_branch)
        # Use the https protocol for pull, but use ssh/git for push (only configure if not already set).
        git = GitProcessor.new(dir: dotfiles_dir)
        push_key = 'url.ssh://git@github.com/.pushInsteadOf'
        git.config_set(push_key, 'https://github.com/') if git.config_value(push_key).nil?

        PathUtils.prepend_to_path(dotfiles_dir.join('scripts'))
      else
        error 'Failed to clone dotfiles repo'
      end
    end

    # Setup the dotfiles repo's upstream remote (points at the repo this fork was
    # derived from). This runs regardless of whether the repo was just cloned or
    # already existed. AddUpstreamGitConfig.run is idempotent and no-ops cleanly both
    # when 'upstream' already exists and when origin's own owner already matches
    # UPSTREAM_GH_USERNAME (e.g. running this on the upstream owner's own machine) --
    # so no GH_USERNAME comparison is needed here.
    upstream_ok = AddUpstreamGitConfig.run(dir: dotfiles_dir, upstream_owner: EnvVars::UPSTREAM_GH_USERNAME)
    record_warning 'Failed to add upstream git config for dotfiles repo' unless upstream_ok
  end
end

# Installs Homebrew, taps repos, and runs brew bundle.
def _install_homebrew(curl_opts)
  homebrew_prefix = EnvVars::HOMEBREW_PREFIX
  homebrew_prefix_str = homebrew_prefix.to_s
  Logging.with_step('Install Homebrew', "Installing Homebrew into '#{homebrew_prefix_str.cyan}'") do
    error "'HOMEBREW_PREFIX' env var is not set; something is wrong" if nil_or_empty?(homebrew_prefix_str)

    brew_bin = homebrew_prefix.join('bin', 'brew')

    if brew_bin.executable?
      info 'Homebrew already installed -- skipping.'
    else
      # Prepare directories for homebrew installation.
      system('sudo', 'mkdir', '-p',
             homebrew_prefix.join('tmp').to_s, homebrew_prefix.join('repository').to_s,
             homebrew_prefix.join('plugins').to_s, homebrew_prefix.join('bin').to_s)
      system('sudo', 'chown', '-fR', "#{EnvVars::USER}:admin", homebrew_prefix_str)
      begin
        FileUtils.chmod('u+w', homebrew_prefix_str)
      rescue StandardError
        nil
      end

      install_script = Tempfile.new(['brew-install', '.sh'])
      begin
        # Build cache-busting headers if CACHE_BUST_HEADERS env var is set
        cache_bust_headers = []
        if EnvVars.cache_bust_headers?
          cache_bust_headers = [
            '-H', 'Cache-Control: no-cache, no-store, must-revalidate',
            '-H', 'Pragma: no-cache',
            '-H', 'Expires: 0'
          ]
        end

        # Append timestamp query param to bust GitHub's CDN cache
        timestamp = Time.now.to_i
        install_url = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh?#{timestamp}"

        cmd = ['curl'] + cache_bust_headers + curl_opts + ['-fsSL', install_url, '-o', install_script.path]
        Logging.error 'Failed to download Homebrew installation script' unless system(*cmd)

        Logging.error 'Homebrew installation failed' unless system({ 'NONINTERACTIVE' => '1' }, 'bash', install_script.path)
      ensure
        begin
          install_script.unlink
        rescue StandardError
          nil
        end
      end

      success 'Successfully installed Homebrew'
    end

    # Ensure homebrew env vars are set for this process session.
    MacOS.load_brew_shellenv(brew_bin)

    # Trust custom taps and install formulae/casks from Brewfile.
    # On first install: base section only + background full install.
    # On pre-configured: full Brewfile synchronously.
    MacOS.install_homebrew_bundle(brew_bin)
  end
end

# Configures remote_url as a git remote on target_dir -- 'origin' if no other remote
# exists yet, 'origin2' if 'origin' is already something else (e.g. the other backup
# mechanism, or a remote configured in a previous run). Idempotent: no-ops if
# remote_url is already configured as either 'origin' or 'origin2'. Shared by both
# backup mechanisms (Keybase and the gpg+git-bundle encrypted backup) so they can
# coexist on the same repo, each pushed/pulled explicitly and independently -- see
# KeybaseMigration.md. Never fans a URL into an existing remote's push URLs -- each
# mechanism always gets its own separately-named remote.
def _configure_backup_remote(target_dir, remote_url)
  git = GitProcessor.new(dir: target_dir)
  return if git.remote_url(name: 'origin') == remote_url
  return if git.remote_url(name: 'origin2') == remote_url

  if nil_or_empty?(git.remote_url(name: 'origin'))
    git.add_remote('origin', remote_url)
    success "Added 'origin' -> '#{remote_url.cyan}' for '#{target_dir.to_s.cyan}'"
  elsif nil_or_empty?(git.remote_url(name: 'origin2'))
    git.add_remote('origin2', remote_url)
    success "Added 'origin2' -> '#{remote_url.cyan}' for '#{target_dir.to_s.cyan}' (separate from 'origin' -- push/pull each explicitly)"
  else
    record_warning "Both 'origin' and 'origin2' are already configured on '#{target_dir.to_s.cyan}' with different URLs -- not adding '#{remote_url.cyan}'. Add it manually under a different remote name if you want it too."
  end
end

# Clones dir from whichever backup mechanism(s) are enabled (a KEYBASE_*_REPO_NAME
# and/or an ENCRYPTED_*_REPO_URL env var -- see KeybaseMigration.md for how they
# coexist). Keybase is tried first (original mechanism, historical precedence); the
# gpg+git-bundle encrypted backup (external 'git-remote-gpg-encrypt' tool, installed
# via the 'vraravam/tap' Homebrew tap) is the fallback, or the only option if Keybase
# isn't enabled/available. Whichever succeeds performs the actual clone; if the other
# mechanism is also enabled, it is configured as an additional remote by the caller
# (via _configure_backup_remote) rather than cloned from again. Shared by
# _clone_home_repo and _clone_profiles_repo -- callers handle their own small
# differences (pull-on-exists behavior, extra git config, one-time post-clone setup)
# since those aren't part of the backup-mechanism selection logic itself.
#
# @param dir [Pathname] Target directory for the clone.
# @param keybase_repo_name [String] Value of the repo's KEYBASE_*_REPO_NAME env var
#   (may be empty if that mechanism isn't enabled for this repo).
# @param encrypted_repo_url [String] Value of the repo's ENCRYPTED_*_REPO_URL env var
#   (may be empty if that mechanism isn't enabled for this repo).
# @param label [String] Human-readable repo label for log messages (e.g. 'home repo').
# @param keybase_env_var [String] Name of the KEYBASE_*_REPO_NAME env var, for the
#   "neither env var set" skip message.
# @param encrypted_env_var [String] Name of the ENCRYPTED_*_REPO_URL env var, for the
#   "neither env var set" skip message.
# @return [String] 'keybase' or 'encrypted-backup' if a clone succeeded via that
#   mechanism; '' (empty string) if both enabled mechanisms failed, or if neither
#   mechanism is enabled for this repo (not itself a failure -- see record_error vs
#   info distinction inside).
def _clone_via_backup_mechanisms(dir:, keybase_repo_name:, encrypted_repo_url:, label:, keybase_env_var:, encrypted_env_var:)
  cloned_via = ''

  unless nil_or_empty?(keybase_repo_name)
    if PathUtils.command_exists?('keybase') && Keybase.ensure_logged_in &&
       GitProcessor.clone_repo_into(Keybase.build_repo_url(keybase_repo_name), dir)
      cloned_via = 'keybase'
      success "Successfully cloned #{label} from Keybase"
    else
      record_warning "Failed to clone #{label} from Keybase -- will try encrypted-backup next if enabled"
    end
  end

  if nil_or_empty?(cloned_via) && !nil_or_empty?(encrypted_repo_url)
    # clone_repo_into's 'gpg-encrypt::' special-case already strips the bogus 'origin'
    # that 'git-gpg-encrypt-restore' leaves behind internally, so -- same as the
    # Keybase branch above -- there is no remote to configure here; whichever remote
    # name (origin/origin2) this backup ends up under is decided uniformly by the
    # caller's '_configure_backup_remote' calls, regardless of which mechanism
    # actually performed the clone.
    if PathUtils.command_exists?('git-gpg-encrypt-restore') && GitProcessor.clone_repo_into("gpg-encrypt::#{encrypted_repo_url}", dir)
      cloned_via = 'encrypted-backup'
      success "Successfully cloned #{label} from encrypted backup"
    else
      record_error "Failed to clone #{label} from encrypted backup"
    end
  end

  if nil_or_empty?(cloned_via)
    if !nil_or_empty?(keybase_repo_name) || !nil_or_empty?(encrypted_repo_url)
      record_error "Failed to clone #{label} from any enabled backup mechanism"
    else
      info "Skipping cloning of #{label} since neither '#{keybase_env_var}' nor '#{encrypted_env_var}' env var has been set"
    end
  end

  cloned_via
end

# Clones the home repo (private configs) from whichever backup mechanism(s) are
# enabled (KEYBASE_HOME_REPO_NAME and/or ENCRYPTED_HOME_REPO_URL -- see
# _clone_via_backup_mechanisms for the shared clone-selection logic).
def _clone_home_repo
  keybase_repo_name = ENV.fetch('KEYBASE_HOME_REPO_NAME', '')
  encrypted_repo_url = ENV.fetch('ENCRYPTED_HOME_REPO_URL', '')
  home = EnvVars::HOME
  already_exists = GitProcessor.repo?(home)

  Logging.with_step('Clone home repo', already_exists ? 'Updating home repo' : 'Cloning home repo') do
    if already_exists
      # Pre-configured machine: pull latest changes to get fresh backup files.
      # GitProcessor#pull delegates to the 'pull-safe' git alias (with-retry hang
      # protection + a clean-working-tree guard), consistent with every other
      # repo-sync path in this script.
      info 'Home repo already exists -- pulling latest changes'
      git = GitProcessor.new(dir: home)
      git.ensure_branch_tracking
      _stdout, _stderr, status = git.pull
      if status.success?
        success 'Successfully updated home repo'
      else
        record_warning 'Failed to pull home repo -- continuing with existing backup files'
      end
    else
      cloned_via = _clone_via_backup_mechanisms(
        dir: home, keybase_repo_name: keybase_repo_name, encrypted_repo_url: encrypted_repo_url,
        label: 'home repo', keybase_env_var: 'KEYBASE_HOME_REPO_NAME', encrypted_env_var: 'ENCRYPTED_HOME_REPO_URL'
      )

      unless nil_or_empty?(cloned_via)
        PathUtils.set_ssh_folder_permissions
        PathUtils.set_gnupg_folder_permissions

        etc_hosts_src = EnvVars::PERSONAL_CONFIGS_DIR.join('etc.hosts')
        system('sudo', 'cp', etc_hosts_src.to_s, '/etc/hosts') if etc_hosts_src.file?
      end
    end

    # Ensure remotes for both enabled mechanisms are present, whether the repo was just
    # cloned above or already existed -- idempotent, safe to call every run.
    if GitProcessor.repo?(home)
      _configure_backup_remote(home, Keybase.build_repo_url(keybase_repo_name)) unless nil_or_empty?(keybase_repo_name)
      _configure_backup_remote(home, "gpg-encrypt::#{encrypted_repo_url}") unless nil_or_empty?(encrypted_repo_url)
    end
  end
end

# Clones the browser-profiles repo (personal browser profile data) from whichever
# backup mechanism(s) are enabled -- see _clone_via_backup_mechanisms for the shared
# clone-selection logic.
def _clone_profiles_repo
  keybase_repo_name = ENV.fetch('KEYBASE_PROFILES_REPO_NAME', '')
  encrypted_repo_url = ENV.fetch('ENCRYPTED_PROFILES_REPO_URL', '')
  profiles_dir = EnvVars::PERSONAL_PROFILES_DIR

  Logging.with_step('Clone profiles repo') do
    if nil_or_empty?(profiles_dir.to_s)
      info "Skipping cloning of profiles repo since 'PERSONAL_PROFILES_DIR' env var hasn't been set"
    elsif GitProcessor.repo?(profiles_dir)
      section_header('Profiles repo already exists -- skipping clone')
      # This repo is periodically force-squashed by recreate-repository.rb, so it is not
      # routinely pulled here the way the home repo is above -- see the
      # pull.allowResetOnDivergedHistory config flag set below, which lets the 'pull'
      # autoload function handle that safely if/when the user pulls it manually.
      GitProcessor.new(dir: profiles_dir).ensure_branch_tracking
    else
      section_header('Cloning profiles repo')
      _clone_via_backup_mechanisms(
        dir: profiles_dir, keybase_repo_name: keybase_repo_name, encrypted_repo_url: encrypted_repo_url,
        label: 'browser-profiles repo', keybase_env_var: 'KEYBASE_PROFILES_REPO_NAME', encrypted_env_var: 'ENCRYPTED_PROFILES_REPO_URL'
      )
    end

    next unless GitProcessor.repo?(profiles_dir)

    git = GitProcessor.new(dir: profiles_dir)
    _configure_backup_remote(profiles_dir, Keybase.build_repo_url(keybase_repo_name)) unless nil_or_empty?(keybase_repo_name)
    _configure_backup_remote(profiles_dir, "gpg-encrypt::#{encrypted_repo_url}") unless nil_or_empty?(encrypted_repo_url)

    # This repo is periodically force-squashed by recreate-repository.rb, so 'pull'
    # (files/--XDG_CONFIG_HOME--/zsh/pull) needs to hard-reset instead of rebase when
    # local and remote history have diverged with no common ancestor -- see
    # KeybaseMigration.md. Opt-in via this per-repo config flag (idempotent, safe to
    # set on every run). Applies regardless of which backup mechanism(s) are
    # configured -- the squashing itself is what causes the divergence, not the remote.
    git.config_set('pull.allowResetOnDivergedHistory', 'true')
  end
end

# Refreshes the preferences backup (export + commit) on a pre-configured machine
# before importing, so the git-timestamp check in capture-prefs.rb -i passes.
def _refresh_preferences_backup(capture_prefs)
  info 'Pre-configured machine detected -- refreshing preferences backup first'
  # Must use subprocess instead of CapturePrefs.run(operation: 'export'):
  # capture-prefs.rb has at_exit hooks that must fire immediately after
  # the export completes (resume softwareupdate schedule), not at the end
  # of fresh-install. Subprocess isolation ensures independent lifecycle.
  #
  # Export auto-commits inside capture-prefs.rb (uses smart_commit) -- no separate
  # commit needed here.
  if system(RUBY_BIN, capture_prefs.to_s, '-e')
    success 'Successfully refreshed and committed preferences backup'
  else
    record_warning 'Failed to refresh backup -- will attempt import with existing backup'
  end
end

# Sets Homebrew's zsh as the default login shell.
# macOS ships with /bin/zsh but Homebrew's zsh is newer and managed independently.
# chsh requires the target shell to be listed in /etc/shells -- adds it if absent.
# Without this, iTerm2's "Login shell" setting stays on /bin/zsh even when
# /opt/homebrew/bin/zsh is on PATH, and $SHELL stays /bin/zsh after a fresh install.
def _set_default_shell
  Logging.with_step('Set default shell', 'Setting default shell to Homebrew zsh') do
    brew_zsh = EnvVars::HOMEBREW_PREFIX.join('bin', 'zsh')
    unless brew_zsh.executable?
      record_error("Homebrew zsh not found at '#{brew_zsh.to_s.cyan}' -- skipping default shell change.")
      return
    end

    brew_zsh_str = brew_zsh.to_s
    brew_zsh_cyan = brew_zsh_str.cyan

    # /etc/shells must list the shell before chsh will accept it. Always validated,
    # regardless of whether chsh itself will be needed below (idempotent self-healing --
    # e.g. a macOS update can wipe /etc/shells while dscl's UserShell record still points
    # at Homebrew zsh, so this must not be skipped just because chsh isn't needed).
    # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
    etc_shells_path = Core::ROOT.join('etc', 'shells').expand_path
    etc_shells_path_str = etc_shells_path.to_s
    etc_shells = Core.read_lines_utf8(etc_shells_path).map(&:chomp)
    if etc_shells.include?(brew_zsh_str)
      info "'#{brew_zsh_cyan}' already in '#{etc_shells_path_str.cyan}' -- skipping."
    else
      info "Adding '#{brew_zsh_cyan}' to '#{etc_shells_path_str.cyan}'"
      # Use Open3.popen3 to safely write to stdin and discard stdout
      Open3.popen3('sudo', 'tee', '-a', etc_shells_path_str) do |stdin, stdout, _stderr, wait_thr|
        stdin.puts(brew_zsh_str)
        stdin.close
        stdout.read # Discard stdout (tee echoes to stdout + file)
        wait_thr.value
      end
    end

    # Check the user's configured default shell (not the current $SHELL env var).
    # $SHELL reflects the current terminal session; dscl shows what chsh configured.
    configured_shell = CommandUtils.query('dscl', '.', '-read', EnvVars::HOME.to_s, 'UserShell')
    configured_shell = configured_shell.split(':').last&.strip || ''

    if configured_shell == brew_zsh_str
      info "Default shell is already configured as '#{brew_zsh_cyan}' -- skipping."
      return
    end

    if CommandUtils.run_interactive('chsh', '-s', brew_zsh_str)
      success "Default shell changed to '#{brew_zsh_cyan}'."
    else
      record_warning "Failed to change default shell to '#{brew_zsh_cyan}'. You may need to run 'chsh -s #{brew_zsh_str}' manually after installation completes."
    end
  end
end

# ---------------------------------------------------------------------------
# Main

# Set the cron backup path so cron_backup_file in cron.rb can read it via ENV.
ENV['_DOTFILES_CRON_BACKUP_FILE'] = EnvVars.cron_backup_file.to_s

# at_exit hooks run in LIFO order, but we use a single consolidated block to
# ensure correct execution order: print summary, then notification (matching shell
# EXIT trap + cleanup ordering). Cron suspend/resume is handled by with_cron_suspended
# wrapper below. Sudo is kept alive via MacOS.keep_sudo_alive below (a background
# thread with its own internal duplicate-launch guard) -- there is nothing to tear
# down for that at exit, unlike osx-defaults.sh/capture-prefs.rb's use of
# suspend_softwareupdate_schedule/resume_softwareupdate_schedule, which this script
# does not use (this script never disables the software-update schedule -- see
# MacOS.keep_sudo_alive's own doc for why it's the right primitive here instead).
start_time = nil

at_exit do
  # Print summary (if start_time was set)
  print_script_summary(start_time) if start_time

  # Notification runs last -- after print_script_summary has printed the
  # collected issues so the user sees them in the terminal before the popup.
  errors = Logging.step_errors
  warnings = Logging.step_warnings
  parts = []
  parts << "#{errors.length} error(s): #{errors.join('; ')}" unless nil_or_empty?(errors)
  parts << "#{warnings.length} warning(s): #{warnings.join('; ')}" unless nil_or_empty?(warnings)

  if nil_or_empty?(parts)
    MacOS.notify('Fresh install completed successfully.', '✅ Fresh Install Done')
  else
    MacOS.notify("Install done -- #{parts.join(' | ')}", '⚠️ Fresh Install')
  end
end

# Wrap entire execution in with_cron_suspended to ensure cron is suspended
# before any work begins and automatically resumed on exit (clean or error).
Cron.with_cron_suspended do
  increment_script_depth
  start_time = print_script_start

  # EnvVars.first_install?: on a vanilla OS ${XDG_CONFIG_HOME}/git/config is not yet symlinked,
  # so core.sshCommand is absent. Export GIT_SSH_COMMAND for this session to ensure
  # consistent SSH options for all git operations. Keepalive prevents timeout on slow networks.
  # Unset after install-dotfiles.rb symlinks ${XDG_CONFIG_HOME}/git/config into place.
  ENV['GIT_SSH_COMMAND'] = 'ssh -o ConnectTimeout=20 -o Compression=no -o ServerAliveInterval=10 -o ServerAliveCountMax=3' if EnvVars.first_install?

  # ~/.curlrc is not yet symlinked on a vanilla OS, so its defaults are absent.
  # Build resilient curl flags explicitly for all bootstrap curl calls.
  # --retry-all-errors is intentionally omitted -- it causes the terminal to close.
  curl_opts = if EnvVars.first_install? || !EnvVars::HOME.join('.curlrc').file?
                %w[--retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused]
              else
                []
              end

  # Build cache-busting headers if CACHE_BUST_HEADERS env var is set
  cache_bust_headers = []
  if EnvVars.cache_bust_headers?
    cache_bust_headers = [
      '-H', 'Cache-Control: no-cache, no-store, must-revalidate',
      '-H', 'Pragma: no-cache',
      '-H', 'Expires: 0'
    ]
  end

  # ZDOTDIR must be set before any zsh is invoked downstream.
  ENV['ZDOTDIR'] ||= EnvVars::ZDOTDIR.to_s

  _setup_jio_dns

  gh_username = _resolve_gh_username
  dotfiles_branch = _resolve_dotfiles_branch

  # Download and source .shellrc before any other operations (provides utility functions).
  _download_and_source_shellrc(gh_username, dotfiles_branch, curl_opts, cache_bust_headers)

  # Printed as early as possible (right after '.shellrc' is sourced, so ENCRYPTED_*_REPO_URL
  # env vars are populated) rather than at the much-later cloning step -- this manual escape
  # hatch is only needed if the external 'git-remote-gpg-encrypt' tool's interactive Keychain
  # prompt fails or can't run (e.g. no TTY), and by the time the cloning step is reached
  # (after xcode tools/homebrew/etc.) it is too late for the user to act on this in parallel
  # with the rest of the install. Gated on the encrypted-backup env vars actually being set --
  # no point reminding someone who has disabled this mechanism.
  if !nil_or_empty?(ENV.fetch('ENCRYPTED_HOME_REPO_URL', '')) || !nil_or_empty?(ENV.fetch('ENCRYPTED_PROFILES_REPO_URL', ''))
    Logging.user_action "The 'home'/'browser-profiles' repo clone steps later in this script read their encrypted-backup passphrase from the macOS Keychain -- you won't normally be prompted."
    Logging.user_action 'If that fails, run this in another terminal now (no need to wait): ' \
                        "security add-generic-password -A -a \"#{EnvVars::USER}\" -s 'git-remote-gpg-encrypt' -w"
  end

  # Prompt for sudo once here, then keep it alive via a background thread for the
  # rest of the script -- mirrors keep_sudo_alive in .shellrc. Unlike osx-defaults.sh/
  # capture-prefs.rb, this script does not disable the software-update schedule.
  system('sudo', '-v')
  MacOS.keep_sudo_alive

  MacOS.approve_fingerprint_sudo

  MacOS.ensure_filevault_is_on

  MacOS.install_xcode_command_line_tools

  PathUtils.set_ssh_folder_permissions
  PathUtils.set_gnupg_folder_permissions

  # DOTFILES_DIR is created by clone_repo_into's mkpath call. ANTIDOTE_HOME and other
  # tool-specific subdirectories (e.g. XDG_CONFIG_HOME/pg, XDG_STATE_HOME/vim/undo) are
  # created automatically by their respective tools, or by install-dotfiles.rb when it
  # creates symlinks to those locations.
  Logging.with_step('Create directories', 'Creating XDG base directories') do
    PathUtils.ensure_directories_exist([EnvVars::XDG_CACHE_HOME, EnvVars::XDG_CONFIG_HOME])
  end

  _clone_dot_files_repo(gh_username, dotfiles_branch)

  # On FIRST_INSTALL: validate that curl-downloaded .shellrc matches the repo version.
  # If they differ, GitHub's CDN cache is stale -- abort with instructions.
  _validate_shellrc_matches_repo

  # Ensure dotfiles/scripts is on PATH regardless of whether the repo was just
  # cloned or was already present.
  PathUtils.prepend_to_path(EnvVars::DOTFILES_DIR.join('scripts'))

  Logging.with_step('install-dotfiles', 'Running install-dotfiles') do
    record_error 'install-dotfiles encountered errors' unless InstallDotfiles.run
  end

  _recompile_zsh_startup_files

  # On FIRST_INSTALL: install-dotfiles.rb moves curl-downloaded .shellrc into the repo,
  # overwriting the committed version. Restore it so the symlink points to correct content.
  _restore_shellrc_after_install_dotfiles

  # ${XDG_CONFIG_HOME}/git/config is now symlinked -- core.sshCommand is in effect.
  # Unset GIT_SSH_COMMAND so it no longer overrides core.sshCommand.
  ENV.delete('GIT_SSH_COMMAND')

  # Reload homebrew env and install.
  _install_homebrew(curl_opts)

  # Note: the dotfiles repo (cloned above via _clone_dot_files_repo -> GitProcessor.clone_repo_into)
  # is already a full clone by this point -- clone_repo_into runs 'unshallow' synchronously as
  # part of the clone itself, regardless of FIRST_INSTALL. No separate unshallow step is needed here.

  # Migrate repos cloned before Homebrew's git (2.45+) was on PATH. The system
  # git on vanilla macOS ignores -c init.defaultRefFormat=reftable and does not
  # support 'git refs migrate', so clone_repo_into's migration call was a no-op
  # for those early clones. Now that Homebrew's git is available, migrate them.
  # This runs after unshallow so the complete repository is migrated in one pass.
  Logging.with_step('Migrate repos to reftable', 'Migrating repos to reftable format') do
    GitProcessor.new(dir: EnvVars::DOTFILES_DIR).run_alias('migrate-reftable')
  end

  # Log into Keybase if KEYBASE_HOME_REPO_NAME/KEYBASE_PROFILES_REPO_NAME enable it.
  # Coexists with the encrypted-backup setup below -- see KeybaseMigration.md. This is
  # a readiness/login step only; the actual clone attempt (which also calls
  # Keybase.ensure_logged_in defensively) happens in _clone_home_repo/_clone_profiles_repo.
  Logging.with_step('Setup Keybase', 'Setup Keybase') do
    if nil_or_empty?(ENV.fetch('KEYBASE_HOME_REPO_NAME', '')) && nil_or_empty?(ENV.fetch('KEYBASE_PROFILES_REPO_NAME', ''))
      debug "Neither 'KEYBASE_HOME_REPO_NAME' nor 'KEYBASE_PROFILES_REPO_NAME' env var is set -- skipping Keybase setup"
    elsif !PathUtils.command_exists?('keybase')
      info "Skipping Keybase setup since 'keybase' is not installed"
    elsif Keybase.username
      # Already logged in (from a previous run, or 'keybase login' run manually) --
      # sync silently every time, never re-ask. This is what makes re-running this
      # idempotent script pleasant: once set up, it just stays set up.
      success 'Already logged into Keybase'
    elsif EnvVars.first_install?
      # Not logged in yet -- attempt login only on the true first-time vanilla-OS
      # bootstrap, non-interactively (no y/N gate). Re-runs on an already-configured
      # machine must NOT re-litigate this every time (see the 'else' branch below) --
      # that would turn a script designed to be safely re-run into one that blocks
      # on a login attempt every single run.
      if Keybase.ensure_logged_in
        success 'Successfully logged into Keybase'
      else
        record_warning 'Keybase login failed -- continuing without Keybase-based backups'
      end
    else
      # Pre-configured machine, not logged in, not FIRST_INSTALL: skip silently
      # rather than prompting on every maintenance re-run.
      info "Skipping Keybase login -- not logged in. Run 'keybase login' manually, then re-run this script, to enable it."
    end
  end

  # Verify encrypted-backup mechanism is ready (gpg installed, Keychain passphrase set --
  # see the external 'git-remote-gpg-encrypt' tool, installed via the 'vraravam/tap'
  # Homebrew tap). Coexists with Keybase above -- see KeybaseMigration.md. gnupg homedir
  # permissions were already fixed earlier in main() -- no need to repeat that here.
  Logging.with_step('Setup encrypted backup', 'Setup encrypted backup') do
    if nil_or_empty?(ENV.fetch('ENCRYPTED_HOME_REPO_URL', '')) && nil_or_empty?(ENV.fetch('ENCRYPTED_PROFILES_REPO_URL', ''))
      debug "Neither 'ENCRYPTED_HOME_REPO_URL' nor 'ENCRYPTED_PROFILES_REPO_URL' env var is set -- skipping encrypted-backup setup"
    elsif PathUtils.command_exists?('git-gpg-encrypt-setup')
      if system('git-gpg-encrypt-setup')
        success 'Encrypted backup is ready to use'
      else
        record_warning 'Encrypted backup is not configured -- see instructions above'
      end
    else
      debug "'git-gpg-encrypt-setup' not found in PATH -- skipping encrypted backup setup"
    end
  end

  # Clone repos from whichever backup mechanism(s) are enabled (home and browser-profiles)
  Logging.with_step('Clone repos', 'Cloning repos') do
    _clone_home_repo
    _clone_profiles_repo
  end

  # Remove stale SSH known_hosts backup if present.
  old_known_hosts = EnvVars::HOME.join('.ssh', 'known_hosts.old')
  old_known_hosts.delete if old_known_hosts.file?

  # Restore macOS preferences.
  Logging.with_step('Restore preferences', 'Restore preferences') do
    osx_defaults = EnvVars::DOTFILES_DIR.join('scripts', 'osx-defaults.rb')
    if osx_defaults.file?
      # Invoke directly via its own shebang rather than through the Ruby interpreter --
      # works the same whether the target is a shell script or (as here) a Ruby script.
      system(osx_defaults.to_s, '-s')
      success 'Successfully baselined preferences'
    else
      record_error "osx-defaults.rb not found at '#{osx_defaults}' -- baseline preferences manually"
    end

    capture_prefs = EnvVars::DOTFILES_DIR.join('scripts', 'capture-prefs.rb')
    if capture_prefs.file?
      # On pre-configured machines, refresh backup before import if stale.
      _refresh_preferences_backup(capture_prefs) unless EnvVars.first_install?

      # Must use subprocess instead of CapturePrefs.run(operation: 'import'):
      # capture-prefs.rb has at_exit hooks (resume softwareupdate, restart apps)
      # that must fire immediately after import completes, not at fresh-install
      # exit. Multiple invocations (export above, import here) need independent
      # cleanup lifecycles. Subprocess isolation ensures this.
      system(RUBY_BIN, capture_prefs.to_s, '-i')
      success 'Successfully restored preferences from backup'
    else
      record_error "capture-prefs.rb not found at '#{capture_prefs}' -- import preferences manually"
    end
  end

  # Recreate zsh completions cache.
  Logging.with_step('Recreate zsh completions', 'Recreate zsh completions') do
    zcompdump = EnvVars::XDG_CACHE_HOME.join('zcompdump')
    PathUtils.glob_pathnames(Pathname.new("#{zcompdump}*")) { |f| f.rmtree if f.exist? }
    CommandUtils.run_silent(
      'zsh', '-c',
      "autoload -Uz compinit && compinit -C -d '#{zcompdump}'"
    ) || true # Ignore failures - zsh completions are non-critical
  end

  # Setup cron jobs.
  Logging.with_step('Setup cron jobs', 'Setup cron jobs') do
    # Call recron first; only delete the backup after it completes without raising.
    # This ensures the at_exit resume_cron hook can still restore the original
    # schedule if recron fails outright (mirrors the shell version's ordering).
    Cron.recron
    EnvVars.cron_backup_file.delete if EnvVars.cron_backup_file.file?
  rescue StandardError => e
    record_error "Failed to set up cron jobs: #{e.message} -- original cron schedule preserved in backup"
  end

  # Resurrect all repos tracked in ${PERSONAL_CONFIGS_DIR}/repositories-*.yml catalogs.
  # Calls ResurrectRepositories.run directly (module call, not a subprocess) once per
  # catalog file -- mirrors the shell resurrect_tracked_repos function's loop over
  # 'repositories-*.yml(N.)'. Runs synchronously: on a first install this can legitimately
  # take a while (many repos to clone), but the rest of this script depends on repos
  # already being resurrected (e.g. regenerate_repo_aliases just below needs them present).
  if EnvVars::PERSONAL_CONFIGS_DIR.directory?
    failed_files = []
    Dir.glob(EnvVars::PERSONAL_CONFIGS_DIR.join('repositories-*.yml').to_s).each do |file|
      failed_files << file unless ResurrectRepositories.run(resurrect: file)
    end

    if failed_files.empty?
      success 'Successfully resurrected all tracked git repos'
    else
      # A warning, not an error -- mirrors the shell resurrect_tracked_repos function,
      # which appends directly to _step_warnings (not _step_errors) for this exact
      # condition, treating per-catalog resurrection failures as recoverable.
      record_warning "Failed to process #{failed_files.count} file(s): #{failed_files.join(', ')}"
    end
  else
    debug "Skipping resurrecting of repositories since '#{EnvVars::PERSONAL_CONFIGS_DIR.to_s.cyan}' doesn't exist"
  end

  # post-clone operations for installing system dependencies
  GitWorkspace.setup_dev_environment(first_install: EnvVars.first_install?)
  GitWorkspace.regenerate_repo_aliases

  # Force-refresh all zsh bytecode (*.zwc) and cache files. install-dotfiles.rb
  # re-symlinks .zshrc/.shellrc/.aliases on every run, but a .zwc left over from
  # an earlier partial fresh-install attempt (or a terminal opened manually
  # mid-debug) can carry a mtime that defeats recompile_zsh_script's -nt
  # staleness check -- new terminals then load bytecode compiled from stale
  # source indefinitely (e.g. missing PATH entries added by a later commit),
  # with no self-correction since plain zsh never checks .zwc staleness itself.
  # delete_caches (a shell function in .aliases) sidesteps the mtime comparison
  # entirely by deleting every *.zwc* file unconditionally and rebuilding from
  # current source. Shelled out to zsh (mirrors _download_and_source_shellrc
  # above) since delete_caches has no Ruby port -- .shellrc must be sourced
  # first since .aliases' functions depend on it.
  Logging.with_step('Refresh zsh bytecode caches', 'Refresh zsh bytecode caches') do
    shellrc_path = EnvVars::HOME.join('.shellrc')
    aliases_path = EnvVars::ZDOTDIR.join('.aliases')
    cmd = "source #{shellrc_path.to_s.shellescape}; source #{aliases_path.to_s.shellescape}; delete_caches"
    if system('zsh', '-c', cmd)
      success 'Successfully refreshed zsh bytecode caches'
    else
      record_warning "Failed to run 'delete_caches' -- new terminals may load stale .zwc files until it is run manually"
    end
  end

  # Set default shell to Homebrew zsh (done at the end to avoid password prompt mid-script).
  _set_default_shell

  # User action reminders
  Logging.user_action 'Review System Settings and adjust as needed (Privacy & Security, Notifications, etc.)'

  # On FIRST_INSTALL, remind user to unshallow repos to get full history.
  Logging.user_action "Repositories were cloned shallow (--depth=1) to save time. Run '#{'all unshallow'.yellow}' to fetch complete history, then '#{'git rebase @{u}'.yellow}' or '#{'git merge @{u}'.yellow}' in each repo to update working trees." if EnvVars.first_install?

  success '** Finished auto installation process **'
rescue StandardError => e
  # Unhandled exception during main execution.
  # at_exit hooks will still run (softwareupdate resume, summary, notification).
  # with_cron_suspended will automatically resume cron on exit.
  # Print error details before at_exit hooks fire.
  msg = "Installation failed with unhandled exception: #{e.message}"
  # Add first backtrace line for context
  msg += "\n  at #{e.backtrace.first}" if e.backtrace&.any?
  Logging.error msg
  # Exit non-zero to signal failure
  exit 1
end

# ---------------------------------------------------------------------------
# Script execution
# ---------------------------------------------------------------------------

# This script always executes at top level (lines 403-674) when run.
# No if __FILE__ == $PROGRAM_NAME guard is needed because this is a one-time
# install script that is never required as a library by other scripts.
