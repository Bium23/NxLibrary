import Foundation
import NXLibraryCore

extension GameOptionsBuildSettings {
    /// What a ported build's saved settings decide about the rows.
    public init(_ snapshot: GameSettingsSnapshot) {
        self.init(fixed: snapshot.fixed,
                  visible: Set(GameOptionsRow.settingRows.compactMap(\.settingKey).filter(snapshot.visible)),
                  offersRenderScale: snapshot.isOffered("DM_RENDER_SCALE"),
                  hasMoreSettings: !snapshot.extraSettings.isEmpty)
    }
}

extension GameOptionsPresentation {
    /// A ported game's options, with its build's settings (nil for a build without saved choices).
    public init(supportsRenderScale: Bool, isPlayable: Bool, sourcesDetached: Bool,
                toolchainBlocked: Bool = false, toolchainHint: String? = nil, hasStorePage: Bool = false,
                offersStoreSearch: Bool = false,
                gameName: String = "", appPath: String = "", canDeleteBundle: Bool = false,
                cheatsValue: String = "None", modsValue: String = "None", settings: GameSettingsSnapshot?) {
        self.init(supportsRenderScale: supportsRenderScale, isPlayable: isPlayable, sourcesDetached: sourcesDetached,
                  toolchainBlocked: toolchainBlocked, toolchainHint: toolchainHint, hasStorePage: hasStorePage,
                  offersStoreSearch: offersStoreSearch, gameName: gameName, appPath: appPath,
                  canDeleteBundle: canDeleteBundle, cheatsValue: cheatsValue, modsValue: modsValue,
                  buildSettings: settings.map(GameOptionsBuildSettings.init))
    }
}
