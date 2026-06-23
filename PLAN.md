# Implementation plan — repo hardening & ergonomics

Planned work from the project review, covering themes **A, B, D and E**.
Theme **C** (pruning Brewfile-unlisted packages via `brew bundle cleanup`) is
**intentionally out of scope** for this plan.

Work is grouped into four phases. Each phase is independently shippable as one
or more `dotpush`-able commits, and ends by running the **Validation gates** at
the bottom. Tick the boxes as you go; every task lists the files it touches, the
approach, and a "done when" check.

## Summary

| Phase | Focus | Items |
|-------|-------|-------|
| 1 | Foundation hardening & drift elimination | A1, A2, E1, E2 |
| 2 | Bootstrap resilience & one-command setup | B1, B2 |
| 3 | Guardrails & tests | D2, D1 |
| 4 | Ergonomics & documentation | B3, E3 |

## Phase 1 — Foundation hardening & drift elimination

Goal: close the remaining single-source-of-truth gaps and make script failures
legible. All small, internal edits; no new files.

- [x] **A1 — Derive `BACKUP_DOMAINS` from `lib/macos-defaults.list`**
  - Files: `macos.sh`
  - Approach: replace the hardcoded `BACKUP_DOMAINS='…'` string with the unique
    set of domains (field 1) parsed from the settings list already loaded into
    `$SETTINGS`, e.g. `awk -F'|' '$1 !~ /^#/ && NF {print $1}' | sort -u`.
  - Done when: adding a row in a brand-new domain to the list causes that domain
    to be backed up by `ensure_backup`, with no edit to `macos.sh`.

- [x] **A2 — `check.sh` flags *extra* brew packages not in the Brewfile**
  - Files: `check.sh` (Homebrew section)
  - Approach: diff installed top-level formulae + casks (`brew leaves` /
    `brew list --cask`) against the names parsed from the Brewfile; report any
    surplus. Soft **warn** (not drift) so deliberate manual installs don't fail
    `check.sh`; note the two intentionally-manual apps are not brew-managed and
    won't appear.
  - Done when: `brew install <throwaway>` makes `check.sh` warn; removing it clears.

- [x] **E1 — Lib-file existence preflight**
  - Files: `macos.sh`, `check.sh`, `dock.sh`, `install.sh` (hostname.sh already guards)
  - Approach: before each `< lib/…` read or `source`, assert readability and exit
    with a clear message, e.g. `[ -r "$f" ] || { echo "missing $f" >&2; exit 1; }`.
  - Done when: renaming a `lib/` file yields a one-line error, not a raw `set -e` abort.

- [x] **E2 — Shebang consistency**
  - Files: `install.sh`
  - Approach: change `#!/bin/bash` to `#!/usr/bin/env bash` to match the other scripts.
  - Done when: `head -1 *.sh` is uniform; `bash -n install.sh` still clean.

## Phase 2 — Bootstrap resilience & one-command setup

Goal: a fresh-machine setup that survives a partial Brewfile failure and runs as
one guided command instead of seven manual steps.

- [x] **B1 — A failing App Store (`mas`) entry must not abort `install.sh`**
  - Files: `install.sh`
  - Approach: run `brew bundle` tolerantly (capture its exit code rather than
    letting `set -e` kill the script), then continue to `mise trust` and the final
    summary, surfacing a clear warning if any entry failed (e.g. WhatsApp when not
    signed into the App Store).
  - Done when: a simulated bundle failure still reaches `mise trust` and prints the
    closing summary, with an explicit note about what didn't install.

- [x] **B2 — Single guided bootstrap entrypoint**
  - Files: new `bootstrap.sh`; `README.md`; reconcile `install.sh` header comment
  - Approach: a top-level script that runs `install.sh` → `shell.sh` →
    `hostname.sh` → `macos.sh` → `dock.sh` in order, each behind a confirm prompt
    (support `--dry-run` to preview and `--yes` to skip prompts). Fix the
    `install.sh` header, which currently claims it "optionally sets login shell +
    hostname" but doesn't — let `bootstrap.sh` own that orchestration.
  - Done when: `bootstrap.sh --dry-run` previews the full sequence; a real run
    prompts before each step and is a no-op on an already-configured machine.

