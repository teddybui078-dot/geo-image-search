import Photos
@testable import GeoImageSearch

struct FakePhotosAuthorizing: PhotosAuthorizing {
    let status: PhotosAccessStatus
    func requestAccess() async -> PhotosAccessStatus { status }
}

// fetchAllPhotoAssetSnapshots() is a synchronous `throws` requirement (not
// async), so it can't hop onto actor isolation to mutate call-count state —
// @unchecked Sendable is safe here because RetryExecutor only ever calls it
// serially within one ingest run, never concurrently.
final class SerialFakeFetcher: PhotoLibraryFetching, @unchecked Sendable {
    private var results: [Result<[PhotoAssetSnapshot], Error>]
    private(set) var callCount = 0

    init(results: [Result<[PhotoAssetSnapshot], Error>]) {
        self.results = results
    }

    func fetchAllPhotoAssetSnapshots() throws -> [PhotoAssetSnapshot] {
        callCount += 1
        guard !results.isEmpty else { return [] }
        return try results.removeFirst().get()
    }
}

struct FakeReverseGeocoder: ReverseGeocoding {
    let placeNamesByCoordinate: [String: String]

    func placeName(latitude: Double, longitude: Double) async throws -> String? {
        placeNamesByCoordinate[GeoBucket.key(latitude: latitude, longitude: longitude)]
    }
}

final class SpyErrorReporter: ErrorReporting, @unchecked Sendable {
    private(set) var reported: [(error: AppError, context: String)] = []

    func report(_ error: AppError, context: String) {
        reported.append((error, context))
    }
}
