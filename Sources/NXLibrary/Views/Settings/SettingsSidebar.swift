import SwiftUI
import AppKit
import NXLibraryCore

/// Left column of Settings: app mark, name and version, then the sections under their group headings.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    var isFocused: Bool = false
    let context: AppLocale
    @Environment(\.seleneCanvas) private var canvas

    private var version: String {
        L10n.format("Version %@", [AppUpdate.versionLabel(Bundle.main.infoDictionary)], context: context)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, canvas.u(26))
            ScrollView {
                groups
            }
            .scrollIndicators(.hidden)
        }
    }

    /// App-wide groups, then one per platform (`SettingsSidebarGroup`); a heading is a label, not a stop.
    private var groups: some View {
        VStack(alignment: .leading, spacing: canvas.u(6)) {
            ForEach(SettingsSidebarGroup.all) { group in
                if let heading = group.title(in: context) {
                    Text(heading)
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(20))
                        .padding(.top, canvas.u(18))
                        .padding(.bottom, canvas.u(2))
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.sections) { section in groupRow(section) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: canvas.u(16)) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: canvas.u(48), height: canvas.u(48))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: canvas.u(2)) {
                Text(L10n.text("NX Library"))
                    .seleneFont(28, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Text(version)
                    .seleneFont(16)
                    .foregroundColor(SeleneTheme.ink.opacity(0.55))
            }
        }
    }

    private func groupRow(_ section: SettingsSection) -> some View {
        let selected = selection == section
        let lit = selected && isFocused
        return Button {
            selection = section
        } label: {
            HStack(spacing: canvas.u(16)) {
                // Selene's section icons take the row's ink, like the title.
                MaterialIconView(section.icon, size: 24)
                    .foregroundColor(lit ? SeleneTheme.onFocus : SeleneTheme.ink)
                Text(section.title(in: context))
                    .seleneFont(21, .medium)
                    .foregroundColor(lit ? SeleneTheme.onFocus : SeleneTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, canvas.u(20))
            .padding(.vertical, canvas.u(14))
            .background(
                RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
                    .fill(lit ? SeleneTheme.focus : (selected ? SeleneTheme.glass : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title(in: context))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
