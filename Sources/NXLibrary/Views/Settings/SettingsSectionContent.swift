import SwiftUI
import NXLibraryCore

struct SettingsSectionContent: View {
    let section: SettingsSection
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var artwork: ArtworkStore
    let onViewControls: () -> Void
    let onOpenConsole: () -> Void
    let onOpenGroup: (SettingsSection) -> Void
    let onSearchSubmit: () -> Void
    let onActions: ([SettingsRowAction]) -> Void

    var body: some View {
        switch section {
        case .search:
            SettingsSearchSection(settings: settings, onOpenGroup: onOpenGroup,
                                  onSubmit: onSearchSubmit, onActions: onActions)
        case .changed:
            SettingsChangedSection(settings: settings, viewModel: viewModel,
                                   onOpenGroup: onOpenGroup, onActions: onActions)
        case .startUp:
            SettingsStartUpSection(viewModel: viewModel, settings: settings, onActions: onActions)
        case .navigation:
            SettingsNavigationSection(settings: settings, onActions: onActions)
        case .spotlight:
            SettingsSpotlightSection(settings: settings, onActions: onActions)
        case .soundMusic:
            SettingsSoundSection(settings: settings, onActions: onActions)
        case .look:
            SettingsLookSection(viewModel: viewModel, settings: settings, onActions: onActions)
        case .games:
            SettingsGamesSection(viewModel: viewModel, settings: settings, onActions: onActions)
        case .controllers:
            SettingsControllersSection(settings: settings, onActions: onActions,
                                       onViewControls: onViewControls)
        case .library:
            SettingsLibrarySection(viewModel: viewModel, settings: settings,
                                   artwork: artwork, onActions: onActions)
        case .storage:
            SettingsStorageSection(viewModel: viewModel, artwork: artwork,
                                   onActions: onActions, onOpenConsole: onOpenConsole)
        case .engine:
            SettingsEngineSection(viewModel: viewModel, onActions: onActions)
        case .about:
            SettingsAboutSection(viewModel: viewModel, onActions: onActions)
        }
    }
}

/// Selene's in-group heading: 17 SemiBold in the accent colour.
struct SettingsSubheading: View {
    @Environment(\.seleneCanvas) private var canvas
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .seleneFont(17, .semibold)
            .foregroundColor(SeleneTheme.glyph)
            .padding(.top, canvas.u(18))
            .padding(.bottom, canvas.u(4))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func seleneBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func seleneShort(_ commit: String?) -> String {
    guard let commit, !commit.isEmpty else { return "unknown" }
    return String(commit.prefix(7))
}

struct SeleneStatusLine: View {
    let ok: Bool
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .seleneFont(15, .bold)
                .foregroundColor(ok ? SeleneTheme.success : SeleneTheme.danger)
            Text(title)
                .seleneFont(15, .semibold)
                .foregroundColor(SeleneTheme.ink)
            if let detail {
                Text(detail)
                    .seleneFont(13, .regular, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }
}
