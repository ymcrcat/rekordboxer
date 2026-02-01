# Rekordboxer

A macOS app for syncing a local music folder into rekordbox playlists via the rekordbox XML interchange format, and efficiently updating audio files on USB sticks.

## Features

- **Library Sync**: Point Rekordboxer at a music folder (e.g. synced via Dropbox) and it generates a rekordbox XML file where each subfolder becomes a playlist. New tracks are added automatically; removed tracks require your confirmation before deletion. Existing track data (cue points, beatgrids, BPM analysis) is preserved.

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

## Tests

```bash
swift test
```
