import SwiftUI
import AppKit
import NXLibraryCore

/// "Find the game" / "Wrong game?": search GameBanana by name and pick this game's page. Its state lives here so the
/// page's controller and key handling can drive it.
@MainActor
final class GameBananaFindModel: ObservableObject {
    @Published var isOpen = false
    @Published var query = ""
    @Published private(set) var results: [GameBananaGame] = []
    @Published private(set) var searching = false
    @Published private(set) var searched = false
    /// The focused row: results, then None of these.
    @Published var focus = 0

    private var task: Task<Void, Never>?

    var rowCount: Int { results.count + 1 }

    func open(name: String, using band: GameBananaBandModel) {
        query = name
        results = []
        searched = false
        focus = 0
        isOpen = true
        search(using: band)
    }

    func close() {
        task?.cancel()
        isOpen = false
    }

    func search(using band: GameBananaBandModel) {
        task?.cancel()
        let text = query
        searching = true
        task = Task { [weak self] in
            let found = await band.search(text)
            guard !Task.isCancelled, let self else { return }
            self.results = Array(found.prefix(8))
            self.searching = false
            self.searched = true
            self.focus = 0
        }
    }

    func move(by delta: Int) -> Bool {
        let next = min(max(focus + delta, 0), rowCount - 1)
        guard next != focus else { return false }
        focus = next
        return true
    }

    /// Runs the focused row; true when it closed the panel.
    func activate(_ index: Int, using band: GameBananaBandModel) {
        if index < results.count {
            band.confirm(results[index])
        } else {
            band.noneOfThese()
        }
        close()
    }
}

struct GameBananaFindPanel: View {
    @ObservedObject var model: GameBananaFindModel
    @ObservedObject var band: GameBananaBandModel
    let gameName: String

    @Environment(\.seleneCanvas) private var canvas
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            SeleneTheme.scrim65
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: canvas.u(14)) {
                Text("GAMEBANANA")
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                Text("Which game is \(gameName)?")
                    .seleneFont(32)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(2)
                HStack(spacing: canvas.u(10)) {
                    MaterialIconView(.search, size: 22).foregroundColor(SeleneTheme.ink60)
                    TextField("", text: $model.query, prompt: Text("Game name").foregroundColor(SeleneTheme.ink60))
                        .textFieldStyle(.plain)
                        .seleneFont(18)
                        .foregroundColor(SeleneTheme.ink)
                        .focused($fieldFocused)
                        .onSubmit {
                            fieldFocused = false
                            model.search(using: band)
                        }
                        .onExitCommand { close() }
                }
                .padding(.horizontal, canvas.u(16))
                .padding(.vertical, canvas.u(10))
                .background(Capsule().fill(SeleneTheme.glassSolid))

                if model.searching {
                    Text("Searching GameBanana…").seleneFont(16).foregroundColor(SeleneTheme.ink60)
                } else if model.searched && model.results.isEmpty {
                    Text("No games found. Try another name.").seleneFont(16).foregroundColor(SeleneTheme.ink60)
                }
                VStack(alignment: .leading, spacing: canvas.u(8)) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, game in
                        row(index: index, title: game.name, icon: game.iconURL)
                    }
                    row(index: model.results.count, title: "None of these", icon: nil)
                }
                Text("Mod data provided by GameBanana")
                    .seleneFont(14)
                    .foregroundColor(SeleneTheme.ink60)
            }
            .padding(canvas.u(36))
            .frame(width: canvas.u(820), alignment: .leading)
            .background(RoundedRectangle(cornerRadius: canvas.u(22), style: .continuous).fill(SeleneTheme.glassSolid))
        }
    }

    private func row(index: Int, title: String, icon: URL?) -> some View {
        let focused = model.focus == index && !fieldFocused
        return HStack(spacing: canvas.u(14)) {
            if let icon {
                GameBananaImageView(url: icon, maxPixelSize: 128)
                    .frame(width: canvas.u(40), height: canvas.u(40))
                    .clipShape(RoundedRectangle(cornerRadius: canvas.u(8), style: .continuous))
            } else {
                MaterialIconView(.close, size: 22).foregroundColor(SeleneTheme.ink60)
                    .frame(width: canvas.u(40), height: canvas.u(40))
            }
            Text(title)
                .seleneFont(18, .medium)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, canvas.u(14))
        .padding(.vertical, canvas.u(8))
        .background(RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
            .fill(focused ? SeleneTheme.glass : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
            .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2.5))
            .padding(canvas.u(-3))
            .opacity(focused ? 1 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            SoundEffectService.shared.play(.click)
            model.activate(index, using: band)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }

    private func close() {
        SoundEffectService.shared.play(.focus)
        model.close()
    }
}
