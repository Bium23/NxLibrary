import SwiftUI
import AppKit
import NXLibraryCore

/// Left column of Settings: app mark, name and version, then the groups (Selene `SettingsScreen.cs`).
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    var isFocused: Bool = false
    @Environment(\.seleneCanvas) private var canvas

    private var version: String {
        "Version \(AppUpdate.versionLabel(Bundle.main.infoDictionary))"
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

    private var groups: some View {
        VStack(alignment: .leading, spacing: canvas.u(6)) {
            ForEach(SettingsSection.allCases) { section in
                groupRow(section)
                if section == .changed {
                    Rectangle()
                        .fill(SeleneTheme.ink.opacity(0.16))
                        .frame(height: max(1, canvas.u(1)))
                        .padding(.leading, canvas.u(20))
                        .padding(.top, canvas.u(8))
                        .padding(.trailing, canvas.u(44))
                        .padding(.bottom, canvas.u(14))
                }
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
                Text("NX Library")
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
                Text(section.title)
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
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
