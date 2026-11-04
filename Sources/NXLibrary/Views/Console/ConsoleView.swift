import SwiftUI
import AppKit
import NXLibraryCore

enum ConsoleFilter: String, CaseIterable, Identifiable {
    case all
    case errors
    case build
    case launch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .errors: return "Errors"
        case .build: return "Build"
        case .launch: return "Launch"
        }
    }
}

/// The console's one row of controls, left to right.
enum ConsoleControl: Hashable {
    case filter(ConsoleFilter)
    case search
    case follow
    case copy
    case diagnostics
    case reveal
    case clear

    static let all: [ConsoleControl] = ConsoleFilter.allCases.map { .filter($0) } + [.search, .follow, .copy, .diagnostics, .reveal, .clear]
}

/// The app's build and launch output, drawn like Add game over the screen it was
/// opened from (blurred by the shell) and fading in like Game options: a centred column with a small title, one
/// row of quiet controls and the log in a glass panel.
///
/// Input: Left/Right move along the controls, A runs one, Up/Down scroll the
/// log (scrolling up stops following new lines; reaching the end follows again),
/// B or Esc leaves: out of the search field or the dialog first. Nothing here
/// takes key focus until the search starts, so a local monitor maps the keys;
/// the controller arrives through `.nxConsoleGamepadAction`.
public struct ConsoleView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    private let showsHints: Bool

    @State private var filter: ConsoleFilter = .all
    @State private var searchText = ""
    @State private var follow = true
    @State private var didCopy = false
    @State private var didCopyDiagnostics = false
    @State private var confirmClear = false
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    @State private var focus: ConsoleControl = .filter(.all)
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    /// The line Up/Down last scrolled to; nil follows the end.
    @State private var scrollIndex: Int?
    @State private var scrollTarget: UUID?
    @State private var scrollTick = 0
    @State private var keyMonitor: Any?

    public init(viewModel: AppViewModel, router: AppRouter, showsHints: Bool = true) {
        self.viewModel = viewModel
        self.router = router
        self.showsHints = showsHints
    }

    private var filteredLogs: [LogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.logs.filter { entry in
            matchesFilter(entry) && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query))
        }
    }

    private func matchesFilter(_ entry: LogEntry) -> Bool {
        switch filter {
        case .all:
            return true
        case .errors:
            return entry.level == .error
        case .build:
            return entry.message.localizedCaseInsensitiveContains("build")
                || entry.message.localizedCaseInsensitiveContains("stage")
        case .launch:
            return entry.message.localizedCaseInsensitiveContains("launch")
                || entry.message.localizedCaseInsensitiveContains("game")
        }
    }

    public var body: some View {
        let logs = filteredLogs
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if !confirmClear { leave() } }
            VStack(spacing: 0) {
                column(logs)
                if showsHints {
                    SeleneHintsBar(left: [HintItem(.b, searching ? "Done" : "Back")],
                                   right: [HintItem(.a, aLabel)],
                                   bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
                        .opacity(confirmClear ? 0 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if confirmClear {
                ZStack {
                    SeleneTheme.scrim45.ignoresSafeArea()
                    SeleneConfirmDialog(title: "Clear the console?",
                                        message: "The log file on disk is kept; only the lines shown here go.",
                                        confirmTitle: "Clear",
                                        cancelTitle: "Keep",
                                        focus: $confirmFocus,
                                        onCancel: dismissClear,
                                        onConfirm: clear)
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: confirmClear)
        .onAppear(perform: appear)
        .onDisappear(perform: removeKeyMonitor)
        .onReceive(NotificationCenter.default.publisher(for: .nxConsoleGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
    }

    // MARK: - Column

    private func column(_ logs: [LogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONSOLE")
                .seleneFont(15, .semibold)
                .tracking(1.2)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.leading, canvas.u(8))
            HStack(alignment: .firstTextBaseline) {
                Text("Build and launch output")
                    .seleneFont(40)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: canvas.u(20))
                Text(countLine(logs))
                    .seleneFont(15)
                    .monospacedDigit()
                    .foregroundColor(SeleneTheme.ink60)
            }
            .padding(.horizontal, canvas.u(6))
            controls
                .padding(.top, canvas.u(14))
                .padding(.bottom, canvas.u(16))
            logPanel(logs)
        }
        .frame(width: canvas.u(1240), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas.u(90))
        .padding(.bottom, canvas.u(28))
        // Clicks inside the column are not clicks on the shade.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func countLine(_ logs: [LogEntry]) -> String {
        let errors = viewModel.logs.filter { $0.level == .error }.count
        let lines = logs.count == viewModel.logs.count ? "\(logs.count) lines" : "\(logs.count) of \(viewModel.logs.count) lines"
        return errors == 0 ? lines : "\(lines) · \(errors) \(errors == 1 ? "error" : "errors")"
    }

    private var controls: some View {
        HStack(spacing: canvas.u(6)) {
            ForEach(ConsoleFilter.allCases) { item in
                pill(.filter(item)) {
                    Text(item.title)
                        .seleneFont(15, filter == item ? .semibold : .regular)
                        .foregroundColor(filter == item ? SeleneTheme.ink : SeleneTheme.ink60)
                }
                .background(Capsule().fill(filter == item ? SeleneTheme.glassLight : Color.clear))
            }
            Spacer(minLength: canvas.u(20))
            pill(.search) {
                HStack(spacing: canvas.u(8)) {
                    MaterialIconView(.search, size: 16)
                        .foregroundColor(SeleneTheme.ink60)
                    if searching {
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .seleneFont(15)
                            .foregroundColor(SeleneTheme.ink)
                            .focused($searchFocused)
                            .onSubmit(endSearch)
                    } else {
                        Text(searchText.isEmpty ? "Search" : searchText)
                            .seleneFont(15)
                            .foregroundColor(searchText.isEmpty ? SeleneTheme.ink60 : SeleneTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: canvas.u(200), alignment: .leading)
            }
            .background(Capsule().fill(SeleneTheme.glassLight))
            pill(.follow) {
                HStack(spacing: canvas.u(8)) {
                    Circle()
                        .fill(follow ? PortingLogBox.softGreen : SeleneTheme.ink25)
                        .frame(width: canvas.u(7), height: canvas.u(7))
                    Text("Follow")
                        .seleneFont(15)
                        .foregroundColor(follow ? SeleneTheme.ink : SeleneTheme.ink60)
                }
            }
            pill(.copy) {
                Text(didCopy ? "Copied" : "Copy log")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink)
            }
            pill(.diagnostics) {
                Text(didCopyDiagnostics ? "Copied" : "Copy diagnostics")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink)
            }
            pill(.reveal) {
                Text("Show in Finder")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink)
            }
            pill(.clear) {
                Text("Clear")
                    .seleneFont(15)
                    .foregroundColor(PortingPillCopy.softRed)
            }
        }
        .padding(.horizontal, canvas.u(4))
    }

    /// A quiet capsule: no fill of its own, the Selene focus ring when focused.
    private func pill<Label: View>(_ control: ConsoleControl, @ViewBuilder label: () -> Label) -> some View {
        label()
            .padding(.horizontal, canvas.u(16))
            .frame(height: canvas.u(36))
            .contentShape(Capsule())
            .seleneRowFocus(focus == control && !confirmClear, radius: canvas.u(18))
            .onTapGesture {
                focus = control
                activate(control)
            }
            .accessibilityAddTraits(.isButton)
    }

    private func logPanel(_ logs: [LogEntry]) -> some View {
        let radius = canvas.u(18)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if logs.isEmpty {
                        emptyState
                    } else {
                        ForEach(logs) { entry in
                            logRow(entry).id(entry.id)
                        }
                    }
                }
                .padding(.vertical, canvas.u(16))
            }
            .scrollIndicators(.hidden)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: canvas.u(14))
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: canvas.u(14))
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(SeleneTheme.glassLight))
            .onAppear { scrollToEnd(proxy, animated: false) }
            .onChange(of: viewModel.logs.count) { _ in
                if follow { scrollToEnd(proxy, animated: false) }
            }
            .onChange(of: filter) { _ in resetScroll(proxy) }
            .onChange(of: searchText) { _ in resetScroll(proxy) }
            .onChange(of: scrollTick) { _ in
                if let scrollTarget {
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                        proxy.scrollTo(scrollTarget, anchor: .center)
                    }
                } else {
                    scrollToEnd(proxy, animated: true)
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: canvas.u(16)) {
            Text(entry.formattedTimestamp)
                .seleneFont(12, .regular, design: .monospaced)
                .foregroundColor(SeleneTheme.ink25)
                .frame(width: canvas.u(64), alignment: .leading)
            Text(entry.message)
                .seleneFont(13, entry.level == .step ? .medium : .regular, design: .monospaced)
                .foregroundColor(color(for: entry.level))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, canvas.u(24))
        .padding(.vertical, canvas.u(3))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.formattedTimestamp), \(levelName(entry.level)): \(entry.message)")
    }

    private var emptyState: some View {
        VStack(spacing: canvas.u(8)) {
            MaterialIconView(.terminal, size: 30)
                .foregroundColor(SeleneTheme.ink25)
            Text(viewModel.logs.isEmpty ? "Nothing yet" : "No lines match")
                .seleneFont(19, .medium)
                .foregroundColor(SeleneTheme.ink82)
            Text(viewModel.logs.isEmpty
                 ? "Portings and launches write here."
                 : "Try another filter or search.")
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink60)
        }
        .frame(maxWidth: .infinity, minHeight: canvas.u(360))
    }

    private func levelName(_ level: LogLevel) -> String {
        switch level {
        case .info: return "info"
        case .step: return "step"
        case .success: return "success"
        case .warning: return "warning"
        case .error: return "error"
        }
    }

    /// Soft, never vivid: the porting log's colours.
    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return SeleneTheme.ink75
        case .step: return SeleneTheme.ink
        case .success: return PortingLogBox.softGreen
        case .warning: return Color(hex: 0xF0D29A)
        case .error: return PortingPillCopy.softRed
        }
    }

    // MARK: - Scrolling

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = filteredLogs.last else { return }
        DispatchQueue.main.async {
            withAnimation(animated && !reduceMotion ? SeleneTheme.quick : nil) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func resetScroll(_ proxy: ScrollViewProxy) {
        scrollIndex = nil
        follow = true
        scrollToEnd(proxy, animated: false)
    }

    /// Up/Down: eight lines at a time; the end follows again.
    private func scroll(by delta: Int) {
        let logs = filteredLogs
        guard !logs.isEmpty else { return }
        let current = scrollIndex ?? logs.count - 1
        let next = min(max(current + delta * 8, 0), logs.count - 1)
        if next >= logs.count - 1 {
            scrollIndex = nil
            scrollTarget = nil
            follow = true
        } else {
            scrollIndex = next
            scrollTarget = logs[next].id
            follow = false
        }
        scrollTick += 1
    }

    // MARK: - Actions

    private var aLabel: String {
        switch focus {
        case .filter(let item): return item.title
        case .search: return searching ? "Done" : "Search"
        case .follow: return follow ? "Stop following" : "Follow"
        case .copy: return "Copy log"
        case .diagnostics: return "Copy diagnostics"
        case .reveal: return "Show in Finder"
        case .clear: return "Clear"
        }
    }

    private func move(by delta: Int) {
        let all = ConsoleControl.all
        let current = all.firstIndex(of: focus) ?? 0
        let next = min(max(current + delta, 0), all.count - 1)
        guard next != current else { return }
        focus = all[next]
        SoundEffectService.shared.play(.focus)
    }

    private func activate(_ control: ConsoleControl) {
        switch control {
        case .filter(let item):
            guard filter != item else { return }
            filter = item
            SoundEffectService.shared.play(.key)
        case .search:
            searching ? endSearch() : startSearch()
        case .follow:
            follow.toggle()
            if follow {
                scrollIndex = nil
                scrollTarget = nil
                scrollTick += 1
            }
            SoundEffectService.shared.play(.key)
        case .copy:
            copyLog()
        case .diagnostics:
            viewModel.copyDiagnostics()
            didCopyDiagnostics = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { didCopyDiagnostics = false }
        case .reveal:
            SoundEffectService.shared.play(.click)
            viewModel.openBuildLog()
        case .clear:
            confirmFocus = .cancel
            confirmClear = true
            SoundEffectService.shared.play(.alert)
        }
    }

    private func startSearch() {
        focus = .search
        searching = true
        SoundEffectService.shared.play(.click)
        DispatchQueue.main.async { searchFocused = true }
    }

    private func endSearch() {
        searchFocused = false
        searching = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func dismissClear() {
        confirmClear = false
        confirmFocus = .cancel
    }

    private func clear() {
        dismissClear()
        viewModel.logs.removeAll()
        didCopy = false
    }

    /// The last 200 app log lines plus the tail of the latest build log, for a bug report.
    private func copyLog() {
        var text = viewModel.logs.suffix(200)
            .map { "[\($0.formattedTimestamp)] \($0.message)" }
            .joined(separator: "\n")
        if let url = viewModel.buildLogURL,
           let build = try? String(contentsOf: url, encoding: .utf8) {
            let tail = build.split(separator: "\n", omittingEmptySubsequences: false).suffix(400)
            text += "\n\n--- Build log: \(url.lastPathComponent) ---\n" + tail.joined(separator: "\n")
        }
        guard !text.isEmpty else { return SoundEffectService.shared.play(.error) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DiagnosticsReport.scrub(text, home: NSHomeDirectory()), forType: .string)
        SoundEffectService.shared.play(.success)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }

    private func leave() {
        endSearch()
        removeKeyMonitor()
        SoundEffectService.shared.play(.back)
        router.back()
    }

    private func appear() {
        installKeyMonitor()
    }

    // MARK: - Input

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard router.route == .console,
                  !viewModel.isUpdateOfferOpen,
                  !NativeMenuCommands.shared.isTracking,
                  !router.isMenuPresented,
                  viewModel.gameToClose == nil,
                  viewModel.gameToRemove == nil,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  viewModel.gameWithInstallFailure == nil,
                  !viewModel.showSetupCheck,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return event }
            // Typing in the search: Return, Tab and Esc end it; everything else types.
            if window.firstResponder is NSText {
                guard [36, 76, 48, 53].contains(event.keyCode) else { return event }
                endSearch()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            if modifiers == .command, event.keyCode == 3 {
                startSearch()
                return nil
            }
            guard modifiers.isEmpty else { return event }
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

    private func handleGamepad(_ action: GamepadAction) {
        if confirmClear {
            switch action {
            case .navigateLeft, .navigateRight:
                let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
                if confirmFocus != next {
                    confirmFocus = next
                    SoundEffectService.shared.play(.focus)
                }
            case .confirm:
                SoundEffectService.shared.play(.click)
                confirmFocus == .confirm ? clear() : dismissClear()
            case .cancel:
                dismissClear()
            default:
                break
            }
            return
        }
        // A controller while the search is typed in: A or B ends it.
        if searching {
            if action == .confirm || action == .cancel { endSearch() }
            return
        }
        switch action {
        case .navigateLeft: move(by: -1)
        case .navigateRight: move(by: 1)
        case .navigateUp: scroll(by: -1)
        case .navigateDown: scroll(by: 1)
        case .confirm: activate(focus)
        case .cancel: leave()
        case .menu: router.isMenuPresented = true
        default: break
        }
    }
}
