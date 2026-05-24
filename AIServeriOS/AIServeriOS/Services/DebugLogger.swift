import Foundation
import os.log

private let sysLog = Logger(subsystem: "ai.ecoinference.app", category: "DebugLogger")

/// Writes timestamped log lines to a rolling file in the app's Documents folder.
/// Pull the file with:
///   xcrun devicectl device copy from --device <udid> \
///     --source /private/var/mobile/Containers/Data/Application/<UUID>/Documents/ecoinference_debug.log \
///     --destination ~/Desktop/ecoinference_debug.log
final class DebugLogger {

    static let shared = DebugLogger()
    private init() { open() }

    private var handle: FileHandle?
    private let queue  = DispatchQueue(label: "ai.ecoinference.debuglog")
    private let maxBytes = 2 * 1024 * 1024   // 2 MB rolling cap

    var logFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ecoinference_debug.log")
    }

    // MARK: - Public

    func log(_ message: String, level: String = "INFO",
             file: String = #fileID, line: Int = #line) {
        let ts    = ISO8601DateFormatter().string(from: Date())
        let fname = URL(fileURLWithPath: file).lastPathComponent
        let entry = "[\(ts)] [\(level)] \(fname):\(line) \(message)\n"
        sysLog.info("\(message)")
        // Synchronous write so log entries survive a hard crash (abort/SIGSEGV).
        // queue.async was losing the last N entries before process termination.
        queue.sync { self.write(entry) }
    }

    func error(_ message: String, file: String = #fileID, line: Int = #line) {
        log(message, level: "ERROR", file: file, line: line)
    }

    // MARK: - Private

    private func open() {
        let url = logFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        let header = "\n\n=== Session start \(Date()) ===\n"
        handle?.write(header.data(using: .utf8) ?? Data())
    }

    private func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        handle?.write(data)
        // Rolling: truncate oldest half when file exceeds cap
        if let size = try? FileManager.default.attributesOfItem(
            atPath: logFileURL.path)[.size] as? Int, size > maxBytes {
            roll()
        }
    }

    private func roll() {
        guard let url = handle.map({ _ in logFileURL }),
              let content = try? Data(contentsOf: url) else { return }
        let half = content.suffix(maxBytes / 2)
        try? half.write(to: url)
        handle?.seek(toFileOffset: UInt64(half.count))
    }
}

// Convenience free functions used like the Logger API
func dlog(_ msg: String, file: String = #fileID, line: Int = #line) {
    DebugLogger.shared.log(msg, file: file, line: line)
}
func derr(_ msg: String, file: String = #fileID, line: Int = #line) {
    DebugLogger.shared.error(msg, file: file, line: line)
}
