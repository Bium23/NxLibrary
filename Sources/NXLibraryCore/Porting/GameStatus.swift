public enum GameStatus: String, Codable, Equatable {
    case notBuilt, building, built, builtSourcesMissing
    case failed, cancelled, needsRebuild, appMissing
}
