#!/usr/bin/env python3
"""Check the square icon art lookup with no windows or player data.

Compile the actual GameIconProvider: a game with no icon on disk is not read again on every
draw of its tile, and an icon that arrives later shows once the game is forgotten or built.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'

host = r'''
import AppKit
import NXLibraryCore

@main struct Check {
    static func main() throws {
        var failures = 0
        func require(_ ok: Bool, _ message: String) {
            if !ok { failures += 1; print("FAIL: " + message) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("icon-cache-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("workspace")
        let titleID = "0100000000001000"
        let iconFolder = workspace.appendingPathComponent("\(titleID)_build/extract/v0")
        try FileManager.default.createDirectory(at: iconFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var game = PortedGame(name: "Fixture", url: root.appendingPathComponent("not-built"),
                              platform: .macApp, sizeBytes: 0, modificationDate: Date(), titleId: titleID)
        game.workspacePath = workspace.path
        require(GameIconProvider.squareArt(for: game) == nil, "no icon on disk gives no square art")

        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); image.unlockFocus()
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: iconFolder.appendingPathComponent("icon.jpg"))
        require(GameIconProvider.squareArt(for: game) == nil,
                "a game with no icon is not read from disk again on the next draw")

        GameIconProvider.forget(game)
        require(GameIconProvider.squareArt(for: game) != nil, "forgetting the game reads its new icon")

        var other = PortedGame(name: "Other", url: root.appendingPathComponent("other-not-built"),
                               platform: .macApp, sizeBytes: 0, modificationDate: Date(), titleId: "0100000000002000")
        other.workspacePath = root.appendingPathComponent("other").path
        require(GameIconProvider.squareArt(for: other) == nil, "a second game with no icon gives no square art")
        let otherFolder = root.appendingPathComponent("other/0100000000002000_build/extract/v0")
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        try png.write(to: otherFolder.appendingPathComponent("icon.jpg"))
        other.url = root.appendingPathComponent("Other.app")
        require(GameIconProvider.squareArt(for: other) != nil, "a game that moved to its built app is looked up again")

        if failures > 0 { exit(1) }
        print("Icon cache checks passed: missing icons are remembered, forgetting and building look again.")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='icon-cache-check-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(swift),
                    str(ROOT / 'Sources/NXLibrary/Views/Components/GameIconProvider.swift'),
                    str(BIN / 'NXLibraryCore.o'), '-o', str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable)], env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)), check=True)
