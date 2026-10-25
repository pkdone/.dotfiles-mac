# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 7b. Finder file handlers -------------------------------------------
# Read-only here. lib/file-handlers.py runs `duti -x <ext>` (bundle id is the
# last line). --fix sets drifted extensions with `duti -s <bundle> .<ext> all`
# via the fileext fixer below.
hdr "File handlers"
fixid file-handler
FILE_HANDLERS_LIST="$DOTDIR/lib/file-handlers.list"
if [ ! -r "$FILE_HANDLERS_LIST" ]; then
  fixid repo-file; warn "lib/file-handlers.list missing — skipping file handlers check"
elif ! command -v duti >/dev/null 2>&1; then
  fixid tooling; warn "duti not installed — run brewsync (skipping file handlers check)"
elif ! PY="$(dot_python)"; then
  fixid tooling; warn "no python3 — skipping file handlers check"
else
  while IFS='|' read -r status ext msg; do
    [ -z "$status" ] && continue
    case "$status" in
      ok)   CHECKED=$((CHECKED + 1)); fixid file-handler "$ext"; pass "$msg" ;;
      bad)  CHECKED=$((CHECKED + 1)); fixid file-handler "$ext"; bad "$msg" ;;
      info) note "$msg" ;;
      # No declared file type (dyn.* / duti error -50). Not drift, and --fix
      # does not call duti. handlers.sh prints the same sentence as a warning.
      warn) note "$msg" ;;
      *)    CHECKED=$((CHECKED + 1)); fixid tooling; warn "${msg:-$ext}" ;;
    esac
  done < <("$PY" "$DOTDIR/lib/file-handlers.py" "$FILE_HANDLERS_LIST")
fi

# ---- Developer folder ---------------------------------------------------
# All repos are cloned under ~/Developer. install.sh creates it.
hdr "Folders"
fixid developer-folder
CHECKED=$((CHECKED + 1))
if [ -d "$HOME/Developer" ]; then
  pass "Developer folder ($HOME/Developer) exists"
else
  bad "Developer folder ($HOME/Developer) missing — run install.sh"
fi
