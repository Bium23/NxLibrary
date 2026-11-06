import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// Game options → Cheats: this game's cheat files as the host reads them, switched here while the game is not running.
/// Top to bottom: the header, notices, the master
/// switch, the list, the actions, other builds' files.
///
/// Input: Up/Down move, A (Return, Space) toggles or activates, B (or Esc) returns to Game options; in a dialog,
/// Left/Right pick the pill. A click activates a row. Files and folders dropped on the panel are added like Add cheats….
struct CheatsPanel: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let onRebuild: () -> Void
    let onClose: () -> Void

    @State private var context: CheatContext
    @State private var cheatState: CheatState?
    @State private var running: Bool
    @State private var focus = 0
    @State private var confirm: Confirm?
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    /// The last refusal or failed write, one sentence; cleared by the next action.
    @State private var message: String?
    @State private var dropTargeted = false
    @State private var keyMonitor: Any?
    /// The community list's cheats for this exact build, when it has them and none are installed.
    @State private var offer: CheatOffer?

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    enum Row: Hashable {
        case rebuild
        case master
        case download
        case cheat(String)
        case add
        case turnAllOff
        case showInFinder
        case remove
        case otherBuild(String)
    }

    /// One line of the panel: a row that takes focus, or text between rows.
    enum Line: Hashable {
        case row(Row)
        case heading(String)
        case text(title: String, about: String?, chip: String?, dim: Bool)
    }

    enum Confirm: Equatable {
        case install(data: Data, file: CheatFile, unnamed: Bool, replacing: Bool)
        case remove(build: String)
    }

    init(viewModel: AppViewModel, game: PortedGame, onRebuild: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.game = game
        self.onRebuild = onRebuild
        self.onClose = onClose
        let context = viewModel.cheatContext(for: game)
        _context = State(initialValue: context)
        _cheatState = State(initialValue: viewModel.cheatState(in: context, gameID: game.id))
        _running = State(initialValue: RunningGameMonitor.runningApplication(for: game) != nil)
    }

    // MARK: - Model

    private var lines: [Line] {
        guard context.status == .ready, let state = cheatState else { return [.row(.rebuild)] }
        var lines: [Line] = [.row(.master)]
        var section: String?
        for entry in state.file?.entries ?? [] where !entry.pairOff {
            if let next = entry.section, next != section { lines.append(.heading(next)) }
            section = entry.section
            if let broken = entry.broken {
                lines.append(.text(title: entry.name, about: "Not supported: \(broken).", chip: nil, dim: true))
                continue
            }
            switch entry.kind {
            case .label:
                lines.append(.text(title: entry.name, about: entry.note, chip: nil, dim: true))
            case .master:
                lines.append(.text(title: entry.name, about: entry.note, chip: "Always on", dim: false))
            case .cheat where entry.once:
                lines.append(.text(title: entry.name, about: "Runs once: use it in the game's Cheats panel (⌘⇧C).",
                                   chip: nil, dim: true))
            case .cheat:
                lines.append(.row(.cheat(entry.name)))
            }
        }
        if state.file != nil {
            lines += [.row(.add), .row(.turnAllOff), .row(.showInFinder), .row(.remove)]
        } else {
            // Shown only when the list has cheats for this very build: otherwise the panel is as it was.
            lines += (offer == nil ? [] : [.row(.download)]) + [.row(.add), .row(.showInFinder)]
        }
        if !state.otherBuilds.isEmpty {
            lines.append(.heading("Other versions"))
            lines += state.otherBuilds.map { .row(.otherBuild($0)) }
        }
        return lines
    }

    private var rows: [Row] {
        lines.compactMap { if case .row(let row) = $0 { row } else { nil } }
    }

    private var notices: [String] {
        var notices: [String] = []
        if case .needsRebuild(let why) = context.status { notices.append(why + " Rebuild to use cheats.") }
        if running { notices.append(CheatCopy.running(gameName: game.name)) }
        else if cheatState?.safeModePending == true { notices.append(CheatCopy.safeMode) }
        return notices
    }

    private var entries: [String: CheatEntry] {
        Dictionary((cheatState?.file?.entries ?? []).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Body

    var body: some View {
        let lines = self.lines
        let rows = self.rows
        return ZStack {
            SeleneTheme.scrim65
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("CHEATS")
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(8))
                    Text(game.name)
                        .seleneFont(40)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                        .padding(.leading, canvas.u(6))
                    Text(CheatCopy.header(version: context.version, buildID: context.buildID))
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(8))
                    Text(CheatCopy.about)
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink60)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, canvas.u(8))
                        .padding(.top, canvas.u(4))
                        .padding(.bottom, canvas.u(14))
                    noticeArea
                    list(lines, rows: rows)
                }
                .frame(width: canvas.u(1040), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, canvas.u(90))
                .padding(.bottom, canvas.u(20))
                .contentShape(Rectangle())

                SeleneHintsBar(left: [HintItem(.b, "Back", action: close)], right: [HintItem(.a, "Select")],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: canvas.u(16), style: .continuous)
                    .stroke(SeleneTheme.focus, lineWidth: canvas.u(3))
                    .padding(canvas.u(24))
                    .opacity(dropTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            )

            if let confirm {
                confirmOverlay(confirm)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: confirm)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: drop)
        .onAppear(perform: installKeyMonitor)
        .task(id: context.buildID) {
            guard let found = await viewModel.cheatOffer(for: context), cheatState?.file == nil else { return }
            // The row arrives above Add: a focus below it keeps its row.
            let at = rows.firstIndex(of: .add)
            offer = found
            if let at, focus >= at { focus += 1 }
        }
        .onDisappear(perform: removeKeyMonitor)
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        // The host owns the files while the game runs; a quit, a launch or a return to NX Library re-reads them.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in reload() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    @ViewBuilder private var noticeArea: some View {
        let notices = self.notices
        if !notices.isEmpty || message != nil {
            VStack(alignment: .leading, spacing: canvas.u(8)) {
                ForEach(notices, id: \.self) { notice in
                    Label {
                        Text(notice).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        MaterialIconView(.info, size: 20)
                    }
                    .seleneFont(16)
                    .foregroundColor(SeleneTheme.ink75)
                }
                if let message {
                    Text(message)
                        .seleneFont(16, .medium)
                        .foregroundColor(SeleneTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, canvas.u(10))
            .padding(.bottom, canvas.u(14))
        }
    }

    private func list(_ lines: [Line], rows: [Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: canvas.u(8)) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        lineView(line, rows: rows)
                    }
                }
                .padding(.top, canvas.u(6))
                .padding(.bottom, canvas.u(24))
            }
            .scrollIndicators(.hidden)
            .onChange(of: focus) { index in
                guard rows.indices.contains(index) else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(rows[index], anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: Line, rows: [Row]) -> some View {
        switch line {
        case .heading(let title):
            Text(title.uppercased())
                .seleneFont(14, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.leading, canvas.u(10))
                .padding(.top, canvas.u(14))
        case .text(let title, let about, let chip, let dim):
            SeleneOptionRow(icon: nil, title: title, about: about, focused: false, enabled: !dim) {
                if let chip { SeleneValueChip(text: chip) }
            }
            .accessibilityElement(children: .combine)
        case .row(let row):
            let index = rows.firstIndex(of: row) ?? 0
            rowView(row, focused: index == focus)
                .id(row)
                .contentShape(Rectangle())
                .onTapGesture {
                    focus = index
                    activate(row)
                }
        }
    }

    private func rowView(_ row: Row, focused: Bool) -> some View {
        let text = describe(row)
        return SeleneOptionRow(icon: text.icon, title: text.title, about: text.about, focused: focused,
                               destructive: text.destructive, enabled: text.enabled) {
            if let isOn = text.isOn {
                SeleneSwitch(isOn: .constant(isOn)).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text.title, text.about].compactMap { $0 }.joined(separator: ". "))
        .accessibilityValue(text.isOn.map { $0 ? "On" : "Off" } ?? "")
        .accessibilityAddTraits(.isButton)
    }

    private func describe(_ row: Row) -> (icon: MaterialIcon?, title: String, about: String?, isOn: Bool?,
                                          destructive: Bool, enabled: Bool) {
        let writable = !running
        switch row {
        case .rebuild:
            return (.build, "Rebuild", "Build a new app with this engine; the old app stays if the build fails.", nil, false, true)
        case .master:
            return (.casino, "Cheats", "Off keeps every cheat from running, whatever is switched on.",
                    cheatState?.masterOn ?? true, false, writable)
        case .cheat(let key):
            let entry = entries[key]
            return (nil, entry.map(CheatCopy.title(of:)) ?? key, entry?.note,
                    cheatState?.enabled.contains(key) ?? false, false, writable)
        case .download:
            let count = offer?.file.summary.cheats ?? 0
            return (.download, count == 1 ? "Download 1 cheat" : "Download \(count) cheats",
                    "Made for this version, from the \(CheatDatabase.name) community list. Every cheat starts off.",
                    nil, false, writable)
        case .add:
            return (.add, "Add cheats…", "A .txt cheat file, or a folder in SD-card layout. You can also drop them here.",
                    nil, false, writable)
        case .turnAllOff:
            return (.power, "Turn all off", "Every cheat off; the Cheats switch stays as it is.", nil, false, writable)
        case .showInFinder:
            return (.folder, "Show in Finder", "The folder the game reads its cheats from.", nil, false, true)
        case .remove:
            return (.delete, "Remove cheats", "This version's cheat files go to the Trash.", nil, true, writable)
        case .otherBuild(let build):
            return (.history, CheatCopy.otherBuild(build), "Select to move these files to the Trash.", nil, false, writable)
        }
    }

    private func confirmOverlay(_ target: Confirm) -> some View {
        let copy = confirmCopy(target)
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissConfirm() }
            SeleneConfirmDialog(title: copy.title, message: copy.message, confirmTitle: copy.confirm,
                                focus: $confirmFocus, onCancel: dismissConfirm, onConfirm: runConfirm)
        }
    }

    private func confirmCopy(_ target: Confirm) -> (title: String, message: String, confirm: String) {
        switch target {
        case .install(_, let file, let unnamed, let replacing):
            return CheatCopy.confirm(file: file, unnamed: unnamed, replacing: replacing, version: context.version,
                                     buildID: context.buildID ?? "")
        case .remove(let build):
            return CheatCopy.removal(build: build)
        }
    }

    // MARK: - Actions

    private func reload() {
        context = viewModel.cheatContext(for: game)
        cheatState = viewModel.cheatState(in: context, gameID: game.id)
        running = RunningGameMonitor.runningApplication(for: game) != nil
        focus = min(focus, max(rows.count - 1, 0))
    }

    private func activate(_ row: Row) {
        message = nil
        switch row {
        case .rebuild:
            onRebuild()
        case .master:
            write(click: true) { try $0.setMaster(on: !(cheatState?.masterOn ?? true)) }
        case .cheat(let key):
            var on = cheatState?.enabled ?? []
            if on.contains(key) { on.remove(key) } else { on.insert(key) }
            write(click: true) { try $0.setEnabled(on) }
        case .download:
            guard ensureWritable(), let offer else { return }
            askConfirm(.install(data: offer.data, file: offer.file, unnamed: false, replacing: cheatState?.file != nil))
        case .add:
            guard ensureWritable() else { return }
            SoundEffectService.shared.play(.click)
            addFromOpenPanel()
        case .turnAllOff:
            write(click: true) { try $0.turnAllOff() }
        case .showInFinder:
            showInFinder()
        case .remove:
            guard ensureWritable(), let build = context.buildID else { return }
            askConfirm(.remove(build: build))
        case .otherBuild(let build):
            guard ensureWritable() else { return }
            askConfirm(.remove(build: build))
        }
    }

    /// The panel refuses before asking; the store refuses again at the moment of writing.
    private func ensureWritable() -> Bool {
        guard running || RunningGameMonitor.runningApplication(for: game) != nil else { return true }
        running = true
        SoundEffectService.shared.play(.error)
        return false
    }

    /// True when the change is on disk.
    @discardableResult
    private func write(click: Bool, _ change: (CheatStore) throws -> Void) -> Bool {
        guard let store = context.store, ensureWritable() else { return false }
        defer { reload() }
        do {
            try change(store)
            if click { SoundEffectService.shared.play(.click) }
            return true
        } catch CheatStoreError.notAllowed {
            running = true
            SoundEffectService.shared.play(.error)
        } catch CheatStoreError.writeFailed(let reason) {
            message = "The cheat files were not changed: \(reason)."
            SoundEffectService.shared.play(.error)
        } catch {
            message = "The cheat files were not changed: \(error.localizedDescription)."
            SoundEffectService.shared.play(.error)
        }
        return false
    }

    private func showInFinder() {
        guard let folder = context.store?.folder else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        // A folder that does not exist yet is made, so cheat files can be put there by hand.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(context.buildID ?? "").txt")
        viewModel.revealInFinder(url: FileManager.default.fileExists(atPath: file.path) ? file : folder)
    }

    private func addFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add cheats for \(game.name)"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .folder]
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            message = nil
            guard ensureWritable() else { return }
            add(urls.sorted { $0.path < $1.path })
        }
        return true
    }

    /// Every added file goes through CheatInstall: the one to install is confirmed with its summary, or the reason it
    /// is not is said in one sentence.
    private func add(_ urls: [URL]) {
        let found = viewModel.cheatCandidates(urls)
        let decisions = found.map { viewModel.cheatDecision(for: $0.url, titleIDInPath: $0.titleIDInPath, context: context) }
        switch CheatInstall.pick(decisions) {
        case .file(let index, let unnamed):
            let file: CheatFile
            switch decisions[index] {
            case .install(let parsed), .confirmUnnamed(let parsed): file = parsed
            default: return
            }
            guard let data = try? Data(contentsOf: found[index].url) else {
                refuse("NX Library could not read the file.")
                return
            }
            askConfirm(.install(data: data, file: file, unnamed: unnamed, replacing: cheatState?.file != nil))
        case .several:
            refuse(CheatCopy.several)
        case .nothing(let decision):
            refuse(decision.flatMap { CheatCopy.refusal($0, gameName: game.name, buildID: context.buildID ?? "") }
                   ?? CheatCopy.noFile)
        }
    }

    private func refuse(_ sentence: String) {
        message = sentence
        SoundEffectService.shared.play(.error)
    }

    private func askConfirm(_ target: Confirm) {
        confirmFocus = .cancel
        confirm = target
    }

    private func dismissConfirm() {
        SoundEffectService.shared.play(.focus)
        confirm = nil
    }

    private func runConfirm() {
        guard let target = confirm else { return }
        confirm = nil
        let done: Bool
        switch target {
        case .install(let data, _, _, let replacing):
            done = write(click: false) { try $0.install(data, replacing: replacing) }
        case .remove(let build):
            done = write(click: false) { try $0.remove(build: build) }
        }
        if done { SoundEffectService.shared.play(.success) }
    }

    // MARK: - Input

    private func move(by delta: Int) {
        let next = min(max(focus + delta, 0), max(rows.count - 1, 0))
        guard next != focus else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    private func activateFocused() {
        let rows = self.rows
        guard rows.indices.contains(focus) else { return }
        activate(rows[focus])
    }

    private func close() {
        SoundEffectService.shared.play(.focus)
        onClose()
    }

    private func moveConfirmFocus(_ to: SeleneConfirmButton) {
        guard confirmFocus != to else { return }
        confirmFocus = to
        SoundEffectService.shared.play(.focus)
    }

    private func handleGamepad(_ action: GamepadAction) {
        if confirm != nil {
            switch action {
            case .navigateLeft: moveConfirmFocus(.cancel)
            case .navigateRight: moveConfirmFocus(.confirm)
            case .confirm: confirmFocus == .confirm ? runConfirm() : dismissConfirm()
            case .cancel, .secondaryAction, .menu: dismissConfirm()
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: move(by: -1)
        case .navigateDown: move(by: 1)
        case .confirm: activateFocused()
        case .cancel, .secondaryAction, .menu: close()
        default: break
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.gameForSettingsSheet?.id == game.id,
                  viewModel.gameWithInstallFailure == nil, viewModel.settingsNotice == nil,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil, !(window.firstResponder is NSText) else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 36, 76, 49: action = .confirm
            case 53: action = .cancel
            default: return event
            }
            handleGamepad(action)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
