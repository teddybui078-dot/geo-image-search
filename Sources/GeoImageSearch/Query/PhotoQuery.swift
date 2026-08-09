import Foundation

// Next Step 5 — shared query layer backing all four agent tools, avoids four
// independent SQL builders (Code Quality Issue 3).
enum PhotoQuery {
    static func byLocation() {}
    static func byDateRange() {}
    static func bySimilarity() {}
    static func clusterTrips() {}
}
