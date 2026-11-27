#!/usr/bin/env bash
# Checks README.md, llms.txt and (when present) FORKS.md in a yungSNAT profile checkout:
# 1. releases:start and releases:end markers in README.md are balanced and intact.
# 2. Every relative link, self-repo blob/main link, image/srcset path and internal
#    #fragment anchor target exists.
# 3. README.md and llms.txt stay in parity in both directions.
# Shell, not Rust: the profile's only other code is shell, and the workflow
# runs this with no build step. Requires bash, POSIX awk and realpath
# (available on ubuntu-latest, macOS and Git Bash).
set -euo pipefail
export LC_ALL=C

root=${1:-.}
script_dir=$(cd "$(dirname "$0")" && pwd)
bullet_repos="$script_dir/../lib/bullet-repos.awk"
readme="$root/README.md"
llms="$root/llms.txt"

if [ ! -f "$bullet_repos" ]; then
  echo "::error::Missing $bullet_repos." >&2
  exit 2
fi
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

has_anchor() {
  local file=$1 want=$2
  ANCHOR_WANT="$want" awk '
    BEGIN {
      want = ENVIRON["ANCHOR_WANT"]
      for (b = 1; b < 256; b++) ord[sprintf("%c", b)] = b
      hex = "0123456789abcdef"
    }
    function trim(s) {
      sub(/^[ \t]+/, "", s)
      sub(/[ \t]+$/, "", s)
      return s
    }
    function hex_val(ch,    p) {
      p = index(hex, tolower(ch))
      return p > 0 ? p - 1 : -1
    }
    function pct_decode(s,    out, i, n, h1, h2, v) {
      out = ""
      n = length(s)
      for (i = 1; i <= n; ) {
        if (substr(s, i, 1) == "%" && i + 2 <= n) {
          h1 = hex_val(substr(s, i + 1, 1))
          h2 = hex_val(substr(s, i + 2, 1))
          if (h1 >= 0 && h2 >= 0) {
            v = h1 * 16 + h2
            if (v > 0) {
              out = out sprintf("%c", v)
              i += 3
              continue
            }
          }
        }
        out = out substr(s, i, 1)
        i++
      }
      return out
    }
    function utf8_lower(s,    out, i, n, b1, b2) {
      s = tolower(s)
      out = ""
      n = length(s)
      for (i = 1; i <= n; ) {
        b1 = ord[substr(s, i, 1)]
        if (b1 == 195 && i + 1 <= n) {
          b2 = ord[substr(s, i + 1, 1)]
          if ((b2 >= 128 && b2 <= 150) || (b2 >= 152 && b2 <= 158)) {
            out = out sprintf("%c%c", 195, b2 + 32)
            i += 2
            continue
          }
        }
        out = out substr(s, i, 1)
        i++
      }
      return out
    }
    function is_stripped_cp(cp) {
      # Mirrors GitHub heading slugs: drops Unicode punctuation, symbols,
      # controls and non-ASCII spaces while keeping letters, decimal digits,
      # marks (e.g. U+FE0F, U+20E3), connector punctuation (Pc) and ZWNJ/ZWJ.
      if (cp >= 128 && cp <= 191) return (cp != 170 && cp != 181 && cp != 186)
      if (cp == 215 || cp == 247) return 1
      if (cp >= 8192 && cp <= 8303) {
        return (cp != 8204 && cp != 8205 && cp != 8255 && cp != 8256 && cp != 8276)
      }
      if (cp >= 8304 && cp <= 8334) return (cp != 8305 && cp != 8319)
      if (cp >= 8352 && cp <= 8399) return 1
      if ((cp >= 8448 && cp <= 8449) || (cp >= 8451 && cp <= 8454) || cp == 8456 || cp == 8457 || cp == 8468 || (cp >= 8470 && cp <= 8472) || (cp >= 8478 && cp <= 8483) || cp == 8485 || cp == 8487 || cp == 8489 || cp == 8494 || cp == 8506 || cp == 8507 || (cp >= 8512 && cp <= 8516) || (cp >= 8522 && cp <= 8525) || cp == 8527) return 1
      if (cp >= 8592 && cp <= 11263) return 1
      if (cp >= 11776 && cp <= 11903) return (cp != 11823)
      if ((cp >= 12288 && cp <= 12292) || (cp >= 12296 && cp <= 12320) || cp == 12336 || cp == 12342 || cp == 12343 || (cp >= 12349 && cp <= 12351)) return 1
      if (cp >= 12800 && cp <= 13311) return 1
      if (cp >= 65040 && cp <= 65055) return 1
      if (cp >= 65072 && cp <= 65135) {
        return (cp != 65075 && cp != 65076 && !(cp >= 65101 && cp <= 65103))
      }
      if ((cp >= 65281 && cp <= 65295) || (cp >= 65306 && cp <= 65312) || (cp >= 65339 && cp <= 65342) || cp == 65344 || (cp >= 65371 && cp <= 65381) || (cp >= 65504 && cp <= 65519)) return 1
      if (cp >= 126976 && cp <= 130047) return !(cp >= 130032 && cp <= 130041)
      if (cp >= 917536 && cp <= 917631) return 1
      return 0
    }
    function strip_inline(s,    t) {
      gsub(/<[^>]+>/, "", s)
      while (match(s, /!?\[[^][]*\]\([^)]*\)/)) {
        t = substr(s, RSTART, RLENGTH)
        sub(/^!?\[/, "", t)
        sub(/\]\([^)]*\)$/, "", t)
        s = substr(s, 1, RSTART - 1) t substr(s, RSTART + RLENGTH)
      }
      gsub(/[`*~]/, "", s)
      return s
    }
    function slugify(text,    s, out, i, n, b1, b2, b3, b4, cp, step, base, cand, k) {
      s = utf8_lower(trim(strip_inline(text)))
      out = ""
      n = length(s)
      for (i = 1; i <= n; ) {
        b1 = ord[substr(s, i, 1)]
        if (b1 < 128) {
          if (b1 == 32) {
            out = out "-"
          } else if ((b1 >= 97 && b1 <= 122) || (b1 >= 48 && b1 <= 57) || b1 == 45 || b1 == 95) {
            out = out substr(s, i, 1)
          }
          i++
          continue
        }
        cp = -1
        step = 1
        if (b1 >= 194 && b1 <= 223 && i + 1 <= n) {
          b2 = ord[substr(s, i + 1, 1)]
          if (b2 >= 128 && b2 <= 191) {
            cp = (b1 - 192) * 64 + (b2 - 128)
            step = 2
          }
        } else if (b1 >= 224 && b1 <= 239 && i + 2 <= n) {
          b2 = ord[substr(s, i + 1, 1)]
          b3 = ord[substr(s, i + 2, 1)]
          if (b2 >= 128 && b2 <= 191 && b3 >= 128 && b3 <= 191) {
            cp = (b1 - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128)
            if (cp >= 2048 && !(cp >= 55296 && cp <= 57343)) step = 3
            else cp = -1
          }
        } else if (b1 >= 240 && b1 <= 244 && i + 3 <= n) {
          b2 = ord[substr(s, i + 1, 1)]
          b3 = ord[substr(s, i + 2, 1)]
          b4 = ord[substr(s, i + 3, 1)]
          if (b2 >= 128 && b2 <= 191 && b3 >= 128 && b3 <= 191 && b4 >= 128 && b4 <= 191) {
            cp = (b1 - 240) * 262144 + (b2 - 128) * 4096 + (b3 - 128) * 64 + (b4 - 128)
            if (cp >= 65536 && cp <= 1114111) step = 4
            else cp = -1
          }
        }
        if (cp < 0 || !is_stripped_cp(cp)) {
          out = out substr(s, i, step)
        }
        i += step
      }
      if (out == "") return ""
      base = out
      cand = base
      k = 0
      while (cand in used) {
        k++
        cand = base "-" k
      }
      used[cand] = 1
      return cand
    }
    function record_attr(line, attr,    rest, re, q, i, val) {
      rest = line
      re = "(^|[^A-Za-z0-9_-])" attr "[ \t]*=[ \t]*[\042\047]"
      while (match(tolower(rest), re)) {
        q = substr(rest, RSTART + RLENGTH - 1, 1)
        rest = substr(rest, RSTART + RLENGTH)
        i = index(rest, q)
        if (i == 0) break
        val = substr(rest, 1, i - 1)
        rest = substr(rest, i + 1)
        if (val != "") html_ids[val] = 1
      }
    }
    { sub(/\r$/, "") }
    /^[ \t]*(```|~~~)/ { in_fence = !in_fence; next }
    in_fence { next }
    {
      if (match($0, /^[ ]?[ ]?[ ]?(######|#####|####|###|##|#)[ \t]+/)) {
        heading = substr($0, RSTART + RLENGTH)
        sub(/[ \t]+#+[ \t]*$/, "", heading)
        s = slugify(heading)
        if (s != "") anchors[s] = 1
      }
      line = $0
      gsub(/`[^`]*`/, "", line)
      record_attr(line, "id")
      if (tolower(line) ~ /<a[ \t]/) record_attr(line, "name")
    }
    # HTML ids match case-sensitively; heading slugs are lower case and
    # GitHub also matches lower-cased or percent-encoded fragments against them.
    END {
      decoded = pct_decode(want)
      exit !((want in html_ids) || (decoded in html_ids) || (utf8_lower(want) in anchors) || (utf8_lower(decoded) in anchors))
    }
  ' "$file"
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

# 2. Every relative link, self-repo blob/main link, image/srcset path and #fragment target exists.
check_links() {
  local rel_file=$1
  local full_file="$root/$rel_file"
  local kind lineno target has_frag frag rel resolved
  while IFS=$'\t' read -r kind lineno target; do
    if [ -z "$target" ]; then
      fail "$rel_file:$lineno: empty $kind target."
      continue
    fi
    if [[ $target == https://github.com/yungSNAT/yungSNAT/blob/main/* ]]; then
      target=${target#https://github.com/yungSNAT/yungSNAT/blob/main/}
    fi
    if [[ $target == \#* ]]; then
      if [ "$kind" != image ]; then
        frag=${target#\#}
        if [ -z "$frag" ]; then
          fail "$rel_file:$lineno: empty fragment target '$target'."
        elif ! has_anchor "$full_file" "$frag"; then
          fail "$rel_file:$lineno: missing anchor '#$frag' in '$rel_file'."
        fi
      fi
      continue
    fi
    if [[ $target == //* || $target =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]; then
      continue
    fi
    has_frag=0
    frag=""
    if [[ $target == *\#* ]]; then
      has_frag=1
      frag=${target#*\#}
    fi
    rel=${target%%[\#?]*}
    rel=${rel#/}
    if [ -z "$rel" ]; then
      fail "$rel_file:$lineno: $kind target resolves to an empty path: $target"
      continue
    fi
    if [[ "/$rel/" == *"/../"* ]]; then
      fail "$rel_file:$lineno: $kind path escapes repository root: $target"
      continue
    fi
    if [ "$kind" = image ]; then
      if [ ! -f "$root/$rel" ]; then
        fail "$rel_file:$lineno: missing image file '$rel'."
        continue
      fi
    elif [ ! -e "$root/$rel" ]; then
      fail "$rel_file:$lineno: missing relative link '$rel'."
      continue
    fi
    resolved=$(realpath "$root/$rel" 2>/dev/null || true)
    if [ -z "$resolved" ] || { [ "$resolved" != "$canon_root" ] && [[ "$resolved" != "$canon_root/"* ]]; }; then
      fail "$rel_file:$lineno: $kind path resolves outside repository root: '$rel'."
      continue
    fi
    if [ "$kind" != image ] && [ "$has_frag" -eq 1 ]; then
      if [ -z "$frag" ]; then
        fail "$rel_file:$lineno: empty fragment in '$target'."
      else
        case "$rel" in
          *.[Mm][Dd]|*.[Mm][Aa][Rr][Kk][Dd][Oo][Ww][Nn])
            if [ -f "$root/$rel" ] && ! has_anchor "$root/$rel" "$frag"; then
              fail "$rel_file:$lineno: missing anchor '#$frag' in '$rel'."
            fi
            ;;
        esac
      fi
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
  ' "$full_file")
}

check_links README.md
check_links llms.txt
if [ -f "$root/FORKS.md" ]; then
  check_links FORKS.md
fi

# 3. README.md and llms.txt list matching yungSNAT repositories in both directions.
while IFS=$'\t' read -r status repo; do
  if [ "$status" = EMPTY ]; then
    fail "README.md lists no active yungSNAT repositories."
  elif [ "$status" = MISSING ]; then
    fail "Active repository '$repo' in README.md is missing from llms.txt."
  elif [ "$status" = EXTRA ]; then
    fail "Repository '$repo' in llms.txt is missing from README.md."
  fi
done < <(
  {
    awk -f "$bullet_repos" -v prefix=LLMS "$llms"
    awk -f "$bullet_repos" -v prefix=README "$readme"
  } | awk '
    BEGIN {
      FS = "\t"
      llms_file = ARGV[2]
      readme_file = ARGV[3]
    }
    FILENAME == "-" {
      if ($1 == "LLMS") {
        in_llms[$3] = 1
      } else if ($1 == "README") {
        if ($2 == "active" && !($3 in seen)) {
          seen[$3] = 1
          order[++n_active] = $3
        } else if ($2 == "archived") {
          archived[$3] = 1
        }
      }
      next
    }
    FNR == 1 { in_fence = 0 }
    { sub(/\r$/, "") }
    /^[ \t]*(```|~~~)/ { in_fence = !in_fence; next }
    in_fence { next }
    FILENAME == llms_file {
      rest = $0
      gsub(/`[^`]*`/, "", rest)
      while (match(rest, /https:\/\/github\.com\/yungSNAT\/[A-Za-z0-9._-]+/)) {
        raw = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        sub(/^https:\/\/github\.com\/yungSNAT\//, "", raw)
        sub(/\.+$/, "", raw)
        sub(/\.git$/, "", raw)
        if (raw != "" && raw != "yungSNAT" && !(raw in llms_ref_seen)) {
          llms_ref_seen[raw] = 1
          llms_refs[++n_llms_refs] = raw
        }
      }
      next
    }
    FILENAME == readme_file {
      rest = $0
      while (match(rest, /(^|[^A-Za-z0-9_-])[Hh][Rr][Ee][Ff][ \t]*=[ \t]*[\042\047]https:\/\/github\.com\/yungSNAT\/[A-Za-z0-9._-]+[\042\047]/)) {
        raw = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        sub(/^.*\//, "", raw)
        sub(/[\042\047]$/, "", raw)
        sub(/\.git$/, "", raw)
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
      for (i = 1; i <= n_llms_refs; i++) {
        r = llms_refs[i]
        if (!(r in seen) && !(r in archived)) print "EXTRA\t" r
      }
    }
  ' - "$llms" "$readme"
)

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "Profile checks passed."
