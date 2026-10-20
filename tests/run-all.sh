#!/usr/bin/env bash
#
# tests/run-all.sh — one entry point for the shell unit tests and shellcheck.
#
# Discovers tests/*.test.sh, plus any other ./tests/*.sh named by hooks/pre-push
# (so a hook entry point that doesn't match the glob still runs). Runs them in
# parallel. Prints a per-suite pass/fail summary and exits non-zero if any
# suite fails.
#
#   tests/run-all.sh                         # tests only
#   tests/run-all.sh --shellcheck changed    # tests + shellcheck of .sh files
#                                            # changed versus the remote
#   tests/run-all.sh --shellcheck all        # tests + shellcheck of every .sh
#   tests/run-all.sh --shellcheck all --no-tests
#   tests/run-all.sh --jobs N
#   tests/run-all.sh --mac-home [name]
#
# --shellcheck changed reads the pre-push ref lines on stdin
# (`<local ref> <local sha> <remote ref> <remote sha>`). When that remote
# commit can't be resolved (no stdin, a new branch, or a missing object) it
# diffs against @{upstream}, and if that isn't available either it shellchecks
# every .sh file. --shellcheck all always checks every .sh file.
#
# --mac-home copies this repo to /Users/<name>/.dotfiles-mac-style, points
# HOME at /Users/<name>, and runs the suite there. The default name is the
# account whose checkout used to pass in CI and fail locally. On Linux, where
# that directory doesn't exist, it is created (sudo -n) so the path is real.
#
# Bash 3.2-safe (stock macOS bash): no mapfile, no associative arrays.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: tests/run-all.sh [options]
  --jobs N                 Parallel jobs (default: number of CPUs, at least 1).
  --shellcheck changed     Shellcheck .sh files changed versus the remote.
  --shellcheck all         Shellcheck every .sh file.
  --no-tests               Do not run tests/*.test.sh.
  --mac-home [name]        Copy the repo under /Users/<name>/.dotfiles-mac-style,
                           set HOME, and run there. Default name: pdone.
  -h, --help               Show this help.
A missing shellcheck binary is skipped for --shellcheck changed (local hook)
and is a failure for --shellcheck all (CI).
EOF
}

JOBS=""
SHELLCHECK_MODE=""
DO_TESTS=1
MAC_HOME=0
# Default account: the checkout that passed in CI and failed locally.
MAC_NAME="pdone"

while [ $# -gt 0 ]; do
  case "$1" in
    --jobs)
      [ $# -ge 2 ] || { echo "tests/run-all.sh: --jobs needs a number" >&2; exit 2; }
      JOBS="$2"
      shift 2
      ;;
    --shellcheck)
      [ $# -ge 2 ] || { echo "tests/run-all.sh: --shellcheck needs changed or all" >&2; exit 2; }
      case "$2" in
        changed|all) SHELLCHECK_MODE="$2" ;;
        *) echo "tests/run-all.sh: --shellcheck must be changed or all" >&2; exit 2 ;;
      esac
      shift 2
      ;;
    --no-tests) DO_TESTS=0; shift ;;
    --mac-home)
      MAC_HOME=1
      shift
      if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
        MAC_NAME="$1"
        shift
      fi
      ;;
    -h|--help) usage; exit 0 ;;
    --worker|--shellcheck-worker) break ;;
    *) echo "tests/run-all.sh: unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# Internal: one test, invoked by xargs. Always exits 0; the status is a file.
if [ "${1:-}" = "--worker" ]; then
  shift
  cd "$ROOT" || exit 1
  name="$(basename "$1")"
  "$1" >"$RUN_ALL_WORK/$name.out" 2>&1
  echo $? >"$RUN_ALL_WORK/$name.rc"
  exit 0
fi

if [ "${1:-}" = "--shellcheck-worker" ]; then
  cd "$ROOT" || exit 1
  mode="$(cat "$RUN_ALL_WORK/shellcheck.mode")"
  if ! command -v shellcheck >/dev/null 2>&1; then
    if [ "$mode" = "all" ]; then
      echo "shellcheck not installed" >"$RUN_ALL_WORK/shellcheck.out"
      echo 1 >"$RUN_ALL_WORK/shellcheck.rc"
    else
      echo "shellcheck not installed — skipping (it's in the Brewfile)" >"$RUN_ALL_WORK/shellcheck.out"
      echo 0 >"$RUN_ALL_WORK/shellcheck.rc"
    fi
    exit 0
  fi
  sh_files=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    sh_files+=("$f")
  done <"$RUN_ALL_WORK/shellcheck.files"
  if [ "${#sh_files[@]}" -eq 0 ]; then
    if [ "$mode" = "changed" ]; then
      echo "no changed .sh files" >"$RUN_ALL_WORK/shellcheck.out"
    else
      echo "no .sh files" >"$RUN_ALL_WORK/shellcheck.out"
    fi
    echo 0 >"$RUN_ALL_WORK/shellcheck.rc"
    exit 0
  fi
  shellcheck "${sh_files[@]}" >"$RUN_ALL_WORK/shellcheck.out" 2>&1
  echo $? >"$RUN_ALL_WORK/shellcheck.rc"
  exit 0
fi

case "$MAC_NAME" in
  ''|*[!A-Za-z0-9._-]*)
    echo "tests/run-all.sh: mac-home name must be [A-Za-z0-9._-]" >&2
    exit 2
    ;;
esac

if [ -z "$JOBS" ]; then
  JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)"
fi
case "$JOBS" in
  ''|*[!0-9]*|0) JOBS=1 ;;
esac

# Copy under a Mac-like home and re-exec without --mac-home so this doesn't recurse.
if [ "$MAC_HOME" = 1 ] && [ -z "${RUN_ALL_INSIDE_MAC_HOME:-}" ]; then
  parent="/Users/${MAC_NAME}"
  dest="${parent}/.dotfiles-mac-style"
  # Removing the directory needs write permission on /Users, which is root's.
  created_parent=0
  if [ ! -d "$parent" ]; then
    created_parent=1
    if ! sudo -n mkdir -p "$parent"; then
      echo "tests/run-all.sh: cannot create ${parent} (sudo -n mkdir failed)" >&2
      exit 1
    fi
    sudo -n chown "$(id -u):$(id -g)" "$parent" || {
      echo "tests/run-all.sh: cannot chown ${parent}" >&2
      exit 1
    }
  fi
  if [ ! -w "$parent" ]; then
    echo "tests/run-all.sh: ${parent} is not writable" >&2
    exit 1
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -a "$ROOT"/. "$dest"/ || {
    echo "tests/run-all.sh: copy to ${dest} failed" >&2
    exit 1
  }
  child=()
  [ -n "$JOBS" ] && child+=(--jobs "$JOBS")
  [ -n "$SHELLCHECK_MODE" ] && child+=(--shellcheck "$SHELLCHECK_MODE")
  [ "$DO_TESTS" = 0 ] && child+=(--no-tests)
  echo "tests/run-all.sh: mac-style home ${dest} (HOME=${parent})"
  HOME="$parent" USER="$MAC_NAME" LOGNAME="$MAC_NAME" RUN_ALL_INSIDE_MAC_HOME=1 \
    "$dest/tests/run-all.sh" "${child[@]+"${child[@]}"}"
  rc=$?
  rm -rf "$dest"
  if [ "$created_parent" = 1 ]; then
    # HOME may have gained files during the suite. Drop the directory we created.
    sudo -n rm -rf "$parent" 2>/dev/null || rm -rf "$parent" 2>/dev/null || true
    sudo -n rmdir /Users 2>/dev/null || true
  fi
  exit "$rc"
fi

cd "$ROOT" || exit 1

work="$(mktemp -d "${TMPDIR:-/tmp}/run-all.XXXXXX")"
trap 'rm -rf "$work"' EXIT
export RUN_ALL_WORK="$work"

# ---- which .sh files shellcheck sees ------------------------------------
list_all_sh() {
  find "$ROOT" -type f -name '*.sh' -not -path '*/.git/*' | sed "s|^$ROOT/||" | sort
}

# Print changed paths on stdout. Return 1 when the remote commit can't be
# worked out (caller falls back). $1 is the pre-push stdin, possibly empty.
list_changed_sh() {
  local refs="$1" local_sha remote_sha zero tmp parsed=0
  zero="0000000000000000000000000000000000000000"
  tmp="$(mktemp)"
  while read -r _ local_sha _ remote_sha _; do
    [ -n "${local_sha:-}" ] || continue
    parsed=1
    if [ "$local_sha" = "$zero" ]; then
      continue
    fi
    if [ "$remote_sha" = "$zero" ] \
      || ! git cat-file -e "${remote_sha}^{commit}" >/dev/null 2>&1 \
      || ! git cat-file -e "${local_sha}^{commit}" >/dev/null 2>&1; then
      rm -f "$tmp"
      return 1
    fi
    if ! git diff --name-only --diff-filter=ACMR "$remote_sha" "$local_sha" -- '*.sh' >>"$tmp"; then
      rm -f "$tmp"
      return 1
    fi
  done <<EOF
$refs
EOF
  if [ "$parsed" -eq 0 ]; then
    rm -f "$tmp"
    if git rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1; then
      git diff --name-only --diff-filter=ACMR '@{upstream}...HEAD' -- '*.sh' | sort -u
      return $?
    fi
    return 1
  fi
  sort -u "$tmp"
  rm -f "$tmp"
  return 0
}

shellcheck_note=""
if [ -n "$SHELLCHECK_MODE" ]; then
  : >"$work/shellcheck.files"
  printf '%s\n' "$SHELLCHECK_MODE" >"$work/shellcheck.mode"
  if [ "$SHELLCHECK_MODE" = "all" ]; then
    list_all_sh >"$work/shellcheck.files"
    shellcheck_note="all $(grep -c . "$work/shellcheck.files" || true) script(s)"
  else
    refs=""
    if [ ! -t 0 ]; then
      refs="$(cat || true)"
    fi
    if list_changed_sh "$refs" >"$work/shellcheck.files"; then
      shellcheck_note="changed $(grep -c . "$work/shellcheck.files" || true) script(s)"
    else
      list_all_sh >"$work/shellcheck.files"
      shellcheck_note="all $(grep -c . "$work/shellcheck.files" || true) script(s); remote unknown"
      echo "tests/run-all.sh: shellcheck could not see the remote commit — checking every .sh file" >&2
    fi
  fi
fi

# ---- discover suites -----------------------------------------------------
tests=()
if [ "$DO_TESTS" = 1 ]; then
  seen=" "
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    case "$seen" in *" $base "*) continue ;; esac
    seen="$seen$base "
    tests+=("$f")
  done <<EOF
$(find "$ROOT/tests" -maxdepth 1 -type f -name '*.test.sh' | sort)
EOF
  if [ -f "$ROOT/hooks/pre-push" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      f="${f#./}"
      case "$f" in
        tests/run-all.sh) continue ;;
        tests/*.sh) ;;
        *) continue ;;
      esac
      [ -f "$ROOT/$f" ] || continue
      base="$(basename "$f")"
      case "$seen" in *" $base "*) continue ;; esac
      seen="$seen$base "
      tests+=("$ROOT/$f")
    done <<EOF
$(grep -oE '\./tests/[A-Za-z0-9._/-]+\.sh' "$ROOT/hooks/pre-push" || true)
EOF
  fi
fi

if [ "$DO_TESTS" = 1 ] && [ "${#tests[@]}" -eq 0 ]; then
  echo "tests/run-all.sh: no tests discovered under tests/" >&2
  exit 1
fi

started=$SECONDS
if [ "$DO_TESTS" = 1 ]; then
  echo "tests/run-all.sh: ${#tests[@]} suite(s), ${JOBS} job(s)"
elif [ -n "$SHELLCHECK_MODE" ]; then
  echo "tests/run-all.sh: shellcheck only"
else
  echo "tests/run-all.sh: nothing to run (pass tests and/or --shellcheck)" >&2
  exit 2
fi

sc_pid=""
if [ -n "$SHELLCHECK_MODE" ]; then
  "$ROOT/tests/run-all.sh" --shellcheck-worker &
  sc_pid=$!
fi

if [ "$DO_TESTS" = 1 ]; then
  printf '%s\0' "${tests[@]}" | xargs -0 -P "$JOBS" -n 1 "$ROOT/tests/run-all.sh" --worker
fi

if [ -n "$sc_pid" ]; then
  wait "$sc_pid" || true
fi

# ---- summary -------------------------------------------------------------
passed=0
failed=0
report() { # label rcfile outfile
  local label="$1" rcfile="$2" outfile="$3" rc
  if [ ! -f "$rcfile" ]; then
    failed=$((failed + 1))
    printf '  FAIL  %s (no result)\n' "$label"
    return
  fi
  rc="$(cat "$rcfile")"
  if [ "$rc" = 0 ]; then
    passed=$((passed + 1))
    printf '  PASS  %s\n' "$label"
  else
    failed=$((failed + 1))
    printf '  FAIL  %s\n' "$label"
  fi
}

if [ -n "$SHELLCHECK_MODE" ]; then
  report "shellcheck (${shellcheck_note})" "$work/shellcheck.rc" "$work/shellcheck.out"
fi
if [ "$DO_TESTS" = 1 ]; then
  for f in "${tests[@]}"; do
    base="$(basename "$f")"
    report "$base" "$work/$base.rc" "$work/$base.out"
  done
fi

echo "tests/run-all.sh: ${passed} passed, ${failed} failed in $((SECONDS - started))s"

show_log() { # label outfile rcfile
  local label="$1" outfile="$2" rcfile="$3" rc="1"
  [ -f "$rcfile" ] && rc="$(cat "$rcfile")"
  [ "$rc" = 0 ] && return 0
  printf '\n----- %s -----\n' "$label"
  if [ -f "$outfile" ]; then
    cat "$outfile"
  else
    echo "(no output)"
  fi
}

if [ "$failed" -ne 0 ]; then
  if [ -n "$SHELLCHECK_MODE" ]; then
    show_log "shellcheck" "$work/shellcheck.out" "$work/shellcheck.rc"
  fi
  if [ "$DO_TESTS" = 1 ]; then
    for f in "${tests[@]}"; do
      base="$(basename "$f")"
      show_log "$base" "$work/$base.out" "$work/$base.rc"
    done
  fi
  exit 1
fi
exit 0
