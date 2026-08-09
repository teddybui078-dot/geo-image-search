# Agent eval fixtures

Fixed question -> expected-tool(+params) eval set, built alongside Next Step 6 (see TODOS.md item 1). Empty until the agent's tool surface exists.

Format (one JSON object per line in `tool-selection.jsonl`):

```json
{"question": "find pictures from my Greece trip", "expected_tool": "cluster_trips", "expected_params": {"place": "Greece"}, "expected_result_kind": "photo_set"}
```
