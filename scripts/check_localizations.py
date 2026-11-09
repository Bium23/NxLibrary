#!/usr/bin/env python3
"""Validate translated copy and the localization resources shipped in a built app."""
import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
from xml.parsers.expat import ExpatError

LANGUAGES = ('en', 'it', 'fr', 'de', 'es', 'pt-BR')
BUNDLE = 'NXLibrary_NXLibraryCore.bundle'
PLACEHOLDER = re.compile(r'%(?:(\d+)\$)?(lld|ld|d|@|(?:\.\d+)?f)')


def placeholders(text):
    matches = PLACEHOLDER.findall(text.replace('%%', ''))
    return Counter((int(position) if position else index + 1, kind) for index, (position, kind) in enumerate(matches))


def check_catalog(path):
    errors = []
    try:
        catalog = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        return [f'Cannot read catalog: {error}']
    if catalog.get('sourceLanguage') != 'en':
        errors.append('Catalog source language must be en')
    for key, item in catalog.get('strings', {}).items():
        for language in LANGUAGES:
            entry = item.get('localizations', {}).get(language)
            if entry is None:
                errors.append(f'{language}: missing translation for {key!r}')
                continue
            variants = entry.get('variations', {}).get('plural')
            units = [item.get('stringUnit', {}) for item in variants.values()] if variants else [entry.get('stringUnit', {})]
            if variants and not {'one', 'other'}.issubset(variants):
                errors.append(f'{language}: incomplete plurals for {key!r}')
            for unit in units:
                value = unit.get('value', '')
                if not value.strip() or unit.get('state') != 'translated':
                    errors.append(f'{language}: unfinished translation for {key!r}')
                if placeholders(value) != placeholders(key):
                    errors.append(f'{language}: placeholder mismatch for {key!r}')
    return errors


def read_compiled_plist(path):
    data = path.read_bytes()
    # Xcode emits UTF-16 XML strings with an UTF-8 declaration. Foundation accepts this;
    # normalize the BOM encoding before handing the XML to Python's stricter parser.
    if data.startswith((b'\xff\xfe', b'\xfe\xff')):
        text = data.decode('utf-16')
        text = re.sub(r'encoding="[^"]+"', 'encoding="UTF-8"', text, count=1)
        data = text.encode('utf-8')
    return plistlib.loads(data)


def check_app(app):
    errors = []
    try:
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError, UnicodeError):
        return ['App Info.plist missing or invalid']
    if not set(LANGUAGES).issubset(info.get('CFBundleLocalizations', [])):
        errors.append('App Info.plist does not declare all six languages')
    resources = app / 'Contents/Resources' / BUNDLE / 'Contents/Resources'
    if not resources.is_dir():
        return errors + ['Compiled localization bundle missing']
    for language in LANGUAGES:
        folder = resources / f'{language}.lproj'
        for name in ('Localizable.strings', 'Localizable.stringsdict'):
            try:
                value = read_compiled_plist(folder / name)
                if not value:
                    errors.append(f'{language}: empty {name}')
            except (OSError, ValueError, plistlib.InvalidFileException, ExpatError, UnicodeError):
                errors.append(f'{language}: missing or invalid compiled {name}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, default=Path(__file__).resolve().parents[1] / 'Sources/NXLibraryCore/Resources/Localizable.xcstrings')
    parser.add_argument('--app', type=Path)
    args = parser.parse_args()
    errors = check_catalog(args.catalog)
    if args.app:
        errors += check_app(args.app)
    if errors:
        for error in errors:
            print(error)
        return 1
    print('Localization checks passed (six languages, placeholders and plurals).')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
