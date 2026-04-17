#!/usr/bin/env bash
# wiki-stop-hook.sh — Claude Code PostToolUse hook.
# Runs wiki-lint.sh whenever Edit/Write/MultiEdit modified a .md file.
# On lint errors, returns JSON {"decision":"block","reason":"..."} so Claude must fix.
# On lint warnings, emits to stderr non-blocking. On clean, silent exit 0.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Hook input is JSON on stdin. Shape (relevant fields):
#   { "tool_name": "Edit", "tool_input": { "file_path": "/abs/path" }, ... }
input="$(cat)"

extract_string() {
  printf '%s' "$1" \
    | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" \
    | head -1 \
    | sed -E "s/.*\"([^\"]+)\"$/\1/"
}

tool_name=$(extract_string "$input" "tool_name")
file_path=$(extract_string "$input" "file_path")

# Filter: only Edit / Write / MultiEdit on a .md file
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac
[[ "$file_path" == *.md ]] || exit 0

# Run lint
lint_output=$("$ROOT/docs/scripts/wiki-lint.sh" 2>&1)
lint_exit=$?

case "$lint_exit" in
  0)
    exit 0
    ;;
  1)
    # warnings only — surface to stderr, don't block
    printf '%s\n' "$lint_output" >&2
    exit 0
    ;;
  2|*)
    # errors — emit blocking JSON for Claude to address
    json_escape() {
      local s="$1"
      s="${s//\\/\\\\}"
      s="${s//\"/\\\"}"
      s="${s//$'\n'/\\n}"
      s="${s//$'\r'/\\r}"
      s="${s//$'\t'/\\t}"
      printf '%s' "$s"
    }
    reason=$(printf 'wiki-lint failed after editing %s. Output:\n%s' "$file_path" "$lint_output")
    printf '{"decision":"block","reason":"%s"}\n' "$(json_escape "$reason")"
    exit 0
    ;;
esac
