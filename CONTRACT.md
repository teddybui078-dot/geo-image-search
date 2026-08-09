# CONTRACT.md

The locked interface between geo-image-search's features: shared types, the database schema, and the protocols every feature builds against. This exists so features can be built in parallel git worktrees without blocking on each other — build against the shapes defined here, not against another feature's actual implementation.

If you're an agent starting work in a worktree: **read this file before writing code.** If your feature needs a shared type to change, see "Changing the contract" at the bottom before you change it — a change here can break every other worktree building against it.

Feature areas map 1:1 to `TODOS.md`'s Build Breakdown and to suggested branch names:

| Feature area | Branch name | Owns |
|---|---|---|
| Photo/iCloud Extraction | `photo-icloud-extraction` | Produces `PhotoAsset` records, writes through `PhotoStore` |
| Database Structure | `database-structure` | Implements `PhotoStore` and `PhotoQuery`, owns the SQL schema |
| 3D Interactive Map | `add-3dmap` | The `WebViewBridge` message protocol, globe rendering |
| Q&A AI Agent | `q-and-a-ai-agent` | Agent tool schemas, calls `PhotoQuery` |
| Embedding Pipeline | `embedding-pipeline` | Produces `EmbeddingRecord`, writes through `PhotoStore` |
| Error Handling | `error-handling` | `AppError`, `RetryPolicy`, `ErrorReporting` — everyone else imports this |

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

**Open dependency:** `EmbeddingRecord.vector`'s dimension depends on the CoreML model choice (TODOS.md item 5, not yet decided). Database Structure's `photo_embeddings` schema can't be finalized until Embedding Pipeline picks a model. This is exactly the "feature A needs feature B's output" case — coordinate before either merges, don't let Database Structure guess a dimension and Embedding Pipeline diverge from it.

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

-- Dimension is a placeholder — see "Open dependency" above.
CREATE VIRTUAL TABLE IF NOT EXISTS photo_embeddings USING vec0(
    asset_id TEXT PRIMARY KEY,
    embedding FLOAT[512]
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
```

Per `/plan-eng-review`: one shared `ErrorReporting` surface (consistent UI presentation), but each boundary (PhotosKit/iCloud, CLGeocoder, OpenAI) gets its own `RetryPolicy` instance — different failure semantics, not one-size-fits-all.

## Parallelization guide

**Build first, or at least merge first:** `error-handling`. Every other feature imports `AppError`/`RetryPolicy`/`ErrorReporting`. It's small and has no dependencies on anything else in this doc — cheapest to get real and merged early so nobody's stubbing it out themselves.

**Fully parallel from day one, against this contract:** `photo-icloud-extraction`, `database-structure`, `add-3dmap`, and `embedding-pipeline` can all start immediately. Each builds against the types and protocols above; none needs another feature's actual implementation. Use an in-memory mock of `PhotoStore`/`PhotoQuery` where you need one to test against.

**Also parallel, but real correctness waits on `database-structure`:** `q-and-a-ai-agent` can be fully written and unit-tested against a mock `PhotoQuery` in parallel with everyone else. Whether it actually answers questions correctly can't be verified until `database-structure`'s real implementation exists to query against.

**Suggested merge order:** `error-handling` -> `database-structure` -> everything else, in any order. `database-structure` is the one feature the others integrate against for real (not just against its protocol), so landing it early de-risks the rest.

## Changing the contract

If your feature needs a type or protocol here to change: update this file in a small, dedicated commit on `main` (or flag it to the other worktrees) before you change your own branch's usage of it. Don't let a shared type drift silently in one worktree — that's the exact merge-hell scenario this file exists to prevent. If a change is additive (a new optional field, a new method with a default), it's usually safe to land without coordination. If it's a breaking change (renaming/removing a field or method), coordinate first.
