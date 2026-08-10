# Error Handling

The shared error surface every other feature imports — `AppError`, `RetryPolicy`, `ErrorReporting`.

**Status: not started — skeleton only.**

## What this covers

- `AppError`: one enum covering every failure mode across PhotosKit/iCloud, CLGeocoder, and the OpenAI API
- `ErrorReporting`: one consistent reporting/logging surface, so errors show up the same way in the UI regardless of where they came from
- `RetryPolicy`: a separate implementation per boundary (PhotosKit/iCloud, CLGeocoder, OpenAI), since each fails differently — this was a deliberate refinement made during `/plan-eng-review` after an outside-voice review argued a single unified retry abstraction would hide real failure-mode differences; see [DESIGN.md](DESIGN.md)'s Architecture Decisions

Every other feature branch is currently using a local placeholder error type until this merges — landing this small, no-dependency feature early avoids each of them building throwaway retry logic they'll rip out later. See [CONTRACT.md](CONTRACT.md)'s Error handling section for the exact shape to implement.
