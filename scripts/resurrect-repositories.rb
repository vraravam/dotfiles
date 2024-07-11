#!/usr/bin/env ruby

# file location: <anywhere; but advisable in the PATH>

require "#{__dir__}/utilities/string.rb"

if ARGV.length != 2 || ARGV[0] == '--help' || !['-r', '-c'].include?(ARGV[0])
  puts "This script resurrects or flags for backup all known repositories in the 'dev' folder"
  puts "#{'Usage:'.pink} #{__FILE__} -<r/c> <config-filename>".yellow
  puts "  #{'-r'.green} resurrects 'known' codebases (usually on fresh laptop)"
  puts "  #{'-c'.green} verifies 'known' codebases"
  puts 'Environment variables:'.yellow
  puts "  #{"FILTER".light_blue} can be used to apply the operation to a subset of codebases (will match on folder or repo name)"
  puts "  #{'REF_FOLDER'.light_blue} can be used to apply a filter when verifying against a specific yaml file that might not contain all the repos in your system"
  exit(0)
end

require 'fileutils'
require 'yaml'

def justify(num)
  num.to_s.rjust(2, ' ')
end

def resurrect(repo, idx, total)
  folder = repo['folder'].strip
  env_var_name = folder[/.*\$\{(.*)}/, 1]
  folder.gsub!("${#{env_var_name}}", ENV[env_var_name]) if !env_var_name.nil? && !env_var_name.empty?
  folder = File.expand_path(folder)

  puts "***** Resurrecting [#{justify(idx + 1)} of #{justify(total)}]: #{folder} *****".green
  # Debugging with a different folder name
  # folder.sub!('dev/', 'dev2/')
  FileUtils.mkdir_p(folder)
  Dir.chdir(folder) do
    puts "Cloning from: #{repo['remote'].yellow} into #{Dir.pwd.yellow}"
    if Dir.exist?('.git')
      puts 'Already an existing git repo with the following remotes: '
      system('git remote -vv')
    else
      system("git clone -q '#{repo['remote']}' .") || abort("Couldn't clone the repo since the folder is not empty; aborting")
    end
    Array(repo['other_remotes']).each do |name, remote|
      system("git remote add #{name} '#{remote}'") unless system("git remote | grep #{name} 2>&1 >/dev/null")
    end if repo['other_remotes']
    system('git fetch -q --all --tags')
    Array(repo['post_clone']).each { |step| system(step) } if repo['post_clone']
  end
end

def apply_filter(repos, filter)
  filter.empty? ? repos : repos = repos.select{ |repo| (repo.is_a?(String) ? repo : repo['folder']) =~ /#{filter}/i}
end

filter = (ENV['FILTER'] || '').strip
puts "Using filter: #{filter.green}" if filter.length > 0
yml_file = File.expand_path(ARGV[1])
puts "Using config file: #{yml_file.green}"
repositories = YAML.load_file(yml_file).select{ |repo| repo['active']}
repositories = apply_filter(repositories, filter)
if ARGV[0] == '-r'
  puts "Running operation: #{'resurrection'.green}"
  repositories.each_with_index { |repo, idx| resurrect(repo, idx, repositories.length) }
elsif ARGV[0] == '-c'
  puts "Running operation: #{'verification'.green}"
  yml_folders = repositories.map{ |repo| repo['folder']}.compact.sort

  local_folders = Dir.glob('./**/.git').map{|r| r.sub('/.git', '')[2..-1]}.compact # remove the beginning './'
  local_folders = apply_filter(local_folders, filter).compact.sort

  # Note: Since I always use relative path from the home folder
  local_folders = local_folders.map {|folder| "#{ENV["HOME"]}/#{folder}"}

  if (ENV['REF_FOLDER'])
    reference_folder = ENV['REF_FOLDER']
    yml_folders = apply_filter(yml_folders, reference_folder)
    local_folders = apply_filter(local_folders, reference_folder)
  end

  diff_repos = local_folders - yml_folders | yml_folders - local_folders
  if diff_repos.any?
    puts "Please correlate the following #{diff_repos.length} differences projects manually:\n#{diff_repos.join("\n")}".red
    exit(-1)
  else
    puts 'Everything is kosher!'.green
  end
end
