#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'open3'

require_relative 'command_utils'
require_relative 'core'
require_relative 'enumerable_ext'
require_relative 'logging'

# Generic framework for processing collections of items (paths, hashes, objects)
# with unified logging, error handling, and summary reporting.
#
# This is a domain-agnostic utility that provides consistent iteration patterns
# for any collection. Scripts that process repositories, directories, or other
# collections (run-all.rb, resurrect-repositories.rb, DevEnvironment.install_mise_versions,
# DevEnvironment.activate_all_direnv_configs) delegate to this module for the processing loop
# mechanics while providing their own domain-specific logic via blocks.
#
# The module makes no assumptions about what is being processed -- it only
# provides the iteration infrastructure.
module CollectionProcessor
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Note: Logging methods must be qualified (Logging.debug, Logging.info, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # ---------------------------------------------------------------------------
  # Directory Discovery
  # ---------------------------------------------------------------------------

  # Finds directories matching a specific name pattern using the find command.
  # Generic directory discovery utility that can be used for any pattern-based
  # search (.git directories, node_modules, etc.).
  #
  # @param dirs [Array<String, Pathname>, String, Pathname] Root directory/directories to search
  # @param name_pattern [String] The directory name to search for (e.g., '.git', 'node_modules')
  # @param mindepth [Integer] Minimum search depth (default: 1)
  # @param maxdepth [Integer] Maximum search depth (default: 6)
  # @param filter [String, Regexp, nil] Optional regex to filter results by full path
  # @param prune_dirs [Array<String>] Directories to exclude from search (default: [])
  # @param exclude_regex [String, nil] Optional regex pattern to pass to find's -not -regex flag
  #   (e.g., '.*/\\..*/\\.git' to exclude .git dirs inside hidden directories)
  # @param skip_symlinks [Boolean] Also drop matches that are symlinks (default: true). Currently a
  #   no-op safety net: 'find' runs without -L and the match is restricted to '-type d', so a
  #   symlink is never reported (nor descended into) to begin with. Kept for API compatibility and
  #   so the intent stays explicit at call sites; it would only matter if 'find' were ever run
  #   with -L.
  # @param transform_result [Proc, nil] Optional proc to transform each result path
  #   before adding to results. Receives the matched path, should return the
  #   transformed path. For example, to get parent directories of matched items:
  #   ->(path) { File.dirname(path) }
  # @param noise_patterns [Array<String>, nil] Patterns to filter from stderr (e.g., ['Permission denied'])
  # @return [Array<String>] Matching directory paths, deduplicated and sorted alphabetically
  #
  # @example Find all .git directories
  #   git_dirs = CollectionProcessor.find_directories_matching(
  #     dirs: '/Users/me/projects',
  #     name_pattern: '.git'
  #   )
  #
  # @example Find git repo roots (parents of .git dirs)
  #   repo_roots = CollectionProcessor.find_directories_matching(
  #     dirs: '/Users/me/projects',
  #     name_pattern: '.git',
  #     transform_result: ->(git_dir) { File.dirname(git_dir) }
  #   )
  #
  # @example With pruning and filtering
  #   repos = CollectionProcessor.find_directories_matching(
  #     dirs: ['/Users/me/work', '/Users/me/oss'],
  #     name_pattern: '.git',
  #     prune_dirs: %w[node_modules .cache],
  #     filter: /my-project/,
  #     maxdepth: 4
  #   )
  #
  # @example Exclude hidden directories
  #   repos = CollectionProcessor.find_directories_matching(
  #     dirs: ENV['HOME'],
  #     name_pattern: '.git',
  #     exclude_regex: '.*/\\..*/\\.git',
  #     noise_patterns: ['Permission denied', 'No such file or directory']
  #   )
  def find_directories_matching(dirs:, name_pattern:, mindepth: 1, maxdepth: 6, filter: nil, prune_dirs: [], exclude_regex: nil, skip_symlinks: true, transform_result: nil, noise_patterns: nil)
    roots = _existing_dirs(dirs)
    # Nothing left to search (e.g. every root was missing) -- 'find' with no path
    # arguments defaults to searching '.', which would silently search the wrong
    # location instead of returning no results.
    return [] if nil_or_empty?(roots)

    find_cmd = _build_find_cmd(roots, name_pattern: name_pattern, mindepth: mindepth, maxdepth: maxdepth,
                                      prune_dirs: prune_dirs, exclude_regex: exclude_regex)
    stdout_str, stderr_str, status = Open3.capture3(*find_cmd)

    # Log formatted output on failure (warnings logged but processing continues for partial results).
    # noise_patterns filters stderr if provided, otherwise shows all stderr.
    # Stdout is not logged - it contains the list of found directories which are processed and returned.
    success = CommandUtils.check_status_or_record(nil, stderr_str, status, 'Issues while searching directories',
                                                  noise_patterns: noise_patterns)

    # Process results if command succeeded OR produced output (partial success case:
    # find may encounter permission denied but still return results for accessible dirs)
    return [] unless success || !nil_or_empty?(stdout_str)

    _collect_matches(stdout_str, filter: filter, skip_symlinks: skip_symlinks, transform_result: transform_result)
  rescue Errno::ENOENT
    Logging.record_error("'find' command not found. Please ensure it is installed and in your PATH.")
    []
  rescue StandardError => e
    Logging.record_error("Error executing 'find' command: #{e.message}")
    []
  end

  # ---------------------------------------------------------------------------
  # Item Processing
  # ---------------------------------------------------------------------------

  # Processes a collection of items (directories, repos, etc.) with unified
  # progress logging, error tracking, and summary reporting.
  #
  # The caller provides a block that receives each item and performs the
  # operation. The block should return a truthy value on success, falsy on
  # failure. Exceptions raised in the block are caught and recorded as errors.
  #
  # @param items [Array<String, Hash>] Items to process. Can be simple paths
  #   (Strings) or hashes (e.g., repo configs with folder/remote keys).
  # @param item_name_proc [Proc, nil] Optional proc to extract a display name
  #   from each item. Defaults to calling .to_s on the item. For hashes, pass
  #   a proc like ->(item) { item['folder'] }.
  # @param operation_desc [String, nil] Optional description of the operation
  #   for progress messages (e.g., 'Running command', 'Resurrecting',
  #   'Installing mise tools'). When provided, progress messages show:
  #   "[idx/total] <operation_desc>: 'item_name'"
  #   When nil, progress messages show: "[idx/total] 'item_name'"
  # @param skip_proc [Proc, nil] Optional proc to determine if an item should
  #   be skipped before processing. Receives the item and returns truthy to skip.
  #   When an item is skipped, no progress message is logged, and it doesn't
  #   count toward successful/failed totals.
  # @param dry_run [Boolean] When true, logs what would be done without calling
  #   the block. Useful for --dry-run modes.
  # @yield [item, idx, total] Processes a single item. The block receives:
  #   - item: the item to process
  #   - idx: 1-based index of the item
  #   - total: total count of items
  #   Should return truthy on success, falsy on failure. Exceptions are caught and recorded as errors.
  # @return [Hash] Summary hash with keys:
  #   - :total [Integer] Total items processed (excludes skipped)
  #   - :successful [Array<String>] Display names of successful items
  #   - :failed [Array<String>] Display names of failed items
  #   - :skipped [Integer] Count of items skipped via skip_proc
  #
  # @example Simple path processing
  #   results = CollectionProcessor.process_items(
  #     repo_paths,
  #     operation_desc: 'Running git status'
  #   ) do |repo_path, idx, total|
  #     GitProcessor.new(dir: repo_path) { |git| git.status }
  #   end
  #   puts "Processed #{results[:total]}, #{results[:failed].length} failed"
  #
  # @example Hash processing with custom name extraction
  #   results = CollectionProcessor.process_items(
  #     repo_configs,
  #     item_name_proc: ->(repo) { repo['folder'] },
  #     operation_desc: 'Resurrecting'
  #   ) do |repo, idx, total|
  #     clone_and_verify(repo)
  #   end
  #
  # @example With skip logic
  #   results = CollectionProcessor.process_items(
  #     dirs_with_mise,
  #     operation_desc: 'Installing mise tools',
  #     skip_proc: ->(dir) { mise_already_installed?(dir) }
  #   ) do |dir, idx, total|
  #     CommandUtils.run_silent('mise', '-C', dir, 'install')
  #   end
  def process_items(items, item_name_proc: nil, operation_desc: nil, skip_proc: nil, dry_run: false, &block)
    # Default name extraction: call .to_s on the item
    name_extractor = item_name_proc || ->(item) { item.to_s }

    successful = []
    failed = []
    skipped_count = 0
    total = items.length

    # Calculate width for counter alignment based on total count
    counter_width = total.to_s.length
    # Format total once (constant throughout loop)
    total_str = format_counter(total, counter_width)

    items.each_with_index do |item, idx|
      item_name = name_extractor.call(item)
      one_based_idx = idx + 1

      # Check skip condition before any logging or processing
      if skip_proc&.call(item)
        skipped_count += 1
        next
      end

      # Build progress message with aligned counters
      idx_str = format_counter(one_based_idx, counter_width)
      progress = "[#{idx_str.purple} of #{total_str.purple}]"

      ok = _process_one(item, item_name: item_name, progress: progress, operation_desc: operation_desc,
                              dry_run: dry_run, idx: one_based_idx, total: total, &block)
      (ok ? successful : failed) << item_name
    end

    # Adjust total to exclude skipped items for accurate summary
    processed_total = total - skipped_count

    {
      total: processed_total,
      successful: successful,
      failed: failed,
      skipped: skipped_count
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  # Keeps the existing, searchable directories from a caller-supplied list.
  # A root that doesn't exist (e.g. PROJECTS_BASE_DIR defaulting to '~/dev' on a machine where
  # that directory was never created) is skipped here rather than passed to 'find', which would
  # otherwise fail with "No such file or directory" on that single root and surface as a spurious
  # warning even though the other roots are perfectly searchable.
  #
  # @param dirs [Array<String, Pathname>, String, Pathname, nil]
  # @return [Array<String>] Paths of the existing directories (blank and missing entries dropped)
  def _existing_dirs(dirs)
    # filter_map polyfill in enumerable_ext.rb provides optimized single-pass implementation for Ruby 2.6
    Array(dirs).filter_map do |dir|
      dir_str = dir.to_s
      next if nil_or_empty?(dir_str)

      unless File.directory?(dir_str)
        Logging.debug "Skipping search dir '#{dir_str.cyan}' -- doesn't exist"
        next
      end

      dir_str
    end
  end

  # Pure: builds the 'find' argv, running nothing.
  #
  # @param roots [Array<String>] Existing directories to search (at least one)
  # @return [Array<String>] e.g. ['find', '/r', '-mindepth', '1', '-maxdepth', '6', '(', '-name', 'node_modules',
  #   ')', '-prune', '-o', '-type', 'd', '-name', '.git', '-prune', '-print0']
  def _build_find_cmd(roots, name_pattern:, mindepth:, maxdepth:, prune_dirs: [], exclude_regex: nil)
    prune = Array(prune_dirs)
    # Prune expression: ( -name dir1 -o -name dir2 ... ) -prune -o
    prune_expr = nil_or_empty?(prune) ? [] : ['('] + prune.flat_map { |d| ['-o', '-name', d] }.drop(1) + [')', '-prune', '-o']
    exclude_expr = exclude_regex ? ['-not', '-regex', exclude_regex] : []

    start = ['find', *roots, '-mindepth', mindepth.to_s, '-maxdepth', maxdepth.to_s]
    start + prune_expr + exclude_expr + ['-type', 'd', '-name', name_pattern, '-prune', '-print0']
  end

  # Turns NUL-separated 'find' output into the final result list: filtered, optionally
  # transformed, de-duplicated and sorted (sorted for deterministic output; callers may re-sort
  # by other criteria such as depth).
  #
  # @return [Array<String>]
  def _collect_matches(stdout_str, filter:, skip_symlinks:, transform_result:)
    filter_re = filter.is_a?(Regexp) || !filter ? filter : Regexp.new(filter)

    stdout_str.split("\0").filter_map do |path|
      next if filter_re && !path.match?(filter_re)
      next if skip_symlinks && File.symlink?(path)

      # Apply transform if provided (e.g., get parent directory)
      transform_result ? transform_result.call(path) : path
    end.uniq.sort
  end

  # Processes one item of process_items: depth/indent bookkeeping, header, then the caller's block.
  #
  # @return [Boolean] true when the item counts as successful (dry-run items always do)
  def _process_one(item, item_name:, progress:, operation_desc:, dry_run:, idx:, total:)
    # Increment depth before printing the item header so it's indented one level deeper
    # than the parent operation.
    Logging.increment_script_depth

    # Print section header for this item
    item_name_colored = item_name.cyan
    operation_part = operation_desc ? "#{operation_desc.yellow}: " : ''
    Logging.section_header("#{progress} #{operation_part}'#{item_name_colored}'")

    if dry_run
      Logging.info "Would process '#{item_name_colored}'"
      Logging.decrement_script_depth
      return true
    end

    # Increment depth again so operations within this item are nested one level deeper
    Logging.increment_script_depth
    begin
      # Call the user's block with item, idx (1-based), and total
      return true if yield(item, idx, total)

      # Caller should handle its own warning/error logging before returning false.
      # run-all.rb always returns true and logs via record_warning before returning.
      # resurrect-repositories.rb returns false for fatal failures (logs via record_error).
      # Provide a fallback warning in case a future caller returns false without logging.
      Logging.record_warning("Processing failed for '#{item_name_colored}'")
      false
    rescue StandardError => e
      # Exceptions are unexpected script errors (missing method, nil reference, etc.)
      # Record as error with context. Callers should not rescue StandardError.
      Logging.record_error("Exception processing '#{item_name_colored}': #{e.message}")
      false
    ensure
      # Decrement depth twice: once for operations block, once for item header
      2.times { Logging.decrement_script_depth }
    end
  end

  # Right-justifies a number to the specified width.
  # Used for aligned progress counters like [ 1 of 100], [10 of 100], [100 of 100].
  #
  # @param num [Numeric] The number to format
  # @param width [Integer] The width to pad to (calculated from total count)
  # @return [String] The right-justified number string
  #
  # @example
  #   format_counter(1, 3)    # => "  1"
  #   format_counter(10, 3)   # => " 10"
  #   format_counter(100, 3)  # => "100"
  def format_counter(num, width)
    num.to_s.rjust(width, ' ')
  end
end
