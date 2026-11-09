import Foundation

/// One entry of a cheat file, as nxnative's host sees it.
public struct CheatEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case cheat, master, label }
    /// The key `<build ID>.enabled` uses: "Max HP", a duplicate's later entries "Max HP #2", "Max HP #3".
    public var name: String
    public var kind: Kind
    public var words: [UInt32]
    /// From EdiZon's section markers or the meta file.
    public var section: String?
    /// From the meta file only.
    public var note: String?
    /// Why the host never runs it ("unsupported opcode B", "malformed line 3"); nil when it runs.
    public var broken: String?
    /// The meta file's "set" cheats: they run one pass, then turn themselves off.
    public var once: Bool
    /// The off (restore) half of an on / off pair: not a switch of its own.
    public var pairOff: Bool
    /// The other half's key.
    public var pairName: String?
    /// The meta file's never-decrease host action: a switch without code words.
    public var neverDecrease: Bool

    var rawName: String
    var metaPairName = ""
    var metaPatchOff = false
}

/// A cheat file read the way the pinned engine reads it (`dm/host/hle_cheats.c`: parse_file, ins_dec, meta_load,
/// pairs_link), which is more forgiving than Atmosphère's dmnt: a bad cheat is marked broken instead of failing the
/// file. Keep it in step with the engine at every re-pin.
public struct CheatFile: Equatable, Sendable {
    public var entries: [CheatEntry]

    /// hle_cheats.c FILE_MAX: a larger file is not a cheat file.
    public static let maxBytes = 4 << 20
    static let maxCheats = 256        // CHEAT_MAX
    static let maxWords = 0x2000      // INS_MAX
    static let nameLimit = 127        // NAME_MAX - 1

    public static func parse(_ text: String) -> CheatFile { parse(Data(text.utf8)) }

    public static func parse(_ data: Data) -> CheatFile {
        guard data.count <= maxBytes else { return CheatFile(entries: []) }
        var file = CheatFile(entries: Parser(Array(data)).run())
        file.linkPairs()
        return file
    }

    /// The bytes NX Library writes as `<build ID>.txt`: without a UTF-8 byte order mark, which the engine would read as
    /// prose in front of the first header (losing that cheat).
    public static func normalized(_ data: Data) -> Data {
        data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
    }

    /// Switches the player sees: runnable cheats that are not masters, labels, the off half of a pair or one-pass.
    public var switches: [CheatEntry] {
        entries.filter { $0.kind == .cheat && $0.broken == nil && !$0.pairOff && !$0.once }
    }

    /// cheats: every cheat a player could see as one (pairs once, broken included); alwaysOn: runnable masters;
    /// notSupported: entries the host never runs.
    public var summary: (cheats: Int, alwaysOn: Int, notSupported: Int) {
        (entries.filter { $0.kind == .cheat && !$0.pairOff }.count,
         entries.filter { $0.kind == .master && $0.broken == nil }.count,
         entries.filter { $0.broken != nil }.count)
    }

    public var summaryText: String {
        let s = summary
        var parts = ["\(s.cheats) \(s.cheats == 1 ? "cheat" : "cheats")"]
        if s.alwaysOn > 0 { parts.append("\(s.alwaysOn) always on") }
        if s.notSupported > 0 { parts.append("\(s.notSupported) not supported") }
        return parts.joined(separator: " · ")
    }

    // MARK: - The meta file

