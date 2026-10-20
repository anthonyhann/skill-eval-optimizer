#!/usr/bin/env bash
# quick-diff.sh — compare skill file mtimes against results.json evaluated_at
# Usage: quick-diff.sh RESULTS_JSON [CWD_SKILLS_DIR]
# Output: JSON array of {path,mtime,is_new} to stdout
#
# Environment:
#   SKILL_EVAL_OPTIMIZER_GLOBAL_DIR    default ~/.claude/skills
#   SKILL_EVAL_OPTIMIZER_PROJECT_DIR   default $PWD/.claude/skills

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

RESULTS_JSON="${1:-}"
CWD_SKILLS_DIR="${SKILL_EVAL_OPTIMIZER_PROJECT_DIR:-${2:-$PWD/.claude/skills}}"
GLOBAL_DIR="${SKILL_EVAL_OPTIMIZER_GLOBAL_DIR:-$HOME/.claude/skills}"

if [[ -z "$RESULTS_JSON" || ! -f "$RESULTS_JSON" ]]; then
  echo "Error: RESULTS_JSON not found: ${RESULTS_JSON:-<empty>}" >&2
  exit 1
fi

if [[ -n "$CWD_SKILLS_DIR" && -d "$CWD_SKILLS_DIR" && "$CWD_SKILLS_DIR" != */.claude/skills* ]]; then
  echo "Warning: CWD_SKILLS_DIR does not look like a .claude/skills path: $CWD_SKILLS_DIR" >&2
fi

evaluated_at=$(jq -r '.evaluated_at' "$RESULTS_JSON")

if [[ ! "$evaluated_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "Error: invalid or missing evaluated_at in $RESULTS_JSON: $evaluated_at" >&2
  exit 1
fi

known_paths=$(jq -r '.skills | to_entries[] | .value.path // empty' "$RESULTS_JSON" 2>/dev/null)

tmpdir=$(mktemp -d)
_cleanup() { rm -rf "$tmpdir"; }
trap _cleanup EXIT

i=0

process_dir() {
  local dir="$1"
  while IFS= read -r file; do
    local mtime dp is_new
    mtime=$(date -u -r "$file" +%Y-%m-%dT%H:%M:%SZ)
    dp="${file/#$HOME/~}"

    if echo "$known_paths" | grep -qxF "$dp"; then
      is_new="false"
      [[ "$mtime" > "$evaluated_at" ]] || continue
    else
      is_new="true"
    fi

    jq -n \
      --arg path "$dp" \
      --arg mtime "$mtime" \
      --argjson is_new "$is_new" \
      '{path:$path,mtime:$mtime,is_new:$is_new}' \
      > "$tmpdir/$i.json"
    i=$((i + 1))
  done < <(find "$dir" -name "*.md" -type f 2>/dev/null | sort)
}

[[ -d "$GLOBAL_DIR" ]] && process_dir "$GLOBAL_DIR"
[[ -n "$CWD_SKILLS_DIR" && -d "$CWD_SKILLS_DIR" ]] && process_dir "$CWD_SKILLS_DIR"

if [[ $i -eq 0 ]]; then
  echo "[]"
else
  jq -s '.' "$tmpdir"/*.json
fi
