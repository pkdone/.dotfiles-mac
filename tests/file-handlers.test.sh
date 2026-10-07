#!/usr/bin/env bash
#
# Unit tests for lib/file-handlers.py (Finder double-click defaults) and the
# shape of lib/file-handlers.list. A fake `duti` on PATH — never a real Launch
# Services database. Run: ./tests/file-handlers.test.sh
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/file-handlers.py"
REAL_LIST="$DIR/lib/file-handlers.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "file-handlers tests: python3 not found, skipped"; exit 0; fi

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
ok() {  # description status
  if [ "$2" = 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"

# Fake duti. DUTI_DB is a JSON object of ext -> bundle (missing or "" = no handler).
# DUTI_S_FAIL is a comma-separated list of extensions whose `duti -s` fails.
# DUTI_X_ERROR, when set, makes every `duti -x` fail with that stderr.
cat > "$bin/duti" <<'PY'
#!/usr/bin/env python3
import json, os, sys
log = os.environ["DUTI_LOG"]
db_path = os.environ["DUTI_DB"]
with open(log, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(sys.argv[1:]) + "\n")

def load():
    if not os.path.exists(db_path) or os.path.getsize(db_path) == 0:
        return {}
    with open(db_path, encoding="utf-8") as fh:
        return json.load(fh)

def save(db):
    with open(db_path, "w", encoding="utf-8") as fh:
        json.dump(db, fh)

argv = sys.argv[1:]
fail_s = set(filter(None, os.environ.get("DUTI_S_FAIL", "").split(",")))
lie_s = set(filter(None, os.environ.get("DUTI_S_LIE", "").split(",")))
x_error = os.environ.get("DUTI_X_ERROR", "")
lag = int(os.environ.get("DUTI_X_LAG", "0"))
DECLARED = {
    "html": ["public.html"],
    "htm": ["public.html"],
    "xhtml": ["public.xhtml"],
    "shtml": ["public.html"],
    "plist": ["com.apple.property-list", "com.apple.xml-property-list"],
}

def bare(typed):
    return typed[1:] if typed.startswith(".") else typed

if len(argv) == 2 and argv[0] == "-e":
    ext = bare(argv[1])
    for ident in DECLARED.get(ext, ["public.plain-text"]):
        sys.stdout.write("identifier: %s\n" % ident)
    raise SystemExit(0)

if len(argv) == 2 and argv[0] == "-x":
    ext = bare(argv[1])
    if x_error:
        sys.stderr.write(x_error + "\n")
        raise SystemExit(2)
    db = load()
    lag_map = db.get("_lag") or {}
    if ext in lag_map:
        left, reveal = lag_map[ext]
        if left > 0:
            lag_map[ext] = [left - 1, reveal]
            db["_lag"] = lag_map
            save(db)
            bundle = db.get(ext) or ""
            if not bundle:
                sys.stderr.write("Failed to get default application for extension '%s'\n" % ext)
                raise SystemExit(2)
            sys.stdout.write("App\n/Applications/App.app\n%s\n" % bundle)
            raise SystemExit(0)
        db[ext] = reveal
        del lag_map[ext]
        db["_lag"] = lag_map
        save(db)
    db = load()
    bundle = db.get(ext) or ""
    if not bundle:
        sys.stderr.write("Failed to get default application for extension '%s'\n" % ext)
        raise SystemExit(2)
    name = "Cursor Nightly" if bundle.startswith("co.anysphere") else "App"
    sys.stdout.write("%s\n/Applications/%s.app\n%s\n" % (name, name, bundle))
    raise SystemExit(0)

if len(argv) == 4 and argv[0] == "-s":
    bundle, typed, role = argv[1], argv[2], argv[3]
    if role != "all":
        sys.stderr.write("unexpected duti -s role\n")
        raise SystemExit(2)
    db = load()
    if typed.startswith("."):
        ext = typed[1:]
        if not ext:
            sys.stderr.write("unexpected duti -s shape\n")
            raise SystemExit(2)
        if ext in fail_s:
            sys.stderr.write("%s does not conform to any UTI hierarchy\n" % ext)
            raise SystemExit(1)
        if ext in lie_s:
            raise SystemExit(0)
        # .plist writes xml-property-list only. duti -x plist keeps reading
        # com.apple.property-list, which is a separate -s.
        if ext == "plist":
            db["_set_com.apple.xml-property-list"] = bundle
            save(db)
            raise SystemExit(0)
        if lag > 0:
            lag_map = db.get("_lag") or {}
            lag_map[ext] = [lag, bundle]
            db["_lag"] = lag_map
            save(db)
            raise SystemExit(0)
        db[ext] = bundle
        save(db)
        raise SystemExit(0)
    if "." not in typed:
        sys.stderr.write("failed to set %s as handler for %s (error -50)\n" % (bundle, typed))
        raise SystemExit(1)
    db["_set_" + typed] = bundle
    if typed == "com.apple.property-list":
        db["plist"] = bundle
    save(db)
    raise SystemExit(0)

sys.stderr.write("unexpected duti argv: %s\n" % argv)
raise SystemExit(99)
PY
chmod +x "$bin/duti" "$HELPER"

export PATH="$bin:$PATH"
export DUTI_LOG="$tmp/duti.log"
export DUTI_DB="$tmp/db.json"
export DUTI_S_FAIL=""
export DUTI_S_LIE=""
export DUTI_X_ERROR=""
export DUTI_X_LAG=0
export FILE_HANDLERS_SETTLE_SECS=5
: > "$DUTI_LOG"
printf '{}\n' > "$DUTI_DB"

run() { "$PY" "$HELPER" "$@"; }
s_calls() {
  "$PY" -c 'import json,sys
n=0
for line in open(sys.argv[1], encoding="utf-8"):
    a=json.loads(line)
    if a and a[0]=="-s":
        n+=1
        print(json.dumps(a))
print("count %d" % n)' "$1"
}

# ---- the real list is the mapping, and nothing else ----
rows() { awk -F'|' '$1 !~ /^#/ && NF { print $1 "|" $2 "|" $3 }' "$REAL_LIST"; }
exts() { rows | cut -d'|' -f1 | sort; }
eq "extensions, one per line" "$(printf '%s\n' \
  bash cfg conf css csv env fish ini js json list log markdown md plist sh swift text toml txt xml yaml yml zsh)" \
  "$(exts)"
eq "extensions are unique" "" "$(exts | uniq -d)"
eq "cursor extensions are js and swift" "$(printf '%s\n' js swift)" \
  "$(rows | awk -F'|' '$2 == "Cursor" { print $1 }' | sort)"
eq "cursor bundle is the stable cask" "com.todesktop.230313mzl4w4u92" \
  "$(rows | awk -F'|' '$2 == "Cursor" { print $3 }' | sort -u)"
eq "every other row is CotEditor" "" "$(rows | awk -F'|' '$2 != "Cursor" && !($2 == "CotEditor" && $3 == "com.coteditor.CotEditor") { print }')"
eq "24 extensions" 24 "$(rows | grep -c .)"
eq "html is not managed" "" "$(exts | grep -x html || true)"
eq "unpinnable extensions" "$(printf '%s\n' cfg env list)" \
  "$(awk -F'|' '$4 == "unpinnable" { print $1 }' "$REAL_LIST" | sort)"
eq "plist sets both property-list UTIs" "uti:com.apple.property-list,com.apple.xml-property-list" \
  "$(awk -F'|' '$1 == "plist" { print $4 }' "$REAL_LIST")"
bad_shape="$(awk -F'|' '$1 !~ /^#/ && NF {
  if (NF != 3 && NF != 4) print
  else if ($1 ~ /\./ || $1 != tolower($1)) print
  else if (NF == 4 && $4 != "unpinnable" && $4 !~ /^uti:/) print
}' "$REAL_LIST")"
eq "rows are ext|app|bundle with an optional flag" "" "$bad_shape"

# ---- read-only check: bundle id is the last duti -x line, not the app name ----
cat > "$tmp/small.list" <<'EOF'
# comment and blanks ignored

txt|CotEditor|com.coteditor.CotEditor
sh|CotEditor|com.coteditor.CotEditor
env|CotEditor|com.coteditor.CotEditor
js|Cursor|com.todesktop.230313mzl4w4u92
EOF
"$PY" -c 'import json,sys; json.dump({
  "txt": "com.coteditor.CotEditor",
  "sh": "com.mitchellh.ghostty",
  "js": "co.anysphere.cursor.nightly",
}, open(sys.argv[1],"w"))' "$DUTI_DB"
: > "$DUTI_LOG"
db_before="$(cat "$DUTI_DB")"
out="$(run "$tmp/small.list")"; rc=$?
eq "check with drift exits 0" 0 "$rc"
eq "check lines" "$(printf '%s\n' \
  'ok|txt|.txt -> CotEditor / com.coteditor.CotEditor' \
  'bad|sh|.sh -> com.mitchellh.ghostty (expected CotEditor / com.coteditor.CotEditor)' \
  'bad|env|.env -> unset (expected CotEditor / com.coteditor.CotEditor)' \
  'bad|js|.js -> co.anysphere.cursor.nightly (expected Cursor / com.todesktop.230313mzl4w4u92)')" "$out"
