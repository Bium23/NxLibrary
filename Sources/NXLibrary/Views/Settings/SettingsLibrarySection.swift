import SwiftUI
import NXLibraryCore

struct SettingsLibrarySection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var artwork: ArtworkStore
    let onActions: ([SettingsRowAction]) -> Void

    @State private var metadataBytes: Int64 = 0
    @State private var artworkBytes: Int64 = 0

    var body: some View {
        VStack(spacing: 9) {
            SeleneRow("Game ROMs folder",
                      subtitle: "Where NX Library looks for NSP, XCI and NSZ files.") {
                HStack(spacing: 10) {
                    Text(viewModel.selectedGameFolder?.path ?? "Not selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SeleneTheme.ink.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .trailing)
                    Button("Choose") { viewModel.selectGameFolder() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.glyph)
                    if viewModel.selectedGameFolder != nil {
                        Button("Clear") { viewModel.selectedGameFolder = nil }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(SeleneTheme.danger)
                    }
                }
            }

            SeleneRow("App library folder",
                      subtitle: "Where built Mac apps are installed and discovered.") {
                HStack(spacing: 10) {
                    Text(viewModel.libraryFolder?.path ?? "Default")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SeleneTheme.ink.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .trailing)
                    Button("Change") { viewModel.selectLibraryFolder() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.glyph)
                    Button("Reset") {
                        viewModel.libraryFolder = URL(fileURLWithPath: viewModel.defaultInstallPath)
                            .appendingPathComponent("Applications")
                        viewModel.loadLibrary()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink60)
                }
            }

            SeleneButtonRow("Existing builds",
                            subtitle: "Scan the app library for nxnative builds made outside NX Library.",
                            info: "Searches your Applications folder for standalone game .app bundles that were compiled with nxnative CLI or previous workflows, and registers them into NX Library.",
                            buttonTitle: "Import") {
                viewModel.importExistingBuilds()
            }

            SeleneButtonRow("Library refresh",
                            subtitle: viewModel.isScanningLibrary
                                ? "Scanning the app library..." : "Rescan folders for new or removed apps.",
                            buttonTitle: "Refresh") {
                viewModel.refreshLibrary()
            }

            SeleneValueRow("Metadata cache",
                           subtitle: "Nintendo Store descriptions, genres and links.",
                           info: "Locally cached game metadata such as title IDs, publisher names, release dates, and category tags fetched during library scans.",
                           value: seleneBytes(metadataBytes),
                           actionTitle: "Clear") {
                viewModel.clearMetadataCache()
                metadataBytes = viewModel.metadataCacheSize()
            }

            SeleneValueRow("Artwork cache",
                           subtitle: "Hero and cover art downloaded for this library.",
                           info: "High-resolution game box art and hero wallpapers cached locally from the Nintendo Store catalog.",
                           value: seleneBytes(artworkBytes),
                           actionTitle: "Clear") {
                artwork.clear()
                artworkBytes = artwork.cacheSize()
            }
        }
        .task {
            metadataBytes = viewModel.metadataCacheSize()
            artworkBytes = artwork.cacheSize()
        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .init(id: "romChoose", title: "Game ROMs folder") {
                viewModel.selectGameFolder()
            },
            .init(id: "appsChange", title: "App library folder") {
                viewModel.selectLibraryFolder()
            },
            .init(id: "import", title: "Existing builds") {
                viewModel.importExistingBuilds()
            },
            .init(id: "refresh", title: "Library refresh", isEnabled: !viewModel.isScanningLibrary) {
                viewModel.refreshLibrary()
            },
            .init(id: "metadataClear", title: "Metadata cache") {
                viewModel.clearMetadataCache()
                metadataBytes = viewModel.metadataCacheSize()
            },
            .init(id: "artworkClear", title: "Artwork cache") {
                artwork.clear()
                artworkBytes = artwork.cacheSize()
            }
        ])
    }
}
