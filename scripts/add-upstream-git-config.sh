#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script will check and add a new remote called 'upstream' to the specified git repo

type red &> /dev/null 2>&1 || source "${HOME}/.shellrc"
type section_header &> /dev/null 2>&1 || source "${HOME}/.shellrc"

usage() {
  echo "$(red 'Usage'): $(yellow "${1} <target-folder> <upstream-repo-owner>")"
  echo "  $(yellow 'target-folder')       --> The folder which has to be processed"
  echo "  $(yellow 'upstream-repo-owner') --> The upstream repo's owner"
  exit 1
}

[ $# -ne 2 ] && usage "${0}"

local target_folder="${1}"
local upstream_repo_owner="${2}"

section_header "Adding new upstream to: '$(yellow "${target_folder}")'"

git -C "${target_folder}" remote -vv | \grep "${upstream_repo_owner}2"
if [ $? -eq 0 ]; then
  warn "skipping setting new upstream remote for the repo in '$(yellow "${target_folder}")' since the existing remote(s) alerady point to the target owner"
  return
fi

existing_upstream="$(git -C "${target_folder}" config remote.upstream.url)"
if [ $? -eq 0 ]; then
  warn "remote 'upstream' already exists for the repo in '$(yellow "${target_folder}")'"
  return
fi

local origin_remote_url="$(git -C "${target_folder}" config remote.origin.url)"
if [[ "${origin_remote_url}" =~ 'git@' ]]; then
  local cloned_repo_owner="$(echo "${origin_remote_url}" | cut -d '/' -f1 | cut -d ':' -f2)"
elif [[ "${origin_remote_url}" =~ 'https:' ]]; then
  local cloned_repo_owner="$(echo "${origin_remote_url}" | cut -d '/' -f4)"
fi
local new_repo_url="$(echo "${origin_remote_url}" | sed "s/${cloned_repo_owner}/${upstream_repo_owner}/")"
git -C "${target_folder}" remote add upstream "${new_repo_url}"
success "Successfully set new upstream remote for the repo in '$(yellow "${target_folder}")'"
