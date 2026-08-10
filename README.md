# Photo/iCloud Extraction

Real macOS Photos/iCloud permission access via PhotosKit — no upload, no folder picker. This is the feature that makes the app's permission model real instead of simulated.

**Status: not started — skeleton only.**

## What this covers

- `PHPhotoLibrary.requestAuthorization` permission flow
- Asset enumeration: `PHAsset.location` (GPS) + timestamp, no manual EXIF parsing needed
- Asset identity model: `PHAsset.localIdentifier` as the stable ID, with `deleted_at`/`updated_at` tracking so relaunches can diff the library against a chosen sync strategy (one-shot full ingest vs. incremental diff)
- Reverse geocoding via CLGeocoder — ~1km bucketed, cached, and throttled, since Apple's geocoder isn't built for high-volume bulk calls
- Live Photos indexed as photos only, motion component ignored (v1)
- iCloud-only assets: metadata/location pulled without forcing a full-resolution download

Writes everything through `PhotoStore` (implemented by `database-structure`, merged). See [CONTRACT.md](CONTRACT.md) for the exact `PhotoAsset` shape and write interface, and [TODOS.md](TODOS.md) item 6 for the GPS-coverage-validation and limited-Photos-access follow-ups this feature is expected to surface.
