import XCTest

/// Screens read the keyboard through their own `NSEvent` monitors. A shell overlay drawn on top of them
/// (the update offer, the welcome) must make every such monitor let the key go, or Return reaches the screen
/// underneath: a game starts instead of the overlay's button.
final class ShellOverlayInputTests: XCTestCase {
    private var views: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NXLibrary/Views")
    }

    func testEveryMonitorThatYieldsToTheUpdateOfferYieldsToTheWelcome() throws {
        let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var missing: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let offer = text.components(separatedBy: "!viewModel.isUpdateOfferOpen").count - 1
            let welcome = text.components(separatedBy: "!viewModel.isWelcomeOpen").count - 1
            if offer != welcome { missing.append("\(file.lastPathComponent): \(offer) vs \(welcome)") }
        }
        XCTAssertFalse(files.isEmpty)
        XCTAssertEqual(missing.sorted(), [])
    }
}