eq "check does not rewrite the handler db" "$db_before" "$(cat "$DUTI_DB")"
eq "check does not call duti -s" "" "$(s_calls "$DUTI_LOG" | grep '^\[' || true)"
has "check calls duti -x for env" '["-x", "env"]' "$(cat "$DUTI_LOG")"

# A duti -x failure that is not "no handler" is a warning, not drift to fix.
export DUTI_X_ERROR="duti: broken"
out="$(run "$tmp/small.list")"; rc=$?
eq "broken duti -x still exits 0" 0 "$rc"
eq "broken duti -x is warn, not bad" "" "$(printf '%s\n' "$out" | grep '^bad|' || true)"
has "broken duti -x names the error" "warn|txt|.txt: duti: broken" "$out"
export DUTI_X_ERROR=""

printf 'not|a valid row\n' > "$tmp/bad.list"
out="$(run "$tmp/bad.list")"; rc=$?
eq "malformed list on check exits 0" 0 "$rc"
has "malformed list is a warning" "warn||could not read the file-handler list" "$out"

# Leading dot in the list is the same extension.
printf '.env|CotEditor|com.coteditor.CotEditor\n' > "$tmp/dot.list"
"$PY" -c 'import json,sys; json.dump({"env":"com.coteditor.CotEditor"}, open(sys.argv[1],"w"))' "$DUTI_DB"
out="$(run "$tmp/dot.list")"
eq "leading dot still matches" "ok|env|.env -> CotEditor / com.coteditor.CotEditor" "$out"

