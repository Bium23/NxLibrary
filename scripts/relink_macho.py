"""Relink Homebrew Mach-O files into a self-contained runtime folder.

Usage: python3 -I relink_macho.py <runtime> <origins.txt>

origins.txt has one "<name in bin/> <original path>" line per tool. Every
dependency outside /usr/lib and /System is copied into <runtime>/lib and
rewritten to @loader_path; absolute rpaths are deleted; every touched file is
ad-hoc signed. Maintainer only, run by scripts/bundle_runtime.sh.
"""

import os
import shutil
import subprocess
import sys

FOREIGN = ("/opt/homebrew", "/usr/local", "@rpath/", "@loader_path/", "@executable_path/")


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def dependencies(path):
    own = run("otool", "-D", path).splitlines()[1:]
    lines = run("otool", "-L", path).splitlines()[1:]
    deps = [line.strip().split(" (compatibility")[0] for line in lines]
    return [d for d in deps if d not in own]


def rpaths(path):
    found, lines = [], run("otool", "-l", path).splitlines()
    for i, line in enumerate(lines):
        if line.strip() == "cmd LC_RPATH":
            found.append(lines[i + 2].strip().split("path ", 1)[1].rsplit(" (offset", 1)[0])
    return found


def resolve(dep, origin):
    """The real file a load command names, seen from the original file."""
    here = os.path.dirname(origin)
    if dep.startswith("@rpath/"):
        rest = dep[len("@rpath/"):]
        for rp in rpaths(origin):
            base = rp.replace("@loader_path", here).replace("@executable_path", here)
            candidate = os.path.join(base, rest)
            if os.path.exists(candidate):
                return os.path.realpath(candidate)
        sys.exit(f"relink: cannot resolve {dep} from {origin}")
    if dep.startswith(("@loader_path/", "@executable_path/")):
        return os.path.realpath(os.path.join(here, dep.split("/", 1)[1]))
    return os.path.realpath(dep)


def main():
    runtime, origins_file = sys.argv[1], sys.argv[2]
    lib = os.path.join(runtime, "lib")
    queue = []
    with open(origins_file) as handle:
        for line in handle:
            name, origin = line.split(" ", 1)
            queue.append((os.path.join(runtime, "bin", name), origin.strip(), False))

    done = set()
    while queue:
        target, origin, is_lib = queue.pop(0)
        if target in done:
            continue
        done.add(target)
        os.chmod(target, 0o755)
        for dep in dependencies(target):
            if not dep.startswith(FOREIGN):
                continue
            real = resolve(dep, origin)
            name = os.path.basename(dep)
            copy = os.path.join(lib, name)
            if not os.path.exists(copy):
                shutil.copy2(real, copy)
                os.chmod(copy, 0o755)
            queue.append((copy, real, True))
            new = f"@loader_path/{name}" if is_lib else f"@loader_path/../lib/{name}"
            run("install_name_tool", "-change", dep, new, target)
        if is_lib:
            run("install_name_tool", "-id", f"@loader_path/{os.path.basename(target)}", target)
        for rp in rpaths(target):
            if not rp.startswith("@"):
                run("install_name_tool", "-delete_rpath", rp, target)
        run("codesign", "--force", "--sign", "-", target)
        print(f"relinked {os.path.relpath(target, runtime)}")


if __name__ == "__main__":
    main()
