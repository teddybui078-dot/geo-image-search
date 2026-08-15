import Foundation

// One shared reporting surface across PhotosKit, CLGeocoder, and LLM calls
// (consistent UI/logging presentation) — see DESIGN.md's Architecture
// Decisions. Shape locked by CONTRACT.md.
protocol ErrorReporting: Sendable {
    func report(_ error: AppError, context: String)
}
