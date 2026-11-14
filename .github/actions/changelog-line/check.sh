#!/usr/bin/env bash
# Fails when BASE...HEAD changes a path matching SHIPPED (less any matching
# EXCLUDE) without adding a non-blank line to CHANGELOG.md.
# Shell, not Rust: a composite action runs on the runner with no build step.
set -euo pipefail

: "${BASE:?BASE is required}" "${HEAD:?HEAD is required}" "${SHIPPED:?SHIPPED is required}" "${HEADING:?HEADING is required}"
EXCLUDE="${EXCLUDE:-}"

# -z prints every path unquoted (moved and non-ASCII paths included);
# --no-renames lists a moved file under its old path as well as its new one.
files=$(git diff -z --no-renames --name-only "$BASE...$HEAD" | tr '\0' '\n')

# grep exits 1 on no match and 2 on a bad pattern; only 1 is a clean result.
matched=$(grep -E -- "$SHIPPED" <<<"$files") || { status=$?; [ "$status" -eq 1 ] || exit "$status"; }
if [ -n "$EXCLUDE" ] && [ -n "$matched" ]; then
  matched=$(grep -vE -- "$EXCLUDE" <<<"$matched") || { status=$?; [ "$status" -eq 1 ] || exit "$status"; }
fi
if [ -z "$matched" ]; then
  echo "No shipped files changed."
  exit 0
fi

# Added lines follow the first hunk header, so the '+++' file header is never
# counted, even when an added line itself starts with '++'.
log=$(git diff --unified=0 --no-renames "$BASE...$HEAD" -- CHANGELOG.md)
if awk '/^@@/ { hunk = 1; next } hunk && /^\+/ && substr($0, 2) ~ /[^[:space:]]/ { found = 1 } END { exit !found }' <<<"$log"; then
  echo "CHANGELOG.md has a new line."
  exit 0
fi

printf 'Shipped files changed:\n%s\n' "$matched"
echo "::error file=CHANGELOG.md::This pull request changes shipped files but adds no line to CHANGELOG.md. Add one under ${HEADING}, or apply the skip-changelog label if users will not notice the change."
exit 1
