# Automation hardening plan

A tracked plan for increasing setup automation in this repo **without risking system
stability**. Phases are ordered by dependency and risk, not by the order originally
listed. Each phase ends with a verification gate; don't advance past a gate until it
passes.

**Status key:** `[ ]` not started · `[~]` in progress · `[x]` done

## Build order & rationale

`CI → shared libs → check.sh → guarded bootstrap scripts → install.sh hardening → defaults discovery`

- **CI first** — the off-machine safety net that catches script mistakes in every later
  edit, at zero risk to the Mac.
- **Shared libs second** — `check.sh` and the discovery workflow both need the
  desired-state tables; extract them once so the apply path and verify path can't drift.
- **check.sh third** — once drift is cheap to detect, every later change is self-verifying.
- **Bootstrap scripts & install.sh hardening** — close the two riskiest manual
  touchpoints (login shell, symlink clobbering).
- **Discovery last** — most useful once `check.sh` can confirm any new keys it turns up.

Net effect: `discovery → macos.sh → check.sh` becomes a closed loop, CI guards every
script edit, and the riskiest manual steps become safe and idempotent.

---

## Phase 1 — CI linting  ✅ complete (all jobs green on commit 09ed693)

- [x] `.github/workflows/lint.yml` created
- [x] `shellcheck` job (Ubuntu runner) over `*.sh` only (not `.fish`) — uses preinstalled
      shellcheck, finds scripts via `find -name '*.sh'` so later phases need no edits
- [x] Brewfile job (`macos-latest` runner): `brew bundle list --all --file Brewfile`, no install
- [x] Triage existing findings — manual analysis missed SC2016; the first CI run was the
      authoritative check. Findings: SC2086 ×2 (intentional word-splits: `macos.sh`
      `$RESTARTS` loop, `dock.sh` `set -- $path`) and SC2016 ×3 (literal Markdown backticks
      in single-quoted strings: `macos.sh` `SETTINGS` block + the two `list_settings`
      printfs). All suppressed with reasons. `read`-populated unused vars are not flagged.
- [x] Every deliberate case annotated with a targeted `# shellcheck disable=` + reason
      (SC2086 and SC2016; directive placed above the enclosing `case`/`for`/assignment/
      function for reliable scoping)

**Verification gate:** ✅ PASSED — all three jobs green on commit `09ed693` (run
27916030405): shellcheck, Brewfile parse, fish syntax. Every suppression has a justifying
comment. (The first push surfaced SC2016 ×3 that manual triage missed; fixed and re-pushed.)

Optional (on-theme, low priority):
- [x] `fish -n` syntax-check job for the fish files (included — repo is fish-heavy)
- [ ] `actionlint` on the workflow itself (skipped — left as a later nicety)

## Phase 2 — Extract shared data & logic into `lib/`  ✅ complete (gate passed: byte-identical output)

Refactor of working scripts — comes after CI so the net guards it.

- [x] `lib/macos-defaults.list` — `SETTINGS` rows verbatim, with a `#` format header
- [x] `lib/dock-apps.list` — `APPS` rows verbatim, with a `#` format header
- [x] `lib/defaults-lib.sh` — factored out `norm_bool`, `values_equal`, `type_token`
      (sourced, not executable; `# shellcheck shell=bash` in lieu of a shebang)
- [x] `macos.sh` loads `SETTINGS` via `$(<lib/macos-defaults.list)` and sources
      `lib/defaults-lib.sh` (`# shellcheck source=… disable=SC1091`)
- [x] `dock.sh` loads `APPS` via `$(<lib/dock-apps.list)` (added the missing `DOTDIR` line)
- [x] Both scripts' read loops now skip blank **and** `#` lines (`case "$x" in ''|'#'*)`),
      so the `.list` files can carry self-documenting headers — behaviour-preserving since
      no data row is blank or starts with `#`

**Verification gate:** ✅ PASSED — `macos.sh --list`, `macos.sh --dry-run`, and
`dock.sh --list` are byte-identical before vs after the refactor (diff clean on all three).

