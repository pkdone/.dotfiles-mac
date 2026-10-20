# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.

# norm_path PATH — collapse . and .. without requiring the path to exist.
norm_path() {
  if [ -n "${DOT_PYTHON:-}" ]; then
    "$DOT_PYTHON" -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$1"
  else
    printf '%s\n' "$1"
  fi
}

# broken_repo_symlinks HOME — print broken symlink paths that point into the
# dotfiles repo. A line "TIMEOUT" means find was killed. Read-only.
broken_repo_symlinks() {
  local home="$1" list rc top link target abs root seen=" "
  local roots=()
  [ -d "$home/.config" ] || [ -L "$home/.config" ] && roots+=("$home/.config")
  [ -d "$home/Library/LaunchAgents" ] || [ -L "$home/Library/LaunchAgents" ] && roots+=("$home/Library/LaunchAgents")
  rc=0
  list=""
  if [ "${#roots[@]}" -gt 0 ]; then
    list="$(with_timeout 20 find -P "${roots[@]}" -type l -print 2>/dev/null)" || rc=$?
  fi
  if [ "$rc" = 142 ]; then
    printf 'TIMEOUT\n'
  fi
  rc=0
  top="$(with_timeout 10 find -P "$home" -maxdepth 1 -name '.*' -type l -print 2>/dev/null)" || rc=$?
  if [ "$rc" = 142 ]; then
    printf 'TIMEOUT\n'
  fi
  list="${list}"$'\n'"${top}"
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    [ -L "$link" ] || continue
    [ -e "$link" ] && continue
    case "$seen" in
      *" $link "*) continue ;;
    esac
    seen="$seen$link "
    target="$(readlink "$link" || true)"
    [ -n "$target" ] || continue
    case "$target" in
      /*) abs="$(norm_path "$target")" ;;
      *) abs="$(norm_path "$(dirname "$link")/$target")" ;;
    esac
    for root in "$DOTDIR" "$home/.dotfiles-mac"; do
      [ -n "$root" ] || continue
      case "$abs" in
        "$root"|"$root"/*)
          printf '%s\n' "$link"
          break
          ;;
      esac
    done
  done <<EOF
$list
EOF
}

check_broken_dotfiles_symlinks() {
  local out link shown n=0
  fixid broken-symlink
  out="$(broken_repo_symlinks "$HOME" || true)"
  if printf '%s\n' "$out" | grep -qx 'TIMEOUT'; then
    CHECKED=$((CHECKED + 1))
    warn "symlink scan timed out before it finished (~/.config, ~/Library/LaunchAgents, home dotfiles)"
  fi
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    [ "$link" = TIMEOUT ] && continue
    n=$((n + 1))
    CHECKED=$((CHECKED + 1))
    shown="$link"
    case "$shown" in
      "$HOME"/*) shown="~${shown#"$HOME"}" ;;
    esac
    fixid broken-symlink
    warn "broken symlink $shown points into the dotfiles repo but the target is missing"
  done <<EOF
$out
EOF
  if [ "$n" -eq 0 ] && ! printf '%s\n' "$out" | grep -qx 'TIMEOUT'; then
    CHECKED=$((CHECKED + 1))
    pass "no broken symlinks into the dotfiles repo (~/.config, ~/Library/LaunchAgents, home dotfiles)"
  fi
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 1. symlinks --------------------------------------------------------
hdr "Symlinks"
check_link() {  # target  expected-source
  local target="$1" expected="$2"
  CHECKED=$((CHECKED + 1))
  fixid symlink "$target|$expected"
  if [ ! -L "$target" ]; then
    if [ -e "$target" ]; then
      bad "${target/#$HOME/~} — exists but is not a symlink"
    else
      bad "${target/#$HOME/~} — missing"
    fi
    return 0
  fi
  local actual; actual="$(readlink "$target")"
  if [ "$actual" != "$expected" ]; then
    bad "${target/#$HOME/~} -> $actual (expected $expected)"
  elif [ ! -e "$target" ]; then
    bad "${target/#$HOME/~} -> $expected (broken: source missing)"
  else
    pass "${target/#$HOME/~} -> repo"
  fi
}

# Static one-to-one links from lib/links.list (shared with install.sh).
while IFS='|' read -r src tgt; do
  case "$src" in ''|'#'*) continue ;; esac
  check_link "${tgt//@HOME@/$HOME}" "$DOTDIR/$src"
done < "$DOTDIR/lib/links.list"
# Fish functions: one-dir-to-many glob, handled as a special case.
for f in "$DOTDIR"/fish/functions/*.fish; do
  check_link "$HOME/.config/fish/functions/$(basename "$f")" "$f"
done
check_broken_dotfiles_symlinks
