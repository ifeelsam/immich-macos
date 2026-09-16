# Immich Photos for macOS

Immich Photos is a native SwiftUI gallery for an Immich server, shaped around the
familiar macOS Photos workflow rather than a Finder integration.

## Included now

- Paged, lazy, month-grouped library grid that does not load the entire timeline.
- Library, Favorites, Videos, Archived, and server Album views.
- Native photo detail sheet with preview rendition loading and AVPlayer video streaming.
- Import photos/videos to Immich, download originals, favorite, archive, delete, create albums, and add selected assets to albums.
- Secure API-key storage in macOS Keychain; server address is stored separately in UserDefaults.
- Clear empty, loading, error, and destructive-action confirmation states.

The API layer follows the supplied desktop reference's Immich v1.135+ contract:
`POST /search/metadata`, thumbnail `preview`/`thumbnail` renditions, and the
current asset/album mutation endpoints.

## Build

```sh
xcodegen generate
xcodebuild -project ImmichPhotos.xcodeproj -scheme ImmichPhotos \
  -destination 'platform=macOS' -derivedDataPath /tmp/immich-photos-derived \
  build CODE_SIGNING_ALLOWED=NO
```

For running from Xcode, assign your signing team to the `ImmichPhotos` target.
The app targets macOS 14 or later. It permits HTTP/private-LAN servers in its
development Info.plist, matching the reference project's self-hosted use case.

## API-key permissions

Minimum browsing permissions: `album.read`, `asset.read`, `asset.view`, and
`asset.download`. Add `asset.create`, `asset.update`, `album.create`, and
`asset.delete` for the corresponding import and editing controls.

## Next product slices

People/Places, map browsing, richer metadata editing, background transfer queues,
offline caching, and non-destructive editing are deliberately separate additions.
They require their own server-permission and failure/retry policies rather than
being simulated in the UI.
