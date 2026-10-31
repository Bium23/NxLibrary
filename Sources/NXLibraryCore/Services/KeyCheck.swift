// Adapted from NX2Apple's KeyCheck.swift (https://github.com/LNPANDY/NX2Apple), MIT License,
// Copyright (c) 2026 LNPANDY and NX2Apple contributors. See NOTICE.

import Foundation
import CommonCrypto

/// Checks the imported prod.keys against a game's files before a porting. A porting with keys that
/// are too old for the game, or a header_key that does not open it, used to fail minutes in, in the
/// extraction step. The same answer is in the first kilobyte of each NCA: its header, encrypted with
/// header_key, names the key generation the content needs.
///
/// What is read: the PFS0 table of an NSP or NSZ and the first 0x400 bytes of each NCA (an NCZ keeps
/// its NCA header uncompressed). An XCI's NCAs sit in nested HFS0 partitions, so it is reported as
/// not checkable rather than guessed at. Key values are never returned, logged or shown: only names.
public enum KeyCheck {
    public enum Part: String, Sendable { case base, update, dlc }

    public enum Outcome: Equatable, Sendable {
        case fits
        case unreadableKeys
        case noHeaderKey
        /// header_key decrypts none of the file's NCA headers.
        case wrongHeaderKey(file: String)
        /// The newest generation a file needs and the key of it the file lacks (its name, never its value).
        case tooOld(part: Part, generation: Int, missing: String)
        case cannotCheck(file: String)

        /// Only a certain mismatch stops a porting.
        public var blocks: Bool {
            switch self {
            case .wrongHeaderKey, .tooOld, .noHeaderKey, .unreadableKeys: return true
            case .fits, .cannotCheck: return false
            }
        }
    }

    /// The firmware that brought each master key revision (hactool's table); index = generation − 1.
    static let firmwareTable = ["1.0.0", "3.0.0", "3.0.1", "4.0.0", "5.0.0", "6.0.0", "6.2.0", "7.0.0", "8.1.0", "9.0.0",
                                "9.1.0", "12.1.0", "13.0.0", "14.0.0", "15.0.0", "16.0.0", "17.0.0", "18.0.0", "19.0.0", "20.0.0"]

    public static func firmware(forGeneration generation: Int) -> String? {
        firmwareTable.indices.contains(generation - 1) ? firmwareTable[generation - 1] : nil
    }

    // MARK: - prod.keys

    /// `name = hex` lines, names lowercased; comments, blank lines and non-hex values are skipped.
    public static func parseKeys(_ text: String) -> [String: [UInt8]] {
        var keys: [String: [UInt8]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            if !name.isEmpty, let value = hex(parts[1].trimmingCharacters(in: .whitespaces)) { keys[name] = value }
        }
        return keys
    }

