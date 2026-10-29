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

public struct ConsoleView: View {
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter

    @State private var filter: ConsoleFilter = .all
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var didCopy = false
    @State private var confirmClear = false
    @State private var focus = FocusIndex()

    private var hints: [HintItem] {
        let label: String
        switch focus.index {
        case 1: label = "Reveal Log"
        case 2: label = "Clear View"
        default: label = "Copy log"
        }
        return [HintItem(.b, "Back"), HintItem(.a, label)]
    }

    public init(viewModel: AppViewModel, router: AppRouter) {
        self.viewModel = viewModel
        self.router = router
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
        GeometryReader { geo in
            let margin = canvas.u(120)
            VStack(spacing: 0) {
                header(margin)
                toolbar(margin)
                logList(margin)
                if viewModel.settingsStore?.settings.showButtonHints ?? true {
                    SeleneHintsBar(right: hints)
                }
            }
        }
        .background(SeleneTheme.scrim)
        .onMoveCommand(perform: handleMove)
        .onExitCommand { router.back() }
        .seleneActivationKeys(activateFocused)
        .onReceive(NotificationCenter.default.publisher(for: .nxConsoleGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .confirmationDialog("Clear the console view?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Clear View", role: .destructive) {
                viewModel.logs.removeAll()
                didCopy = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The log file on disk is kept. This only clears the entries shown in the app.")
        }
    }

    private func header(_ margin: CGFloat) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Console")
                    .seleneFont(34, .bold)
                    .tracking(-1.2)
                    .foregroundColor(SeleneTheme.ink)
                Text("Build and launch output, in one place.")
                    .seleneFont(19)
                    .foregroundColor(SeleneTheme.ink60)
            }
            Spacer()
            Text("\(filteredLogs.count) of \(viewModel.logs.count) entries")
                .seleneFont(13, .semibold, design: .monospaced)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.top, 10)
        }
        .padding(.horizontal, margin)
        .padding(.top, 34)
        .padding(.bottom, 18)
    }

    private func toolbar(_ margin: CGFloat) -> some View {
        HStack(spacing: 14) {
            SeleneSegmented(selection: $filter, options: ConsoleFilter.allCases.map { ($0, $0.title) })

            searchField

            Spacer(minLength: 8)

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink60)

            actionButton(didCopy ? "Copied" : "Copy log", systemImage: didCopy ? "checkmark" : "doc.on.doc",
                         isFocused: focus.index == 0, action: copyLog)
            actionButton("Reveal Log", systemImage: "doc.text.magnifyingglass",
                         isFocused: focus.index == 1, action: viewModel.openBuildLog)
            actionButton("Clear View", systemImage: "trash",
                         isFocused: focus.index == 2,
                         tint: SeleneTheme.danger) { confirmClear = true }
        }
        .padding(.horizontal, margin)
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .seleneFont(13, .semibold)
                .foregroundColor(SeleneTheme.ink60)
            TextField("Search log entries", text: $searchText)
                .textFieldStyle(.plain)
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink.opacity(0.94))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .seleneFont(13)
                        .foregroundColor(SeleneTheme.ink60)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 250, height: 30)
        .background(SeleneTheme.glass)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionButton(_ title: String, systemImage: String,
                              isFocused: Bool,
                              tint: Color = SeleneTheme.ink.opacity(0.9),
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .seleneFont(13, .semibold)
                Text(title)
                    .seleneFont(14, .semibold)
            }
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(SeleneTheme.ink.opacity(0.06))
            .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .seleneRowFocus(isFocused, radius: 100)
        .accessibilityLabel(title)
    }

    private func logList(_ margin: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredLogs.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(filteredLogs.enumerated()), id: \.element.id) { index, entry in
                            logRow(entry)
                                .id(entry.id)
                                .background(index.isMultiple(of: 2)
                                            ? SeleneTheme.ink.opacity(0.018)
                                            : Color.clear)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .background(SeleneTheme.glassSolid)
            .overlay(
                RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                    .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous))
            .padding(.horizontal, margin)
            .padding(.bottom, 8)
            .onChange(of: viewModel.logs.count) { _ in
                guard autoScroll, let last = filteredLogs.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: filter) { _ in scrollToEnd(proxy) }
            .onChange(of: searchText) { _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard autoScroll, let last = filteredLogs.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.formattedTimestamp)
                .seleneFont(13, .regular, design: .monospaced)
                .foregroundColor(SeleneTheme.ink60.opacity(0.7))
                .frame(width: 58, alignment: .leading)

            Circle()
                .fill(color(for: entry.level))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            Text(entry.message)
                .seleneFont(14, .regular, design: .monospaced)
                .foregroundColor(color(for: entry.level))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.formattedTimestamp), \(levelName(entry.level)): \(entry.message)")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .seleneFont(34, .light)
                .foregroundColor(SeleneTheme.glyph.opacity(0.5))
            Text(viewModel.logs.isEmpty ? "No log entries yet." : "No entries match this filter.")
                .seleneFont(19, .semibold)
                .foregroundColor(SeleneTheme.ink.opacity(0.9))
            Text(viewModel.logs.isEmpty
                 ? "Builds and launches will report their output here."
                 : "Try another filter or clear the search field.")
                .seleneFont(15)
                .foregroundColor(SeleneTheme.ink60)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
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

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return SeleneTheme.ink90
        case .step: return SeleneTheme.glyph
        case .success: return SeleneTheme.success
        case .warning: return SeleneTheme.untested
        case .error: return SeleneTheme.danger
        }
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
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        SoundEffectService.shared.play(.success)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left, .up:
            moveFocus(by: -1)
        case .right, .down:
            moveFocus(by: 1)
        default:
            break
        }
    }

    private func moveFocus(by delta: Int) {
        let previous = focus.index
        focus.move(by: delta, count: 3)
        if focus.index != previous {
            SoundEffectService.shared.play(.focus)
        }
    }

    private func handleGamepad(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateUp: moveFocus(by: -1)
        case .navigateRight, .navigateDown: moveFocus(by: 1)
        case .confirm:
            activateFocused()
        case .cancel:
            router.back()
        case .menu:
            router.isMenuPresented = true
        default:
            break
        }
    }

    private func activateFocused() {
        switch focus.index {
        case 0: copyLog()
        case 1: viewModel.openBuildLog()
        case 2: confirmClear = true
        default: break
        }
    }
}
