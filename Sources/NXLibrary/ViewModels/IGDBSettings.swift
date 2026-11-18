import Foundation
import Combine
import NXLibraryCore

/// Optional provider settings, separate from the catalog coordinator. Never publishes credentials.
@MainActor final class IGDBSettings: ObservableObject {
    static let shared = IGDBSettings()
    @Published private(set) var isConfigured: Bool
    @Published private(set) var revision = UUID()
    @Published var isEditing = false
    @Published private(set) var isRemoving = false
    @Published private(set) var message: String?
    private let store = IGDBCredentialsStore()
    private init() { isConfigured = store.load() != nil }
    var credentials: IGDBCredentials? { store.load() }

    func save(_ credentials: IGDBCredentials) async throws {
        try await IGDBRatingService.shared.check(credentials)
        try Task.checkCancellation()
        await IGDBRatingService.shared.invalidate()
        try Task.checkCancellation()
        try store.save(credentials)
        message = nil; isConfigured = true; revision = UUID()
    }
    func remove() async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }
        do {
            try store.remove()
            await IGDBRatingService.shared.invalidate()
            message = nil; isConfigured = false; revision = UUID()
        } catch { message = IGDBError.notSaved.localizedDescription }
    }
}
