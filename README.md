# Embedding Pipeline

Generates on-device photo embeddings so `semantic_search` ("sunset on a beach") can find photos by meaning, not just metadata.

**Status: not started — skeleton only.**

## What this covers

- CoreML model selection (a MobileCLIP variant — a real decision to make and document, not defer) — see [TODOS.md](TODOS.md) item 5
- Background-queue, bounded-concurrency generation with a visible progress indicator, since a first run on a ~50k-photo library touches every asset's thumbnail once
- An optional date-range scope for first-run indexing (e.g. "2021-present first") to reduce cold-start cost
- Embeddings generated from PhotosKit's local low-resolution thumbnail, not a full-resolution iCloud download
- Writes through `PhotoStore.upsertEmbedding` — `database-structure` is merged, no mocking needed

`database-structure` already resolved the cross-feature dependency this would otherwise create: `photo_embeddings`' vector dimension is a runtime parameter to schema setup rather than a hardcoded guess, so this feature can pick its model and pass the real dimension without needing a schema migration afterward. See [CONTRACT.md](CONTRACT.md)'s "Open dependency, resolved" note.
