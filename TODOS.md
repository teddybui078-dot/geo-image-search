# TODOS

## Build Breakdown

What actually needs to be built, organized by subsystem. Cross-references DESIGN.md's Next Steps and the deferred items below.

### 1. Photo/iCloud Extraction
**Done (`photo-icloud-extraction` branch):** built against the real `PhotoStore`/`PhotoQuery` and `AppError`/`RetryPolicy`/`ErrorReporting` from the now-merged `database-structure` and `error-handling` branches.
- ~~PhotosKit permission request flow (native Swift, `PHPhotoLibrary.requestAuthorization`)~~ **Done** — `PhotosPermissionManager`/`PhotosAccessStatus`, behind a `PhotosAuthorizing` seam for testing.
- ~~Asset enumeration: list `PHAsset`s, pull GPS (`PHAsset.location`) + timestamp — no manual EXIF parsing needed~~ **Done** — `PHPhotoLibraryFetcher`, mapped through `PhotoLibraryAsset`/`PhotoAssetSnapshot`.
- ~~Asset identity model: `PHAsset.localIdentifier` as the stable ID, `deleted_at`/`updated_at` tracking so relaunches can diff the library~~ **Done** — no separate identity type needed; the fields live on `PhotoAsset` itself.
- ~~Relaunch sync strategy: one-shot full ingest vs. incremental diff~~ **Done** — full (cheap, metadata-only) enumeration every launch, diffed client-side via `SyncPlanner` against the new `PhotoQuery.allActiveIdentifiers()`, using `PHAsset.modificationDate` as the change signal. First launch falls out of the same path for free. Full reasoning: CONTRACT.md's "Relaunch sync strategy".
- ~~Reverse geocoding: CLGeocoder, ~1km bucketed + cached + throttled (lat/lon → place name)~~ **Done** — `ReverseGeocoder`/`GeoBucket`, retried via the shared `RetryExecutor` + `GeocodingRetryPolicy`. Cache is process-lifetime only (see CONTRACT.md/code comments for why that's sufficient).
- ~~Live Photos handled as photos (image component only, motion ignored)~~ **Done** — `PhotoAssetSnapshot.isLivePhoto` via `mediaSubtypes.contains(.photoLive)`.
- iCloud-only assets: pull metadata/location without forcing a full-res download — **already true by construction**: `PHAsset` metadata (location/dates) is locally available regardless of iCloud-only status; this feature never touches image bytes, so there was no full-res fetch to defer.
- ~~Validate real GPS coverage % against your own library early~~ **Mechanism done, real number not yet measured** — `GPSCoverageReport` is computed on every sync and surfaced in the app's "Sync Photo Library" button. Couldn't be run in this build environment: `swift build`/`swift test` don't carry the Photos entitlement, only a full Xcode build does. Run it from Xcode against a real library to get the actual percentage.
- "Selected Photos" limited-access handling — **still a known gap, not solved.** `PhotosAccessStatus.isLimitedAccess`/`IngestResult.isLimitedAccess` detect and surface the state (the app shows a warning), but there's no prompt or explanation UI beyond that, per DESIGN.md's Constraints and item 6 below.

### 2. Database Structure
**Done (`database-structure` branch):** `PhotoStore`/`PhotoQuery` are implemented against real SQLite, matching CONTRACT.md's schema section.
- ~~SQLite schema for photo metadata, keyed by `PHAsset.localIdentifier`~~ **Done** — `photos` table keyed by `id` (TEXT), carries GPS presence/absence, cached place name, soft-delete/updated timestamps per CONTRACT.md.
- ~~SQLite **R-Tree** virtual table for geospatial (lat/lon/radius) range queries — distinct from sqlite-vec, easy to conflate the two~~ **Done** — `photos_rtree`, kept in sync on upsert/GPS-clear via the documented rowid lookup (CONTRACT.md's rowid gotcha), read side backed by a bounding-box prefilter (`GeoMath.boundingBox`) plus an exact haversine cutoff.
- ~~**sqlite-vec** table for embedding similarity (backs `semantic_search`)~~ **Done** — `photo_embeddings` (vec0), dimension parameterized at schema-creation time rather than hardcoded (see item 5 below), plus an additive `photo_embedding_meta` companion table for `EmbeddingRecord.modelVersion`/`.generatedAt` (no column for those in CONTRACT's literal 2-column DDL).
- ~~Schema needs to carry: GPS presence/absence (no-GPS photos indexed but excluded from globe pins, not from date/semantic search), cached geocoded place name, soft-delete/updated timestamps~~ **Done**, see above.

Apple's system `libsqlite3` disables `sqlite3_auto_extension`, so the standard sqlite-vec integration pattern doesn't work — SQLite and sqlite-vec are vendored as SPM C targets (`Sources/CSQLite3`, `Sources/CSQLiteVec`) built `SQLITE_CORE`-mode instead. 62 Swift Testing tests cover schema creation, R-Tree sync, the two-phase geo query, KNN similarity (including the sqlite-vec 4096 k-ceiling and soft-delete overfetch buffer), and trip clustering, all against in-memory/temp-file DBs seeded with fixture data (no real Photos data exists yet).

### 3. 3D Interactive Map
- ~~Globe library decision~~ **Resolved: OpenGlobus** — Apache-2.0, no ion account/token friction, lighter in the WKWebView, better fit for hand-coding a custom look. Tradeoff accepted: thinner docs, no built-in time-dynamic visualization for a future trip-recap/timeline feature.
- `WKWebView` host + `WKScriptMessageHandler` bridge (native → JS pin data, JS → native query dispatch)
- Native fallback UI if the webview fails to load or crashes (`WKNavigationDelegate`)
- Pin rendering from SQLite data
- LOD/clustering by zoom level, using the chosen library's built-in support — raw rendering performance at scale, distinct from visual burst/duplicate-photo clustering
- Hand-tweaked custom styling (color palette, custom pin/marker glyphs) — explicitly not the library's default look

### 4. Q&A AI Agent
- Shared `PhotoQuery` repository (`byLocation`, `byDateRange`, `bySimilarity`, `clusterTrips`) — one query layer, not four independent SQL builders
- ~~LLM provider choice~~ **Resolved: OpenAI API.**
- Keychain storage for the API key, plus key UX (validation, missing-key state, quota exhaustion — see item 3 below)
- Agent tool-calling loop over the four tools
- Explicit param schemas per tool (see item 1 below)
- `cluster_trips` definition: stop duration, travel-gap threshold, timezone handling (see item 2 below)
- Eval suite: fixed question → expected tool + params + result set (see item 1 below)
- Chat UI wired to the agent, updates the globe on response

### 5. Embedding Pipeline (cross-cutting — feeds Database Structure, consumed by Q&A AI Agent)
- CoreML embedding model selection (MobileCLIP variant — dimension, tokenizer, license) — see item 5 below, gates the sqlite-vec schema
- Background-queue, bounded-concurrency generation with visible progress and an optional date-range scope for first-run indexing

### 6. Error Handling (cross-cutting — spans Extraction, Database writes, and the Agent)
**Done (`error-handling` branch):** `AppError`/`RetryPolicy`/`ErrorReporting` are implemented against CONTRACT.md's locked shapes.
- ~~One shared error-reporting surface across PhotosKit, CLGeocoder, and LLM calls (consistent UI presentation)~~ **Done** — `ErrorReporter` (`Sources/GeoImageSearch/Common/ErrorReporter.swift`), backed by `os.Logger` through an injectable `ErrorLogSink` so call sites format every `AppError` the same way instead of ad hoc messages per boundary.
- ~~Per-boundary retry policy for each (different failure semantics — PhotosKit/iCloud, geocoding rate limits, LLM timeouts/rate limits all behave differently)~~ **Done** — `PhotosRetryPolicy`, `GeocodingRetryPolicy`, and `LLMRetryPolicy`, each with its own `maxAttempts`/backoff curve/retryability rules (e.g. `llmInvalidAPIKey` and `photosPermissionDenied` are explicitly not retryable). A shared `RetryExecutor` (injectable delay) runs any policy against an async operation so boundaries don't hand-roll their own retry loop.

Every other feature worktree (`photo-icloud-extraction`, `add-3dmap`, `embedding-pipeline`, `q-and-a-ai-agent`) should swap its local placeholder error type for the real `AppError`/`RetryPolicy`/`ErrorReporting` in `Sources/GeoImageSearch/Common/` once this branch merges.

---

## Deferred Items

Surfaced during `/plan-eng-review` (2026-08-09), sourced from the Codex outside-voice pass on `DESIGN.md`. None of these block Next Steps 1-2; each notes which later step it gates.

## 1. Agent tool schemas + eval hardening

**What:** Define explicit param schemas for all four agent tools (`query_by_location`, `query_by_date_range`, `semantic_search`, `cluster_trips`). Strengthen the eval set beyond "expected tool + params" to include expected result sets, ambiguous queries, no-result cases, and date-relative phrasing ("last summer").

**Why:** Routing to the right tool isn't the same as getting a correct answer. Without param schemas, the model can invent place names with no disambiguation logic.

**Pros:** Prevents silent wrong-answer bugs that a routing-only eval would miss; makes tool behavior predictable enough to actually trust the "correct answer" success criterion in DESIGN.md.

**Cons:** More upfront design work before Next Steps 5-6 can start; schemas may need revision once real usage patterns emerge.

**Context:** Directly extends the eval-suite decision already confirmed in this review's Test Review section (fixed question -> expected tool + params). Do this before writing the actual tool implementations, not after.

**Depends on / blocked by:** PhotoQuery repository (decided, Issue 3), eval suite scope (decided, Test Review).

## 2. cluster_trips scoping

**What:** Define what counts as a "trip" — minimum stop duration, travel-gap threshold, timezone handling, dense single-city days vs. multi-day trips, road trips/cruises with many short stops.

**Why:** Clustering quality depends entirely on these definitions being nailed down; left vague, this tool can become "a project inside the project."

**Pros:** Prevents cluster_trips from becoming an open-ended research problem once you're actually building it.

**Cons:** Hard to get these thresholds right without real data from your own library — premature to lock in exact numbers today.

**Context:** Next Steps 6 work (expanding the agent's tool surface). Scope this right before starting that step, using real ingested data to calibrate thresholds.

**Depends on / blocked by:** A working ingestion pipeline with real GPS+timestamp data (Next Steps 1-2).

## 3. LLM API key UX

**What:** Validation on entry, rotation, a clear missing-key state, quota-exhaustion handling, and whether an offline/no-agent mode exists when there's no key configured.

**Why:** Keychain storage (decided in Architecture review, Issue 2) covers where the key lives, not what the user experiences around it.

**Pros:** Avoids a confusing blank/broken state if the key is missing or invalid when the chat UI first ships.

**Cons:** Extra UI surface for a single-user personal tool where "you'll notice immediately" is a real, if less polished, alternative.

**Context:** Relevant once the chat UI is built in Next Step 5. At minimum needs a clear "no key configured" state before that step ships.

**Depends on / blocked by:** Keychain storage implementation (Issue 2, decided).

## 4. Privacy posture for LLM queries

**What:** Document what leaves the device when the agent runs — natural-language questions (which may reference trip/family/location details) are sent to a third-party LLM API. Once open-sourced, other users inherit the same tradeoff with their own API key.

**Why:** Currently undocumented. Becomes more relevant if tool outputs later include photo captions or other richer metadata.

**Pros:** Sets expectations for future contributors/users before open-sourcing; cheap to write now while the data flow is still simple (query text only, not photos).

**Cons:** Low urgency for personal-only use today.

**Context:** Pre-open-source documentation task — a short README/DESIGN.md note on what data leaves the device and why.

**Depends on / blocked by:** None — can be written any time before open-sourcing.

## 5. CoreML embedding model selection

**What:** Pick the specific MobileCLIP variant (embedding dimension, tokenizer/text-tower availability, license).

**Why:** Not a detail — the choice determines the embedding dimension `photo_embeddings` is created with.

**No longer schema-blocking:** the `database-structure` branch parameterized the sqlite-vec schema on `embeddingDimension` at creation time (`Schema.photoEmbeddingsSQL(dimension:)`) rather than hardcoding CONTRACT.md's `FLOAT[512]` placeholder, specifically so this choice wouldn't require a migration later. Picking the model is still a prerequisite for the embedding-pipeline worktree itself (and for `upsertEmbedding`'s dimension validation to mean anything against a real model), just no longer a hard blocker on the database schema landing.

**Pros:** Avoids a schema migration later; picking early means the sqlite-vec table is right the first time.

**Cons:** Requires research into MobileCLIP variants (and any licensing terms) before Next Step 4 can fully start.

**Context:** Next Step 4 prerequisite — research and pick the specific model variant before the embedding pipeline starts writing real vectors.

**Depends on / blocked by:** None — can be researched independently.

## 6. Real GPS coverage + limited-access risk

**What:** Measure how much of the actual photo library has usable GPS data (screenshots, DSLR imports, and old scans often lack it) early. Reconsider whether "Selected Photos" limited-access handling (currently deferred in DESIGN.md's Constraints) should move up given it directly affects family usability.

**Why:** The app's value could be undercut if only a minority of assets are mappable, and macOS users can grant limited Photos access somewhat easily — if v1 silently misses photos in that case, results look wrong without explanation.

**Pros:** Cheap to check as soon as PhotosKit access is granted (Next Step 1) — costly to discover only after building the rest of the pipeline around an assumption of good GPS coverage.

**Cons:** May reveal a real constraint (low GPS coverage) that has no easy fix beyond setting expectations.

**Context:** Check real GPS coverage % against your own library as part of Next Step 1 validation. Treat limited-access handling as a pre-family-use requirement, not something fully deferred.

**Depends on / blocked by:** Next Step 1 (PhotosKit permission flow) must exist to measure this.

**Status (photo-icloud-extraction branch):** the measurement mechanism exists (`GPSCoverageReport`, surfaced via the app's "Sync Photo Library" button) but hasn't been run against a real library yet — this build environment can't grant Photos access (`swift build`/`swift test` lack the entitlement a full Xcode build applies). Limited-access is detected and surfaced (`PhotosAccessStatus.isLimitedAccess` → a warning in the synced result) but still has no dedicated prompt/explanation UI — remains a real gap, not a solved one. Both need a real Mac with a real library and an Xcode build to close out.
