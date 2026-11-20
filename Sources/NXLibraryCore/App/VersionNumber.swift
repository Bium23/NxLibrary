import Foundation

public enum VersionNumber {
    /// Dotted numbers compared part by part; a missing part counts as 0. Text before the first digit is skipped,
    /// so `xcodebuild -version`'s "Xcode 27.2" reads as 27.2.
    public static func isOlder(_ a: String, than b: String) -> Bool {
        let left = parts(a), right = parts(b)
        for i in 0..<max(left.count, right.count) {
            let x = i < left.count ? left[i] : 0
            let y = i < right.count ? right[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.drop { !$0.isNumber }.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
