import Foundation

// Shared error-reporting surface across PhotosKit/CLGeocoder/LLM boundaries —
// consistent UI presentation, but see RetryPolicy for per-boundary retry logic.
enum ErrorReporter {}
