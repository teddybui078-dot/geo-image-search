# CONTRACT.md

The locked interface between geo-image-search's features: shared types, the database schema, and the protocols every feature builds against. This exists so features can be built in parallel git worktrees without blocking on each other — build against the shapes defined here, not against another feature's actual implementation.

If you're an agent starting work in a worktree: **read this file before writing code.** If your feature needs a shared type to change, see "Changing the contract" at the bottom before you change it — a change here can break every other worktree building against it.

Feature areas map 1:1 to `TODOS.md`'s Build Breakdown and to suggested branch names:

| Feature area | Branch name | Status | Owns |
|---|---|---|---|
| Photo/iCloud Extraction | `photo-icloud-extraction` | Not started | Produces `PhotoAsset` records, writes through `PhotoStore` |
| Database Structure | `database-structure` | **✅ Merged (PR #1)** | Implements `PhotoStore` and `PhotoQuery`, owns the SQL schema |
| 3D Interactive Map | `add-3dmap` | Not started | The `WebViewBridge` message protocol, globe rendering |
| Q&A AI Agent | `q-and-a-ai-agent` | In progress | Agent tool schemas, calls `PhotoQuery`, the `GlobeUpdating` protocol |
| Embedding Pipeline | `embedding-pipeline` | Not started | Produces `EmbeddingRecord`, writes through `PhotoStore` |
| Error Handling | `error-handling` | **✅ Merged (PR #2)** | `AppError`, `RetryPolicy`, `ErrorReporting`, `RetryExecutor` — everyone else imports this |

`database-structure` and `error-handling` are both real now — `PhotoStore`/`PhotoQuery` against actual SQLite in `Sources/GeoImageSearch/Storage/`, and `AppError`/`RetryPolicy`/`ErrorReporting`/`RetryExecutor` in `Sources/GeoImageSearch/Common/`. Every other feature should build against the real thing, not a mock or a local placeholder, from here on.

## Core types

```swift
struct PhotoAsset: Identifiable, Codable {
    let id: String              // PHAsset.localIdentifier — stable across relaunches
    let latitude: Double?       // nil if the photo has no GPS data
    let longitude: Double?
    let capturedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?        // soft delete — nil means active
    let placeName: String?      // cached reverse-geocode result, nil until geocoded
    let isLivePhoto: Bool       // true = indexed as photo, motion component ignored (v1)
}

struct EmbeddingRecord: Codable {
    let assetID: String         // PhotoAsset.id
    let vector: [Float]         // dimension TBD — see "Open dependency" below
    let modelVersion: String    // e.g. "mobileclip-s0-v1" — lets you re-embed if the model changes
    let generatedAt: Date
}

struct TripCluster: Codable {
    let id: String
    let assetIDs: [String]
    let startDate: Date
    let endDate: Date
    let centroidLatitude: Double
    let centroidLongitude: Double
    let placeName: String?
}
```

**Open dependency, resolved:** `EmbeddingRecord.vector`'s dimension depends on the CoreML model choice (TODOS.md item 5, still not decided). Rather than guessing a number, `database-structure` made the dimension a runtime parameter to `Schema.create(in:embeddingDimension:)` — so `embedding-pipeline` passes its actual model's dimension when it sets up storage, no schema coordination or migration needed once the model is picked. This is the pattern to reach for generally when one feature's shape depends on another's not-yet-made decision: parameterize instead of guessing a placeholder value.

## Database schema (owned by `database-structure`, written to by `photo-icloud-extraction` and `embedding-pipeline`)

```sql
CREATE TABLE IF NOT EXISTS photos (
    id TEXT PRIMARY KEY,               -- PHAsset.localIdentifier
    latitude REAL,                     -- NULL if no GPS
    longitude REAL,                    -- NULL if no GPS
    captured_at INTEGER NOT NULL,      -- unix timestamp
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,                -- NULL if not deleted
    place_name TEXT,
    is_live_photo INTEGER NOT NULL DEFAULT 0
);

-- R-Tree requires an INTEGER rowid, not photos.id (TEXT). Use photos.rowid
-- (SQLite's implicit integer rowid, since `photos` is not WITHOUT ROWID) and
-- join photos_rtree.id = photos.rowid. This is the standard R-Tree gotcha —
-- getting it wrong is the most likely place database-structure loses time.
CREATE VIRTUAL TABLE IF NOT EXISTS photos_rtree USING rtree(
    id,
    min_lat, max_lat,
    min_lon, max_lon
);

-- Dimension is a runtime parameter (Schema.photoEmbeddingsSQL(dimension:)),
-- not hardcoded — resolves the "open dependency" below without database-structure
-- needing to guess embedding-pipeline's eventual CoreML model choice.
CREATE VIRTUAL TABLE IF NOT EXISTS photo_embeddings USING vec0(
    asset_id TEXT PRIMARY KEY,
    embedding FLOAT[?]
);

-- Additive, beyond this doc's original 3-table schema: vec0's photo_embeddings
-- table only has room for the id + vector (2 columns). EmbeddingRecord also
-- carries modelVersion/generatedAt, which live here instead.
CREATE TABLE IF NOT EXISTS photo_embedding_meta (
    asset_id TEXT PRIMARY KEY,
    model_version TEXT NOT NULL,
    generated_at INTEGER NOT NULL
);
```

## Write interface (implemented by `database-structure`; called by `photo-icloud-extraction` and `embedding-pipeline`)

```swift
protocol PhotoStore {
    func upsert(_ assets: [PhotoAsset]) async throws
    func markDeleted(ids: [String]) async throws
    func upsertEmbedding(_ record: EmbeddingRecord) async throws
}
```

## Read interface (implemented by `database-structure`; called by `q-and-a-ai-agent` and `add-3dmap`)

```swift
protocol PhotoQuery {
    func byLocation(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PhotoAsset]
    func byDateRange(start: Date, end: Date) async throws -> [PhotoAsset]
    func bySimilarity(embedding: [Float], limit: Int) async throws -> [PhotoAsset]
    func clusterTrips(minStopDuration: TimeInterval, maxTravelGap: TimeInterval) async throws -> [TripCluster]
    func allActivePhotosWithLocation() async throws -> [PhotoAsset]  // feeds the globe's initial pin load
}
```

`add-3dmap` only needs `allActivePhotosWithLocation()` to build the initial globe view — it does not need the other three methods, and does not need to wait on `q-and-a-ai-agent`'s work.

## Native \<-\> globe bridge (owned by `add-3dmap`)

`WKScriptMessageHandler` JSON messages, one message type per line, native \<-\> JS via `WKWebView`.

**Native -> JS:**
```json
{ "type": "setPins", "pins": [{ "id": "string", "lat": 0.0, "lon": 0.0 }] }
{ "type": "focusRegion", "bounds": { "minLat": 0.0, "maxLat": 0.0, "minLon": 0.0, "maxLon": 0.0 } }
{ "type": "highlightAssets", "ids": ["string"] }
```

**JS -> Native:**
```json
{ "type": "webviewReady" }
{ "type": "webviewError", "message": "string" }
{ "type": "pinSelected", "id": "string" }
```

`webviewError` is what backs the native fallback UI decided in `/plan-eng-review` (`WKNavigationDelegate` + a native SwiftUI error state) — any JS-side failure that isn't a clean load failure should still emit this so the fallback can catch it.

## Globe update protocol (owned by `q-and-a-ai-agent`, implemented by `add-3dmap`)

`add-3dmap` hasn't landed yet — `WebViewBridge` is still an empty stub — so `q-and-a-ai-agent` defined a small Swift protocol the chat UI codes against today, backed by a logging no-op (`LoggingGlobeUpdater`). This is additive (a new protocol, not a change to an existing locked type), so it's landing without cross-branch coordination per "Changing the contract" below. When `add-3dmap` is built, its real `WebViewBridge` should conform `GlobeUpdating` to the native→JS bridge messages above (`setPins`/`focusRegion`/`highlightAssets` map 1:1 to the `setPins`/`focusRegion`/`highlightAssets` JSON messages) — the chat UI call site doesn't change.

```swift
protocol GlobeUpdating: Sendable {
    func setPins(_ pins: [GlobePin]) async
    func focusRegion(_ bounds: GlobeBounds) async
    func highlightAssets(ids: [String]) async
}

struct GlobePin: Sendable, Equatable {
    let id: String
    let lat: Double
    let lon: Double
}

struct GlobeBounds: Sendable, Equatable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}
```

## Agent tool schemas (owned by `q-and-a-ai-agent`)

OpenAI function-calling format. Four tools, matching `PhotoQuery` 1:1 (`allActivePhotosWithLocation` has no tool — it's map-only).

```json
[
  {
    "name": "query_by_location",
    "parameters": {
      "type": "object",
      "properties": {
        "placeName": { "type": "string", "description": "e.g. 'Athens', 'Greece' — resolved to coordinates via the cached place_name index before falling back to live geocoding" },
        "radiusKm": { "type": "number", "default": 50 }
      },
      "required": ["placeName"]
    }
  },
  {
    "name": "query_by_date_range",
    "parameters": {
      "type": "object",
      "properties": {
        "start": { "type": "string", "format": "date" },
        "end": { "type": "string", "format": "date" }
      },
      "required": ["start", "end"]
    }
  },
  {
    "name": "semantic_search",
    "parameters": {
      "type": "object",
      "properties": {
        "query": { "type": "string", "description": "free-text description, e.g. 'sunset on a beach'" },
        "limit": { "type": "integer", "default": 20 }
      },
      "required": ["query"]
    }
  },
  {
    "name": "cluster_trips",
    "parameters": {
      "type": "object",
      "properties": {
        "placeName": { "type": "string", "description": "optional filter, e.g. 'Greece'" }
      }
    }
  }
]
```

**Open dependency:** these schemas are the working draft from TODOS.md item 1 (agent tool schemas + eval hardening) — not finalized. Whoever builds `q-and-a-ai-agent` owns refining them; changing a tool's parameter shape doesn't affect other features since nothing else consumes these directly (they wrap `PhotoQuery`, which is the actual cross-feature contract).

## Error handling (owned by `error-handling`; imported by every other feature)

```swift
enum AppError: Error {
    case photosPermissionDenied
    case photosFetchFailed(underlying: Error)
    case geocodingRateLimited
    case geocodingFailed(underlying: Error)
    case llmTimeout
    case llmRateLimited
    case llmInvalidAPIKey
    case embeddingGenerationFailed(assetID: String, underlying: Error)
    case webviewLoadFailed
}

protocol RetryPolicy {
    var maxAttempts: Int { get }
    func isRetryable(_ error: AppError) -> Bool
    func backoff(forAttempt attempt: Int) -> TimeInterval
}

protocol ErrorReporting {
    func report(_ error: AppError, context: String)
}

// Shared retry loop so a boundary drives its own RetryPolicy without
// hand-rolling attempt-counting/backoff. Delay is injectable for tests.
enum RetryExecutor {
    static func run<Value>(
        policy: any RetryPolicy,
        delaying: any RetryDelaying = TaskSleepDelaying(),
        operation: () async throws -> Value
    ) async throws -> Value
}

protocol RetryDelaying {
    func delay(_ duration: TimeInterval) async throws
}
```

Per `/plan-eng-review`: one shared `ErrorReporting` surface (consistent UI presentation), but each boundary (PhotosKit/iCloud, CLGeocoder, OpenAI) gets its own `RetryPolicy` instance — different failure semantics, not one-size-fits-all. `RetryExecutor` is additive on top of that split: it's the one shared loop every boundary runs its own policy through, so retry attempt-counting/backoff logic isn't duplicated per boundary.

## Parallelization guide

**Unblocked now that `database-structure` and `error-handling` are both merged:** `photo-icloud-extraction`, `add-3dmap`, and `embedding-pipeline` should build against the real `PhotoStore`/`PhotoQuery` (`Sources/GeoImageSearch/Storage/`) and the real `AppError`/`RetryPolicy`/`ErrorReporting`/`RetryExecutor` (`Sources/GeoImageSearch/Common/`) directly — no more mocking or local placeholder error types needed for those. Any worktree branched before PR #2 merged should merge `main` in before continuing (a stale worktree's `Common/` files are still empty stubs from before `error-handling` landed).

**`q-and-a-ai-agent`:** built against the real `PhotoQuery` and the real error-handling types. Its `semantic_search` tool specifically needs `embedding-pipeline`'s work to return meaningful results (real embeddings have to exist in `photo_embeddings`) — it's stubbed (no results, explanatory message) until embeddings exist; the other three tools are built and tested against the real `SQLitePhotoQuery` now.

## Changing the contract

If your feature needs a type or protocol here to change: update this file in a small, dedicated commit on `main` (or flag it to the other worktrees) before you change your own branch's usage of it. Don't let a shared type drift silently in one worktree — that's the exact merge-hell scenario this file exists to prevent. If a change is additive (a new optional field, a new method with a default), it's usually safe to land without coordination. If it's a breaking change (renaming/removing a field or method), coordinate first.
