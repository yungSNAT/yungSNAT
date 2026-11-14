#!/usr/bin/env bash
# Fails when BASE...HEAD changes a path matching SHIPPED (less any matching
# EXCLUDE) without adding a non-blank line to CHANGELOG.md.
# Shell, not Rust: a composite action runs on the runner with no build step.
set -euo pipefail

: "${BASE:?BASE is required}" "${HEAD:?HEAD is required}" "${SHIPPED:?SHIPPED is required}" "${HEADING:?HEADING is required}"
EXCLUDE="${EXCLUDE:-}"

# grep exits 1 on no match, the only non-zero status that is a clean result;
# 2 (a bad pattern or read error) ends the script with that status.
nomatch_ok() { [ "$1" -eq 1 ] || exit "$1"; }

# grep reads a newline in a pattern as 2 patterns, and an empty one matches
# everything, so a YAML block scalar's trailing newline would void the check.
for pattern in "$SHIPPED" "$EXCLUDE"; do
  if [[ $pattern == *$'\n'* ]]; then
    echo "::error::The shipped and exclude patterns must be one line each."
    exit 2
  fi
  # Checked up front, so a bad pattern fails even when nothing it would
  # filter has changed.
  if [ -n "$pattern" ]; then
    grep -E -- "$pattern" </dev/null || nomatch_ok $?
  fi
done

# The list stays NUL-separated, in files because bash drops NUL bytes from
# variables, so no path is split or read as binary: -z prints every path
# unquoted (non-ASCII and moved paths included), grep -a reads paths that are
# not valid UTF-8 as text, and --no-renames lists a moved file under its old
# path as well as its new one.
list=$(mktemp -d)
trap 'rm -rf "$list"' EXIT
git diff -z --no-renames --name-only "$BASE...$HEAD" >"$list/changed"
grep -azE -- "$SHIPPED" <"$list/changed" >"$list/shipped" || nomatch_ok $?
if [ -n "$EXCLUDE" ]; then
  grep -azvE -- "$EXCLUDE" <"$list/shipped" >"$list/kept" || nomatch_ok $?
  mv "$list/kept" "$list/shipped"
fi
if [ ! -s "$list/shipped" ]; then
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

echo "Shipped files changed:"
tr '\0' '\n' <"$list/shipped"
echo "::error file=CHANGELOG.md::This pull request changes shipped files but adds no line to CHANGELOG.md. Add one under ${HEADING}, or apply the skip-changelog label if users will not notice the change."
exit 1
