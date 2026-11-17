#!/usr/bin/env python3
"""Exercise installation and icon changes on signed, synthetic nested data bundles.

Uses the nxnative data-bundle layout and relative Resources links, real codesign
and the production Swift installer/icon writer. No UI, engine checkout, keys or
game data. The cross-volume branch is forced on the temporary fixture volume;
this does not replace a real external-volume or engine-build check.
Run after swift test.
"""
from pathlib import Path
import os
import plistlib
import struct
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'


def run(*args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stderr or result.stdout or f'Command failed: {args[0]}')
    return result


def plist(path, values):
    path.write_bytes(plistlib.dumps(values))


def signed_app(path, executable, version):
    contents = path / 'Contents'
    resources = contents / 'Resources'
    resources.mkdir(parents=True)
    (contents / 'MacOS').mkdir()
    for target in (contents / 'MacOS/nxnative', contents / 'MacOS/dmhost'):
        target.write_bytes(executable.read_bytes())
        target.chmod(0o755)
        run('/usr/bin/codesign', '--force', '--sign', '-', target)
    plist(contents / 'Info.plist', {
        'CFBundleIdentifier': 'org.arcane.contractfixture', 'CFBundleName': 'Fixture',
        'CFBundleExecutable': 'nxnative', 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': str(version), 'CFBundleShortVersionString': str(version),
    })
    for name, top in (
        ('GameData', 'romfs.img'), ('ShaderLibraries', 'msl'),
        ('PipelineArchive', 'pso'), ('AddOnContent', 'aoc'),
        ('GameDataPrograms', 'romfs_programs'), ('GameData1', 'p1/romfs.img'),
    ):
        bundle = contents / 'PlugIns' / (name + '.bundle')
        inner = bundle / 'Contents/Resources'
        inner.mkdir(parents=True)
        plist(bundle / 'Contents/Info.plist', {
            'CFBundleIdentifier': 'org.arcane.contractfixture.data.' + name.lower(),
            'CFBundleName': name, 'CFBundlePackageType': 'BNDL', 'CFBundleVersion': '1',
        })
        payload = inner / top
        if top.endswith('.img'):
            payload.parent.mkdir(parents=True, exist_ok=True)
        else:
            payload.mkdir()
            payload /= 'synthetic.bin'
        payload.write_bytes(f'{name}:version:{version}'.encode())
        link = resources / top
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(os.path.relpath(inner / top, link.parent))
        run('/usr/bin/codesign', '--force', '--sign', '-', bundle)
    run('/usr/bin/codesign', '--force', '--sign', '-', path)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', path)


