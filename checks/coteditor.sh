# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 13. CotEditor theme + font ----
hdr "CotEditor"
fixid coteditor
CHECKED=$((CHECKED + 1))
cot_theme="$(defaults read com.coteditor.CotEditor defaultTheme 2>/dev/null || true)"
cot_font="$(defaults export com.coteditor.CotEditor - 2>/dev/null | plutil -extract modes.general.fontType raw - 2>/dev/null || true)"
if [ "$cot_theme" = "Anura (Dark)" ] && [ "$cot_font" = "monospaced" ]; then
  pass "CotEditor theme=Anura (Dark) fontType=monospaced"
else
  bad "CotEditor theme=${cot_theme:-unset} fontType=${cot_font:-unset} (expected Anura (Dark) / monospaced)"
fi
