#!/usr/bin/env bash
# Runs check.sh against throwaway Git repositories. Exits non-zero on any failure.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

export SHIPPED='^src/' EXCLUDE='_test\.rs$' HEADING='## [Unreleased]'

# new_repo: a repository whose base commit has src/lib.rs, docs/guide.md and a CHANGELOG.md.
new_repo() {
  repo="$work/$1"
  git init -q "$repo"
  cd "$repo"
  git config user.name test
  git config user.email test@example.invalid
  git config core.autocrlf false
  mkdir -p src docs
  echo 'fn main() {}' >src/lib.rs
  echo guide >docs/guide.md
  printf '# Changelog\n\n## [Unreleased]\n' >CHANGELOG.md
  git add -A
  git commit -qm base
  BASE=$(git rev-parse HEAD)
}

# expect: commits the working tree, runs check.sh and compares its exit status.
expect() {
  local want=$1 name=$2 got=0 out
  git add -A
  git commit -qm change
  out=$(BASE=$BASE HEAD=$(git rev-parse HEAD) bash "$check" 2>&1) || got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: exit $got, want $want"
    printf '%s\n' "$out" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
}

new_repo rename-out
mkdir -p attic
git mv src/lib.rs attic/lib.rs
expect 1 'rename out of a shipped folder needs a line'

new_repo non-ascii
echo x >'src/naïve café.rs'
expect 1 'non-ASCII shipped path needs a line'

new_repo non-ascii-with-line
echo x >'src/naïve café.rs'
echo '- Add naïve café.' >>CHANGELOG.md
expect 0 'non-ASCII shipped path with a line passes'

new_repo blank-only
echo 'fn main() { }' >src/lib.rs
printf '\n   \n\t\n' >>CHANGELOG.md
expect 1 'blank-only changelog edit does not count'

new_repo plus-line
echo 'fn main() { }' >src/lib.rs
echo '++ counts' >>CHANGELOG.md
expect 0 'an added line starting with ++ counts'

new_repo exempt-only
echo more >>docs/guide.md
expect 0 'exempt-only change passes'

new_repo excluded-only
echo '#[test] fn t() {}' >src/lib_test.rs
expect 0 'excluded shipped path passes'

new_repo shipped-with-line
echo 'fn main() { }' >src/lib.rs
echo '- Fix main.' >>CHANGELOG.md
expect 0 'shipped change with a line passes'

new_repo shipped-without-line
echo 'fn main() { }' >src/lib.rs
expect 1 'shipped change without a line fails'

new_repo bad-pattern
echo 'fn main() { }' >src/lib.rs
SHIPPED='^(src' expect 2 'a bad pattern fails instead of passing'

new_repo bad-base
echo 'fn main() { }' >src/lib.rs
BASE=0000000000000000000000000000000000000000
expect 128 'an unknown base fails instead of passing'

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo 'All tests passed.'
