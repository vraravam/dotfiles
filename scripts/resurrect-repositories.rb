#!/usr/bin/env ruby

# file location: <anywhere; but advisable in the PATH>

require 'tempfile'
require "#{__dir__}/utilities/string.rb"

def usage(exit_code = -1)
  puts 'This script resurrects or flags for backup all known repositories in the current machine'
  puts "#{'Usage:'.pink} #{__FILE__} [-g <folder-to-generate-config-for>] [-r <config-filename>] [-c <config-filename>]".yellow
  puts "  #{'-g'.green} generates the configuration contents onto the stdout for codebases (usually on current laptop). #{"Please note that this option will not handle 'post_clone' commands in the generated yaml structure".red}"
  puts "  #{'-r'.green} resurrects 'known' codebases (usually on fresh laptop)"
  puts "  #{'-c'.green} verifies 'known' codebases"
  puts 'Environment variables:'.yellow
  puts "  #{'FILTER'.light_blue} can be used to apply the operation to a subset of codebases (will match on folder or repo name)"
  puts "  #{'REF_FOLDER'.light_blue} can be used to apply a filter when verifying against a specific yaml file that might not contain all the repos in your system"
  exit(exit_code)
end

usage(0) if ARGV[0] == '--help'
usage if ARGV.length != 2 || !['-g', '-r', '-c'].include?(ARGV[0])

require 'fileutils'
require 'yaml'

# frozen string constants (defined for performance)
ORIGIN_NAME = 'origin'.freeze
FOLDER_KEY_NAME = 'folder'.freeze
OTHER_REMOTES_KEY_NAME = 'other_remotes'.freeze
POST_CLONE_KEY_NAME = 'post_clone'.freeze

# utility functions
def nil_or_empty?(val)
  val.nil? || val.empty?
end

def stringify(hash)
  hash.map { |k, v| [k.to_s, v.is_a?(Hash) ? stringify(v) : v] }.to_h
end

def justify(num)
  num.to_s.rjust(2, ' ')
end

def find_and_replace_env_var(folder)
  env_var_name = folder[/.*\$\{(.*)}/, 1]
  nil_or_empty?(env_var_name) ? folder : folder.gsub("${#{env_var_name}}", ENV[env_var_name])
end

def git_repo?(folder)
  Dir.exist?("#{folder}/.git")
end

def find_git_remote_url(git_cmd, remote_name)
  `#{git_cmd} config remote.#{remote_name}.url`.strip
end

def find_git_repos_from_disk(path)
  stderr = Tempfile.new
  begin
    paths = `find '#{path}' -name .git -type d -not -regex '.*/\\..*/\\.git' -exec dirname {} \\; 2>#{stderr.path}`
    unless File.zero?(stderr.path)
      puts "WARNING: Following errors occurred when traversing directories for git repositories:".yellow
      puts `cat #{stderr.path}`.yellow
    end
    return paths.split("\n").sort
  ensure
    stderr.close
    stderr.unlink
  end
end

def read_git_repos_from_file(filename)
  yml_file = File.expand_path(filename)
  puts "Using config file: #{yml_file.green}"
  repositories = YAML.load_file(yml_file).select { |repo| repo['active'] }
  repositories.each do |repo|
    repo[FOLDER_KEY_NAME] = find_and_replace_env_var(repo[FOLDER_KEY_NAME].strip)
  end
  repositories
end

def apply_filter(repos, filter)
  return repos if nil_or_empty?(filter)

  repos.select { |repo| find_and_replace_env_var(repo.is_a?(String) ? repo : repo[FOLDER_KEY_NAME]).strip =~ /#{filter}/i }
end

# main functions
def generate_each(git_dir)
  git_cmd = "git -C #{git_dir}"
  remotes = `#{git_cmd} remote`
  hash = { folder: git_dir, remote: find_git_remote_url(git_cmd, ORIGIN_NAME), active: true }
  remotes.split.compact.each do |remote|
    next if nil_or_empty?(remote) || nil_or_empty?(remote.strip)

    remote.strip!
    next if remote == ORIGIN_NAME

    hash[OTHER_REMOTES_KEY_NAME] ||= {}
    hash[OTHER_REMOTES_KEY_NAME][remote] = find_git_remote_url(git_cmd, remote)
  end
  hash.delete(OTHER_REMOTES_KEY_NAME) if nil_or_empty?(hash[OTHER_REMOTES_KEY_NAME])
  stringify(hash)
end

def resurrect_each(repo, idx, total)
  folder = repo[FOLDER_KEY_NAME]
  FileUtils.mkdir_p(folder)

  puts "***** Resurrecting [#{justify(idx + 1)} of #{justify(total)}]: #{folder} *****".green
  git_cmd = "git -C #{folder}"
  if git_repo?(folder)
    puts 'Already an existing git repo with the following remotes:'.yellow
    system("#{git_cmd} remote -vv")
  else
    puts "Cloning from: #{repo['remote'].yellow} into #{folder.yellow}"
    system("#{git_cmd} clone -q '#{repo['remote']}' .") || abort("Couldn't clone the repo since the folder is not empty; aborting")
  end

  Array(repo[OTHER_REMOTES_KEY_NAME]).each do |name, remote|
    system("#{git_cmd} remote add #{name} #{remote}") if find_git_remote_url(git_cmd, name).empty?
  end if repo[OTHER_REMOTES_KEY_NAME]

  system("#{git_cmd} fetch -q --all --tags")

  Array(repo[POST_CLONE_KEY_NAME]).each do |step|
    Dir.chdir(folder) { system(step) }
  end if repo[POST_CLONE_KEY_NAME]
end

def verify_all(repositories, filter)
  ref_folder = File.expand_path(ENV['REF_FOLDER']) if ENV['REF_FOLDER']
  yml_folders = repositories.map { |repo| repo[FOLDER_KEY_NAME] }.compact.sort.uniq
  yml_folders = apply_filter(yml_folders, ref_folder) if ref_folder

  local_folders = find_git_repos_from_disk(ref_folder || ENV['HOME'])
  local_folders = apply_filter(local_folders, filter).compact.sort.uniq

  diff_repos = local_folders - yml_folders | yml_folders - local_folders
  if diff_repos.any?
    puts "Please correlate the following #{diff_repos.length} differences projects manually:\n#{diff_repos.join("\n")}".red
    exit(-1)
  else
    puts 'Everything is kosher!'.green
  end
end

# main program
filter = (ENV['FILTER'] || '').strip
puts "Using filter: #{filter.green}" unless filter.empty?

case ARGV[0]
when '-g'
  puts "Running operation: #{'generation'.green}"
  discovery_dir = File.expand_path(ARGV[1])
  puts "Discovering repos under: #{discovery_dir.green}"
  repositories = find_git_repos_from_disk(discovery_dir)
  repositories = apply_filter(repositories, filter)
  puts repositories.map { |dir| generate_each(dir) }.to_yaml
when '-r'
  puts "Running operation: #{'resurrection'.green}"
  repositories = read_git_repos_from_file(ARGV[1])
  repositories = apply_filter(repositories, filter)
  repositories.each_with_index do |repo, idx|
    resurrect_each(repo, idx, repositories.length)
  end
when '-c'
  puts "Running operation: #{'verification'.green}"
  repositories = read_git_repos_from_file(ARGV[1])
  repositories = apply_filter(repositories, filter)
  verify_all(repositories, filter)
else
  usage
end
