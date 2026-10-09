#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'rbconfig'
require 'pathname' # System Ruby on a vanilla macOS is 2.6; Pathname must be required explicitly because autoloading is unreliable at that version.
require_relative 'core'
require_relative 'env_lite'

# Centralized environment variable access for dotfiles scripts.
#
# Path constants are expanded Pathname objects.
# Non-path constants are frozen strings or nil.
# Runtime flags are methods (evaluated dynamically on each access).
#
# All values mirror shell export statements in .shellrc and provide sensible
# fallbacks for use during FIRST_INSTALL before .shellrc is sourced.
#
# Usage:
#   require 'env_vars'
#
#   # Path constants (Pathname objects)
#   puts EnvVars::HOME                              # Pathname object
#   puts EnvVars::HOME.to_s                         # String path
#   EnvVars::DOTFILES_DIR.join('scripts', 'foo.rb') # Pathname manipulation
#
#   # Non-path constants (String or nil)
#   puts EnvVars::USER                              # String (always set)
#
#   # Runtime flag methods (evaluated dynamically)
#   if EnvVars.debug?                               # Boolean
#     dir = EnvVars.folder || Dir.pwd            # String (expanded path) or nil
#     filter = EnvVars.filter                       # String (stripped) or nil
#   end
# :reek:TooManyConstants -- Centralized env var access requires many path constants
module EnvVars
  extend Core

  # ---------------------------------------------------------------------------
  # Private helpers (must be defined before constants that use them)
  # ---------------------------------------------------------------------------

  # Normalizes an optional string environment variable.
  # Returns nil when value is unset, nil, or empty after stripping whitespace.
  # Returns the stripped string otherwise.
  #
  # Used for env vars where empty and unset are semantically identical (the
  # feature is disabled or absent). Prevents returning empty strings that would
  # pass truthiness checks but fail nil_or_empty? checks.
  #
  # @param value [String, nil] Raw environment variable value
  # @return [String, nil] Stripped string, or nil if value is unset/empty/whitespace-only
  def self._normalize_optional_string(value)
    value&.then { |s| nil_or_empty?(s) ? nil : s.strip }
  end
  private_class_method :_normalize_optional_string

  # Fetches an environment variable and returns a Pathname, with fallback for empty values.
  # Returns the default Pathname (from block) when env var is unset, nil, or empty after stripping.
  # Returns expanded Pathname of the env var value otherwise.
  #
  # Handles both unset vars (vanilla OS) and accidentally-empty vars (user error).
  #
  # @param key [String] Environment variable name
  # @yield Block that returns the default (Pathname or String) when var is unset/empty
  # @return [Pathname] Expanded pathname from env var or default
  #
  # @example
  #   DOTFILES_DIR = _fetch_pathname('DOTFILES_DIR') { HOME.join('.config', 'dotfiles') }
  def self._fetch_pathname(key)
    val = ENV.fetch(key, '').strip
    Pathname.new(val.empty? ? yield : val).expand_path
  end
  private_class_method :_fetch_pathname

  # ---------------------------------------------------------------------------
  # Non-path variables (String objects)
  # ---------------------------------------------------------------------------

  # Current user's login name.
  # Mirrors: ${USER} (always set by the shell)
  USER = ENV.fetch('USER', ENV.fetch('USERNAME', '')).freeze

  # Current user's default shell.
  # Mirrors: ${SHELL} (always set by the shell)
  SHELL = ENV.fetch('SHELL', '/bin/zsh').freeze

  # GitHub username of the upstream owner of this dotfiles repo; passed to
  # add-upstream-git-config.rb (-u), which skips adding an 'upstream' remote when the
  # clone's 'origin' already belongs to this user.
  # Mirrors: export UPSTREAM_GH_USERNAME='vraravam'
  UPSTREAM_GH_USERNAME = ENV.fetch('UPSTREAM_GH_USERNAME', 'vraravam').freeze

  # Optional Keybase username. When set, fresh-install-of-osx.sh logs in with
  # 'keybase login <username>' (see Keybase.ensure_logged_in) instead of the fully
  # interactive flow; nil (unset/empty) keeps the interactive flow. Only consulted when
  # nobody is logged in yet -- the active username is otherwise derived from
  # 'keybase status' (see Keybase.username). It is only a hint, never a source of truth.
  # Mirrors: export KEYBASE_USERNAME='someuser'
  KEYBASE_USERNAME = _normalize_optional_string(ENV.fetch('KEYBASE_USERNAME', nil))

  # Keybase repository names (used with the Keybase backup mechanism, see
  # scripts/utilities/keybase.rb). nil (unset/empty in .shellrc) means Keybase support is
  # not enabled for that repo -- comment out the export in .shellrc to disable it entirely.
  # Mirrors: export KEYBASE_HOME_REPO_NAME='home'
  KEYBASE_HOME_REPO_NAME = _normalize_optional_string(ENV.fetch('KEYBASE_HOME_REPO_NAME', nil))

  # Mirrors: export KEYBASE_PROFILES_REPO_NAME='profiles'
  KEYBASE_PROFILES_REPO_NAME = _normalize_optional_string(ENV.fetch('KEYBASE_PROFILES_REPO_NAME', nil))

  # Encrypted git repo URLs (used with the external 'git-remote-gpg-encrypt' tool,
  # installed via the 'vraravam/tap' Homebrew tap -- see files/--HOME--/Brewfile). nil
  # (unset/empty in .shellrc) means this mechanism is not enabled for that repo --
  # comment out the export in .shellrc to disable it entirely. Coexists with Keybase
  # above -- both can be enabled at once (see KeybaseMigration.md). Unlike
  # KEYBASE_*_REPO_NAME above, this holds a full URL, not a bare repo name -- that tool
  # has no concept of a "default owner" to derive a full URL from a bare name.
  # Mirrors: export ENCRYPTED_HOME_REPO_URL='https://github.com/vraravam/home.git'
  ENCRYPTED_HOME_REPO_URL = _normalize_optional_string(ENV.fetch('ENCRYPTED_HOME_REPO_URL', nil))

  # Mirrors: export ENCRYPTED_PROFILES_REPO_URL='https://github.com/vraravam/browser-profiles.git'
  ENCRYPTED_PROFILES_REPO_URL = _normalize_optional_string(ENV.fetch('ENCRYPTED_PROFILES_REPO_URL', nil))

  # ---------------------------------------------------------------------------
  # Path variables (Pathname objects)
  # ---------------------------------------------------------------------------

  # User's home directory.
  # Mirrors: export HOME (always set by the shell)
  #
  # NOTE: This is the single source of truth for HOME in Ruby code. The lowest layers
  # (colorizable.rb) read it through EnvLite.home, which sits beneath env_vars in the
  # require chain.
  HOME = _fetch_pathname('HOME') { '~' }.freeze

  # User's Downloads directory.
  # Standard macOS location for temporary/transient files.
  DOWNLOADS = HOME.join('Downloads').freeze

  # Dotfiles repository directory.
  # Mirrors: export DOTFILES_DIR="${XDG_CONFIG_HOME}/dotfiles"
  DOTFILES_DIR = _fetch_pathname('DOTFILES_DIR') { HOME.join('.config', 'dotfiles') }.freeze

  # Personal bin directory (non-public scripts).
  # Mirrors: export PERSONAL_BIN_DIR="${HOME}/personal/dev/bin"
  PERSONAL_BIN_DIR = _fetch_pathname('PERSONAL_BIN_DIR') { HOME.join('personal', 'dev', 'bin') }.freeze

  # Personal configs directory (sensitive config files).
  # Mirrors: export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev/configs"
  PERSONAL_CONFIGS_DIR = _fetch_pathname('PERSONAL_CONFIGS_DIR') { HOME.join('personal', 'dev', 'configs') }.freeze

  # Personal profiles directory (browser profiles).
  # Mirrors: export PERSONAL_PROFILES_DIR="${HOME}/personal/${USER}/browser-profiles"
  PERSONAL_PROFILES_DIR = _fetch_pathname('PERSONAL_PROFILES_DIR') { HOME.join('personal', USER, 'browser-profiles') }.freeze

  # Projects base directory (where all git repos live).
  # Mirrors: export PROJECTS_BASE_DIR="${HOME}/dev"
  PROJECTS_BASE_DIR = _fetch_pathname('PROJECTS_BASE_DIR') { HOME.join('dev') }.freeze

  # XDG base directory specification paths.
  # Mirrors: XDG_* exports in .shellrc
  XDG_CACHE_HOME = _fetch_pathname('XDG_CACHE_HOME') { HOME.join('.cache') }.freeze
  XDG_CONFIG_HOME = _fetch_pathname('XDG_CONFIG_HOME') { HOME.join('.config') }.freeze
  XDG_DATA_HOME = _fetch_pathname('XDG_DATA_HOME') { HOME.join('.local', 'share') }.freeze
  XDG_STATE_HOME = _fetch_pathname('XDG_STATE_HOME') { HOME.join('.local', 'state') }.freeze

  # Temporary directory for transient files.
  # Mirrors: ${TMPDIR} (set by macOS, falls back to /tmp on other systems)
  # Used for cron backups, cache invalidation markers, etc.
  TMPDIR = _fetch_pathname('TMPDIR') { '/tmp' }.freeze

  # Zsh dotfiles directory.
  # Mirrors: export ZDOTDIR="${ZDOTDIR:-"${XDG_CONFIG_HOME:-${HOME}/.config}/zsh"}" in .shellrc
  ZDOTDIR = _fetch_pathname('ZDOTDIR') { XDG_CONFIG_HOME.join('zsh') }.freeze

  # Zsh history file location.
  # Mirrors: export HISTFILE="${XDG_STATE_HOME}/zsh/history" in .shellrc
  HISTFILE = _fetch_pathname('HISTFILE') { XDG_STATE_HOME.join('zsh', 'history') }.freeze

  # Homebrew paths.
  # Mirrors: HOMEBREW_* exports (set by brew shellenv, or fallback based on architecture)
  # ARM (Apple Silicon) uses /opt/homebrew, Intel uses /usr/local
  # The CPU comes from RbConfig (no subprocess); 'uname -m' would fork just to learn it.
  # Apple Silicon reports 'arm64' via uname but 'aarch64' via RbConfig, hence both spellings.
  HOMEBREW_PREFIX = _fetch_pathname('HOMEBREW_PREFIX') do
    RbConfig::CONFIG['host_cpu'].match?(/arm|aarch64/) ? '/opt/homebrew' : '/usr/local'
  end.freeze

  # Homebrew bundle files (Brewfile).
  # Mirrors: HOMEBREW_BUNDLE_FILE* exports in .shellrc (lines 147-148)
  HOMEBREW_BUNDLE_FILE = _fetch_pathname('HOMEBREW_BUNDLE_FILE') { HOME.join('Brewfile') }.freeze
  HOMEBREW_BUNDLE_FILE_GLOBAL = _fetch_pathname('HOMEBREW_BUNDLE_FILE_GLOBAL') { HOME.join('Brewfile') }.freeze

  # Antidote plugin manager paths.
  # Mirrors: ANTIDOTE_* exports in .shellrc (platform-specific and brew-dependent)
  # Note: On macOS ANTIDOTE_HOME defaults to ~/Library/Caches/antidote, on Linux to ${XDG_CACHE_HOME}/antidote
  ANTIDOTE_HOME = _fetch_pathname('ANTIDOTE_HOME') { HOME.join('Library', 'Caches', 'antidote') }.freeze
  ANTIDOTE_ZSH = _fetch_pathname('ANTIDOTE_ZSH') { HOMEBREW_PREFIX.join('opt', 'antidote', 'share', 'antidote', 'antidote.zsh') }.freeze
  ANTIDOTE_PLUGIN_ZSH = _fetch_pathname('ANTIDOTE_PLUGIN_ZSH') { XDG_CONFIG_HOME.join('zsh', 'plugins.zsh') }.freeze
  ANTIDOTE_PLUGIN_TXT = _fetch_pathname('ANTIDOTE_PLUGIN_TXT') { XDG_CONFIG_HOME.join('zsh', 'plugins.txt') }.freeze

  # ---------------------------------------------------------------------------
  # Non-path variables (String objects)
  # ---------------------------------------------------------------------------

  # Note: There is no DOTFILES_BRANCH constant here (mirrors the absence of GH_USERNAME).
  # Both are shell-only, bootstrap-transient values used solely by
  # fresh-install-of-osx.sh's own _resolve_gh_username/_resolve_dotfiles_branch --
  # nothing in Ruby ever needs either one.

  # ---------------------------------------------------------------------------
  # Runtime flags and temporary operation variables (evaluated dynamically)
  # These are implemented as class methods (not constants) because they can
  # change between invocations or during script execution.
  # ---------------------------------------------------------------------------

  # Filter pattern for repo operations (run-all.rb, resurrect-repositories.rb).
  # Mirrors: export FILTER (set temporarily for filtering operations)
  # Returns nil when not set or empty (after stripping whitespace), otherwise returns stripped string.
  #
  # @return [String, nil] Stripped filter pattern, or nil when unset/empty
  def self.filter
    _normalize_optional_string(ENV.fetch('FILTER', nil))
  end

  # Reference dir for repo verification (resurrect-repositories.rb).
  # Mirrors: export REF_FOLDER (set temporarily for verification operations)
  # Returns nil when not set or empty (after stripping whitespace), otherwise returns expanded absolute Pathname.
  #
  # @return [Pathname, nil] Expanded reference folder path, or nil when unset/empty
  def self.ref_folder
    _normalize_optional_string(ENV.fetch('REF_FOLDER', nil))&.then { |s| Pathname.new(s).expand_path }
  end

  # Base dir for repo operations (run-all.rb).
  # Mirrors: export FOLDER (set temporarily for run-all operations, defaults to current directory)
  # Returns nil when not set or empty (after stripping whitespace), otherwise returns expanded absolute Pathname.
  #
  # @return [Pathname, nil] Expanded base folder path, or nil when unset/empty
  def self.folder
    _normalize_optional_string(ENV.fetch('FOLDER', nil))&.then { |s| Pathname.new(s).expand_path }
  end

  # Search depth limits for repo operations (run-all.rb).
  # Mirrors: export MINDEPTH / MAXDEPTH (set temporarily for run-all operations)
  #
  # @return [Integer] Minimum recursion depth (default: 1)
  def self.mindepth
    ENV.fetch('MINDEPTH', '1').to_i
  end

  # Maximum depth for recursive git operations (used by run-all.rb and shell
  # equivalents like 'home pull'). Defaults to 4 levels deep. Can be overridden
  # via MAXDEPTH env var for ad-hoc operations.
  #
  # @return [Integer] Maximum recursion depth (default: 4)
  def self.maxdepth
    ENV.fetch('MAXDEPTH', '4').to_i
  end

  # First install mode (vanilla OS, no dotfiles yet).
  # Mirrors: export FIRST_INSTALL=1 (set in fresh-install bootstrap)
  #
  # @return [Boolean] true if FIRST_INSTALL is set to a non-empty value
  def self.first_install?
    !nil_or_empty?(ENV.fetch('FIRST_INSTALL', ''))
  end

  # Debug mode (verbose logging).
  # Mirrors: export DEBUG=1 (set manually for debugging)
  #
  # @return [Boolean] true if DEBUG is set to a non-empty value
  def self.debug?
    !nil_or_empty?(ENV.fetch('DEBUG', ''))
  end

  # Returns true if FORCE_COLOR is set (used by color output methods).
  # Mirrors: FORCE_COLOR env var (standard convention for forcing color output)
  #
  # Delegates to EnvLite, which Core uses too (Core sits beneath EnvVars in the require chain).
  #
  # @return [Boolean] true if FORCE_COLOR is set to a non-empty (stripped) value
  def self.force_color?
    EnvLite.force_color?
  end

  # Current script depth (incremented by increment_script_depth).
  # Mirrors: _DOTFILES_SCRIPT_DEPTH (managed by logging.rb and shell scripts)
  # Returns 0 when unset (not yet incremented by any script).
  #
  # @return [Integer] Current script nesting depth (default: 0)
  def self.script_depth
    ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
  end

  # Writes the script nesting depth back to the environment so child processes (shell
  # functions, nested Ruby scripts) inherit it. The only sanctioned writer of
  # _DOTFILES_SCRIPT_DEPTH in Ruby (see Logging.increment_script_depth).
  #
  # @param depth [Integer] The new nesting depth
  # @return [Integer] The depth that was set
  def self.script_depth=(depth)
    ENV['_DOTFILES_SCRIPT_DEPTH'] = depth.to_s
    depth
  end

  # Log file path for structured file logging (opt-in).
  # Mirrors: LOG_FILE env var
  #
  # @return [String, nil] Path, or nil when unset/blank (file logging disabled)
  def self.log_file
    _normalize_optional_string(ENV.fetch('LOG_FILE', nil))
  end

  # Minimum log level name (debug, info, success, warn, error, user_action).
  # Mirrors: LOG_LEVEL env var
  #
  # @return [Symbol] Lowercased level name (default: :info; validity is checked by Logging)
  def self.log_level
    ENV.fetch('LOG_LEVEL', 'info').downcase.to_sym
  end

  # Log file entry format.
  # Mirrors: LOG_FORMAT env var
  #
  # @return [String] 'json' or 'text' (default: 'text')
  def self.log_format
    ENV.fetch('LOG_FORMAT', 'text').downcase
  end

  # Script name override used in JSON log entries.
  # Mirrors: SCRIPT_NAME env var
  #
  # @return [String] SCRIPT_NAME, falling back to $PROGRAM_NAME
  def self.log_script_name
    ENV.fetch('SCRIPT_NAME', $PROGRAM_NAME)
  end

  # Terminal column width from COLUMNS env var.
  # Mirrors: ${COLUMNS} (set by shell, may be 0 in non-TTY contexts)
  # Returns 80 when unset or 0 (fallback matches _FALLBACK_TERMINAL_WIDTH in .shellrc)
  #
  # @return [Integer] Terminal column width (default: 80)
  def self.columns
    ENV.fetch('COLUMNS', '80').to_i
  end

  # Cron backup file path (used by suspend_cron/resume_cron).
  # Mirrors: _DOTFILES_CRON_BACKUP_FILE (set by suspend_cron in .shellrc)
  # Falls back to TMPDIR/crontab_backup when not set.
  # Returns Pathname so callers can use Pathname methods directly.
  #
  # @return [Pathname] Cron backup file path
  def self.cron_backup_file
    _fetch_pathname('_DOTFILES_CRON_BACKUP_FILE') { TMPDIR.join('crontab_backup') }
  end

  # Returns true if logging output should be suppressed.
  # Currently checks if running inside a direnv subshell, where most logging
  # is unwanted noise. Future extensions: CI environment checks, log level filtering.
  # DIRENV_IN_ENVRC=1 is set by direnv during .envrc evaluation and survives
  # strict_env (unlike DIRENV_DIR). Used by info/success/warn/user_action/debug.
  # error() always prints regardless of context -- critical failures must be visible.
  # Mirrors: _should_suppress_log() in .shellrc
  #
  # @return [Boolean] true if logging output should be suppressed
  def self.suppress_log?
    !nil_or_empty?(ENV.fetch('DIRENV_IN_ENVRC', ''))
  end

  # Returns true if CACHE_BUST_HEADERS env var is set (used for curl downloads).
  # When true, curl requests should add cache-busting headers.
  #
  # @return [Boolean] true if CACHE_BUST_HEADERS is set to a non-empty (stripped) value
  def self.cache_bust_headers?
    !nil_or_empty?(ENV.fetch('CACHE_BUST_HEADERS', '').strip)
  end

  # Returns current PATH environment variable.
  # Used by PathUtils.prepend_to_path to check/modify PATH.
  #
  # @return [String] Current PATH value (empty string if unset)
  def self.path
    ENV.fetch('PATH', '')
  end

  # Returns the current RUBYLIB (the directories Ruby searches for 'require').
  #
  # @return [String, nil] RUBYLIB, or nil when unset
  def self.rubylib
    ENV.fetch('RUBYLIB', nil)
  end
end
