import SwiftUI
import AppKit
import NXLibraryCore

/// One source's grid as the Theme screen browses it: the state, and its pages
/// loading in the background. The screen never waits on the network.
@MainActor
final class OnlineBrowser: ObservableObject {
    @Published private(set) var state: OnlineBrowseState?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var task: Task<Void, Never>?

    func open(_ source: BackgroundSourceID) {
        reset()
        state = OnlineBrowseState(source: source)
        loadIfWanted()
    }

    func close() {
        reset()
        state = nil
    }

    /// Changes the state; a new category or search drops the page on its way.
    @discardableResult
    func update(_ change: (inout OnlineBrowseState) -> Bool) -> Bool {
        guard var next = state else { return false }
        let before = (next.categoryIndex, next.query)
        let changed = change(&next)
        if (next.categoryIndex, next.query) != before {
            task?.cancel()
            loading = false
            failed = false
        }
        state = next
        loadIfWanted()
        return changed
    }

    private func reset() {
        task?.cancel()
        task = nil
        loading = false
        failed = false
    }

    private func loadIfWanted() {
        guard let state, state.wantsMore, !loading, !failed else { return }
        let key = (state.source, state.category, state.query, state.nextPage)
        loading = true
        task = Task { [weak self] in
            let page = try? await OnlineBackgroundService.shared.page(key.0, category: key.1, query: key.2, page: key.3)
            guard let self, !Task.isCancelled, var current = self.state, current.source == key.0,
                  current.category == key.1, current.query == key.2, current.nextPage == key.3 else { return }
            self.loading = false
            if let page {
                current.append(page)
                self.state = current
                self.loadIfWanted()
            } else {
                self.failed = true
            }
        }
    }
}

/// The download of the chosen item, with its progress. Cancelling forgets it.
@MainActor
final class OnlineTransfer: ObservableObject {
    @Published private(set) var itemID: String?
    @Published private(set) var progress: Double = 0
    private var task: Task<Void, Never>?

