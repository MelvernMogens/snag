# Threat model — snag

Re-read at the start of each milestone; a threat model that is never revisited is decoration.

## What we protect, and from whom

| Asset | Adversary | Why it matters |
|---|---|---|
| The user's own files on the shelf | Snag itself (a bug) | Deleting or moving a referenced file would be data loss. |
| The user's files, via a tampered `shelf.json` | Any local process that can write to `~/Library/Application Support/Snag` | Marking a user file `"owned": true` could trick cleanup into deleting it. |
| Content of dropped pasteboards | A malicious web page offering a crafted drag (weird filenames, huge text, `javascript:` URLs) | Path traversal in generated filenames, or memory blowups. |

Attack surface is small: a local, single-user utility with no network, no accounts and no server.

## Current posture
- Referenced files are never written or deleted. `ShelfStore.deleteOwned` only deletes paths
  that resolve inside `Items/`, whatever the JSON claims (test: `testTamperedIndexCannotMakeStoreDeleteOutsideItsDirectory`).
- Generated filenames are stripped of `/ : \ NUL`, control characters, newlines and leading dots,
  and length-capped (test: `testCleanStripsIllegalCharacters`).
- Text snippets are capped at 5M characters. Only http/https/ftp/mailto become links (test: `testLinkRejectsNonWebSchemes`).
- No network access at all. No Accessibility permission requested.

## Rules that must hold
- Only owned files under `Items/` are ever deleted. This is enforced in code and covered by a test.
- User-supplied names go through `ItemFactory.clean` before touching the filesystem.

## Accepted risks
- Ad-hoc signed, not notarized: fine for one personal Mac.
- `shelf.json` isn't integrity-protected. A local attacker who can write there can already write the user's files directly.

## Practice
- `/ship` before calling any milestone done.
- CI runs `swift test` on every push.
