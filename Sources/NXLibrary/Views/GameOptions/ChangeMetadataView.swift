import SwiftUI
import AppKit
import NXLibraryCore

/// Game options → Edit details → Change metadata: field by field (description,
/// genres, developer, publisher, release date), Automatic (the store's value, as
/// NX Library reads it), what Title DB and GameTDB offer instead, or the player's
/// own text. A choice is kept in `MetadataPicks` and laid over the store's data.
///
/// Input: Up/Down move, L/R (Q/E, or Left/Right) change the field, A chooses,
/// B (or Esc) returns to Game options. A click chooses.
struct ChangeMetadataView: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let onClose: () -> Void

    @ObservedObject private var picks = MetadataPicks.shared
    @State private var field: MetadataField = .description
    @State private var focus = 0
    @State private var titleDB: TitleDBInfo?
    @State private var gameTDB: [GameTDBEntry] = []
    @State private var searching = true
    @State private var keyMonitor: Any?
    @State private var editing = false
    @State private var draft = ""
    @State private var editorFocus: SeleneConfirmButton = .cancel
    @FocusState private var editorHasFocus: Bool

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    enum Row: Equatable {
        case automatic
        case yourPick(String)
        case option(MetadataOption)
        case write
    }

    private var titleKey: String { game.titleId ?? game.uniqueKey }
    private var pick: String? { picks.value(titleID: titleKey, field: field) }
    private var store: NintendoStoreMetadata? { viewModel.storeMetadataAsFetched(for: game) }

    /// Automatic is the store's value, so the store's option is not listed again.
    private var options: [MetadataOption] {
        MetadataOptions.list(for: field, store: store, titleDB: titleDB, gameTDB: gameTDB)
            .filter { $0.source != "Nintendo store" }
    }

    private var rows: [Row] {
        let options = self.options
        var rows: [Row] = [.automatic]
        if let pick, !options.contains(where: { $0.value == pick }) { rows.append(.yourPick(pick)) }
        return rows + options.map(Row.option) + [.write]
    }

    // MARK: - Body

    var body: some View {
        let rows = self.rows
        return ZStack {
            SeleneTheme.scrim65
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.text("CHANGE METADATA"))
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(8))
                    Text(game.name)
                        .seleneFont(40)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                        .padding(.leading, canvas.u(6))
                        .padding(.bottom, canvas.u(14))
                    tabs
                    Text(searching ? L10n.text("Looking on Title DB and GameTDB…") : " ")
                        .seleneFont(14)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(10))
                        .padding(.vertical, canvas.u(10))
                    list(rows)
                }
                .frame(width: canvas.u(1040), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, canvas.u(90))
                .padding(.bottom, canvas.u(20))
                .contentShape(Rectangle())

                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"), action: close)],
                               right: [HintItem(.lb, L10n.text("Previous")), HintItem(.rb, L10n.text("Next")), HintItem(.a, L10n.text("Choose"))],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!editing)
            if editing { editor }
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .task { await search() }
    }

    private var tabs: some View {
        HStack(spacing: canvas.u(8)) {
            ForEach(MetadataField.allCases, id: \.self) { tab in
                Text(tab.title)
                    .seleneFont(17, .semibold)
                    .foregroundColor(tab == field ? SeleneTheme.ink : SeleneTheme.ink60)
                    .padding(.horizontal, canvas.u(20))
                    .padding(.vertical, canvas.u(9))
                    .background(Capsule().fill(tab == field ? SeleneTheme.glassSolid : Color.clear))
                    .contentShape(Capsule())
                    .onTapGesture { select(tab) }
                    .accessibilityAddTraits(tab == field ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.leading, canvas.u(2))
    }

    private func list(_ rows: [Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: canvas.u(8)) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        rowView(row, focused: index == focus)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focus = index
                                choose(row)
                            }
                    }
                }
                .padding(.top, canvas.u(6))
                .padding(.bottom, canvas.u(24))
            }
            .scrollIndicators(.hidden)
            .onChange(of: focus) { index in
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func rowView(_ row: Row, focused: Bool) -> some View {
        let text = describe(row)
        return SeleneOptionRow(icon: icon(row), title: text.title, about: excerpt(text.value, full: focused),
                               focused: focused) {
            if isCurrent(row) {
                MaterialIconView(.check, size: 26).foregroundColor(SeleneTheme.focus)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text.title). \(text.value ?? "")")
        .accessibilityAddTraits(isCurrent(row) ? [.isButton, .isSelected] : .isButton)
    }

    private func icon(_ row: Row) -> MaterialIcon? {
        switch row {
        case .automatic: return .restore
        case .yourPick, .write: return .edit
        case .option: return .info
        }
    }

    private func describe(_ row: Row) -> (title: String, value: String?) {
        switch row {
        case .automatic:
            let value = MetadataOptions.list(for: field, store: store, titleDB: nil, gameTDB: []).first?.value
            return (L10n.text("Automatic"), value.map { L10n.format("Nintendo store: %@", [displayValue($0)]) } ?? L10n.text("Nothing from the store yet."))
        case .yourPick(let value):
            return (L10n.text("Your own"), displayValue(value))
        case .option(let option):
            return (option.source, displayValue(option.value))
        case .write:
            return (L10n.text("Write your own…"), L10n.format("Type the %@ yourself.", [String(describing: (field.title.lowercased()))]))
        }
    }

    private func displayValue(_ value: String) -> String {
        field == .genres ? GameGenre.list(value.components(separatedBy: ",")).joined(separator: ", ") : value
    }

    /// Long descriptions show in full only on the focused row.
    private func excerpt(_ value: String?, full: Bool) -> String? {
        guard let value, !full, value.count > 240 else { return value }
        return String(value.prefix(240)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func isCurrent(_ row: Row) -> Bool {
        switch row {
        case .automatic: return pick == nil
        case .yourPick: return true
        case .option(let option): return option.value == pick
        case .write: return false
        }
    }

    // MARK: - Loading

    private func search() async {
        defer { searching = false }
        if let titleId = game.titleId { titleDB = await TitleDBInfo.fetch(titleID: titleId) }
        let names = [game.name, store?.name, titleDB?.name].compactMap { $0 }
        // Only exact titles: a look-alike game's synopsis would be the wrong game's.
        let all = await viewModel.boxArt.pickerEntries(names: names)
        gameTDB = all.filter { entry in names.contains { GameTDB.normalize($0) == GameTDB.normalize(entry.title) } }
    }

    // MARK: - Choosing

    private func choose(_ row: Row) {
        switch row {
        case .automatic:
            guard pick != nil else { return }
            viewModel.pickMetadata(nil, field: field, for: game)
        case .yourPick:
            break
        case .option(let option):
            viewModel.pickMetadata(option.value, field: field, for: game)
        case .write:
            draft = pick ?? MetadataOptions.list(for: field, store: store, titleDB: nil, gameTDB: []).first?.value ?? ""
            editorFocus = .cancel
            editing = true
        }
        SoundEffectService.shared.play(.click)
    }

    private var editor: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { editing = false }
            SeleneConfirmDialog(title: field.title, message: game.name, confirmTitle: L10n.text("Save"),
                focus: $editorFocus, onCancel: { editing = false }, onConfirm: saveDraft) {
                VStack(alignment: .leading, spacing: canvas.u(12)) {
                    if field == .description {
                        TextEditor(text: $draft)
                            .scrollContentBackground(.hidden)
                            .frame(height: max(120, canvas.u(200)))
                            .focused($editorHasFocus)
                    } else {
                        TextField(field.title, text: $draft)
                            .textFieldStyle(.plain)
                            .focused($editorHasFocus)
                            .onSubmit(saveDraft)
                    }
                    Text(field == .genres ? L10n.text("Separate with commas.")
                        : field == .releaseDate ? L10n.text("YYYY-MM-DD")
                        : field == .description ? L10n.text("⌘Return to save · Empty for Automatic") : L10n.text("Empty for Automatic"))
                        .seleneFont(14)
                        .foregroundColor(SeleneTheme.ink60)
                }
                .seleneFont(17)
                .foregroundColor(SeleneTheme.ink)
                .padding(canvas.u(16))
                .background(RoundedRectangle(cornerRadius: canvas.u(12)).fill(SeleneTheme.glassLight))
                .padding(.top, canvas.u(24))
                .onAppear { editorHasFocus = true }
            }
        }
    }

    private func saveDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.pickMetadata(text.isEmpty ? nil : text, field: field, for: game)
        editing = false
        SoundEffectService.shared.play(.click)
    }

    // MARK: - Input

    private func select(_ tab: MetadataField) {
        guard tab != field else { return }
        field = tab
        focus = 0
        SoundEffectService.shared.play(.focus)
    }

    private func shiftField(by delta: Int) {
        let all = MetadataField.allCases
        let index = all.firstIndex(of: field) ?? 0
        select(all[min(max(index + delta, 0), all.count - 1)])
    }

    private func move(by delta: Int) {
        let next = min(max(focus + delta, 0), rows.count - 1)
        guard next != focus else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    private func chooseFocused() {
        let rows = self.rows
        guard rows.indices.contains(focus) else { return }
        choose(rows[focus])
    }

    private func close() {
        if editing { editing = false; return }
        SoundEffectService.shared.play(.focus)
        onClose()
    }

    private func handleGamepad(_ action: GamepadAction) {
        if editing {
            switch action {
            case .navigateLeft: editorFocus = .cancel
            case .navigateRight: editorFocus = .confirm
            case .confirm: if editorFocus == .confirm { saveDraft() } else { editing = false }
            case .cancel, .menu: editing = false
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: move(by: -1)
        case .navigateDown: move(by: 1)
        case .navigateLeft, .tabPrevious: shiftField(by: -1)
        case .navigateRight, .tabNext: shiftField(by: 1)
        case .confirm: chooseFocused()
        case .cancel, .secondaryAction, .menu: close()
        default: break
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.gameForSettingsSheet?.id == game.id, viewModel.settingsNotice == nil,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return event }
            if editing {
                if event.keyCode == 53 { editing = false; return nil }
                if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command) { saveDraft(); return nil }
                return event
            }
            guard !(window.firstResponder is NSText) else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 126: move(by: -1)
            case 125: move(by: 1)
            case 123, 12: shiftField(by: -1)
            case 124, 14: shiftField(by: 1)
            case 36, 76, 49: chooseFocused()
            case 53: close()
            default: return event
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
