import SwiftUI
import NXLibraryCore

/// Search: a Selene pill field over `SettingsCatalog.search`; picking a result opens its group.
struct SettingsSearchSection: View {
    @ObservedObject var settings: AppSettingsStore
    let onOpenGroup: (SettingsSection) -> Void
    let onSubmit: () -> Void
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var results: [SettingDescriptor] { SettingsCatalog.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            TextField(L10n.text("Search settings"), text: $query)
                .textFieldStyle(.plain)
                .seleneFont(19)
                .foregroundColor(SeleneTheme.ink)
                .focused($fieldFocused)
                .onSubmit {
                    fieldFocused = false
                    onSubmit()
                }
                .padding(.leading, canvas.u(26))
                .padding(.top, canvas.u(11))
                .padding(.trailing, canvas.u(26))
                .padding(.bottom, canvas.u(13))
                .background(RoundedRectangle(cornerRadius: canvas.u(22), style: .continuous)
                    .fill(SeleneTheme.glass))
                .overlay(RoundedRectangle(cornerRadius: canvas.u(22), style: .continuous)
                    .strokeBorder(fieldFocused ? SeleneTheme.focus : SeleneTheme.ink15,
                                  lineWidth: max(1, canvas.u(2))))
                .padding(.bottom, canvas.u(8))

            if !query.isEmpty && results.isEmpty {
                Text(L10n.text("No settings match."))
                    .seleneFont(19)
                    .foregroundColor(SeleneTheme.ink60)
            }
            SettingsDescriptorList(rows: results, onOpenGroup: onOpenGroup)
        }
        .onAppear {
            fieldFocused = true
            publishActions()
        }
        .onChange(of: query) { _ in publishActions() }
    }

    private func publishActions() {
        onActions(SettingsDescriptorList.actions(results, onOpenGroup: onOpenGroup))
    }
}

/// Changed: every row whose value differs from the default.
struct SettingsChangedSection: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var controller = GameControllerService.shared
    let onOpenGroup: (SettingsSection) -> Void
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var rows: [SettingDescriptor] {
        var external = Set<String>()
        if viewModel.iconAppearanceMode != .auto { external.insert("iconAppearance") }
        if abs(controller.deadzone - 0.35) > 0.001 { external.insert("controllerDeadzone") }
        if viewModel.gameFilesFolder != nil { external.insert("gameFolder") }
        let root = URL(fileURLWithPath: viewModel.defaultInstallPath)
        if viewModel.libraryFolder?.standardizedFileURL != root.appendingPathComponent("Applications").standardizedFileURL {
            external.insert("libraryFolder")
        }
        if URL(fileURLWithPath: viewModel.nxnativePath).standardizedFileURL != root.appendingPathComponent("nxnative").standardizedFileURL {
            external.insert("engineFolder")
        }
        return SettingsCatalog.changed(in: settings.settings, externalChanges: external)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            if rows.isEmpty {
                Text(L10n.text("Nothing changed yet."))
                    .seleneFont(19)
                    .foregroundColor(SeleneTheme.ink60)
            }
            SettingsDescriptorList(rows: rows, onOpenGroup: onOpenGroup)
        }
        .onAppear(perform: publishActions)
        .onChange(of: rows.map(\.id)) { _ in publishActions() }
    }

    private func publishActions() {
        onActions(SettingsDescriptorList.actions(rows, onOpenGroup: onOpenGroup))
    }
}

/// Catalog rows with their group as a chip; A or a click opens the group.
struct SettingsDescriptorList: View {
    let rows: [SettingDescriptor]
    let onOpenGroup: (SettingsSection) -> Void
    @Environment(\.seleneCanvas) private var canvas

    static func title(_ row: SettingDescriptor) -> String { "\(row.group.title) · \(L10n.text(row.title))" }

    static func actions(_ rows: [SettingDescriptor],
                        onOpenGroup: @escaping (SettingsSection) -> Void) -> [SettingsRowAction] {
        rows.map { row in
            SettingsRowAction(id: row.id, title: title(row), rowID: row.id) { onOpenGroup(row.group) }
        }
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            ForEach(rows) { row in
                SeleneRow(Self.title(row), id: row.id, subtitle: row.about) {
                    MaterialIconView(.chevron, size: 24)
                        .foregroundColor(SeleneTheme.ink60)
                }
                .contentShape(Rectangle())
                .onTapGesture { onOpenGroup(row.group) }
            }
        }
    }
}