    /// `<build ID>.meta.tsv` (scripts/cheat_anchor.py): columns by header name, rows matched by name in file order.
    public mutating func applyMeta(_ tsv: String) {
        let columns = ["name", "kind", "section", "type", "action", "ask", "value_words", "once", "pair", "resolved", "note", "address"]
        var at: [String: Int] = [:]
        var header = false, cursor = 0
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#") { continue }
            var fields = line.split(separator: "\t", omittingEmptySubsequences: false).prefix(24).map(String.init)
            if let last = fields.indices.last {
                fields[last] = String(fields[last].prefix { $0 != "\r" && $0 != "\n" })
            }
            if !header {
                header = true
                for (i, f) in fields.enumerated() where columns.contains(f) && at[f] == nil { at[f] = i }
                if at["name"] == nil { break }
                continue
            }
            func col(_ k: String) -> String { at[k].flatMap { $0 < fields.count ? fields[$0] : nil } ?? "" }
            let kind = col("kind")
            if kind == "unresolved" { continue }
            guard let j = entries[cursor...].firstIndex(where: { $0.rawName == col("name") }) else { continue }
            cursor = j + 1
            if !col("section").isEmpty && entries[j].section == nil { entries[j].section = col("section") }
            if col("once") == "1" { entries[j].once = true }
            if kind == "patch-off" { entries[j].metaPatchOff = true }
            entries[j].metaPairName = col("pair")
            let resolved = col("resolved"), note = col("note")
            let joined = resolved + (!resolved.isEmpty && !note.isEmpty ? "; " : "") + note
            entries[j].note = joined.isEmpty ? nil : joined
            if col("action") == "never-decrease" && entries[j].words.isEmpty {
                let address = col("address")
                if let colon = address.firstIndex(of: ":"), Self.typeWidth(col("type")) != 0,
                   (Int(address[..<colon].prefix { $0.isNumber }) ?? 0) <= 1 {
                    entries[j].neverDecrease = true
                    entries[j].kind = .cheat
                }
            }
        }
        linkPairs()
    }

    /// hle_cheats.c type_width: "u32" → 4; 0 for anything but 8/16/32/64 bits.
    static func typeWidth(_ type: String) -> Int {
        let bits = Int(type.dropFirst(type.isEmpty ? 0 : 1).prefix { $0.isNumber }) ?? 0
        return [8, 16, 32, 64].contains(bits) ? bits / 8 : 0
    }

    // MARK: - On / off pairs

    /// hle_cheats.c pairs_link: the meta file's pair names first (both halves plain runnable cheats), then the naming
    /// convention ("X - on" / "X - off", "X on", "X: off", "X (off)") for files without one.
    mutating func linkPairs() {
        var pair = [Int](repeating: -1, count: entries.count)
        var off = entries.map(\.metaPatchOff)
        func plain(_ e: CheatEntry) -> Bool { e.kind != .master && e.kind != .label && !e.neverDecrease }
        for i in entries.indices where !entries[i].metaPairName.isEmpty && pair[i] < 0 && plain(entries[i]) && entries[i].broken == nil {
            if let j = entries.indices.first(where: { $0 != i && pair[$0] < 0 && plain(entries[$0]) && entries[$0].broken == nil
                && entries[$0].rawName == entries[i].metaPairName }) {
                pair[i] = j; pair[j] = i
            }
        }
        for i in entries.indices where pair[i] < 0 && plain(entries[i]) {
            guard let a = Self.onOffSplit(entries[i].rawName) else { continue }
            for j in (i + 1)..<entries.count where pair[j] < 0 && plain(entries[j]) {
                guard let b = Self.onOffSplit(entries[j].rawName), a.off != b.off,
                      a.base.caseInsensitiveCompare(b.base) == .orderedSame else { continue }
                pair[i] = j; pair[j] = i; off[i] = a.off; off[j] = b.off
                break
            }
        }
        for i in entries.indices {
            entries[i].pairName = pair[i] >= 0 ? entries[pair[i]].name : nil
            entries[i].pairOff = pair[i] >= 0 ? off[i] : entries[i].metaPatchOff
        }
    }

    /// hle_cheats.c onoff_split: the base name and whether the name is the off half; nil when it has neither form.
    static func onOffSplit(_ name: String) -> (base: String, off: Bool)? {
        var b = Array(name.utf8)
        while let last = b.last, last == 0x20 || (0x09...0x0D).contains(last) { b.removeLast() }
        if let last = b.last, last == UInt8(ascii: ")") || last == UInt8(ascii: "]") { b.removeLast() }
        func ends(_ s: String) -> Bool {
            let t = Array(s.utf8)
            return b.count >= t.count && zip(b.suffix(t.count), t).allSatisfy { ($0 | 0x20) == $1 }
        }
        let off: Bool
        if ends("off") { off = true; b.removeLast(3) } else if ends("on") { off = false; b.removeLast(2) } else { return nil }
        var sep = false
        while let last = b.last, " -:_([".utf8.contains(last) { b.removeLast(); sep = true }
        guard sep, !b.isEmpty else { return nil }
        return (String(decoding: b, as: UTF8.self), off)
    }
}

/// parse_file, byte for byte.
private struct Parser {
    let raw: [UInt8]
    init(_ raw: [UInt8]) { self.raw = raw }

    private struct Building {
        var entry: CheatEntry
        var junkLine = 0
    }

    private static func isHex(_ c: UInt8) -> Bool {
        (0x30...0x39).contains(c) || (0x41...0x46).contains(c) || (0x61...0x66).contains(c)
    }

