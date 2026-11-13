#!/usr/bin/env python3
"""Evaluate the actual Steam backdrop body without a window or injected settings.

Only image/gradient children are inert substitutes. This reaches the missing
EnvironmentObject failure in the real parent view; it is not UI automation.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'
source = (ROOT / 'Sources/NXLibrary/Views/Catalog/SteamArtwork.swift').read_text()
start = source.index('struct SteamBackdrop: View {')
opening = source.index('{', start)
end, depth = opening + 1, 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
actual = source[start:end]
explicit = 'let shade: BackgroundShade' in actual
arguments = ', shade: shade, showsArt: shown' if explicit else ''
host = '''import SwiftUI
import NXLibraryCore
struct SteamArtwork: View {
    let game: CatalogGame
    let slot: ArtworkSlot
    var body: some View { Color.clear }
}
struct SeleneShades: View {
    let shade: BackgroundShade
    var body: some View { Color.clear }
}
'''
host += actual
host += '''
@main struct Check {
    @MainActor static func main() {
        let game = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "Fixture"))
        for shade in BackgroundShade.allCases {
            for shown in [true, false] {
                let view = SteamBackdrop(game: game''' + arguments + ''')
                withExtendedLifetime(view.body) {}
            }
        }
        print("Actual Steam backdrop body works without implicit settings, for every shade/wallpaper choice.")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='steam-backdrop-check-') as folder:
    folder = Path(folder)
    swift = folder / 'check.swift'; swift.write_text(host)
    binary = folder / 'check'
    subprocess.run(['xcrun','swiftc','-parse-as-library','-I',str(BIN),str(swift),str(BIN/'NXLibraryCore.o'),'-o',str(binary)],check=True,cwd=ROOT)
    subprocess.run([str(binary)],check=True,env=dict(os.environ,PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
