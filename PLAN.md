# Automation hardening plan

A tracked plan for increasing setup automation in this repo **without risking system
stability**. Phases are ordered by dependency and risk, not by the order originally
listed. Each phase ends with a verification gate; don't advance past a gate until it
passes.

**Status key:** `[ ]` not started · `[~]` in progress · `[x]` done

**Status: all six phases complete and CI-verified (June 2026).**

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
- [x] `actionlint` on the workflow itself (added — also shellchecks inline `run:` blocks;
      `actions/checkout` bumped v4 → v5 to clear the Node-20 deprecation warning)

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
- [x] `lib/links.list` (source|target pairs, `@HOME@` → `$HOME`) shared by `install.sh` +
      `check.sh`; the fish-functions dir is handled as a glob special-case in both

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

## Phase 4 — Guarded bootstrap scripts  ✅ complete (gate passed)

Replace the loose README command blocks. Both use `sudo` interactively (no privilege
bypassed) and both take `--dry-run`.

- [x] `shell.sh` — resolves `FISH="$(brew --prefix)/bin/fish"`; bails if missing; appends to
      `/etc/shells` only if absent (`grep -qxF`); `chsh` only if current shell differs
- [x] `hostname.sh` — desired name as a commented constant at top; per name
      (HostName/LocalHostName/ComputerName) `scutil --get` then `sudo scutil --set` only on
      mismatch; flushes DNS cache only if something changed
- [x] README updated to reference the scripts instead of raw commands

**Verification gate:** ✅ PASSED — on this (already-configured) machine each script run
twice reports all-`ok`, exit 0, invoking no sudo/chsh/flush. The *change* branch was
verified via `--dry-run` on throwaway `/tmp` copies pointed at different targets
(`DESIRED=probe-xyz`, `FISH=/bin/zsh`): both printed `would set …`/`would chsh …` while the
real HostName and login shell stayed untouched. `check.sh` shell + hostname sections still
pass. (The live sudo/chsh paths can't run here — Desktop Commander blocks those commands,
and they're what runs on a fresh machine — so they're construction + dry-run verified, to
be exercised for real on first fresh-machine setup.)

## Phase 5 — Harden `install.sh`  ✅ complete (gate passed)

- [x] Preflight (warn, don't cryptically fail): asserts Darwin (hard exit off-macOS);
      warns if `gh` is installed but unauthenticated; notes the `mas` WhatsApp App Store
      sign-in requirement
- [x] `link()` helper: if DST is already a symlink, `ln -sf` repoints it (idempotent); if a
      **real** file/dir sits there, it's moved to `backups/pre-symlink-<timestamp>/` first.
      Backup dir set via a direct `ensure_backup_dir` (not a `$(...)` subshell), so all
      clobbered files land in one timestamped dir
- [x] Aligned `install.sh` to `set -euo pipefail`

**Verification gate:** ✅ PASSED — `bash -n` clean; `link()` logic exercised in an isolated
sandbox (verbatim copy of the helpers): absent target → link, no backup; already-correct
symlink → idempotent, no spurious backup; real file present → original preserved in a single
`pre-symlink-*` dir, then linked. `check.sh` confirms all real symlinks still `ok`. (Did not
run the full `install.sh` here — it would trigger `brew bundle`'s network/install side
effects on an already-set-up machine; the unchanged brew/mise sections weren't re-exercised.)

Optional wiring:
- [x] `install.sh` offers to run `shell.sh` + `hostname.sh` at the end behind a `[y/N]` prompt
      (tty-guarded — prints manual hints when non-interactive; both still runnable standalone)

## Phase 6 — defaults discovery workflow  ✅ complete (gate passed)

Writes only into a new gitignored `discovery/` dir; read-only against the system.

- [x] `defaults-diff.sh snapshot <label>` — one python pass enumerates every domain
      (`defaults domains` + NSGlobalDomain) and flattens scalar keys to TSV
      (domain⇥key⇥type⇥value)
- [x] `defaults-diff.sh diff` — compares the two most recent snapshots; prints each
      changed/new key as a pipe-delimited row in the exact `lib/macos-defaults.list`
      format, with `restart|area|label|display` left as fill-in placeholders
- [x] `discovery/` added to `.gitignore`
- [x] README: "Discovering new defaults" (snapshot→change→snapshot→diff→paste→
      `macos.sh --dry-run`→`check.sh`) with the `cfprefsd` caching + not-in-`defaults`
      caveats; also a "Verifying the setup" blurb for check.sh and a refreshed Contents

**Verification gate:** ✅ PASSED — captured `before` (2398 keys), set a genuinely new key
(`com.apple.dock autohide-delay`, invisible), captured `after` (2399); `diff` emitted exactly
`com.apple.dock|autohide-delay|float|0.5|…` flagged `NEW` (amid 2 lines of incidental churn).
Key restored to unset, snapshots cleaned up. The check.sh drift→pass half of the loop was
proven in Phase 3 against the same list.

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
