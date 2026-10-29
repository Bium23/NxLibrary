import SwiftUI
import AppKit
import NXLibraryCore

struct SettingsAboutSection: View {
    @ObservedObject var viewModel: AppViewModel

    private let credits: [(name: String, role: String, url: String)] = [
        ("seedds", "nxnative engine, NVN/Metal host and ARM64 rewriter", "https://github.com/seedds/nxnative"),
        ("d2r-mobile", "Foundational native execution architecture", "https://github.com/jhaizhou-ops/d2r-mobile"),
        ("Ryujinx Team", "Maxwell shader translator and SPIR-V generator", "https://github.com/Ryujinx/Ryujinx"),
        ("Atmosphère NX", "Mesosphère kernel synchronization semantics", "https://github.com/Atmosphere-NX/Atmosphere"),
        ("LibHac", "NSP reading and PFS/HFS layered filesystem", "https://github.com/Thealexbarney/LibHac"),
        ("Khronos Group", "SPIRV-Cross Metal Shading Language compiler", "https://github.com/KhronosGroup/SPIRV-Cross")
    ]

    var body: some View {
        VStack(spacing: 12) {
            SelenePanel("NX Library") {
                Text("A personal macOS front-end for building and launching your own Switch games with nxnative.")
                    .seleneFont(16)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Version \(version) · Build \(buildDate) · Engine \(seleneShort(viewModel.pinnedEngineCommit))")
                    .seleneFont(13, .regular, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
                Text("Play time is tracked only for launches from NX Library. Not affiliated with Nintendo.")
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
            }

            SelenePanel("Credits") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(credits, id: \.name) { credit in
                        Button {
                            if let url = URL(string: credit.url) { NSWorkspace.shared.open(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(credit.name)
                                        .seleneFont(15, .semibold)
                                        .foregroundColor(SeleneTheme.ink)
                                    Image(systemName: "arrow.up.right")
                                        .seleneFont(11)
                                        .foregroundColor(SeleneTheme.ink60)
                                }
                                Text(credit.role)
                                    .seleneFont(12)
                                    .foregroundColor(SeleneTheme.ink60)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(SeleneTheme.glass.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(credit.name), \(credit.role)")
                    }
                }
            }

            SelenePanel("Visual direction") {
                Text("Inspired by Selene (MIT) by Matthew Silva.")
                    .seleneFont(16, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Button {
                    if let url = URL(string: "https://github.com/mattxslv/Selene") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("https://github.com/mattxslv/Selene")
                        Image(systemName: "arrow.up.right")
                    }
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                }
                .buttonStyle(.plain)
                Text("Selene is a Playnite theme for Windows. No Selene name, logo, wallpaper, avatar or sound is used as NX Library branding; this is a visual adaptation in SwiftUI.")
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SelenePanel("Nintendo Store data") {
                Text("Descriptions, genres and artwork are fetched from the public Nintendo Store catalog for personal use, cached locally for seven days, and never committed or redistributed.")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The app ships no keys, ROMs, game art or Nintendo UI assets.")
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
            }

            SelenePanel("Licenses") {
                Text("NX Library is personal software released under the MIT license. nxnative, Ryujinx, SPIR-V Cross, LibHac and the other dependencies retain their own licenses through the engine.")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openProjectDocs()
                } label: {
                    HStack(spacing: 4) {
                        Text("Open project docs")
                        Image(systemName: "folder")
                    }
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                }
                .buttonStyle(.plain)

                Text("This app is not affiliated with Nintendo.")
                    .seleneFont(13, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
            }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var buildDate: String {
        let url = Bundle.main.executableURL ?? Bundle.main.bundleURL
        if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return "local"
    }

    private func openProjectDocs() {
        let docs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/NXLibrary/docs")
        if FileManager.default.fileExists(atPath: docs.path) {
            NSWorkspace.shared.open(docs)
        } else {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        }
    }
}
