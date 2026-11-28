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

make_site mixed-archived-active-missing-llms
printf '\n- [Hybrid](https://github.com/yungSNAT/Hybrid): older copy (archived).\n- [Hybrid](https://github.com/yungSNAT/Hybrid): active tool.\n' >>"$site/README.md"
expect 1 'mixed archived and active repository missing from llms.txt fails'
if [[ $out != *"Active repository 'Hybrid' in README.md is missing from llms.txt."* ]]; then
  echo 'FAIL mixed archived/active error did not name Hybrid as missing'
  printf '%s\n' "$out" | sed 's/^/     /'
  failures=$((failures + 1))
fi

make_site mixed-archived-active-present-llms
printf '\n- [Hybrid](https://github.com/yungSNAT/Hybrid): older copy (archived).\n- [Hybrid](https://github.com/yungSNAT/Hybrid): active tool.\n' >>"$site/README.md"
printf '\n- [Hybrid](https://github.com/yungSNAT/Hybrid): active tool.\n' >>"$site/llms.txt"
expect 0 'mixed archived and active repository present in llms.txt passes'

make_site llms-git-suffix-valid
printf '\nClone https://github.com/yungSNAT/Antifragile.git, https://github.com/yungSNAT/OldFork.git or [self](https://github.com/yungSNAT/yungSNAT.git).\n' >>"$site/llms.txt"
expect 0 '.git suffixed repository URLs in llms.txt pass'

make_site llms-git-suffix-sentence-dot
printf '\nClone https://github.com/yungSNAT/Antifragile.git. Mirror https://github.com/yungSNAT/yungSNAT.git.\n' >>"$site/llms.txt"
expect 0 'bare sentence-ending .git. repository URLs in llms.txt pass'

make_site llms-git-suffix-bullet
sed 's|https://github\.com/yungSNAT/Antifragile)|https://github.com/yungSNAT/Antifragile.git)|' "$site/llms.txt" >"$site/llms.tmp" && mv "$site/llms.tmp" "$site/llms.txt"
expect 0 '.git suffixed repository bullet in llms.txt passes'

make_site llms-git-suffix-extra
printf '\nClone [GhostRepo](https://github.com/yungSNAT/GhostRepo.git).\n' >>"$site/llms.txt"
expect 1 'extra .git suffixed repository URL in llms.txt fails'
if [[ $out != *"Repository 'GhostRepo' in llms.txt is missing from README.md."* ]]; then
  echo 'FAIL extra .git URL did not strip .git suffix in error'
  printf '%s\n' "$out" | sed 's/^/     /'
  failures=$((failures + 1))
fi

make_site llms-git-suffix-sentence-dot-extra
printf '\nClone https://github.com/yungSNAT/GhostRepo.git.\n' >>"$site/llms.txt"
expect 1 'extra bare sentence-ending .git. URL in llms.txt fails'
if [[ $out != *"Repository 'GhostRepo' in llms.txt is missing from README.md."* ]]; then
  echo 'FAIL extra bare .git. URL did not strip trailing dot and .git suffix in error'
  printf '%s\n' "$out" | sed 's/^/     /'
  failures=$((failures + 1))
fi

make_site card-git-suffix-valid
sed 's|href="https://github\.com/yungSNAT/Antifragile"|href="https://github.com/yungSNAT/Antifragile.git"|' "$site/README.md" >"$site/README.tmp" && mv "$site/README.tmp" "$site/README.md"
printf '\n<a href="https://github.com/yungSNAT/yungSNAT.git">Profile</a>\n' >>"$site/README.md"
expect 0 '.git suffixed README.md card hrefs pass'

make_site card-git-suffix-missing-llms
printf '\n<a href="https://github.com/yungSNAT/CardOnly.git">Card</a>\n' >>"$site/README.md"
expect 1 '.git suffixed card-only repository missing from llms.txt fails'
if [[ $out != *"Active repository 'CardOnly' in README.md is missing from llms.txt."* ]]; then
  echo 'FAIL .git card href did not strip .git suffix in error'
  printf '%s\n' "$out" | sed 's/^/     /'
  failures=$((failures + 1))
fi

make_site unicode-dash-and-emoji-anchors-valid
printf '\n## Tools \342\200\224 notes\n## Tools\342\200\224tight\n## Tools \342\200\223 en-dash\n## \360\237\232\200 Quick start\n## Quick \360\237\232\200 start\n## Quick start \360\237\232\200\n## Check \342\234\205 done\n## Warn \342\232\240\357\270\217 note\n## Family \360\237\221\250\342\200\215\360\237\221\251\342\200\215\360\237\221\247 test\n## \303\211cole Caf\303\251\n## Quotes \342\200\234smart\342\200\235 \342\200\230single\342\200\231\n## Hello \342\200\224 World\n## Hello \342\200\223 World\n## Math \342\237\202 perp \342\237\266 arrow \342\240\201 braille\n## Sup \342\201\260 \342\201\261 \342\201\264 \342\201\272 \342\201\277 \342\202\200 \342\202\212 \342\202\220\n## England \360\237\217\264\363\240\201\247\363\240\201\242\363\240\201\245\363\240\201\256\363\240\201\247\363\240\201\277 flag\n## Care \342\204\205 \342\204\236 \342\204\256\n## Tilde \342\270\257 vert\n## Seg \360\237\257\260\360\237\257\271 digits\n\n[Em](#tools--notes) [Tight](#toolstight) [En](#tools--en-dash) [Lead](#-quick-start) [Mid](#quick--start) [Trail](#quick-start-) [Check](#check--done) [Warn](#warn-\357\270\217-note) [WarnPct](#warn-%%ef%%b8%%8f-note) [Family](#family-\342\200\215\342\200\215-test) [Cafe](#\303\251cole-caf\303\251) [CafeUp](#\303\211cole-Caf\303\251) [CafePct](#%%c3%%a9cole-caf%%c3%%a9) [Quotes](#quotes-smart-single) [H1](#hello--world) [H2](#hello--world-1) [Math](#math--perp--arrow--braille) [Sup](#sup--\342\201\261---\342\201\277---\342\202\220) [England](#england--flag) [Care](#care---) [Tilde](#tilde-\342\270\257-vert) [Seg](#seg-\360\237\257\260\360\237\257\271-digits)\n' >>"$site/README.md"
expect 0 'GitHub heading slugs for Unicode dashes, symbols, emoji, tags and letters pass'

