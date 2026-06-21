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

## Phase 1 — CI linting  ✅ implemented (CI gate pending first push)

- [x] `.github/workflows/lint.yml` created
- [x] `shellcheck` job (Ubuntu runner) over `*.sh` only (not `.fish`) — uses preinstalled
      shellcheck, finds scripts via `find -name '*.sh'` so later phases need no edits
- [x] Brewfile job (`macos-latest` runner): `brew bundle list --all --file Brewfile`, no install
- [x] Triage existing findings — done by manual analysis (shellcheck not runnable in this
      env); only two real findings, both intentional SC2086: `macos.sh` `$RESTARTS` loop and
      `dock.sh` `set -- $path`. `read`-populated unused vars are not flagged. First CI run is
      the authoritative confirmation.
- [x] Every deliberate case annotated with targeted `# shellcheck disable=SC2086` + reason
      (directive placed above the enclosing `case`/`for` for reliable scoping)

**Verification gate:** workflow green on a PR; every suppression has a justifying comment.
→ ⏳ *Pending: CI only runs once `lint.yml` is pushed to GitHub. If shellcheck still flags
the two suppressed lines, move the directive onto the exact offending line and re-push.*

Optional (on-theme, low priority):
- [x] `fish -n` syntax-check job for the fish files (included — repo is fish-heavy)
- [ ] `actionlint` on the workflow itself (skipped — left as a later nicety)

## Phase 2 — Extract shared data & logic into `lib/`

Refactor of working scripts — comes after CI so the net guards it.

- [ ] `lib/macos-defaults.list` — current `SETTINGS` block, verbatim
- [ ] `lib/dock-apps.list` — current `APPS` block, verbatim
- [ ] `lib/defaults-lib.sh` — factor out `norm_bool`, `values_equal`, `type_token`
- [ ] `macos.sh` loads `SETTINGS` from `lib/` and sources `lib/defaults-lib.sh`
- [ ] `dock.sh` loads `APPS` from `lib/` (add a `DOTDIR` line — it currently lacks one)

**Verification gate:** capture `macos.sh --list`, `macos.sh --dry-run`, `dock.sh --list`
output *before* the refactor; diff against the same after. Byte-identical = no behaviour
change.

Optional (follow-up, don't block Phase 3):
- [ ] `lib/links.list` (source|target pairs) shared by `install.sh` + `check.sh`;
      handle the fish-functions glob as a named special case in both

## Phase 3 — `check.sh` (read-only verifier)

Mirrors `macos.sh` UX (`--no-color`, ok/warn lines, summary) but **never writes**; exits
non-zero on any drift.

- [ ] Symlinks — each expected link exists, is a symlink, resolves into the repo
- [ ] Homebrew — `brew bundle check --file Brewfile` (reports missing, no install)
- [ ] Defaults — each `lib/macos-defaults.list` row: read value+type, compare via
      `lib/defaults-lib.sh` (match / differs / missing / type-mismatch)
- [ ] Dock — `dockutil --list` vs `lib/dock-apps.list` (set **and** order)
- [ ] Login shell — `dscl . -read /Users/$USER UserShell` vs fish path
- [ ] Hostname — `scutil --get HostName` (+ LocalHostName, ComputerName) vs expected
- [ ] `--no-color` flag + non-zero exit on drift

**Verification gate:** clean bill of health on the current machine; then change one
`defaults` value by hand and confirm `check.sh` flags exactly that one.

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
