# Immich Photos for macOS

<p align="center">
  <strong>A native macOS client for your self-hosted Immich server</strong><br>
  Built with SwiftUI · Shaped around the Apple Photos experience
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/swift-5-orange?style=flat-square" alt="Swift 5">
  <img src="https://img.shields.io/badge/immich-v1.135%2B-blueviolet?style=flat-square" alt="Immich v1.135+">
  <img src="https://img.shields.io/github/v/release/ifeelsam/immich-macos?style=flat-square&label=release" alt="Release">
</p>

---

## Features

- 📸 **Library browsing** — paged, lazy-loading photo grid with adaptive sizing
- 🗂️ **Collections** — Library, Favorites, Videos, Archived, and Album views
- 🔍 **Search** — filter loaded photos by filename or location
- 🖼️ **Photo detail** — full-resolution preview with EXIF info and AVPlayer video streaming
- 👤 **People** — browse recognized faces from your server
- 🗺️ **Places** — interactive map of geotagged photos
- ⬆️ **Import** — upload photos and videos directly to Immich
- ✏️ **Management** — favorite, archive, delete, create albums, bulk select
- 🔐 **Secure** — API keys in macOS Keychain, never stores locked-folder PINs
- 🌐 **Self-hosted friendly** — works with HTTP/private LAN servers

## Build

```sh
# Generate the Xcode project
xcodegen generate

# Build from command line
xcodebuild -project ImmichPhotos.xcodeproj -scheme ImmichPhotos \
  -destination 'platform=macOS' build

# Or open in Xcode and assign your signing team
open ImmichPhotos.xcodeproj
```

Requires **macOS 14 (Sonoma)** or later and **Xcode 15+**.

## API Key Permissions

| Scope | Required for |
|-------|-------------|
| `album.read`, `asset.read`, `asset.view`, `asset.download` | Browsing (minimum) |
| `asset.create` | Uploading photos |
| `asset.update` | Favorite, archive, edit |
| `asset.delete` | Delete photos |
| `album.create` | Create albums |

## Locked Photos

Immich returns HTTP 401 for locked assets requested with an API key. The app shows a dedicated Locked screen and opens Immich in your browser for secure PIN unlock — it never asks for or stores a PIN.

## Roadmap

- Background transfer queues
- Offline caching
- Non-destructive editing
- Richer metadata editing
- Shared albums

## License

See [LICENSE](LICENSE) for details.
