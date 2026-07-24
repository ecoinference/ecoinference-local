import Foundation

enum DownloadError: LocalizedError {
    case httpError(Int)
    case fileMoveError(String)
    case alreadyDownloading

    var errorDescription: String? {
        switch self {
        case .httpError(let code):      return "HTTP \(code) — download failed."
        case .fileMoveError(let msg):   return "Failed to save file: \(msg)"
        case .alreadyDownloading:       return "A download is already in progress."
        }
    }
}

/// Downloads model files (currently always hosted on our own server) using URLSession.
/// Progress is reported via a closure (0.0–1.0).
///
/// Thread-safety: `isDownloading` and `cancellationRequested` are guarded by
/// an NSLock so they are safe to read from any thread (HTTP handlers, UI).
final class DownloadService {

    static let shared = DownloadService()
    private init() {}

    // ── State (lock-protected) ────────────────────────────────────────────────

    private let lock = NSLock()
    private var _isDownloading         = false
    private var _cancellationRequested = false

    var isDownloading: Bool {
        lock.withLock { _isDownloading }
    }

    // ── File helpers ──────────────────────────────────────────────────────────

    /// Absolute URL on disk for a given model.
    func filePath(for model: ModelInfo) -> URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return docs.appendingPathComponent(model.fileName)
    }

    /// True if the model file is present and at least 90 % of the declared size.
    ///
    /// A 1 MB floor is far too low — a truncated 2 GB download would pass it.
    /// We require at least 90 % of `model.fileSizeMb` so any significantly
    /// incomplete download is caught here rather than silently fed to the engine.
    func isDownloaded(_ model: ModelInfo) -> Bool {
        let url = filePath(for: model)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return false }
        // 90 % of declared size (fileSizeMb uses decimal MB for display, so ×1_000_000)
        let minBytes = model.fileSizeMb * 1_000_000 * 9 / 10
        return size >= minBytes
    }

    /// Delete a downloaded model file.
    func delete(_ model: ModelInfo) throws {
        let path = filePath(for: model)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    // ── Cancel ────────────────────────────────────────────────────────────────

    func cancel() {
        lock.withLock { _cancellationRequested = true }
    }

    // ── Download ──────────────────────────────────────────────────────────────

    /// Download [model] to the Documents directory, calling [onProgress] (0.0–1.0) as data arrives.
    /// Fetches a presigned URL from Firebase Functions before streaming.
    func download(
        model: ModelInfo,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        // Atomically check-and-set isDownloading to avoid races between
        // concurrent HTTP requests or a UI tap + HTTP request arriving together.
        try lock.withLock {
            guard !_isDownloading else { throw DownloadError.alreadyDownloading }
            _isDownloading         = true
            _cancellationRequested = false
        }
        defer { lock.withLock { _isDownloading = false } }

        let presignedUrl = try await B2Service.shared.modelDownloadUrl(
            modelId: model.id,
            filename: model.fileName
        )

        var request = URLRequest(url: presignedUrl)
        // Idle timeout (resets on each byte received), not a total-transfer cap.
        // 30s was too tight for multi-GB files on first request, when Cloudflare/B2
        // haven't warmed the path yet — matches Android's readTimeout(0) intent of
        // not timing out mid-transfer, while still catching a genuinely dead connection.
        request.timeoutInterval = 120

        let destination = filePath(for: model)

        // Write to a temp file first to avoid partial writes landing at destination.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".tmp")

        // Pre-create so FileHandle can open it.
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tmp)

        // Single defer for cleanup: removes tmp (no-op if already moved).
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        // On error, close fileHandle before the defer removes tmp.
        func closeHandle() { try? fileHandle.close() }

        guard let http = response as? HTTPURLResponse else {
            closeHandle()
            throw DownloadError.httpError(0)
        }

        guard http.statusCode == 200 else {
            closeHandle()
            throw DownloadError.httpError(http.statusCode)
        }

        let totalBytes = max(1, response.expectedContentLength)
        var receivedBytes: Int64 = 0
        var buffer = Data(capacity: 256 * 1024)

        for try await byte in asyncBytes {
            if lock.withLock({ _cancellationRequested }) { break }
            buffer.append(byte)
            receivedBytes += 1

            if buffer.count >= 256 * 1024 {
                fileHandle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
                onProgress(Double(receivedBytes) / Double(totalBytes))
            }
        }

        // Flush remaining bytes.
        if !buffer.isEmpty && !lock.withLock({ _cancellationRequested }) {
            fileHandle.write(buffer)
        }

        // Close the handle exactly once before moving the file.
        try fileHandle.close()

        if lock.withLock({ _cancellationRequested }) { return }

        // Atomic move: remove existing destination if present.
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