## Phase 3 — Guardrails & tests

Goal: lock in the comparison semantics the repo depends on, and catch lint/test
failures locally before they reach GitHub. (D2 lands before D1 so the hook can
optionally run the tests.)

- [x] **D2 — Unit tests for `lib/defaults-lib.sh` + CI job**
  - Files: new `tests/defaults-lib.test.sh`; `.github/workflows/lint.yml`; `Brewfile`
  - Approach: plain-bash test (no new runtime dep) that sources the lib and asserts
    `values_equal`, `norm_bool`, and `type_token` behaviour (e.g. `bool true` == `1`,
    float equality, type tokens). Add a `shell-tests` job to CI (ubuntu) that runs it.
    Add `brew "shellcheck"` to the Brewfile (it isn't installed locally today and is
    needed by D1 and by local linting).
  - Done when: tests pass locally and in CI; deliberately breaking `values_equal` fails them.

- [x] **D1 — Version-controlled git pre-push hook**
  - Files: new `hooks/pre-push`; `install.sh`/`bootstrap.sh` (set `core.hooksPath`); `README.md`
  - Approach: a tracked hook (under `hooks/`, wired via
    `git config core.hooksPath hooks` so it lives in the repo, unlike `.git/hooks`)
    that runs `shellcheck` on `*.sh`, `fish -n` on `*.fish`, and optionally the D2
    tests — mirroring CI. Bootstrap sets `core.hooksPath` automatically.
  - Done when: introducing a shellcheck violation blocks `git push` locally with a
    clear message; a clean tree pushes normally.

## Phase 4 — Ergonomics & documentation

Goal: make the repo's everyday commands discoverable and keep the README focused
on setup rather than reference.

- [x] **B3 — Task runner (`Justfile`)**
  - Files: new `Justfile`; `Brewfile` (add `brew "just"`); `README.md` (Usage)
  - Approach: wrap the scripts in self-documenting targets — e.g. `bootstrap`,
    `install`, `check`, `apply` (macos), `dock`, `shell`, `hostname`, `push`,
    `doctor`, `lint`, `test` — so `just --list` is the entrypoint. Targets call the
    existing scripts; no logic moves into the Justfile.
  - Done when: `just --list` shows the targets and `just check` runs `check.sh`.

- [x] **E3 — Split the keyboard-shortcut cheat-sheet into `SHORTCUTS.md`**
  - Files: new `SHORTCUTS.md`; `README.md`
  - Approach: move the "macOS Shortcuts", "Terminal and Shell Differences", and
    "Ghostty" reference tables out of the README into `SHORTCUTS.md`; leave a short
    pointer link in the README. Setup/usage stays in the README.
  - Done when: README is setup-focused; `SHORTCUTS.md` holds the cheat-sheet; the two
    are cross-linked.

## Validation gates (run at the end of every phase)

- [ ] `bash -n` clean on each changed `*.sh`
- [ ] `shellcheck` clean on each changed `*.sh` (once added in Phase 3)
- [ ] `fish -n` clean on each changed `*.fish`
- [ ] `./check.sh` shows no new drift
- [ ] Relevant `--dry-run` previews behave as expected (`macos.sh`, `bootstrap.sh`, …)
- [ ] CI (`.github/workflows/lint.yml`) is green
- [ ] `dotpush "<phase summary>"` — one focused commit per phase (or per item)

## Out of scope

- **C — `brew bundle cleanup` / pruning unlisted packages.** Deliberately excluded
  from this plan. The Brewfile remains additive; `check.sh` will *warn* on extras
  (A2) but nothing is auto-removed.