    private static func hexValue(_ c: UInt8) -> UInt32 {
        switch c {
        case 0x30...0x39: return UInt32(c - 0x30)
        case 0x41...0x46: return UInt32(c - 0x41 + 10)
        default: return UInt32(c - 0x61 + 10)
        }
    }

    /// read_text: a header right after a whole code word (that word at the file's start or after whitespace) starts a
    /// piece of its own, marked with '\v'.
    private func pieces() -> [(bytes: ArraySlice<UInt8>, line: Int)] {
        var out: [UInt8] = []
        out.reserveCapacity(raw.count + 16)
        for i in raw.indices {
            let c = raw[i]
            if (c == UInt8(ascii: "[") || c == UInt8(ascii: "{")) && i >= 8,
               raw[(i - 8)..<i].allSatisfy(Self.isHex),
               i == 8 || [0x20, 0x09, 0x0A, 0x0D].contains(raw[i - 9]) {
                out.append(0x0B)
            }
            out.append(c)
        }
        var result: [(ArraySlice<UInt8>, Int)] = []
        var start = 0, line = 1
        for i in out.indices where out[i] == 0x0A || out[i] == 0x0B {
            result.append((out[start..<i], line))
            if out[i] == 0x0A { line += 1 }
            start = i + 1
        }
        result.append((out[start...], line))
        return result
    }

    func run() -> [CheatEntry] {
        var cheats: [Building] = []
        var current: Int?
        var section = ""
        for (piece, line) in pieces() {
            var p = piece.startIndex
            while p < piece.endIndex, piece[p] == 0x20 || piece[p] == 0x09 { p += 1 }
            var rest = piece[p...]
            if let first = rest.first, first == UInt8(ascii: "[") || first == UInt8(ascii: "{") {
                let end = first == UInt8(ascii: "[") ? UInt8(ascii: "]") : UInt8(ascii: "}")
                let q = rest.firstIndex(of: end)
                let length = q.map { $0 - rest.startIndex - 1 } ?? 0
                guard let q, length > 0, cheats.count < CheatFile.maxCheats else { current = nil; continue }
                var keep = min(length, CheatFile.nameLimit)
                if length > CheatFile.nameLimit {
                    while keep > 0 && rest[rest.startIndex + 1 + keep] & 0xC0 == 0x80 { keep -= 1 }
                }
                let nameBytes = rest[(rest.startIndex + 1)..<(rest.startIndex + 1 + keep)]
                let name = String(decoding: nameBytes, as: UTF8.self)
                var marker: (kind: Int, name: String)?
                if name.hasSuffix("--"), name.utf8.count >= 4 {
                    for (prefix, kind) in [("--SectionStart:", 1), ("--SectionEnd:", 2)] where name.hasPrefix(prefix) {
                        marker = (kind, String(name.dropFirst(prefix.count).dropLast(2)))
                    }
                }
                if marker?.kind == 1 { section = marker!.name }
                let entrySection = marker?.kind == 1 ? marker!.name : section
                if marker?.kind == 2 { section = "" }
                let dup = cheats.filter { $0.entry.rawName == name }.count
                cheats.append(Building(entry: CheatEntry(
                    name: dup > 0 ? "\(name) #\(dup + 1)" : name, kind: end == UInt8(ascii: "}") ? .master : .cheat,
                    words: [], section: entrySection.isEmpty ? nil : entrySection, note: nil, broken: nil,
                    once: false, pairOff: false, pairName: nil, neverDecrease: false, rawName: name)))
                current = cheats.count - 1
                var after = q + 1
                while after < rest.endIndex, [0x20, 0x09, 0x0D].contains(rest[after]) { after += 1 }
                if after >= rest.endIndex { continue }
                rest = rest[after...]
            }
            guard let c = current else { continue }
            var got: [UInt32] = []
            var prose = false, oddHex = false
            tokens: for token in rest.split(whereSeparator: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) {
                if !token.allSatisfy(Self.isHex) { prose = true; continue }
                if token.count % 8 != 0 { oddHex = true; continue }
                var k = token.startIndex
                while k < token.endIndex {
                    guard got.count < CheatFile.maxWords else { break tokens }
                    got.append(token[k..<(k + 8)].reduce(UInt32(0)) { $0 << 4 | Self.hexValue($1) })
                    k += 8
                }
            }
            if got.isEmpty && !prose && !oddHex { continue }
            if prose && got.isEmpty && !oddHex {
                if cheats[c].junkLine == 0 { cheats[c].junkLine = line }
                continue
            }
            if prose || oddHex {
                if cheats[c].entry.broken == nil { cheats[c].entry.broken = "malformed line \(line)" }
                continue
            }
            if cheats[c].entry.words.count + got.count > CheatFile.maxWords { continue }
            cheats[c].entry.words += got
        }
        return cheats.map { building in
            var e = building.entry
            if e.broken != nil { return e }
            if e.words.isEmpty {
                if building.junkLine > 0 { e.broken = "no code words: line \(building.junkLine) is not code" } else { e.kind = .label }
                return e
            }
            var a = 0
            while a < e.words.count {
                switch CheatDecoder.length(e.words[a...]) {
                case .success(let len): a += len
                case .failure(let why): e.broken = why.reason; return e
                }
            }
            return e
        }
    }
}

