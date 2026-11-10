# Snag

**A drag-and-drop shelf for macOS, like Yoink.** Park files at the edge of the screen, go find where they belong, then drag them back out.

Dragging a file across apps, Spaces or full-screen windows means holding the mouse button the whole way. Snag gives the drag a place to land halfway: drop it on the shelf, let go, take your time, pick it up again.

```
  any app: start dragging ──► shelf slides in on the left ──► drop on it
                                                                          │
     Finder / Mail / Slack ◄── drag it back out ◄── shelf stays visible ◄─┘
                                (item leaves the shelf)
```

## Features

- **Appears when you drag.** An empty shelf is hidden and slides in the moment any drag starts. No Accessibility permission needed.
- **Stays while it has items**, on every desktop, including over full-screen apps.
- **Files are kept by reference.** Nothing is copied; moves and renames are tracked with bookmarks.
- **Text, links and images** dragged from apps or browsers become real `.txt`, `.webloc` and `.png` files you can drop anywhere.
- **File promises** (Mail attachments, Photos) are received into Snag's own storage.
- **Stacks.** Several files dropped at once become one stack you can drag out together or split.
- **Multi-select drag-out** with ⌘-click, ⇧-click or ⌘A.
- **Inline rename** that renames the real file on disk and refuses if the name is taken.
- Quick Look, Show in Finder, copy/paste, and an **Add to Snag** Services menu item.
- Menu-bar only (no Dock icon). No dependencies.

## Install

Requirements: macOS 13 or later, Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/MelvernMogens/snag.git
cd snag
./scripts/build.sh --install   # build, copy to /Applications, launch
```

`build.sh` does a release build, wraps it in `Snag.app`, draws the icon and ad-hoc signs it. With `--install` it also copies the app to `/Applications` and launches it. Because you build it on your own Mac, Gatekeeper accepts it; a `.app` copied from someone else's Mac will be blocked.

To update, `git pull` and run the same command again.

## Controls

| Key / action | Does |
|---|---|
| `⌥⌘Y` | Show / hide the shelf |
| `⌃⌥⌘V` | Put the clipboard on the shelf |
| ⌘-click / ⇧-click / `⌘A` | Select several items, then drag them out together |
| `Return` or right-click → Rename… | Rename the file on disk |
| `⌘O` / `⌘↓` / double-click | Open |
| `Space` | Quick Look the selection |
| `⌫` | Remove the selected item |
| `⌘V` / `⌘C` | Paste into / copy from the shelf |
| Right-click | Open, Quick Look, Show in Finder, Copy, Split Stack, Remove |
| Services menu | "Add to Snag" from any app |

**Settings** (menu bar icon → Settings): dock edge (left/right), when to show the shelf (on any drag / when a drag reaches the edge / only from the hotkey or menu bar), remove after drag-out, launch at login.

Data lives in `~/Library/Application Support/Snag/` (`shelf.json` plus `Items/` for files Snag owns). Snag only deletes files inside `Items/`, and waits 5 minutes after a drag-out so the receiving app can finish reading them.

## Develop

```bash
swift test                     # 41 ShelfKit unit tests
swift build                    # debug build
./scripts/build.sh             # release build -> build/Snag.app
SNAG_DATA_DIR=/tmp/x build/Snag.app/Contents/MacOS/Snag   # run against a throwaway shelf
```

```
Sources/ShelfKit/   model, persistence, selection, geometry, settings (pure Foundation, unit tested)
Sources/Snag/       AppKit UI: shelf panel, drag monitor, hotkeys, thumbnails, settings window
App/                Info.plist and the code-drawn icon (MakeIcon.swift)
scripts/build.sh    bundle, sign, install
```

Swift 6, AppKit, SwiftPM. No Xcode project.

## Limits

- Ad-hoc signed, not notarized (see Install).
- No iCloud sync, Handoff or iOS app (Yoink has these).
- Drag detection watches the system drag pasteboard. A few apps with fully custom drags won't trigger the shelf; use `⌥⌘Y` for those.

## Roadmap

- Reorder items, optional clipboard history
- Developer ID signing, notarization and auto-updates

Built by [Melvern Mogens](https://github.com/MelvernMogens).
