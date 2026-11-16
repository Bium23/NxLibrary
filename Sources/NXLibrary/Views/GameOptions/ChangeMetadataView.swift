import SwiftUI
import AppKit
import NXLibraryCore

/// Game options → Edit details → Change metadata: field by field (description,
/// genres, developer, publisher, release date), Automatic (the store's value, as
/// NX Library reads it), platform-appropriate public databases and optional IGDB, or the player's
/// own text. A choice is kept in `MetadataPicks` and laid over the store's data.
/// A Steam game's Automatic is the Steam store's text; it has no Switch databases to offer,
/// and its choices go to the Steam personal store.
///
/// Input: Up/Down move, L/R (Q/E, or Left/Right) change the field, A chooses,
/// B (or Esc) returns to Game options. A click chooses.
struct ChangeMetadataView: View {
    @ObservedObject var viewModel: AppViewModel
    let subject: PersonalizationSubject
    let onClose: () -> Void

    @ObservedObject private var picks = MetadataPicks.shared
    @ObservedObject private var steamPicks = SteamPersonalizations.shared.metadata
    @ObservedObject private var steamFacts = SteamGameFacts.shared
    @ObservedObject private var igdb = IGDBSettings.shared
    @State private var igdbResult: IGDBMetadataResult?
    @State private var igdbSearching = false
    @State private var igdbAttempt = 0
    @State private var databaseResults: [MetadataDatabase: DatabaseMetadataResult] = [:]
    @State private var databaseSearching: Set<MetadataDatabase> = []
    @State private var databaseAttempts: [MetadataDatabase: Int] = [:]
    @State private var failure: String?
    @State private var field: MetadataField = .description
    @State private var focus = 0
    @State private var titleDB: TitleDBInfo?
    @State private var gameTDB: [GameTDBEntry] = []
    @State private var searching: Bool
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
        case source(Source, Int)
        case retry(Source)
        case write
    }
    enum Source: CaseIterable, Hashable {
        case titleDB, gameTDB, igdb, launchBox, theGamesDB
        var name: String {
            switch self {
            case .titleDB: return "Title DB"
            case .gameTDB: return "GameTDB"
            case .igdb: return "IGDB"
            case .launchBox: return "LaunchBox"
            case .theGamesDB: return "TheGamesDB"
            }
        }
        var database: MetadataDatabase? {
            switch self { case .launchBox: return .launchBox; case .theGamesDB: return .theGamesDB; default: return nil }
        }
    }
    private struct IGDBLookup: Hashable {
        let query: CriticRatingQuery
        let revision: UUID
        let attempt: Int
    }
    private struct DatabaseLookup: Hashable { let query: CriticRatingQuery; let attempt: Int }

    init(viewModel: AppViewModel, subject: PersonalizationSubject, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.subject = subject
        self.onClose = onClose
        // Steam games have no Switch databases to search.
        _searching = State(initialValue: subject.ported != nil)
    }

    private var pick: String? {
        _ = picks.revision; _ = steamPicks.revision
        return subject.metadataPick(field)
    }
    private var store: NintendoStoreMetadata? { subject.ported.flatMap(viewModel.storeMetadataAsFetched) }
    private var igdbQuery: CriticRatingQuery {
        if let game = subject.ported { return CriticRatingQuery(game: game, name: store?.name) }
        return CriticRatingQuery(name: subject.steam?.steamGame?.name ?? subject.name, platform: .mac, steamAppID: subject.steamAppID)
    }
    private var databaseQuery: CriticRatingQuery {
        let query = igdbQuery
        return CriticRatingQuery(name: igdbResult?.metadata?.name ?? query.name, platform: query.platform, steamAppID: query.steamAppID)
    }
    private var sources: [Source] {
        igdbQuery.platform == .mac ? [.igdb, .launchBox, .theGamesDB] : Source.allCases
    }

    /// What Automatic shows: the Nintendo or Steam store's value.
    private var automaticValue: String? {
        if let steam = subject.steam { return steamFacts.metadata(for: steam)?.value(field) }
        return MetadataOptions.list(for: field, store: store, titleDB: nil, gameTDB: []).first?.value
    }

    private func options(_ source: Source) -> [MetadataOption] {
        switch source {
        case .titleDB: return MetadataOptions.list(for: field, store: nil, titleDB: titleDB, gameTDB: [])
        case .gameTDB: return MetadataOptions.list(for: field, store: nil, titleDB: nil, gameTDB: gameTDB)
        case .igdb: return igdbResult?.metadata?.option(for: field).map { [$0] } ?? []
        case .launchBox, .theGamesDB:
            guard let database = source.database else { return [] }
            return databaseResults[database]?.preview?.option(for: field).map { [$0] } ?? []
        }
    }
    private func option(_ row: Row) -> MetadataOption? {
        guard case .source(let source, let index) = row else { return nil }
        let values = options(source)
        return values.indices.contains(index) ? values[index] : nil
    }

    private var rows: [Row] {
        var rows: [Row] = [.automatic]
        if let pick { rows.append(.yourPick(pick)) }
        for source in sources {
            rows += (0..<max(1, options(source).count)).map { .source(source, $0) }
            if (canRetry(source) && !options(source).isEmpty) || (isSearching(source) && attempts(source) > 0) { rows.append(.retry(source)) }
        }
        return rows + [.write]
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
                    Text(subject.name)
                        .seleneFont(40)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                        .padding(.leading, canvas.u(6))
                        .padding(.bottom, canvas.u(14))
                    tabs
                    Text(failure ?? sourceStatus)
                        .seleneFont(14)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(1)
                        .help(failure ?? sourceStatus)
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
                               right: rightHints,
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
        .task(id: IGDBLookup(query: igdbQuery, revision: igdb.revision, attempt: igdbAttempt)) { await searchIGDB() }
        .task(id: DatabaseLookup(query: databaseQuery, attempt: databaseAttempts[.launchBox, default: 0])) { await searchDatabase(.launchBox) }
        .task(id: DatabaseLookup(query: databaseQuery, attempt: databaseAttempts[.theGamesDB, default: 0])) { await searchDatabase(.theGamesDB) }
    }

    private var rightHints: [HintItem] {
        var hints = [HintItem(.lb, L10n.text("Previous")), HintItem(.rb, L10n.text("Next"))]
        if rows.indices.contains(focus), enabled(rows[focus]) {
            let row = rows[focus]
            let retrying: Bool
            switch row {
            case .retry: retrying = true
            case .source(let source, _): retrying = option(row) == nil && canRetry(source)
            default: retrying = false
            }
            hints.append(HintItem(.a, L10n.text(retrying ? "Retry" : "Choose")))
        }
        return hints
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
                               focused: focused, enabled: enabled(row)) {
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
        case .automatic, .retry: return .restore
        case .yourPick, .write: return .edit
        case .source: return .info
        }
    }

    private func describe(_ row: Row) -> (title: String, value: String?) {
        switch row {
        case .automatic:
            let format = subject.steam != nil ? "Steam: %@" : "Nintendo store: %@"
            return (L10n.text("Automatic"), automaticValue.map { L10n.format(format, [displayValue($0)]) } ?? L10n.text("Nothing from the store yet."))
        case .yourPick(let value):
            return (L10n.text("Your choice"), displayValue(value))
        case .source(let source, _):
            if let option = option(row) {
                let same = automaticValue?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(option.value) == .orderedSame
                var value = same ? L10n.text("Same as Automatic") : displayValue(option.value)
                if isStale(source) { value = L10n.text("Saved copy") + " · " + value }
                return (option.source, value)
            }
            let platform = source.database.flatMap { databaseResults[$0]?.preview?.platform }
            return (platform.map { "\(source.name) · \($0)" } ?? source.name, sourceMessage(source))
        case .retry(let source):
            return (L10n.format("Retry %@", [source.name]), L10n.text("Other sources and your saved choices remain available."))
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
        case .source: return false // The stored value is shown once in Your choice; sources are alternatives.
        case .write, .retry: return false
        }
    }

    // MARK: - Loading

    private func search() async {
        guard subject.ported != nil else { return }
        defer { searching = false }
        if let titleId = subject.titleId {
            let result = await TitleDBInfo.fetch(titleID: titleId)
            guard !Task.isCancelled else { return }
            preservingFocus { titleDB = result }
        }
        let names = [subject.name, store?.name, titleDB?.name].compactMap { $0 }
        // Only exact titles: a look-alike game's synopsis would be the wrong game's.
        let all = await viewModel.boxArt.pickerEntries(names: names)
        guard !Task.isCancelled else { return }
        preservingFocus {
            gameTDB = all.filter { entry in names.contains { GameTDB.normalize($0) == GameTDB.normalize(entry.title) } }
        }
    }

    private var sourceStatus: String {
        if searching || igdbSearching || !databaseSearching.isEmpty { return L10n.text("Looking for metadata…") }
        return field == .description ? L10n.text("Descriptions are shown in the source’s original language.")
            : L10n.text("Choose a source for each field.")
    }
    private func isSearching(_ source: Source) -> Bool {
        if let database = source.database { return databaseSearching.contains(database) }
        return source == .igdb ? igdbSearching : searching
    }
    private func isStale(_ source: Source) -> Bool {
        if let database = source.database { return databaseResults[database]?.isStale == true }
        return source == .igdb && igdbResult?.isStale == true
    }
    private func attempts(_ source: Source) -> Int {
        source.database.map { databaseAttempts[$0, default: 0] } ?? (source == .igdb ? igdbAttempt : 0)
    }
    private func canRetry(_ source: Source) -> Bool {
        guard !isSearching(source) else { return false }
        if let database = source.database { return databaseResults[database]?.issue == .unavailable }
        return source == .igdb && igdbResult?.issue == .unavailable
    }
    private func enabled(_ row: Row) -> Bool {
        switch row {
        case .source(let source, _): return option(row) != nil || canRetry(source)
        case .retry(let source): return !isSearching(source)
        default: return true
        }
    }
    private func sourceMessage(_ source: Source) -> String {
        if isSearching(source) { return L10n.text("Looking for metadata…") }
        if canRetry(source) { return L10n.text("Unavailable · choose this row to retry.") }
        if let database = source.database {
            guard let result = databaseResults[database] else { return L10n.text("Loading…") }
            if result.issue == .ambiguous { return L10n.text("No unique match for this edition.") }
            if result.issue == .notFound { return L10n.text("No matching game for this platform.") }
        } else if source == .igdb {
            if !igdb.isConfigured { return L10n.text("IGDB is optional · connect it in Settings → API services.") }
            if igdbResult == nil { return L10n.text("Loading…") }
            if igdbResult?.issue == .ambiguous { return L10n.text("No unique match for this edition.") }
            if igdbResult?.issue == .notFound { return L10n.text("No matching game for this platform.") }
        }
        return L10n.text("No data for this field.")
    }
    private func searchDatabase(_ database: MetadataDatabase) async {
        let query = databaseQuery
        preservingFocus { databaseResults[database] = nil; databaseSearching.insert(database) }
        let result = await DatabaseMetadataService.shared(database).load(query, forceRefresh: databaseAttempts[database, default: 0] > 0)
        guard !Task.isCancelled, query == databaseQuery else { return }
        preservingFocus { databaseResults[database] = result; databaseSearching.remove(database) }
    }

    private func searchIGDB() async {
        let query = igdbQuery, revision = igdb.revision
        let credentials = igdb.credentials
        preservingFocus { igdbResult = nil; igdbSearching = credentials != nil }
        guard let credentials else { return }
        let result = await IGDBMetadataService.shared.load(query, credentials: credentials)
        guard !Task.isCancelled, revision == igdb.revision, query == igdbQuery else { return }
        preservingFocus { igdbResult = result; igdbSearching = false }
    }

    /// Source results must not move the user's selection to a different action.
    private func preservingFocus(_ update: () throws -> Void) rethrows {
        let before = rows
        let selected = before.indices.contains(focus) ? before[focus] : nil
        try update()
        let after = rows
        if let selected, let index = after.firstIndex(of: selected) { focus = index }
        else if case .yourPick(let value) = selected,
                let index = after.firstIndex(where: { option($0)?.value == value }) {
            focus = index
        } else if case .retry(let source) = selected,
                  let index = after.firstIndex(of: .source(source, 0)) {
            focus = index
        } else { focus = 0 }
    }

    // MARK: - Choosing

    private func choose(_ row: Row) {
        switch row {
        case .automatic:
            guard pick != nil else { return }
            save(nil)
        case .yourPick:
            break
        case .source(let source, _):
            if let option = option(row) { save(option.value) }
            else if canRetry(source) { retry(source) }
            else { return }
        case .retry(let source):
            guard !isSearching(source) else { return }
            retry(source)
        case .write:
            draft = pick ?? automaticValue ?? ""
            editorFocus = .cancel
            editing = true
        }
        SoundEffectService.shared.play(.click)
    }

    private func retry(_ source: Source) {
        if let database = source.database {
            databaseSearching.insert(database); databaseAttempts[database, default: 0] += 1
        } else if source == .igdb { igdbSearching = true; igdbAttempt += 1 }
    }

    /// Keeps the value (nil: the store's), reporting a save that failed instead of showing it as chosen.
    private func save(_ value: String?) {
        do {
            try preservingFocus { try subject.pickMetadata(value, field: field, viewModel: viewModel) }
            failure = nil
        }
        catch {
            failure = error.localizedDescription
            SoundEffectService.shared.play(.error)
        }
    }

    private var editor: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { editing = false }
            SeleneConfirmDialog(title: field.title, message: subject.name, confirmTitle: L10n.text("Save"),
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
        save(text.isEmpty ? nil : text)
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
            guard viewModel.optionsGameID == subject.id, viewModel.settingsNotice == nil,
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
