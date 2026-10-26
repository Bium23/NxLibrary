public enum BuildEvent: Equatable {
    case stage(k: Int, n: Int, name: String, step: String?)
    case step(String)
    case progress(fraction: Double, done: Double?, total: Double?, unit: String?, eta: Double?)
    case stageEnd(name: String, ok: Bool, elapsed: Double?, summary: String?)
    case say(String)
    case log(String)
}
