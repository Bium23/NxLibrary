#!/usr/bin/env python3
"""Validate and optionally extract a bounded release ZIP; never run its contents."""
import os
import pathlib
import stat
import struct
import sys
import unicodedata
import zipfile
import zlib


MAX_ARCHIVE = 512 * 1024 * 1024
MAX_EXPANSION = 2 * 1024 * 1024 * 1024
MAX_ENTRIES = 30_000


def chunks(path, entry):
    """Count raw inflater output, rather than trusting ZipExtFile's declared-size truncation."""
    if entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
        raise ValueError("Unsupported compression")
    decoder = zlib.decompressobj(-15) if entry.compress_type == zipfile.ZIP_DEFLATED else None
    count = crc = 0
    with path.open("rb") as source:
        source.seek(entry.header_offset)
        header = source.read(30)
        if len(header) != 30 or header[:4] != b"PK\x03\x04":
            raise ValueError("Local header")
        name_size, extra_size = struct.unpack_from("<HH", header, 26)
        source.seek(name_size + extra_size, 1)
        remaining = entry.compress_size
        while remaining:
            pending = source.read(min(65536, remaining))
            if not pending:
                raise ValueError("Truncated data")
            remaining -= len(pending)
            while pending:
                output = decoder.decompress(pending, 65536) if decoder else pending
                pending = decoder.unconsumed_tail if decoder else b""
                count += len(output)
                if count > entry.file_size or (decoder and decoder.unused_data):
                    raise ValueError("Unexpected expanded size")
                crc = zlib.crc32(output, crc)
                yield output
        while decoder and not decoder.eof:
            output = decoder.decompress(b"", 65536)
            if not output:
                raise ValueError("Incomplete stream")
            count += len(output)
            if count > entry.file_size:
                raise ValueError("Unexpected expanded size")
            crc = zlib.crc32(output, crc)
            yield output
    if count != entry.file_size or crc != entry.CRC:
        raise ValueError("Content size or checksum")


def validate(path, destination=None):
    if not 0 < path.stat().st_size <= MAX_ARCHIVE:
        raise ValueError("Download size")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if not entries or len(entries) > MAX_ENTRIES:
            raise ValueError("Entry count")
        if sum(entry.file_size for entry in entries) > MAX_EXPANSION:
            raise ValueError("Expanded size")
        names = set()
        links = set()
        paths = []
        for entry in entries:
            name = pathlib.PurePosixPath(entry.filename)
            if (entry.orig_filename != entry.filename
                    or name.is_absolute() or ".." in name.parts or "\\" in entry.filename
                    or not name.parts or "\x00" in entry.filename
                    or any(ord(char) < 32 for char in entry.filename)):
                raise ValueError("Unsafe path")
            if name.parts[0] != "NXLibrary.app" and name.parts[:2] != ("__MACOSX", "NXLibrary.app"):
                raise ValueError("Unexpected root")
            normalized = unicodedata.normalize("NFD", str(name)).casefold()
            if normalized in names or entry.flag_bits & 1:
                raise ValueError("Duplicate or encrypted entry")
            names.add(normalized)
            mode = entry.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if kind not in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK):
                raise ValueError("Special file")
            # Verify the local header too, without expanding the file's contents.
            with archive.open(entry):
                pass
            if stat.S_ISLNK(mode):
                if entry.file_size > 4096:
                    raise ValueError("Symlink size")
                target = pathlib.PurePosixPath(b"".join(chunks(path, entry)).decode("utf-8"))
                # Packaged Python uses relative sibling links; no parent traversal is needed.
                if target.is_absolute() or not target.parts or ".." in target.parts or "\\" in str(target):
                    raise ValueError("Unsafe symlink")
                links.add(normalized)
            paths.append(name)
        for name in paths:
            if any(unicodedata.normalize("NFD", str(parent)).casefold() in links for parent in name.parents):
                raise ValueError("Entry below symlink")
        required = {"nxlibrary.app/contents/info.plist", "nxlibrary.app/contents/macos/nxlibrary"}
        if not required.issubset(names):
            raise ValueError("Incomplete app")
        if destination is not None:
            destination.mkdir(parents=True, exist_ok=False)
        # Use this same bounded reader for extraction; an independent ZIP parser could
        # interpret forged size fields differently and bypass the expansion budget.
        for entry in entries:
            output = destination / entry.filename if destination is not None else None
            if output is not None:
                output.parent.mkdir(parents=True, exist_ok=True)
            mode = entry.external_attr >> 16
            if stat.S_ISLNK(mode):
                target = b"".join(chunks(path, entry)).decode("utf-8")
                if output is not None:
                    os.symlink(target, output)
            elif entry.is_dir():
                for _ in chunks(path, entry):
                    pass
                if output is not None:
                    output.mkdir(exist_ok=True)
            elif output is not None:
                with output.open("xb") as stream:
                    for chunk in chunks(path, entry):
                        stream.write(chunk)
                output.chmod((mode & 0o777) or 0o644)
            else:
                for _ in chunks(path, entry):
                    pass


if __name__ == "__main__":
    try:
        if len(sys.argv) not in (2, 3):
            raise ValueError("Arguments")
        validate(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]) if len(sys.argv) == 3 else None)
    except (OSError, ValueError, RuntimeError, UnicodeError, zipfile.BadZipFile, zlib.error):
        print("The update archive could not be verified.", file=sys.stderr)
        sys.exit(1)
