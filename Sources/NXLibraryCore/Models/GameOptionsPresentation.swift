import Foundation

public struct GameOptionsPresentation: Equatable {
    public let showRenderScale: Bool
    public let canPlay: Bool
    public let sourcesDetached: Bool
    public let resolutionNote: String

    public init(supportsRenderScale: Bool, isPlayable: Bool, sourcesDetached: Bool) {
        self.showRenderScale = supportsRenderScale
        self.canPlay = isPlayable
        self.sourcesDetached = sourcesDetached
        self.resolutionNote = "Output follows the window/display. Render scale changes the internal 3D resolution only; native 1440p/4K is not available in this engine pin."
    }
}
