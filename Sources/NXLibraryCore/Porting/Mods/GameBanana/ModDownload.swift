import Foundation

/// Downloads one GameBanana file into the game's mods folder (a hidden `.installing-<UUID>.download` file the caller
/// passes as `destination` and removes after the install). Follows redirects only to trusted GameBanana hosts, stops
/// past the published size, and reports progress; Cancel and every failure end in `.download`. Modelled on
/// `AppUpdateDownload`.
public final class ModDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let file: GameBananaFile
    private let destination: URL
    private let userAgent: String
    private let progress: @Sendable (Double) -> Void
    private let complete: @Sendable (Result<URL, ModInstallError>) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var finished = false

    public init(file: GameBananaFile, destination: URL, userAgent: String,
                progress: @escaping @Sendable (Double) -> Void,
                complete: @escaping @Sendable (Result<URL, ModInstallError>) -> Void) {
        self.file = file
        self.destination = destination
        self.userAgent = userAgent
        self.progress = progress
        self.complete = complete
    }

    public func start() {
        guard let url = file.downloadURL, GameBananaAPI.trusted(url), file.size > 0 else {
            finish(.failure(.download))
            return
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: queue)
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    public func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(GameBananaAPI.trusted) == true ? request : nil)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= file.size else {
            downloadTask.cancel()
            return
        }
        progress(Double(totalBytesWritten) / Double(file.size))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let trustedEnd = downloadTask.response?.url.map(GameBananaAPI.trusted) == true
        guard (200..<300).contains(status), trustedEnd else { return finish(.failure(.download)) }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            // URLSession removes `location` when this method returns.
            try fm.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(.writeFailed(error.localizedDescription)))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(.failure(.download))
        session.finishTasksAndInvalidate()
    }

    /// Reports once.
    private func finish(_ result: Result<URL, ModInstallError>) {
        lock.lock()
        let first = !finished
        finished = true
        lock.unlock()
        if first { complete(result) }
    }
}
