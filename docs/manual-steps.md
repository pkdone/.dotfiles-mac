# Manual steps

See [README.md](../README.md).

> _Manual — no script can do these. `install.sh` and `bootstrap.sh` print this checklist when they finish and, on a terminal, offer to walk through it._

Some setup stays manual: privacy permissions (TCC / DriverKit), sign-ins, company MDM apps, and settings that aren't a single reliable `defaults` key (notification mirroring, Spotlight, mouse double-click and secondary click, Look up & data detectors, Accessibility trackpad dragging, and the Menu Bar allow-list for Raycast, Logi Options+ and Docker). **`lib/manual-steps.list` is the single source of truth** for them; `scripts/manual-steps.sh` reads it. Per-app Allow Notifications is checked by `macconfig-check.sh` (see [Notifications](settings.md#notifications)). Built-in display More Space is checked from `system_profiler` (see below). Trackpad tap to click, click pressure, secondary click, three-finger drag, tracking speed, and Force Click are applied by `macos.sh` (see [macOS defaults](settings.md#macos-defaults)).

This file is generated from `lib/manual-steps.list`. Edit the list, then run `scripts/render-manual-steps-doc.sh`.

```bash
~/.dotfiles-mac/scripts/manual-steps.sh list    # numbered checklist
~/.dotfiles-mac/scripts/manual-steps.sh open    # walk through the steps not yet done, opening each System Settings page (terminal only; --all for every step)
~/.dotfiles-mac/scripts/manual-steps.sh check   # read-only: ok / warn / by hand (also the "Manual steps" section of macconfig-check.sh)
```

`check` never writes a setting or prompts, and wraps every slow call in a timeout. It verifies what it can reliably read: privacy grants from the system TCC database (needs Full Disk Access for the terminal or agent running it, otherwise those become "by hand"), pointer size, Accessibility trackpad dragging (`Dragging=1`, `DragLock=0`), mouse tracking speed `1.5` and scrolling speed `0.5` (check only; `defaults write` does not reliably drive System Settings → Mouse), the Karabiner driver, the Hammerspoon grant (live via `hs`), installed apps, Logi Options+ values (from a temp copy of its settings database), `gh auth status` and `op whoami`. Steps marked `macconfig-check.sh` below are verified by their own `macconfig-check.sh` section. To add a step, add a row to `lib/manual-steps.list` (format in its header) and regenerate this file with `scripts/render-manual-steps-doc.sh` (the table is `scripts/manual-steps.sh list --markdown`).

`macconfig-check.sh` also reports four of those in **Sign-ins, keyboard, and pointer**, each linked to its row: British input (`com.apple.HIToolbox` `AppleEnabledInputSources`, manual step `input-british`), pointer size (manual step `pointer-size`, and only when that row exists), `gh auth status` (manual step `gh-auth`), and `op whoami` (manual step `1password-cli`). A miss is a warning, never drift. `--fix` does not change them. There is no sudo, and the notification store is not written. `op whoami` failing because 1Password is installed but locked or not signed in is info, not a warning. The Manual steps section does not repeat those four rows.

