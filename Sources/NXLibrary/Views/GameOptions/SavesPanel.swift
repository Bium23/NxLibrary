import SwiftUI
import AppKit
import NXLibraryCore

struct SavesPanel: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let onClose: () -> Void
    @StateObject private var model: SavePanelModel
    @State private var target: SaveSlot = .account
    @State private var focus = 0
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    @State private var keyMonitor: Any?
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    private enum Row: Hashable {
        case open, backup, target, add, refresh, backups
        case restore(UUID), reveal(UUID)
    }
    init(viewModel: AppViewModel, game: PortedGame, onClose: @escaping () -> Void) {
        self.viewModel = viewModel; self.game = game; self.onClose = onClose
        _model = StateObject(wrappedValue: SavePanelModel(viewModel: viewModel, game: game))
    }
    private var confirming: Bool { model.preview != nil || model.restorePreview != nil }
    private var rows: [Row] {
        [.open, .backup, .target, .add, .refresh, .backups] + model.snapshots.flatMap { [.restore($0.id), .reveal($0.id)] }
    }
    var body: some View {
        ZStack {
            SeleneTheme.scrim65.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { close() }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: canvas.u(10)) {
                    Text("SAVES").seleneFont(15, .semibold).foregroundColor(SeleneTheme.ink60)
                    Text(game.name).seleneFont(40).foregroundColor(SeleneTheme.ink).lineLimit(1)
                    summary
                    notices
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: canvas.u(8)) {
                                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                                    rowView(row, focused: index == focus)
                                        .id(row)
                                        .contentShape(Rectangle())
                                        .onTapGesture { focus = index; activate(row) }
                                }
                            }.padding(.vertical, canvas.u(8))
                        }.scrollIndicators(.hidden)
                        .onChange(of: focus) { index in
                            guard rows.indices.contains(index) else { return }
                            withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(rows[index], anchor: .center) }
                        }
                    }
                }
                .frame(width: canvas.u(1040), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, canvas.u(90)).padding(.bottom, canvas.u(20))
                SeleneHintsBar(left: [HintItem(.b, "Back", action: close)], right: [HintItem(.a, "Select")],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if confirming { confirmation.zIndex(1) }
        }
        .onAppear { model.refresh(); installKeyMonitor() }
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil; model.close() }
        .onChange(of: model.preview) { _ in confirmFocus = .cancel }
        .onChange(of: model.restorePreview) { _ in confirmFocus = .cancel }
        .onChange(of: model.snapshots.count) { _ in focus = min(focus, max(0, rows.count - 1)) }
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in model.refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: canvas.u(5)) {
            Text("Installed version \(game.versionString ?? "unknown") · \(model.running ? "Game running" : model.currentDate.map { "Local save · " + SavePresentation.size(model.currentBytes) + " · " + SavePresentation.date($0) } ?? "No local save yet")")
            Text("\(model.snapshots.count) backups · \(SavePresentation.size(model.snapshots.reduce(0) { $0 + $1.byteCount })) · Kept until you manage them in Finder")
        }.seleneFont(15).foregroundColor(SeleneTheme.ink60)
    }
    private var notices: some View {
        VStack(alignment: .leading, spacing: canvas.u(7)) {
            Text(SavePresentation.closedNotice)
            if let reason = model.context?.cloudReason { Text(SaveFailure.cloudEnabled(reason).localizedDescription) }
            if model.context?.cloudReason != nil { Text(SavePresentation.cloudNotice) }
            if model.recoveryRequired { Text("Save recovery is required. Refresh to retry; Play stays blocked. Backups: \(model.backupsURL.path)") }
            if model.busy { Text("Working… Keep the game closed.") }
            if let message = model.message { Text(message).foregroundColor(SeleneTheme.ink) }
        }.seleneFont(15).foregroundColor(SeleneTheme.ink75).fixedSize(horizontal: false, vertical: true)
    }
    private func description(_ row: Row) -> (title: String, about: String?, enabled: Bool) {
        switch row {
        case .open: return ("Open folder", "The local committed save.", model.context != nil && !model.busy)
        case .backup: return ("Back up now", "Keep both account and device saves, including their metadata.", model.context != nil && !model.running && !model.recoveryRequired && !model.busy)
        case .target: return ("Import destination", SavePresentation.slotName(target) + ". Device-only games use the first option; choose Separate device save only for a game that also has an account save.", model.canMutate)
        case .add: return ("Import from…", "Choose an emulator or console export folder; preview it before replacing anything.", model.canMutate)
        case .refresh: return (model.recoveryRequired ? "Retry recovery" : "Refresh", "Read the local save and configuration again.", !model.busy)
        case .backups: return ("Show backups in Finder", model.backupsURL.path, !model.busy)
        case .restore(let id):
            let snapshot = model.snapshots.first { $0.id == id }
            return ("Restore · " + (snapshot.map { SavePresentation.date($0.created) } ?? "Backup"),
                    snapshot.map { SavePresentation.reason($0.reason) + " · " + SavePresentation.size($0.byteCount) + " · game version " + ($0.identity.version ?? "unknown") }, model.canMutate)
        case .reveal: return ("Show this backup in Finder", nil, !model.busy)
        }
    }
    private func rowView(_ row: Row, focused: Bool) -> some View {
        let description = description(row)
        return SeleneOptionRow(icon: .save, title: description.title, about: description.about,
                               focused: focused, enabled: description.enabled) { EmptyView() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([description.title, description.about].compactMap { $0 }.joined(separator: ". "))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate(row) }
    }
    @ViewBuilder private var confirmation: some View {
        if let preview = model.preview, let context = model.context {
            SeleneConfirmDialog(title: "Import this save?", message: "Your current save is kept in a backup first.", confirmTitle: "Import",
                detail: SavePresentation.importMessage(preview, destination: context.location.directory(preview.slot), version: game.versionString),
                focus: $confirmFocus, onCancel: { if !model.busy { model.cancelPreview() } },
                onConfirm: { if !model.busy { model.confirmImport() } })
                .disabled(model.busy)
        } else if let snapshot = model.restorePreview?.snapshot {
            SeleneConfirmDialog(title: "Restore this backup?", message: SavePresentation.restoreMessage(snapshot, installedVersion: game.versionString),
                confirmTitle: "Restore", focus: $confirmFocus,
                onCancel: { if !model.busy { model.cancelPreview() } }, onConfirm: { if !model.busy { model.confirmRestore() } })
                .disabled(model.busy)
        }
    }
    private func activate(_ row: Row) {
        guard !confirming, description(row).enabled else { return }
        SoundEffectService.shared.play(.click)
        switch row {
        case .open: model.showFolder()
        case .backup: model.backUp()
        case .target: target = target == .account ? .device : .account
        case .add: model.chooseImport(slot: target)
        case .refresh: model.refresh()
        case .backups: model.showBackups()
        case .restore(let id): if let snapshot = model.snapshots.first(where: { $0.id == id }) { model.prepareRestore(snapshot) }
        case .reveal(let id): model.showBackups(model.snapshots.first { $0.id == id })
        }
    }
    private func close() {
        guard !model.busy else { return }
        if model.preview != nil || model.restorePreview != nil { model.cancelPreview(); return }
        onClose()
    }
    private func handle(_ action: GamepadAction) {
        if confirming {
            guard !model.busy else { return }
            switch action {
            case .navigateLeft: confirmFocus = .cancel
            case .navigateRight: confirmFocus = .confirm
            case .cancel, .secondaryAction, .menu: close()
            case .confirm:
                if confirmFocus == .cancel { close() }
                else if model.preview != nil { model.confirmImport() }
                else if model.restorePreview != nil { model.confirmRestore() }
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: focus = max(0, focus - 1)
        case .navigateDown: focus = min(max(0, rows.count - 1), focus + 1)
        case .navigateLeft, .navigateRight:
            if rows.indices.contains(focus), rows[focus] == .target { activate(.target) }
        case .confirm: if rows.indices.contains(focus) { activate(rows[focus]) }
        case .cancel, .secondaryAction, .menu: close()
        default: break
        }
    }
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.gameForSettingsSheet?.id == game.id, let window = event.window,
                  !window.isSheet, window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText), event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
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
            handle(action); return nil
        }
    }
}
