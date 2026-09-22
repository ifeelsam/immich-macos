# Changelog

All notable changes to Immich Photos for macOS will be documented in this file.

## [v0.1.0] — 2026-09-22

### 🎉 Initial Release

The first public build of **Immich Photos** — a native macOS client for your self-hosted [Immich](https://immich.app) server, designed around the familiar Apple Photos experience.

### Features

#### Library & Browsing
- **Paged lazy-loading grid** — loads photos on demand, never fetches the entire timeline at once
- **Multiple views** — Library, Favorites, Videos, and Archived collections
- **Album support** — browse server albums, create new albums, add selected photos to existing albums
- **Adaptive grid sizing** — zoom in/out controls to adjust thumbnail size
- **"All Photos" collection picker** — quick-switch between library views from the toolbar

#### Photo Detail
- **Native detail view** — full-resolution preview with smooth rendition loading
- **Video playback** — stream videos directly via AVPlayer
- **Photo actions** — favorite, archive, rotate, share, and view EXIF info

#### People & Places
- **People browser** — browse recognized faces from your Immich server
- **Places map** — interactive map view of geotagged photos

#### Import & Management
- **Upload photos/videos** — import local files directly to your Immich server
- **Bulk selection** — select multiple photos for batch operations
- **Delete** — move items to Immich trash with server retention settings
- **Download originals** — save full-resolution copies locally

#### Apple Photos-Style Toolbar
- **Clean header** — route title with date subtitle (e.g. "Library / 25 Apr 2026")
- **Integrated search** — native toolbar search to filter loaded photos by filename or location
- **Toolbar controls** — zoom, view options, and quick actions in a familiar layout

#### Security & Connectivity
- **Keychain storage** — API keys stored securely in macOS Keychain
- **HTTP/LAN support** — works with self-hosted servers on private networks
- **Locked photos** — dedicated screen that opens Immich for secure PIN unlock (never stores PINs)

### Requirements
- macOS 14.0 (Sonoma) or later
- Immich server v1.135+
- API key with minimum permissions: `album.read`, `asset.read`, `asset.view`, `asset.download`

[v0.1.0]: https://github.com/ifeelsam/immich-macos/releases/tag/v0.1.0
