# -*- coding: utf-8 -*-
"""
Rebuild the four bundled mods and stage their .wotmod payloads for the installer.

  python build/gather_payload.py

What it does:
  1. Runs each sibling mod repo's own build/build_wotmod.py (with the interpreter
     that repo's build requires -- Python 2.7 for the three that ship compiled
     .pyc, plain Python 3 for class-icons-recolor which ships no Python at all).
  2. Copies each repo's freshly built dist\\*.wotmod into payload\\.
  3. Emits payload\\payload.iss: one #define per mod with its exact built filename
     plus one #define per mod with its meta.xml <id> prefix, #include'd by
     installer\\modpack-setup.iss so the .iss never hardcodes a version number
     or a package id.

Each mod repo is a dependency-free sibling of this one (..\\<repo-name>).
"""
from __future__ import print_function

import glob
import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIBLINGS = os.path.dirname(ROOT)
PAYLOAD = os.path.join(ROOT, "payload")
PY27 = r"C:\Python27\python.exe"

# (repo dir name, #define base name used in payload.iss, interpreter)
# Each base name gets two defines: <Base>Wotmod (built filename) and
# <Base>IdPrefix (the mod's meta.xml <id>) -- see _build_one.
MODS = [
    ("hint-silencer", "HintSilencer", PY27),
    ("class-icons-recolor", "ClassIcons", sys.executable),
    ("neutral_reticle", "NeutralReticle", PY27),
    ("ua-rename", "UaRename", PY27),
]


def _build_one(repo_name, python_exe):
    """Build repo_name's mod and return (built .wotmod path, meta.xml <id>).

    Reads src/meta.xml for the exact <id>_<version>.wotmod name rather than
    globbing dist\\*.wotmod -- a repo's dist\\ may hold stale .wotmods from an
    older version and a bare glob can't tell which one is the fresh build.
    The parsed <id> is also the single source of truth for the installer's
    stale-package-cleanup prefix -- see CleanStalePackage in modpack-setup.iss.
    """
    repo_dir = os.path.join(SIBLINGS, repo_name)
    build_script = os.path.join(repo_dir, "build", "build_wotmod.py")
    if not os.path.isfile(build_script):
        sys.exit("ERROR: missing build script: {0}".format(build_script))
    subprocess.check_call([python_exe, build_script], cwd=repo_dir)

    meta = ET.parse(os.path.join(repo_dir, "src", "meta.xml")).getroot()
    mod_id = meta.findtext("id").strip()
    version = meta.findtext("version").strip()
    built = os.path.join(repo_dir, "dist", "{0}_{1}.wotmod".format(mod_id, version))
    if not os.path.isfile(built):
        sys.exit("ERROR: expected build output not found: {0}".format(built))
    return built, mod_id


def main():
    if not os.path.isdir(PAYLOAD):
        os.makedirs(PAYLOAD)
    for stale in glob.glob(os.path.join(PAYLOAD, "*.wotmod")):
        os.remove(stale)

    defines = []
    for repo_name, base_name, python_exe in MODS:
        built, mod_id = _build_one(repo_name, python_exe)
        filename = os.path.basename(built)
        shutil.copy2(built, os.path.join(PAYLOAD, filename))
        defines.append((base_name + "Wotmod", filename))
        defines.append((base_name + "IdPrefix", mod_id))
        print("Staged: {0}".format(filename))

    iss_path = os.path.join(PAYLOAD, "payload.iss")
    with open(iss_path, "w") as f:
        for define_name, value in defines:
            f.write('#define {0} "{1}"\n'.format(define_name, value))

    _self_check(defines)
    print("Wrote: {0}".format(iss_path))


def _self_check(defines):
    """One runnable check: exactly four payloads staged, four wotmod + four
    id-prefix defines emitted."""
    staged = glob.glob(os.path.join(PAYLOAD, "*.wotmod"))
    assert len(staged) == 4, "expected 4 .wotmod files in payload\\, found {0}".format(len(staged))
    wotmod_defines = [n for n, _ in defines if n.endswith("Wotmod")]
    idprefix_defines = [n for n, _ in defines if n.endswith("IdPrefix")]
    assert len(wotmod_defines) == 4, "expected 4 Wotmod defines, found {0}".format(len(wotmod_defines))
    assert len(idprefix_defines) == 4, "expected 4 IdPrefix defines, found {0}".format(len(idprefix_defines))


if __name__ == "__main__":
    main()
