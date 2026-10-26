import Foundation

public enum TargetPlatform: String, CaseIterable, Identifiable {
    case macApp = "mac-app"
    
    public var id: String { rawValue }
    
    public var title: String { "Mac App (.app)" }
    
    public var iconName: String { "macbook.gen2" }
    
    public var subtitle: String { "Double-clickable native macOS app for Apple Silicon." }
}
