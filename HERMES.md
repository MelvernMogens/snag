# snag

## What this is
Snag is a native macOS drag-and-drop shelf, a personal clone of Yoink. Start dragging anything
and a translucent shelf slides in on the left edge; drop files, text, links or images on it, go
find the destination, then drag them back out. It is a menu-bar-only app (no Dock icon), for
Melvern's own Mac.

## Stack
- **Swift 6 / AppKit, SwiftPM, no Xcode project.** Window-level tricks the shelf needs
  (non-activating panel on all Spaces and over full-screen apps, global mouse monitors, drag
  sessions, Quick Look panel) are AppKit APIs; SwiftUI would just wrap them.
- **ShelfKit** (library target) = model, persistence, geometry, settings. Pure Foundation, unit tested.
- **Snag** (executable target) = AppKit UI. Thin; logic belongs in ShelfKit where it can be tested.
- Bundled by `scripts/build.sh` (copies the binary into `build/Snag.app`, renders the icon, ad-hoc signs it).
- **Rejected:** Electron/Tauri (they can't do non-activating edge panels or real file drag-out
  cleanly). An Xcode project (adds a pbxproj with no gain for a single-target menu-bar app).

## Commands
```bash
swift test                       # ShelfKit unit tests (41)
swift build                      # debug build of everything
./scripts/build.sh               # release build -> build/Snag.app (+ icon, ad-hoc sign)
./scripts/build.sh --install     # also copy to /Applications and relaunch
SNAG_DATA_DIR=/tmp/x build/Snag.app/Contents/MacOS/Snag   # run against a throwaway shelf
SNAG_SHOW_ON_LAUNCH=1 ...        # force the shelf open at launch (testing)
SNAG_DATA_DIR=/tmp/x SNAG_SELFTEST_RENAME="New" .../Snag  # opens inline rename on the top item, types, presses Return, prints SELFTEST + quits
```
Real data: `~/Library/Application Support/Snag/` (`shelf.json` + `Items/` for owned files).
Settings: `defaults read com.melvern.snag`.

## Milestones — status and which model to use
Product scope, non-goals, and open questions live in `docs/prd.md`.

| # | Scope | Status | Model / effort |
|---|---|---|---|
| M1 | Shelf slice: any drag -> shelf on the left edge; files/text/links/images/promises; drag-out; stacks; persistence; menu bar; hotkeys; Quick Look; settings | done | opus / high |
| M2 | Daily-driver polish: multi-select drag-out, reorder, per-item rename, clipboard history toggle | todo | opus / high |
| M3 | Distribution: Developer ID signing + notarization, Sparkle updates (needs paid dev account) | todo | opus / high |

Default is your strongest model + high effort. Raise to maximum effort only for
adversarial or security work; drop to a cheap model + medium for UI boilerplate.

**State the model and effort at the start of every milestone, before working.**

## Behavior contract (what Melvern asked for, do not regress)
- Docks to the **left** edge by default.
- **Empty shelf = hidden.** It slides in as soon as ANY drag starts (like Yoink), and hides
  after the drag ends if nothing was dropped. ("Near edge" / "manual" remain as settings.)
- **Shelf with items = always visible**, on every Space including full-screen apps (re-ordered front on `activeSpaceDidChange`). Room for at least 5 rows; it grows, then scrolls.
- Multi-select: ⌘-click toggle, ⇧-click range, ⌘A; dragging a selected tile drags the whole selection (logic in `ShelfKit/Selection.swift`).
- Rename (Return / right-click) renames the real file in place via `ShelfStore.rename`; never overwrites, rejects `/ :`, leading dots, >255 bytes. Stacks can't be renamed.
- No notifications, no big buttons. The header shows the file count and a small trash icon.

## Gotchas
- Drag detection needs no Accessibility permission: `NSPasteboard(name: .drag).changeCount`
  changes when any app starts a drag, and the poller only runs while the mouse button is held.
- The user's own files are held **by reference** (path + bookmark), never copied or deleted.
  Only files under `Items/` are owned, and `ShelfStore.deleteOwned` refuses any path outside it.
- Owned files removed by a drag-out are deleted after 5 minutes, because Mail/Slack may still be reading them.

## Conventions
- Ask before adding a dependency (there are none).
- Never commit secrets.

## House rules
- **Before adding a feature to working code, run the tests FIRST.**
- After editing, run `swift test` + `./scripts/build.sh` and report the real result.
- If the diff contradicts a sentence in a doc, that sentence is part of the diff.
- If you are unsure, say so instead of guessing.
