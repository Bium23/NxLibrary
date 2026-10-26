import SwiftUI

@main
struct NXLibraryApp: App {
    var body: some Scene {
        WindowGroup {
            Text("NX Library")
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)
    }
}
