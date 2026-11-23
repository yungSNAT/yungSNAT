#!/usr/bin/env bash
# Checks README.md and llms.txt in a yungSNAT profile checkout:
# 1. releases:start and releases:end markers in README.md are balanced and intact.
# 2. Every relative link and image/srcset path in README.md exists on disk.
# 3. llms.txt lists every active yungSNAT repository named in README.md.
# Shell, not Rust: the profile's only other code is shell, and the workflow
# runs this with no build step. Requires bash, POSIX awk and realpath
# (available on ubuntu-latest, macOS and Git Bash).
set -euo pipefail
export LC_ALL=C

root=${1:-.}
readme="$root/README.md"
llms="$root/llms.txt"

if [ ! -f "$readme" ]; then
  echo "::error::Missing $readme." >&2
  exit 2
fi
if [ ! -f "$llms" ]; then
  echo "::error::Missing $llms." >&2
  exit 2
fi

canon_root=$(realpath "$root")
canon_root=${canon_root%/}

failures=0
fail() {
  echo "::error::$1" >&2
  failures=$((failures + 1))
}

# 1. Exactly one start marker, then one end marker, and no stray release markers.
start='<!-- releases:start -->'
end='<!-- releases:end -->'
if ! awk -v s="$start" -v e="$end" '
  { sub(/\r$/, "") }
  $0 == s { ns++; if (ne) bad = 1; next }
  $0 == e { ne++; next }
  index($0, "releases:start") || index($0, "releases:end") { bad = 1 }
  END { exit !(ns == 1 && ne == 1 && !bad) }
' "$readme"; then
  fail "README.md needs one '$start' line followed by one '$end' line, with no stray release markers."
fi

