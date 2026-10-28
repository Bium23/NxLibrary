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
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter

    @State private var filter: ConsoleFilter = .all
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var didCopy = false
    @State private var confirmClear = false
    @State private var focus = FocusIndex()

    private var hints: [CommandHint] {
        let label: String
        switch focus.index {
        case 1: label = "Reveal Log"
        case 2: label = "Clear View"
        default: label = "Copy"
        }
        return [CommandHint("B", "Back"), CommandHint("A", label)]
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
            let metrics = SeleneLayoutMetrics(width: geo.size.width)
            VStack(spacing: 0) {
                header(metrics)
                toolbar(metrics)
                logList(metrics)
                if viewModel.settingsStore?.settings.showButtonHints ?? true {
                    CommandBar(hints)
                }
            }
        }
        .background(SeleneTheme.canvas)
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

    private func header(_ metrics: SeleneLayoutMetrics) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Console")
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-1.2)
                    .foregroundColor(SeleneTheme.ink)
                Text("Build and launch output, in one place.")
                    .font(.system(size: 13))
                    .foregroundColor(SeleneTheme.inkMuted)
            }
            Spacer()
            Text("\(filteredLogs.count) of \(viewModel.logs.count) entries")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(SeleneTheme.inkMuted)
                .padding(.top, 10)
        }
        .padding(.horizontal, metrics.margin)
        .padding(.top, 34)
        .padding(.bottom, 18)
    }

    private func toolbar(_ metrics: SeleneLayoutMetrics) -> some View {
        HStack(spacing: 14) {
            SeleneSegmented(selection: $filter, options: ConsoleFilter.allCases.map { ($0, $0.title) })

            searchField

            Spacer(minLength: 8)

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.system(size: 10.5))
                .foregroundColor(SeleneTheme.inkMuted)

            actionButton("Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc",
                         isFocused: focus.index == 0, action: copyVisibleLogs)
            actionButton("Reveal Log", systemImage: "doc.text.magnifyingglass",
                         isFocused: focus.index == 1, action: viewModel.openBuildLog)
            actionButton("Clear View", systemImage: "trash",
                         isFocused: focus.index == 2,
                         tint: SeleneTheme.danger) { confirmClear = true }
        }
        .padding(.horizontal, metrics.margin)
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(SeleneTheme.inkMuted)
            TextField("Search log entries", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundColor(SeleneTheme.ink.opacity(0.94))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SeleneTheme.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 250, height: 30)
        .background(SeleneTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SeleneTheme.border, lineWidth: 1)
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
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(SeleneTheme.ink.opacity(0.06))
            .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .seleneCapsuleFocus(isFocused)
        .accessibilityLabel(title)
    }

    private func logList(_ metrics: SeleneLayoutMetrics) -> some View {
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
            .background(SeleneTheme.canvasRaised)
            .overlay(
                RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                    .strokeBorder(SeleneTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous))
            .padding(.horizontal, metrics.margin)
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
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(SeleneTheme.inkMuted.opacity(0.7))
                .frame(width: 58, alignment: .leading)

            Circle()
                .fill(color(for: entry.level))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            Text(entry.message)
                .font(.system(size: 10.5, design: .monospaced))
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
                .font(.system(size: 30, weight: .light))
                .foregroundColor(SeleneTheme.accent.opacity(0.5))
            Text(viewModel.logs.isEmpty ? "No log entries yet." : "No entries match this filter.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SeleneTheme.ink.opacity(0.9))
            Text(viewModel.logs.isEmpty
                 ? "Builds and launches will report their output here."
                 : "Try another filter or clear the search field.")
                .font(.system(size: 11))
                .foregroundColor(SeleneTheme.inkMuted)
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
        case .info: return SeleneTheme.inkSecondary
        case .step: return SeleneTheme.accent
        case .success: return SeleneTheme.success
        case .warning: return SeleneTheme.warning
        case .error: return SeleneTheme.danger
        }
    }

    private func copyVisibleLogs() {
        let lines = filteredLogs.map { "[\($0.formattedTimestamp)] \($0.message)" }
        guard !lines.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
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
        case 0: copyVisibleLogs()
        case 1: viewModel.openBuildLog()
        case 2: confirmClear = true
        default: break
        }
    }
}
