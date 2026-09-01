# TODOS

## XML Round-Trip

### Typed Track fields are frozen for parsed tracks
**Priority:** P2
The verbatim writer re-emits `rawAttributes`/`rawChildrenXML` for tracks parsed from an existing XML, so any future in-app edit to a parsed track's typed fields (name, rating, cues) would be silently reverted on write. Before building any track-editing feature, route typed-setter mutations through methods that also update the raw copies (or clear them). Noticed on branch fix/review-hardening.

## USB Sync

### Test: temp file preserved when destination is gone
**Priority:** P3
`USBSync.execute` keeps the temp copy when the destination was already removed and the final move fails (the temp is the only surviving copy). Covering this needs an injected `moveItem` failure — requires a FileManager seam or protocol. Noticed on branch fix/review-hardening.

### Test: per-file attribute-read degradation
**Priority:** P4
`plan()` degrades per-file when `attributesOfItem` fails mid-plan (file vanished). Inherently racy to reproduce with the real filesystem; needs the same injection seam as above.

## Library Sync

### Unchecked removals still lose playlist membership
**Priority:** P3
The playlist tree is rebuilt from the folder structure on every sync (by design), so a removed-but-unchecked track stays in the collection but leaves all playlists. Revisit if this surprises real usage — the timestamped `.bak` files are the current safety net.

## Distribution

### Notarize the app for public distribution
**Priority:** P3
Bundles are ad-hoc signed (`codesign --sign -`), enough for local installs but Gatekeeper blocks downloaded copies. Add Developer ID signing + `notarytool` to `scripts/dmg.sh` if the DMG is ever distributed.

### Backup pruning discards the pre-first-sync state
**Priority:** P2
`LibraryBackup.prune` keeps the newest five backups and treats them all equally, so the copy taken before the app ever touched the library ages out after five syncs. Found during the manual smoke test: six syncs pruned the original 1-track backup, leaving only post-sync copies. On a real library that's a normal week, and it's the state most worth rolling back to. Fix: keep the first-ever backup permanently (`.original.bak`), or make retention time-based rather than count-based.

## Completed
