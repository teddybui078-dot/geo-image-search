# Geo Image Search

A personal geographic memory engine for macOS. Grants real Photos/iCloud permission (no upload, no folder picker), plots your photos on a hand-styled interactive 3D globe, and answers natural-language questions about where you've been through an AI agent — "where did I go in Europe?", "find pictures from my trip to Greece."

Personal project, solo builder, likely open-sourced once it's further along.

## Status

Early development, being built across parallel feature branches.

| Feature | Branch | Status |
|---|---|---|
| Database Structure | `database-structure` | ✅ Merged |
| Photo/iCloud Extraction | `photo-icloud-extraction` | Ingestion pipeline done; limited-access UI + real coverage measurement open |
| 3D Interactive Map | `add-3dmap` | In progress |
| Q&A AI Agent | `q-and-a-ai-agent` | In progress |
| Embedding Pipeline | `embedding-pipeline` | In progress |
| Error Handling | `error-handling` | ✅ Merged |

## Architecture

Native Swift app. PhotosKit for real Photos/iCloud access, SQLite (with an R-Tree geospatial index and sqlite-vec for semantic search) for storage, an [OpenGlobus](https://github.com/openglobus/openglobus) globe rendered in an embedded `WKWebView`, and an OpenAI tool-calling agent that queries the indexed library and drives the globe.

- [DESIGN.md](DESIGN.md) — full design history: the problem, the alternatives considered, the architecture decisions, and why each one was made
- [CONTRACT.md](CONTRACT.md) — the locked interfaces (shared types, database schema, protocols) every feature branch builds against, so they can be developed in parallel worktrees without blocking on each other
- [TODOS.md](TODOS.md) — the build breakdown by subsystem, plus deferred/lower-priority items

## Build

```bash
swift build      # build the package
swift run        # run the app
swift test       # run the test suite
```

Full build commands, module layout, and the parallel-worktree workflow: [CLAUDE.md](CLAUDE.md)

## On-device embedding model

Semantic photo search runs on [MobileCLIP-S2](https://github.com/apple/ml-mobileclip), via Apple's ready-made CoreML export (`apple/coreml-mobileclip` on Hugging Face). See CONTRACT.md's "Model choice, resolved" note for the technical shape.

**License note.** This app's code is MIT (see below). MobileCLIP's weights are not. The CoreML export repo declares a permissive license, but the link backing that declaration now 404s — Apple deleted the file it points to when it relicensed MobileCLIP's underlying weights to a research-only license in August 2025, with no announcement. The terms the CoreML exports actually ship under are therefore unverifiable, not confirmed-permissive. Given that, this repo:

- **Never commits the `.mlpackage` weight files.** They're downloaded on first run into `~/Library/Application Support/GeoImageSearch/Models` and verified present before the embedding pipeline runs — this repo's own MIT license only ever covers the code that fetches and calls the model, not the model itself.
- Vendors its CLIP tokenizer from `apple/coreai-models` (BSD-3) instead of copying Apple's MobileCLIP demo tokenizer, which has two known silent-corruption bugs: no truncation (crashes on long queries) and loading an untruncated merge table (drops rare words from output with no error).

If this project is ever distributed to a machine other than the builder's own, revisit this decision — bundling ambiguously-licensed weights in a redistributed MIT app is a materially different risk than a personal, single-machine runtime download.

## License

See [LICENSE](LICENSE) for this repository's code. See the "On-device embedding model" section above for the separate, distinct terms covering the MobileCLIP model weights.
