import Foundation

extension Date {
    /// Safe conversion to whole Unix seconds for SQLite storage.
    /// `Int64(Double)` traps (crashes) on NaN or out-of-Int64-range values —
    /// reachable from malformed upstream metadata, not just contrived input.
    /// Clamps instead of crashing: +infinity/oversized values clamp to
    /// Int64.max, -infinity/undersized values clamp to Int64.min, NaN
    /// clamps to 0 (no meaningful direction to clamp toward).
    var unixSecondsClamped: Int64 {
        let seconds = timeIntervalSince1970
        guard !seconds.isNaN else { return 0 }
        if seconds >= Double(Int64.max) { return .max }
        if seconds <= Double(Int64.min) { return .min }
        return Int64(seconds)
    }
}
