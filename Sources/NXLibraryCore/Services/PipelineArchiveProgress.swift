import Foundation

/// Inspects `<buildCache>/pso/mac-work` while upstream `nxnative` runs `Pipeline archive`
/// to compute live progress, completed pipeline counts, and an ETA without modifying `nxnative`.
public final class PipelineArchiveProgress: @unchecked Sendable {
    public struct Counts: Equatable, Sendable {
        public let bases: Int
        public let computes: Int
        public var total: Int { bases + computes }

        public init(bases: Int, computes: Int) {
            self.bases = bases
            self.computes = computes
        }
    }

    private let fileManager: FileManager
    private var cachedScriptURL: URL?
    private var cachedScriptMTime: Date?
    private var cachedScriptSize: UInt64?
    private var cachedCounts: Counts?
    private var maxDone: Int = 0

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func reset() {
        cachedScriptURL = nil
        cachedScriptMTime = nil
        cachedScriptSize = nil
        cachedCounts = nil
        maxDone = 0
    }

    /// Fast occurrence count of ASCII byte needles (e.g. `"vertex_function_descriptor"`)
    /// without full JSON AST parsing.
    public static func countOccurrences(of needle: String, in data: Data) -> Int {
        guard !needle.isEmpty, !data.isEmpty else { return 0 }
        let needleBytes = Array(needle.utf8)
        let needleLen = needleBytes.count
        guard data.count >= needleLen else { return 0 }

        return data.withUnsafeBytes { rawBuffer -> Int in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            let total = data.count
            var count = 0
            var i = 0
            let limit = total - needleLen
            let first = needleBytes[0]

            while i <= limit {
                if ptr[i] == first {
                    var match = true
                    var j = 1
                    while j < needleLen {
                        if ptr[i + j] != needleBytes[j] {
                            match = false
                            break
                        }
                        j += 1
                    }
                    if match {
                        count += 1
                        i += needleLen
                        continue
                    }
                }
                i += 1
            }
            return count
        }
    }

    /// Reads descriptor counts from `bases.mtl4-json`.
    public static func countDescriptors(in data: Data) -> Counts {
        let bases = countOccurrences(of: "\"vertex_function_descriptor\"", in: data)
        let computes = countOccurrences(of: "\"compute_function_descriptor\"", in: data)
        return Counts(bases: bases, computes: computes)
    }

