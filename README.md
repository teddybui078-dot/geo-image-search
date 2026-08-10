# Error Handling

The shared error surface every other feature imports — `AppError`, `RetryPolicy`, `ErrorReporting`.

**Status: done.** `AppError`/`RetryPolicy`/`ErrorReporting` are implemented in `Sources/GeoImageSearch/Common/`, matching CONTRACT.md's locked shapes, with Swift Testing coverage.

## What this covers

- `AppError`: one enum covering every failure mode across PhotosKit/iCloud, CLGeocoder, and the OpenAI API, plus `severity`/`logDescription` so every call site formats an error the same way
- `ErrorReporting`: one consistent reporting/logging surface (`ErrorReporter`, backed by `os.Logger` through an injectable `ErrorLogSink`), so errors show up the same way in the UI regardless of where they came from
- `RetryPolicy`: a separate implementation per boundary (`PhotosRetryPolicy`, `GeocodingRetryPolicy`, `LLMRetryPolicy`), since each fails differently — this was a deliberate refinement made during `/plan-eng-review` after an outside-voice review argued a single unified retry abstraction would hide real failure-mode differences; see [DESIGN.md](DESIGN.md)'s Architecture Decisions
- `RetryExecutor`: a shared retry loop (injectable delay) so each boundary runs its policy without hand-rolling its own attempt-counting/backoff logic

Every other feature branch is currently using a local placeholder error type until this merges — swap it for the real `AppError`/`RetryPolicy`/`ErrorReporting` in `Sources/GeoImageSearch/Common/` once this lands. See [CONTRACT.md](CONTRACT.md)'s Error handling section for the locked shape.
