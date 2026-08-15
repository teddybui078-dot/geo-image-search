# Geo Image Search

A personal geographic memory engine for macOS. Grants real Photos/iCloud permission (no upload, no folder picker), plots your photos on a hand-styled interactive 3D globe, and answers natural-language questions about where you've been through an AI agent — "where did I go in Europe?", "find pictures from my trip to Greece."

Personal project, solo builder, likely open-sourced once it's further along.

## Status

Early development, being built across parallel feature branches.

| Feature | Branch | Status |
|---|---|---|
| Database Structure | `database-structure` | ✅ Merged |
| Photo/iCloud Extraction | `photo-icloud-extraction` | In progress |
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

## License

See [LICENSE](LICENSE).
