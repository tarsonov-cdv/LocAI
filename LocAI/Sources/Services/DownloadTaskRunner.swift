import Foundation

/// Wraps a URLSessionDownloadTask in async/await with byte-level progress,
/// since URLSession's async `bytes(from:)` API iterates one UInt8 at a
/// time and is unusably slow for multi-gigabyte model weight files.
enum DownloadTaskRunner {
    static func run(
        url: URL,
        destPath: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let delegate = ProgressDelegate(destPath: destPath, expectedSize: expectedSize, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destPath: URL
        let expectedSize: Int64
        let progress: @Sendable (Int64, Int64) -> Void
        var continuation: CheckedContinuation<Void, Error>?

        init(destPath: URL, expectedSize: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) {
            self.destPath = destPath
            self.expectedSize = expectedSize
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
        ) {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
            progress(totalBytesWritten, total)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: destPath.path) {
                    try fm.removeItem(at: destPath)
                }
                try fm.moveItem(at: location, to: destPath)
                continuation?.resume(returning: ())
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }
    }
}
