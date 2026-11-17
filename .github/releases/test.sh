#!/usr/bin/env bash
# Runs update.sh against a stub gh. Exits non-zero on any failure.
set -euo pipefail

update="$(cd "$(dirname "$0")" && pwd)/update.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# The stub answers 'gh api repos/yungSNAT/<name>[/releases/latest] ...' from
# $work/fixtures/<name>: a TSV line as update.sh's --jq would print it, or
# 404 (no release), 500 (a failure) or missing (no such repository).
mkdir -p "$work/bin" "$work/fixtures"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
path=${2#repos/yungSNAT/}
name=${path%/releases/latest}
answer=$(cat "$FIXTURES/$name" 2>/dev/null || echo missing)
if [ "$path" = "$name" ]; then
  [ "$answer" != missing ] && { echo 1; exit 0; }
  answer=404
elif [ "$answer" = missing ]; then
  answer=404
fi
case $answer in
  404) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
  500) echo 'gh: Server Error (HTTP 500)' >&2; exit 1 ;;
  *) printf '%s\n' "$answer" ;;
esac
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" FIXTURES="$work/fixtures"

fixture() { printf '%s\n' "$2" >"$FIXTURES/$1"; }
fixture Old $'2026-11-12T11:56:41Z\tv0.1.0\thttps://github.com/yungSNAT/Old/releases/tag/v0.1.0'
fixture New $'2026-11-14T02:43:49Z\tv1.2.0-1\thttps://github.com/yungSNAT/New/releases/tag/v1.2.0-1'
fixture Unreleased 404

readme() {
  cat >"$work/README.md" <<EOF
# Profile

- [Old](https://github.com/yungSNAT/Old): an old tool.
- [Unreleased](https://github.com/yungSNAT/Unreleased): no release.
- [New](https://github.com/yungSNAT/New): a newer fork.
- [Old](https://github.com/yungSNAT/Old) again.
- [Other](https://github.com/someone/Other): not ours.

## Latest releases

<!-- releases:start -->
- stale line
$1
EOF
}

want_list='<!-- releases:start -->
- 14 Nov 2026: [New v1.2.0-1](https://github.com/yungSNAT/New/releases/tag/v1.2.0-1)
- 12 Nov 2026: [Old v0.1.0](https://github.com/yungSNAT/Old/releases/tag/v0.1.0)
<!-- releases:end -->
After.'

# expect: runs update.sh on README.md and compares its exit status; a
# failure must leave the README unchanged. With a third argument, also
# compares the README from the start marker on. Leaves the script's output
# in $out.
expect() {
  local want=$1 name=$2 got=0
  cp "$work/README.md" "$work/before"
  out=$(bash "$update" "$work/README.md" 2>&1) || got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $name: exit $got, want $want"
    printf '%s\n' "$out" | sed 's/^/     /'
    failures=$((failures + 1))
  elif [ "$want" -ne 0 ] && ! cmp -s "$work/README.md" "$work/before"; then
    echo "FAIL $name: the README changed"
    failures=$((failures + 1))
  elif [ $# -ge 3 ] && [ "$(sed -n '/^<!-- releases:start -->$/,$p' "$work/README.md")" != "$3" ]; then
    echo "FAIL $name: README differs"
    sed 's/^/     /' "$work/README.md"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

readme $'<!-- releases:end -->\nAfter.'
expect 0 'newest first, unreleased and duplicate and foreign links left out' "$want_list"
[[ $out == *'Unreleased: no published release'* ]] || { echo 'FAIL the unreleased repository is not named'; failures=$((failures + 1)); }
expect 0 'a second run changes nothing' "$want_list"

fixture Unreleased 500
readme $'<!-- releases:end -->\nAfter.'
expect 1 'an API failure fails'
fixture Unreleased 404

rm "$FIXTURES/Unreleased"
readme $'<!-- releases:end -->\nAfter.'
expect 1 'a listed repository that does not exist fails'
fixture Unreleased 404

fixture New $'2026-11-14T02:43:49Z\t\thttps://github.com/yungSNAT/New/releases/tag/x'
readme $'<!-- releases:end -->\nAfter.'
expect 1 'a release with no tag fails'
fixture New $'2026-11-14T02:43:49Z\tv1.2.0-1\thttps://github.com/yungSNAT/New/releases/tag/v1.2.0-1'

fixture New $'2026-11-14T02:43:49Z\tv1]*_&amp;x\thttps://github.com/yungSNAT/New/releases/tag/v1(a)&amp;'
readme $'<!-- releases:end -->\nAfter.'
expect 0 'Markdown and entities in a tag stay literal and a URL keeps its destination' '<!-- releases:start -->
- 14 Nov 2026: [New v1\]\*\_\&amp;x](https://github.com/yungSNAT/New/releases/tag/v1%28a%29%26amp;)
- 12 Nov 2026: [Old v0.1.0](https://github.com/yungSNAT/Old/releases/tag/v0.1.0)
<!-- releases:end -->
After.'

fixture New $'2026-11-14T02:43:49Z\tv1\thttps://github.com/yungSNAT/New/releases/tag/v1 x'
readme $'<!-- releases:end -->\nAfter.'
expect 1 'a URL with a space fails'

fixture New $'2026-11-14T02:43:49Z\tv1\thttps://example.com/yungSNAT/New/releases/tag/v1'
readme $'<!-- releases:end -->\nAfter.'
expect 1 "a URL outside the repository's releases fails"

# jq's @tsv writes a tab or newline inside a field as \t or \n.
fixture New '2026-11-14T02:43:49Z	v1	https://github.com/yungSNAT/New/releases/tag/v1\nx'
readme $'<!-- releases:end -->\nAfter.'
expect 1 'a URL with an escaped newline fails'

fixture New $'not-a-date\tv1.2.0-1\thttps://github.com/yungSNAT/New/releases/tag/v1.2.0-1'
readme $'<!-- releases:end -->\nAfter.'
expect 1 'a release date that does not parse fails'
fixture New $'2026-11-14T02:43:49Z\tv1.2.0-1\thttps://github.com/yungSNAT/New/releases/tag/v1.2.0-1'

readme 'After.'
expect 2 'no end marker fails'

readme $'<!-- releases:end -->\n<!-- releases:end -->'
expect 2 'two end markers fail'

printf '%s\n' '<!-- releases:end -->' '- [Old](https://github.com/yungSNAT/Old)' '<!-- releases:start -->' >"$work/README.md"
expect 2 'markers out of order fail'

printf '%s\n' '<!-- releases:start -->' '<!-- releases:end -->' >"$work/README.md"
expect 2 'no listed repository fails'

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
echo 'all passed'
