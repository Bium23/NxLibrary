import SwiftUI

public struct BottomDock: View {
    @ObservedObject public var viewModel: AppViewModel

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
                        Text(item.title)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium,
                                          design: .rounded))
                    }
                    .foregroundColor(isSelected ? NXTheme.primary : NXTheme.textSecondary)
                    .frame(width: 98, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? NXTheme.primary.opacity(0.14) : Color.clear)
                    )
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Capsule()
                                .fill(NXTheme.primary)
                                .frame(width: 24, height: 3)
                                .offset(y: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .nxNoFocusRing()
                .accessibilityLabel(item.title)
                .help(item.title)
                .keyboardShortcut(KeyEquivalent(Character(String(item.tag + 1))),
                                  modifiers: [.command, .option])
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                NXTheme.glassSurface.opacity(0.92)
                Rectangle().fill(.ultraThinMaterial)
            }
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(NXTheme.borderSubtle),
            alignment: .top
        )
    }
}
