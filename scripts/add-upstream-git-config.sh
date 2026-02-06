#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script will check and add a new remote called 'upstream' to the specified git repo
# TODO: Need to decide whether this script is best kept standalone or converted to a function that's used only within the fresh-install script (or) moved into the global .gitconfig so as to be used as a git alias. Each of these has their own pros & cons which need to be analyzed.

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shellrc only once if any required function is missing
type is_shellrc_sourced 2>&1 &> /dev/null || source "${HOME}/.shellrc"

usage() {
  echo "$(red 'Usage'): $(yellow "${1}") -d <target-folder> -u <upstream-repo-owner>"
  echo "  $(yellow '-d <target-folder>')       --> (mandatory) The folder which has to be processed"
  echo "  $(yellow '-u <upstream-repo-owner>') --> (mandatory) The upstream repo's owner"
  exit 1
}

local target_folder
local upstream_repo_owner

while getopts ":d:u:" opt; do
  case ${opt} in
    d)
      target_folder="${OPTARG}"
      ;;
    u)
      upstream_repo_owner="${OPTARG}"
      ;;
    \?)
      usage "${0##*/}"
      ;;
    :)
      echo "Invalid option: -${OPTARG} requires an argument" 1>&2
      usage "${0##*/}"
      ;;
  esac
done
shift $((OPTIND - 1))

if is_zero_string "${target_folder}" || is_zero_string "${upstream_repo_owner}"; then
  usage "${0##*/}"
fi

main() {
  section_header "$(yellow 'Adding new upstream to'): '$(purple "${target_folder}")'"

  if ! is_git_repo "${target_folder}"; then
    warn "'$(yellow "${target_folder}")' is not a git repo; Skipping!!!"
    return 0 # Success, nothing to do
  fi

  # Check if an 'upstream' remote already exists using 'git remote get-url'
  local existing_upstream
  if existing_upstream=$(git -C "${target_folder}" remote get-url upstream 2> /dev/null); then
    # If get-url succeeded, the remote exists.
    warn "Remote 'upstream' already exists for the repo in '$(yellow "${target_folder}")': '$(yellow "${existing_upstream}")'"
    return 0 # Success, nothing to do
  fi

  # Get the URL of the 'origin' remote using 'git remote get-url'
  local origin_remote_url
  # Capture output and check exit status separately for clarity
  origin_remote_url=$(git -C "${target_folder}" remote get-url origin 2> /dev/null)
  if [[ $? -ne 0 ]]; then
    error "Could not retrieve URL for remote 'origin' in '$(yellow "${target_folder}")'. Does the remote exist?"
  elif is_zero_string "${origin_remote_url}"; then
    # This case is less likely with get-url but check anyway
    error "Retrieved empty URL for remote 'origin' in '$(yellow "${target_folder}")'."
  fi

  local cloned_repo_owner host repo_path new_repo_url protocol

  # Parse the origin URL (SSH or HTTPS) to extract the current owner's username using regex
  if [[ "${origin_remote_url}" =~ ^git@([^:]+):([^/]+)/(.+)$ ]]; then
    # SSH format: git@host:owner/repo.git or git@host:owner/repo
    host="${match[1]}"
    cloned_repo_owner="${match[2]}"
    repo_path="${match[3]}"
    new_repo_url="git@${host}:${upstream_repo_owner}/${repo_path}"
  elif [[ "${origin_remote_url}" =~ ^https?://([^/]+)/([^/]+)/(.+)$ ]]; then
    # HTTPS format: https://host/owner/repo.git or https://host/owner/repo
    host="${match[1]}"
    cloned_repo_owner="${match[2]}"
    repo_path="${match[3]}"
    # Preserve http vs https
    protocol='https'
    [[ "${origin_remote_url}" =~ ^http:// ]] && protocol='http'
    new_repo_url="${protocol}://${host}/${upstream_repo_owner}/${repo_path}"
  else
    error "Cannot parse origin remote URL format: $(yellow "${origin_remote_url}")"
  fi
  # Ensure .git suffix for consistency when reconstructing
  [[ "${new_repo_url}" != *.git ]] && new_repo_url+='.git'

  # Check if the owners are the same
  if [[ "${cloned_repo_owner}" == "${upstream_repo_owner}" ]]; then
    warn "Origin owner ('$(yellow "${cloned_repo_owner}")') and upstream owner ('$(yellow "${upstream_repo_owner}")') are the same. No change needed for repo in '$(yellow "${target_folder}")'."
    return 0 # Exit successfully, no action needed
  fi

  # Add the upstream remote
  if ! git -C "${target_folder}" remote add upstream "${new_repo_url}"; then
    error "Failed to add upstream remote '$(yellow "${new_repo_url}")'"
  fi

  # Fetch the newly added remote
  if ! git -C "${target_folder}" fetch upstream; then
    error "Failed to fetch upstream remote '$(yellow "${new_repo_url}")' after adding it."
  fi

  success "Successfully added and fetched upstream remote '$(yellow "${new_repo_url}")' to repo in '$(yellow "${target_folder}")'"
}

# Execute the main function with all script arguments
main
