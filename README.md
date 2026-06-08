# dotfiles-mac

Personal macOS dotfiles and bootstrap setup.

## Contents

- `Brewfile` — all Homebrew packages and casks
- `fish/` — Fish shell config and functions
- `ghostty/` — Ghostty terminal config
- `gitconfig` — Git user and behaviour settings
- `mise/` — pinned default tool versions (Node, npm)
- `install.sh` — bootstraps a new machine

## New machine setup

```bash
git clone https://github.com/pkdone/.dotfiles-mac.git ~/.dotfiles-mac
bash ~/.dotfiles-mac/install.sh
```

This creates symlinks from `~/.config` into this repo and installs everything in the Brewfile.

After running, trust the `mise` config to silence its warnings:

```bash
mise trust ~/.dotfiles-mac/mise/config.toml
```

## Day-to-day

Edit configs normally — changes go directly into the repo via symlinks. Then push:

```bash
dotpush "your message"
```

To install new packages, add them to `Brewfile` and run `brewsync`.

## Fish functions

| Function | Description |
|----------|-------------|
| `brewsync` | Installs, upgrades, and cleans up Homebrew packages from the Brewfile |
| `dotpush` | Commits and pushes all dotfile changes to GitHub in one command |
| `edit` | Opens a file in CotEditor |

## Set Hostname

```bash
sudo scutil --set HostName pdone-mac
sudo scutil --set LocalHostName pdone-mac
sudo scutil --set ComputerName pdone-mac
dscacheutil -flushcache
```

## Manual macOS tweaks

These settings adjustments aren't automated — apply them by hand on a fresh machine to match this setup.

### System Settings

| Area | Setting | Value |
|------|---------|-------|
| Apple Account | ID | pkdone.apple@icloud.com |
| Appearance | Theme | Dark mode |
| Displays | Built-in Display | More Space | 
| Dock | Icon size | Smaller than default (~46px) |
| Dock | Show recent applications | Off |
| Dock | Auto-rearrange Spaces based on most recent use | Off |
| Sound | Play feedback when sound is changed | On |
| Finder | Default view | Icon view |
| Finder | Show hard drives on Desktop | Off |
| Keyboard | Text input sources | British |
| Mouse | Tracking speed | faster |
| Mouse | Double click speed | faster |
| Mouse | Scrolling speed | faster |
| Trackpad | Point & click tracking speed | Slower |
| Trackpad | Point & click - click | Light |
| Trackpad | Point & Click - Lookup & Data Detectors | off |
| Trackpad | Point & Click - Secondary click | Click in bottom right corner |
| Trackpad | Point & Click - Tap to click | On |
| Accessibility | Pointer Control — Trackpad Options — Use trackpad for dragging | On (Without Drag Lock) |
| Accessibility | Display — Pointer — Pointer size | One notch above Normal |
| User & Groups | Paul Done icon | Dog |
| Control Center | Clock — Show AM/PM | On |
| Control Center | Clock — Show day of week | On |
| Control Center | Clock — Show date | On |
| Screenshots | Default save location | `~/Pictures` (`defaults write com.apple.screencapture location ~/Pictures && killall SystemUIServer`) |

### Finder

| Area | Setting | Value |
|------|---------|-------|
Op| General | New Finder windows show | Home folder | | Sidebar | Show Recents | Off |

### CotEditor

| Area | Setting | Value |
|------|---------|-------|
| Mode | General - Font | Monospaced |
| Appearance | Default theme | Anura (Dark) |

### AltTab

| Area | Setting | Value |
|------|---------|-------|
| Controls | Show windows from Spaces | Visible Spaces |
| Controls | Show apps with no open window | Hide |
| Exceptions | Slack | Hide windows |

### Raycast

On first launch, Raycast auto-binds itself to `Option + Space`, which clashes with the ChatGPT app. Change it via Raycast Settings → General → Raycast Hotkey to `Shift + Control + Command + R`.

To bind a global hotkey for activating Finder from anywhere:
1. Open Raycast (`Shift + Control + Command + R`)
2. Type **Finder** until "Finder" appears as a command result
3. Highlight it and press `Command + K` (Actions menu)
4. Choose **Configure Application…**
5. Click the **Record Hotkey** field and press `Shift + Control + Command + F`

## **Fish Commands Configured**

* **brewsync**   \- Installs, upgrades, and cleans up Homebrew packages from the Brewfile  
* **dotpush \<file\>**  \-  Commits and pushes all dotfile changes to GitHub in one command  
* **edit \<file\>**  \-  Opens a file in CotEditor

---

## **macOS Shortcuts**

Standard macOS shortcuts rely on Command (⌘) for system-wide actions and line navigation, and Option (⌥) for semantic movements and word navigation. The Control (^) key is reserved for system functions (Lock Screen, Mission Control), screenshot-to-clipboard actions, and Linux/Emacs-style navigation in Terminal (e.g., Control \+ A). These patterns apply to most native macOS applications and text fields (such as Slack or browser bars).

