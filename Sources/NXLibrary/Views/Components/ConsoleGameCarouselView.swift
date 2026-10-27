import SwiftUI
import AppKit
import NXLibraryCore

public struct ConsoleGameCarouselView: View {
    @ObservedObject public var viewModel: AppViewModel
    public let games: [PortedGame]

    public init(viewModel: AppViewModel, games: [PortedGame]) {
        self.viewModel = viewModel
        self.games = games
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        gameTile(
                            game: game,
                            isFocused: viewModel.focusedGameIndex == index,
                            isLaunching: viewModel.launchingGameId == game.id
                        )
                        .id(index)
                        .onTapGesture {
                            SoundEffectService.shared.play(.focus)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                viewModel.focusedGameIndex = index
                                viewModel.isFocusOnDeck = false
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
            .onChange(of: viewModel.focusedGameIndex) { newIndex in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(height: 320)
    }

    private func gameTile(game: PortedGame, isFocused: Bool, isLaunching: Bool) -> some View {
        let icon = GameIconProvider.icon(for: game)

        return VStack(spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                isFocused
                                    ? AnyShapeStyle(NXTheme.selectedBorder)
                                    : AnyShapeStyle(Color.white.opacity(0.10)),
                                lineWidth: isFocused ? 2.5 : 1
                            )
                    )
                    .shadow(
                        color: isFocused
                            ? NXTheme.secondary.opacity(0.42)
                            : NXTheme.cardShadow,
                        radius: isFocused ? 26 : 10,
                        x: 0,
                        y: isFocused ? 12 : 4
                    )
                    .shadow(
                        color: isFocused
                            ? NXTheme.primary.opacity(0.22)
                            : Color.clear,
                        radius: isFocused ? 44 : 0
                    )

                if isLaunching {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Launching")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(10)
                } else if let badge = tileBadge(for: game) {
                    Text(badge.text)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(badge.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(badge.color.opacity(0.5), lineWidth: 0.6))
                        .padding(10)
                }
            }
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isFocused)

            Text(game.name)
                .font(.system(size: isFocused ? 13 : 11,
                              weight: isFocused ? .bold : .medium,
                              design: .rounded))
                .foregroundColor(isFocused ? NXTheme.textPrimary : NXTheme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 250, height: 32, alignment: .top)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(game.name)
        .accessibilityHint("Select this game, then press A or Return to play.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play") {
            viewModel.launchGame(game)
        }
    }

    private func tileBadge(for game: PortedGame) -> (text: String, color: Color)? {
        if viewModel.currentBuildGameID == game.id {
            return ("Building", NXTheme.secondary)
        }
        switch game.status {
        case .builtSourcesMissing:
            return ("Sources missing", NXTheme.warning)
        case .appMissing:
            return ("App missing", NXTheme.error)
        case .failed:
            return ("Build failed", NXTheme.error)
        case .built:
            if !game.toolchain.verified, game.lastBuild != nil {
                return ("Untested toolchain", NXTheme.warning)
            }
            return nil
        case .needsRebuild:
            return ("Needs rebuild", NXTheme.warning)
        case .notBuilt, .building, .cancelled:
            return nil
        }
    }
}
