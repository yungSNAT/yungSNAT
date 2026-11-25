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

[Tools](#tools) · [Notes](docs/notes.md#notes)

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
  local want=$1 name=$2 got=0
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
sed 's|\.github/assets/banner\.svg|.github/assets|g' "$site/README.md" >"$site/README.tmp" && mv "$site/README.tmp" "$site/README.md"
expect 1 'directory used as image src fails'

make_site traversal-link
printf '\n[Escape](../outside.md)\n' >>"$site/README.md"
expect 1 'relative link escaping repository root fails'

make_site symlink-outside-file
printf 'outside\n' >"$work/outside.md"
MSYS=winsymlinks:nativestrict ln -s "$work/outside.md" "$site/docs/outside.md"
printf '\n[Outside](docs/outside.md)\n' >>"$site/README.md"
expect 1 'symlink to file outside repository root fails'

make_site symlink-outside-dir
mkdir -p "$work/outside-dir"
printf 'outside\n' >"$work/outside-dir/secret.md"
MSYS=winsymlinks:nativestrict ln -s "$work/outside-dir" "$site/docs/ext"
printf '\n[Secret](docs/ext/secret.md)\n' >>"$site/README.md"
expect 1 'path through symlink directory outside repository root fails'

make_site symlink-inside
MSYS=winsymlinks:nativestrict ln -s notes.md "$site/docs/alias.md"
printf '\n[Alias](docs/alias.md)\n' >>"$site/README.md"
expect 0 'internal symlink inside repository root passes'

make_site ref-link-valid
printf '\n[notes-ref]: docs/notes.md "Notes"\n[ext-ref]: https://example.com\n' >>"$site/README.md"
expect 0 'valid markdown reference link definitions pass'

make_site ref-link-missing
printf '\n[missing-ref]: docs/missing.md "Missing"\n' >>"$site/README.md"
expect 1 'missing markdown reference link definition fails'

make_site ref-link-angle-missing
printf '\n[missing-angle]: <docs/missing.md> "Missing"\n' >>"$site/README.md"
expect 1 'missing angle-bracketed markdown reference link fails'

make_site srcset-data-uri
printf '\n<picture><source srcset="data:image/svg+xml;base64,PHN2Zy8+ 1x, .github/assets/banner.svg 2x"><img src=".github/assets/banner.svg" alt="x"></picture>\n' >>"$site/README.md"
expect 0 'data URI with comma in srcset passes'

make_site srcset-data-uri-missing
printf '\n<picture><source srcset="data:image/svg+xml;base64,PHN2Zy8+, .github/assets/missing.svg"><img src=".github/assets/banner.svg" alt="x"></picture>\n' >>"$site/README.md"
expect 1 'data URI followed by missing relative path in srcset fails'

make_site srcset-data-uri-multi-comma-ok
printf '\n<picture><source srcset="data:text/plain,hello,world 1x, .github/assets/banner.svg 2x"><img src=".github/assets/banner.svg" alt="x"></picture>\n' >>"$site/README.md"
expect 0 'multi-comma data URI with descriptor in srcset passes'

make_site srcset-data-uri-multi-comma-missing
printf '\n<picture><source srcset="data:text/plain,hello,world 1x, .github/assets/missing.svg 2x"><img src=".github/assets/banner.svg" alt="x"></picture>\n' >>"$site/README.md"
expect 1 'multi-comma data URI followed by missing path in srcset fails'
if [[ $out != *"missing image file '.github/assets/missing.svg'"* || $out == *"missing image file 'world'"* ]]; then
  echo 'FAIL multi-comma data URI error did not isolate .github/assets/missing.svg'
  printf '%s\n' "$out" | sed 's/^/     /'
  failures=$((failures + 1))
fi

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

make_site extra-llms-repo
printf '\n- [GhostRepo](https://github.com/yungSNAT/GhostRepo): stale entry.\n' >>"$site/llms.txt"
expect 1 'extra repository bullet in llms.txt missing from README.md fails'

make_site extra-llms-inline-link
printf '\nSee [GhostRepo](https://github.com/yungSNAT/GhostRepo#install).\n' >>"$site/llms.txt"
expect 1 'extra inline yungSNAT repo link in llms.txt missing from README.md fails'

make_site archived-also-in-llms
printf '\n- [OldFork](https://github.com/yungSNAT/OldFork): archived.\n' >>"$site/llms.txt"
expect 0 'archived repository present in both README.md and llms.txt passes'

make_site missing-same-file-anchor
printf '\n[Missing](#does-not-exist)\n' >>"$site/README.md"
expect 1 'missing same-file #fragment anchor fails'

make_site missing-cross-file-anchor
printf '\n[Missing](docs/notes.md#does-not-exist)\n' >>"$site/README.md"
expect 1 'missing cross-file #fragment anchor fails'

make_site duplicate-and-html-anchors
printf '\n<a id="custom-id"></a>\n\n## Tools\n\n[Second Tools](#tools-1) · [Custom](#custom-id)\n' >>"$site/README.md"
expect 0 'duplicate heading suffix and HTML id anchors pass'

make_site html-id-case-mismatch
printf '\n<a id="Install"></a>\n\n[Install](#install)\n' >>"$site/README.md"
expect 1 'fragment differing in case from an HTML id fails'

make_site heading-fragment-upper-case
printf '\n[Tools](#Tools)\n' >>"$site/README.md"
expect 0 'upper-case fragment for a heading slug passes'

make_site self-repo-blob-anchor-valid
printf '\n## Reusing this code\n' >"$site/AGENTS.md"
printf '\n[Reuse](https://github.com/yungSNAT/yungSNAT/blob/main/AGENTS.md#reusing-this-code)\n' >>"$site/llms.txt"
expect 0 'valid self-repo blob/main link and anchor in llms.txt passes'

make_site self-repo-blob-anchor-missing
printf '\n## Reusing this code\n' >"$site/AGENTS.md"
printf '\n[Reuse](https://github.com/yungSNAT/yungSNAT/blob/main/AGENTS.md#wrong-anchor)\n' >>"$site/llms.txt"
expect 1 'missing anchor on self-repo blob/main link in llms.txt fails'

make_site forks-broken-anchor
printf '# Forks\n\n[Broken](#nope)\n' >"$site/FORKS.md"
expect 1 'broken #fragment anchor in FORKS.md fails'

make_site missing-end-marker
sed '/releases:end/d' "$site/README.md" >"$site/README.tmp" && mv "$site/README.tmp" "$site/README.md"
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
