import SwiftUI
import NXLibraryCore

/// "Let's get NX Library ready" (Selene's SetupScreen): a card per thing NX Library
/// needs, rising in one after another; the focused card's story in a fixed panel
/// below; Install all and Continue. It checks again every few seconds, so a step
/// finished elsewhere ticks over by itself.
struct SetupCheckView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var model: SetupCheckModel
    let isFirstRun: Bool

    @State var focus: SetupFocus = .carryOn
    @State var focusPlaced = false
    @State var confirming = false
    @State var confirmFocus: SeleneConfirmButton = .confirm
    @State var shakes = 0
    @State private var risen = false
    @State private var popping: Set<SetupItemID> = []

    static let cardSize = CGSize(width: 240, height: 140)
    static let gap: CGFloat = 18

    init(viewModel: AppViewModel, isFirstRun: Bool) {
        self.viewModel = viewModel
        self.isFirstRun = isFirstRun
        _model = StateObject(wrappedValue: SetupCheckModel(viewModel: viewModel))
    }

    var items: [SetupItem] { model.items }
    var rows: [Int] { SetupGrid.rowCounts(items.count) }
    var setup: SetupCheckModel { model }

    var body: some View {
        ZStack {
            SeleneBackdrop()
            VStack(spacing: 0) {
                Text("Let's get NX Library ready")
                    .seleneFont(46, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Text("NX Library checks what it needs. You can come back here anytime from the menu: Setup check.")
                    .seleneFont(19)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(10))
                grid.padding(.top, canvas.u(46))
                panel.padding(.top, canvas.u(34))
                buttons.padding(.top, canvas.u(30))
            }
            .modifier(Shake(amount: CGFloat(shakes)))
            .offset(y: canvas.u(-20))
            VStack {
                Spacer(minLength: 0)
                SeleneHintsBar(right: isFirstRun ? [HintItem(.a, "Select")] : [HintItem(.a, "Select"), HintItem(.b, "Back")],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
            if confirming { confirmLayer }
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .onAppear {
            model.startRechecking()
            withAnimation(nil) { risen = false }
            DispatchQueue.main.async { risen = true }
        }
        .onDisappear {
            model.stopRechecking()
            model.rememberStates()
        }
        .onChange(of: items.map(\.state)) { _ in placeInitialFocus() }
        .onChange(of: model.justReady) { ready in pop(ready) }
        .onReceive(NotificationCenter.default.publisher(for: .nxSetupCheckGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    // MARK: - Cards

    private var grid: some View {
        VStack(spacing: canvas.u(Self.gap)) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row, count in
                HStack(spacing: canvas.u(Self.gap)) {
                    let start = rows.prefix(row).reduce(0, +)
                    ForEach(start..<(start + count), id: \.self) { index in
                        card(items[index], index: index)
                    }
                }
            }
        }
    }

    private func card(_ item: SetupItem, index: Int) -> some View {
        let focused = focus == .card(index)
        return VStack(spacing: 0) {
            MaterialIconView(Self.icon(item.id), size: 26)
                .foregroundColor(SeleneTheme.glyph)
                .frame(height: canvas.u(30))
            Text(item.title)
                .seleneFont(18, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.top, canvas.u(8))
            StatusChip(item: item, popping: popping.contains(item.id))
                .padding(.top, canvas.u(10))
            Spacer(minLength: 0)
        }
        .padding(.top, canvas.u(20))
        .padding(.horizontal, canvas.u(16))
        .frame(width: canvas.u(Self.cardSize.width), height: canvas.u(Self.cardSize.height))
        .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.cardRadius), style: .continuous)
            .fill(SeleneTheme.glassCard))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.cardRadius), style: .continuous)
            .strokeBorder(focused ? SeleneTheme.focus : SeleneTheme.ink15,
                          lineWidth: canvas.u(focused ? 3 : 1)))
        .shadow(color: focused ? SeleneTheme.focusGlow : .clear, radius: canvas.u(18))
        .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? nil : SeleneTheme.focusIn, value: focused)
        .opacity(risen ? 1 : 0)
        .offset(y: risen || reduceMotion ? 0 : canvas.u(24))
        .animation(reduceMotion ? nil : SeleneTheme.standard.delay(0.14 + Double(index) * 0.045), value: risen)
        .contentShape(Rectangle())
        .onHover { if $0 { move(to: .card(index)) } }
        .onTapGesture { move(to: .card(index)); activate() }
    }

    static func icon(_ id: SetupItemID) -> MaterialIcon {
        switch id {
        case .xcode: return .build
        case .metal: return .monitor
        case .dotnet: return .terminal
        case .engine: return .rocket
        case .runtime: return .storage
        case .keys: return .key
        case .library: return .folder
        }
    }

    private func pop(_ ready: Set<SetupItemID>) {
        guard !ready.isEmpty, !reduceMotion else { return }
        popping.formUnion(ready)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { popping.subtract(ready) }
    }

    // MARK: - Panel

    private var panel: some View {
        let story = panelStory
        return HStack(alignment: .top, spacing: canvas.u(22)) {
            MaterialIconView(story.icon, size: 34)
                .foregroundColor(story.tone)
                .frame(width: canvas.u(40))
            VStack(alignment: .leading, spacing: canvas.u(6)) {
                HStack(spacing: canvas.u(12)) {
                    Text(story.title).seleneFont(24, .semibold).foregroundColor(SeleneTheme.ink)
                    Text(story.state.uppercased())
                        .seleneFont(13, .bold)
                        .foregroundColor(story.tone)
                }
                Text(story.about)
                    .seleneFont(17)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text(story.detail)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let action = story.action {
                HStack(spacing: canvas.u(8)) {
                    SelenePromptBadge(button: .a, height: 26)
                    Text(action).seleneFont(17, .semibold).foregroundColor(SeleneTheme.ink)
                }
            }
        }
        .padding(canvas.u(22))
        .frame(width: canvas.u(960), height: canvas.u(156), alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.cardRadius), style: .continuous)
            .fill(SeleneTheme.glass))
        .clipped()
    }

    private struct Story {
        var icon: MaterialIcon, tone: Color, title: String, state: String
        var about: String, detail: String, action: String?
    }

    private var panelStory: Story {
        switch focus {
        case .card(let index) where items.indices.contains(index):
            let item = items[index]
            return Story(icon: Self.icon(item.id), tone: StatusChip.tone(item.state), title: item.title,
                         state: StatusChip.stateName(item), about: item.about, detail: item.detail,
                         action: item.actionTitle)
        case .installAll:
            let names = missingNames
            if model.installAllRunning, let progress = model.installAllProgress {
                return Story(icon: .sync, tone: SeleneTheme.glyph, title: "Install all", state: progress,
                             about: names.isEmpty ? "Finishing…" : names.joined(separator: " · "),
                             detail: "Each card shows how it is going.", action: nil)
            }
            if names.isEmpty {
                return Story(icon: .check, tone: SeleneTheme.success, title: "Install all", state: "Done",
                             about: "Everything NX Library can install by itself is installed.",
                             detail: "Xcode, your keys and your library folder stay with you.", action: nil)
            }
            return Story(icon: .sync, tone: SeleneTheme.glyph, title: "Install all", state: "\(names.count) to go",
                         about: names.joined(separator: " · "),
                         detail: "Xcode, your keys and your library folder stay with you.", action: "Install all")
        default:
            let ready = items.filter { $0.state == .ready }.count
            let left = items.filter { $0.state != .ready }.map(\.title)
            if left.isEmpty {
                return Story(icon: .check, tone: SeleneTheme.success, title: "All set", state: "Ready",
                             about: "Everything NX Library needs is here.", detail: "", action: isFirstRun ? "Continue" : "Done")
            }
            return Story(icon: .checklist, tone: SeleneTheme.glyph, title: "\(ready) of \(items.count) ready",
                         state: "\(left.count) left", about: "Still to do: \(left.joined(separator: ", ")).",
                         detail: "You can finish this later from the menu: Setup check. Games you already built still play.",
                         action: isFirstRun ? "Continue" : "Done")
        }
    }

    var missingNames: [String] {
        model.missingAutomatic.compactMap { id in items.first { $0.id == id }?.title }
    }

    // MARK: - Buttons

    private var buttons: some View {
        let count = model.missingAutomatic.count
        let title = model.installAllProgress ?? (count > 0 ? "Install all (\(count))" : "All installed")
        return HStack(spacing: canvas.u(22)) {
            SelenePillButton(title: title, minWidth: 240, focused: focus == .installAll,
                             enabled: count > 0 && !model.installAllRunning) {
                move(to: .installAll); activate()
            }
            .onHover { if $0 { move(to: .installAll) } }
            .opacity(model.installAllRunning ? 0.75 : 1)
            SelenePillButton(title: isFirstRun ? "Continue" : "Done", minWidth: 200, focused: focus == .carryOn) {
                move(to: .carryOn); activate()
            }
            .onHover { if $0 { move(to: .carryOn) } }
        }
    }

    private var confirmLayer: some View {
        ZStack {
            SeleneTheme.scrim65.ignoresSafeArea()
            SeleneConfirmDialog(
                title: "Install \(missingNames.count == 1 ? "1 item" : "\(missingNames.count) items")?",
                message: missingNames.joined(separator: " · ")
                    + "\n\nNX Library installs them one after another. macOS asks for your password for .NET.",
                confirmTitle: "Install all",
                focus: $confirmFocus,
                onCancel: { confirming = false },
                onConfirm: { confirming = false; model.installAll() })
        }
        .transition(.opacity)
    }
}

