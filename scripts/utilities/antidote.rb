# frozen_string_literal: true

require 'open3'

require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

# Shared antidote plugin-manager helpers used by both post-brew-install.rb
# and software-updates-cron.rb.
#
# Antidote must be driven through zsh because antidote itself is a zsh
# function -- there is no Ruby API for it. The update step and bundle
# regeneration are therefore shell invocations, but the guard logic and
# git maintenance calls are kept in Ruby to avoid an extra shell layer.
#
# fsck is disabled on fetch for bundle repos: some repos (e.g. ohmyzsh,
# fast-syntax-highlighting) have zero-padded file modes that fail remote
# fsck during --unshallow. Disabling it only on fetch (not receive/transfer)
# is the narrowest correct fix.
module Antidote
  extend self

  # Note: Logging methods must be qualified (Logging.debug, Logging.info, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # Updates all installed antidote plugins, unshallows their git repos,
  # and regenerates the static bundle file. Reads all paths from EnvVars:
  #   ANTIDOTE_ZSH        path to antidote.zsh
  #   ANTIDOTE_PLUGIN_TXT path to the .zsh_plugins.txt input file
  #   ANTIDOTE_PLUGIN_ZSH path to the generated .zsh_plugins.zsh bundle
  #   ANTIDOTE_HOME       directory where antidote clones plugins
  def update_and_regenerate_bundle
    antidote_zsh = EnvVars::ANTIDOTE_ZSH
    plugin_txt = EnvVars::ANTIDOTE_PLUGIN_TXT
    plugin_zsh = EnvVars::ANTIDOTE_PLUGIN_ZSH
    antidote_home = EnvVars::ANTIDOTE_HOME

    unless antidote_zsh.file? && !antidote_zsh.empty? && plugin_txt.file? && !plugin_txt.empty?
      Logging.debug "Skipping antidote bundle regeneration: antidote not found at '#{antidote_zsh.cyan}' " \
                    "or plugin list '#{plugin_txt.cyan}' is missing"
      return
    end

    if antidote_home.directory? && !Dir.empty?(antidote_home)
      system('zsh', '-f', '-c', 'source "$1"; antidote update', '--', antidote_zsh.to_s)
      PathUtils.glob_pathnames(antidote_home.join('github.com', '*', '*')) do |bundle_dir|
        next unless bundle_dir.directory?
        next unless bundle_dir.join('.git').directory?
        system('git', '-C', bundle_dir.to_s, 'config', '--local', 'fetch.fsckObjects', 'false',
               out: File::NULL, err: File::NULL)
        system('git', '-C', bundle_dir.to_s, 'pull-unshallow', '-q',
               out: File::NULL, err: File::NULL)
      end
    end

    # antidote bundle reads the plugin list from stdin; pass it via stdin_data
    # so no shell redirect (<) is needed -- array form avoids a shell layer.
    bundle_content, _err, status = Open3.capture3(
      'zsh', '-f', '-c', 'source "$1"; antidote bundle', '--', antidote_zsh.to_s,
      stdin_data: plugin_txt.read
    )
    if status.success?
      plugin_zsh.write(bundle_content)
      Logging.success "antidote bundle regenerated at '#{plugin_zsh.to_s.yellow}'"
    else
      Logging.record_warning('Failed to regenerate antidote bundle')
    end
  end
end
