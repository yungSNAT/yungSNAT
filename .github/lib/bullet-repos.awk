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
{ sub(/\r$/, "") }
/^[ \t]*(```|~~~)/ { in_fence = !in_fence; next }
in_fence { next }
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
