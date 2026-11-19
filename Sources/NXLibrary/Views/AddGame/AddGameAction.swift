import SwiftUI
import NXLibraryCore

// MARK: - Shared actions

struct AddGameAction: Identifiable {
    let id: String
    let title: String
    let isEnabled: Bool
    let perform: () -> Void

    init(id: String, title: String, isEnabled: Bool = true,
         perform: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

enum SeleneActionKind {
    case primary, secondary, destructive, quiet
}
