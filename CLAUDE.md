## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. SKILL.md Strategy
- Write a SKILL.md file for any reusable workflow, pattern, or domain knowledge that recurs across tasks
- Each skill is a single focused capability -- one trigger, one purpose, no kitchen sinks
- Frontmatter must include `name` and a precise `description` (when to invoke, not what it is)
- Keep skills under ~150 lines; link to references for deep detail rather than inlining everything
- Invoke existing skills before improvising -- if a skill applies even at 1% odds, use it
- After repeated corrections on the same topic, promote the lesson into a skill so it self-applies next time
- Store project-specific skills in `.claude/skills/`; review and prune stale ones at session start

### 4. Self-Improvement Loop
- After ANY correction from the user: update tasks/lessons.md with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 5. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 6. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes -- don't over-engineer
- Challenge your own work before presenting it

### 7. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests -- then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

# Task Management

1. **Plan First**: Write plan to tasks/todo.md with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to tasks/todo.md
6. **Capture Lessons**: Update tasks/lessons.md after corrections
7. **Work Verifcation**: Ask for specific questions (when asking questions, always give interactive options, interactive Q and A's)
8. **Step by Step**: Break down the problem into smaller steps and solve each step one by one
9. **Be Collaborative**: Collaborate with users to achieve their goals
10. **Be Adaptable**: Adapt to changing requirements and priorities

### 8. Ending Notes
- Always deploy subagents and skills
- Create USEFUL subagents and skills, not just random ones
- Create Agent Teams if you ever need Subagents to communicate with each other
- (IMPORTANT) When inquiring the user about ANYTHING to gather information to help build something better, always use interactive questions.

### 9. Git Commits
- Write commit messages naturally — NO conventional-commit prefixes (`feat:`, `chore:`, `docs:`, `fix:`, `fulfill:`, etc.)
- The subject line reads like a sentence a human would write about the change, e.g. "Add the gallery page with video playback" or "Render the signal sting demo end-to-end" — not "feat: gallery page"
- Keep the rest as is: granular commits (one meaningful change each), push after each, author = repo owner from `.env`, Claude co-author trailer at the end

### 10. Parallel Work & Git Worktrees
- Never point multiple Claude Code instances at the same working directory — concurrent edits and commits will race and conflict, including with auto-checkpoint commits
- Use `git worktree add <path> <branch>` to give each instance its own isolated directory + branch, sharing the same `.git` history (no full re-clone needed)
- Before splitting dependent work across parallel instances, lock the interface first (API shape, types, schema) via a plan doc — then build against that agreed contract simultaneously instead of blocking
- Clean up worktrees after merging: `git worktree remove <path>`

### 11. Skill Suite Routing (gstack + superpowers)
- Both suites auto-invoke based on context — no need to type `/commands` or skill names manually; describe the task and the matching skill fires on its own
- Superpowers' `using-superpowers` skill mandates invoking any skill with even a 1% chance of applying, checked before any response, including clarifying questions
- gstack auto-invokes when `proactive: true` (global `~/.gstack/config.yaml`, on by default) and either its router or the current project's CLAUDE.md `## Skill routing` section match the request
- The two suites overlap on two triggers with no defined winner: a new idea / "let's build X" (superpowers `brainstorming` vs. gstack `/office-hours`), and "fix this bug" (superpowers `systematic-debugging` vs. gstack `/investigate`)
- Default tiebreak: prefer gstack's skill when the current project already has gstack's CLAUDE.md routing section installed (it produces chained artifacts — design docs, specs — that downstream gstack skills expect); otherwise use superpowers' general-purpose skill
- Naming a skill explicitly (e.g. "run /office-hours" or "use systematic-debugging") always overrides the auto-pick, regardless of which suite it's from

Do not skip skills, ignore gstack errors, or work around missing gstack.

Using gstack skills: skills like /qa, /ship, /review, /investigate, and /browse
are available. Use /browse for all web browsing. Use ~/.claude/skills/gstack/...
for gstack file paths (the global path).

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec

## Project: Geo Image Search

Native macOS app. Grants real Photos/iCloud permission via PhotosKit (no upload/folder-picker flow), plots geotagged photos on a custom-styled interactive 3D globe, and answers natural-language questions via an LLM tool-calling agent. Personal project, solo builder, likely open-sourced later. Full architecture, premises, and decision history: see `DESIGN.md`. Deferred work: see `TODOS.md`.

### Stack

- Swift 6, SwiftUI app shell, Swift Package Manager (`Package.swift`) — open with Xcode via "Open..." on `Package.swift`, or use the `swift` CLI below.
- PhotosKit for Photos/iCloud access — GPS from `PHAsset.location`, not manual EXIF parsing.
- SQLite: R-Tree module for geospatial (lat/lon/radius) queries, sqlite-vec for embedding similarity — these solve different problems, do not conflate them.
- CoreML (MobileCLIP or similar, TBD — TODOS.md item 5) for on-device photo/text embeddings.
- OpenGlobus (Apache-2.0) rendered in a `WKWebView`, bridged to native Swift via `WKScriptMessageHandler`.
- OpenAI API for the LLM agent. macOS Keychain for the API key — never a config file or environment variable.
- Swift Testing (`import Testing`, `@Test`/`#expect`) — not XCTest.

### Build commands

```bash
swift build      # build the package
swift run        # run the app (SwiftUI window)
swift test       # run the test suite
```

Full app-bundle build (Photos entitlements, sandboxing, code signing) requires opening `Package.swift` in Xcode and building the `GeoImageSearch` scheme — `swift build` alone does not apply `Resources/GeoImageSearch.entitlements` or `Resources/Info.plist`. Wiring that up is part of Next Step 1.

### Module layout

`Sources/GeoImageSearch/` — `App/` (SwiftUI entry point), `Ingestion/` (PhotosKit permission, asset identity, sync strategy), `Storage/` (SQLite schema), `Globe/` (WKWebView bridge, pin clustering), `Query/` (shared `PhotoQuery` repository backing all agent tools), `Agent/` (tool schemas), `Embeddings/` (background embedding generation), `Common/` (shared error reporting + per-boundary retry policies).

### Testing

- Framework: Swift Testing.
- Agent tool-selection correctness is an eval, not a unit test — see `eval/README.md`. Not scripted CI in v1; run manually when the tool surface or prompts change (per DESIGN.md Success Criteria).

### Parallel development / worktrees

This project is meant to be built across multiple git worktrees at once — one feature per worktree, per branch. **Read `CONTRACT.md` before writing code in a worktree.** It locks the shared types, database schema, and protocols (`PhotoAsset`, `PhotoStore`, `PhotoQuery`, the native↔globe bridge messages, agent tool schemas, `AppError`/`RetryPolicy`) that every feature builds against — build against those shapes, not against another feature's actual implementation. `CONTRACT.md` also has a suggested branch name and merge-order guide per feature.

If a worktree needs a shared type in `CONTRACT.md` to change, update `CONTRACT.md` on `main` (or flag it) before changing your branch's usage of it — a shared type drifting silently in one worktree is the exact merge-hell scenario `CONTRACT.md` exists to prevent.

**Commit and push granularly.** Within a feature branch, commit and push each sub-component separately as it's done — not one giant commit at the end of the feature. This matches the global commit-incrementally convention, worth restating here since worktree agents in this repo run somewhat independently: smaller, frequent pushes on your own branch make merges predictable, especially when another worktree is depending on a type your branch touches. Push only the branch your current worktree is on — never push another worktree's branch or use `push --all`.

See `github.txt` for this repo's GitHub push conventions (commit naming, account info).