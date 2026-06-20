# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Contents

- `Brewfile` — all Homebrew packages and casks
- `fish/` — Fish shell config and functions
- `ghostty/` — Ghostty terminal config
- `gitconfig` — Git user and behaviour settings
- `mise/` — pinned default tool versions (Node, npm)
- `install.sh` — bootstraps a new machine
- `macos.sh` — applies a curated set of macOS `defaults` (idempotent)
- `dock.sh` — pins the Dock apps in order (idempotent; needs dockutil)

## Setup

### Bootstrap

On a fresh machine, first install Homebrew (which also pulls in the Command Line Tools that provide `git`), then the GitHub CLI, and sign in — this is what lets the private repo be cloned over HTTPS:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh
gh auth login
```

Clone and bootstrap:

```bash
git clone https://github.com/pkdone/.dotfiles-mac.git ~/.dotfiles-mac
bash ~/.dotfiles-mac/install.sh
```

This creates symlinks from `~/.config` into this repo, installs everything in the Brewfile, and trusts the `mise` config.

Finally, make Fish (installed by the Brewfile) your login shell:

```bash
echo /opt/homebrew/bin/fish | sudo tee -a /etc/shells
chsh -s /opt/homebrew/bin/fish
```

### Apps not in the Brewfile

Two apps can't be installed by `brew bundle`, so set them up by hand after bootstrapping:

- **Cursor Nightly** — download and install it manually from the [Cursor Nightly download page](https://cursor.com/nightlydownload), as a separate app. It's deliberately kept out of the Brewfile (which installs only the stable Cursor), so the stable build and Nightly sit side by side.
- **YouTube Music** — a Chrome PWA. In Chrome, open `music.youtube.com`, then click the install icon in the address bar (or **⋮ menu → Cast, save, and share → Install page as app**).

Do both before running `dock.sh`, or it'll skip them.

### Set Hostname

```bash
sudo scutil --set HostName pdone-mac
sudo scutil --set LocalHostName pdone-mac
sudo scutil --set ComputerName pdone-mac
dscacheutil -flushcache
```

### Dock

Pin the apps to the Dock in order (idempotent; uses `dockutil` from the Brewfile):

```bash
bash ~/.dotfiles-mac/dock.sh --list   # preview the apps and their order
bash ~/.dotfiles-mac/dock.sh          # apply
```

### macOS defaults

A curated set of macOS `defaults` is applied by `macos.sh`:

```bash
bash ~/.dotfiles-mac/macos.sh --dry-run   # preview every decision, write nothing
bash ~/.dotfiles-mac/macos.sh             # apply
```

Safe to re-run: it reads and type-checks each setting first, then writes the desired value (re-asserting even when it already matches), skips any key whose stored type is unexpected (with a warning), and sets missing keys. Before the first actual change it backs up each affected domain to `backups/defaults-<timestamp>/`. UI restarts (Dock, Finder, menu bar) happen at the end only when something actually changed, after you confirm.

Run `macos.sh --list` to see the exact set of settings it manages (printed as a Markdown table).

### Manual macOS tweaks

The settings below aren't automated (not exposed via `defaults`, require sudo, or out of scope) — apply them by hand on a fresh machine to match this setup.

#### System Settings

| Area | Setting | Value | Reason not automated |
|------|------|------|------|
| Apple Account | ID | pkdone.apple@icloud.com | Interactive Apple ID sign-in; not a `defaults` key |
| Displays | Built-in Display | More Space | Display scaling is hardware-specific; not reliably scriptable |
| Desktop & Dock | Widgets on desktop | None (all removed) | Widget placement isn't exposed via `defaults`; removed per-widget in the UI |
| Keyboard | Text input sources | British | Input sources are a complex array blob; error-prone to script |
| Mouse | Tracking speed | faster | Device-specific pointer scaling; left manual to preserve feel |
| Mouse | Natural scrolling | Off | Global key also flips the trackpad; handled via Logi Options+ |
| Mouse | Secondary click | Click Right Side | Button mapping stored per-device, not a stable global key |
| Mouse | Double click speed | faster | Device-specific timing; no stable global `defaults` key |
| Mouse | Scrolling speed | faster | Device-specific scaling; left manual |
| Trackpad | Point & Click tracking speed | Slower | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - click | Light | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - Lookup & Data Detectors | off | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - Secondary click | Click in bottom right corner | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - Tap to click | On | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | Point & Click - Force Click and haptic feedback | Off | Trackpad prefs span two interdependent domains; fragile to script |
| Trackpad | More Gestures - Three-finger drag | Off | Trackpad prefs span two interdependent domains; fragile to script |
| Accessibility | Pointer Control — Trackpad Options — Use trackpad for dragging | On (Without Drag Lock) | Accessibility settings are TCC-protected; not writable via `defaults` |
| Accessibility | Display — Pointer — Pointer size | One notch above Normal | Accessibility settings are TCC-protected; not writable via `defaults` |
| User & Groups | Paul Done icon | Dog | Account picture is set via Directory Services, not `defaults` |
| Notifications | When mirroring or sharing the display | Notifications Off | Notification prefs are SIP-protected (ncprefs); unsafe to script |
| Notifications | App notifications turned Off: Calendar, Cursor Nightly, FaceTime, Game Center, Home, Mail, Microsoft Teams, Slack, Spotify, Tips, Wallet | Off | Notification prefs are SIP-protected (ncprefs); unsafe to script |
| Spotlight | Results from Apps — disable: Books, Keynote, Mail, Notes, Numbers, Photos, Podcasts, Reminders, Stocks, Tips, Voice Memos | Off | Changing categories triggers reindexing; complex ordered array, out of scope |

#### Finder

| Area | Setting | Value |
|------|------|------|
| Sidebar | Show Recents | Off |

#### CotEditor

| Area | Setting | Value |
|------|------|------|
| Mode | General - Font | Monospaced |
| Appearance | Default theme | Anura (Dark) |

#### AltTab

| Area | Setting | Value |
|------|------|------|
| Controls | Show windows from Spaces | Visible Spaces |
| Controls | Show apps with no open window | Hide |
| Exceptions | Slack | Hide windows |

#### Logi Options+

| Area | Setting | Value |
|------|------|------|
| Pointer & Scrolling | Smooth scrolling | On |

#### Gemini

The Gemini desktop app's default shortcuts (`Option + Space` and `Option + Shift + Space`) clash with the ChatGPT app. Change them via Gemini Settings → Shortcuts:

| Action | Shortcut |
|------|------|
| Mini chat | `Control + Option + G` |
| Full chat | `Control + Option + Shift + G` |

#### Raycast

On first launch, Raycast auto-binds itself to `Option + Space`, which clashes with the ChatGPT app. Change it via Raycast Settings → General → Raycast Hotkey to `Shift + Control + Command + R`.

To bind a global hotkey for activating Finder from anywhere:
1. Open Raycast (`Shift + Control + Command + R`)
2. Type **Finder** until "Finder" appears as a command result
3. Highlight it and press `Command + K` (Actions menu)
4. Choose **Configure Application…**
5. Click the **Record Hotkey** field and press `Shift + Control + Command + F`

To enable Clipboard History:
1. Open Raycast and run the **Clipboard History** command once
2. Grant Accessibility permission if prompted (System Settings → Privacy & Security → Accessibility → enable Raycast)
3. Bind a hotkey via Raycast Settings → Extensions → search "clipboard", then in the **Clipboard History** row of type **Command** (not the parent "Extension" row), click **Record Hotkey** and press `Control + Command + V`.
   - Avoid `Command + Shift + V` (paste without formatting) and `Command + Option + V` (Finder paste-as-move).
4. Set **Keep History For** to 1 Day
5. Add password apps to **Disabled Applications** so their copies are never recorded: 1Password, 1Password for Safari

## Usage & reference

### Making changes

Edit configs normally — changes go directly into the repo via symlinks. Then push:

```bash
dotpush "your message"
```

To install new packages, add them to `Brewfile` and run `brewsync`.

### Fish functions

| Function | Description |
|------|------|
| `brewsync` | Installs, upgrades, and cleans up Homebrew packages from the Brewfile |
| `dotpush <message>` | Commits and pushes all dotfile changes to GitHub in one command |
| `edit <file>` | Opens a file in CotEditor |

### macOS Shortcuts

Standard macOS shortcuts rely on Command (⌘) for system-wide actions and line navigation, and Option (⌥) for semantic movements and word navigation. The Control (^) key is reserved for system functions (Lock Screen, Mission Control), screenshot-to-clipboard actions, and Linux/Emacs-style navigation in Terminal (e.g., Control + A). These patterns apply to most native macOS applications and text fields (such as Slack or browser bars).

#### Text Navigation and Editing

| Action | Shortcut |
|------|------|
| Start of line | Command + Left Arrow |
| End of line | Command + Right Arrow |
| Previous word | Option + Left Arrow |
| Next word | Option + Right Arrow |
| Select to start of line | Shift + Command + Left Arrow |
| Select to end of line | Shift + Command + Right Arrow |
| Select previous word | Shift + Option + Left Arrow |
| Select next word | Shift + Option + Right Arrow |
| Select all | Command + A |
| Paste without formatting | Command + Shift + V |
| Delete character after cursor (Fwd Delete) | Fn + Delete |
| Delete previous word | Option + Delete |
| Delete next word | Fn + Option + Delete |
| Delete to start of line | Command + Delete |

#### Document Navigation and Selection

| Action | Shortcut |
|------|------|
| Start of document | Command + Up Arrow |
| End of document | Command + Down Arrow |
| Select to start of document | Shift + Command + Up Arrow |
| Select to end of document | Shift + Command + Down Arrow |
| Page Up | Fn + Up Arrow |
| Page Down | Fn + Down Arrow |

#### Screenshot Actions

**Pro Tip:** Adding the **Control** key to any of the following shortcuts copies the image to the clipboard instead of saving a file.

| Capture Type | Save to File | Copy to Clipboard |
|------|------|------|
| Whole screen | Shift + Command + 3 | Control + Shift + Command + 3 |
| Selected area | Shift + Command + 4 (+ drag) | Control + Shift + Command + 4 (+ drag) |
| Selected window | Shift + Command + 4 + Space | Control + Shift + Command + 4 + Space |
| Screen Copy Options panel | Shift + Command + 5 | N/A |

#### System and Utility Actions

| Action | Shortcut / Gesture |
|------|------|
| Spotlight Search | Command + Space |
| Open settings in current app | Command + , |
| Activate Finder (via Raycast) | Shift + Control + Command + F |
| Clipboard History (via Raycast) | Control + Command + V |
| Force Quit Applications window | Option + Command + Escape |
| Lock Screen | Control + Command + Q OR TouchID press |
| App Switcher | Command + Tab |
| AltTab Switcher | Option + Tab |
| Mission Control / Desktop Overview | Control + Up Arrow OR 3-Finger Swipe Up |
| Show Desktop | Fn + F11 OR Click desktop space |
| Move Item to Trash | Command + Backspace (in Finder/Desktop) |
| Paste file as a move (cut & paste) | Option + Command + V (in Finder, after Command + C) |
| Show/hide hidden files in Finder | Command + Shift + . |
| Ghostty Quick Launcher | Command + ` |
| Claude Browser | Command + E (in Chrome) |
| Claude Chat | Option, Option (i.e., double-tap) |
| ChatGPT | Option + Space |
| Gemini | Control + Option + G |

