#!/usr/bin/env python3
"""Check where Back (Esc, controller B) takes Add Game, with the real PortingModel rules.

A finished porting leaves Add Game; a failed new porting returns to its options; a Rebuild,
which never filled the steps before Porting, closes. No window, game or player data.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
porting_source = ''.join(p.read_text() for p in sorted((ROOT / 'Sources/NXLibrary/ViewModels').glob('PortingModel*.swift')))


def declaration(signature, source=porting_source):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


host = '''
import Foundation
enum PortingModel {
    // RULES
}
var failures = 0
func require(_ ok: Bool, _ message: String) {
    if !ok { failures += 1; print("FAIL: " + message) }
}
// Ready to play: Esc leaves, whether the porting was new or a Rebuild.
require(PortingModel.stepBack(from: 3, isBuilding: false, succeeded: true, hasSelectedGame: true) == nil,
        "a finished new porting leaves Add Game")
require(PortingModel.stepBack(from: 3, isBuilding: false, succeeded: true, hasSelectedGame: false) == nil,
        "a finished Rebuild leaves Add Game")
require(!PortingModel.closingAsks(isBuilding: false, succeeded: true, hasDraft: true),
        "leaving after a success never asks to discard the spent files")
// A failure: a new porting returns to its options; a Rebuild has none and closes.
require(PortingModel.stepBack(from: 3, isBuilding: false, succeeded: false, hasSelectedGame: true) == 2,
        "a failed new porting returns to its options")
require(PortingModel.stepBack(from: 3, isBuilding: false, succeeded: false, hasSelectedGame: false) == nil,
        "a failed Rebuild closes instead of a step that was never filled")
// A running porting goes on behind the home.
require(PortingModel.stepBack(from: 3, isBuilding: true, succeeded: false, hasSelectedGame: true) == nil,
        "Back during a porting closes Add Game")
require(!PortingModel.closingAsks(isBuilding: true, succeeded: false, hasDraft: true),
        "closing during a porting never asks")
// The draft steps keep their behaviour.
require(PortingModel.stepBack(from: 2, isBuilding: false, succeeded: false, hasSelectedGame: true) == 1,
        "Options return to the files")
require(PortingModel.stepBack(from: 1, isBuilding: false, succeeded: false, hasSelectedGame: true) == nil,
        "the first step closes")
require(PortingModel.closingAsks(isBuilding: false, succeeded: false, hasDraft: true),
        "closing with chosen files asks first")
require(!PortingModel.closingAsks(isBuilding: false, succeeded: false, hasDraft: false),
        "closing an empty draft does not ask")
require(!PortingModel.wizardStepReachable(2, hasSelectedGame: false), "Options need a chosen game")
require(PortingModel.wizardStepReachable(3, hasSelectedGame: false), "Porting is always reachable")
if failures > 0 { exit(1) }
print("Add Game Back: finished, failed, running and draft steps: PASS")
'''

with tempfile.TemporaryDirectory(prefix='arcane-add-game-back-') as scratch:
    scratch = Path(scratch)
    rules = '\n'.join(declaration(signature) for signature in (
        '    static func wizardStepReachable(',
        '    static func stepBack(',
        '    static func closingAsks('))
    main = scratch / 'main.swift'
    main.write_text(host.replace('// RULES', rules))
    executable = scratch / 'add-game-back'
    subprocess.run(['xcrun', 'swiftc', str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], env=dict(os.environ), check=True)
