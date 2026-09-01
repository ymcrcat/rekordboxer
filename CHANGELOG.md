# Changelog

All notable changes to Rekordboxer are documented in this file.
Versions follow MAJOR.MINOR.PATCH.MICRO.

## [1.0.1.0] - 2026-08-31

### Fixed
- Syncing against a pre-existing rekordbox XML (or with a missing/stale track-ID map) no longer silently overwrites tracks or drops existing tracks from playlists — track IDs are reconciled with the library on every load, and stale ID-map entries are purged.
- A rekordbox XML that fails to read or parse now blocks syncing instead of being treated as an empty library and overwritten.
- Rewriting the XML no longer alters data the app didn't touch: attribute formatting, cue points, beatgrids, and unknown fields round-trip byte-for-byte for existing tracks.
- Accented filenames (é, ü, …) no longer churn as "new + removed" on every scan, which silently shed cue points; paths are Unicode-normalized on both sides.
- USB copies can no longer destroy the only copy of a track on the stick: files are copied to a temp file and swapped, and a failed swap preserves whichever copy survives.
- Two tracks sharing a filename anywhere in the library are now skipped as ambiguous instead of silently overwriting the same USB file; plan rows are keyed by destination so checkboxes can't toggle the wrong file.
- Same-size edits to audio files are now detected via modification time, so an edited file of identical byte size still syncs to USB.
- Playlists keyed by track location (KeyType="1") are resolved to track IDs instead of being silently emptied.
- Hidden files (including FAT32 `._` metadata), symlinked folders, and non-regular files are excluded from library scans, preventing junk tracks and infinite recursion.
- Double-clicking Sync or switching tabs/volumes mid-operation can no longer corrupt state: writes, scans, and USB plans are guarded against re-entrancy, and a plan is invalidated when the volume changes.
- Dates written to the XML use a fixed calendar, so non-Gregorian system calendars can't write wrong years.

### Added
- Timestamped backups of the XML before every sync (newest five kept).
- The sync refuses to overwrite a rekordbox XML that changed on disk since the last scan.
- USB plan now reports files skipped as ambiguous, not present on the USB, or missing at the source.
- App bundles are ad-hoc code-signed, and the app version is read from the VERSION file.

### Changed
- Removed tracks now default to unchecked — deleting a track from the library requires an explicit check.
- XML writing and USB scanning run off the main thread, so large libraries no longer freeze the app.
- External XML entities are disabled when parsing (hardening against malicious library files).
