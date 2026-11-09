import SwiftUI
import NXLibraryCore

struct SaveImportDetails: View {
    let source: URL
    let destination: URL
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content }
        }
        .multilineTextAlignment(.center)
        .padding(.top, canvas.u(24))
    }

    private var content: some View {
        VStack(spacing: canvas.u(18)) {
            VStack(spacing: canvas.u(13)) {
                endpoint(L10n.text("From"), folder: source)
                SaveTransferArrow()
                endpoint("To", folder: destination)
            }
            .padding(.horizontal, canvas.u(12))
            .padding(.vertical, canvas.u(10))
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
                .fill(SeleneTheme.glassLight))

            VStack(spacing: canvas.u(8)) {
                Text(L10n.text("Your current save is backed up before replacement."))
                    .seleneFont(17, .medium)
                    .foregroundColor(SeleneTheme.ink)
                Text(SavePresentation.importWarning)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineSpacing(canvas.u(3))
            }
            .padding(.horizontal, canvas.u(12))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func endpoint(_ label: String, folder: URL) -> some View {
        let path = (folder.path as NSString).abbreviatingWithTildeInPath
        return VStack(spacing: canvas.u(8)) {
            Text(verbatim: label.uppercased())
                .seleneFont(13, .semibold)
                .tracking(canvas.u(1.2))
                .foregroundColor(SeleneTheme.ink60)
            // Give long directory names a natural wrap point after each slash.
            Text(verbatim: path.replacingOccurrences(of: "/", with: "/\u{200B}"))
                .seleneFont(17)
                .lineSpacing(canvas.u(2))
                .foregroundColor(SeleneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, canvas.u(12))
                .padding(.vertical, canvas.u(10))
                .frame(maxWidth: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: canvas.u(10), style: .continuous)
                        .strokeBorder(SeleneTheme.ink15, lineWidth: 1 / displayScale)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .help(folder.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(folder.path)
    }
}

private struct SaveTransferArrow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.controlActiveState) private var windowState
    @State private var start = Date()

    var body: some View {
        Group {
            if reduceMotion || systemReduceMotion || windowState == .inactive {
                glyph.foregroundStyle(SeleneTheme.ink60)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tick in
                    litGlyph(at: tick.date.timeIntervalSince(start))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var glyph: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: canvas.u(22), weight: .light))
            .scaleEffect(x: 1, y: 1.22)
            .frame(height: canvas.u(28))
    }

    private func litGlyph(at elapsed: TimeInterval) -> some View {
        let centre = TileMotion.shineCentre(at: elapsed)
        let radius = TileMotion.shineHalfWidth
        return glyph.foregroundStyle(LinearGradient(
            colors: [SeleneTheme.ink60, SeleneTheme.ink.opacity(0.80), SeleneTheme.ink60],
            startPoint: UnitPoint(x: 0.5, y: centre - radius),
            endPoint: UnitPoint(x: 0.5, y: centre + radius)))
    }
}
