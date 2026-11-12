import SwiftUI
import AppKit
import NXLibraryCore

struct SettingsAboutSection: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var updater: AppUpdater
    @Environment(\.seleneFocusedRowID) private var focusedRowTitle
    let onActions: ([SettingsRowAction]) -> Void

    @State private var didCopyDiagnostics = false

    private let credits: [(name: String, role: String, url: String)] = [
        ("seedds", "nxnative engine, NVN/Metal host and ARM64 rewriter", "https://github.com/seedds/nxnative"),
        ("d2r-mobile", L10n.text("Foundational native execution architecture"), "https://github.com/jhaizhou-ops/d2r-mobile"),
        ("Ryujinx Team", L10n.text("Maxwell shader translator and SPIR-V generator"), "https://github.com/Ryujinx/Ryujinx"),
        ("Atmosphère NX", L10n.text("Mesosphère kernel synchronization semantics"), "https://github.com/Atmosphere-NX/Atmosphere"),
        ("LibHac", L10n.text("NSP reading and PFS/HFS layered filesystem"), "https://github.com/Thealexbarney/LibHac"),
        ("Khronos Group", L10n.text("SPIRV-Cross Metal Shading Language compiler"), "https://github.com/KhronosGroup/SPIRV-Cross"),
        ("GameTDB", L10n.text("Switch box covers"), "https://www.gametdb.com"),
        ("Title DB", L10n.text("Game names, icons and banners"), "https://github.com/blawar/titledb"),
        ("LaunchBox Games Database", L10n.text("Box covers, logos, backgrounds and square art in Change artwork"), "https://gamesdb.launchbox-app.com"),
        ("SteamGridDB", L10n.text("Community covers, backgrounds, logos and icons, with your API key"), "https://www.steamgriddb.com"),
        ("NX2Apple", L10n.text("Key check, failure explanations and diagnostics, adapted (MIT)"), "https://github.com/LNPANDY/NX2Apple")
    ]

    var body: some View {
        VStack(spacing: 12) {
            SelenePanel(L10n.text("NX Library")) {
                Text(L10n.text("A personal macOS front-end for building and launching your own Switch games with nxnative."))
                    .seleneFont(16)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.format("Version %@ · Build %@ · Engine %@", [String(describing: (version)), String(describing: (buildDate)), String(describing: (seleneShort(viewModel.pinnedEngineCommit)))]))
                    .seleneFont(13, .regular, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
                Text(L10n.text("Play time is tracked only for launches from NX Library. Not affiliated with Nintendo."))
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
                updateRow
                Button {
                    copyDiagnostics()
                } label: {
                    HStack(spacing: 4) {
                        Text(didCopyDiagnostics ? L10n.text("Copied") : L10n.text("Copy diagnostics"))
                        Image(systemName: didCopyDiagnostics ? "checkmark" : "doc.on.doc")
                    }
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                }
                .buttonStyle(.plain)
                .padding(6)
                .seleneRowFocus(focusedRowTitle == "Copy diagnostics")
                .id("selene-row-Copy diagnostics")
                .accessibilityHint(L10n.text("A report for an issue: versions, setup and the last porting. No keys."))
            }

            SelenePanel(L10n.text("Credits")) {
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
                        .seleneRowFocus(focusedRowTitle == credit.name, radius: 7)
                        .id("selene-row-\(credit.name)")
                        .accessibilityLabel("\(credit.name), \(credit.role)")
                    }
                }
            }

            SelenePanel(L10n.text("Visual direction")) {
                Text(L10n.text("Inspired by Selene (MIT) by Matthew Silva."))
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
                .padding(6)
                .seleneRowFocus(focusedRowTitle == "Selene")
                .id("selene-row-Selene")
                Text(L10n.text("Selene is a Playnite theme for Windows. No Selene name, logo, wallpaper, avatar or sound is used as NX Library branding; this is a visual adaptation in SwiftUI."))
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SelenePanel(L10n.text("Nintendo Store data")) {
                Text(L10n.text("Descriptions, genres and artwork are fetched from the public Nintendo Store catalog for personal use, cached locally for seven days, and never committed or redistributed."))
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.text("The app ships no keys, ROMs, game art or Nintendo UI assets."))
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
            }

            SelenePanel(L10n.text("Licenses")) {
                Text(L10n.text("NX Library is personal software released under the MIT license. nxnative, Ryujinx, SPIR-V Cross, LibHac and the other dependencies retain their own licenses through the engine."))
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openProjectDocs()
                } label: {
                    HStack(spacing: 4) {
                        Text(L10n.text("Open project docs"))
                        Image(systemName: "folder")
                    }
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                }
                .buttonStyle(.plain)
                .padding(6)
                .seleneRowFocus(focusedRowTitle == "Open project docs")
                .id("selene-row-Open project docs")

                Text(L10n.text("This app is not affiliated with Nintendo."))
                    .seleneFont(13, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: updater.state) { _ in publishActions() }
        .onChange(of: viewModel.isBuilding) { _ in publishActions() }
        .onChange(of: viewModel.isCleaningStorage) { _ in publishActions() }
        .onChange(of: viewModel.hasActiveSaveOperations) { _ in publishActions() }
        .onChange(of: viewModel.isUpdatingApp) { _ in publishActions() }
        .onChange(of: viewModel.runningGameCount) { _ in publishActions() }
    }

    private func copyDiagnostics() {
        viewModel.copyDiagnostics()
        didCopyDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { didCopyDiagnostics = false }
    }

    private func publishActions() {
        var actions = updateActions.map { action in
            SettingsRowAction(id: "update-\(action.title)", title: action.title,
                              isEnabled: action.enabled, activate: action.perform)
        }
        actions.append(.init(id: "diagnostics", title: "Copy diagnostics", activate: copyDiagnostics))
        actions += credits.map { credit in
            SettingsRowAction(id: "credit-\(credit.name)", title: credit.name) {
                if let url = URL(string: credit.url) { NSWorkspace.shared.open(url) }
            }
        }
        actions.append(.init(id: "selene", title: "Selene") {
            NSWorkspace.shared.open(URL(string: "https://github.com/mattxslv/Selene")!)
        })
        actions.append(.init(id: "docs", title: "Open project docs", activate: openProjectDocs))
        onActions(actions)
    }

    // MARK: - Updates

    private struct UpdateAction {
        let title: String
        var enabled = true
        let perform: () -> Void
    }

    @ViewBuilder private var updateRow: some View {
        if updater.state != .hidden {
            HStack(spacing: 14) {
                Text(updateText)
                    .seleneFont(14)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                ForEach(updateActions, id: \.title) { action in
                    Button(action.title, action: action.perform)
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(action.enabled ? SeleneTheme.glyph : SeleneTheme.ink60)
                        .disabled(!action.enabled)
                        .padding(6)
                        .seleneRowFocus(focusedRowTitle == action.title)
                        .id("selene-row-\(action.title)")
                }
            }
        }
    }

    private var updateText: String {
        switch updater.state {
        case .hidden: return ""
        case .developer: return L10n.text("Development copy · manual checks only")
        case .readOnly: return L10n.text("Move NX Library to Applications to update")
        case .idle: return L10n.text("Updates not checked yet")
        case .checking: return "Checking for updates…"
        case .upToDate: return L10n.text("NX Library is up to date")
        case .available(let release):
            let xcode = AppUpdate.neededXcode(release.requirements, installedXcode: viewModel.environmentStatus?.xcodeVersion)
                .map { L10n.format(" · new portings need Xcode %@", [String(describing: ($0))]) } ?? ""
            return (updater.blockedReason().map { L10n.format("%@ is available · %@", [String(describing: (release.version)), String(describing: ($0))]) } ?? L10n.format("%@ is available", [String(describing: (release.version))])) + xcode
        case .downloading(let fraction): return L10n.format("Downloading %@%%", [String(describing: (Int((fraction * 100).rounded())))])
        case .verifying: return L10n.text("Checking download…")
        case .installing: return L10n.text("Installing…")
        case .failed(let message): return message
        }
    }

    private var updateActions: [UpdateAction] {
        let checkNow = UpdateAction(title: L10n.text("Check now")) { updater.checkNow() }
        switch updater.state {
        case .hidden, .checking, .downloading, .verifying, .installing:
            return []
        case .readOnly:
            return [checkNow, UpdateAction(title: L10n.text("Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }]
        case .developer, .idle, .upToDate:
            return [checkNow]
        case .available:
            return [UpdateAction(title: L10n.text("View update")) { updater.showDetails() }, checkNow]
        case .failed:
            return [checkNow]
        }
    }

    private var version: String {
        AppUpdate.versionLabel(Bundle.main.infoDictionary)
    }

    private var buildDate: String {
        let url = Bundle.main.executableURL ?? Bundle.main.bundleURL
        if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            return date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.context.formatLocale))
        }
        return "local"
    }

    private func openProjectDocs() {
        let docs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/NXLibrary/docs")
        if FileManager.default.fileExists(atPath: docs.path) {
            NSWorkspace.shared.open(docs)
        } else {
            viewModel.showSettingsNotice(title: L10n.text("Docs unavailable"), message: L10n.text("Project documentation is not installed on this Mac."))
        }
    }
}
