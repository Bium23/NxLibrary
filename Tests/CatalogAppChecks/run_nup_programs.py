#!/usr/bin/env python3
"""Check real NUP probe/converters, persistence and rebuild arguments without app UI.

An optional immutable engine snapshot runs its synthetic edition fixture through
Arcane's actual embedded Python probe. No checkout, game content or keys are used.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--engine-snapshot', type=Path)
parser.add_argument('--python', default='python3')
args = parser.parse_args()
source = ''.join(p.read_text() for p in sorted((ROOT / 'Sources/NXLibrary/ViewModels').glob('AppViewModel*.swift')))
porting_source = ''.join(p.read_text() for p in sorted((ROOT / 'Sources/NXLibrary/ViewModels').glob('PortingModel*.swift')))


def declaration(signature, source=source):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private static func', 'static func', 1)


with tempfile.TemporaryDirectory(prefix='arcane-nup-check-') as scratch:
    scratch = Path(scratch)
    output = 'title 0400F00000010001\napplication 0100F00000010000\naoc_base 0100F00000011000\nbase 272\ndlc 0100F00000011001 2\n'
    if args.engine_snapshot:
        bridge = (ROOT / 'Sources/NXLibraryCore/Porting/Build/NUPSourceCatalog.swift').read_text()
        probe = bridge.split('let script = #"""', 1)[1].split('"""#', 1)[0]
        generator = """
import pathlib,sys
repo=pathlib.Path(sys.argv[1])
sys.path.insert(0,str(repo/'dm/tools/tests'))
import test_nsp_nup as fixture
fixture.write_nup(pathlib.Path(sys.argv[2]),fixture.edition())
"""
        nup = scratch / 'synthetic.nup'
        subprocess.run([args.python, '-I', '-B', '-c', generator, str(args.engine_snapshot), str(nup)], check=True)
        result = subprocess.run([args.python, '-I', '-B', '-c', probe, str(args.engine_snapshot), str(nup)],
                                check=True, text=True, capture_output=True, timeout=20)
        output = result.stdout
    wire = scratch / 'probe.txt'
    wire.write_text(output)
    host = '''
import Foundation
@testable import NXLibraryCore
struct Host {
    // CONVERTERS
}
let scratch = URL(fileURLWithPath: CommandLine.arguments[1])
let wire = try String(contentsOf: scratch.appendingPathComponent("probe.txt"), encoding: .utf8)
let nup = scratch.appendingPathComponent("synthetic.nup")
let game = try NUPSourceCatalog.parse(wire, nup: nup, fileSize: 400,
    profiles: scratch.appendingPathComponent("profiles"), provisional: true)
precondition(game.baseTitleId == 0x0400F00000010001)
let ui = Host.selectableGame(from: game)
precondition(ui.titleId == "0400F00000010001")
let persisted = try JSONEncoder().encode(ui.files)
let restored = try JSONDecoder().decode([GameFileItem].self, from: persisted)
let detected = restored.compactMap { Host.detectedSource(from: $0) }
precondition(detected.count == game.allSources.count)
precondition(detected.allSatisfy { $0.nupProgram?.applicationID == 0x0100F00000010000 && $0.nupProgram?.index == 1 })
precondition(detected.first(where: { $0.kind == .dlc })?.titleId == 0x0100F00000011001)
precondition(SourceSelection.supported(restored, titleSelection: true, extractedFolders: true,
    nupContainers: true, nupPrograms: true))
let command = BuildCommandBuilder.make(repo: scratch, toolchain: EngineToolchain(python: scratch.appendingPathComponent("python"),
    extraPath: [], isBundled: true), workspace: scratch, keys: nil, output: scratch.appendingPathComponent("Game.app"),
    developerDir: scratch, titleId: ui.titleId,
    programIndex: SourceSelection.programIndex(for: restored, titleID: ui.titleId!, nupPrograms: true))
precondition(command.arguments[command.arguments.firstIndex(of: "--program")! + 1] == "1")
print("NUP probe → real UI converters → persisted sources → rebuild program: PASS")
'''
    methods = '\n'.join((declaration('    static func selectableGame(from game:', porting_source),
                          declaration('    static func detectedSource(from file:', source=porting_source)))
    main = scratch / 'main.swift'
    main.write_text(host.replace('// CONVERTERS', methods))
    library = ROOT / '.build/debug'
    executable = scratch / 'nup-check'
    subprocess.run(['xcrun', 'swiftc', '-I', str(library), str(main),
                    str(ROOT / 'Sources/NXLibrary/Models/SelectableGame.swift'),
                    str(library / 'NXLibraryCore.o'), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(scratch)], env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(library)), check=True)
