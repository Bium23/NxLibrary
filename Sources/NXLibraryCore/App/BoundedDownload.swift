import Foundation

/// A size-bounded HTTP read that keeps the chunks URLSession delivers. Iterating `URLSession.AsyncBytes`
/// one byte at a time cost about 6 µs per byte (a 640 KB LaunchBox page: 5.4 s instead of 2.0 s, almost all
/// of it CPU; measured 16 Nov 2026), so the public-source and Steam downloads read through this instead.
/// Redirects are never followed: the redirect response itself is returned, for the caller's URL checks.
enum BoundedDownload {
    static func data(for request: URLRequest, session: URLSession, limit: Int) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let collector = Collector(limit: limit)
        let task = session.dataTask(with: request)
        task.delegate = collector
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                collector.start(continuation)
                task.resume()
            }
        }, onCancel: { task.cancel() })
    }

    private final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let limit: Int
        private let lock = NSLock()
        private var data = Data()
        private var response: URLResponse?
        private var failure: Error?
        private var outcome: Result<(Data, URLResponse), Error>?
        private var continuation: CheckedContinuation<(Data, URLResponse), Error>?

        init(limit: Int) { self.limit = limit }

        func start(_ continuation: CheckedContinuation<(Data, URLResponse), Error>) {
            lock.lock()
            if let outcome { lock.unlock(); continuation.resume(with: outcome); return }
            self.continuation = continuation
            lock.unlock()
        }

        private func finish(_ result: Result<(Data, URLResponse), Error>) {
            lock.lock()
            guard outcome == nil else { lock.unlock(); return }
            outcome = result
            let waiting = continuation; continuation = nil
            lock.unlock()
            waiting?.resume(with: result)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            lock.lock(); self.response = response; lock.unlock()
            completionHandler(nil)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            lock.lock()
            self.response = response
            let tooLong = response.expectedContentLength > Int64(limit)
            if tooLong { failure = URLError(.dataLengthExceedsMaximum) }
            lock.unlock()
            completionHandler(tooLong ? .cancel : .allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            lock.lock()
            guard failure == nil else { lock.unlock(); return }
            if data.count + chunk.count > limit {
                failure = URLError(.dataLengthExceedsMaximum)
                lock.unlock()
                dataTask.cancel()
                return
            }
            data.append(chunk)
            lock.unlock()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let failure = failure, data = data, response = response ?? task.response
            lock.unlock()
            if let failure { return finish(.failure(failure)) }
            if let error {
                let cancelled = (error as? URLError)?.code == .cancelled
                return finish(.failure(cancelled ? CancellationError() : error))
            }
            guard let response else { return finish(.failure(URLError(.badServerResponse))) }
            finish(.success((data, response)))
        }
    }
}
