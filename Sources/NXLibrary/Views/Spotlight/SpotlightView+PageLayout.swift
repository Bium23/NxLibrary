import SwiftUI
import AppKit
import NXLibraryCore

/// The page below the row: its offsets, fades and mask, and what About shows.
extension SpotlightView {
    // MARK: - Page

    /// How far the page rises once the focus leaves the row: the logo goes from 420 to 96.
    static let pageTravel: CGFloat = 324

    /// The page's scroll for the focus, in points. The pills and the strip
    /// share the first shift (the strip only moves further if it would sit
    /// under the hints); Details brings About this game and the column
    /// beside it up to 150 by their titles; More like this rises until the
    /// page's end sits above the hints, never further (`SpotlightPageScroll`).
    /// Positions add up the blocks' heights from the column's top at 420.
    func pageOffset(_ state: SpotlightState) -> CGFloat {
        offset(for: state.focus)
    }

    func offset(for area: SpotlightFocusArea) -> CGFloat {
        let first = -canvas.u(Self.pageTravel)
        let h = { (block: SpotlightPageBlock) in blocks[block] ?? 0 }
        let stripBottom = canvas.u(420) + h(.head) + h(.genres) + h(.strip)
        // The description block includes its 44 top padding.
        let aboutTop = stripBottom + canvas.u(44)
        // The Mods band (its top gap included) sits between About this game and More like this.
        let modsTop = stripBottom + h(.description) + canvas.u(Self.moreGap)
        let moreTop = stripBottom + h(.description) + h(.mods) + canvas.u(Self.moreGap)
        switch area {
        case .row, .topGames:
            return 0
        case .store:
            return storeOffset()
        case .pills:
            return first
        case .strip:
            // Keep the strip clear of the hints on the window's bottom edge.
            return min(first, canvas.size.height - canvas.u(Self.pageBottomInset) - stripBottom)
        case .about, .actions, .mods, .more, .achievements:
            // The bands report a height only when they are shown.
            let more = h(.more) > 0
            let pageBottom = stripBottom + h(.description) + h(.mods) + (more ? h(.more) : 0)
            let rest = SpotlightPageScroll.resting(
                first: first, aboutTop: aboutTop, moreTop: more ? moreTop : nil, pageBottom: pageBottom,
                top: canvas.u(150), viewport: canvas.size.height, bottomInset: canvas.u(Self.pageBottomInset))
            switch area {
            case .actions, .achievements: return rest.actions
            case .more: return rest.more
            case .mods:
                // The band's title rises to the top line, as More like this does, unless the page ends first.
                guard h(.mods) > 0 else { return rest.actions }
                return SpotlightPageScroll.resting(
                    first: first, aboutTop: aboutTop, moreTop: modsTop,
                    pageBottom: pageBottom, top: canvas.u(150), viewport: canvas.size.height,
                    bottomInset: canvas.u(Self.pageBottomInset)).more
            default:
                // Read more (or Show less, under the whole text) comes into view.
                return SpotlightPageScroll.revealing(rest.actions, bottom: aboutTop + h(.about),
                                                     viewport: canvas.size.height, bottomInset: canvas.u(Self.pageBottomInset))
            }
        }
    }

    /// The page's edges, in canvas units: clear up to `clear` from the window's
    /// edge, solid from `solid` (the top bar's breathing room, top and bottom).
    static let pageEdge = (top: (clear: CGFloat(28), solid: CGFloat(84)),
                           bottom: (clear: SeleneBottomScrim.contentClearance,
                                    solid: SeleneBottomScrim.contentClearance + 64))
    /// A focused band clears both the footer and its fade, with space for its ring.
    static let pageBottomInset: CGFloat = pageEdge.bottom.solid + 30

    var pageMask: some View {
        let height = max(canvas.size.height, 1)
        let at = { (units: CGFloat) in min(max(canvas.u(units) / height, 0), 1) }
        let e = Self.pageEdge
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: at(e.top.clear)),
            .init(color: .black, location: at(e.top.solid)),
            .init(color: .black, location: 1 - at(e.bottom.solid)),
            .init(color: .clear, location: 1 - at(e.bottom.clear)),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    /// Between About this game (or the column beside it, whichever ends lower) and More like this.
    static let moreGap: CGFloat = 72

