import SwiftUI

// MARK: - Step bar

struct AddGameStepBar: View {
    let step: Int
    private let titles = ["Sources", "Review", "Build"]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let number = index + 1
                HStack(spacing: 8) {
                    Text("\(number)")
                        .seleneFont(12, .bold)
                        .frame(width: 17, height: 17)
                        .background(number == step ? SeleneTheme.scrim
                                    : (number < step ? SeleneTheme.success.opacity(0.16) : SeleneTheme.ink.opacity(0.10)))
                        .foregroundColor(number == step ? SeleneTheme.focus
                                         : (number < step ? SeleneTheme.success : SeleneTheme.ink.opacity(0.6)))
                        .clipShape(Circle())
                    Text(title)
                        .seleneFont(15, number == step ? .semibold : .medium)
                }
                .foregroundColor(number == step ? SeleneTheme.scrim : SeleneTheme.ink.opacity(0.5))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(number == step ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.04))
                .overlay(Capsule().strokeBorder(SeleneTheme.ink15, lineWidth: 1))
                .clipShape(Capsule())
                if index < titles.count - 1 {
                    Rectangle()
                        .fill(SeleneTheme.ink15)
                        .frame(width: 34, height: 1)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Shared actions

struct AddGameAction: Identifiable {
    let id: String
    let title: String
    let isEnabled: Bool
    let perform: () -> Void

    init(id: String, title: String, isEnabled: Bool = true,
         perform: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

enum SeleneActionKind {
    case primary, secondary, destructive, quiet
}

struct SeleneActionButton: View {
    let title: String
    var systemImage: String? = nil
    var kind: SeleneActionKind = .secondary
    var isEnabled: Bool = true
    var isFocused: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .seleneFont(13, .semibold)
                }
                Text(title)
                    .seleneFont(16, .semibold)
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 18)
            .frame(height: 37)
            .background(background)
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(isFocused ? SeleneTheme.glyph : Color.clear,
                                       lineWidth: 2)
            )
            .shadow(color: isFocused ? SeleneTheme.glyph.opacity(0.22) : .clear,
                    radius: 8)
            .opacity(isEnabled ? 1 : 0.38)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return SeleneTheme.scrim
        case .secondary: return SeleneTheme.ink.opacity(0.9)
        case .destructive: return SeleneTheme.danger
        case .quiet: return SeleneTheme.glyph
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return SeleneTheme.focus
        case .secondary: return SeleneTheme.ink.opacity(0.08)
        case .destructive: return SeleneTheme.danger.opacity(0.12)
        case .quiet: return .clear
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return .clear
        case .secondary: return SeleneTheme.ink.opacity(0.16)
        case .destructive: return SeleneTheme.danger.opacity(0.32)
        case .quiet: return .clear
        }
    }
}

// MARK: - Destination text

enum AddGameDestination {
    static func name(appName: String, gameName: String?) -> String {
        var value = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = gameName ?? "Game" }
        value = value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Game" : value
    }

    static func path(appName: String, gameName: String?) -> String {
        "~/Applications/\(name(appName: appName, gameName: gameName)).app"
    }
}
