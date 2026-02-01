# Rekordboxer

A macOS app for syncing a local music folder into rekordbox playlists via the rekordbox XML interchange format, and efficiently updating audio files on USB sticks.

## Features

- **Library Sync**: Point Rekordboxer at a music folder (e.g. synced via Dropbox) and it generates a rekordbox XML file where each subfolder becomes a playlist. New tracks are added automatically; removed tracks require your confirmation before deletion. Existing track data (cue points, beatgrids, BPM analysis) is preserved.

- **Folder Tree Selection**: After scanning, folders are displayed as a hierarchical tree with tri-state checkboxes (checked, unchecked, mixed). Uncheck a folder to exclude it from the XML. On subsequent scans, folders are pre-selected based on what's already in the library — previously excluded folders stay unchecked.

- **USB Sync**: Select which playlists to sync to a USB stick. Rekordboxer tracks which files have changed since the last sync and copies only what's needed — no more deleting and re-exporting entire playlists through rekordbox.

## Requirements

- macOS 14+
- Swift 5.9+ (included with Xcode or Command Line Tools)

## Build

```bash
./scripts/bundle.sh
```

This builds a release binary and packages it into `build/Rekordboxer.app`.

To run:

```bash
open build/Rekordboxer.app
```

To install to Applications:

```bash
cp -r build/Rekordboxer.app /Applications/
```

## Usage

1. Open Rekordboxer and go to **Settings**
2. Set your music source folder (the folder whose subfolders become playlists)
3. Set a path for the rekordbox XML file
4. Go to **Library Sync**, click **Scan**, review changes, then **Sync to XML**
5. In rekordbox: File > Import Collection in XML Format
6. For USB updates: go to **USB Sync**, select a volume and playlists, then sync

## Architecture

Rekordboxer is a pure Swift project with no external dependencies. It uses SwiftUI for the UI and targets macOS 14+.

### Project Structure

```
Sources/
  RekordboxerCore/           # Core library (no UI dependencies)
    Models/
      RekordboxLibrary.swift  # Track, PlaylistNode, RekordboxLibrary, Tempo, PositionMark
    XML/
      XMLParser.swift         # Parse rekordbox XML into RekordboxLibrary
      XMLWriter.swift         # Write RekordboxLibrary back to XML
    Sync/
      FolderScanner.swift     # Recursively scan filesystem for audio files
      SyncEngine.swift        # Diff calculation and library updates
      TrackIDMap.swift         # Stable track ID assignment across syncs
      USBSync.swift            # Incremental USB file synchronization
    AppState.swift            # Settings persistence (JSON)
  Rekordboxer/                # SwiftUI application
    RekordboxerApp.swift      # App entry point
    Views/
      ContentView.swift       # NavigationSplitView with sidebar
      SyncView.swift          # Library sync UI with folder tree
      USBSyncView.swift       # USB sync UI with playlist selection
      SettingsView.swift      # Source folder and XML path configuration
    ViewModels/
      SyncViewModel.swift     # Library sync state and logic
      USBSyncViewModel.swift  # USB sync state and logic
Tests/
  RekordboxerCoreTests/       # 37 tests covering all core logic
Resources/
  AppIcon.svg                 # Source artwork
  AppIcon.icns                # Compiled macOS icon
scripts/
  bundle.sh                   # Build and package .app bundle
```

### Data Models

**`RekordboxLibrary`** holds the full library state: a dictionary of `Track` objects keyed by track ID, and a `PlaylistNode` tree representing the folder/playlist hierarchy.

**`Track`** stores all rekordbox metadata: name, artist, album, genre, BPM, key, rating, cue points (`PositionMark`), beatgrid (`Tempo`), and a `rawAttributes` dictionary that preserves any XML attributes rekordbox writes that Rekordboxer doesn't explicitly model. This means analysis data, waveform info, and future rekordbox fields survive round-trips through Rekordboxer.

**`PlaylistNode`** is a recursive tree where each node is either a folder (contains children) or a playlist (contains track IDs). This maps directly to rekordbox's `NODE` XML elements.

**`ScannedFolder`** mirrors the filesystem structure: each folder has direct `files` (audio files) and `children` (subfolders). The `allFiles` computed property recursively flattens the tree.

### Library Sync Pipeline

The sync flow has four stages:

1. **Scan** (`FolderScanner.scan`): Walks the source folder recursively, collecting audio files (mp3, wav, flac, aiff, aac, m4a, ogg, alac) into a `ScannedFolder` tree. Empty folders are omitted.

2. **Diff** (`SyncEngine.diff`): Compares the scanned files against the existing library. Produces a `SyncDiff` containing new tracks (files not in library), removed tracks (library tracks not on disk), and an unchanged count.

3. **User Review**: The UI displays the folder tree with checkboxes. Users can uncheck folders to exclude them and confirm which removed tracks to delete. On subsequent scans, `preselectFolders` reads the existing library to determine which folders were previously included — folders with at least one track already in the library are checked; others are left unchecked.

4. **Apply** (`SyncEngine.apply`): Removes confirmed tracks, adds new tracks from selected folders, and rebuilds the playlist tree. Each subfolder becomes a playlist. When a folder has both direct files and subfolders, the direct files get a playlist named after the folder (prefixed with `_` if a subfolder has the same name to avoid collisions). Track IDs are assigned via `TrackIDMap` which persists the mapping to disk, ensuring tracks keep stable IDs across syncs.

The XML is then written by `RekordboxXMLWriter`, which reconstructs the full rekordbox XML format including the `DJ_PLAYLISTS` root, `PRODUCT` info, `COLLECTION` of tracks, and `PLAYLISTS` tree.

### USB Sync Pipeline

USB sync assumes rekordbox has already exported tracks to a USB stick. Rekordboxer's job is to update files that have changed on disk (e.g. re-encoded or re-tagged files in a Dropbox folder) without re-exporting through rekordbox, which would lose cue points and analysis data.

1. **Plan** (`USBSync.plan`): Indexes all files on the USB stick by filename. For each track in the selected playlists, finds the matching file on USB. Compares file size and modification date against a manifest (`.rekordboxer_manifest.json` stored on the USB root). Files that differ are queued for copy; unchanged files are skipped; files not on USB are ignored (they need to be exported from rekordbox first).

2. **Execute** (`USBSync.execute`): Copies each changed file from source to its existing location on USB, preserving rekordbox's directory structure (`Contents/Artist/Album/`). Updates the manifest for next sync.

### Settings

`AppSettings` stores two paths as JSON in `~/Library/Application Support/Rekordboxer/settings.json`:
- `sourceFolderPath`: the root music folder to scan
- `xmlFilePath`: where to read/write the rekordbox XML

`TrackIDMap` is stored alongside at `~/Library/Application Support/Rekordboxer/track_id_map.json`. It maps file paths to integer track IDs so that tracks maintain stable identifiers even when the library is rebuilt from scratch.

## Tests

```bash
swift test
```

The test suite (37 tests) covers:

- **Model tests**: Rating conversion, position mark types, location encoding, playlist node types
- **XML round-trip tests**: Parse fixture XML, write it back, verify all data preserved
- **Folder scanner tests**: Audio file detection, non-audio filtering, nested scanning, metadata capture
- **Sync engine tests**: New/removed/unchanged detection, selective removal, nested playlist building, name collision handling, track ID stability
- **USB sync tests**: Skip-unchanged logic, change detection, in-place overwrite, selective playlist sync
- **Integration tests**: Full end-to-end workflow (scan → diff → apply → write → re-read → re-scan)
