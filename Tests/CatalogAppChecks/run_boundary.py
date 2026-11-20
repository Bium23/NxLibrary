#!/usr/bin/env python3
"""The base Core (everything in Sources/NXLibraryCore outside Porting/) must not grow new uses of Porting types.

A base file that names, in code, a type declared under Porting/ is a link still to cut. ALLOWED lists the links
left; the check fails when a file outside it gains one, and when a listed file has none left (shorten the list).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'Sources/NXLibraryCore'
PORTING = CORE / 'Porting'

ALLOWED = {
    'App/AppDataProfile.swift',
    'App/DevelopmentProfileImporter.swift',
    'App/FirstRunFindings.swift',
}

DECLARATION = re.compile(r'^(?:public |internal |final |indirect |fileprivate |private )*'
                         r'(?:struct|class|enum|protocol|actor|typealias)\s+(\w+)', re.M)


def code(text):
    """Source without comments and string literals, so a name in a doc comment is not a link."""
    text = re.sub(r'"""[\s\S]*?"""', '', text)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '', text)
    text = re.sub(r'/\*[\s\S]*?\*/', '', text)
    return re.sub(r'//[^\n]*', '', text)


porting_types = set()
for path in PORTING.rglob('*.swift'):
    porting_types.update(DECLARATION.findall(path.read_text()))

links = {}
for path in sorted(CORE.rglob('*.swift')):
    if PORTING in path.parents:
        continue
    used = sorted(set(re.findall(r'\b[A-Z]\w*', code(path.read_text()))) & porting_types)
    if used:
        links[str(path.relative_to(CORE))] = used

failures = [f'{name} uses Porting types {", ".join(used)}' for name, used in links.items() if name not in ALLOWED]
failures += [f'{name} no longer uses Porting types: remove it from ALLOWED' for name in ALLOWED if name not in links]
if failures:
    print('Boundary check failed:\n  ' + '\n  '.join(failures))
    sys.exit(1)
print(f'Boundary check passed: {len(links)} base files still use Porting types, none new.')
