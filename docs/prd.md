# PRD — snag

Status: M1 shipped. Living document — correct it when reality disagrees, do not let it rot.

## 1. The problem
Moving files between apps on a Mac means holding the mouse button down while switching apps,
Spaces or full-screen windows. One slip and the drag is lost. Yoink fixes this for $8.99. Melvern
wants his own version that behaves exactly the way he likes.

## 2. What we are building
A menu-bar macOS app with a translucent shelf docked to the left screen edge. A drag that
reaches the edge reveals the shelf. Drop anything on it (files, text, links, images, file
promises), then drag it back out wherever it belongs.

## 3. Who it is for
Melvern, on his own Mac. It is a daily-driver utility, not a product for sale (yet).

## 4. What "done" means for the MVP
- Drag a file from Finder to the left edge → shelf appears → drop → it stays on the shelf, file untouched.
- Drag it from the shelf into another folder or app → it arrives and leaves the shelf.
- Empty shelf is invisible; a shelf with items stays visible; it survives a relaunch.
- Text, links and browser images work as well as files.

## 5. Scope
### In
Edge shelf on all Spaces and over full-screen apps · files by reference (bookmarks) · stacks and
split · text/link/image/promise ingest · drag-out with Finder semantics · persistence · menu
bar menu · hotkeys (⌥⌘Y, ⌃⌥⌘V) · Quick Look · right-click menu · Services "Add to Snag" ·
Open With Snag · settings window · launch at login.

### Out (deliberately, for now)
iCloud sync, Handoff, iOS app, a clipboard history UI, a Share extension (it needs an Xcode
app-extension target).

## 6. What not to oversell
Safe to say: "It's a Yoink-style shelf I built. Drag to the edge, drop, drag out later."
Not safe to say: "It's a drop-in replacement for Yoink." It has no iOS/iCloud/Handoff, it isn't
notarized, and a few apps with custom drag implementations won't auto-reveal the shelf.

## 7. Constraints that shape the build
- No paid Apple developer account: ad-hoc signing only, so no notarization and no sandboxed App Store build.
- No Accessibility permission. Drag detection must work from global mouse monitors plus the drag pasteboard.
- Never modify or delete the user's own files.

## 8. Parts inventory
Shelf panel · drag detector · ingest (pasteboard → items) · store + persistence · thumbnails ·
drag-out source · menu bar + hotkeys · settings · Quick Look · Services/Open With · icon +
bundle · (later) sync, clipboard history, signing/updates.

## 9. Milestones
| # | Slice | Status |
|---|---|---|
| M1 | Full shelf loop: drag in at the edge → shelf → drag out, for files, text, links, images, promises; persistence; menu bar; settings | done |
| M2 | Daily-driver polish: multi-select drag-out, reorder, rename, optional clipboard history | todo |
| M3 | Distribution: Developer ID + notarization, Sparkle updates | todo, needs a paid account |

## 10. Backlog
Share extension · per-app exclusions (don't reveal for drags inside app X) · shelf on the screen
under the pointer for multi-monitor setups (partly done: it shows on the drag's screen) · themes.

Per-milestone model/effort guidance lives in `HERMES.md`, not here.

## 11. Open questions
- Does the shelf really need a right-edge mode? Kept as a setting; the default is left.
- If Melvern ever wants this on another Mac, does he buy a $99/yr dev account for notarization,
  or keep right-click → Open?
- Clipboard history: worth it, or is it scope creep against Raycast/Paste, which he may already use?