# ---- apply: only drifted rows, always `duti -s <bundle> .<ext> all` ----
"$PY" -c 'import json,sys; json.dump({
  "txt": "com.coteditor.CotEditor",
  "sh": "com.mitchellh.ghostty",
  "js": "co.anysphere.cursor.nightly",
}, open(sys.argv[1],"w"))' "$DUTI_DB"
: > "$DUTI_LOG"
out="$(run --apply --dry-run "$tmp/small.list")"; rc=$?
eq "dry-run exits 0" 0 "$rc"
has "dry-run would set sh" "dry|sh|.sh: com.mitchellh.ghostty -> CotEditor / com.coteditor.CotEditor" "$out"
has "dry-run would set unset env" "dry|env|.env: unset -> CotEditor / com.coteditor.CotEditor" "$out"
eq "dry-run does not call duti -s" "" "$(s_calls "$DUTI_LOG" | grep '^\[' || true)"
has "dry-run still reads duti -x" '["-x", "txt"]' "$(cat "$DUTI_LOG")"

: > "$DUTI_LOG"
out="$(run --apply "$tmp/small.list")"; rc=$?
eq "apply exits 0" 0 "$rc"
has "apply leaves a match alone" "ok|txt|.txt already CotEditor / com.coteditor.CotEditor" "$out"
has "apply sets sh" "chg|sh|.sh: com.mitchellh.ghostty -> CotEditor / com.coteditor.CotEditor" "$out"
has "apply sets env with no UTI handler" "chg|env|.env: unset -> CotEditor / com.coteditor.CotEditor" "$out"
has "apply sets js off Nightly" "chg|js|.js: co.anysphere.cursor.nightly -> Cursor / com.todesktop.230313mzl4w4u92" "$out"
eq "duti -s argv" "$(printf '%s\n' \
  '["-s", "com.coteditor.CotEditor", ".sh", "all"]' \
  '["-s", "com.coteditor.CotEditor", ".env", "all"]' \
  '["-s", "com.todesktop.230313mzl4w4u92", ".js", "all"]' \
  'count 3')" "$(s_calls "$DUTI_LOG")"

