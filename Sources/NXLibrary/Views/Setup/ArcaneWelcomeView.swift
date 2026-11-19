import SwiftUI
import AppKit
import NXLibraryCore

/// "Welcome to Arcane", once, for players who update from NX Library: the new name, what's new, Steam
/// when it is found and still off (Add / Not now) and Open library. Every exit marks it shown.
struct ArcaneWelcomeView: View {
    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion
    /// Whether the Steam source is already on; then nothing is read and nothing is offered.
    let steamEnabled: Bool
    let steamRoot: URL
    let appsFolder: URL
    let onAddSteam: () -> Void
    let onExit: (ArcaneWelcome.Exit) -> Void

    @StateObject var reader = FirstRunFindingsReader()
    @State var focus: ArcaneWelcome.Focus = .openLibrary
    @State var moved = false
    /// Add or Not now was chosen: the offer row leaves.
    @State var offerAnswered = false

    var offer: ArcaneWelcome.Offer? {
        guard !offerAnswered else { return nil }
        return ArcaneWelcome.offer(steamEnabled: steamEnabled, steamGameCount: reader.findings?.steamGameCount)
    }

    private static let news: [(MaterialIcon, String)] = [
        (.gamepad, "Steam games for Mac in the same library"),
        (.trophy, "Achievements, with rarity and crystal trophies"),
        (.star, "Critic scores and metadata from more sources"),
        (.settings, "Settings regrouped: General, Library, Porting, System")
    ]

    var body: some View {
        ZStack {
            SeleneBackdrop()
            VStack(spacing: 0) {
                Text(L10n.text("Welcome to Arcane")).seleneFont(46, .semibold).foregroundColor(SeleneTheme.ink)
                    .multilineTextAlignment(.center)
                Text(L10n.format("%@ has a new name: your games and settings are right where you left them.",
                                 [AppIdentity.formerName]))
                    .seleneFont(19).foregroundColor(SeleneTheme.ink75)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, canvas.u(10))

                newsCard.padding(.top, canvas.u(30))
                if let offer { offerRow(offer).padding(.top, canvas.u(12)).transition(.opacity) }

                SelenePillButton(title: L10n.text("Open library"), minWidth: 220,
                                 focused: focus == .openLibrary) { activate(.openLibrary) }
                    .onHover { if $0 { move(to: .openLibrary) } }
                    .padding(.top, canvas.u(30))
            }
            .frame(width: canvas.u(900))
            .offset(y: canvas.u(-20))
            .animation(reduceMotion ? nil : SeleneTheme.standard, value: offer)

            VStack {
                Spacer(minLength: 0)
                SeleneHintsBar(right: [HintItem(.a, L10n.text("Select")), HintItem(.b, L10n.text("Close"))],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .onAppear {
            guard !steamEnabled else { return }
            reader.start(steamRoot: steamRoot, appsFolder: appsFolder)
        }
        .onDisappear { reader.cancel() }
        .onChange(of: offer) { _, next in
            // The offer arrives after the read: it takes the first focus unless the player already moved.
            if next != nil, !moved { focus = ArcaneWelcome.Focus.initial(offer: next) }
            if next == nil, focus != .openLibrary { focus = .openLibrary }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxArcaneWelcomeGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handle(action)
        }
    }

    private var newsCard: some View {
        VStack(alignment: .leading, spacing: canvas.u(14)) {
            Text(L10n.text("What's new")).seleneFont(17, .semibold).foregroundColor(SeleneTheme.ink60)
            ForEach(Self.news, id: \.1) { icon, line in
                HStack(spacing: canvas.u(14)) {
                    MaterialIconView(icon, size: 22).foregroundColor(SeleneTheme.ink75)
                    Text(L10n.text(line)).seleneFont(19).foregroundColor(SeleneTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(canvas.u(26))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeleneTheme.glass.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: canvas.u(18), style: .continuous))
    }

    private func offerRow(_ offer: ArcaneWelcome.Offer) -> some View {
        let count: Int
        switch offer { case .steam(let gameCount): count = gameCount }
        return HStack(spacing: canvas.u(16)) {
            MaterialIconView(.gamepad, size: 26).foregroundColor(SeleneTheme.ink75)
            VStack(alignment: .leading, spacing: canvas.u(4)) {
                Text(L10n.count("Found %lld Steam games", count)).seleneFont(20, .semibold).foregroundColor(SeleneTheme.ink)
                Text(L10n.text("Adding them doesn't change Steam's files.")).seleneFont(16).foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            SelenePillButton(title: L10n.text("Add"), minWidth: 120, height: 50, focused: focus == .add) { activate(.add) }
                .onHover { if $0 { move(to: .add) } }
            SelenePillButton(title: L10n.text("Not now"), minWidth: 120, height: 50, focused: focus == .notNow) {
                activate(.notNow)
            }
            .onHover { if $0 { move(to: .notNow) } }
        }
        .padding(.horizontal, canvas.u(26))
        .padding(.vertical, canvas.u(18))
        .background(SeleneTheme.glass.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: canvas.u(18), style: .continuous))
    }
}