enum SetupFocus: Equatable {
    case card(Int), installAll, carryOn
}

/// The card's state in a word or two, coloured by state; a running action breathes.
private struct StatusChip: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let item: SetupItem
    let popping: Bool
    @State private var dim = false

    static func tone(_ state: SetupState) -> Color {
        switch state {
        case .ready: return SeleneTheme.success
        case .missing, .needsYou: return SeleneTheme.glyph
        case .working: return SeleneTheme.ink82
        case .warning: return SeleneTheme.untested
        case .failed: return SeleneTheme.danger
        }
    }

    static func stateName(_ item: SetupItem) -> String {
        item.chip.replacingOccurrences(of: "✓ ", with: "").capitalized
    }

    var body: some View {
        let tone = Self.tone(item.state)
        Text(item.chip)
            .seleneFont(12, .bold)
            .foregroundColor(tone)
            .lineLimit(1)
            .padding(.horizontal, canvas.u(10))
            .padding(.vertical, canvas.u(3))
            .background(Capsule().fill(tone.opacity(0.14)))
            .frame(maxWidth: canvas.u(200))
            .scaleEffect(popping ? 1.18 : 1)
            .animation(SeleneTheme.quick, value: popping)
            .opacity(item.state == .working && dim ? 0.45 : 1)
            .onAppear(perform: breathe)
            .onChange(of: item.state) { _ in breathe() }
    }

    private func breathe() {
        guard item.state == .working, !reduceMotion else { dim = false; return }
        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { dim = true }
    }
}

/// Selene's Ui.Shake: a short side-to-side when B or A has nothing to do.
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}
