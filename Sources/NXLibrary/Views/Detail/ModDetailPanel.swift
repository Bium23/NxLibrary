import SwiftUI
import AppKit
import NXLibraryCore

/// One GameBanana mod over the game's page: its images, author, version beside the game's, likes and downloads, the
/// description as plain text, then one row per file that works (Install / Update / Installed, progress with Cancel,
/// the failure with Retry) and Open on GameBanana. Up/Down move between rows, A activates, B (Esc) closes; a click
/// activates a row. Rows are listed by `ModDetailPanel.rows`, which the page's input uses too.
struct ModDetailPanel: View {
    @ObservedObject var model: GameBananaBandModel
    let mod: AvailableMod
    let game: PortedGame
    /// The installed copy of this mod, if any.
    let installed: ModRecord?
    @Binding var focus: Int
    @Binding var expanded: Bool
    let onClose: () -> Void

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    enum Row: Equatable {
        case readMore
        case file(Int)
        case openPage
    }

    /// Long descriptions get a Read more row.
    static func rows(for mod: AvailableMod) -> [Row] {
        (mod.description.count > 420 ? [.readMore] : []) + mod.files.map { .file($0.id) } + [.openPage]
    }

    var body: some View {
        let rows = Self.rows(for: mod)
        return ZStack {
            SeleneTheme.scrim65
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            HStack(alignment: .top, spacing: canvas.u(36)) {
                gallery
                VStack(alignment: .leading, spacing: canvas.u(12)) {
                    Text("GAMEBANANA MOD")
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                    Text(mod.name)
                        .seleneFont(36)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(2)
                    authorLine
                    Text(versionLine)
                        .seleneFont(16)
                        .foregroundColor(SeleneTheme.ink75)
                    Text("\(mod.likes) likes · \(mod.downloads) downloads")
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink60)
                    if !mod.description.isEmpty {
                        Text(mod.description)
                            .seleneFont(16)
                            .foregroundColor(SeleneTheme.ink82)
                            .lineLimit(expanded ? nil : 8)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, canvas.u(6))
                    }
                    VStack(alignment: .leading, spacing: canvas.u(8)) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            rowView(row, focused: focus == index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    focus = index
                                    activate(row)
                                }
                        }
                    }
                    .padding(.top, canvas.u(10))
                    Text("Mod data provided by GameBanana")
                        .seleneFont(14)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.top, canvas.u(6))
                }
                .frame(width: canvas.u(700), alignment: .leading)
            }
            .padding(canvas.u(40))
            .background(RoundedRectangle(cornerRadius: canvas.u(24), style: .continuous).fill(SeleneTheme.glassSolid))
            .frame(maxHeight: canvas.u(980))
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: expanded)
    }

    private var gallery: some View {
        let images = Array(mod.images.prefix(4))
        return VStack(alignment: .leading, spacing: canvas.u(12)) {
            GameBananaImageView(url: images.first ?? mod.thumbnailURL, maxPixelSize: 1200)
                .frame(width: canvas.u(560), height: canvas.u(315))
                .clipShape(RoundedRectangle(cornerRadius: canvas.u(16), style: .continuous))
            if images.count > 1 {
                HStack(spacing: canvas.u(12)) {
                    ForEach(images.dropFirst(), id: \.self) { url in
                        GameBananaImageView(url: url, maxPixelSize: 500)
                            .frame(width: canvas.u(178), height: canvas.u(100))
                            .clipShape(RoundedRectangle(cornerRadius: canvas.u(10), style: .continuous))
                    }
                }
            }
        }
    }

    private var authorLine: some View {
        HStack(spacing: canvas.u(10)) {
            if let avatar = mod.avatarURL {
                GameBananaImageView(url: avatar, maxPixelSize: 96)
                    .frame(width: canvas.u(28), height: canvas.u(28))
                    .clipShape(Circle())
            }
            Text("by \(mod.author)")
                .seleneFont(18, .medium)
                .foregroundColor(SeleneTheme.ink)
        }
    }

    private var versionLine: String {
        let date = mod.updated.formatted(date: .abbreviated, time: .omitted)
        var parts = [mod.version.isEmpty ? "Updated \(date)" : "Version \(mod.version) · Updated \(date)"]
        if let version = game.versionString, !version.isEmpty { parts.append("Your game: \(version)") }
        return parts.joined(separator: "   ")
    }

    // MARK: - Rows

    private struct RowText {
        var icon: MaterialIcon
        var title: String
        var detail: String?
        var action: String?
        var progress: Double?
        var message: String?
        var enabled = true
    }

    private func describe(_ row: Row) -> RowText {
        switch row {
        case .readMore:
            return RowText(icon: .info, title: expanded ? "Show less" : "Read more", action: nil)
        case .openPage:
            return RowText(icon: .link, title: "Open on GameBanana", detail: "Every file, comments and credits")
        case .file(let id):
            guard let file = mod.files.first(where: { $0.id == id }) else { return RowText(icon: .puzzle, title: "") }
            let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
            let date = file.dateAdded.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            var text = RowText(icon: .puzzle, title: file.name, detail: size + date)
            switch model.installs[mod.id] {
            case .downloading(let fraction):
                text.action = "Cancel"
                text.progress = fraction
                return text
            case .installing:
                text.action = "Installing…"
                text.enabled = false
                return text
            case .failed(let message):
                text.message = message
            case .done(let message):
                text.message = message
            case nil:
                break
            }
            if installed?.gameBananaFileID == file.id {
                text.action = "Installed"
                text.enabled = false
            } else if case .failed = model.installs[mod.id] {
                text.action = "Retry"
            } else {
                text.action = installed == nil ? "Install" : "Update"
            }
            return text
        }
    }

    private func rowView(_ row: Row, focused: Bool) -> some View {
        let text = describe(row)
        return VStack(alignment: .leading, spacing: canvas.u(6)) {
            HStack(spacing: canvas.u(14)) {
                MaterialIconView(text.icon, size: 22).foregroundColor(SeleneTheme.ink75)
                VStack(alignment: .leading, spacing: canvas.u(2)) {
                    Text(text.title)
                        .seleneFont(17, .medium)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                    if let detail = text.detail {
                        Text(detail).seleneFont(14).foregroundColor(SeleneTheme.ink60).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let action = text.action {
                    Text(action)
                        .seleneFont(15, .semibold)
                        .foregroundColor(text.enabled ? SeleneTheme.ink : SeleneTheme.ink60)
                        .padding(.horizontal, canvas.u(14))
                        .padding(.vertical, canvas.u(6))
                        .background(Capsule().fill(text.enabled ? SeleneTheme.glass : Color.clear))
                }
            }
            if let progress = text.progress {
                ProgressView(value: progress).progressViewStyle(.linear).tint(SeleneTheme.focus)
            }
            if let message = text.message {
                Text(message)
                    .seleneFont(14, .medium)
                    .foregroundColor(SeleneTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, canvas.u(14))
        .padding(.vertical, canvas.u(10))
        .background(RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
            .fill(focused ? SeleneTheme.glass : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
            .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2.5))
            .padding(canvas.u(-3))
            .opacity(focused ? 1 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text.title, text.detail, text.action, text.message].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    /// A row's action: shared with the page's controller handling.
    func activate(_ row: Row) {
        Self.activate(row, mod: mod, installed: installed, model: model, expanded: $expanded)
    }

    @MainActor
    static func activate(_ row: Row, mod: AvailableMod, installed: ModRecord?, model: GameBananaBandModel,
                         expanded: Binding<Bool>) {
        switch row {
        case .readMore:
            SoundEffectService.shared.play(.click)
            expanded.wrappedValue.toggle()
        case .openPage:
            SoundEffectService.shared.play(.click)
            NSWorkspace.shared.open(mod.pageURL)
        case .file(let id):
            guard let file = mod.files.first(where: { $0.id == id }) else { return }
            switch model.installs[mod.id] {
            case .downloading:
                SoundEffectService.shared.play(.focus)
                model.cancel(mod.id)
            case .installing:
                SoundEffectService.shared.play(.error)
            default:
                if installed?.gameBananaFileID == file.id {
                    SoundEffectService.shared.play(.error)
                } else {
                    SoundEffectService.shared.play(.click)
                    model.install(mod, file: file)
                }
            }
        }
    }
}
