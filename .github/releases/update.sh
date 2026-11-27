#!/usr/bin/env bash
# Rewrites the list between the release markers in a README: the latest
# published release of each active repository the README lists as
# '- [Name](https://github.com/yungSNAT/Name)', newest first, dated.
# Rows marked '(archived)' are skipped without querying the API; a repository
# that also has an unmarked row is still listed.
# A listed repository with no published release is named on stderr and left
# out; any other API failure stops the script before the README is written.
# Shell, not Rust: the profile's only other code is shell, and the workflow
# runs this with no build step. Needs an authenticated gh and GNU date.
set -euo pipefail
export LC_ALL=C

readme=${1:?usage: update.sh README.md}
script_dir=$(cd "$(dirname "$0")" && pwd)
bullet_repos="$script_dir/../lib/bullet-repos.awk"
if [ ! -f "$bullet_repos" ]; then
  echo "::error::Missing $bullet_repos." >&2
  exit 2
fi
start='<!-- releases:start -->'
end='<!-- releases:end -->'

# Exactly one start marker, then exactly one end marker.
if ! awk -v s="$start" -v e="$end" '
  { sub(/\r$/, "") }
  $0 == s { ns++; if (ne) bad = 1 }
  $0 == e { ne++ }
  END { exit !(ns == 1 && ne == 1 && !bad) }' "$readme"; then
  echo "::error::$readme needs one '$start' line followed by one '$end' line." >&2
  exit 2
fi

repos=$(awk -f "$bullet_repos" -v only_active=1 "$readme")
if [ -z "$repos" ]; then
  echo "::error::$readme lists no yungSNAT repository." >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

while read -r name; do
  if out=$(gh api "repos/yungSNAT/$name/releases/latest" --jq '[.published_at, .tag_name, .html_url] | @tsv' 2>"$work/err"); then
    printf '%s\t%s\n' "$out" "$name" >>"$work/rows"
  elif grep -qF '(HTTP 404)' "$work/err" && gh api "repos/yungSNAT/$name" --jq .id >/dev/null; then
    echo "$name: no published release" >&2
  else
    cat "$work/err" >&2
    echo "::error::Could not read $name's latest release." >&2
    exit 1
  fi
done <<<"$repos"

touch "$work/rows"
sort -r "$work/rows" | while IFS=$'\t' read -r published tag url name; do
  # read merges adjacent tabs, so an empty field leaves the last one empty.
  if [ -z "$published" ] || [ -z "$tag" ] || [ -z "$url" ] || [ -z "$name" ]; then
    echo "::error::A latest release lacks a date, tag or URL: $published $tag $url $name" >&2
    exit 1
  fi
  # A backslash here is @tsv's escape for a tab or newline in the URL.
  if [[ $url != "https://github.com/yungSNAT/$name/releases/"* || $url =~ [[:space:]\<\>\\] ]]; then
    echo "::error::$name's release URL is not a plain link: $url" >&2
    exit 1
  fi
  # An assignment, so a date that does not parse stops the script.
  day=$(date -u -d "$published" '+%-d %b %Y')
  # Backslash-escape Markdown and entities in the link text; percent-encode
  # parentheses and ampersands in the URL.
  label=$(printf '%s %s' "$name" "$tag" | sed 's/[][\\`*_~<>&]/\\&/g')
  url=${url//&/%26}
  url=${url//(/%28}
  printf -- '- %s: [%s](%s)\n' "$day" "$label" "${url//)/%29}"
done >"$work/list"

awk -v s="$start" -v e="$end" -v list="$work/list" '
  { marker = $0; sub(/\r$/, "", marker) }
  marker == s {
    print
    cr = substr($0, length(s) + 1)
    while ((getline line < list) > 0) print line cr
    skip = 1
    next
  }
  marker == e { skip = 0 }
  !skip' "$readme" >"$work/readme"
cat "$work/readme" >"$readme"
