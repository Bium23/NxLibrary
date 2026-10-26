import Foundation

public enum BuildEventParser {
    private struct Wire: Decodable {
        let ev: String?
        let k: Int?
        let n: Int?
        let name: String?
        let step: String?
        let done: Double?
        let total: Double?
        let unit: String?
        let frac: Double?
        let eta: Double?
        let elapsed: Double?
        let ok: Bool?
        let summary: String?
        let msg: String?
    }

    public static func parse(_ line: String) -> BuildEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let ev = wire.ev else { return .log(trimmed) }
        switch ev {
        case "stage":
            return .stage(k: wire.k ?? 1, n: wire.n ?? 1,
                          name: wire.name ?? "stage", step: wire.step)
        case "step":
            return wire.step.map { .step($0) }
        case "progress":
            return .progress(fraction: wire.frac ?? 0, done: wire.done,
                             total: wire.total, unit: wire.unit, eta: wire.eta)
        case "stage_end":
            return .stageEnd(name: wire.name ?? "", ok: wire.ok ?? true,
                             elapsed: wire.elapsed, summary: wire.summary)
        case "say":
            return wire.msg.map { .say($0) }
        default:
            return .log(trimmed)
        }
    }
}
