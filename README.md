# Q&A AI Agent

Ask it a real question — "where did I go in Europe?", "find pictures from my trip to Greece" — and it answers by calling tools against your indexed photo library, then updates the globe.

**Status: not started — skeleton only.**

## What this covers

- An OpenAI tool-calling agent loop over four tools: `query_by_location`, `query_by_date_range`, `semantic_search`, `cluster_trips` — draft schemas in [CONTRACT.md](CONTRACT.md)
- A real agent from day one, not a keyword parser wearing an AI costume — this was deliberately reconfirmed three separate times against outside-voice pushback during design; see [DESIGN.md](DESIGN.md)'s Cross-Model Perspective and Architecture Decisions
- Calls the real `PhotoQuery` — `database-structure` is merged, no mocking needed
- Keychain storage for the OpenAI API key, plus real key UX (validation, missing-key state, quota exhaustion)
- `cluster_trips`' definition of a "trip" (stop duration, travel-gap threshold, timezone handling) scoped using real ingested data, not guessed upfront
- An eval suite (fixed question → expected tool + params + result set) built alongside each tool as it's written, not bolted on at the end — see [TODOS.md](TODOS.md) item 1

`semantic_search` needs `embedding-pipeline`'s work to return meaningful results — the other three tools don't, and can be built and tested against real data now.
