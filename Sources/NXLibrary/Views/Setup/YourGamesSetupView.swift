import SwiftUI
import AppKit
import NXLibraryCore

/// The library half of first launch. It uses the same backdrop, rows, pills and input channel as Get ready.
struct YourGamesSetupView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: AppViewModel
    let onChooseFiles: () -> Void
    let onChooseFolder: () -> Void
    let onFinish: () -> Void

    @State private var focus: FirstRunSetup.Focus = .file
    @State private var focusPlaced = false

    private var libraryState: FirstRunSetup.LibraryState {
        FirstRunSetup.libraryState(isScanning: viewModel.isScanningLibrary, gameCount: viewModel.libraryGames.count)
    }
    private var folderProblem: String? { GameAppDestination.folderProblem(at: viewModel.gameAppsFolder) }
    private var title: String { libraryState == .empty ? "Add your first game" : "Your games" }
    private var subtitle: String {
        switch libraryState {
        case .scanning: return "Looking for existing game apps…"
        case .empty: return "Choose a game file, or add one later."
        case .ready:
            let count = viewModel.libraryGames.count
            return "\(count) game\(count == 1 ? "" : "s") found."
        }
    }

    var body: some View {
        ZStack {
            SeleneBackdrop()
            VStack(spacing: 0) {
                SetupStepIndicator(page: .games).padding(.bottom, canvas.u(18))
                Text(title).seleneFont(46, .semibold).foregroundColor(SeleneTheme.ink)
                Text(subtitle).seleneFont(19).foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(10))

                row(.apps, title: GameFoldersCopy.appsTitle,
                    detail: GameFoldersCopy.appsContents + "\n" + (viewModel.gameAppsFolder.path as NSString).abbreviatingWithTildeInPath,
                    icon: .folder, trailing: "Change") {
                    viewModel.selectLibraryFolder()
                }
                .help(viewModel.gameAppsFolder.path)
                .padding(.top, canvas.u(32))

                if !viewModel.isScanningLibrary, let warning = viewModel.libraryScanWarnings.first {
                    Text(warning).seleneFont(15).foregroundColor(SeleneTheme.ink75)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, canvas.u(12))
                }

                row(.file, title: "Choose game file", detail: "NSP · XCI · NSZ · XCZ", icon: .add,
                    enabled: folderProblem == nil, action: onChooseFiles)
                    .padding(.top, canvas.u(12))

                SelenePillButton(title: "Choose a folder instead", icon: .folder, iconSize: 19,
                                 minWidth: 0, height: 44, horizontalPadding: 24,
                                 focused: focus == .folder, enabled: folderProblem == nil) {
                    activate(.folder)
                }
                .onHover { if $0 { move(to: .folder) } }
                .padding(.top, canvas.u(18))

                if let folderProblem {
                    Text(folderProblem).seleneFont(15).foregroundColor(SeleneTheme.ink75)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, canvas.u(12))
                }

                HStack(spacing: canvas.u(22)) {
                    SelenePillButton(title: "Back", focused: focus == .back) { activate(.back) }
                        .onHover { if $0 { move(to: .back) } }
                    SelenePillButton(title: libraryState == .ready ? "Open library" : "Skip for now",
                                     minWidth: 220, focused: focus == .finish) { activate(.finish) }
                        .onHover { if $0 { move(to: .finish) } }
                }
                .padding(.top, canvas.u(30))
            }
            .frame(width: canvas.u(960))
            .offset(y: canvas.u(-20))

            VStack {
                Spacer(minLength: 0)
                SeleneHintsBar(left: [HintItem(.b, "Back")], right: [HintItem(.a, "Select")],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .onAppear(perform: placeInitialFocus)
        .onChange(of: viewModel.isScanningLibrary) { _ in placeInitialFocus() }
        .onReceive(NotificationCenter.default.publisher(for: .nxSetupCheckGamepadAction)) { note in
            guard let action = note.object as? GamepadAction,
                  viewModel.showSetupCheck, viewModel.firstRunSetup.page == .games,
                  NSApp.modalWindow == nil, viewModel.alertMessage == nil else { return }
            switch action {
            case .navigateLeft: move(to: focus.moved(.left))
            case .navigateRight: move(to: focus.moved(.right))
            case .navigateUp: move(to: focus.moved(.up))
            case .navigateDown: move(to: focus.moved(.down))
            case .confirm: activate(focus)
            case .cancel: activate(.back)
            default: break
            }
        }
    }

    private func row(_ target: FirstRunSetup.Focus, title: String, detail: String, icon: MaterialIcon,
                     trailing: String? = nil, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        let focused = focus == target
        return Button {
            move(to: target)
            guard enabled else { return }
            SoundEffectService.shared.play(.click)
            action()
        } label: {
            HStack(spacing: canvas.u(22)) {
                MaterialIconView(icon, size: 30).frame(width: canvas.u(40))
                VStack(alignment: .leading, spacing: canvas.u(5)) {
                    Text(title).seleneFont(22, .semibold)
                    Text(detail).seleneFont(15).foregroundColor(SeleneTheme.ink75)
                        .lineLimit(2).truncationMode(.middle)
                }
                Spacer(minLength: canvas.u(12))
                if let trailing { Text(trailing).seleneFont(16, .semibold) }
                else { MaterialIconView(.chevron, size: 22) }
            }
            .foregroundColor(SeleneTheme.ink)
            .padding(.horizontal, canvas.u(24))
            .frame(width: canvas.u(960), height: canvas.u(112))
            .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.cardRadius), style: .continuous)
                .fill(SeleneTheme.glassCard))
            .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.cardRadius), style: .continuous)
                .strokeBorder(focused ? SeleneTheme.focus : SeleneTheme.ink15, lineWidth: canvas.u(focused ? 2 : 1)))
            .shadow(color: focused ? SeleneTheme.focusGlow : .clear, radius: canvas.u(16))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { if $0 { move(to: target) } }
        .animation(reduceMotion ? nil : SeleneTheme.focusIn, value: focused)
    }

    private func move(to next: FirstRunSetup.Focus) {
        focusPlaced = true
        guard focus != next else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    private func placeInitialFocus() {
        guard !focusPlaced, !viewModel.isScanningLibrary else { return }
        focus = libraryState == .ready ? .finish : .file
        focusPlaced = true
    }

    private func activate(_ target: FirstRunSetup.Focus) {
        guard viewModel.showSetupCheck, viewModel.firstRunSetup.page == .games, NSApp.modalWindow == nil else { return }
        move(to: target)
        if (target == .file || target == .folder), folderProblem != nil {
            move(to: .apps)
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        switch target {
        case .apps: viewModel.selectLibraryFolder()
        case .file: onChooseFiles()
        case .folder: onChooseFolder()
        case .back: viewModel.returnToSetupRequirements()
        case .finish: onFinish()
        }
    }
}

struct SetupStepIndicator: View {
    @Environment(\.seleneCanvas) private var canvas
    let page: FirstRunSetup.Page

    var body: some View {
        HStack(spacing: canvas.u(14)) {
            step(1, "Get ready", active: page == .requirements)
            Capsule().fill(SeleneTheme.ink15).frame(width: canvas.u(38), height: canvas.u(1))
            step(2, "Your games", active: page == .games)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page == .requirements ? "Step 1 of 2: Get ready" : "Step 2 of 2: Your games")
    }

    private func step(_ number: Int, _ title: String, active: Bool) -> some View {
        HStack(spacing: canvas.u(8)) {
            Text(String(number)).seleneFont(13, .semibold)
                .foregroundColor(active ? SeleneTheme.onFocus : SeleneTheme.ink60)
                .frame(width: canvas.u(24), height: canvas.u(24))
                .background(Circle().fill(active ? SeleneTheme.focus : SeleneTheme.glass))
            Text(title).seleneFont(14, .semibold).foregroundColor(active ? SeleneTheme.ink : SeleneTheme.ink60)
        }
    }
}
