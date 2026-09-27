# -*- coding: utf-8 -*-
"""
Rebuild the four bundled mods and stage their .wotmod payloads for the installer.

  python build/gather_payload.py

What it does:
  1. For each sibling mod repo: refuses a dirty working tree or a HEAD that
     isn't tagged v<meta.xml version> (see _verify_sibling_clean), then runs
     the repo's own build/build_wotmod.py (with the interpreter that repo's
     build requires -- Python 2.7 for the three that ship compiled .pyc,
     plain Python 3 for class-icons-recolor which ships no Python at all).
  2. Copies each repo's freshly built dist\\*.wotmod into payload\\, then
     refuses to stage it if any shipped .pyc has an absolute path baked into
     its bytecode (see _assert_no_absolute_pyc_paths).
  3. Emits payload\\payload.iss: one #define per mod with its exact built
     filename, one with its meta.xml <id> prefix, and one with the sibling's
     HEAD sha (provenance), #include'd by installer\\modpack-setup.iss so the
     .iss never hardcodes a version number or a package id.

Each mod repo is a dependency-free sibling of this one (..\\<repo-name>).
"""
from __future__ import print_function

import glob
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

# A Windows absolute path (drive letter + separator) baked into a shipped
# .pyc's co_filename leaks the dev machine's username/folder layout into
# every player's python.log -- see the LEAK-PYC audit finding. Refuse to
# stage a payload that carries one instead of trying to fix it here; the
# fix belongs in the sibling mod's own build_wotmod.py (dfile).
_ABS_PYC_PATH_RE = re.compile(rb"[A-Za-z]:[\\/]")

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


def _verify_sibling_clean(repo_dir, version):
    """Refuse to gather from a dirty sibling tree or one whose HEAD isn't the
    tagged release meta.xml claims -- a modpack payload should only ever be
    built from a reproducible, released sibling commit. Returns HEAD's SHA
    so the caller can record provenance in payload.iss.
    """
    status = subprocess.check_output(
        ["git", "-C", repo_dir, "status", "--porcelain"]
    ).decode("utf-8", "replace").strip()
    if status:
        sys.exit(
            "ERROR: {0} has uncommitted changes; commit or stash before "
            "gathering the payload:\n{1}".format(repo_dir, status)
        )
    sha = subprocess.check_output(
        ["git", "-C", repo_dir, "rev-parse", "HEAD"]
    ).decode("utf-8", "replace").strip()
    tag = "v" + version
    tags_at_head = subprocess.check_output(
        ["git", "-C", repo_dir, "tag", "--points-at", "HEAD"]
    ).decode("utf-8", "replace").split()
    if tag not in tags_at_head:
        sys.exit(
            "ERROR: {0} HEAD ({1}) is not tagged {2} (meta.xml version "
            "{3}); tag the release before gathering the payload.".format(
                repo_dir, sha[:8], tag, version
            )
        )
    return sha


def _assert_no_absolute_pyc_paths(wotmod_path):
    """Refuse a staged .wotmod whose bytecode carries an absolute path."""
    with zipfile.ZipFile(wotmod_path) as zf:
        for name in zf.namelist():
            if not name.endswith(".pyc"):
                continue
            if _ABS_PYC_PATH_RE.search(zf.read(name)):
                sys.exit(
                    "ERROR: {0} ships {1} with an absolute path baked into "
                    "its bytecode (co_filename leak) -- rebuild that mod "
                    "with a relative dfile before staging.".format(wotmod_path, name)
                )


def _build_one(repo_name, python_exe):
    """Build repo_name's mod and return (built .wotmod path, meta.xml <id>,
    sibling HEAD sha).

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

    meta = ET.parse(os.path.join(repo_dir, "src", "meta.xml")).getroot()
    mod_id = meta.findtext("id").strip()
    version = meta.findtext("version").strip()

    sha = _verify_sibling_clean(repo_dir, version)

    subprocess.check_call([python_exe, build_script], cwd=repo_dir)

    built = os.path.join(repo_dir, "dist", "{0}_{1}.wotmod".format(mod_id, version))
    if not os.path.isfile(built):
        sys.exit("ERROR: expected build output not found: {0}".format(built))
    return built, mod_id, sha


def main():
    if not os.path.isdir(PAYLOAD):
        os.makedirs(PAYLOAD)
    for stale in glob.glob(os.path.join(PAYLOAD, "*.wotmod")):
        os.remove(stale)

    defines = []
    for repo_name, base_name, python_exe in MODS:
        built, mod_id, sha = _build_one(repo_name, python_exe)
        filename = os.path.basename(built)
        staged_path = os.path.join(PAYLOAD, filename)
        shutil.copy2(built, staged_path)
        _assert_no_absolute_pyc_paths(staged_path)
        defines.append((base_name + "Wotmod", filename))
        defines.append((base_name + "IdPrefix", mod_id))
        defines.append((base_name + "Sha", sha))
        print("Staged: {0} ({1})".format(filename, sha[:8]))

    iss_path = os.path.join(PAYLOAD, "payload.iss")
    with open(iss_path, "w") as f:
        for define_name, value in defines:
            f.write('#define {0} "{1}"\n'.format(define_name, value))

    _self_check(defines)
    print("Wrote: {0}".format(iss_path))


def _self_check(defines):
    """One runnable check: exactly four payloads staged, four wotmod + four
    id-prefix + four sha defines emitted."""
    staged = glob.glob(os.path.join(PAYLOAD, "*.wotmod"))
    assert len(staged) == 4, "expected 4 .wotmod files in payload\\, found {0}".format(len(staged))
    wotmod_defines = [n for n, _ in defines if n.endswith("Wotmod")]
    idprefix_defines = [n for n, _ in defines if n.endswith("IdPrefix")]
    sha_defines = [n for n, _ in defines if n.endswith("Sha")]
    assert len(wotmod_defines) == 4, "expected 4 Wotmod defines, found {0}".format(len(wotmod_defines))
    assert len(idprefix_defines) == 4, "expected 4 IdPrefix defines, found {0}".format(len(idprefix_defines))
    assert len(sha_defines) == 4, "expected 4 Sha defines, found {0}".format(len(sha_defines))


if __name__ == "__main__":
    main()
