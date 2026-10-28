import SwiftUI
import NXLibraryCore

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    var isFocused: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Categories")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundColor(SeleneTheme.inkMuted)
                .padding(.leading, 14)
                .padding(.bottom, 9)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 17)
                        Text(section.title)
                            .font(.system(size: 13, weight: selection == section ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundColor(selection == section
                                     ? SeleneTheme.ink
                                     : SeleneTheme.ink.opacity(0.52))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(selection == section
                                ? SeleneTheme.ink.opacity(0.06)
                                : Color.clear)
                    .overlay(alignment: .leading) {
                        if selection == section {
                            Capsule()
                                .fill(SeleneTheme.focus)
                                .frame(width: 2, height: 16)
                                .padding(.leading, 5)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .seleneFocus(isFocused && selection == section, radius: 9)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}
