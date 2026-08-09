# TODOS

## Build Breakdown

What actually needs to be built, organized by subsystem. Cross-references DESIGN.md's Next Steps and the deferred items below.

### 1. Photo/iCloud Extraction
- PhotosKit permission request flow (native Swift, `PHPhotoLibrary.requestAuthorization`)
- Asset enumeration: list `PHAsset`s, pull GPS (`PHAsset.location`) + timestamp — no manual EXIF parsing needed
- Asset identity model: `PHAsset.localIdentifier` as the stable ID, `deleted_at`/`updated_at` tracking so relaunches can diff the library
- Relaunch sync strategy: one-shot full ingest vs. incremental diff — decide alongside the identity model, same decision
- Reverse geocoding: CLGeocoder, ~1km bucketed + cached + throttled (lat/lon → place name)
- Live Photos handled as photos (image component only, motion ignored)
- iCloud-only assets: pull metadata/location without forcing a full-res download; defer full-res fetch to on-demand thumbnailing
- Validate real GPS coverage % against your own library early (see item 6 below)
- "Selected Photos" limited-access handling — currently deferred, flagged as a family-usability risk (see item 6 below)

### 2. Database Structure
- SQLite schema for photo metadata, keyed by `PHAsset.localIdentifier`
- SQLite **R-Tree** virtual table for geospatial (lat/lon/radius) range queries — distinct from sqlite-vec, easy to conflate the two
- **sqlite-vec** table for embedding similarity (backs `semantic_search`)
- Schema needs to carry: GPS presence/absence (no-GPS photos indexed but excluded from globe pins, not from date/semantic search), cached geocoded place name, soft-delete/updated timestamps

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
- One shared error-reporting surface across PhotosKit, CLGeocoder, and LLM calls (consistent UI presentation)
- Per-boundary retry policy for each (different failure semantics — PhotosKit/iCloud, geocoding rate limits, LLM timeouts/rate limits all behave differently)

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

**What:** Pick the specific MobileCLIP variant (embedding dimension, tokenizer/text-tower availability, license) before the sqlite-vec schema is finalized — the vector column width depends on this choice.

**Why:** Not a detail — picking it after the schema exists means a migration.

**Pros:** Avoids a schema migration later; picking early means the sqlite-vec table is right the first time.

**Cons:** Requires research into MobileCLIP variants (and any licensing terms) before Next Step 4 can fully start.

**Context:** Next Step 4 prerequisite — research and pick the specific model variant before writing the sqlite-vec schema, not after.

**Depends on / blocked by:** None — can be researched independently, but must land before Next Step 4's schema work.

## 6. Real GPS coverage + limited-access risk

**What:** Measure how much of the actual photo library has usable GPS data (screenshots, DSLR imports, and old scans often lack it) early. Reconsider whether "Selected Photos" limited-access handling (currently deferred in DESIGN.md's Constraints) should move up given it directly affects family usability.

**Why:** The app's value could be undercut if only a minority of assets are mappable, and macOS users can grant limited Photos access somewhat easily — if v1 silently misses photos in that case, results look wrong without explanation.

**Pros:** Cheap to check as soon as PhotosKit access is granted (Next Step 1) — costly to discover only after building the rest of the pipeline around an assumption of good GPS coverage.

**Cons:** May reveal a real constraint (low GPS coverage) that has no easy fix beyond setting expectations.

**Context:** Check real GPS coverage % against your own library as part of Next Step 1 validation. Treat limited-access handling as a pre-family-use requirement, not something fully deferred.

**Depends on / blocked by:** Next Step 1 (PhotosKit permission flow) must exist to measure this.