    func start(_ item: OnlineBackground, done: @escaping (Result<String, Error>) -> Void) {
        task?.cancel()
        itemID = item.id
        progress = 0
        let report: @Sendable (Double) -> Void = { share in
            Task { @MainActor in
                if self.itemID == item.id { self.progress = share }
            }
        }
        task = Task { [weak self] in
            let result: Result<String, Error>
            do {
                result = .success(try await OnlineBackgroundService.shared.download(item, progress: report))
            } catch {
                result = .failure(error)
            }
            guard let self, self.itemID == item.id else { return }
            self.itemID = nil
            done(result)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        itemID = nil
    }
}

/// The left column while browsing a source: category chips, the search field on
/// Search, a status line, and the grid of thumbnails with their resolution badges.
struct OnlineBrowsePanel: View {
    let state: OnlineBrowseState
    let loading: Bool
    let failed: Bool
    let downloadingID: String?
    let progress: Double
    /// Ids (online/<source>-<id>) already downloaded.
    let downloaded: Set<String>
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onChip: (Int) -> Void
    let onTile: (Int) -> Void

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    static let gridHeight: CGFloat = 500

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chips
                .padding(.bottom, canvas.u(14))
            if state.category.isSearch {
                searchField
                    .padding(.bottom, canvas.u(10))
            }
            Text(status)
                .seleneFont(13, .semibold)
                .foregroundColor(SeleneTheme.ink.opacity(0.55))
                .padding(.leading, canvas.u(10))
                .padding(.bottom, canvas.u(10))
            grid
        }
    }

    private var status: String {
        let source = state.source.title
        if failed { return L10n.format("%@ IS UNAVAILABLE RIGHT NOW", [String(describing: (source.uppercased()))]) }
        if state.category.isSearch && state.query.isEmpty { return L10n.text("TYPE WHAT YOU'RE LOOKING FOR, THEN RETURN") }
        if state.items.isEmpty { return loading ? L10n.format("LOOKING ON %@…", [String(describing: (source.uppercased()))]) : L10n.text("NOTHING FOUND") }
        return L10n.format("ONLINE · %@ · %@", [String(describing: (source.uppercased())), String(describing: (state.category.displayTitle.uppercased()))])
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: canvas.u(6)) {
                    ForEach(Array(state.categories.enumerated()), id: \.offset) { index, category in
                        let selected = index == state.categoryIndex
                        Text(category.displayTitle)
                            .seleneFont(16, .semibold)
                            .foregroundColor(selected ? SeleneTheme.ink : SeleneTheme.ink60)
                            .padding(.horizontal, canvas.u(16))
                            .padding(.vertical, canvas.u(8))
                            .background(Capsule().fill(selected ? SeleneTheme.glassSolid : Color.clear))
                            .overlay(Capsule().strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2.5))
                                .padding(canvas.u(-3))
                                .opacity(selected && state.focus == .chips ? 1 : 0))
                            .contentShape(Capsule())
                            .onTapGesture { onChip(index) }
                            .id(index)
                            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(canvas.u(5))
            }
            .scrollIndicators(.hidden)
            .frame(width: canvas.u(3 * 226))
            .onChange(of: state.categoryIndex) { index in
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: canvas.u(10)) {
            MaterialIconView(.search, size: 22).foregroundColor(SeleneTheme.ink60)
            TextField("", text: $searchText, prompt: Text(L10n.format("Search %@", [String(describing: (state.source.title))])).foregroundColor(SeleneTheme.ink60))
                .textFieldStyle(.plain)
                .seleneFont(18)
                .foregroundColor(SeleneTheme.ink)
                .focused(searchFocused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, canvas.u(16))
        .padding(.vertical, canvas.u(10))
        .background(Capsule().fill(SeleneTheme.glassSolid))
        .frame(width: canvas.u(3 * 226 - 20))
        .padding(.leading, canvas.u(10))
    }

    private var grid: some View {
        let height = Self.gridHeight - (state.category.isSearch ? 58 : 0)
        let items = state.items
        let focusedIndex: Int? = { if case .tile(let index) = state.focus { return index } else { return nil } }()
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stride(from: 0, to: items.count, by: OnlineBrowseState.columns)), id: \.self) { first in
                        HStack(spacing: 0) {
                            ForEach(first..<min(first + OnlineBrowseState.columns, items.count), id: \.self) { index in
                                OnlineTile(item: items[index], focused: index == focusedIndex,
                                           downloaded: downloaded.contains(OnlineDownload.wallpaperID(for: items[index])),
                                           progress: downloadingID == items[index].id ? progress : nil)
                                    .id(index)
                                    .onTapGesture { onTile(index) }
                            }
                        }
                    }
                }
                .padding(.vertical, canvas.u(10))
            }
            .scrollIndicators(.hidden)
            .frame(width: canvas.u(3 * 226), height: canvas.u(height))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                         .init(color: .black, location: 1 - 150 / height),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: focusedIndex) { index in
                guard let index else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                    proxy.scrollTo(index - index % OnlineBrowseState.columns, anchor: .center)
                }
            }
        }
    }
}

/// An online item: its thumbnail, a resolution badge, a check once downloaded,
/// and a progress ring while it downloads.
private struct OnlineTile: View {
    let item: OnlineBackground
    let focused: Bool
    let downloaded: Bool
    let progress: Double?

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(SeleneTheme.baseGradient)
            WallpaperThumb(url: item.thumbnailURL)
            HStack(spacing: canvas.u(4)) {
                if item.kind == .video { MaterialIconView(.play, size: 13) }
                Text(ResolutionBadge.label(width: item.width, height: item.height)).seleneFont(12, .semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, canvas.u(7))
            .padding(.vertical, canvas.u(3))
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(canvas.u(7))
            if downloaded {
                MaterialIconView(.check, size: 20)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: canvas.u(4))
                    .padding(canvas.u(7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let progress {
                Color.black.opacity(0.45)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: canvas.u(4))
                    Circle().trim(from: 0, to: max(0.02, progress))
                        .stroke(SeleneTheme.focus, style: StrokeStyle(lineWidth: canvas.u(4), lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 0.15), value: progress)
                }
                .frame(width: canvas.u(44), height: canvas.u(44))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: canvas.u(204), height: canvas.u(115))
        .clipShape(shape)
        .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: 1))
        .overlay(
            RoundedRectangle(cornerRadius: canvas.u(15), style: .continuous)
                .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
                .padding(canvas.u(-4))
                .opacity(focused ? 1 : 0))
        .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: focused)
        .padding(.horizontal, canvas.u(11))
        .padding(.top, canvas.u(13))
        .padding(.bottom, canvas.u(14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("%@, %@ by %@", [String(describing: (item.title)), String(describing: (item.width)), String(describing: (item.height))]))
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }
}
