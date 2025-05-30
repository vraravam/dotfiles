#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script will check and add a new remote called 'upstream' to the specified git repo
# TODO: Need to decide whether this script is best kept standalone or converted to a function that's used only within the fresh-install script (or) moved into the global .gitconfig so as to be used as a git alias. Each of these has their own pros & cons which need to be analyzed.

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shellrc only once if any required function is missing
if ! type red &> /dev/null 2>&1 || ! type section_header &> /dev/null 2>&1 || ! type is_git_repo &> /dev/null 2>&1 || ! type warn &> /dev/null 2>&1 || ! type error &> /dev/null 2>&1 || ! type success &> /dev/null 2>&1 ; then
  source "${HOME}/.shellrc"
fi

usage() {
  echo "$(red 'Usage'): $(yellow "${1} <target-folder> <upstream-repo-owner>")"
  echo "  $(yellow 'target-folder')       --> The folder which has to be processed"
  echo "  $(yellow 'upstream-repo-owner') --> The upstream repo's owner"
  exit 1
}

main() {
  # Ensure exactly two arguments are passed to the main function
  [ $# -ne 2 ] && usage "${0##*/}" # Use basename of script in usage

  local target_folder="${1}"
  local upstream_repo_owner="${2}"

  section_header "Adding new upstream to: '$(yellow "${target_folder}")'"

  ! is_git_repo "${target_folder}" && error "'$(yellow "${target_folder}")' is not a git repo; Aborting!!!"

  # Check if an 'upstream' remote already exists using 'git remote get-url'
  local existing_upstream
  if existing_upstream=$(git -C "${target_folder}" remote get-url upstream 2>/dev/null); then
    # If get-url succeeded, the remote exists.
    warn "Remote 'upstream' already exists for the repo in '$(yellow "${target_folder}")': '$(yellow "${existing_upstream}")'"
    return 0 # Success, nothing to do
  fi

  # Get the URL of the 'origin' remote using 'git remote get-url'
  local origin_remote_url
  # Capture output and check exit status separately for clarity
  origin_remote_url=$(git -C "${target_folder}" remote get-url origin 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    error "Could not retrieve URL for remote 'origin' in '$(yellow "${target_folder}")'. Does the remote exist?"
  elif ! is_non_zero_string "${origin_remote_url}"; then
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
    # Ensure .git suffix for consistency when reconstructing
    [[ "${repo_path}" != *.git ]] && repo_path+=".git"
    new_repo_url="git@${host}:${upstream_repo_owner}/${repo_path}"
  elif [[ "${origin_remote_url}" =~ ^https?://([^/]+)/([^/]+)/(.+)$ ]]; then
    # HTTPS format: https://host/owner/repo.git or https://host/owner/repo
    host="${match[1]}"
    cloned_repo_owner="${match[2]}"
    repo_path="${match[3]}"
    # Ensure .git suffix for consistency when reconstructing
    [[ "${repo_path}" != *.git ]] && repo_path+=".git"
    # Preserve http vs https
    protocol="https"
    [[ "${origin_remote_url}" =~ ^http:// ]] && protocol="http"
    new_repo_url="${protocol}://${host}/${upstream_repo_owner}/${repo_path}"
  else
    error "Cannot parse origin remote URL format: $(yellow "${origin_remote_url}")"
  fi

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
main "$@"
