# Database Structure

SQLite-backed storage for geo-image-search: implements the `PhotoStore` (write) and `PhotoQuery` (read) protocols locked in [CONTRACT.md](CONTRACT.md).

**Status: merged (PR #1).**

## What's here

- `photos` table — core metadata (GPS, timestamps, cached geocoded place name, soft delete) keyed by `PHAsset.localIdentifier`
- `photos_rtree` — SQLite's built-in R-Tree module for lat/lon/radius range queries (backs `query_by_location`)
- `photo_embeddings` (sqlite-vec) — embedding similarity search (backs `semantic_search`); the vector dimension is a runtime parameter rather than hardcoded, so it can match whatever CoreML model `embedding-pipeline` ends up choosing without a schema migration
- `photo_embedding_meta` — additive table carrying `EmbeddingRecord`'s `modelVersion`/`generatedAt`, fields sqlite-vec's 2-column `photo_embeddings` table has no room for

SQLite and sqlite-vec are vendored as SPM C targets (`Sources/CSQLite3`, `Sources/CSQLiteVec`) rather than linking the system library — Apple's system `libsqlite3` disables `sqlite3_auto_extension`, which the standard sqlite-vec integration pattern depends on.

62 Swift Testing tests cover schema creation, R-Tree sync, the two-phase geo query (bounding-box prefilter + exact haversine cutoff), KNN similarity search, and trip clustering — all against in-memory/temp-file databases seeded with fixture data, since no real Photos data exists yet.

See [CONTRACT.md](CONTRACT.md)'s Database Schema section for the full interface every other feature builds against.
