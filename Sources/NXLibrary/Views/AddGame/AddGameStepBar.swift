import SwiftUI
import NXLibraryCore

// MARK: - Step bar

/// Three small pills: the current step solid, the finished ones with a check.
struct AddGameStepBar: View {
    @Environment(\.seleneCanvas) private var canvas

    let step: Int
    private let titles = ["Choose", "Review", "Porting"]

    var body: some View {
        HStack(spacing: canvas.u(10)) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let number = index + 1
                let current = number == step
                HStack(spacing: canvas.u(6)) {
                    if number < step {
                        MaterialIconView(.check, size: 15)
                    }
                    Text(title)
                        .seleneFont(15, current ? .semibold : .regular)
                }
                .foregroundColor(current ? SeleneTheme.onFocus : (number < step ? SeleneTheme.ink : SeleneTheme.ink60))
                .padding(.horizontal, canvas.u(16))
                .frame(height: canvas.u(32))
                .background(Capsule().fill(current ? SeleneTheme.focus : SeleneTheme.glassLight))
                .overlay(Capsule().strokeBorder(current ? Color.clear : SeleneTheme.ink15,
                                                lineWidth: max(1, canvas.u(1))))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(number), \(title)")
                .accessibilityAddTraits(current ? .isSelected : [])
            }
            Spacer()
        }
        .animation(SeleneTheme.cubicOut(0.26), value: step)
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

/// Add game's action pill, in Selene's pill look: glass at rest, the solid focus
/// colour when focused. Primary keeps a focus-coloured edge at rest so the next
/// step stays easy to find; destructive reads in soft red.
struct SeleneActionButton: View {
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let title: String
    var systemImage: String? = nil
    var kind: SeleneActionKind = .secondary
    var isEnabled: Bool = true
    var isFocused: Bool = false
    let action: () -> Void

    var body: some View {
        let solid = isFocused && isEnabled
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .seleneFont(13, .semibold)
                }
                Text(title)
                    .seleneFont(16, .semibold)
            }
            .foregroundColor(solid ? SeleneTheme.onFocus : foreground)
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background(Capsule().fill(solid ? SeleneTheme.focus : background))
            .overlay(Capsule().strokeBorder(solid ? Color.clear : border,
                                            lineWidth: isFocused && !solid ? 2 : 1))
            .shadow(color: solid ? SeleneTheme.focus.opacity(0.35) : .clear, radius: 12)
            .scaleEffect(isFocused && !reduceMotion ? 1.04 : 1)
            .animation(SeleneTheme.cubicOut(0.26), value: isFocused)
            .opacity(isEnabled ? 1 : 0.38)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .secondary: return SeleneTheme.ink
        case .destructive: return PortingPillCopy.softRed
        case .quiet: return SeleneTheme.ink75
        }
    }

    private var background: Color {
        kind == .quiet ? .clear : SeleneTheme.glass
    }

    private var border: Color {
        if isFocused { return SeleneTheme.focus }
        switch kind {
        case .primary: return SeleneTheme.focus.opacity(0.7)
        case .destructive: return PortingPillCopy.softRed.opacity(0.4)
        case .secondary: return SeleneTheme.ink15
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
