public enum BuildEvent: Equatable {
    case stage(k: Int, n: Int, name: String, step: String?)
    case step(String)
    case progress(fraction: Double, done: Double?, total: Double?, unit: String?, eta: Double?, elapsed: Double? = nil)
    /// `warn`: the stage finished without what it makes, though `ok` (a pipeline archive that failed, so the app is
    /// packed without one). Engines before `warn` existed never send it.
    case stageEnd(name: String, ok: Bool, elapsed: Double?, summary: String?, warn: Bool = false)
    case say(String)
    case log(String)
}
