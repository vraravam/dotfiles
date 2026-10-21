# file location: ${DOTFILES_DIR}/scripts/shared/git-common.sh
#
# Shared helpers for the external git subcommands in ${DOTFILES_DIR}/scripts (git-cc, git-fo,
# git-maintain, git-migrate-reftable, git-unshallow, git-upreb). SOURCED, never executed. Plain
# POSIX sh and dependency-free on purpose -- no .shellrc -- because these commands must work from
# cron and before the dotfiles shell environment exists. Each command locates this file relative
# to its own real path (following symlinks), so it works however the command was put on PATH.
#
# Functions and the globals they set:
#   resolve_dir "$@"      sets 'dir' and 'dir_shift'. The first argument is the repo directory
#                         unless it is empty or starts with '-' (a flag); otherwise the directory
#                         is the work tree's top level ('.' outside a repo). The caller then does
#                         'shift "${dir_shift}"' so "$@" holds only the flags. The default case
#                         also sets 'git_common' with the same single 'git rev-parse' call.
#   git_common_dir <dir>  sets 'git_common': the absolute path of the repository's common git
#                         directory (objects, packed refs, config, modules). Unlike '<dir>/.git',
#                         this is correct when '.git' is a FILE -- a submodule or a linked worktree.
#                         No-op if resolve_dir already set it.
#   is_shallow <dir>      succeeds if the repo is a shallow clone.
#   is_partial <dir>      succeeds if ANY remote is a promisor remote (partial/blobless clone). This
#                         stays true until drop_promisor_config removes the settings -- a fully
#                         backfilled blobless clone keeps them on its own.
#   has_wide_refspecs <dir>   succeeds if every remote already fetches all branches.
#   has_missing_objects <dir> succeeds if any object is missing locally (refs, reflogs, index) or
#                         that cannot be determined.
#   drop_promisor_config <dir> removes the promisor settings of a fully backfilled partial clone.
#   dispatch_override <command> <dir> [args...]
#                         runs the per-repo override ${PERSONAL_BIN_DIR}/<command>-<dir basename>.rb
#                         (preferred) or .sh if one exists and overrides are not being skipped.
#                         Succeeds (and sets 'override_status') if an override ran; fails if there
#                         was none, in which case the caller runs its default implementation.
#                         Mirrors GitOverrides.script_for (scripts/utilities/git_overrides.rb),
#                         which stays authoritative for the naming convention.
#   make_tmp              creates one temp directory in 'tmp_dir' and removes it when the script
#                         exits for any reason, including an interrupt.

resolve_dir() {
  git_common=''
  case "${1:-}" in
  -* | '')
    dir_shift=0
    _gc_nl='
'
    _gc_out="$(git rev-parse --show-toplevel --git-common-dir 2>/dev/null)" || _gc_out=''
    if [ -n "${_gc_out}" ]; then
      dir="${_gc_out%%"${_gc_nl}"*}"
      git_common="${_gc_out#*"${_gc_nl}"}"
      # '--git-common-dir' is relative to the current directory, not to the top level.
      case "${git_common}" in /*) ;; *) git_common="${PWD}/${git_common}" ;; esac
    else
      dir=.
    fi
    ;;
  *)
    dir_shift=1
    dir="${1}"
    ;;
  esac
}

git_common_dir() {
  if [ -n "${git_common:-}" ]; then return 0; fi
  git_common="$(git -C "${1}" rev-parse --git-common-dir 2>/dev/null)" || git_common=''
  case "${git_common}" in
  '') git_common="${1}/.git" ;;
  /*) ;;
  *) git_common="${1}/${git_common}" ;;
  esac
}

is_shallow() {
  [ "$(git -C "${1}" rev-parse --is-shallow-repository 2>/dev/null)" = true ]
}

is_partial() {
  case "$(git -C "${1}" config --get-regexp '^remote\..*\.promisor$' 2>/dev/null)" in
  *' true'*) return 0 ;;
  esac
  return 1
}

# Succeeds if every remote already fetches all branches ('+refs/heads/*:refs/remotes/<remote>/*'),
# i.e. 'git fo' has nothing left to widen. A clone made with --single-branch fails this until
# 'git fo' has run once (it calls 'git remote set-branches <remote> "*"').
has_wide_refspecs() {
  _hwr_lines="$(git -C "${1}" config --get-regexp '^remote\..*\.fetch$' 2>/dev/null)"
  for _hwr_remote in $(git -C "${1}" remote 2>/dev/null); do
    case "${_hwr_lines}" in
    *"remote.${_hwr_remote}.fetch +refs/heads/*:refs/remotes/${_hwr_remote}/*"*) ;;
    *) return 1 ;;
    esac
  done
  return 0
}

# Succeeds if some object is missing locally -- reachable from any ref, any reflog entry or the
# index -- or if that cannot be determined (any 'rev-list' failure counts as "missing"), so a
# caller deciding whether a partial clone is complete can only ever err on the safe side.
# Purely local, no network: '--missing=print' lists the gaps without fetching anything. It walks
# every reachable object, so the time scales with the repository: ~10-300ms for ordinary repos,
# 25-50s for a 488k-commit one.
has_missing_objects() {
  _hmo_file="$(mktemp)" || return 0
  if ! git -C "${1}" rev-list --objects --all --reflog --indexed-objects --missing=print >"${_hmo_file}" 2>/dev/null; then
    rm -f "${_hmo_file}"
    return 0
  fi
  grep -q '^?' "${_hmo_file}"
  _hmo_status=$?
  rm -f "${_hmo_file}"
  return "${_hmo_status}"
}

# Turns a fully backfilled partial clone into a normal one by removing its promisor settings
# (remote.<name>.promisor / .partialclonefilter and extensions.partialClone). The caller must
# have verified that nothing is missing (has_missing_objects): afterwards git no longer lazy
# fetches, so a missing object would be an error instead of a transparent download.
drop_promisor_config() {
  for _dpc_remote in $(git -C "${1}" config --get-regexp '^remote\..*\.promisor$' 2>/dev/null | sed 's/^remote\.\(.*\)\.promisor .*/\1/'); do
    git -C "${1}" config --unset-all "remote.${_dpc_remote}.promisor"
    git -C "${1}" config --unset-all "remote.${_dpc_remote}.partialclonefilter" 2>/dev/null || true
  done
  git -C "${1}" config --unset-all extensions.partialClone 2>/dev/null || true
}

dispatch_override() {
  _gc_cmd="${1}"
  _gc_dir="${2}"
  shift 2
  if [ -n "${_GIT_OVERRIDE_SKIP:-}" ]; then return 1; fi
  _gc_abs="$(cd "${_gc_dir}" && pwd)" || return 1
  _gc_name="${_gc_abs##*/}"
  for _gc_ext in rb sh; do
    _gc_script="${_gc_cmd}-${_gc_name}.${_gc_ext}"
    [ -x "${_gc_script}" ] || continue
    section_header "Using: '$(cyan $(which "${_gc_script}"))'"
    if [ "${_gc_ext}" = rb ]; then
      (cd "${_gc_dir}" && _GIT_OVERRIDE_SKIP=1 "${_gc_script}" "$@")
    else
      (cd "${_gc_dir}" && _GIT_OVERRIDE_SKIP=1 /bin/zsh -l "${_gc_script}" "$@")
    fi
    override_status=$?
    return 0
  done
  return 1
}

make_tmp() {
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}