    /// About this game's cut for the page, as tall as the column beside it.
    func aboutExcerpt(_ page: SpotlightPageModel) -> DescriptionExcerpt {
        SpotlightDescription.excerpt(aboutWikipedia(page)?.text ?? page.presentation.description,
                                     columnHeight: blocks[.column] ?? 0, canvas: canvas)
    }

    func aboutLookup(_ page: SpotlightPageModel) -> WikipediaAboutLookup? {
        WikipediaAboutLookup(presentation: page.presentation, query: selectedRatingQuery)
    }

    /// The selected page's Wikipedia text, once it has arrived for this game and language.
    func aboutWikipedia(_ page: SpotlightPageModel) -> WikipediaDescription? {
        wikipediaAbout?.matching(aboutLookup(page))
    }

    /// The page's glide: one slow, soft curve (1 s, long ease out) for the whole screen.
    static let glide = Animation.timingCurve(0.4, 0, 0.1, 1, duration: 1.0)

    /// Moves the page to the focus, after the focus change has rendered, in
    /// transactions of its own. Leaving the row, the icons and the bar fade out
    /// first and the sections below fade in behind the glide; coming back, the
    /// sections go first and the icons return as the page settles. Under reduce
    /// motion the page jumps and only the fades run.
    func syncPage(glide: Animation = Self.glide) {
        let state = viewModel.spotlight
        let target = pageOffset(state)
        let onRow = state.focus == .row || state.focus == .topGames
        if holdScroll {
            // The focus followed a wheel scroll: the page stays where the user left it.
            holdScroll = false
        } else if reduceMotion {
            scroll = target
        } else if abs(scroll - target) > 0.5 {
            glideEnds = Date().addingTimeInterval(glide == Self.glide ? 1.05 : 0.6)
            withAnimation(glide) { scroll = target }
        }
        // Mods found in the background wait until the page rests: no rebuild under a glide.
        if selectedItem == .card(.mods) { storeHost.hold(until: glideEnds) }
        setPageFades(onRow: onRow, deep: isDeep(state))
    }

    /// Leaving the row, the icons and the bar fade out first and the sections
    /// below fade in behind; coming back, the sections go first.
    func setPageFades(onRow: Bool, deep: Bool) {
        if onRow == stripFull {
            withAnimation(.easeInOut(duration: onRow ? 0.7 : 0.9)) { stripFull = !onRow }
        }
        if onRow == !rowShown {
            if onRow {
                withAnimation(.easeInOut(duration: 0.45)) { belowShown = false }
                withAnimation(.easeInOut(duration: 0.7).delay(0.3)) { rowShown = true }
            } else {
                withAnimation(.easeInOut(duration: 0.55)) { rowShown = false }
                withAnimation(.easeInOut(duration: 0.8).delay(0.25)) { belowShown = true }
            }
        }
        if deep != dimmed {
            withAnimation(.easeInOut(duration: 0.8)) { dimmed = deep }
        }
    }

    /// Measured heights that differ by under a point are the same layout.
    static func sameLayout(_ a: [SpotlightPageBlock: CGFloat], _ b: [SpotlightPageBlock: CGFloat]) -> Bool {
        guard a.keys == b.keys else { return false }
        return a.allSatisfy { key, height in abs(height - (b[key] ?? .infinity)) < 1 }
    }

    /// Past the screenshots the art dims behind the text.
    func isDeep(_ state: SpotlightState) -> Bool {
        state.focus == .about || state.focus == .actions || state.focus == .mods || state.focus == .more
            || state.focus == .store || state.focus == .achievements
    }

    var currentPage: SpotlightPageModel? {
        if let game = selectedGame { return page(for: game) }
        return selectedCatalogGame.flatMap { $0.integration == .steam ? steamPage(for: $0) : nil }
    }
}