| # | Step | Where | Checked |
|---|------|------|------|
| 1 | Sign in to the GitHub CLI (needed to clone this private repo) | Terminal: gh auth login | auto |
| 2 | Sign in with your Apple Account (your @icloud.com Apple ID) | System Settings → Apple Account | by hand |
| 3 | iCloud: Photos, iCloud Drive, Messages and other unused sync Off; Passwords (iCloud Keychain) and Find My On | System Settings → Apple Account → iCloud | by hand |
| 4 | Sign in to the App Store (brew bundle needs it for WhatsApp and the other mas apps) | App Store → Store → Sign In | by hand |
| 5 | Install Okta Verify and 1Password from Iru Self Service (Kandji), not Homebrew | Applications → Iru Self Service | macconfig-check.sh |
| 6 | Sign in to 1Password and unlock it | 1Password app | by hand |
| 7 | Turn on Integrate with 1Password CLI, then run op whoami in a terminal | 1Password → Settings → Developer | auto |
| 8 | Install Cursor Nightly (separate app, next to the stable Cursor) | cursor.com/nightlydownload | auto |
| 9 | Install YouTube Music as a Chrome app | Chrome → music.youtube.com → ⋮ → Cast, save, and share → Install page as app | auto |
| 10 | Allow Hammerspoon (Sidecar → Slack), then restart it and choose Reload Config | System Settings → Privacy & Security → Device Control and Data Access → Hammerspoon | auto |
| 11 | Enable the Karabiner DriverKit VirtualHIDDevice driver | System Settings → General → Login Items & Extensions → Driver Extensions | auto |
| 12 | Allow Karabiner-Elements and Karabiner-Core-Service | System Settings → Privacy & Security → Device Control and Data Access | auto |
| 13 | Allow Karabiner-Elements to run in the background | System Settings → General → Login Items & Extensions → Allow in the Background | by hand |
| 14 | Allow Raycast (needed for Clipboard History) | System Settings → Privacy & Security → Device Control and Data Access → Raycast | auto |
| 15 | Give Ghostty Full Disk Access (lets macconfig-check.sh read Login Items and Finder Recents) | System Settings → Privacy & Security → Full Disk Access → Ghostty | auto |
| 16 | Give Grok Bot Full Disk Access (for its unattended macconfig-check.sh runs) | System Settings → Privacy & Security → Full Disk Access → Grok Bot | auto |
| 17 | Trackpad: Look up & data detectors Off | System Settings → Trackpad → Point & Click | by hand |
| 18 | Use trackpad for dragging On (Without Drag Lock) | System Settings → Accessibility → Pointer Control → Trackpad Options | auto |
| 19 | Pointer size one notch above Normal | System Settings → Accessibility → Display → Pointer → Pointer size | auto |
| 20 | Mouse: tracking speed 1.5 and scrolling speed 0.5 (checked only; writing them is unreliable). Double-click speed faster and secondary click on the right side stay by hand (the double-click threshold key is unset). The wheel's direction, Natural, is set in Logi Options+ and checked by macconfig-check.sh | System Settings → Mouse | auto |
| 21 | Logi Options+: Smooth scrolling On (main wheel and thumb wheel) | Logi Options+ → MX Master 3S → Point & Scroll | auto |
| 22 | Logi Options+: sign in and turn on cloud backup (Automatically backup all devices); confirm it shows a recent Last backup | Logi Options+ → MX Master 3S → Settings → Other → Automatically backup all devices | by hand |
| 23 | Built-in display: More Space | System Settings → Displays | macconfig-check.sh |
| 24 | Displays: Automatically adjust brightness Off (leave True Tone and Slightly dim the display on battery as they are) | System Settings → Displays | macconfig-check.sh |
| 25 | On mains power, stop the Mac sleeping on its own. Closing the lid still sleeps the Mac, and battery is unchanged. The display still turns off and the screen still locks | Terminal: sudo pmset -c sleep 0 | macconfig-check.sh |
| 26 | Keyboard input source: British | System Settings → Keyboard → Text Input → Input Sources | auto |
| 27 | Set your user picture to the Dog | System Settings → Users & Groups → your account picture | by hand |
| 28 | Notifications Off when mirroring or sharing the display | System Settings → Notifications | by hand |
| 29 | Turn notifications Off for Calendar, Cursor Nightly, FaceTime, Game Center, Home, Mail, Microsoft Teams, Slack, Spotify, Tips, Wallet | System Settings → Notifications → Application Notifications | macconfig-check.sh |
| 30 | Spotlight: turn Off results from Books, Keynote, Mail, Notes, Numbers, Photos, Podcasts, Reminders, Stocks, Tips, Voice Memos | System Settings → Spotlight → Results from Apps | by hand |
| 31 | Keep ChatGPT, Gemini and GeminiAppLauncher Off at login | System Settings → General → Login Items & Extensions | macconfig-check.sh |
| 32 | Gemini shortcuts: Mini chat Control+Option+G, Full chat Control+Option+Shift+G (defaults clash with ChatGPT) | Gemini → Settings → Shortcuts | by hand |
| 33 | Raycast: on a new Mac, import your .rayconfig backup (tick Settings, Aliases & Hotkeys), or set the three Raycast items below by hand; keep Scheduled Backup on (never in this repo: it holds clipboard history and extension settings) | Raycast → Import Settings & Data (backups: Raycast → Settings → Advanced → Export / Scheduled Backup) | by hand |
| 34 | Raycast hotkey: Shift+Control+Command+R (off Option+Space, which clashes with ChatGPT) | Raycast → Settings → General → Raycast Hotkey | auto |
| 35 | Raycast: Finder hotkey Shift+Control+Command+F | Raycast → type Finder → Command+K → Configure Application… → Record Hotkey | by hand |
| 36 | Raycast Clipboard History: hotkey Control+Command+V, keep history 1 day, disable 1Password and 1Password for Safari | Raycast → Settings → Extensions → Clipboard History | by hand |
| 37 | Create two Focus modes named WebConf and DeepWork (WebConf: allow Granola; DeepWork: allow Hammerspoon, so the end-of-session notification gets through) | System Settings → Focus → Add Focus… → Custom | macconfig-check.sh |
| 38 | Create four Shortcuts, each with one Set Focus action: "Mode WebConf On" (Turn WebConf On until Turned Off), "Mode WebConf Off" (Turn WebConf Off), "Mode DeepWork On", "Mode DeepWork Off" | Shortcuts → + → search "Set Focus" | macconfig-check.sh |
| 39 | Hammerspoon notifications: style Alerts, so the DeepWork end-of-session buttons (Take a break / Back to Normal / Another session) show | System Settings → Notifications → Hammerspoon → Alerts | macconfig-check.sh |
| 40 | Pin the mode-switcher menu-bar icon so it stays visible: hold Command (⌘) and drag it toward Control Centre / the clock, because icons further from them get auto-hidden behind << | Menu bar → ⌘-drag the mode icon (desktop computer / red ⏺ / brain) | by hand |
| 41 | Allow in the Menu Bar: turn Off Raycast, Logi Options+ and Docker. Leave Tailscale, 1Password, Granola, Hammerspoon and Kandji/company agents as they are. Raycast's own menu-bar toggle isn't scriptable | System Settings → Menu Bar → Allow in the Menu Bar | by hand |