    /// Inspects `psoWorkDirectory` (`<buildCache>/pso/mac-work`) and returns a `.progress`
    /// event with completed pipelines, total, and an ETA.
    public func poll(
        psoWorkDirectory: URL,
        stageStartedAt: Date,
        now: Date = Date()
    ) -> BuildEvent? {
        let scriptURL = psoWorkDirectory.appendingPathComponent("bases.mtl4-json")
        guard let attributes = try? fileManager.attributesOfItem(atPath: scriptURL.path),
              let scriptMTime = attributes[.modificationDate] as? Date,
              let scriptSize = (attributes[.size] as? NSNumber)?.uint64Value,
              scriptSize > 0 else {
            return nil
        }

        // Cache counts unless bases.mtl4-json was rewritten
        let counts: Counts
        if scriptURL == cachedScriptURL,
           scriptMTime == cachedScriptMTime,
           scriptSize == cachedScriptSize,
           let cached = cachedCounts {
            counts = cached
        } else {
            guard let data = try? Data(contentsOf: scriptURL, options: .mappedIfSafe) else {
                return nil
            }
            let fresh = Self.countDescriptors(in: data)
            cachedScriptURL = scriptURL
            cachedScriptMTime = scriptMTime
            cachedScriptSize = scriptSize
            cachedCounts = fresh
            counts = fresh
        }

        let total = counts.total
        guard total > 0 else { return nil }

        let referenceTime = min(stageStartedAt, scriptMTime).addingTimeInterval(-2)
        var done = 0
        var compiledInRun = 0

        // Find batches.<arch> folder
        let batchesDir = (try? fileManager.contentsOfDirectory(at: psoWorkDirectory, includingPropertiesForKeys: nil))?
            .first { $0.lastPathComponent.hasPrefix("batches.") }

        if let batchesDir {
            let arch = String(batchesDir.lastPathComponent.dropFirst("batches.".count))
            let keyName = "key.\(arch)"

            // 1. Base groups: sequentially compiled (BATCH = 1000)
            let baseBatchSize = 1000
            let numBaseBatches = (counts.bases + baseBatchSize - 1) / baseBatchSize

            if numBaseBatches > 0 {
                for i in 1...numBaseBatches {
                    let batchName = String(format: "%05d", i)
                    let batchDir = batchesDir.appendingPathComponent(batchName)
                    let thisBatchSize = min(baseBatchSize, counts.bases - (i - 1) * baseBatchSize)
                    let keyURL = batchDir.appendingPathComponent(keyName)

                    if let keyAttrs = try? fileManager.attributesOfItem(atPath: keyURL.path) {
                        done += thisBatchSize
                        if let keyMTime = keyAttrs[.modificationDate] as? Date, keyMTime >= referenceTime {
                            compiledInRun += thisBatchSize
                        }
                    } else if fileManager.fileExists(atPath: batchDir.path) {
                        let activeCount = countTranslateFiles(in: batchDir)
                        let inBatch = min(thisBatchSize, activeCount)
                        done += inBatch
                        compiledInRun += inBatch
                        break
                    } else {
                        break
                    }
                }
            }

            // 2. Compute groups: compiled after all bases finish (COMPUTE_BATCH = 16)
            if done >= counts.bases && counts.computes > 0 {
                let computeBatchSize = 16
                let numComputeBatches = (counts.computes + computeBatchSize - 1) / computeBatchSize

                for j in 1...numComputeBatches {
                    let batchName = String(format: "c%05d", j)
                    let batchDir = batchesDir.appendingPathComponent(batchName)
                    let thisBatchSize = min(computeBatchSize, counts.computes - (j - 1) * computeBatchSize)
                    let keyURL = batchDir.appendingPathComponent(keyName)

                    if let keyAttrs = try? fileManager.attributesOfItem(atPath: keyURL.path) {
                        done += thisBatchSize
                        if let keyMTime = keyAttrs[.modificationDate] as? Date, keyMTime >= referenceTime {
                            compiledInRun += thisBatchSize
                        }
                    } else if fileManager.fileExists(atPath: batchDir.path) {
                        let activeCount = countTranslateFiles(in: batchDir)
                        let inBatch = min(thisBatchSize, activeCount)
                        done += inBatch
                        compiledInRun += inBatch
                    }
                }
            }
        } else {
            // Single-batch fallback directly in psoWorkDirectory
            let activeCount = countTranslateFiles(in: psoWorkDirectory)
            let inBatch = min(total, activeCount)
            done = inBatch
            compiledInRun = inBatch
        }

        maxDone = max(maxDone, done)
        let effectiveDone = min(maxDone, total)
        let fraction = Double(effectiveDone) / Double(total)

        // ETA calculation
        let elapsed = max(0, now.timeIntervalSince(stageStartedAt))
        let eta: Double?
        if compiledInRun > 0, elapsed >= 3, effectiveDone < total {
            let rate = Double(compiledInRun) / elapsed
            let remaining = Double(total - effectiveDone)
            eta = rate > 0 ? (remaining / rate) : nil
        } else {
            eta = nil
        }

        return .progress(
            fraction: fraction,
            done: Double(effectiveDone),
            total: Double(total),
            unit: "pipelines",
            eta: eta,
            elapsed: nil
        )
    }

    private func countTranslateFiles(in directory: URL) -> Int {
        guard let files = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var count = 0
        for file in files where file.hasPrefix("translate-") {
            count += 1
        }
        return count
    }
}
