import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

@MainActor
final class SteamPersonalizations {
    static let shared = SteamPersonalizations()
    let metadata = SteamPersonalizationStore(directory: AppData.supportRoot.appendingPathComponent("integrations/steam/personal"))
    var artwork: SteamPersonalizationStore { metadata }

}

struct SteamPersonalizationEditor: View {
    let game: CatalogGame
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nxAppLocale) private var localization
    @State private var fields: [MetadataField: String] = [:]
    @State private var saveFocused = true
    @State private var slot: ArtworkSlot = .cover
    @State private var pendingArtwork: [ArtworkSlot: Data] = [:]
    @State private var automatic: Set<ArtworkSlot> = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(game.name).font(.title2)
            Text(L10n.text("Change metadata", context: localization)).font(.headline)
            ForEach(MetadataField.allCases, id: \.self) { field in
                TextField(field.title, text: Binding(get: { fields[field] ?? "" }, set: { fields[field] = $0 }))
            }
            Text(L10n.text("Leave blank to use Steam data.", context: localization)).font(.caption)
            Divider()
            Picker(L10n.text("Change artwork", context: localization), selection: $slot) {
                ForEach(ArtworkSlot.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            HStack {
                Button(L10n.text("Choose", context: localization), action: choose)
                Button(L10n.text("Automatic", context: localization)) { pendingArtwork[slot] = nil; automatic.insert(slot) }
            }
            if let error { Text(error).foregroundColor(.red).font(.caption) }
            HStack {
                Button(L10n.text("Cancel", context: localization)) { dismiss() }.keyboardShortcut(.cancelAction).overlay(RoundedRectangle(cornerRadius: 5).stroke(saveFocused ? Color.clear : Color.accentColor, lineWidth: 2))
                Spacer()
                Button(L10n.text("Save", context: localization)) {
                    save()
                }.keyboardShortcut(.defaultAction).overlay(RoundedRectangle(cornerRadius: 5).stroke(saveFocused ? Color.accentColor : Color.clear, lineWidth: 2))
            }
        }.onReceive(NotificationCenter.default.publisher(for: .nxDetailGamepadAction)) { note in
            guard let action = note.object as? GamepadAction, NSApp.modalWindow == nil else { return }
            switch action {
            case .cancel: dismiss()
            case .navigateLeft: saveFocused = false
            case .navigateRight: saveFocused = true
            case .confirm: if saveFocused { save() } else { dismiss() }
            default: break
            }
        }.padding(28).frame(width: 560)
        .onAppear {
            for field in MetadataField.allCases { fields[field] = SteamPersonalizations.shared.metadata.value(titleID: game.personalizationReference.key, field: field) ?? "" }
        }
    }
    private func save() {
        do {
            try SteamPersonalizations.shared.metadata.save(fields: fields, images: pendingArtwork, automatic: automatic, titleID: game.personalizationReference.key); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 12_582_912 else { throw URLError(.dataLengthExceedsMaximum) }
            let data = try Data(contentsOf: url)
            guard NSImage(data: data) != nil else { throw URLError(.cannotDecodeContentData) }
            pendingArtwork[slot] = data; automatic.remove(slot)
        } catch { self.error = error.localizedDescription }
    }
}
