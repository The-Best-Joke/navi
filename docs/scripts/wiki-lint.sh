#!/usr/bin/env bash
# wiki-lint.sh — checks consistency of the navi documentation wiki.
# Exit codes: 0 clean, 1 warnings only, 2 errors.
# See docs/wiki-schema.md for the rules this script enforces.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SCHEMA="$ROOT/docs/wiki-schema.md"
INDEX="$ROOT/docs/wiki-index.md"
LOG="$ROOT/docs/wiki-log.md"
BACKFILL_LIST="$ROOT/docs/wiki-frontmatter-backfill.txt"

errors=0
warnings=0

err()  { printf 'ERROR: %s\n' "$*" >&2; errors=$((errors+1)); }
warn() { printf 'WARN:  %s\n' "$*" >&2; warnings=$((warnings+1)); }

# ---- 1. Wiki-meta files exist ------------------------------------------------
for f in "$SCHEMA" "$INDEX" "$LOG"; do
  [[ -f "$f" ]] || err "missing wiki-meta file: ${f#"$ROOT"/}"
done
if (( errors > 0 )); then
  exit 2
fi

# ---- 2. Discover .md files ---------------------------------------------------
# Excludes dependency dirs. .claude/ is intentionally INCLUDED so that slash
# commands get broken cross-ref checking — but excluded from orphan/front-matter
# checks via is_excluded_from_index (they are not wiki entries, just tool scripts).
mapfile -d '' all_md < <(find "$ROOT" -type f -name '*.md' \
  -not -path '*/node_modules/*' \
  -not -path '*/vendor/*' \
  -not -path '*/.git/*' \
  -not -path '*/.husky/*' \
  -print0)

# ---- 3. Backfill list (entries excused from front-matter check) --------------
backfill_paths=()
if [[ -f "$BACKFILL_LIST" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    backfill_paths+=("$line")
  done < "$BACKFILL_LIST"
fi

is_in_backfill() {
  local rel="$1" b
  for b in ${backfill_paths[@]+"${backfill_paths[@]}"}; do
    [[ "$b" == "$rel" ]] && return 0
  done
  return 1
}

# ---- 4. Orphaned wiki entries (warn) -----------------------------------------
is_excluded_from_index() {
  # Slash commands and agent config: cross-ref checked but not wiki entries
  [[ "$1" == .claude/* ]] && return 0
  case "$(basename "$1")" in
    CLAUDE.md|AGENTS.md|GEMINI.md) return 0 ;;
  esac
  return 1
}

for f in ${all_md[@]+"${all_md[@]}"}; do
  rel="${f#"$ROOT"/}"
  is_excluded_from_index "$rel" && continue
  if ! grep -qF -- "$rel" "$INDEX"; then
    warn "wiki entry not registered in docs/wiki-index.md: $rel"
  fi
done

# ---- 5. Broken cross-refs (error) --------------------------------------------
extract_link_targets() {
  # Strip fenced code blocks and inline code spans before extracting link targets.
  # Avoids false positives on illustrative examples.
  awk '
    /^```/ { in_fence = !in_fence; next }
    !in_fence {
      gsub(/`[^`]*`/, "")
      print
    }
  ' "$1" \
    | grep -oE '\]\([^)]+\)' \
    | sed -E 's/^\]\(([^)]+)\)$/\1/'
}

for f in ${all_md[@]+"${all_md[@]}"}; do
  rel="${f#"$ROOT"/}"
  dir="$(dirname "$f")"
  while IFS= read -r raw_target; do
    [[ -z "$raw_target" ]] && continue
    target="${raw_target%%#*}"
    [[ -z "$target" ]] && continue
    [[ "$target" =~ ^https?:// ]] && continue
    [[ "$target" =~ ^(mailto|tel): ]] && continue
    [[ "$target" == /* ]] && continue
    resolved="$dir/$target"
    if [[ ! -e "$resolved" ]]; then
      err "broken cross-ref in $rel → '$target' (resolved: ${resolved#"$ROOT"/})"
    fi
  done < <(extract_link_targets "$f")
done

# ---- 6. Index references nonexistent file (error) ----------------------------
mapfile -t indexed_paths < <(grep -oE '^- [^[:space:]]+\.md' "$INDEX" | sed 's/^- //')

for rel in ${indexed_paths[@]+"${indexed_paths[@]}"}; do
  if [[ ! -f "$ROOT/$rel" ]]; then
    err "docs/wiki-index.md references nonexistent file: $rel"
  fi
done

# ---- 7. Front-matter on indexed entries (error after backfill retirement) ----
has_front_matter_field() {
  local file="$1" field="$2" in_fm=0
  while IFS= read -r line; do
    if (( in_fm == 0 )); then
      [[ "$line" == "---" ]] && in_fm=1 || return 1
    else
      [[ "$line" == "---" ]] && return 1
      [[ "$line" =~ ^${field}: ]] && return 0
    fi
  done < "$file"
  return 1
}

for rel in ${indexed_paths[@]+"${indexed_paths[@]}"}; do
  abs="$ROOT/$rel"
  [[ -f "$abs" ]] || continue
  is_in_backfill "$rel" && continue
  for field in title category last_reviewed; do
    if ! has_front_matter_field "$abs" "$field"; then
      err "missing front-matter '$field' in $rel"
    fi
  done
done

# ---- 8. Stale last_reviewed (warn, >90 days) --------------------------------
today_epoch=$(date +%s)
for rel in ${indexed_paths[@]+"${indexed_paths[@]}"}; do
  abs="$ROOT/$rel"
  [[ -f "$abs" ]] || continue
  is_in_backfill "$rel" && continue
  date_str=$(awk '
    NR==1 { if ($0 != "---") exit 0; next }
    /^---$/ { exit 0 }
    /^last_reviewed:/ {
      sub(/^last_reviewed:[[:space:]]*/, "")
      print
      exit 0
    }
  ' "$abs")
  [[ -z "$date_str" ]] && continue
  if entry_epoch=$(date -d "$date_str" +%s 2>/dev/null); then
    age_days=$(( (today_epoch - entry_epoch) / 86400 ))
    if (( age_days > 90 )); then
      warn "stale last_reviewed in $rel: $date_str ($age_days days old)"
    fi
  fi
done

# ---- Result ------------------------------------------------------------------
if (( errors > 0 )); then
  printf '\nwiki-lint: %d error(s), %d warning(s)\n' "$errors" "$warnings" >&2
  exit 2
fi
if (( warnings > 0 )); then
  printf '\nwiki-lint: 0 errors, %d warning(s)\n' "$warnings" >&2
  exit 1
fi
echo "wiki-lint: clean"
exit 0
