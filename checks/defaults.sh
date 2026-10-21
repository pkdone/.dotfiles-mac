# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# Domains may be prefixed with @host/ to use `defaults -currentHost` (ByHost plists).
defaults_read() {  # domain key
  case "$1" in
    @host/*) defaults -currentHost read "${1#@host/}" "$2" ;;
    *)       defaults read "$1" "$2" ;;
  esac
}
defaults_read_type() {  # domain key
  case "$1" in
    @host/*) defaults -currentHost read-type "${1#@host/}" "$2" ;;
    *)       defaults read-type "$1" "$2" ;;
  esac
}

# ---- 3. macOS defaults --------------------------------------------------
hdr "macOS defaults"
while IFS='|' read -r domain key etype desired _restart _area _label _disp tol; do
  case "$domain" in ''|'#'*) continue ;; esac
  CHECKED=$((CHECKED + 1))
  fixid defaults "$domain|$key"
  desired="${desired//@HOME@/$HOME}"
  want_token="$(type_token "$etype")"
  # location is @HOME@/Pictures/Screenshots. A missing folder is drift so --fix
  # (macos.sh) mkdir -p's it before writing. The message uses a literal ~, not a
  # hardcoded home.
  shot_dir_missing=0
  shot_shown="$desired"
  case "$desired" in
    "$HOME"|"$HOME"/*) shot_shown="~${desired#"$HOME"}" ;;
  esac
  if [ "$domain" = com.apple.screencapture ] && [ "$key" = location ] && [ ! -d "$desired" ]; then
    shot_dir_missing=1
  fi
  shot_dir_msg="$domain $key — directory $shot_shown missing (mkdir -p before setting it)"
  if cur="$(defaults_read "$domain" "$key" 2>/dev/null)"; then
    curtype="$(defaults_read_type "$domain" "$key" 2>/dev/null || true)"
    curtype="${curtype##* }"
    # video On is integer 1 or boolean true. Either type with that value is clean.
    video_flex=0
    if [ "$domain" = com.apple.screencapture ] && [ "$key" = video ]; then
      case "$curtype" in
        boolean|integer) video_flex=1 ;;
      esac
    fi
    if [ "$video_flex" = 1 ] && screencapture_video_matches "$curtype" "$cur" "$desired"; then
      if [ "$shot_dir_missing" = 1 ]; then
        bad "$shot_dir_msg"
      else
        pass "$domain $key = $cur"
      fi
    elif [ "$video_flex" = 0 ] && [ "$curtype" != "$want_token" ]; then
      bad "$domain $key — type mismatch (expected $want_token, found ${curtype:-none})"
      if [ "$shot_dir_missing" = 1 ]; then bad "$shot_dir_msg"; fi
    elif values_match "$etype" "$cur" "$desired" "$tol"; then
      if [ "$shot_dir_missing" = 1 ]; then
        bad "$shot_dir_msg"
      elif [ -n "$tol" ] && [ "$tol" != 0 ] && ! values_equal "$etype" "$cur" "$desired"; then
        pass "$domain $key = $cur (within ±$tol of $desired)"
      else
        pass "$domain $key = $cur"
      fi
    else
      bad "$domain $key = $cur (expected $desired)"
      if [ "$shot_dir_missing" = 1 ]; then bad "$shot_dir_msg"; fi
    fi
  else
    bad "$domain $key — not set (expected $desired)"
    if [ "$shot_dir_missing" = 1 ]; then bad "$shot_dir_msg"; fi
  fi
done < "$DOTDIR/lib/macos-defaults.list"

# AppleActionOnDoubleClick = Fill is the row above. The older key minimizes
# on double-click and fights Fill. It is unset on this Mac. If it shows up,
# --fix deletes it. A missing `defaults` command (this check on Linux) counts
# as unset.
CHECKED=$((CHECKED + 1))
fixid titlebar-double-click
if defaults read NSGlobalDomain AppleMiniaturizeOnDoubleClick >/dev/null 2>&1; then
  bad "NSGlobalDomain AppleMiniaturizeOnDoubleClick is set (double-click should fill the window). macconfig --fix removes it"
else
  pass "NSGlobalDomain AppleMiniaturizeOnDoubleClick is unset"
fi
