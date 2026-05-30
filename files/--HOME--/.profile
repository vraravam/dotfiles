# .profile is the POSIX login-shell fallback (loaded by bash/sh when zsh is not the login shell).
# Source .shellrc only — it is bash-compatible at the top level and provides all env vars.
# .aliases is zsh-only and must NOT be sourced here.
# Re-source guard is inside .shellrc itself — safe to call unconditionally.
source "${HOME}/.shellrc"
source "${HOME}/.cargo/env"
