# Agent rules

When Paul asks for a change on his MacBook, apply it on the Mac now where that is possible, and codify it in this repo (`~/.dotfiles-mac` on the machine). Use the strongest rung below that works. In the pull request, say which rung you chose and why.

`macconfig` is the fish function for `macconfig-check.sh`. `check.sh` execs the same script. A plain run only reads. `macconfig --fix` applies the SAFE rows in `lib/autofix.list`, checks again, and lists Fixed and Needs Paul. Exit status is the drift left afterwards. Warnings do not fail the run. `--fix` never uses sudo, never deletes files, and never overwrites a real file with a symlink.

Prefer another row in an existing list, or a few lines in an existing `checks/*.sh`, over a new file. Formats are in each file's header. The longer catalogue of setters is in [Making changes](docs/setup.md#making-changes).

## 1. Scripted and checked

A scripted setting is applied by `bootstrap.sh` on a fresh Mac, and checked by `macconfig`. A setting that only `macconfig --fix` can apply does not count.

`bootstrap.sh` runs, in order, `install.sh`, `shell.sh`, `hostname.sh`, `macos.sh`, `dock.sh`, `handlers.sh`, `prune-apps.sh`. Put the setter in one of those scripts, or in a list that script already reads, so a new setting is picked up with no change to `bootstrap.sh`. Add a new bootstrap step only when none of those fits. That step must be idempotent and accept `--dry-run` (bootstrap passes each script its preview flag; `dock.sh` uses `--list`).

| Setting | Where a new row goes | Applied on a fresh Mac by |
|---|---|---|
| A `defaults` value | `lib/macos-defaults.list` (`defaults-diff.sh` finds the key) | `macos.sh` |
| Dock apps | `lib/dock-apps.list` | `dock.sh` |
| Finder double-click apps | `lib/file-handlers.list` | `handlers.sh` |
| URL schemes | `lib/url-handlers.list` | `handlers.sh` |
| A repo symlink | `lib/links.list`. `fish/functions/*.fish` is the one glob exception, not a row | `install.sh` |
| A Homebrew package | `Brewfile` | `install.sh` (later, `brewsync`) |
| A login agent | `launchagents/*.plist` (`@HOME@`, which launchd does not expand). Rendered to a regular file, not a symlink | `install.sh` |
| Karabiner, Hammerspoon config, fish, Ghostty | `karabiner/`, `hammerspoon/`, `fish/`, `ghostty/`, linked from `lib/links.list` | `install.sh` |
| Dictation, Quick Note, Game Overlay, Spotlight, Services, Finder icon view | the existing `scripts/pin-*.sh` | a full `macos.sh`. `selected` is true when `--only` is absent, which is how bootstrap runs it. `macos.sh --only @<id>` is the same code `--fix` calls |

Tag the check with `fixid <id>` in the `checks/<area>.sh` section that already owns it. `macconfig-check.sh` sources those files. `hdr` clears the id, so set `fixid` immediately before `pass`, `bad`, or `warn`.

Add one row to `lib/autofix.list`: `id | class | fixer | why`.

- **SAFE**, and name a fixer from that file's header (`macos`, `launchagent`, `symlink`, `hammerspoon`, `dockrestart`, `desktop`, `fileext`, `origin`), only when `--fix` can put the value back with a reversible preference write. `origin` is the exception that is not a preference: it reruns Cursor's installer when `$HOME/.local/bin/origin` is missing or not an executable file. A SAFE `macos` id other than `defaults` must be a `selected @<id>` branch in `macos.sh`, and that branch must run on a full `macos.sh`, not only under `--only`. `tests/autofix.test.sh` fails if a `fixid` and the list disagree, or if that branch is missing.
- **PAUL**, with an empty fixer, when a setter exists but `--fix` must not run it. That is the Dock layout (`dock.sh` rebuilds the whole Dock), URL schemes (macOS may ask to confirm), Homebrew, hostname, the login shell, and anything that needs sudo. Those still count as scripted when bootstrap runs the setter.

Do not copy a SAFE fixer that bootstrap never runs. Dock Assign To (`desktop-assign`, `lib/desktop-bindings.py --apply`) and starting Hammerspoon (`open -g -a Hammerspoon`) are repaired only by `macconfig --fix`. The Dock-space repair (`dock-space`) is the same: `--fix` restarts the Dock and measures the usable area. `dock.sh` restarts the Dock after pinning apps, without that measurement. The origin installer is shared: `install.sh` runs `safe_install_origin`, and `--fix` calls that same helper. It does not use sudo and does not pin a version. A present executable is left alone. The published installer has no switch to skip git config, so the helper copies the repo `gitconfig` and writes it back if that run changes it. Only that file.

