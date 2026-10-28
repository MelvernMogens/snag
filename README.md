# Snag

A drag-and-drop shelf for macOS, like Yoink: park files at the edge of the screen, go find where they belong, drag them back out.

## Why

Dragging a file across apps, Spaces or full-screen windows means holding the mouse button down
while you navigate. Snag gives the drag somewhere to land halfway: drop it on the shelf, let go,
take your time, then pick it up again.

## How it works

```
  any app: start dragging ──► shelf slides in on the left ──► drop on it
                                                                          │
     Finder / Mail / Slack ◄── drag it back out ◄── shelf stays visible ◄─┘
                                (item leaves the shelf)
```

- **Empty shelf:** hidden. It slides in the moment you start dragging anything.
- **Shelf with items:** stays visible on the left edge until you empty it, on every desktop, including full-screen apps.
- **Files** are kept by reference (nothing is copied), and moving or renaming them is tracked via bookmarks.
- **Several files dropped at once** become a stack you can drag out together or split.
- **Text, links and images** dragged from apps or browsers become real `.txt`, `.webloc` and `.png` files you can drop anywhere.
- **File promises** (Mail attachments, Photos) are received into Snag's own storage.

### Controls

| | |
|---|---|
| `⌥⌘Y` | show / hide the shelf |
| `⌃⌥⌘V` | put the clipboard on the shelf |
| ⌘-click / ⇧-click / `⌘A` | select several items, then drag them out together |
| `Return` or right-click → Rename… | rename the file (really renames it on disk; refuses if the name is taken) |
| `⌘O` / `⌘↓` | open |
| `Space` | Quick Look the selection |
| `⌫` | remove selected item |
| `⌘V` / `⌘C` | paste into / copy from the shelf |
| double-click | open |
| right-click | Open, Quick Look, Show in Finder, Copy, Split Stack, Remove |
| Services menu | "Add to Snag" from any app |

Menu bar icon → Settings: edge (left/right), when to show, remove after drag-out, launch at login.

## Honest limits

- Ad-hoc signed, not notarized. It runs on the Mac that built it; on another Mac, Gatekeeper will complain.
- No iCloud sync, Handoff or iOS app (Yoink has these).
- Drag detection relies on the system drag pasteboard. A few apps that run fully custom drags
  without touching it won't trigger the shelf. Use `⌥⌘Y` for those.

## Stack

Swift 6, AppKit, SwiftPM. No dependencies. Model and logic live in `ShelfKit` (unit tested);
the UI lives in `Snag`.

## Getting started

```bash
swift test                     # 41 unit tests
./scripts/build.sh --install   # build, copy to /Applications, launch
```

## Roadmap

- M2: multi-select drag-out, reorder, rename, optional clipboard history
- M3: Developer ID signing + notarization, auto-updates
