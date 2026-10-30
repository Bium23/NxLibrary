import SwiftUI

/// Where a few home tiles sit in the window, so Add game can grow out of the Add
/// game card and shrink back into the porting tile. Written by Spotlight's row,
/// read when the panel opens or closes; nothing redraws on it.
final class HomeAnchors {
    static let shared = HomeAnchors()
    static let addCard = "card:addGame"

    /// Window-space frames by Spotlight item key.
    var frames: [String: CGRect] = [:]
    /// The key the next Add game opens from; consumed on open.
    var openFrom: String?

    func frame(_ key: String?) -> CGRect? {
        key.flatMap { frames[$0] }
    }
}

extension View {
    /// Records this view's window-space frame under `key` (no-op for nil).
    func homeAnchor(_ key: String?) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { if let key { HomeAnchors.shared.frames[key] = geo.frame(in: .global) } }
                    .onChange(of: geo.frame(in: .global)) { frame in
                        if let key { HomeAnchors.shared.frames[key] = frame }
                    }
            }
        )
    }
}
