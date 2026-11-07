import Foundation

/// Which GameBanana mods can work with the engine: only file (RomFS) mods, read through `DM_ROMFS_OVERLAY`. Code
/// mods (exefs, IPS and pchtxt patches) cannot, because nxnative recompiles the game's code at build time.
public enum ModSupport {
    /// The archive path up to and including its RomFS folder ("romfs", "Pack 1.4/romfs",
    /// "atmosphere/contents/<TID>/romfs"), or nil when the file cannot work: no RomFS, more than one RomFS root
    /// (variants in one archive), any code (exefs, exefs_patches, .pchtxt, .ips, main.npdm), or a RomFS meant for
    /// another title ID. Paths under a top-level `cheats` folder are ignored.
    public static func romfsRoot(in paths: [String], titleID: String) -> String? {
        var roots = Set<String>()
        for path in paths {
            let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let first = parts.first, first.lowercased() != "cheats" else { continue }
            if parts.contains(where: isCode) { return nil }
            guard let index = parts.firstIndex(where: { $0.lowercased() == "romfs" }) else { continue }
            let prefix = Array(parts[...index])
            if prefix.contains("..") { return nil }
            if index >= 2, prefix[index - 2].lowercased() == "contents",
               prefix[index - 1].lowercased() != titleID.lowercased() { return nil }
            roots.insert(prefix.joined(separator: "/"))
        }
        return roots.count == 1 ? roots.first : nil
    }

    public static func isVisible(_ summary: GameBananaModSummary) -> Bool {
        !summary.isObsolete && !summary.hasContentRatings
    }

    public static func isVisible(_ profile: GameBananaModProfile) -> Bool {
        !profile.isObsolete && !profile.isPrivate && !profile.isWithheld && !profile.isTrashed
            && profile.contentRatings.isEmpty && !ModRequirements.needsTool(profile.requirements)
    }

    private static func isCode(_ component: String) -> Bool {
        let name = component.lowercased()
        return name == "exefs" || name == "exefs_patches" || name == "main.npdm"
            || name.hasSuffix(".pchtxt") || name.hasSuffix(".ips")
    }
}

/// What a mod's GameBanana Requirements mean here. They are free text, so only clear cases are acted on: a loader or
/// a PC tool the engine cannot run hides the mod (it would install and then not work, or break the game, as exlaunch
/// mods do); notes about a modded Switch or an emulator are left out; everything else (game versions, other mods) is
/// shown in the mod's panel for the player to judge.
public enum ModRequirements {
    /// Loaders and tools: exlaunch-based loaders, Smash's Skyline/ARCropolis, mod managers and mergers that must run
    /// on the game first, and ReShade, which hooks a PC emulator's renderer.
    static let tools = ["exlaunch", "skyline", "arcropolis", "mod loader", "modloader", "mod manager", "tkmm",
                        "recomp", "reshade"]
    static let optionalWords = ["optional", "preferred", "recommended", "not required"]
    static let platformWords = ["hacked", "modded", "emulator", "yuzu", "ryujinx", "atmosphere", "sdcard", "sd card",
                                "cfw", "homebrew"]
    static let platformNames: Set<String> = ["computer", "pc"]

    public static func needsTool(_ requirements: [GameBananaRequirement]) -> Bool {
        requirements.contains { requirement in
            let name = requirement.name.lowercased()
            return !requirement.isOptional && !optionalWords.contains(where: name.contains)
                && tools.contains(where: name.contains)
        }
    }

    public static func shown(_ requirements: [GameBananaRequirement]) -> [GameBananaRequirement] {
        requirements.filter { requirement in
            let name = requirement.name.lowercased()
            return !platformNames.contains(name) && !platformWords.contains(where: name.contains)
        }
    }
}

/// A mod's folder name in the game's mods folder: safe for `DM_ROMFS_OVERLAY` (no `:`), a single path component,
/// visible in Finder, and unique (APFS is case-insensitive by default).
public enum ModFolderName {
    public static let maxLength = 80

    public static func make(from modName: String, modID: Int, existing: Set<String>) -> String {
        let unsafe = CharacterSet(charactersIn: ":/\\").union(.controlCharacters).union(.newlines)
        var name = String(String.UnicodeScalarView(modName.unicodeScalars.map { unsafe.contains($0) ? " " : $0 }))
        name = name.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        while name.hasPrefix(".") || name.hasPrefix(" ") { name.removeFirst() }
        name = String(name.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Mod \(modID)" }

        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)".lowercased()) { number += 1 }
        return "\(name) \(number)"
    }
}