with tempfile.TemporaryDirectory(prefix='arcane-nested-check-') as temporary:
    scratch = Path(temporary)
    code = scratch / 'fixture.c'
    code.write_text('int main(void) { return 0; }\n')
    executable = scratch / 'fixture'
    run('xcrun', 'clang', code, '-o', executable)
    signed_app(scratch / 'old.app', executable, 1)
    signed_app(scratch / 'rebuilt.app', executable, 2)

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    # A generated 32 x 32 solid-colour PNG; no external artwork.
    pixels = (b'\0' + b'\x40\x80\xc0\xff' * 32) * 32
    (scratch / 'icon.png').write_bytes(
        b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 32, 32, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))
    main = scratch / 'main.swift'
    main.write_text(r'''
import Foundation
import CryptoKit
@testable import NXLibraryCore

struct CheckFailure: Error {}
func require(_ condition: @autoclosure () throws -> Bool) throws {
    if try !condition() { throw CheckFailure() }
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
let runner = SystemCommandRunner()
let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
func verify(_ app: URL) throws {
    let result = try runner.run(codesign, ["--verify", "--deep", "--strict", app.path],
                                environment: nil, currentDirectory: nil)
    try require(result.status == 0)
}
func digest(_ folder: URL) throws -> String {
    let paths = try fm.subpathsOfDirectory(atPath: folder.path).sorted()
    var hash = SHA256()
    for path in paths {
        let file = folder.appendingPathComponent(path)
        let attributes = try fm.attributesOfItem(atPath: file.path)
        hash.update(data: Data(path.utf8))
        if attributes[.type] as? FileAttributeType == .typeRegular {
            hash.update(data: try Data(contentsOf: file))
        }
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func links(_ app: URL) throws -> [String: String] {
    let res = app.appendingPathComponent("Contents/Resources")
    let tops = ["romfs.img", "msl", "pso", "aoc", "romfs_programs", "p1/romfs.img"]
    return try Dictionary(uniqueKeysWithValues: tops.map { top in
        let file = res.appendingPathComponent(top)
        let link = try fm.destinationOfSymbolicLink(atPath: file.path)
        try require(!link.hasPrefix("/"))
        try require(fm.fileExists(atPath: file.path))
        let resolved = file.resolvingSymlinksInPath().path
        try require(resolved.hasPrefix(app.appendingPathComponent("Contents/PlugIns").path + "/"))
        return (top, link)
    })
}
func dataSeal(_ app: URL) throws -> String {
    try digest(app.appendingPathComponent("Contents/PlugIns"))
}
func hostBytes(_ app: URL) throws -> Data {
    try Data(contentsOf: app.appendingPathComponent("Contents/MacOS/dmhost"))
}
let source = root.appendingPathComponent("old.app")
let destination = root.appendingPathComponent("Installed/Game.app")
let originalSeal = try dataSeal(source)
let originalLinks = try links(source)
let originalHost = try hostBytes(source)
try BuildOutputInstaller.install(tempApp: source, finalApp: destination)
try verify(destination)
try require(try dataSeal(destination) == originalSeal)
try require(try links(destination) == originalLinks)
try require(try hostBytes(destination) == originalHost)
print("Same-volume install preserves nested signatures and relative links: PASS")

let writer = AppIconWriter(backups: root.appendingPathComponent("backups"))
let png = try Data(contentsOf: root.appendingPathComponent("icon.png"))
try writer.apply(image: png, to: destination, key: "fixture")
try verify(destination)
try require(writer.showsWrittenIcon(destination))
try require(try dataSeal(destination) == originalSeal)
try require(try hostBytes(destination) == originalHost)
try writer.restore(destination, key: "fixture")
try verify(destination)
try require(!writer.showsWrittenIcon(destination))
try require(try dataSeal(destination) == originalSeal)
try require(try links(destination) == originalLinks)
try require(try hostBytes(destination) == originalHost)
print("Real icon write and restore preserve nested signatures: PASS")

struct FailVerification: CommandRunning {
    func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
             currentDirectory: URL?) throws -> CommandResult {
        if executable.lastPathComponent == "codesign" && arguments.contains("--verify") {
            return CommandResult(status: 1, stdout: "", stderr: "synthetic verification failure")
        }
        return try SystemCommandRunner().run(executable, arguments, environment: environment,
                                              currentDirectory: currentDirectory)
    }
}
let beforeFailure = try digest(destination)
let failing = AppIconWriter(backups: root.appendingPathComponent("rollback-backups"), runner: FailVerification())
do {
    try failing.apply(image: png, to: destination, key: "fixture")
    throw CheckFailure()
} catch AppIconWriter.Failure.signingFailed { }
try verify(destination)
try require(try digest(destination) == beforeFailure)
print("Failed verification restores the original signed app: PASS")

let rebuilt = root.appendingPathComponent("rebuilt.app")
let rebuiltSeal = try dataSeal(rebuilt)
let rebuiltLinks = try links(rebuilt)
let rebuiltHost = try hostBytes(rebuilt)
var io = BuildInstallIO()
io.sameVolume = { _, _ in false }
io.afterPublish = { throw CocoaError(.userCancelled) }
do {
    try BuildOutputInstaller.install(tempApp: rebuilt, finalApp: destination, io: io)
    throw CheckFailure()
} catch let error as CocoaError where error.code == .userCancelled { }
try verify(destination)
io.afterPublish = {}
try BuildOutputInstaller.install(tempApp: rebuilt, finalApp: destination, io: io)
try verify(destination)
try require(try dataSeal(destination) == rebuiltSeal)
try require(try links(destination) == rebuiltLinks)
try require(try hostBytes(destination) == rebuiltHost)
try require(BuildOutputInstaller.version(of: destination) == "2")
print("Copied rebuild and interrupted-publication retry preserve the new app: PASS")

let payload = destination.appendingPathComponent("Contents/Resources/romfs.img")
let original = try Data(contentsOf: payload)
try Data("tampered".utf8).write(to: payload)
let rejected = try runner.run(codesign, ["--verify", "--deep", "--strict", destination.path],
                               environment: nil, currentDirectory: nil)
try require(rejected.status != 0)
try original.write(to: payload)
try verify(destination)
print("Deep verification rejects changed nested payloads: PASS")
''')
    host = scratch / 'check'
    run('xcrun', 'swiftc', '-I', BIN, main, BIN / 'NXLibraryCore.o', '-o', host)
    result = run(host, scratch)
    print(result.stdout, end='')
