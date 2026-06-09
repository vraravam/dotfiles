# frozen_string_literal: true

# macOS-specific helpers. Currently provides only time formatting utilities
# needed by recreate-repo.rb.
#
# These are macOS-only -- callers should not require this module on Linux or Windows.
module MacOS
  extend self

  # Returns the current wall-clock time formatted as 'YYYY-MM-DD HH:MM:SS',
  # mirroring current_timestamp in .shellrc.
  #
  # @return [String]
  def current_timestamp
    Time.now.strftime('%Y-%m-%d %H:%M:%S')
  end
end
