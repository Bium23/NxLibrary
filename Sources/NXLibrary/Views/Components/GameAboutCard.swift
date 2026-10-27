import SwiftUI
import AppKit
import NXLibraryCore

public struct GameAboutCard: View {
    @ObservedObject public var viewModel: AppViewModel
    public let game: PortedGame
    @State private var expanded = false

    public init(viewModel: AppViewModel, game: PortedGame) {
        self.viewModel = viewModel
        self.game = game
    }

    private var metadata: NintendoStoreMetadata? {
        viewModel.storeMetadata[game.id]
    }

    private var isLoading: Bool {
        viewModel.storeMetadataLoading.contains(game.id)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("About", systemImage: "storefront")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textSecondary)
                Spacer()
                if metadata != nil {
                    Text("Nintendo Store")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(NXTheme.textMuted)
                }
            }

            if let metadata {
                HStack(alignment: .top, spacing: 12) {
                    storeImage(metadata)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metadata.description)
                            .font(.system(size: 12))
                            .foregroundColor(NXTheme.textSecondary)
                            .lineLimit(expanded ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)

                        if metadata.description.count > 240 {
                            Button(expanded ? "Show less" : "Read more") {
                                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(NXTheme.primary)
                        }
                    }
                }

                HStack(spacing: 6) {
                    ForEach(Array(metadata.genres.prefix(3)), id: \.self) { genre in
                        Text(genre)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(NXTheme.primary.opacity(0.10))
                            .foregroundColor(NXTheme.primary)
                            .clipShape(Capsule())
                    }
                    if let publisher = metadata.publishers.first {
                        Text(publisher)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(NXTheme.glassSurfaceActive.opacity(0.55))
                            .foregroundColor(NXTheme.textSecondary)
                            .clipShape(Capsule())
                    }
                    if let year = metadata.releaseYear {
                        Text(year)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(NXTheme.glassSurfaceActive.opacity(0.55))
                            .foregroundColor(NXTheme.textSecondary)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    Button {
                        viewModel.openURL(metadata.storeURL)
                    } label: {
                        Label("Nintendo Store", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(NXTheme.primary)

                    if let hltb = viewModel.howLongToBeatURL(for: game) {
                        Button {
                            viewModel.openURL(hltb)
                        } label: {
                            Label("HowLongToBeat", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(NXTheme.secondary)
                    }
                    Spacer()
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading store details...")
                        .font(.system(size: 11))
                        .foregroundColor(NXTheme.textMuted)
                }
            } else {
                HStack(spacing: 12) {
                    Text("Store details unavailable.")
                        .font(.system(size: 11))
                        .foregroundColor(NXTheme.textMuted)
                    if let search = viewModel.nintendoStoreSearchURL(for: game) {
                        Button("Search Nintendo Store") { viewModel.openURL(search) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(NXTheme.primary)
                    }
                    if let hltb = viewModel.howLongToBeatURL(for: game) {
                        Button("HowLongToBeat") { viewModel.openURL(hltb) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(NXTheme.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(NXTheme.glassSurfaceElevated.opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NXTheme.borderSubtle.opacity(0.45), lineWidth: 0.8)
        )
        .cornerRadius(10)
        .task(id: game.id) {
            viewModel.loadStoreMetadata(for: game)
        }
    }

    @ViewBuilder
    private func storeImage(_ metadata: NintendoStoreMetadata) -> some View {
        if let url = metadata.headerImageURL ?? metadata.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    ZStack {
                        NXTheme.glassSurfaceActive
                        Image(systemName: "photo")
                            .foregroundColor(NXTheme.textMuted)
                    }
                }
            }
            .frame(width: 116, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NXTheme.specularRim, lineWidth: 0.8)
            )
        }
    }
}
