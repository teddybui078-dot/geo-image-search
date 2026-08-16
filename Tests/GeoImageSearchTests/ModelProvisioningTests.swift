import Foundation
import Testing
@testable import GeoImageSearch

// Verifies HuggingFaceModelProvisioner's cache-check/download/atomic-move
// shape against a temp directory and a fake transport — no real network
// call, per this project's constraint that the weight files themselves
// are never fetched/verified in CI, only manually on a provisioned machine.
private actor FakeModelFileTransferring: ModelFileTransferring {
    enum ManifestBehavior {
        case files([RemoteModelFile])
        case requestFails
    }

    private let manifestBehavior: ManifestBehavior
    private let failDownloadSuffix: String?
    private(set) var listFilesCallCount = 0
    private(set) var downloadedRelativePaths: [String] = []

    init(manifestBehavior: ManifestBehavior, failDownloadSuffix: String? = nil) {
        self.manifestBehavior = manifestBehavior
        self.failDownloadSuffix = failDownloadSuffix
    }

    func listFiles(repositoryID: String, revision: String, pathPrefix: String) async throws -> [RemoteModelFile] {
        listFilesCallCount += 1
        switch manifestBehavior {
        case .files(let files): return files
        case .requestFails: throw URLError(.badServerResponse)
        }
    }

    func download(repositoryID: String, revision: String, relativePath: String, to destination: URL) async throws {
        if let suffix = failDownloadSuffix, relativePath.hasSuffix(suffix) {
            throw URLError(.timedOut)
        }
        downloadedRelativePaths.append(relativePath)
        try Data("fixture-\(relativePath)".utf8).write(to: destination)
    }
}

@Suite struct ModelProvisioningTests {
    private func makeTempCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelProvisioningTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private let sampleFiles = [
        RemoteModelFile(relativePath: "Manifest.json", sizeInBytes: 100),
        RemoteModelFile(relativePath: "Data/com.apple.CoreML/model.mlmodel", sizeInBytes: 900)
    ]

    @Test func alreadyCachedSkipsTransportEntirely() async throws {
        let cacheDirectory = try makeTempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let destination = cacheDirectory.appendingPathComponent(EmbeddingModelAsset.image.fileName, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let transport = FakeModelFileTransferring(manifestBehavior: .files(sampleFiles))
        let provisioner = HuggingFaceModelProvisioner(
            configuration: .init(cacheDirectory: cacheDirectory),
            transport: transport
        )

        let resolved = try await provisioner.ensureAvailable(.image)
        #expect(resolved == destination)
        #expect(await transport.listFilesCallCount == 0)
    }

    @Test func downloadsListedFilesIntoDestination() async throws {
        let cacheDirectory = try makeTempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let transport = FakeModelFileTransferring(manifestBehavior: .files(sampleFiles))
        let provisioner = HuggingFaceModelProvisioner(
            configuration: .init(cacheDirectory: cacheDirectory),
            transport: transport
        )

        let resolved = try await provisioner.ensureAvailable(.image)

        #expect(FileManager.default.fileExists(atPath: resolved.appendingPathComponent("Manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: resolved.appendingPathComponent("Data/com.apple.CoreML/model.mlmodel").path))
        let downloaded = await transport.downloadedRelativePaths
        #expect(downloaded.count == 2)
        #expect(downloaded.allSatisfy { $0.hasPrefix("\(EmbeddingModelAsset.image.fileName)/") })
    }

    @Test func reportsMonotonicallyIncreasingProgress() async throws {
        let cacheDirectory = try makeTempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let transport = FakeModelFileTransferring(manifestBehavior: .files(sampleFiles))
        let provisioner = HuggingFaceModelProvisioner(
            configuration: .init(cacheDirectory: cacheDirectory),
            transport: transport
        )

        let reported = LockedProgressLog()
        _ = try await provisioner.ensureAvailable(.image) { fraction in
            reported.append(fraction)
        }

        let fractions = reported.values
        #expect(fractions.count == sampleFiles.count)
        #expect(fractions == fractions.sorted())
        #expect(fractions.last == 1.0)
    }

    @Test func manifestFailureThrowsManifestUnavailable() async throws {
        let cacheDirectory = try makeTempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let transport = FakeModelFileTransferring(manifestBehavior: .requestFails)
        let provisioner = HuggingFaceModelProvisioner(
            configuration: .init(cacheDirectory: cacheDirectory),
            transport: transport
        )

        await #expect(throws: ModelProvisioningError.self) {
            try await provisioner.ensureAvailable(.image)
        }
    }

    @Test func emptyManifestThrowsMalformedManifest() async throws {
        let cacheDirectory = try makeTempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let transport = FakeModelFileTransferring(manifestBehavior: .files([]))
        let provisioner = HuggingFaceModelProvisioner(
            configuration: .init(cacheDirectory: cacheDirectory),
            transport: transport
        )

        await #expect(throws: ModelProvisioningError.self) {
            try await provisioner.ensureAvailable(.image)
        }
    }

    @Test func downloadFailureLeavesNoPartialDestinationOrStagingDirectory() async throws {
        let cacheDirectory = try makeTempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let transport = FakeModelFileTransferring(manifestBehavior: .files(sampleFiles), failDownloadSuffix: "model.mlmodel")
        let provisioner = HuggingFaceModelProvisioner(
            configuration: .init(cacheDirectory: cacheDirectory),
            transport: transport
        )

        await #expect(throws: ModelProvisioningError.self) {
            try await provisioner.ensureAvailable(.image)
        }

        let destination = provisioner.localURL(for: .image)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let remainingEntries = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
        #expect(remainingEntries.allSatisfy { !$0.hasPrefix(".staging-") })
    }
}

// Testing @Test functions run concurrently — collecting the progress
// callback's values needs its own synchronization independent of the
// provisioner under test.
private final class LockedProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