/// ins_dec: how many words the instruction at the slice's start takes, or why the host never runs it.
enum CheatDecoder {
    struct Refusal: Error { let reason: String }

    static func opKind(_ w: UInt32) -> UInt32 {
        var op = w >> 28
        if op >= 0xC { op = op << 4 | (w >> 24 & 0xF) }
        if op >= 0xF0 { op = op << 4 | (w >> 20 & 0xF) }
        return op
    }

    static func length(_ p: ArraySlice<UInt32>) -> Result<Int, Refusal> {
        guard let w = p.first else { return .failure(Refusal(reason: L10n.text("truncated"))) }
        let n = p.count
        func refuse(_ r: String) -> Result<Int, Refusal> { .failure(Refusal(reason: r)) }
        func widthOK(_ t: UInt32) -> Bool { t == 1 || t == 2 || t == 4 || t == 8 }
        var len = 1
        let op = opKind(w)
        switch op {
        case 0, 1:
            let t = w >> 24 & 0xF
            guard widthOK(t) else { return refuse("width") }
            if op == 1, !(1...6).contains(w >> 16 & 0xF) { return refuse("condition") }
            guard n >= 2 else { return refuse("truncated") }
            if t == 8 { guard n >= 4 else { return refuse("truncated") }; len = 4 } else { len = 3 }
        case 2:
            len = 1
        case 3:
            if w >> 24 & 0xF == 0 { guard n >= 2 else { return refuse("truncated") }; len = 2 }
        case 4:
            guard n >= 3 else { return refuse("truncated") }
            len = 3
        case 5:
            guard widthOK(w >> 24 & 0xF) else { return refuse("width") }
            guard w >> 12 & 0xF <= 3 else { return refuse("operand") }
            guard n >= 2 else { return refuse("truncated") }
            len = 2
        case 6:
            guard widthOK(w >> 24 & 0xF) else { return refuse("width") }
            guard n >= 3 else { return refuse("truncated") }
            len = 3
        case 7:
            guard widthOK(w >> 24 & 0xF) else { return refuse("width") }
            guard w >> 12 & 0xF <= 4 else { return refuse("arithmetic") }
            guard n >= 2 else { return refuse("truncated") }
            len = 2
        case 8:
            len = 1
        case 9:
            let t = w >> 24 & 0xF
            guard widthOK(t) else { return refuse("width") }
            if w >> 8 & 0xF != 0 {
                guard n >= (t == 8 ? 3 : 2) else { return refuse("truncated") }
                len = t == 8 ? 3 : 2
            }
        case 0xA:
            guard widthOK(w >> 24 & 0xF) else { return refuse("width") }
            let o = w >> 8 & 0xF
            guard o <= 5 else { return refuse("operand") }
            if o == 2 || o == 4 || o == 5 { guard n >= 2 else { return refuse("truncated") }; len = 2 }
        case 0xC0:
            let t = w >> 20 & 0xF
            guard widthOK(t) else { return refuse("width") }
            guard (1...6).contains(w >> 16 & 0xF) else { return refuse("condition") }
            switch w >> 8 & 0xF {
            case 0, 2: guard n >= 2 else { return refuse("truncated") }; len = 2
            case 1, 3, 5: len = 1
            case 4: guard n >= (t == 8 ? 3 : 2) else { return refuse("truncated") }; len = t == 8 ? 3 : 2
            default: return refuse("operand")
            }
        case 0xC1, 0xC2, 0xC3:
            len = 1
        case 0xC4:
            guard n >= 3 else { return refuse("truncated") }
            len = 3
        default:
            return refuse("unsupported opcode \(String(op, radix: 16, uppercase: true))")
        }
        return len > n ? refuse("truncated") : .success(len)
    }
}
