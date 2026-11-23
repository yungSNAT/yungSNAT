#!/usr/bin/env bash
# Runs check.sh against fixture checkouts. Exits non-zero on any failure.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

make_site() {
  site="$work/$1"
  mkdir -p "$site/.github/assets/cards" "$site/docs"
  printf '<svg/>\n' >"$site/.github/assets/banner.svg"
  printf '<svg/>\n' >"$site/.github/assets/banner-light.svg"
  printf '<svg/>\n' >"$site/.github/assets/cards/antifragile.svg"
  printf '# Notes\n' >"$site/docs/notes.md"

  cat >"$site/README.md" <<'EOF'
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset=".github/assets/banner-light.svg 1x, .github/assets/banner.svg 2x">
    <img src=".github/assets/banner.svg" alt="Banner">
  </picture>
</p>

[Tools](#tools) · [Notes](docs/notes.md#top)

## Tools

<p>
<a href="https://github.com/yungSNAT/Antifragile"><img src=".github/assets/cards/antifragile.svg" alt="Antifragile"></a>
</p>

- [Antifragile](https://github.com/yungSNAT/Antifragile): a tool that gains from disorder.

## Forks

- [OldFork](https://github.com/yungSNAT/OldFork): kept for history (archived).

## Latest releases

<!-- releases:start -->
- 14 Nov 2026: [Antifragile v1.0.0](https://github.com/yungSNAT/Antifragile/releases/tag/v1.0.0)
<!-- releases:end -->
EOF

  cat >"$site/llms.txt" <<'EOF'
# yungSNAT

## Tools

- [Antifragile](https://github.com/yungSNAT/Antifragile): a tool that gains from disorder.
EOF
}

expect() {
  local want=$1 name=$2 got=0 out
  out=$(bash "$check" "$site" 2>&1) || got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $name: exit $got, want $want"
    printf '%s\n' "$out" | sed 's/^/     /'
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

make_site valid
expect 0 'valid profile with archived fork omitted from llms.txt passes'

make_site missing-srcset
rm "$site/.github/assets/banner-light.svg"
expect 1 'missing srcset asset fails'

make_site missing-img
rm "$site/.github/assets/cards/antifragile.svg"
expect 1 'missing img src asset fails'

make_site missing-rel-link
rm "$site/docs/notes.md"
expect 1 'missing relative markdown link fails'

make_site titled-rel-link
printf '\n[Notes](docs/notes.md "Read notes")\n' >>"$site/README.md"
expect 0 'relative markdown link with title passes'

make_site missing-href-link
printf '\n<a href="docs/missing.md">Missing</a>\n' >>"$site/README.md"
expect 1 'missing relative HTML href fails'

make_site missing-md-img
printf '\n![Broken](.github/assets/none.svg)\n' >>"$site/README.md"
expect 1 'missing markdown image fails'

make_site dir-as-md-img
printf '\n![Dir](.github/assets)\n' >>"$site/README.md"
expect 1 'directory used as markdown image fails'

make_site dir-as-img
sed -i 's|\.github/assets/banner\.svg|.github/assets|g' "$site/README.md"
expect 1 'directory used as image src fails'

make_site traversal-link
printf '\n[Escape](../outside.md)\n' >>"$site/README.md"
expect 1 'relative link escaping repository root fails'

make_site empty-link
printf '\n[Empty]()\n' >>"$site/README.md"
expect 1 'empty markdown link fails'

make_site code-span-ignored
cat >>"$site/README.md" <<'EOF'

Try `[not-a-link](missing.md)`.

```
<img src="missing.svg">
```
EOF
expect 0 'links inside inline code and fenced blocks are ignored'

make_site missing-llms-repo
printf '\n- [SecondTool](https://github.com/yungSNAT/SecondTool): missing from llms.\n' >>"$site/README.md"
expect 1 'active repository missing from llms.txt fails'

make_site card-only-missing-llms
printf '\n<a href="https://github.com/yungSNAT/CardOnly">Card</a>\n' >>"$site/README.md"
expect 1 'card-only repository missing from llms.txt fails'

make_site missing-end-marker
sed -i '/releases:end/d' "$site/README.md"
expect 1 'missing releases:end marker fails'

make_site reversed-markers
awk '
  /releases:start/ { print "<!-- releases:end -->"; next }
  /releases:end/ { print "<!-- releases:start -->"; next }
  { print }
' "$site/README.md" >"$site/README.tmp" && mv "$site/README.tmp" "$site/README.md"
expect 1 'reversed release markers fail'

make_site duplicate-start-marker
printf '\n<!-- releases:start -->\n' >>"$site/README.md"
expect 1 'duplicate releases:start marker fails'

make_site stray-inline-marker
printf '\n<!-- releases:start --> stray\n' >>"$site/README.md"
expect 1 'stray inline release marker fails'

make_site missing-llms-file
rm "$site/llms.txt"
expect 2 'missing llms.txt exits 2'

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
echo 'all passed'