    static func hex(_ s: String) -> [UInt8]? {
        let chars = Array(s.utf8)
        guard !chars.isEmpty, chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x41...0x46: return c - 0x41 + 10
        case 0x61...0x66: return c - 0x61 + 10
        default: return nil
        }
    }

    // MARK: - AES-XTS

    /// AES-128-XTS over whole sectors, as Nintendo uses it for NCA headers: the 32-byte key is the
    /// data key then the tweak key, and the tweak is the sector number big-endian (IEEE 1619 has it
    /// little-endian). CommonCrypto has no XTS mode, so it is built on ECB.
    public static func xts(_ data: [UInt8], key: [UInt8], sector: UInt64 = 0, sectorSize: Int = 0x200,
                           encrypt: Bool) -> [UInt8]? {
        guard key.count == 32, sectorSize > 0, sectorSize % 16 == 0, data.count % sectorSize == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        for (i, start) in stride(from: 0, to: data.count, by: sectorSize).enumerated() {
            var tweak = [UInt8](repeating: 0, count: 16)
            var n = sector + UInt64(i)
            for b in (8..<16).reversed() { tweak[b] = UInt8(n & 0xFF); n >>= 8 }
            guard let s = xtsSector(Array(data[start..<start + sectorSize]), dataKey: Array(key[0..<16]),
                                    tweakKey: Array(key[16..<32]), tweak: tweak, encrypt: encrypt) else { return nil }
            out += s
        }
        return out
    }

    private static func xtsSector(_ data: [UInt8], dataKey: [UInt8], tweakKey: [UInt8], tweak: [UInt8],
                                  encrypt: Bool) -> [UInt8]? {
        guard data.count % 16 == 0, var t = ecb(tweak, key: tweakKey, encrypt: true) else { return nil }
        var masks: [UInt8] = []
        masks.reserveCapacity(data.count)
        for _ in 0..<(data.count / 16) {
            masks += t
            // Multiply by x in GF(2^128), bytes little-endian.
            var carry: UInt8 = 0
            for j in 0..<16 { let c = t[j] >> 7; t[j] = t[j] << 1 | carry; carry = c }
            if carry != 0 { t[0] ^= 0x87 }
        }
        guard let y = ecb(zip(data, masks).map { $0 ^ $1 }, key: dataKey, encrypt: encrypt) else { return nil }
        return zip(y, masks).map { $0 ^ $1 }
    }

    private static func ecb(_ data: [UInt8], key: [UInt8], encrypt: Bool) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: data.count)
        var moved = 0
        let status = CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionECBMode), key, key.count, nil, data, data.count, &out, out.count, &moved)
        return status == kCCSuccess && moved == data.count ? out : nil
    }

    // MARK: - NCA headers

    /// The two header sectors: the magic at 0x200, both generation fields and the rights ID.
    public static let headerBytes = 0x400

    /// The key a decrypted header needs and its master key revision; nil when it is not an NCA header.
    /// The revision is the larger generation field minus one when not zero, as LibHac derives it.
    /// Rights-ID content opens through its title key (titlekek_XX); other content through the key
    /// area (key_area_key_<application|ocean|system>_XX, the index at 0x207).
    public static func needs(header h: [UInt8]) -> (revision: Int, key: String)? {
        guard h.count >= headerBytes else { return nil }
        let magic = String(bytes: h[0x200..<0x204], encoding: .ascii) ?? ""
        guard magic == "NCA3" || magic == "NCA2" else { return nil }
        let generation = Int(max(h[0x206], h[0x220]))
        let revision = generation == 0 ? 0 : generation - 1
        let suffix = String(format: "%02x", revision)
        if h[0x230..<0x240].contains(where: { $0 != 0 }) { return (revision, "titlekek_" + suffix) }
        let areas = ["application", "ocean", "system"]
        guard Int(h[0x207]) < areas.count else { return nil }
        return (revision, "key_area_key_\(areas[Int(h[0x207])])_" + suffix)
    }

    /// A derived key counts when it is in the file or its master key is: LibHac derives the others,
    /// and some dumps list only the master keys.
    public static func has(_ key: String, in keys: [String: [UInt8]]) -> Bool {
        if keys[key]?.count == 16 { return true }
        guard let suffix = key.split(separator: "_").last else { return false }
        return keys["master_key_" + suffix]?.count == 16
    }

    public enum Container {
        /// The encrypted headers of the package's NCAs, each with whether it is an NCZ.
        case pfs0([(header: [UInt8], ncz: Bool)])
        case unsupported
    }

    /// The NCA headers of an NSP or NSZ (a PFS0); anything else, an XCI among them, is `unsupported`.
    public static func readContainer(_ url: URL) -> Container {
        guard let f = try? FileHandle(forReadingFrom: url) else { return .unsupported }
        defer { try? f.close() }
        func read(_ offset: UInt64, _ count: Int) -> [UInt8]? {
            guard (try? f.seek(toOffset: offset)) != nil, let d = try? f.read(upToCount: count), d.count == count
            else { return nil }
            return [UInt8](d)
        }
        func u32(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        func u64(_ b: [UInt8], _ o: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 | UInt64(b[o + $1]) << (8 * $1) } }
        guard let head = read(0, 0x10), head[0..<4].elementsEqual("PFS0".utf8) else { return .unsupported }
        let count = u32(head, 4), names = u32(head, 8)
        guard count > 0, count <= 4096, names <= 1 << 20, let table = read(0x10, count * 0x18 + names)
        else { return .unsupported }
        let dataStart = UInt64(0x10 + count * 0x18 + names)
        var headers: [(header: [UInt8], ncz: Bool)] = []
        for i in 0..<count {
            let e = i * 0x18
            let offset = u64(table, e), size = u64(table, e + 8), nameAt = count * 0x18 + u32(table, e + 0x10)
            guard nameAt < table.count else { continue }
            let name = String(decoding: table[nameAt...].prefix { $0 != 0 }, as: UTF8.self).lowercased()
            let ncz = name.hasSuffix(".ncz")
            guard name.hasSuffix(".nca") || ncz, size >= UInt64(headerBytes),
                  let h = read(dataStart + offset, headerBytes) else { continue }
            headers.append((h, ncz))
        }
        return .pfs0(headers)
    }

    // MARK: - The check

    /// Every file against the keys; the worst finding wins: a key that opens nothing, then the newest
    /// missing generation, then a file that cannot be checked. Reads a few kilobytes per file, so it is
    /// quick, but it reads files: call it off the main thread.
    public static func run(keysURL: URL, files: [(part: Part, url: URL)]) -> Outcome {
        guard let data = FileManager.default.contents(atPath: keysURL.path),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return .unreadableKeys }
        return check(keys: parseKeys(text),
                     files: files.map { ($0.part, $0.url.lastPathComponent, readContainer($0.url)) })
    }

    public static func check(keys: [String: [UInt8]],
                             files: [(part: Part, name: String, container: Container)]) -> Outcome {
        guard let headerKey = keys["header_key"], headerKey.count == 32 else { return .noHeaderKey }
        var tooOld: (part: Part, revision: Int, key: String)?
        var unchecked: String?
        for file in files {
            guard case let .pfs0(ncas) = file.container, !ncas.isEmpty else {
                unchecked = unchecked ?? file.name
                continue
            }
            // A damaged NCA among good ones is the file's problem, not the keys': only a key that opens none is wrong.
            let opened = ncas.compactMap { nca -> (revision: Int, key: String)? in
                guard let plain = xts(nca.header, key: headerKey, encrypt: false) else { return nil }
                return needs(header: plain)
            }
            if opened.isEmpty {
                // An NCZ's header is taken on trust; if it does not open, that is not proof against the key.
                if ncas.allSatisfy(\.ncz) { unchecked = unchecked ?? file.name; continue }
                return .wrongHeaderKey(file: file.name)
            }
            for need in opened where !has(need.key, in: keys) && need.revision > (tooOld?.revision ?? -1) {
                tooOld = (file.part, need.revision, need.key)
            }
        }
        if let tooOld { return .tooOld(part: tooOld.part, generation: tooOld.revision + 1, missing: tooOld.key) }
        if let unchecked { return .cannotCheck(file: unchecked) }
        return .fits
    }
}
