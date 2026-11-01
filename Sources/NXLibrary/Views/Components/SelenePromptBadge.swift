import SwiftUI
import AppKit
import NXLibraryCore

/// One controller button as a prompt, everywhere prompts show: Apple's glyph for
/// the connected controller (SF Symbols, filled, ink on the scrim colour) or,
/// with no controller and Automatic names, the Mac key that does the same thing
/// as a keycap. `height` is in Selene units: 30 in the hints, 26 in the top bar.
struct SelenePromptBadge: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneButtonNames) private var style
    @ObservedObject private var controller = GameControllerService.shared

    let button: PromptButton
    var height: CGFloat = 30

    private var pad: ConnectedPad {
        ConnectedPad(connected: controller.isGamepadConnected, brand: controller.activeBrand)
    }

    var body: some View {
        if ButtonPrompts.usesKeyboard(style: style, connected: pad) {
            keycap(ButtonPrompts.keyboardKey(button))
        } else if let name = ButtonPrompts.symbol(button, style: style, connected: pad,
                                           reported: controller.buttonSymbols),
           let symbol = Self.filled(name) {
            badgeImage(symbol)
        } else {
            let label = ButtonPrompts.label(button, style: style, connected: pad)
            Text(label)
                .font(.system(size: canvas.u(height * 0.43), weight: .bold))
                .foregroundColor(SeleneTheme.scrim)
                .padding(.horizontal, canvas.u(height * 0.27))
                .frame(minWidth: canvas.u(height), minHeight: canvas.u(height))
                .background(RoundedRectangle(cornerRadius: canvas.u(height / 2), style: .continuous)
                    .fill(SeleneTheme.ink))
        }
    }

    @ViewBuilder
    private func badgeImage(_ symbol: String) -> some View {
        if symbol.hasSuffix(".fill") {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(SeleneTheme.scrim, SeleneTheme.ink)
                .font(.system(size: canvas.u(height * 0.94), weight: .semibold))
                .frame(minWidth: canvas.u(height), minHeight: canvas.u(height))
                .accessibilityLabel(ButtonPrompts.label(button, style: style, connected: pad))
        } else {
            Image(systemName: symbol)
                .font(.system(size: canvas.u(height * 0.5), weight: .bold))
                .foregroundColor(SeleneTheme.scrim)
                .frame(minWidth: canvas.u(height), minHeight: canvas.u(height))
                .background(Circle().fill(SeleneTheme.ink))
                .accessibilityLabel(ButtonPrompts.label(button, style: style, connected: pad))
        }
    }

    /// A Mac key: a rounded square (not the round controller buttons), ink with the
    /// key's symbol or printed text in the scrim colour.
    private func keycap(_ key: KeyCap) -> some View {
        Group {
            switch key {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: canvas.u(height * 0.5), weight: .bold))
            case .text(let text):
                Text(text)
                    .font(.system(size: canvas.u(height * (text.count > 2 ? 0.4 : 0.47)), weight: .semibold))
            }
        }
        .foregroundColor(SeleneTheme.scrim)
        .padding(.horizontal, canvas.u(height * 0.24))
        .frame(minWidth: canvas.u(height), minHeight: canvas.u(height))
        .background(RoundedRectangle(cornerRadius: canvas.u(height * 0.24), style: .continuous)
            .fill(SeleneTheme.ink))
        .accessibilityLabel(ButtonPrompts.label(button, style: style, connected: pad))
    }

    /// The filled variant when the system has it (it reads as a badge), else the
    /// outline; nil for a name this macOS does not know, so the text pill shows.
    private static var cache: [String: String?] = [:]

    static func filled(_ name: String) -> String? {
        if let known = cache[name] { return known }
        let candidates: [String]
        if name.hasSuffix(".fill") {
            candidates = [name]
        } else if name.contains(".circle") || name.contains(".rectangle") {
            candidates = [name + ".fill", name]
        } else {
            candidates = [
                name + ".circle.fill",
                name + ".circle",
                name + ".fill",
                name
            ]
        }
        let resolved = candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
        cache[name] = resolved
        return resolved
    }
}
