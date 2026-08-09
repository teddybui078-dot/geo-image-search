# TODOS

Deferred items surfaced during `/plan-eng-review` (2026-08-09), sourced from the Codex outside-voice pass on `DESIGN.md`. None of these block Next Steps 1-2; each notes which later step it gates.

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