Trackpad tap to click, click pressure Light, secondary click in the bottom right corner, three-finger drag Off, tracking speed `0.6875`, and Force Click and haptic feedback On are in `lib/macos-defaults.list` (`macos.sh` / `macconfig-check.sh`; `macconfig --fix` repairs them). A change may need a logout/login before the trackpad follows it. Look up & data detectors stays in the table above: `ActuateDetents` and `ForceSuppressed` only cover Force Click and haptic feedback, both On. Use trackpad for dragging stays a check (`Dragging=1`, `DragLock=0`: On, without drag lock) because that Accessibility setting does not reliably follow `defaults write`.

Mouse tracking speed (`NSGlobalDomain` `com.apple.mouse.scaling` = `1.5`) and scrolling speed (`com.apple.scrollwheel.scaling` = `0.5`) are the same kind of check. `macconfig-check.sh` warns when they drift (`mouse-settings` in `lib/autofix.list`, Needs Paul). `--fix` does not write them: on recent macOS those System Settings → Mouse sliders do not reliably follow `defaults write`. Double-click speed and secondary click on the right side stay in that step. The double-click threshold key is unset on this Mac, so it cannot be checked. Wheel direction (Natural) stays in Logi Options+.

Desktop widgets and Stage Manager are in `lib/macos-defaults.list` too (`StandardHideWidgets` and `StageManagerHideWidgets` = true, `GloballyEnabled` = false). `macos.sh` applies them and `macconfig --fix` repairs them. `restart` is empty, so a repair restarts no process. Click wallpaper to reveal desktop is not pinned.

Built-in display **More Space** is checked by the **Display (More Space)** section of `macconfig-check.sh`. The expected prefix is `lib/display-resolution.list` (`1800 x 1169` on this Color LCD). The check reads `system_profiler SPDisplaysDataType -json` and warns when the built-in panel's `_spdisplays_resolution` does not start with that prefix (`1800 x 1169 @ 120.00Hz` is More Space on this panel). No built-in panel, such as a clamshell Mac, is an info line. `--fix` does not change the display mode.

AC idle sleep on mains power (`sudo pmset -c sleep 0`, manual step `ac-sleep`) is in [Troubleshooting](troubleshooting.md#ac-idle-sleep).

Notes: Passwords in iCloud = iCloud Keychain, so don't turn it Off casually. Mouse-wheel direction (Natural) is set in Logi Options+, not System Settings: the macOS natural-scrolling switch is global and also flips the trackpad. The Logi Options+ values are checked automatically (see [Logi Options+](settings.md#logi-options)). The Finder, Logi Options+, Gemini and Raycast subsections in [Settings](settings.md) have the click-by-click detail.
