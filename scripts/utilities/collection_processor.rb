# frozen_string_literal: true

require_relative 'logging'

# Generic framework for processing collections of items (paths, hashes, objects)
# with unified logging, error handling, and summary reporting.
#
# This is a domain-agnostic utility that provides consistent iteration patterns
# for any collection. Scripts that process repositories, directories, or other
# collections (run-all.rb, resurrect-repositories.rb, install_mise_versions,
# allow_all_direnv_configs) delegate to this module for the processing loop
# mechanics while providing their own domain-specific logic via blocks.
#
# The module makes no assumptions about what is being processed -- it only
# provides the iteration infrastructure.
module CollectionProcessor
  extend self

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
  # @param folders [Array<String, Pathname>, String, Pathname] Root directory/directories to search
  # @param name_pattern [String] The directory name to search for (e.g., '.git', 'node_modules')
  # @param mindepth [Integer] Minimum search depth (default: 1)
  # @param maxdepth [Integer] Maximum search depth (default: 6)
  # @param filter [String, Regexp, nil] Optional regex to filter results by full path
  # @param prune_dirs [Array<String>] Directories to exclude from search (default: [])
  # @param skip_symlinks [Boolean] Skip directories that are symlinks (default: true)
  # @param transform_result [Proc, nil] Optional proc to transform each result path
  #   before adding to results. Receives the matched path, should return the
  #   transformed path. For example, to get parent directories of matched items:
  #   ->(path) { File.dirname(path) }
  # @return [Array<String>] Matching directory paths, deduplicated and sorted alphabetically
  #
  # @example Find all .git directories
  #   git_dirs = CollectionProcessor.find_directories_matching(
  #     folders: '/Users/me/projects',
  #     name_pattern: '.git'
  #   )
  #
  # @example Find git repo roots (parents of .git dirs)
  #   repo_roots = CollectionProcessor.find_directories_matching(
  #     folders: '/Users/me/projects',
  #     name_pattern: '.git',
  #     transform_result: ->(git_dir) { File.dirname(git_dir) }
  #   )
  #
  # @example With pruning and filtering
  #   repos = CollectionProcessor.find_directories_matching(
  #     folders: ['/Users/me/work', '/Users/me/oss'],
  #     name_pattern: '.git',
  #     prune_dirs: %w[node_modules .cache],
  #     filter: /my-project/,
  #     maxdepth: 4
  #   )
  def find_directories_matching(folders:, name_pattern:, mindepth: 1, maxdepth: 6, filter: nil, prune_dirs: [], skip_symlinks: true, transform_result: nil)
    # Convert Pathname objects to strings, rejecting nil and empty strings
    folders = Array(folders).compact.map(&:to_s).reject { |f| f.empty? }
    prune = Array(prune_dirs)

    # Build prune expression: ( -name dir1 -o -name dir2 ... ) -prune -o
    prune_expr = prune.empty? ? [] : ['('] + prune.flat_map { |d| ['-o', '-name', d] }.drop(1) + [')', '-prune', '-o']

    find_cmd = [
      'find', *folders,
      '-mindepth', mindepth.to_s,
      '-maxdepth', maxdepth.to_s,
      *prune_expr,
      '-type', 'd',
      '-name', name_pattern,
      '-print'
    ]

    seen = {}
    results = []
    filter_re = filter.is_a?(Regexp) ? filter : (filter ? Regexp.new(filter) : nil)

    IO.popen(find_cmd, err: File::NULL) do |io|
      io.each_line do |line|
        path = line.chomp
        next if filter_re && !path.match?(filter_re)
        next if skip_symlinks && File.symlink?(path)

        # Apply transform if provided (e.g., get parent directory)
        final_path = transform_result ? transform_result.call(path) : path
        next if seen[final_path]

        seen[final_path] = true
        results << final_path
      end
    end

    # Return sorted for deterministic output. Callers may re-sort by different
    # criteria (e.g., depth) for their specific needs.
    results.sort
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
  # @yield [item, idx, total] Processes a single item. The block receives the
  #   item, its 1-based index, and the total count. Should return truthy on
  #   success, falsy on failure. Exceptions are caught and recorded as errors.
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
  #     system('git', '-C', repo_path, 'status')
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
  #     system('mise', '-C', dir, 'install')
  #   end
  def process_items(items, item_name_proc: nil, operation_desc: nil, skip_proc: nil, dry_run: false)
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
      if skip_proc && skip_proc.call(item)
        skipped_count += 1
        next
      end

      # Build progress message with aligned counters
      idx_str = format_counter(one_based_idx, counter_width)
      progress = "[#{idx_str.purple} of #{total_str.purple}]"
      if operation_desc
        Logging.info "#{progress} #{operation_desc.yellow}: '#{item_name.cyan}'"
      else
        Logging.info "#{progress} '#{item_name.cyan}'"
      end

      if dry_run
        Logging.info "  [DRY RUN] Would process '#{item_name.cyan}'"
        successful << item_name
        next
      end

      begin
        # Call the user's block with item, idx (1-based), and total
        result = yield(item, one_based_idx, total)

        if result
          successful << item_name
        else
          failed << item_name
          Logging.record_error("Processing failed for '#{item_name.cyan}'")
        end
      rescue StandardError => e
        failed << item_name
        Logging.record_error("Exception processing '#{item_name.cyan}': #{e.message}")
      end
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
