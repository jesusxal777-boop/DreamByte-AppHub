import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DownloadProgress: Sendable, Equatable {
    public let bytesReceived: Int64
    public let totalBytes: Int64

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(bytesReceived) / Double(totalBytes)))
    }

    public init(bytesReceived: Int64, totalBytes: Int64) {
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
    }
}

private final class DownloadHandler: @unchecked Sendable {
    let continuation: CheckedContinuation<URL, Error>
    let destination: URL
    let expectedSize: Int64?
    let progress: @Sendable (DownloadProgress) -> Void
    let lock = NSLock()
    var resumed = false
    var moved = false

    init(
        continuation: CheckedContinuation<URL, Error>,
        destination: URL,
        expectedSize: Int64?,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) {
        self.continuation = continuation
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        resumed = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

/// URLSession-backed downloader with byte progress and cancellation. Files are
/// moved into AppHub's quarantine directory; callers must validate before use.
public final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [Int: DownloadHandler] = [:]
    private var session: URLSession!

    public override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        #if canImport(Darwin)
        configuration.waitsForConnectivity = false
        #endif
        configuration.allowsCellularAccess = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    public func download(
        from url: URL,
        to destination: URL,
        expectedSize: Int64?,
        progress: @escaping @Sendable (DownloadProgress) -> Void,
        onTaskCreated: @escaping @Sendable (Int) -> Void
    ) async throws -> URL {
        try? FileStore.removeIfExists(destination)

        return try await withCheckedThrowingContinuation { continuation in
            let request = URLRequest(url: url)
            let task = session.downloadTask(with: request)
            let handler = DownloadHandler(
                continuation: continuation,
                destination: destination,
                expectedSize: expectedSize,
                progress: progress
            )
            lock.lock()
            handlers[task.taskIdentifier] = handler
            lock.unlock()
            onTaskCreated(task.taskIdentifier)
            task.resume()
        }
    }

    public func cancel(taskIdentifier: Int) {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            if let task = tasks.first(where: { $0.taskIdentifier == taskIdentifier }) {
                task.cancel()
            } else {
                self.lock.lock()
                let handler = self.handlers.removeValue(forKey: taskIdentifier)
                self.lock.unlock()
                handler?.finish(.failure(AppHubError.cancelled))
            }
        }
    }

    private func handler(for task: URLSessionTask) -> DownloadHandler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[task.taskIdentifier]
    }

    private func takeHandler(for task: URLSessionTask) -> DownloadHandler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers.removeValue(forKey: task.taskIdentifier)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let handler = handler(for: downloadTask) else { return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (handler.expectedSize ?? 0)
        handler.progress(DownloadProgress(bytesReceived: totalBytesWritten, totalBytes: total))
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let handler = handler(for: downloadTask) else { return }
        do {
            try FileManager.default.createDirectory(
                at: handler.destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: handler.destination)
            try FileManager.default.moveItem(at: location, to: handler.destination)
            takeHandler(for: downloadTask)?.finish(.success(handler.destination))
        } catch {
            takeHandler(for: downloadTask)?.finish(
                .failure(AppHubError.fileWrite("Could not store the download: \(error.localizedDescription)"))
            )
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let handler = takeHandler(for: task) else { return }
        if let error {
            if (error as? URLError)?.code == .cancelled {
                handler.finish(.failure(AppHubError.cancelled))
            } else {
                handler.finish(.failure(AppHubError(.downloadFailed, error.localizedDescription)))
            }
            return
        }
        handler.finish(.failure(AppHubError(.downloadFailed, "The download ended without producing a file.")))
    }
}
