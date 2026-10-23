#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'core'
require_relative 'command_utils'
require_relative 'logging'
require_relative 'path_utils'

# SQLite helper for database operations (e.g., browser profile cleanup).
# Only check availability at the call site if you don't want to require this file.
module SQLite
  extend self

  COMMAND = 'sqlite3'

  def available?
    PathUtils.command_exists?(COMMAND)
  end

  def execute(db_path, sql)
    unless available?
      Logging.skip_tool(COMMAND)
      return false
    end

    return false unless Pathname(db_path).file?

    CommandUtils.run_interactive(COMMAND, db_path, sql)
  end
end
