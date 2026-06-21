# file location: ${HOME}/.gitconfig-delta.inc
#
# Delta-specific git configuration
# Conditionally included from ~/.gitconfig only when 'delta' is in PATH

[core]
  pager = delta
[interactive]
  diffFilter = delta --color-only
[delta]
  # Designed to emulate diff-so-fancy's default look and feel
  # ==========================================================
  file-style = "bold yellow"
  file-decoration-style = "yellow ul ol"
  file-added-label = "🟢 added:"
  file-modified-label = "🟠 modified:"
  file-removed-label = "🔴 deleted:"
  file-renamed-label = "🔵 renamed:"
  file-change-type-label-width = 0
  hunk-header-style = "file line-number syntax bold"
  hunk-header-decoration-style = "box"
  line-numbers = false
  side-by-side = false
  syntax-theme = "Monokai Extended"
  # Use "syntax <bg>" so whole removed/added lines keep syntax highlighting
  # on a coloured background. Plain "red"/"green" only set the foreground
  # colour, which loses syntax highlighting and looks flat on multi-line diffs.
  minus-style = "syntax #3D1A1A"
  # Emph bg must be brighter than the minus-style bg (#3D1A1A) so that
  # intra-line changed characters remain visually distinct from the base line.
  minus-emph-style = "bold #FF6B68 #6B2020"
  plus-style = "syntax #002800"
  # #006400 is visually distinct from the plus-style bg #002800 — no change needed.
  plus-emph-style = "bold #98FB98 #006400"
  # ansi fills the background colour to the full terminal width; "spaces"
  # (the default) only colours actual characters, leaving short lines unshaded.
  line-fill-method = ansi
  whitespace-error-style = "magenta reverse"
  navigate = true
  hyperlinks = true
  hyperlinks-file-link-format = "zed://file/{path}:{line}"
