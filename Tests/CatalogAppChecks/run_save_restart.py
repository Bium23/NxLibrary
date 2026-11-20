#!/usr/bin/env python3
"""Crash/restart the real save transaction against generated temporary data only.

Run after Core is ready and built with testing enabled. This script only compiles
its helper against .build/debug/NXLibraryCore.o; it never builds or opens the app.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / '.build/debug'
SLOTS = ['account', 'device', *[f'user{i}' for i in range(2, 9)], 'users']
CRASH = 86

HOST = r'''
import Foundation
import Darwin
@testable import NXLibraryCore
@testable import ArcanePorting

let fm = FileManager.default
let slots: [SaveSlot] = [.account, .device, .user2, .user3, .user4,
                         .user5, .user6, .user7, .user8, .users]
let names = ["save", "save_device"] + (2...8).map { "save_user\($0)" } + ["save.users"]
let identity = SaveIdentity(titleID: "0100000000000001", gameName: "Restart fixture",
                            version: "fixture-1", buildID: "synthetic-build")
func require(_ ok: Bool, _ message: String) throws {
    if !ok { throw NSError(domain: "SaveRestartCheck", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: message]) }
}
func write(_ data: Data, to url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}
func payload(_ prefix: String, _ slot: SaveSlot) -> Data {
    Data((slot == .users ? "nxnative-users-1\n\(prefix)\n" : "\(prefix)-\(slot.rawValue)\n").utf8)
}
func content(_ root: URL, _ slot: SaveSlot, _ name: String) -> URL {
    let piece = root.appendingPathComponent(name)
    return slot == .users ? piece : piece.appendingPathComponent("nested/progress")
}
func seed(_ location: SaveLocation, _ prefix: String) throws {
    for (slot, name) in zip(slots, names) {
        try require(location.directory(slot).lastPathComponent == name, "Incorrect path: \(slot)")
        try write(payload(prefix, slot), to: content(location.root, slot, name))
    }
}
func checkGroup(_ root: URL, _ prefix: String) throws {
    for (slot, name) in zip(slots, names) {
        let piece = root.appendingPathComponent(name)
        let kind = try fm.attributesOfItem(atPath: piece.path)[.type] as? FileAttributeType
        try require(kind == (slot == .users ? .typeRegular : .typeDirectory), "Incorrect type: \(name)")
        try require(try Data(contentsOf: content(root, slot, name)) == payload(prefix, slot),
                    "Wrong \(prefix) payload: \(name)")
    }
}
do {
    try require(CommandLine.arguments.count == 4, "Expected mode, fixture path and checkpoint/state")
    let mode = CommandLine.arguments[1], argument = CommandLine.arguments[3]
    let base = URL(fileURLWithPath: CommandLine.arguments[2]).resolvingSymlinksInPath()
    let location = try SaveLocation.defaultLocation(titleID: identity.titleID,
                                                   home: base.appendingPathComponent("home"))
    let store = SaveSnapshotStore(root: base.appendingPathComponent("backups"))
    let targetFile = base.appendingPathComponent("target-id")
    try require(SaveSlot.allCases == slots, "Expected all users, with registry last")
    if mode == "setup" {
        try seed(location, "target")
        let target = try store.create(location: location, identity: identity, reason: .manual)
        try write(Data(target.id.uuidString.utf8), to: targetFile)
        try seed(location, "original")
        try write(Data("working".utf8), to: location.root.appendingPathComponent("save_user2.work/progress"))
        try write(Data("sync".utf8), to: location.root.appendingPathComponent("save.sync"))
    } else {
        guard let targetID = UUID(uuidString: try String(contentsOf: targetFile, encoding: .utf8)) else {
            throw SaveFailure.invalidSnapshot
        }
        if mode == "fail" {
            let target = try store.verify(snapshotID: targetID, titleID: identity.titleID)
            var io = SaveFileIO()
            io.afterMutation = { if $0 == argument { _exit(86) } }
            try SaveTransaction(store: store, isRunning: { false }, io: io)
                .restore(target, location: location, identity: identity)
            try require(false, "Forward checkpoint was not reached: \(argument)")
        } else if mode == "recover" {
            try require(SaveTransaction.needsRecovery(location: location), "Crash left no recovery journal")
            var io = SaveFileIO()
            io.afterMutation = { if $0 == argument { _exit(86) } }
            let transaction = SaveTransaction(store: store, isRunning: { false }, io: io)
            try transaction.recover(location: location)
            try require(argument == "-", "Recovery checkpoint was not reached: \(argument)")
            let once = try store.currentInventory(location: location)
            try transaction.recover(location: location)
            try require(try store.currentInventory(location: location) == once, "Second recovery changed saves")
            try require(!SaveTransaction.needsRecovery(location: location), "Recovery left its journal")
        } else if mode == "check" {
            try require(argument == "target" || argument == "original", "Unknown expected state")
            try require(!SaveTransaction.needsRecovery(location: location), "Recovery is still pending")
            let snapshots = try store.list(titleID: identity.titleID)
            try require(snapshots.count == 2 && snapshots.contains(where: { $0.id == targetID }), "Missing backup")
            for snapshot in snapshots {
                let verified = try store.verify(snapshotID: snapshot.id, titleID: identity.titleID)
                let isTarget = snapshot.id == targetID
                try require(verified == snapshot && verified.identity == identity, "Backup metadata changed")
                try require(verified.schemaVersion == 2 && verified.presentSlots == Set(slots), "Incomplete backup")
                try require(verified.reason == (isTarget ? .manual : .beforeRestore), "Wrong backup reason")
                try checkGroup(try store.directory(snapshotID: snapshot.id, titleID: identity.titleID),
                               isTarget ? "target" : "original")
            }
            let expected = snapshots.first { ($0.id == targetID) == (argument == "target") }!
            try checkGroup(location.root, argument)
            try require(try store.currentInventory(location: location) == expected.entries, "Mixed save group")
            try require(try String(contentsOf: location.root.appendingPathComponent("save_user2.work/progress"), encoding: .utf8)
                        == "working", "Working save changed")
            try require(try String(contentsOf: location.root.appendingPathComponent("save.sync"), encoding: .utf8)
                        == "sync", "Sync sentinel changed")
        } else {
            try require(false, "Unknown helper mode: \(mode)")
        }
    }
} catch {
    fputs("Save restart check failed: \(error)\n", stderr)
    exit(1)
}
'''


def backup_bytes(fixture):
    root = fixture / 'backups'
    return {str(path.relative_to(root)): path.read_bytes()
            for path in root.rglob('*') if path.is_file()}


def main():
    if not (LIBRARY / 'NXLibraryCore.o').is_file():
        raise SystemExit('Core is not ready: build it with testing enabled before running this harness.')
    with tempfile.TemporaryDirectory(prefix='arcane-save-restart-') as scratch:
        scratch = Path(scratch)
        source, binary = scratch / 'main.swift', scratch / 'save-restart'
        source.write_text(HOST)
        subprocess.run(['xcrun', 'swiftc', '-I', str(LIBRARY), str(source),
                        str(LIBRARY / 'NXLibraryCore.o'), str(LIBRARY / 'ArcanePorting.o'), '-o', str(binary)],
                       cwd=ROOT, check=True, timeout=60)
        env = dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(LIBRARY))

        def run(mode, fixture, argument='-', expected=0):
            result = subprocess.run([str(binary), mode, str(fixture), argument],
                                    env=env, capture_output=True, text=True, timeout=30)
            if result.returncode != expected:
                raise RuntimeError(f'{mode} {argument}: exit {result.returncode}, expected {expected}\n'
                                   f'{result.stdout}{result.stderr}')

        cases = [(checkpoint, None) for checkpoint in ['journal', *SLOTS, 'committed', 'cleanup', 'cleanup-item', 'cleanup-stage']]
        # All pieces have been swapped at "users", but the journal is not committed.
        cases += [('users', f'recovery-{slot}') for slot in SLOTS]
        cases += [('users', checkpoint) for checkpoint in ['cleanup', 'cleanup-item', 'cleanup-stage']]
        for checkpoint, recovery_crash in cases:
            label = recovery_crash or checkpoint
            with tempfile.TemporaryDirectory(prefix=f'{label}-', dir=scratch) as fixture:
                fixture = Path(fixture)
                run('setup', fixture)
                run('fail', fixture, checkpoint, expected=CRASH)
                backups = backup_bytes(fixture)
                if recovery_crash:
                    run('recover', fixture, recovery_crash, expected=CRASH)
                # A fresh process resumes, including after a crash inside rollback.
                run('recover', fixture)
                run('check', fixture, 'target' if checkpoint in ['committed', 'cleanup', 'cleanup-item', 'cleanup-stage'] else 'original')
                if backup_bytes(fixture) != backups:
                    raise RuntimeError(f'{label}: recovery changed backup files')
                print(f'Save restart {label}: PASS', flush=True)
        print(f'Save restart checks: PASS ({len(cases)} crash/restart cases)')


if __name__ == '__main__':
    main()
