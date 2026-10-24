# shellcheck shell=bash
#
# brew_missing_hint — turn `brew bundle check --verbose` output into a source
# hint. Formulae and casks are Homebrew (run brewsync). Mac App Store apps
# need App Store sign-in. Prints nothing when the text names no missing entry;
# the caller then uses a generic hint. Sourced, not executed.

# shellcheck source=join-names.sh disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/join-names.sh"

brew_missing_hint() {
  local text="$1" line name formulae="" casks="" apps="" homebrew_names app_names out=""
  while IFS= read -r line || [ -n "$line" ]; do
    # Trim leading spaces, then a leading arrow from brew's verbose lines.
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
      "→ "*|"↳ "*|"-> "*) line="${line#* }" ;;
    esac
    case "$line" in
      "Formula "*" needs to be installed"*|"Formula "*" needs to be updated"*)
        name="${line#Formula }"
        name="${name%% needs to be *}"
        formulae="${formulae}${name}"$'\n'
        ;;
      "Cask "*" needs to be installed"*|"Cask "*" needs to be updated"*)
        name="${line#Cask }"
        name="${name%% needs to be *}"
        casks="${casks}${name}"$'\n'
        ;;
      "App "*" needs to be installed"*|"App "*" needs to be updated"*)
        name="${line#App }"
        name="${name%% needs to be *}"
        # "Keynote (409183694)" -> "Keynote"
        name="${name% (*)}"
        apps="${apps}${name}"$'\n'
        ;;
    esac
  done < <(printf '%s\n' "$text")

  homebrew_names="$(printf '%s%s' "$formulae" "$casks" | join_and)"
  app_names="$(printf '%s' "$apps" | join_and)"
  if [ -n "$homebrew_names" ]; then
    out="Homebrew packages (${homebrew_names}): run brewsync."
  fi
  if [ -n "$app_names" ]; then
    if [ -n "$out" ]; then
      out="${out}"$'\n'
    fi
    out="${out}Mac App Store apps (${app_names}): needs App Store sign-in."
  fi
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  fi
}