out="$(run "$tmp/small.list")"; rc=$?
eq "check is clean after apply" 0 "$rc"
eq "no remaining drift" "" "$(printf '%s\n' "$out" | grep '^bad|' || true)"
eq "four ok after apply" 4 "$(printf '%s\n' "$out" | grep -c '^ok|')"

: > "$DUTI_LOG"
out="$(run --apply "$tmp/small.list")"; rc=$?
eq "second apply exits 0" 0 "$rc"
eq "second apply calls no duti -s" "" "$(s_calls "$DUTI_LOG" | grep '^\[' || true)"
eq "second apply is all already-set" "" "$(printf '%s\n' "$out" | grep -v '^ok|' || true)"

# --only, unknown extension, and a duti -s refusal (dynamic UTI rejected).
: > "$DUTI_LOG"
"$PY" -c 'import json,sys; json.dump({}, open(sys.argv[1],"w"))' "$DUTI_DB"
out="$(run --apply --only sh,nope "$tmp/small.list")"; rc=$?
eq "unknown --only fails the apply" 1 "$rc"
has "unknown extension is refused" "refuse|nope|not in lib/file-handlers.list" "$out"
eq "only the named extension is set" '["-s", "com.coteditor.CotEditor", ".sh", "all"]
count 1' "$(s_calls "$DUTI_LOG")"
eq "env was not filled in by --only sh" "" "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("env",""))' "$DUTI_DB")"

export DUTI_S_FAIL="env,list"
"$PY" -c 'import json,sys; json.dump({}, open(sys.argv[1],"w"))' "$DUTI_DB"
printf '%s\n' 'env|CotEditor|com.coteditor.CotEditor' 'list|CotEditor|com.coteditor.CotEditor' 'txt|CotEditor|com.coteditor.CotEditor' > "$tmp/dyn.list"
: > "$DUTI_LOG"
out="$(run --apply "$tmp/dyn.list")"; rc=$?
eq "duti -s refusal exits 1" 1 "$rc"
has "env refusal names duti -s" "fail|env|duti -s com.coteditor.CotEditor .env all failed: env does not conform to any UTI hierarchy" "$out"
has "list refusal is reported too" "fail|list|duti -s com.coteditor.CotEditor .list all failed:" "$out"
has "a sibling extension is still set" "chg|txt|.txt: unset -> CotEditor / com.coteditor.CotEditor" "$out"
eq "refused extensions are not stored" "" "$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.stdout.write(d.get("env","")+d.get("list",""))' "$DUTI_DB")"
export DUTI_S_FAIL=""

