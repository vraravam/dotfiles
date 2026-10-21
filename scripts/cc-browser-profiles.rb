#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Per-folder override for 'cc' in the browser-profiles repo: runs the default 'cc'
# implementation with cron suspended for the duration, so that no cron job touches the
# profile files while they are being compressed.

require 'cron'
require 'git_commands'
require 'logging'

Logging.run_script do
  # header: false -- run_script already prints this script's own banner.
  Cron.with_cron_suspended { GitCommands.cc(args: ARGV, header: false) }
end
