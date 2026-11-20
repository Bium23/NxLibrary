import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NXLibraryCore

/// Loading: the slot's candidates and their previews, a source's browse results, the pick and the automatic icon.
extension ChangeArtworkView {
    // MARK: - Loading

    /// Lists the slot's candidates and loads them all at once; each shows as it arrives.
    func search(_ slot: ArtworkSlot) async {
        guard found[slot] == nil, !searching.contains(slot) else { return }
        searching.insert(slot)
        defer { searching.remove(slot) }
        if !titleDBLoaded, let titleId = subject.titleId {
            titleDB = await TitleDBInfo.fetch(titleID: titleId)
            titleDBLoaded = true
        }
        let metadata = store.storeMetadata[subject.id]
        let names = gameNames
        var candidates: [ArtworkCandidate]
        found[slot] = []
        if let steam = subject.steam, let appID = subject.steamAppID {
            // Steam's own art for this AppID shows at once; the online sources take seconds and follow it.
            let screenshots = SteamGameFacts.shared.metadata(for: steam)?.screenshots ?? []
            let own = ArtworkCandidates.steamList(for: slot, appID: appID, screenshots: screenshots)
            await collect(own, slot: slot, from: 0)
            guard !Task.isCancelled else { found[slot] = nil; return }
            if online == nil { online = await OnlineArtwork.find(names: names, platform: .mac) }
            candidates = ArtworkCandidates.steamList(for: slot, appID: appID, screenshots: screenshots, online: online ?? [])
            await collect(Array(candidates.dropFirst(own.count)), slot: slot, from: own.count)
        } else {
            let entries = slot == .cover ? await viewModel.boxArt.pickerEntries(names: names) : []
            if online == nil { online = await OnlineArtwork.find(names: names, platform: switch2 ? .switch2 : .switch) }
            candidates = ArtworkCandidates.list(for: slot, entries: entries, titleDB: titleDB,
                                                storeHeader: metadata?.headerImageURL, storeImage: metadata?.imageURL,
                                                storeLogo: metadata?.logoURL, online: online ?? [])
            await collect(candidates, slot: slot, from: 0)
        }
        if slot == .icon, !Task.isCancelled,
           let titleID = subject.titleId,
           let url = await AppViewModel.automaticIconArtwork.automaticIcon(titleID: titleID, name: subject.name),
           AppViewModel.automaticIconArtwork.automaticIconSource(titleID: titleID) == "Switch Icon Showdown",
           let data = try? Data(contentsOf: url), let size = ArtworkCandidates.pixelSize(of: data),
           let preview = await GameArtLoader.decode(at: url, maxPixelSize: 600), !Task.isCancelled {
            let candidate = ArtworkCandidate(slot: .icon, source: "Switch Icon Showdown", url: url)
            let art = LoadedArtwork(candidate: candidate, data: data, pixelWidth: size.width, pixelHeight: size.height)
            found[slot, default: []].append(Found(order: candidates.count, art: art, preview: preview))
        }
        // Left for another tab before it finished: search again on return.
        if Task.isCancelled { found[slot] = nil }
    }

    /// Adds the candidates' previews to the slot as they arrive, in list order after `offset`.
    private func collect(_ candidates: [ArtworkCandidate], slot: ArtworkSlot, from offset: Int) async {
        for await item in Self.previews(of: candidates) {
            var list = found[slot] ?? []
            list.append(Found(order: item.order + offset, art: item.art, preview: item.preview))
            list.sort { $0.order < $1.order }
            found[slot] = list
        }
    }

    /// Downloads each candidate's preview at once and yields those that are images, as they arrive.
    private static func previews(of candidates: [ArtworkCandidate]) -> AsyncStream<Found> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Found?.self) { group in
                    for (order, candidate) in candidates.enumerated() {
                        group.addTask {
                            guard let art = await ArtworkCandidates.load(candidate),
                                  let preview = thumbnail(art.data) else { return nil }
                            return Found(order: order, art: art, preview: preview)
                        }
                    }
                    for await item in group {
                        if let item { continuation.yield(item) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    var browseTaskKey: String {
        guard let browsing else { return "" }
        return "\(browsing.rawValue)|\(browseRound)|\(slot.rawValue)"
    }

    /// Searches the source once per name, then loads the open tab's previews.
    func browse() async {
        guard let source = browsing else { return }
        let round = browseRound
        if browseResult == nil {
            let key = source.needsKey ? SteamGridDBKey().load() : nil
            let result = await source.search(browseQuery, gameNames: gameNames, switch2: switch2, computer: subject.steam != nil, key: key)
            guard round == browseRound, browsing == source, !Task.isCancelled else { return }
            browseResult = result
        }
        let slot = self.slot
        guard browseItems[slot] == nil, !browseLoading.contains(slot), let result = browseResult else { return }
        browseLoading.insert(slot)
        defer { browseLoading.remove(slot) }
        browseItems[slot] = []
        for await item in Self.previews(of: result.candidates.filter { $0.slot == slot }) {
            guard round == browseRound, browsing == source else { return }
            var list = browseItems[slot] ?? []
            list.append(item)
            list.sort { $0.order < $1.order }
            browseItems[slot] = list
        }
        if Task.isCancelled, round == browseRound { browseItems[slot] = nil }
    }

    func loadPickPreview() async {
        guard let url = subject.artworkURL(slot) else {
            pickPreview = nil
            return
        }
        pickPreview = await GameArtLoader.decode(at: url, maxPixelSize: 600)
    }

    func loadAutomaticIcon() async {
        guard slot == .icon else { return }
        automaticIconChecked = false
        let url: URL?
        if let macApp { url = await appIcon.automaticIconURL(for: macApp) }
        else if let steam = subject.steam { url = SteamArtworkRequest(game: steam, role: .square).automaticLocalURL }
        else { url = nil }
        let preview: NSImage?
        if let url { preview = await GameArtLoader.decode(at: url, maxPixelSize: 600) }
        else { preview = nil }
        guard !Task.isCancelled else { return }
        automaticIconPreview = preview
        automaticIconChecked = true
    }

    nonisolated private static func thumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
