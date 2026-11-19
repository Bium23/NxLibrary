import SwiftUI
import AppKit
import NXLibraryCore

/// The first launch's first page: what is already on the Mac (Steam, ported apps), the Porting card and
/// Open library. It reads without changing anything; the switches apply only on Open library.
struct FoundGamesSetupView: View {
    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion
    @ObservedObject var viewModel: AppViewModel
    let steamRoot: URL
    /// The Steam switch lives in `FirstRunSetup`, so it survives the Porting path; the shell applies it.
    let onOpenLibrary: (_ importPorted: Bool) -> Void

    @StateObject var reader = FirstRunFindingsReader()
    @State var focus: FirstRunSetup.Focus = .initialOnFound

    var findings: FirstRunFindings? { reader.findings }
    var steamCount: Int? { findings?.steamGameCount }
    var hasSteam: Bool { steamCount != nil || findings?.steamReadFailed == true }
    var portedCount: Int { findings?.portedAppCount ?? 0 }
    var isReading: Bool { findings == nil }
    var steamOn: Bool { viewModel.firstRunSetup.steamChoice ?? true }

    private var title: String {
        if isReading { return L10n.text("Looking at your Mac…") }
        return findings?.isEmpty == true ? L10n.text("No games found") : L10n.text("Here's what's on your Mac")
    }

    private var subtitle: String {
        if isReading { return L10n.text("Arcane reads Steam and your Game apps folder without changing anything. You can open the library now and add sources later in Settings.") }
        return findings?.isEmpty == true
            ? L10n.text("Steam and ported apps aren't here yet. Add them later from Settings → Sources or with Porting.")
            : L10n.text("Arcane looked without changing anything. Choose what goes in your library.")
    }

    var body: some View {
        ZStack {
            SeleneBackdrop()
            VStack(spacing: 0) {
                Text(title).seleneFont(46, .semibold).foregroundColor(SeleneTheme.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle).seleneFont(19).foregroundColor(SeleneTheme.ink75)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, canvas.u(10))

                VStack(spacing: canvas.u(12)) {
                    if let steamCount {
                        SetupCardRow(title: "Steam",
                                     detail: L10n.count("%lld installed Mac games", steamCount),
                                     icon: .store, trailing: .toggle(steamOn),
                                     focused: focus == .steamToggle,
                                     onHover: { move(to: .steamToggle) }) { activate(.steamToggle) }
                    } else if findings?.steamReadFailed == true {
                        SetupCardRow(title: "Steam",
                                     detail: L10n.text("Steam couldn't be read completely. Try again or continue and check Settings → Sources later."),
                                     icon: .store, trailing: .text(L10n.text("Retry")),
                                     focused: focus == .steamToggle,
                                     onHover: { move(to: .steamToggle) }) { activate(.steamToggle) }
                    }
                    if portedCount > 0 {
                        SetupCardRow(title: L10n.format("Already ported: %@", [String(portedCount)]),
                                     detail: L10n.text("They're in your library."),
                                     icon: .check, trailing: .none, height: 84, focused: false) {}
                            .allowsHitTesting(false)
                    }
                    SetupCardRow(title: AppIdentity.portingName,
                                 detail: L10n.text("Bring the Nintendo Switch games you own to the Mac."),
                                 note: L10n.text("Arcane is not affiliated with Nintendo."),
                                 icon: .build, focused: focus == .portingCard,
                                 onHover: { move(to: .portingCard) }) { activate(.portingCard) }
                }
                .padding(.top, canvas.u(32))

                SelenePillButton(title: L10n.text("Open library"), minWidth: 220,
                                 focused: focus == .openLibrary) {
                    activate(.openLibrary)
                }
                .onHover { if $0 { move(to: .openLibrary) } }
                .padding(.top, canvas.u(30))
            }
            .frame(width: canvas.u(960))
            .offset(y: canvas.u(-20))
            .animation(reduceMotion ? nil : SeleneTheme.standard, value: findings)

            VStack {
                Spacer(minLength: 0)
                SeleneHintsBar(right: [HintItem(.a, L10n.text("Select"))],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .onAppear {
            reader.start(steamRoot: steamRoot, appsFolder: viewModel.gameAppsFolder)
        }
        .onDisappear { reader.cancel() }
        .onChange(of: findings) { _, found in
            if found != nil, !hasSteam, focus == .steamToggle { move(to: .openLibrary) }
            // The switch starts on; that is the choice until the player turns it off.
            if found?.steamGameCount != nil, viewModel.firstRunSetup.steamChoice == nil {
                viewModel.chooseSteamOnFound(true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSetupCheckGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handle(action)
        }
    }
}
