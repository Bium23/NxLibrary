import SwiftUI
import NXLibraryCore

struct SaveImportDetails: View {
    let source: URL
    let destination: URL
    @Environment(\.seleneCanvas) private var canvas

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
                endpoint("From", folder: source)
                Image(systemName: "arrow.down")
                    .font(.system(size: canvas.u(22), weight: .light))
                    .foregroundColor(SeleneTheme.ink60)
                    .accessibilityHidden(true)
                endpoint("To", folder: destination)
            }
            .padding(.horizontal, canvas.u(24))
            .padding(.vertical, canvas.u(20))
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
                .fill(SeleneTheme.glassLight))

            VStack(spacing: canvas.u(8)) {
                Text("Your current save is backed up before replacement.")
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
        return VStack(spacing: canvas.u(5)) {
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
        }
        .frame(maxWidth: .infinity)
        .help(folder.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(folder.path)
    }
}
