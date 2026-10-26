import SwiftUI
import NXLibraryCore

public struct FileCard: View {
    public let item: GameFileItem
    public let isSelected: Bool
    public let isLocked: Bool
    public let onToggle: (() -> Void)?

    public init(item: GameFileItem, isSelected: Bool = true,
                isLocked: Bool = false, onToggle: (() -> Void)? = nil) {
        self.item = item
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected
                            ? (isLocked ? NXTheme.textSecondary : NXTheme.secondary)
                            : NXTheme.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .help(isLocked ? "The base game is required." : "Include this source")
            }

            Image(systemName: item.type.iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 18))
                .foregroundColor(colorForType(item.type))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(item.type.title)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForType(item.type).opacity(0.28))
                        .foregroundColor(.white)
                        .clipShape(Capsule())

                    if let version = item.versionString {
                        Text(version)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(NXTheme.textSecondary)
                    }

                    if let titleId = item.titleId {
                        Text("[\(titleId)]")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(NXTheme.textMuted)
                    }
                }
            }

            Spacer()

            Text(item.formattedSize)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(NXTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NXTheme.glassSurfaceElevated.opacity(0.75))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? AnyShapeStyle(NXTheme.secondary.opacity(0.45))
                        : AnyShapeStyle(NXTheme.specularRim),
                    lineWidth: isSelected ? 1.2 : 0.8
                )
        )
        .opacity(isSelected ? 1 : 0.55)
    }

    private func colorForType(_ type: SourceKind) -> Color {
        switch type {
        case .base: return NXTheme.primary
        case .update: return NXTheme.secondary
        case .dlc: return NXTheme.tertiary
        case .unknown: return NXTheme.textMuted
        }
    }
}
