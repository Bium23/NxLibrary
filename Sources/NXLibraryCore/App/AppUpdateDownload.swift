import Foundation

/// One bounded public download. The serial session delegate owns completion and the temporary file.
public final class AppUpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedBytes: Int64
    private let progress: @Sendable (Double) -> Void
    private let complete: @Sendable (URL?, URLResponse?, Error?) -> Void
    private var finished = false

    public init(expectedBytes: Int64, progress: @escaping @Sendable (Double) -> Void,
                complete: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void) {
        self.expectedBytes = expectedBytes
        self.progress = progress
        self.complete = complete
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(AppUpdate.trustedDownloadURL) == true ? request : nil)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        guard AppUpdate.downloadWithinLimit(received: totalBytesWritten, expected: expectedBytes),
              totalBytesExpectedToWrite < 0 || totalBytesExpectedToWrite == expectedBytes else {
            downloadTask.cancel()
            return
        }
        progress(Double(totalBytesWritten) / Double(expectedBytes))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        let bytes = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        finished = true
        let response = downloadTask.response
        if bytes == expectedBytes, response?.url.map(AppUpdate.trustedDownloadURL) == true {
            // URLSession removes this file after the delegate returns; the receiver moves it now.
            complete(location, response, nil)
        } else {
            complete(nil, response, URLError(.cannotDecodeContentData))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        if !finished { complete(nil, task.response, error ?? URLError(.unknown)) }
        session.finishTasksAndInvalidate()
    }
}