Optional (follow-up, don't block Phase 3):
- [ ] `lib/links.list` (source|target pairs) shared by `install.sh` + `check.sh`;
      handle the fish-functions glob as a named special case in both

## Phase 3 — `check.sh` (read-only verifier)  ✅ complete (gate passed)

Mirrors `macos.sh` UX (`--no-color`, ok/warn lines, summary) but **never writes**; exits
non-zero on any drift. Reuses `lib/macos-defaults.list`, `lib/dock-apps.list`, and the
sourced `lib/defaults-lib.sh`, so the verify path can't diverge from the apply path.

- [x] Symlinks — each expected link exists, is a symlink, resolves into the repo
      (ghostty, fish config + each function, mise, gitconfig)
- [x] Homebrew — `brew bundle check --file Brewfile` (reports missing via `--verbose`, no install)
- [x] Defaults — each `lib/macos-defaults.list` row: read value+type, compare via
      `lib/defaults-lib.sh` (match / differs / missing / type-mismatch)
- [x] Dock — compares **by path** (mirrors how dock.sh pins) vs `lib/dock-apps.list`, set
      **and** order; decodes `%20`, lets the `*` glob absorb WhatsApp's U+200E mark
- [x] Login shell — `dscl . -read /Users/$USER UserShell` vs `$(brew --prefix)/bin/fish`
- [x] Hostname — `scutil --get` HostName / LocalHostName / ComputerName vs `pdone-mac`
- [x] `--no-color` flag (honours `NO_COLOR`) + exit 1 on drift, 0 when clean

**Verification gate:** ✅ PASSED — clean machine reports 25/25 ok, exit 0. Injecting one
change (`com.apple.dock tilesize` 46→50, then restored) produced exactly one DRIFT line and
exit 1; clean again afterwards with exit 0.

Note: portable to bash 3.2 (no `mapfile`, no `printf %b` hex reliance) since the Brewfile
doesn't pin bash and a fresh machine's `/usr/bin/env bash` may be the system 3.2.

## Phase 4 — Guarded bootstrap scripts

Replace the loose README command blocks. Both use `sudo` interactively (no privilege
bypassed) and both take `--dry-run`.

- [ ] `shell.sh` — resolve `FISH="$(brew --prefix)/bin/fish"`; bail if missing; append to
      `/etc/shells` only if absent (`grep -qxF`); `chsh` only if current shell differs
- [ ] `hostname.sh` — desired name as a commented constant at top; per name
      (HostName/LocalHostName/ComputerName) `scutil --get` then `sudo scutil --set` only on
      mismatch; flush cache only if something changed
- [ ] README updated to reference the scripts instead of raw commands

**Verification gate:** run each twice — second run reports all-correct, no changes. Then
`check.sh` shell + hostname sections pass.

## Phase 5 — Harden `install.sh`

- [ ] Preflight (warn, don't cryptically fail): assert Darwin; warn if `gh auth status`
      fails; warn that `mas` WhatsApp needs App Store sign-in
- [ ] `link()` helper: if target is already a symlink, `ln -sf` (idempotent); if a **real**
      file/dir would be clobbered, move it to `backups/pre-symlink-<timestamp>/` first
- [ ] Align `install.sh` to `set -euo pipefail`

**Verification gate:** re-run on the configured machine — existing repo symlinks replaced
cleanly, nothing in `backups/pre-symlink-*` unless a real file genuinely existed.

Optional wiring:
- [ ] `install.sh` offers to run `shell.sh` + `hostname.sh` at the end behind a prompt
      (both still runnable standalone)

## Phase 6 — defaults discovery workflow

Writes only into a new gitignored `discovery/` dir; read-only against the system.

- [ ] `defaults-diff.sh snapshot <label>` — export a broad net of domains (extend
      `macos.sh` `BACKUP_DOMAINS` or enumerate via `defaults domains`)
- [ ] `defaults-diff.sh diff` — compare two most recent snapshots; print each changed key
      as a pipe-delimited row in the exact `lib/macos-defaults.list` format
      (domain, key, inferred type, new value)
- [ ] `discovery/` added to `.gitignore`
- [ ] README section: snapshot→change one setting→snapshot→diff→paste row→
      `macos.sh --dry-run`→`check.sh`; note `cfprefsd` caching (relaunch System Settings
      or `killall cfprefsd`); anything not in `defaults` stays in the manual table

**Verification gate:** discover one genuinely new key this way, add it, watch `check.sh`
go from flagging it as drift to passing.

---

## What we deliberately are NOT automating (stability guardrails)

- Interactive auth: `gh auth login`, Apple ID, App Store sign-in — stay manual
- Unattended `brew upgrade` (e.g. launchd timer) — actively *reduces* stability; keep
  upgrades deliberate
- TCC/SIP-protected settings (Accessibility grants, Notifications, Spotlight categories) —
  fragile + a security regression to script
- Device-specific input tuning (mouse/trackpad feel) — not worth the fragility
- YouTube Music PWA — effectively unscriptable; stays manual
- Cursor Nightly auto-download — only if isolated in its own script allowed to fail
  without aborting bootstrap (URL/packaging break unannounced)