# duti -s exits 0 but the handler does not change: report it, don't claim chg.
export DUTI_S_LIE="env"
export FILE_HANDLERS_SETTLE_SECS=0.4
"$PY" -c 'import json,sys; json.dump({}, open(sys.argv[1],"w"))' "$DUTI_DB"
printf '%s\n' 'env|CotEditor|com.coteditor.CotEditor' > "$tmp/lie.list"
out="$(run --apply "$tmp/lie.list")"; rc=$?
eq "a set that does not stick exits 1" 1 "$rc"
has "a set that does not stick is fail" "fail|env|duti -s com.coteditor.CotEditor .env all did not stick after 0.4s: duti -x still shows unset" "$out"
export DUTI_S_LIE=""
export FILE_HANDLERS_SETTLE_SECS=5

# Launch Services applies a moment after duti returns. Poll before failing.
export DUTI_X_LAG=3
export FILE_HANDLERS_SETTLE_SECS=3
"$PY" -c 'import json,sys; json.dump({"sh":"com.mitchellh.ghostty"}, open(sys.argv[1],"w"))' "$DUTI_DB"
printf '%s\n' 'sh|CotEditor|com.coteditor.CotEditor' > "$tmp/lag.list"
: > "$DUTI_LOG"
out="$(run --apply "$tmp/lag.list")"; rc=$?
eq "a late duti -x read still counts as set" 0 "$rc"
has "late read is a change, not a failure" "chg|sh|.sh: com.mitchellh.ghostty -> CotEditor / com.coteditor.CotEditor" "$out"
export DUTI_X_LAG=0
export FILE_HANDLERS_SETTLE_SECS=5

# Browser extensions, browser UTIs, and URL schemes are never passed to duti -s.
cat > "$tmp/guard.list" <<'EOF'
html|CotEditor|com.coteditor.CotEditor
htm|CotEditor|com.coteditor.CotEditor
xhtml|CotEditor|com.coteditor.CotEditor
shtml|CotEditor|com.coteditor.CotEditor
http|CotEditor|com.coteditor.CotEditor
https|Google Chrome|com.google.Chrome
mailto|CotEditor|com.coteditor.CotEditor
txt|CotEditor|com.coteditor.CotEditor
plist|CotEditor|com.coteditor.CotEditor|uti:public.html
EOF
"$PY" -c 'import json,sys; json.dump({}, open(sys.argv[1],"w"))' "$DUTI_DB"
: > "$DUTI_LOG"
out="$(run --apply "$tmp/guard.list")"; rc=$?
eq "browser guard fails the apply" 1 "$rc"
has "html is refused" "refuse|html|refusing .html: tied to the default web browser" "$out"
has "htm is refused" "refuse|htm|refusing .htm:" "$out"
has "xhtml is refused" "refuse|xhtml|refusing .xhtml:" "$out"
has "shtml is refused via its UTI" "refuse|shtml|refusing .shtml:" "$out"
has "http scheme is refused" "refuse|http|refusing http: URL schemes are not file handlers" "$out"
has "https scheme is refused" "refuse|https|refusing https: URL schemes are not file handlers" "$out"
has "mailto scheme is refused" "refuse|mailto|refusing mailto: URL schemes are not file handlers" "$out"
has "public.html UTI is refused" "refuse|plist|refusing .plist:" "$out"
has "a safe extension is still set" "chg|txt|.txt: unset -> CotEditor / com.coteditor.CotEditor" "$out"
eq "guard calls duti -s only for txt" '["-s", "com.coteditor.CotEditor", ".txt", "all"]
count 1' "$(s_calls "$DUTI_LOG")"
eq "guard never sets a browser UTI or scheme" "" "$(s_calls "$DUTI_LOG" | grep -e html -e htm -e xhtml -e http -e https -e mailto -e public.html || true)"