make_site em-dash-raw-anchor-fails
printf '\n## Tools \342\200\224 notes\n\n[Bad](#tools-\342\200\224-notes)\n' >>"$site/README.md"
expect 1 'fragment retaining em dash fails'

make_site leading-emoji-missing-hyphen-fails
printf '\n## \360\237\232\200 Quick start\n\n[Bad](#quick-start)\n' >>"$site/README.md"
expect 1 'fragment dropping leading hyphen after leading emoji fails'

make_site emoji-only-heading-has-no-anchor
printf '\n## \360\237\232\200\n\n[Bad](#\360\237\232\200)\n' >>"$site/README.md"
expect 1 'emoji-only heading produces no anchor'

make_site warn-emoji-dropped-fe0f-fails
printf '\n## Warn \342\232\240\357\270\217 note\n\n[Bad](#warn--note)\n' >>"$site/README.md"
expect 1 'fragment dropping U+FE0F variation selector fails'

make_site pct-nul-fragment-fails
printf '\n[Bad](#tools%%00)\n' >>"$site/README.md"
expect 1 'percent-encoded NUL in fragment fails'

make_site unicode-case-folding-anchors
printf '\n## \316\224\316\237\316\232\316\231\316\234\316\227\n## \316\237\316\224\316\237\316\243 \316\243\316\231\316\223\316\234\316\221\n## \316\206\316\210\316\211\316\212\316\214\316\216\316\217\n## \320\237\320\240\320\230\320\222\320\225\320\242 \320\201\320\226\n## \304\214\305\230\305\240\305\275 \305\201\304\260\305\270 \341\272\236\n## \324\261\324\262\324\263\n## \357\274\241\357\274\242\357\274\272\n## \360\220\220\200\360\220\220\201\n\n[Gr](#\316\264\316\277\316\272\316\271\316\274\316\267) [GrUp](#\316\224\316\237\316\232\316\231\316\234\316\227) [GrPct](#%%ce%%b4%%ce%%bf%%ce%%ba%%ce%%b9%%ce%%bc%%ce%%b7) [Sig](#\316\277\316\264\316\277\317\203-\317\203\316\271\316\263\316\274\316\261) [GrAcc](#\316\254\316\255\316\256\316\257\317\214\317\215\317\216) [Cyr](#\320\277\321\200\320\270\320\262\320\265\321\202-\321\221\320\266) [Lat](#\304\215\305\231\305\241\305\276-\305\202i\314\207\303\277-\303\237) [Arm](#\325\241\325\242\325\243) [Fw](#\357\275\201\357\275\202\357\275\232) [Des](#\360\220\220\250\360\220\220\251)\n' >>"$site/README.md"
expect 0 'GitHub Unicode lowercase heading slugs (Greek, Cyrillic, Latin-Extended, Armenian, fullwidth, Deseret) pass'

make_site greek-html-id-case-mismatch
printf '\n<a id="\316\224\316\237\316\232\316\231\316\234\316\227"></a>\n\n[Bad](#\316\264\316\277\316\272\316\271\316\274\316\267)\n' >>"$site/README.md"
expect 1 'lowercase Greek fragment differing in case from HTML id fails'

bullet_awk="$(cd "$(dirname "$0")" && pwd)/../lib/bullet-repos.awk"
printf '```\n- [Inside](https://github.com/yungSNAT/Inside)\n' >"$work/fence1.md"
printf -- '- [AfterFence](https://github.com/yungSNAT/AfterFence)\n' >"$work/fence2.md"
multi_out=$(awk -f "$bullet_awk" "$work/fence1.md" "$work/fence2.md")
if [ "$multi_out" != $'active\tAfterFence' ]; then
  echo 'FAIL bullet-repos.awk did not reset fence state on a second file'
  printf '%s\n' "$multi_out" | sed 's/^/     /'
  failures=$((failures + 1))
else
  echo 'ok   bullet-repos.awk resets fence state across input files'
fi

cat >"$work/nested-fence.md" <<'EOF'
````markdown
```
- [FakeInner](https://github.com/yungSNAT/FakeInner)
```
- [StillFenced](https://github.com/yungSNAT/StillFenced)
~~~~
- [AlsoFenced](https://github.com/yungSNAT/AlsoFenced)
````
~~~
```
- [InsideTilde](https://github.com/yungSNAT/InsideTilde)
~~~
- [AfterNested](https://github.com/yungSNAT/AfterNested)
EOF
nested_out=$(awk -f "$bullet_awk" "$work/nested-fence.md")
if [ "$nested_out" != $'active\tAfterNested' ]; then
  echo 'FAIL bullet-repos.awk closed a fence on a shorter or mismatched delimiter'
  printf '%s\n' "$nested_out" | sed 's/^/     /'
  failures=$((failures + 1))
else
  echo 'ok   bullet-repos.awk tracks opening fence delimiter and length'
fi

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
