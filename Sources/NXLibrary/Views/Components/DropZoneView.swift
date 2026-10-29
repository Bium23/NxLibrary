import SwiftUI
import UniformTypeIdentifiers

public struct DropZoneView: View {
    @ObservedObject public var viewModel: AppViewModel
    public var isFocused: Bool
    @State private var isTargeted: Bool = false

    public init(viewModel: AppViewModel, isFocused: Bool = false) {
        self.viewModel = viewModel
        self.isFocused = isFocused
    }

    public var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(isTargeted ? SeleneTheme.glyph.opacity(0.16)
                          : SeleneTheme.ink.opacity(0.05))
                    .frame(width: 56, height: 56)
                Image(systemName: isTargeted ? "arrow.down.doc.fill"
                      : "square.and.arrow.down.on.square.fill")
                    .symbolRenderingMode(.hierarchical)
                    .seleneFont(34, .medium)
                    .foregroundColor(isTargeted ? SeleneTheme.glyph : SeleneTheme.ink60)
                    .scaleEffect(isTargeted ? 1.08 : 1)
                    .animation(SeleneTheme.quick, value: isTargeted)
            }

            VStack(spacing: 4) {
                Text(isTargeted ? "Drop to scan this folder" : "Drop your game files here")
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Text("The base game is required. Updates and DLC are optional.")
                    .seleneFont(14)
                    .foregroundColor(SeleneTheme.ink60)
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.selectGameFolder()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .seleneFont(13, .semibold)
                    Text("Choose folder")
                        .seleneFont(15, .semibold)
                }
                .foregroundColor(SeleneTheme.scrim)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(SeleneTheme.focus)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose a game folder")

            Text("NSP · XCI · NSZ · folders")
                .seleneFont(12, .semibold, design: .monospaced)
                .tracking(0.4)
                .foregroundColor(SeleneTheme.ink60.opacity(0.8))

            if let folder = viewModel.selectedGameFolder {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .seleneFont(13)
                        .foregroundColor(SeleneTheme.glyph)
                    Text(folder.path)
                        .seleneFont(13, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink90)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Change…") { viewModel.selectGameFolder() }
                        .buttonStyle(.plain)
                        .seleneFont(13, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                    Button("Clear") { viewModel.selectedGameFolder = nil }
                        .buttonStyle(.plain)
                        .seleneFont(13, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(SeleneTheme.ink.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let error = viewModel.dropErrorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .seleneFont(13)
                        .foregroundColor(SeleneTheme.untested)
                    Text(error)
                        .seleneFont(13)
                        .foregroundColor(SeleneTheme.untested)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 214)
        .background(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .fill(isTargeted ? SeleneTheme.glyph.opacity(0.07)
                      : SeleneTheme.glass.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .strokeBorder(isTargeted ? SeleneTheme.glyph : SeleneTheme.ink25,
                              style: StrokeStyle(lineWidth: isTargeted ? 1.8 : 1,
                                                 dash: [6, 4]))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .strokeBorder(isFocused ? SeleneTheme.glyph : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    defer { group.leave() }
                    if let fileURL = url { urls.append(fileURL) }
                }
            }
            group.notify(queue: .main) {
                if !urls.isEmpty { viewModel.handleDroppedURLs(urls) }
            }
            return true
        }
    }
}
