import SwiftUI
import NXLibraryCore

struct SettingsSectionContent: View {
    let section: SettingsSection
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var artwork: ArtworkStore
    let focusedRowTitle: String?
    let onViewControls: () -> Void
    let onOpenConsole: () -> Void
    let onActions: ([SettingsRowAction]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundColor(SeleneTheme.ink)
                Spacer()
                Text(focusedRowTitle.map { "Focused: \($0)" } ?? "Changes apply immediately")
                    .font(.system(size: 10))
                    .foregroundColor(focusedRowTitle == nil ? SeleneTheme.inkMuted : SeleneTheme.accent)
                    .lineLimit(1)
            }

            switch section {
            case .general:
                SettingsGeneralSection(viewModel: viewModel, settings: settings, onActions: onActions)
            case .appearance:
                SettingsAppearanceSection(viewModel: viewModel, settings: settings, onActions: onActions)
            case .library:
                SettingsLibrarySection(viewModel: viewModel, settings: settings,
                                       artwork: artwork, onActions: onActions)
            case .gameDefaults:
                SettingsGameDefaultsSection(viewModel: viewModel, settings: settings, onActions: onActions)
            case .controllers:
                SettingsControllersSection(settings: settings, onActions: onActions,
                                           onViewControls: onViewControls)
            case .engineKeys:
                SettingsEngineSection(viewModel: viewModel, onActions: onActions)
            case .storageLogs:
                SettingsStorageSection(viewModel: viewModel, artwork: artwork,
                                       onActions: onActions, onOpenConsole: onOpenConsole)
            case .about:
                SettingsAboutSection(viewModel: viewModel)
            }
        }
        .padding(.top, 1)
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
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ok ? SeleneTheme.success : SeleneTheme.danger)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SeleneTheme.ink)
            if let detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SeleneTheme.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }
}