## 2. Checked only

Use this when a script can read the value and must not write it: a permission, a login item, a Fleet or MDM setting, anything that needs sudo, or app UI state that is readable.

Add the read to the existing section. `bad` when the desired value is wrong (drift; `macconfig` exits 1). `warn` when it needs attention but is not a failed match (AC sleep, notifications, a missing company app, a tool that could not be read). The message is one line and says how to put it back by hand. Add a PAUL row. `--fix` does not write it.

`macos.sh` may still prompt for sudo when Paul runs it (AC sleep). `--fix` never does.

## 3. Manual step

Use this only when the value cannot be read.

Add one row to `lib/manual-steps.list`: `id | group | title | where | open | check`. The title is plain English. `where` is the System Settings path in macOS 27 names. `open` is an `x-apple.systempreferences:` pane, `app:<App Name>`, `https://…`, `safari:https://…`, or empty. `check` is empty when it stays by hand; the header lists the read-only checks. A `@macconfig:<area>` check must be an area `lib/covered-steps.sh` already runs (`mdm`, `karabiner`, `display`, `power`, `notifications`, `login-items`, `finder`, `modes`, `menubar`) and a `check_step_<id>` function in that section. When `macconfig` prints Manual steps, each of those steps still has one line in its numbered place (`checked above under` the section heading `hdr` prints, with that section's ok, warn, or fail, or `info` when the section recorded nothing). The line is not counted again and does not say to press s. `remove-widgets` is that same line for the Desktop widgets section. Add the id to `covered_section_heading` in `lib/covered-steps.sh` so the heading stays in the list.

Then run `scripts/render-manual-steps-doc.sh`. Do not edit the table in `docs/manual-steps.md` by hand. Notes around that table live in the renderer. `tests/manual-steps.test.sh` fails when the doc is stale.

## Every rung

- Say what the setting is and why in `docs/settings.md`. Add a gotcha to `docs/troubleshooting.md` when one exists (a software update resetting it, a sudo prompt, a dialog).
- Add or extend a test under `tests/`, in the style of the suite next to it: `tests/<topic>.test.sh`, `set -uo pipefail`, bash 3.2 (no `mapfile`, no associative arrays), `eq` / `has` helpers. The suite runs on Linux. Source `tests/hermetic.sh` and stub the commands in `hermetic_denied` so a test never sees this machine. Source a section with `MACCONFIG_CHECKS_DEFINE_ONLY=1` when you only want its functions. `./tests/run-all.sh` must pass, including `tests/autofix.test.sh`, `tests/covered-steps.test.sh`, `tests/manual-steps.test.sh`, `tests/manualsteps.test.sh`, and `tests/hermetic.test.sh`. Shellcheck with `./tests/run-all.sh --shellcheck all`.
- A new `checks/<area>.sh` has to be sourced from `macconfig-check.sh`, named in `KNOWN_AREAS`, and added to the heading list in `tests/sections.test.sh`. That test pins section order. Extend an existing section instead.

## Company management, sudo, symlinks, secrets

Do not fight Fleet, MDM, or Santa. Record those as `info` (by hand, not drift) and PAUL. Company apps belong in `lib/mdm-apps.list` and are installed from Fleet Self service (Fleet Desktop menu bar → My device → Self service), not the Brewfile. `--fix` does not install them. Leave Santa, SentinelAgent, and Kerberos off `lib/notifications-off.list`. Santa and SentinelAgent stay in `lib/notifications-reviewed.list`. Do not remove their login items; company items belong on `lib/login-items-allow.list`. Firewall, screen lock, and automatic security updates may be MDM-managed: report them, do not write them.

The symlink fixer runs `ln -sfn` only when the path is already a symlink or missing. LaunchAgents are rendered files, not links.

Do not add secrets, tokens, auth keys, or personal contact details. A check that has to recognise an account follows the Tailscale and 1Password checks: keep a count or a fixed comparison, and do not log ids, keys, or extra addresses.

## Applying it on the Mac

On the Mac, run the setter in this session (the same script `bootstrap.sh` runs, or `macconfig --fix` for a SAFE row) and confirm `macconfig` shows the new check as ok before you finish. A fresh Mac gets every rung-1 setting from `bootstrap.sh`, so that run must not depend on `--fix`.

After the change is merged, on the Mac:

```bash
cd ~/.dotfiles-mac
git pull
# the same setter bootstrap.sh already runs (macos.sh, dock.sh, handlers.sh, install.sh, …)
# or, for a SAFE row only:
macconfig --fix
macconfig
```

`macconfig` should show the new check as ok.