#### Terminal and Shell Differences

Terminal applications often use Linux/Emacs-style bindings, which override standard macOS behavior.

| Terminal Action | Shortcut |
|------|------|
| Start of line | Control + A |
| End of line | Control + E |
| Delete to start of line | Control + U |
| Interrupt process | Control + C |
| Navigate by word | Option + Left / Right (may require terminal-specific config) |

#### Ghostty

Custom keybindings configured in `ghostty/config`.

| Action | Shortcut |
|------|------|
| Toggle fullscreen | Command + Enter |
| Clear screen | Command + K |
| New tab | Command + T |
| Next tab | Control + Tab |
| Previous tab | Control + Shift + Tab |
| New split (right) | Command + D |
| New split (down) | Command + Shift + D |
| Close surface (tab/split) | Command + W |
| Go to previous split | Command + [ |
| Go to next split | Command + ] |
| Resize split up | Command + Control + Up Arrow |
| Resize split down | Command + Control + Down Arrow |
| Resize split left | Command + Control + Left Arrow |
| Resize split right | Command + Control + Right Arrow |
| Equalize splits | Command + Control + = |
| Start search | Command + F |
| End search | Escape |
| Next search result | Command + G |
| Previous search result | Command + Shift + G |
| Reload config | Command + Shift + , |
