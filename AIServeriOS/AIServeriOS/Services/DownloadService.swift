import Foundation

enum DownloadError: LocalizedError {
    case httpError(Int)
    case licenseRequired(String)
    case fileMoveError(String)
    case alreadyDownloading

    var errorDescription: String? {
        switch self {
        case .httpError(let code):         return "HTTP \(code) — check your HuggingFace token."
        case .licenseRequired(let url):    return "license_required: accept licence at \(url) then retry."
        case .fileMoveError(let msg):      return "Failed to save file: \(msg)"
        case .alreadyDownloading:          return "A download is already in progress."
        }
    }
}

/// Downloads model files from HuggingFace using URLSession.
/// Progress is reported via a closure (0.0–1.0).
final class DownloadService {

    static let shared = DownloadService()
    private init() {}

    private var activeTask: URLSessionDataTask?
    private(set) var isDownloading = false
    private var cancellationRequested = false

    /// Absolute path on disk for a given model.
    func filePath(for model: ModelInfo) -> URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return docs.appendingPathComponent(model.fileName)
    }

    /// True if the model file is present and reasonably large.
    func isDownloaded(_ model: ModelInfo) -> Bool {
        let url = filePath(for: model)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return false }
        return size > 1024 * 1024
    }

    /// Delete a downloaded model file.
    func delete(_ model: ModelInfo) throws {
        let path = filePath(for: model)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    /// Cancel the active download.
    func cancel() {
        cancellationRequested = true
        activeTask?.cancel()
    }

    /// Download [model] to the Documents directory, calling [onProgress] as data arrives.
    /// Throws DownloadError on network or auth failure.
    func download(
        model: ModelInfo,
        hfToken: String?,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        guard !isDownloading else { throw DownloadError.alreadyDownloading }

        isDownloading = true
        cancellationRequested = false
        defer { isDownloading = false }

        var request = URLRequest(url: URL(string: model.downloadUrl)!)
        request.timeoutInterval = 30
        if let token = hfToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let destination = filePath(for: model)

        // Write to a temp file first to avoid partial writes
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".tmp")

        defer { try? FileManager.default.removeItem(at: tmp) }

        // Pre-create file so FileHandle can open it
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tmp)
        defer { try? fileHandle.close() }

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.httpError(0)
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            let licenseURL = model.licenseUrl ?? model.downloadUrl
            throw DownloadError.licenseRequired(licenseURL)
        }

        guard http.statusCode == 200 else {
            throw DownloadError.httpError(http.statusCode)
        }

        let totalBytes = max(1, response.expectedContentLength)
        var receivedBytes: Int64 = 0
        var buffer = Data(capacity: 256 * 1024)

        for try await byte in asyncBytes {
            if cancellationRequested { break }
            buffer.append(byte)
            receivedBytes += 1

            if buffer.count >= 256 * 1024 {
                fileHandle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
                onProgress(Double(receivedBytes) / Double(totalBytes))
            }
        }

        if !buffer.isEmpty && !cancellationRequested {
            fileHandle.write(buffer)
        }

        if cancellationRequested { return }

        try fileHandle.close()

        // Move temp → final destination (atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        do {
            try FileManager.default.moveItem(at: tmp, to: destination)
        } catch {
            throw DownloadError.fileMoveError(error.localizedDescription)
        }

        onProgress(1.0)
    }
}
