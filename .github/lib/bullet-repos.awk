# Extracts yungSNAT repository bullets '- [Name](https://github.com/yungSNAT/Name)'
# (with optional '.git' suffix) from a Markdown file, ignoring fenced code blocks.
# Default output: '<status>\t<repo>' where status is 'active' or 'archived'
# (archived-only: any unmarked bullet row makes the repository active).
# Options:
#   -v only_active=1  print only active '<repo>' names, one per line.
#   -v prefix=TAG     prepend 'TAG\t' to each output line.
function bullet_repo(line,    s, p, q, label, url) {
  if (!match(line, /^- \[[A-Za-z0-9._-]+\]\(https:\/\/github\.com\/yungSNAT\/[A-Za-z0-9._-]+\)/)) return ""
  s = substr(line, 4)
  p = index(s, "](")
  label = substr(s, 1, p - 1)
  url = substr(s, p + 2)
  q = index(url, ")")
  url = substr(url, 1, q - 1)
  sub(/^https:\/\/github\.com\/yungSNAT\//, "", url)
  sub(/\.git$/, "", url)
  return (label == url && label != "yungSNAT") ? label : ""
}
function fence_open(line,    s, ch, len, rest) {
  s = line
  sub(/^[ \t]+/, "", s)
  if (match(s, /^```+/)) {
    ch = "`"
    len = RLENGTH
    rest = substr(s, len + 1)
    if (index(rest, "`") > 0) return 0
  } else if (match(s, /^~~~+/)) {
    ch = "~"
    len = RLENGTH
  } else {
    return 0
  }
  fence_ch = ch
  fence_len = len
  return 1
}
function fence_close(line,    s, len) {
  s = line
  sub(/^[ \t]+/, "", s)
  if (fence_ch == "`") {
    if (!match(s, /^```+/)) return 0
  } else {
    if (!match(s, /^~~~+/)) return 0
  }
  len = RLENGTH
  if (len < fence_len) return 0
  return (substr(s, len + 1) ~ /^[ \t]*$/)
}
FNR == 1 { in_fence = 0; fence_ch = ""; fence_len = 0 }
{ sub(/\r$/, "") }
in_fence {
  if (fence_close($0)) {
    in_fence = 0
    fence_ch = ""
    fence_len = 0
  }
  next
}
fence_open($0) { in_fence = 1; next }
{
  r = bullet_repo($0)
  if (r == "") next
  if (tolower($0) ~ /\(archived\)/) {
    if (!(r in archived_seen)) {
      archived_seen[r] = 1
      archived_order[++n_archived] = r
    }
  } else if (!(r in active_seen)) {
    active_seen[r] = 1
    active_order[++n_active] = r
  }
}
END {
  pre = (prefix != "") ? (prefix "\t") : ""
  for (i = 1; i <= n_active; i++) {
    r = active_order[i]
    if (only_active) print pre r
    else print pre "active\t" r
  }
  if (!only_active) {
    for (i = 1; i <= n_archived; i++) {
      r = archived_order[i]
      if (!(r in active_seen)) print pre "archived\t" r
    }
  }
}
