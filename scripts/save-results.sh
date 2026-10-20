#!/usr/bin/env bash
# save-results.sh — merge evaluated skills into results.json with UTC evaluated_at
# Usage: save-results.sh RESULTS_JSON <<< "$EVAL_JSON"
#
# stdin: { "skills": { "skill-key": { ... } }, "mode"?: "full"|"quick", "batch_progress"?: {...} }
# Each skill object may include: path, verdict, reason, mtime, score, dimensions (object), etc.
# Per-skill keys are shallow-merged: existing[key] + incoming[key] for each skill id.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

RESULTS_JSON="${1:-}"

if [[ -z "$RESULTS_JSON" ]]; then
  echo "Error: RESULTS_JSON argument required" >&2
  echo "Usage: save-results.sh RESULTS_JSON <<< \"\$EVAL_JSON\"" >&2
  exit 1
fi

EVALUATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

input_json=$(cat)
if ! echo "$input_json" | jq empty 2>/dev/null; then
  echo "Error: stdin is not valid JSON" >&2
  exit 1
fi

if [[ ! -f "$RESULTS_JSON" ]]; then
  echo "$input_json" | jq --arg ea "$EVALUATED_AT" \
    '. + { evaluated_at: $ea }' >"$RESULTS_JSON"
  exit 0
fi

tmp=$(mktemp "${RESULTS_JSON}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

jq -s \
  --arg ea "$EVALUATED_AT" \
  '.[0] as $existing | .[1] as $new |
   ($new.skills // {}) as $in |
   ($existing.skills // {}) as $old |
   (reduce ($in | keys_unsorted[]) as $k ($old; .[$k] = (($old[$k] // {}) + $in[$k]))) as $merged |
   $existing |
   .evaluated_at = $ea |
   .skills = $merged |
   if ($new | has("mode")) then .mode = $new.mode else . end |
   if ($new | has("batch_progress")) then .batch_progress = $new.batch_progress else . end' \
  "$RESULTS_JSON" <(echo "$input_json") >"$tmp"

mv "$tmp" "$RESULTS_JSON"
