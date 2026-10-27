import SwiftUI

public struct BottomDock: View {
    @ObservedObject public var viewModel: AppViewModel
    @State private var hoveredTag: Int? = nil

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private let items: [(tag: Int, title: String, icon: String)] = [
        (0, "Library", "square.grid.2x2.fill"),
        (1, "Add Game", "plus.square.fill"),
        (2, "Controls", "gamecontroller.fill"),
        (3, "Settings", "gearshape.fill"),
        (4, "Console", "terminal.fill"),
    ]

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.tag) { item in
                let isSelected = viewModel.selectedTab == item.tag
                Button {
                    SoundEffectService.shared.play(.tabSwitch)
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.selectedTab = item.tag
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                            .shadow(color: isSelected ? NXTheme.primary.opacity(0.45) : .clear,
                                    radius: 6)
                        Text(item.title)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium,
                                          design: .rounded))
                    }
                    .foregroundColor(isSelected
                        ? NXTheme.primary
                        : (hoveredTag == item.tag ? NXTheme.textPrimary : NXTheme.textSecondary))
                    .frame(width: 98, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected
                                ? NXTheme.primary.opacity(0.16)
                                : (hoveredTag == item.tag ? NXTheme.glassSurfaceActive.opacity(0.55) : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? NXTheme.primary.opacity(0.28) : Color.clear,
                                          lineWidth: 0.8)
                    )
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Capsule()
                                .fill(NXTheme.primary)
                                .frame(width: 22, height: 3)
                                .offset(y: 2)
                                .shadow(color: NXTheme.primary.opacity(0.6), radius: 5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .nxNoFocusRing()
                .accessibilityLabel(item.title)
                .help(item.title)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.16)) {
                        if hovering {
                            hoveredTag = item.tag
                        } else if hoveredTag == item.tag {
                            hoveredTag = nil
                        }
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character(String(item.tag + 1))),
                                  modifiers: [.command, .option])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NXTheme.barGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(NXTheme.specularRim, lineWidth: 0.8)
                )
                .shadow(color: NXTheme.cardShadow, radius: 18, x: 0, y: 8)
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}
