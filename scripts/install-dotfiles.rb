#!/usr/bin/env ruby

# file location: <anywhere; but advisable in the PATH>

# This script is used to install the dotfiles from this repo/folder structure to the user's home folder
# It can be invoked from any location as long as its in the PATH (and you don't need to specify the fully qualified name while invoking it).
# It can handle nested files.
# If there is already a real file (not a symbolic link), then the script will move that file into this repo, and then create the corresponding symlink. This helps preserve the current settings from the user without forcefully overriding from my repo.
# Special handling (rename + copy instead of symlink) for '.gitattributes' and '.gitignore'
# To run it, just invoke by `install-dotfiles.rb` if this folder is already setup in the PATH

# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.

require "#{__dir__}/utilities/file.rb"
require "#{__dir__}/utilities/string.rb"
require 'fileutils'
require 'find'
require 'pathname'

def override_into_home_folder(file, dotfiles_dir_length)
  # git doesn't handle symlinks for its core configuration files, so files with 'custom.git' in their name have to be handled separately
  relative_file_name = file[dotfiles_dir_length..-1].gsub('custom.git', '.git')

  # process folder names having '--' in their name (strings within two pairs of '--' will refer to env variables)
  relative_file_name = relative_file_name.split('--').map { |entry| ENV.has_key?(entry) ? ENV[entry] : entry }.join if relative_file_name.include?('--')

  # since some env var might already contain the full path from the root...
  target_file_name = relative_file_name.start_with?(HOME) ? relative_file_name : File.join(HOME, relative_file_name)

  puts "Processing #{file.yellow} --> #{target_file_name.yellow}"

  # create the nested folder for the target
  FileUtils.mkdir_p(File.dirname(target_file_name))

  # move the real file into the repo folder
  FileUtils.mv(target_file_name, file, force: true, verbose: true) if File.exist?(target_file_name) && !File.symlink?(target_file_name)

  # copy/symlink from repo to target location
  file.match?(/custom\.git/) ? FileUtils.cp(file, target_file_name) : FileUtils.ln_sf(file, target_file_name)
end

puts 'Starting to install dotfiles'.green
HOME = ENV['HOME']
dotfiles_dir = File.expand_path(File.join(__dir__, '..', 'files'))
dotfiles_dir_length = dotfiles_dir.length + 1
Find.find(dotfiles_dir) do |file|
  next if File.directory?(file) || file.end_with?('.DS_Store') || file.match?(/\.zwc/)
  override_into_home_folder(file, dotfiles_dir_length)
end

ssh_folder = Pathname.new(HOME) + '.ssh'
default_ssh_config = ssh_folder + 'config'
if (ssh_folder + 'global_config').exist?
  default_ssh_config.touch unless default_ssh_config.exist?

  include_line = 'Include ~/.ssh/global_config'
  last_two_lines = default_ssh_config.readlines(chomp: true)[-2..-1] || []

  default_ssh_config.append("\n#{include_line}\n") unless last_two_lines.include?(include_line)
end

puts "Since the '.gitignore' and '.gitattributes' files are COPIED over, any new changes being pulled in (from a newer version of the upstream repo) need to be manually reconciled between this repo and your home and profiles folders".red
