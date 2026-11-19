import Foundation

enum LogLevel {
    case info
    case step
    case success
    case warning
    case error

    var sfSymbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .step: return "gearshape.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    init(level: LogLevel = .info, message: String) {
        self.timestamp = Date()
        self.level = level
        self.message = message
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
