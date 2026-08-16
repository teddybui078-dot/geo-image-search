# Agent eval fixtures

Fixed question -> expected-tool(+params)+result-set eval set, per TODOS.md item 1. Covers straightforward routing, no-result cases, ambiguous queries (more than one tool choice is reasonable), and date-relative phrasing ("last summer") whose correct params depend on when the eval runs.

## Format

One JSON object per line in `tool-selection.jsonl`:

```json
{"question": "Show me photos from Athens", "category": "location", "expected_tool": "query_by_location", "expected_params": {"placeName": "Athens"}, "expected_asset_ids": ["athens-2022"], "expected_result_kind": "photo_set"}
```

- `question` — the natural-language input.
- `category` — `location` | `date_range` | `cluster_trips` | `semantic` | `ambiguous` | `date_relative` | `no_result`.
- `expected_tool` — the one correct tool, when unambiguous.
- `acceptable_tools` — used instead of `expected_tool` for `ambiguous` cases: any tool in this list is a pass.
- `expected_params` — string-valued params only (`placeName`, `start`, `end`, `query`), for a human to eyeball against the printed transcript. Not strictly asserted by the harness — free-text wording varies too much (e.g. the model may resolve "Athens" to "Athens, Greece") to assert reliably, and `date_relative` cases have no fixed correct value at all since it depends on the actual run date.
- `expected_asset_ids` — the exact expected result set, checked against a small fixed fixture library (`AgentEvalFixtures.libraryAssets` in `Tests/GeoImageSearchTests/AgentEvalTests.swift`), or `null` when not deterministic (`ambiguous`/`date_relative` cases).
- `expected_result_kind` — `photo_set` | `trip_set` | `empty`.
- `notes` — why this case is shaped the way it is, especially for `ambiguous`/`no_result`/`date_relative` cases.

## Running it

`swift test --filter AgentEvalTests` runs `toolSelectionEvalSuite`, which seeds an in-memory `SQLitePhotoQuery` with the fixture library, sends each question through the real `PhotoQueryAgent` (a real `OpenAIClient`, real network calls), and checks tool routing + exact result sets where deterministic. It **skips itself** (prints a message, no failure) unless `OPENAI_API_KEY` is set in the environment — per DESIGN.md's Success Criteria this eval is run manually when the tool surface or prompts change, not scripted CI. Run it after touching `ToolSchemas`, `ToolExecutor`, or `PhotoQueryAgent`'s system prompt:

```bash
OPENAI_API_KEY=sk-... swift test --filter AgentEvalTests
```

Read the printed per-case transcript (tool(s) called, resulting assets, the model's answer) for the cases that aren't strictly asserted — `date_relative` and `expected_params` in general — since "correct" for those is a judgment call, not an exact match.
