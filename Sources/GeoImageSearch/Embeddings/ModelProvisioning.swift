import Foundation

// The MobileCLIP-S2 .mlpackage weight files are never committed to this
// MIT-licensed repo (see README's "On-device embedding model" section) —
// they're fetched into the cache directory on first use instead.
protocol ModelProvisioning: Sendable {
    func localURL(for asset: EmbeddingModelAsset) -> URL
    func ensureAvailable(
        _ asset: EmbeddingModelAsset,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL
}

extension ModelProvisioning {
    func ensureAvailable(_ asset: EmbeddingModelAsset) async throws -> URL {
        try await ensureAvailable(asset, onProgress: nil)
    }
}

enum ModelProvisioningError: Error, Sendable {
    case manifestUnavailable(underlying: Error)
    case malformedManifest
    case downloadFailed(relativePath: String, underlying: Error)
}

struct RemoteModelFile: Sendable, Equatable {
    let relativePath: String
    let sizeInBytes: Int64
}

// Split out from HuggingFaceModelProvisioner so tests can substitute a fake
// transport instead of making real network calls — ModelProvisioningTests
// verifies the cache-check/download/atomic-move shape against a temp
// directory and a stub, not against huggingface.co.
protocol ModelFileTransferring: Sendable {
    func listFiles(repositoryID: String, revision: String, pathPrefix: String) async throws -> [RemoteModelFile]
    func download(repositoryID: String, revision: String, relativePath: String, to destination: URL) async throws
}

struct HuggingFaceModelProvisioner: ModelProvisioning {
    struct Configuration: Sendable {
        var repositoryID = "apple/coreml-mobileclip"
        var revision = "main"
        var cacheDirectory: URL
    }

    private let configuration: Configuration
    private let transport: any ModelFileTransferring

    init(configuration: Configuration, transport: any ModelFileTransferring) {
        self.configuration = configuration
        self.transport = transport
    }

    func localURL(for asset: EmbeddingModelAsset) -> URL {
        configuration.cacheDirectory.appendingPathComponent(asset.fileName, isDirectory: true)
    }

    func ensureAvailable(
        _ asset: EmbeddingModelAsset,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let destination = localURL(for: asset)
        if FileManager.default.fileExists(atPath: destination.path) {
            onProgress?(1.0)
            return destination
        }

        let files: [RemoteModelFile]
        do {
            files = try await transport.listFiles(
                repositoryID: configuration.repositoryID,
                revision: configuration.revision,
                pathPrefix: asset.fileName
            )
        } catch {
            throw ModelProvisioningError.manifestUnavailable(underlying: error)
        }
        guard !files.isEmpty else { throw ModelProvisioningError.malformedManifest }

        let staging = configuration.cacheDirectory
            .appendingPathComponent(".staging-\(asset.fileName)-\(ProcessInfo.processInfo.globallyUniqueString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let totalBytes = max(files.reduce(0) { $0 + $1.sizeInBytes }, 1)
        var completedBytes: Int64 = 0
        for file in files {
            let fileDestination = staging.appendingPathComponent(file.relativePath)
            try FileManager.default.createDirectory(
                at: fileDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try await transport.download(
                    repositoryID: configuration.repositoryID,
                    revision: configuration.revision,
                    relativePath: "\(asset.fileName)/\(file.relativePath)",
                    to: fileDestination
                )
            } catch {
                throw ModelProvisioningError.downloadFailed(relativePath: file.relativePath, underlying: error)
            }
            completedBytes += file.sizeInBytes
            onProgress?(Double(completedBytes) / Double(totalBytes))
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomic swap: if two ensureAvailable(_:) calls raced (they shouldn't,
        // callers own the queue's serialization), the loser's staging move
        // just fails and its defer cleans up — the winner's destination
        // stands, never a half-written directory.
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }
}

// Real network transport: Hugging Face's repo tree API to enumerate an
// .mlpackage's files (it's a directory bundle, not a single blob), then
// plain resolve-URL downloads. HuggingFaceModelProvisioner takes this as
// an injected dependency specifically so ModelProvisioningTests can swap
// in a fake instead of hitting huggingface.co.
struct URLSessionModelFileTransferring: ModelFileTransferring {
    private let urlSession: URLSession
    private let hostURL: URL

    init(urlSession: URLSession = .shared, hostURL: URL = URL(string: "https://huggingface.co")!) {
        self.urlSession = urlSession
        self.hostURL = hostURL
    }

    func listFiles(repositoryID: String, revision: String, pathPrefix: String) async throws -> [RemoteModelFile] {
        let treeURL = hostURL
            .appendingPathComponent("api/models/\(repositoryID)/tree/\(revision)/\(pathPrefix)")
        var components = URLComponents(url: treeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        guard let requestURL = components?.url else { throw ModelProvisioningError.malformedManifest }

        let (data, response) = try await urlSession.data(from: requestURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelProvisioningError.malformedManifest
        }

        struct TreeEntry: Decodable {
            let type: String
            let path: String
            let size: Int64?
        }
        let entries = try JSONDecoder().decode([TreeEntry].self, from: data)
        let prefixWithSlash = pathPrefix + "/"
        return entries
            .filter { $0.type == "file" && $0.path.hasPrefix(prefixWithSlash) }
            .map { RemoteModelFile(relativePath: String($0.path.dropFirst(prefixWithSlash.count)), sizeInBytes: $0.size ?? 0) }
    }

    func download(repositoryID: String, revision: String, relativePath: String, to destination: URL) async throws {
        let resolveURL = hostURL.appendingPathComponent("\(repositoryID)/resolve/\(revision)/\(relativePath)")
        let (tempURL, response) = try await urlSession.download(from: resolveURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelProvisioningError.downloadFailed(relativePath: relativePath, underlying: URLError(.badServerResponse))
        }
        // URLSession owns tempURL's lifetime past this call returning — copy,
        // don't move, so we're not racing its own post-completion cleanup.
        try FileManager.default.copyItem(at: tempURL, to: destination)
    }
}