# Missing duti: check warns, apply fails closed.
export PATH="/usr/bin:/bin"
out="$(run "$tmp/small.list")"; rc=$?
eq "missing duti check exits 0" 0 "$rc"
has "missing duti is a warning" "warn||duti not installed" "$out"
out="$(run --apply --only env "$tmp/small.list")"; rc=$?
eq "missing duti apply exits 1" 1 "$rc"
has "missing duti apply does not pretend to set" "fail|env|duti not installed — file handler not changed" "$out"
export PATH="$bin:$PATH"

# handlers.sh --list prints the file-handler rows without calling duti.
: > "$DUTI_LOG"
list_out="$("$DIR/handlers.sh" --list)"
tick='`'
has "handlers --list shows a CotEditor extension" "| ${tick}txt${tick} | ${tick}CotEditor${tick} | ${tick}com.coteditor.CotEditor${tick} |" "$list_out"
has "handlers --list shows Cursor js" "| ${tick}js${tick} | ${tick}Cursor${tick} | ${tick}com.todesktop.230313mzl4w4u92${tick} |" "$list_out"
has "handlers --list still shows mailto" "| ${tick}mailto${tick} | ${tick}com.google.Chrome${tick} |" "$list_out"
has "handlers --list shows https" "| ${tick}https${tick} | ${tick}com.google.Chrome${tick} |" "$list_out"
eq "http and https are Chrome in url-handlers.list" "com.google.Chrome" \
  "$(awk -F'|' '$1 == "http" || $1 == "https" { print $2 }' "$DIR/lib/url-handlers.list" | sort -u)"
eq "handlers --list does not call duti" "" "$(cat "$DUTI_LOG")"

# The real list applies pinnable rows. cfg/env/list are info, not duti -s.
# .plist also sets com.apple.property-list, which is what duti -x plist reads.
"$PY" -c 'import json,sys; json.dump({"plist":"com.todesktop.230313mzl4w4u92"}, open(sys.argv[1],"w"))' "$DUTI_DB"
: > "$DUTI_LOG"
out="$(run --apply "$REAL_LIST")"; rc=$?
eq "real list apply exits 0" 0 "$rc"
eq "real list sets every pinnable extension" 21 "$(printf '%s\n' "$out" | grep -c '^chg|')"
eq "real list reports unpinnable rows" 3 "$(printf '%s\n' "$out" | grep -c '^info|')"
eq "real list duti -s count" 23 "$(s_calls "$DUTI_LOG" | awk 'END { print }' | awk '{ print $2 }')"
has "plist sets com.apple.property-list" '["-s", "com.coteditor.CotEditor", "com.apple.property-list", "all"]' "$(s_calls "$DUTI_LOG")"
has "plist sets com.apple.xml-property-list" '["-s", "com.coteditor.CotEditor", "com.apple.xml-property-list", "all"]' "$(s_calls "$DUTI_LOG")"
eq "real list does not set html cfg env or list" "" "$(s_calls "$DUTI_LOG" | grep -F -e '".html"' -e '".cfg"' -e '".env"' -e '".list"' -e 'public.html' || true)"
out="$(run "$REAL_LIST")"
eq "real list has no drift" "" "$(printf '%s\n' "$out" | grep '^bad|' || true)"
eq "real list pinnable rows ok" 21 "$(printf '%s\n' "$out" | grep -c '^ok|')"
eq "real list unpinnable rows are info" 3 "$(printf '%s\n' "$out" | grep -c '^info|')"

# handlers.sh --dry-run uses the same helper (bootstrap step 6). URL schemes
# hit the fake duti's -d and come back unset; file rows are already applied.
: > "$DUTI_LOG"
dry_out="$("$DIR/handlers.sh" --dry-run)"
dry_rc=$?
eq "handlers dry-run exits 0" 0 "$dry_rc"
has "handlers dry-run sees a pinned extension" "ok      .txt already CotEditor / com.coteditor.CotEditor" "$dry_out"
has "handlers dry-run finishes" "Dry run complete." "$dry_out"
eq "handlers dry-run does not call duti -s" "" "$(s_calls "$DUTI_LOG" | grep '^\[' || true)"

printf 'file-handlers tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
