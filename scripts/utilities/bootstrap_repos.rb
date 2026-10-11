#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative '../resurrect-repositories'
require_relative 'dev_environment'
require_relative 'env_vars'
require_relative 'generate_bootstrap_repositories_yaml'
require_relative 'keybase'
require_relative 'logging'

# Clones or updates the home and browser-profiles repos during the machine setup, from
# whichever backup mechanism(s) are configured (Keybase and/or encrypted git remotes). The
# generated YAML config is consumed by ResurrectRepositories, which owns the generic
# clone/verify/remote-configuration/fetch/post-clone logic, including trying a repo's
# 'other_remotes' as a fallback clone source when the primary remote fails.
#
# fresh-install-of-osx.sh calls it through call-utility.rb; Ruby callers can use it directly.
# The sub-steps run as in-process module calls rather than separate scripts.
module BootstrapRepos
  extend self

  # The generated config lives directly in $HOME, not in ${PERSONAL_CONFIGS_DIR}: that folder is
  # inside the home repo and does not exist until this resurrects it. See
  # files/--HOME--/custom.gitignore for why it is safe to leave there permanently.
  CONFIG_FILE_NAME = '.bootstrap-repositories.yml'

  # Public API method.
  #
  # @return [Boolean] false when the config could not be generated or some repo could not be
  #   fully resurrected; each problem is also recorded (and printed) at the point it occurs.
  def run
    ok = false
    Logging.run_script('bootstrap_repos', 'Cloning the home and browser-profiles repos') do
      ok = _run
    end
    ok
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @return [Boolean]
  def _run
    # Cloning itself does not log into Keybase, so make sure of it here (a no-op when Keybase is
    # not configured or already logged in). Failure is recorded and does not stop the cloning.
    Keybase.bootstrap_login

    ok = _resurrect(EnvVars::HOME.join(CONFIG_FILE_NAME))

    # Run the developer-environment setup once now, as a safety net, right after these repos are
    # cloned: it covers mise tool-version installation and direnv allow for them even if a later
    # step aborts before the full tracked-repos resurrection, which runs it again for every
    # repo (idempotent). Only the repos near the top exist at this point, so the search is shallow.
    DevEnvironment.setup_dev_environment(maxdepth: DevEnvironment::SHALLOW_MAXDEPTH)

    ok
  end

  # @param config [Pathname] where to write the generated config
  # @return [Boolean]
  def _resurrect(config)
    unless GenerateBootstrapRepositoriesYaml.run(output_file: config)
      Logging.record_error 'Failed to generate bootstrap repositories config -- skipping home/profiles repo resurrection'
      return false
    end

    return true if ResurrectRepositories.run(resurrect: config)

    Logging.record_warning 'Failed to fully resurrect home/profiles repos -- see output above for details'
    false
  end

  private_class_method :_run, :_resurrect
end