### **Text Navigation and Editing**

| Action | Shortcut |
| :---- | :---- |
| Start of line | Command \+ Left Arrow |
| End of line | Command \+ Right Arrow |
| Previous word | Option \+ Left Arrow |
| Next word | Option \+ Right Arrow |
| Select to start of line | Shift \+ Command \+ Left Arrow |
| Select to end of line | Shift \+ Command \+ Right Arrow |
| Select previous word | Shift \+ Option \+ Left Arrow |
| Select next word | Shift \+ Option \+ Right Arrow |
| Select all | Command \+ A |
| Paste without formatting | Command \+ Shift \+ V |
| Delete character after cursor (Fwd Delete) | Fn \+ Delete |
| Delete previous word | Option \+ Delete |
| Delete next word | Fn \+ Option \+ Delete |
| Delete to start of line | Command \+ Delete |

### **Document Navigation and Selection**

| Action | Shortcut |
| :---- | :---- |
| Start of document | Command \+ Up Arrow |
| End of document | Command \+ Down Arrow |
| Select to start of document | Shift \+ Command \+ Up Arrow |
| Select to end of document | Shift \+ Command \+ Down Arrow |
| Page Up | Fn \+ Up Arrow |
| Page Down | Fn \+ Down Arrow |

### **Screenshot Actions**

**Pro Tip:** Adding the **Control** key to any of the following shortcuts copies the image to the clipboard instead of saving a file.

| Capture Type | Save to File | Copy to Clipboard |
| :---- | :---- | :---- |
| Whole screen | Shift \+ Command \+ 3 | Control \+ Shift \+ Command \+ 3 |
| Selected area | Shift \+ Command \+ 4 (+ drag) | Control \+ Shift \+ Command \+ 4 (+ drag) |
| Selected window | Shift \+ Command \+ 4 \+ Space | Control \+ Shift \+ Command \+ 4 \+ Space |
| Screen Copy Options panel | Shift \+ Command \+ 5 | N/A |

### **System and Utility Actions**

| Action | Shortcut / Gesture |
| :---- | :---- |
| Spotlight Search | Command \+ Space |
| Open settings in current app | Command \+ , |
| Activate Finder (via Raycast) | Shift \+ Control \+ Command \+ F |
| Tile windows when dragging | Option \+ |
| Lock Screen | Control \+ Command \+ Q OR TouchID press |
| App Switcher | Command \+ Tab |
| AltTab Switcher | Option \+ Tab |
| Mission Control / Desktop Overview | Control \+ Up Arrow OR 3-Finger Swipe Up |
| Show Desktop | Fn \+ F11 OR Click desktop space |
| Move Item to Trash | Command \+ Backspace (in Finder/Desktop) |
| Paste file as a move (cut & paste) | Option \+ Command \+ V (in Finder, after Command \+ C) |
| Show/hide hidden files in Finder | Command \+ Shift \+ . |
| Ghostty Quick Launcher | Command \+ \` |
| Claude Browser | Command \+E (in Chrome) |
| Claude Chat | Option, Option (i.e., double-tap) |
| ChatGPT | Option \+ Space |

### **Terminal and Shell Differences**

Terminal applications often use Linux/Emacs-style bindings, which override standard macOS behavior.

| Terminal Action | Shortcut |
| :---- | :---- |
| Start of line | Control \+ A |
| End of line | Control \+ E |
| Delete to start of line | Control \+ U |
| Interrupt process | Control \+ C |
| Navigate by word | Option \+ Left / Right (may require terminal-specific config) |

### **Ghostty**

Custom keybindings configured in `ghostty/config`.

| Action | Shortcut |
| :---- | :---- |
| Toggle fullscreen | Command \+ Enter |
| Clear screen | Command \+ K |
| New tab | Command \+ T |
| Next tab | Control \+ Tab |
| Previous tab | Control \+ Shift \+ Tab |
| New split (right) | Command \+ D |
| New split (down) | Command \+ Shift \+ D |
| Close surface (tab/split) | Command \+ W |
| Go to previous split | Command \+ \[ |
| Go to next split | Command \+ \] |
| Resize split up | Command \+ Control \+ Up Arrow |
| Resize split down | Command \+ Control \+ Down Arrow |
| Resize split left | Command \+ Control \+ Left Arrow |
| Resize split right | Command \+ Control \+ Right Arrow |
| Equalize splits | Command \+ Control \+ = |
| Start search | Command \+ F |
| End search | Escape |
| Next search result | Command \+ G |
| Previous search result | Command \+ Shift \+ G |
| Reload config | Command \+ Shift \+ , |
