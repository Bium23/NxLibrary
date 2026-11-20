import Foundation

extension AppDataProfile {
    /// Where builds put their temporary files: the profile's own folder, and for the stable profile also beside each
    /// Game apps folder.
    public func automaticStagingFolders(appFolders: [URL]) -> [URL] {
        BuildScratch.tempFolders(core: supportRoot, appFolders: isDevelopment ? [] : appFolders)
    }
}