# 2. Every relative link and SVG/image src or srcset path in README.md exists.
while IFS=$'\t' read -r kind lineno target; do
  if [ -z "$target" ]; then
    fail "README.md:$lineno: empty $kind target."
    continue
  fi
  if [[ $target == \#* || $target == //* || $target =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]; then
    continue
  fi
  rel=${target%%[\#?]*}
  rel=${rel#/}
  if [ -z "$rel" ]; then
    fail "README.md:$lineno: $kind target resolves to an empty path: $target"
    continue
  fi
  if [[ "/$rel/" == *"/../"* ]]; then
    fail "README.md:$lineno: $kind path escapes repository root: $target"
    continue
  fi
  if [ "$kind" = image ]; then
    if [ ! -f "$root/$rel" ]; then
      fail "README.md:$lineno: missing image file '$rel'."
      continue
    fi
  elif [ ! -e "$root/$rel" ]; then
    fail "README.md:$lineno: missing relative link '$rel'."
    continue
  fi
  resolved=$(realpath "$root/$rel" 2>/dev/null || true)
  if [ -z "$resolved" ] || { [ "$resolved" != "$canon_root" ] && [[ "$resolved" != "$canon_root/"* ]]; }; then
    fail "README.md:$lineno: $kind path resolves outside repository root: '$rel'."
  fi
done < <(awk '
  function emit(kind, raw,    val) {
    val = raw
    sub(/^[ \t]+/, "", val)
    sub(/[ \t]+$/, "", val)
    printf "%s\t%d\t%s\n", kind, NR, val
  }
  function scan_srcset(val, kind,    s, item, c) {
    s = val
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    if (s == "") {
      emit(kind, "")
      return
    }
    while (s != "") {
      sub(/^[ \t]+/, "", s)
      if (s == "") {
        emit(kind, "")
        return
      }
      if (match(tolower(s), /^data:[^ \t]*/)) {
        item = substr(s, 1, RLENGTH)
        s = substr(s, RLENGTH + 1)
        if (substr(item, length(item), 1) == ",") {
          sub(/,+$/, "", item)
          emit(kind, item)
          if (s ~ /^[ \t]*$/) {
            emit(kind, "")
            return
          }
          continue
        }
        emit(kind, item)
        c = index(s, ",")
        if (c == 0) return
        s = substr(s, c + 1)
        if (s ~ /^[ \t]*$/) {
          emit(kind, "")
          return
        }
        continue
      }
      c = index(s, ",")
      if (c == 0) {
        item = s
        s = ""
      } else {
        item = substr(s, 1, c - 1)
        s = substr(s, c + 1)
        if (s ~ /^[ \t]*$/) {
          sub(/[ \t].*$/, "", item)
          emit(kind, item)
          emit(kind, "")
          return
        }
      }
      sub(/[ \t].*$/, "", item)
      emit(kind, item)
    }
  }
  function scan_attr(line, attr, kind,    rest, re, q, val, i) {
    rest = line
    re = "(^|[^A-Za-z0-9_-])" attr "[ \t]*=[ \t]*[\042\047]"
    while (match(tolower(rest), re)) {
      q = substr(rest, RSTART + RLENGTH - 1, 1)
      rest = substr(rest, RSTART + RLENGTH)
      i = index(rest, q)
      if (i == 0) break
      val = substr(rest, 1, i - 1)
      rest = substr(rest, i + 1)
      if (attr == "srcset") {
        scan_srcset(val, kind)
      } else {
        emit(kind, val)
      }
    }
  }
  function scan_ref_def(line,    rest, i) {
    if (!match(line, /^[ ]?[ ]?[ ]?\[[^][]+\]:[ \t]*/)) return 0
    rest = substr(line, RSTART + RLENGTH)
    if (rest == "") {
      emit("link", "")
      return 1
    }
    if (substr(rest, 1, 1) == "<") {
      i = index(rest, ">")
      emit("link", i > 0 ? substr(rest, 2, i - 2) : "")
      return 1
    }
    sub(/[ \t].*$/, "", rest)
    emit("link", rest)
    return 1
  }
  function scan_md(line,    rest, p, kind, target, ch, depth, i, len, prev) {
    rest = line
    while ((p = index(rest, "](")) > 0) {
      kind = "link"
      prev = substr(rest, 1, p - 1)
      if (match(prev, /!\[[^][]*$/)) kind = "image"
      rest = substr(rest, p + 2)
      sub(/^[ \t]+/, "", rest)
      if (substr(rest, 1, 1) == "<") {
        i = index(rest, ">")
        if (i == 0) break
        target = substr(rest, 2, i - 2)
        rest = substr(rest, i + 1)
        emit(kind, target)
        continue
      }
      depth = 0
      len = length(rest)
      target = ""
      for (i = 1; i <= len; i++) {
        ch = substr(rest, i, 1)
        if (ch == "(") {
          depth++
        } else if (ch == ")") {
          if (depth == 0) break
          depth--
        } else if ((ch == " " || ch == "\t") && depth == 0) {
          break
        }
        target = target ch
      }
      emit(kind, target)
      rest = substr(rest, i + 1)
    }
  }
  { sub(/\r$/, "") }
  /^[ \t]*(```|~~~)/ { in_fence = !in_fence; next }
  in_fence { next }
  {
    if (scan_ref_def($0)) next
    line = $0
    gsub(/`[^`]*`/, "", line)
    scan_attr(line, "srcset", "image")
    scan_attr(line, "src", "image")
    scan_attr(line, "href", "link")
    scan_md(line)
  }
' "$readme")

# 3. llms.txt lists every active yungSNAT repository named in README.md.
while IFS=$'\t' read -r status repo; do
  if [ "$status" = EMPTY ]; then
    fail "README.md lists no active yungSNAT repositories."
  elif [ "$status" = MISSING ]; then
    fail "Active repository '$repo' in README.md is missing from llms.txt."
  fi
done < <(awk '
  function bullet_repo(line,    s, p, q, label, url) {
    if (!match(line, /^- \[[A-Za-z0-9._-]+\]\(https:\/\/github\.com\/yungSNAT\/[A-Za-z0-9._-]+\)/)) return ""
    s = substr(line, 4)
    p = index(s, "](")
    label = substr(s, 1, p - 1)
    url = substr(s, p + 2)
    q = index(url, ")")
    url = substr(url, 1, q - 1)
    sub(/^https:\/\/github\.com\/yungSNAT\//, "", url)
    return (label == url) ? label : ""
  }
  FNR == NR {
    sub(/\r$/, "")
    r = bullet_repo($0)
    if (r != "") in_llms[r] = 1
    next
  }
  { sub(/\r$/, "") }
  /^[ \t]*(```|~~~)/ { in_fence = !in_fence; next }
  in_fence { next }
  {
    r = bullet_repo($0)
    if (r != "") {
      if (tolower($0) ~ /\(archived\)/) {
        archived[r] = 1
      } else if (!(r in seen)) {
        seen[r] = 1
        order[++n_active] = r
      }
    }
    rest = $0
    while (match(rest, /(^|[^A-Za-z0-9_-])[Hh][Rr][Ee][Ff][ \t]*=[ \t]*[\042\047]https:\/\/github\.com\/yungSNAT\/[A-Za-z0-9._-]+[\042\047]/)) {
      raw = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      sub(/^.*\//, "", raw)
      sub(/[\042\047]$/, "", raw)
      if (raw != "" && raw != "yungSNAT" && !(raw in card_seen)) {
        card_seen[raw] = 1
        cards[++n_cards] = raw
      }
    }
  }
  END {
    for (i = 1; i <= n_cards; i++) {
      r = cards[i]
      if (!(r in archived) && !(r in seen)) {
        seen[r] = 1
        order[++n_active] = r
      }
    }
    if (n_active == 0) {
      print "EMPTY"
      exit 0
    }
    for (i = 1; i <= n_active; i++) {
      r = order[i]
      if (!(r in in_llms)) print "MISSING\t" r
    }
  }
' "$llms" "$readme")

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "Profile checks passed."
