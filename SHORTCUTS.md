# Keyboard shortcuts & macOS reference

Cheat-sheets for macOS, the terminal, and Ghostty. Setup docs live in [README.md](README.md).

### macOS Shortcuts

⌘ = system / line; ⌥ = word/semantic; ⌃ = system (Lock Screen, Mission Control) and Emacs-style in Terminal. Applies in most native text fields.

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
| Home | Fn + Left Arrow |
| End | Fn + Right Arrow |

#### Screenshot and Screen Recording Actions

**Pro Tip:** Adding the **Control** key to any of the following shortcuts copies the image to the clipboard instead of saving a file.

| Capture Type | Save to File | Copy to Clipboard |
|------|------|------|
| Whole screen | Shift + Command + 3 | Control + Shift + Command + 3 |
| Selected area | Shift + Command + 4 (+ drag) | Control + Shift + Command + 4 (+ drag) |
| Selected window | Shift + Command + 4 + Space | Control + Shift + Command + 4 + Space |
| Screenshot / screen-recording toolbar (Record Entire Screen / Record Selected Portion) | Shift + Command + 5 | N/A (recordings always save as a .mov file) |
| Stop recording | Menu-bar stop button OR Control + Command + Esc | N/A |

**Recording tips:** In the Shift + Command + 5 toolbar, turn on **Options > Show Mouse Clicks** so clicks show up. Keep clips under a minute and record just the window.

**No clipboard for recordings:** Adding Control only copies *screenshots* (e.g. Control + Shift + Command + 4). The toolbar's **Save to > Clipboard** option also only applies to screenshots.

**Quick share:** After stopping, drag the thumbnail in the bottom-right corner straight into a chat (e.g. Grok Bot).

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
| Toggle Full Screen | Fn + F (system-wide; Ghostty also uses Command + Enter) |
| Mission Control / Desktop Overview | Control + Up Arrow OR 3-Finger Swipe Up OR F3 (Mission Control key) |
| Show Desktop | Fn + F11 OR Click desktop space |
| Move Item to Trash | Command + Backspace (in Finder/Desktop) |
| Forward Delete → Trash | Forward Delete (in Finder; mapped to Move to Trash) |
| Paste file as a move (cut & paste) | Option + Command + V (in Finder, after Command + C) |
| Show/hide hidden files in Finder | Command + Shift + . |
| Ghostty Quick Launcher | Command + ` |
| Claude Browser | Command + E (in Chrome) |
| Claude Chat | Option, Option (double-tap) |
| ChatGPT | Option + Space (Raycast was moved off this — see README) |
| Gemini mini chat | Control + Option + G |
| Gemini full chat | Control + Option + Shift + G |

#### Window Tiling

Native window tiling on macOS Sequoia 15 and later. Apple's user guide writes the Globe key as Fn; on an Apple keyboard they are the same key. Shortcuts are from [Mac window tiling icons and keyboard shortcuts](https://support.apple.com/guide/mac-help/mac-window-tiling-icons-keyboard-shortcuts-mchl9674d0b0/mac). Dragging is from [Tile windows on Mac](https://support.apple.com/guide/mac-help/tile-app-windows-mchlef287e5d/mac).

**Move and resize the active window**

| Action | Shortcut |
|------|------|
| Tile left half | Globe + Control + Left Arrow |
| Tile right half | Globe + Control + Right Arrow |
| Tile top half | Globe + Control + Up Arrow |
| Tile bottom half | Globe + Control + Down Arrow |
| Fill the desktop | Globe + Control + F |
| Center on the desktop | Globe + Control + C |
| Return to previous size | Globe + Control + R |

The top-left, top-right, bottom-left, and bottom-right quarter positions have no keyboard shortcut. Apple lists each one as n/a. Use the green button, or the Window menu, Move & Resize.

**Arrange two windows.** Globe + Control + Shift + arrow places the active window and a second window. It does not tile one window into a quarter.

| Action | Shortcut |
|------|------|
| Active window left, second window right | Globe + Control + Shift + Left Arrow |
| Active window right, second window left | Globe + Control + Shift + Right Arrow |
| Active window top, second window bottom | Globe + Control + Shift + Up Arrow |
| Active window bottom, second window top | Globe + Control + Shift + Down Arrow |

The four-corner Quarters layout has no keyboard shortcut. Globe + Control + Option + Shift + arrow is the documented half-plus-two-quarters arrange:

| Action | Shortcut |
|------|------|
| Active window left half, second and third windows in the right quarters | Globe + Control + Option + Shift + Left Arrow |
| Active window right half, second and third windows in the left quarters | Globe + Control + Option + Shift + Right Arrow |
| Active window top half, second and third windows in the bottom quarters | Globe + Control + Option + Shift + Up Arrow |
| Active window bottom half, second and third windows in the top quarters | Globe + Control + Option + Shift + Down Arrow |

**Drag.** Drag a window to a screen edge (left, right, a corner, or the menu bar) and release when the highlighted area appears; the window tiles. Dragging to the menu bar fills the desktop. Hold Option while dragging toward an edge or corner and the window tiles immediately.

This repo pins drag-to-left-or-right-edge On and tiled-window margins Off (`lib/macos-defaults.list`). The other Desktop & Dock window toggles stay as they are.

#### Finder

| Action | Shortcut |
|------|------|
| Copy selected item's full path (POSIX pathname) to the clipboard | Option + Command + C |

Or right-click the item, hold Option, and choose **Copy "item" as Pathname**. To copy a folder's own path, select it in its parent folder first (the path shown in the window title bar is display-only).

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

| Action | Shortcut |
|------|------|
| Command palette | Command + Shift + P |
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
| Next search result | Command + G |
| Previous search result | Command + Shift + G |
| Reload config | Command + Shift + , |

#### Slack

| Action | Shortcut |
|------|------|
| Send message | Command + Enter |
| New line in message | Enter |

Set in Slack > Settings > Advanced > 'When writing a message, press Enter to...' > Start a new line.
