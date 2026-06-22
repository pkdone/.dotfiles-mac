#!/usr/bin/env bash
#
# defaults-diff.sh — discover which macOS `defaults` key backs a System Settings toggle.
#
# Workflow:
#   defaults-diff.sh snapshot before     # capture current state
#   ...change ONE setting in System Settings...
#   defaults-diff.sh snapshot after      # capture again
#   defaults-diff.sh diff                # print changed keys as macos-defaults.list rows
#
# Snapshots are flat TSV (domain<TAB>key<TAB>type<TAB>value) covering every domain
# (`defaults domains` + NSGlobalDomain), written to the gitignored discovery/ dir.
# Only scalar top-level keys (bool/int/float/string) are captured — those are what the
# managed list holds.
#
# Read-only against the system; writes nothing outside discovery/.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCDIR="$DOTDIR/discovery"

usage() {
  cat <<'USAGE'
Usage: defaults-diff.sh <command>
  snapshot <label>   Capture all scalar defaults to discovery/snapshot-<label>.tsv
  diff               Compare the two most recent snapshots; emit changed keys as
                     pipe-delimited rows ready to paste into lib/macos-defaults.list
  -h, --help         Show this help.

Typical: snapshot before  ->  change one setting  ->  snapshot after  ->  diff
USAGE
}

snapshot() {
  local label="${1:-}"
  [ -n "$label" ] || { echo "usage: defaults-diff.sh snapshot <label>" >&2; exit 2; }
  mkdir -p "$DISCDIR"
  local out="$DISCDIR/snapshot-$label.tsv"
  # One python process enumerates domains and flattens each export to TSV.
  python3 - <<'PY' | LC_ALL=C sort > "$out"
import subprocess, plistlib
def sh(*a): return subprocess.run(a, capture_output=True).stdout
doms = sh('defaults', 'domains').decode('utf-8', 'replace')
domains = ['NSGlobalDomain'] + [d.strip() for d in doms.split(',') if d.strip()]
def typ(v):
    if isinstance(v, bool):  return 'bool'
    if isinstance(v, int):   return 'int'
    if isinstance(v, float): return 'float'
    if isinstance(v, str):   return 'string'
    return type(v).__name__
def val(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    return str(v).replace('\t', ' ').replace('\n', ' ')
for dom in domains:
    raw = sh('defaults', 'export', dom, '-')
    if not raw: continue
    try: data = plistlib.loads(raw)
    except Exception: continue
    if not isinstance(data, dict): continue
    for k in sorted(data.keys()):
        v = data[k]
        print(f"{dom}\t{k}\t{typ(v)}\t{val(v)}")
PY
  echo "Wrote $out ($(wc -l < "$out" | tr -d ' ') scalar keys)."
}

diff_snapshots() {
  local list
  list="$(ls -t "$DISCDIR"/snapshot-*.tsv 2>/dev/null)" || true
  [ -n "$list" ] || { echo "No snapshots in $DISCDIR. Run 'snapshot before' and 'snapshot after' first." >&2; exit 1; }
  local newest second
  newest="$(printf '%s\n' "$list" | sed -n 1p)"
  second="$(printf '%s\n' "$list" | sed -n 2p)"
  [ -n "$second" ] || { echo "Only one snapshot found; need two (before + after)." >&2; exit 1; }

  echo "# before: $(basename "$second")   after: $(basename "$newest")"
  echo "# Paste matching rows into lib/macos-defaults.list, then fill restart|area|label|display."
  echo "# Format: domain|key|type|desired|restart|area|label|display   (ignore unrelated churn)"
  echo "#"
  # awk: load 'before' values, then flag keys in 'after' that are new or changed.
  awk -F'\t' '
    NR==FNR { before[$1 SUBSEP $2] = $4; seen[$1 SUBSEP $2]=1; next }
    {
      k = $1 SUBSEP $2
      if (!(k in seen))        { tag = "NEW" }
      else if (before[k] != $4) { tag = "CHANGED " before[k] " -> " $4 }
      else                      { tag = "" }
      if (tag != "") {
        printf "# %s  (%s %s)\n", tag, $1, $2
        printf "%s|%s|%s|%s|RESTART?|AREA?|LABEL?|`%s`\n", $1, $2, $3, $4, $4
      }
    }
  ' "$second" "$newest"
}

case "${1:-}" in
  snapshot) shift; snapshot "${1:-}" ;;
  diff)     diff_snapshots ;;
  -h|--help|'') usage ;;
  *) echo "Unknown command: $1" >&2; usage; exit 2 ;;
esac
