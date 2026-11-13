#!/usr/bin/env python3
"""Exercise actual app notice helpers/bridge without constructing SwiftUI or AppKit.

Run after swift test on macOS. Core I/O uses generated temporary data only.
The host substitutes the surrounding view model, not the methods being checked.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'

def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

with tempfile.TemporaryDirectory(prefix='catalog-notice-check-') as scratch:
    scratch = Path(scratch)
    view = (ROOT / 'Sources/NXLibrary/Views/Shell/AppShellView.swift').read_text()
    bridge = '\n'.join(method(view, signature) for signature in (
        '    private func finishSettingsNotice(choice: Int)', '    private func presentLegacyNotice()'))
    host = (ROOT / 'Tests/CatalogAppChecks/NoticeHost.swift').read_text()
    host += '\nstruct LegacyNoticeHost {\n let viewModel: AppViewModel\n'
    host += ' func deliver() { presentLegacyNotice() }\n func dismiss() { finishSettingsNotice(choice: 0) }\n'
    host += bridge + '\n}\n'
    main = scratch / 'main.swift'
    main.write_text(host)
    executable = scratch / 'notices'
    command = ['xcrun', 'swiftc', '-I', str(BIN), str(main),
               str(ROOT / 'Sources/NXLibrary/Models/LogEntry.swift'),
               str(ROOT / 'Sources/NXLibrary/ViewModels/AppViewModel+Catalog.swift'),
               str(BIN / 'NXLibraryCore.o'), '-o', str(executable)]
    subprocess.run(command, cwd=ROOT, check=True)
    env = dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN))
    subprocess.run([str(executable)], env=env, check=True)
