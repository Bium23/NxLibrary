import Foundation

/// A Play request that waits for the app's icon to finish signing. It belongs to its visible
/// preparation notice: cancelling or replacing that notice revokes the request.
public struct IconLaunchWait {
    public private(set) var gameID: UUID?
    public private(set) var noticeID: UUID?

    public init() {}

    public mutating func begin(gameID: UUID, noticeID: UUID) {
        self.gameID = gameID
        self.noticeID = noticeID
    }

    public mutating func cancel() {
        gameID = nil
        noticeID = nil
    }

    public mutating func finished(gameID: UUID, rerun: Bool, succeeded: Bool,
                                  visibleNoticeID: UUID?) -> UUID? {
        guard self.gameID == gameID, !rerun else { return nil }
        let mayLaunch = succeeded && visibleNoticeID == noticeID
        cancel()
        return mayLaunch ? gameID : nil
    }
}
