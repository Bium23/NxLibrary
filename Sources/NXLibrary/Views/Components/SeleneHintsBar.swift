import SwiftUI
import NXLibraryCore

struct HintItem: Identifiable {
    /// Stable across renders: the button (or glyph) and the label.
    var id: String { "\(button?.rawValue ?? glyph?.rawValue ?? "-")|\(label)" }
    var button: PromptButton?
    var glyph: MaterialIcon?
    var label: String
    var hold: String?
    /// A mouse click on the hint, when the screen has one for it.
    var action: (() -> Void)?

    init(_ button: PromptButton?, _ label: String, glyph: MaterialIcon? = nil, hold: String? = nil,
         action: (() -> Void)? = nil) {
        self.button = button
        self.glyph = glyph
        self.label = label
        self.hold = hold
        self.action = action
    }
}

extension ConnectedPad {
    init(connected: Bool, brand: GamepadBrand) {
        guard connected else { self = .none; return }
        switch brand {
        case .nintendoSwitch: self = .nintendo
        case .xbox: self = .xbox
        case .playstation: self = .playstation
        case .generic: self = .other
        }
    }
}

struct SeleneHintsBar: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneButtonNames) private var style
    @Environment(\.seleneShowButtonHints) private var showHints
    @ObservedObject private var controller = GameControllerService.shared

    var left: [HintItem] = []
    var right: [HintItem] = []
    /// Distance from the bottom edge in Selene units: 48 (Ui.cs:267); the home screens use Selene's 40.
    var bottom: CGFloat = 48
    /// Extra inset before the left group (Spotlight's prompts carry Selene's 18 margin).
    var leftInset: CGFloat = 0

    var body: some View {
        if showHints {
            HStack(alignment: .bottom, spacing: canvas.u(22)) {
                HStack(spacing: canvas.u(22)) { ForEach(left) { item($0) } }
                    .padding(.leading, canvas.u(leftInset))
                Spacer(minLength: canvas.u(22))
                HStack(spacing: canvas.u(22)) { ForEach(right) { item($0) } }
            }
            .padding(.horizontal, canvas.u(64))
            .padding(.bottom, canvas.u(bottom))
            .frame(maxWidth: .infinity)
            // A soft shadow lifts the prompts off whatever art is behind them.
            .shadow(color: .black.opacity(0.5), radius: canvas.u(6), y: canvas.u(1))
        }
    }

    private var pad: ConnectedPad {
        ConnectedPad(connected: controller.isGamepadConnected, brand: controller.activeBrand)
    }

    @ViewBuilder
    private func item(_ item: HintItem) -> some View {
        if let action = item.action {
            content(item).contentShape(Rectangle()).onTapGesture(perform: action)
        } else {
            content(item)
        }
    }

    private func content(_ item: HintItem) -> some View {
        HStack(spacing: canvas.u(8)) {
            if let button = item.button {
                badge { Text(ButtonPrompts.label(button, style: style, connected: pad))
                    .seleneFont(13, .bold) }
            } else if let glyph = item.glyph {
                badge { MaterialIconView(glyph, size: 18) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.label)
                    .seleneFont(19)
                    .foregroundColor(SeleneTheme.ink90)
                if let hold = item.hold {
                    Text(hold).seleneFont(13).foregroundColor(SeleneTheme.ink60)
                }
            }
        }
        .shadow(color: .black.opacity(0.55), radius: canvas.u(4), y: canvas.u(1))
    }

    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundColor(SeleneTheme.scrim)
            .padding(.horizontal, canvas.u(8))
            .frame(minWidth: canvas.u(30), minHeight: canvas.u(30))
            .background(RoundedRectangle(cornerRadius: canvas.u(15), style: .continuous).fill(SeleneTheme.ink))
    }
}
