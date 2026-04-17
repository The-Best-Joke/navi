#!/usr/bin/env bash
# wiki-behavior-reminder.sh — Claude Code Stop hook.
# If the session changed behavior code but no .md file, blocks Stop with a reminder.
# Escape hatch: appending a one-line entry to docs/wiki-log.md always satisfies the hook.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 0

# Enumerate all dirty files (modified + untracked, excluding ignored).
mapfile -t changed < <(git status --porcelain -uall 2>/dev/null | awk '{print $NF}')
[[ ${#changed[@]} -eq 0 ]] && exit 0

touched_behavior=false
touched_docs=false

for f in "${changed[@]}"; do
  case "$f" in
    api/app/*)
      touched_behavior=true ;;
  esac
  case "$f" in
    *.md)
      touched_docs=true ;;
  esac
done

if $touched_behavior && ! $touched_docs; then
  cat >&2 <<'EOF'
WIKI REMINDER: this session changed behavior code without updating any .md file.

Watched paths: api/app/

If the change introduces new behavior, conventions, gotchas, decisions, or rules:
  → update the relevant doc (api/TUI.md, PROJECT_ARCHITECTURE.md, TUI.md)
  → append a short entry to docs/wiki-log.md

If the change has no doc impact (routine bug fix, refactor, formatting):
  → append a one-line escape entry to docs/wiki-log.md, e.g.
    "- claude: chore(wiki): noop — refactored X with no behavior change"

This reminder will not fire again once docs/wiki-log.md is updated in this session.
See docs/wiki-schema.md for the full loop.
EOF
  exit 2
fi

exit 0
