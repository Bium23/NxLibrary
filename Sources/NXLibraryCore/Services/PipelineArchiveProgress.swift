import Foundation

/// Reads only the engine's current pipeline log. A batch counts when the engine reports it ready;
/// compiler temporaries and old cache keys do not prove that this build has completed a pipeline.
/// Unknown log formats leave the stage indeterminate. No upstream files are changed.
public struct PipelineArchiveProgress: Sendable {
    public init() {}

    public func poll(logURL: URL, architectures: [String], stageStartedAt: Date,
                     now: Date = Date()) -> BuildEvent? {
        guard !architectures.isEmpty,
              let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let modified = attrs[.modificationDate] as? Date, modified >= stageStartedAt,
              let size = (attrs[.size] as? NSNumber)?.intValue, size <= 4 * 1024 * 1024,
              let log = try? String(contentsOf: logURL, encoding: .utf8) else { return nil }
        var totals: [String: Int] = [:]
        var batches: [String: Int] = [:]
        var ready = Set<String>()
        var compiled = Set<String>()
        // Python's parallel compute workers may join two print calls on one line. Keep both
        // records, but do not consume the final physical line until the writer finishes it.
        let records = log.components(separatedBy: "\n").dropLast().flatMap { line in
            line.components(separatedBy: "pso_offline:").dropFirst().map { "pso_offline:" + $0 }
        }
        for line in records {
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count >= 4, words[0] == "pso_offline:" else { continue }
            let arch = String(words[1].dropLast())
            guard architectures.contains(arch) else { continue }
            if words[2] == "metal-tt,", words.count >= 7,
               let bases = Int(words[3]), let computes = Int(words[5]),
               bases >= 0, computes >= 0, bases <= 10_000_000, computes <= 10_000_000 {
                totals[arch] = bases + computes
            } else if words[2] == "batch", words.count >= 6 {
                let key = arch + ":" + words[3]
                if let count = Int(words[4]), count > 0, count <= 10_000_000,
                   words[5] == "bases," || words[5] == "compute" {
                    batches[key] = count
                } else if words[4] == "ready", words[5] == "(compiled)" || words[5] == "(reused)" {
                    ready.insert(key)
                    if words[5] == "(compiled)" { compiled.insert(key) }
                }
            }
        }
        guard let perArchitecture = totals.values.first, perArchitecture > 0 else { return nil }
        // The same plan is compiled once for each requested GPU. Include GPUs not started yet.
        let total = perArchitecture * Set(architectures).count
        let done = min(total, ready.reduce(0) { $0 + (batches[$1] ?? 0) })
        let newlyCompiled = compiled.reduce(0) { $0 + (batches[$1] ?? 0) }
        let elapsed = max(0, now.timeIntervalSince(stageStartedAt))
        let eta = newlyCompiled > 0 && elapsed >= 3 && done < total
            ? Double(total - done) * elapsed / Double(newlyCompiled) : nil
        return .progress(fraction: min(0.99, Double(done) / Double(total)), done: Double(done),
                         total: Double(total), unit: "pipelines", eta: eta)
    }
}
