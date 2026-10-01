# -*- coding: utf-8 -*-
"""
Rebuild the six bundled mods and stage their .wotmod payloads for the installer.

  python build/gather_payload.py

What it does:
  1. For each sibling mod repo: refuses a dirty working tree or a HEAD that
     isn't tagged v<meta.xml version> (see _verify_sibling_clean), then runs
     the repo's own build/build_wotmod.py (with the interpreter that repo's
     build requires -- Python 2.7 for the five that ship compiled .pyc,
     plain Python 3 for class-icons-recolor which ships no Python at all).
  2. Copies each repo's freshly built dist\\*.wotmod into payload\\, then
     refuses to stage it if any shipped .pyc has an absolute path baked into
     its bytecode (see _assert_no_absolute_pyc_paths).
  3. Copies Spotting Calculator's vendor dependencies (OpenWG GameFace, Aslain
     ModMenu, ModsList API + the GameFace MIT licence) from that repo's
     installer\\vendor into payload\\vendor, refusing any .wotmod whose sha256
     doesn't match its MANIFEST.json entry (see _stage_vendor). 14th_ua HP
     shares the staged OpenWG GameFace; its own MANIFEST.json must pin the
     same file (see _assert_vendor_covered).
  4. Emits payload\\payload.iss: one #define per mod with its exact built
     filename, one with its meta.xml <id> prefix, and one with the sibling's
     HEAD sha (provenance), plus one filename #define per vendor dependency,
     #include'd by installer\\modpack-setup.iss so the .iss never hardcodes a
     version number or a package id.

Each mod repo is a sibling of this one (..\\<repo-name>).
"""
from __future__ import print_function

import glob
import hashlib
import json
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
    ("spotting_calculator", "Spotting", PY27),
    ("14th_ua_hp", "TeamHp", PY27),
]

# 14th_ua HP hard-requires OpenWG GameFace; it reuses the copy staged from
# spotting_calculator's vendor dir, so its own MANIFEST.json must pin the
# exact same file (see _assert_vendor_covered).
HP_MANIFEST = os.path.join(SIBLINGS, "14th_ua_hp", "installer", "vendor", "MANIFEST.json")

# Spotting Calculator's vendor deps, single-sourced from that repo's own
# installer\vendor (filenames + sha256 from its MANIFEST.json). Each
# (filename prefix, #define name) -> payload.iss gets <define> "<filename>".
VENDOR_SRC = os.path.join(SIBLINGS, "spotting_calculator", "installer")
VENDOR_DEST = os.path.join(PAYLOAD, "vendor")
VENDOR_DEFINES = [
    ("net.openwg.gameface_", "OpenWgWotmod"),
    ("aslain.modmenu_", "ModMenuWotmod"),
    ("me.poliroid.modslistapi_", "ModsListWotmod"),
]
OPENWG_LICENSE = os.path.join(VENDOR_SRC, "licenses", "openwg-gameface-LICENSE.txt")


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


def _stage_vendor(vendor_dir, manifest, dest_dir):
    """Copy every .wotmod listed in manifest ({filename: {"sha256": ...}})
    from vendor_dir into dest_dir, refusing on a missing file or a sha256
    mismatch. Returns the staged filenames."""
    if not os.path.isdir(dest_dir):
        os.makedirs(dest_dir)
    staged = []
    for filename, entry in sorted(manifest.items()):
        if not filename.endswith(".wotmod"):
            continue  # "_comment" etc.
        src = os.path.join(vendor_dir, filename)
        if not os.path.isfile(src):
            sys.exit("ERROR: vendor file missing: {0}".format(src))
        with open(src, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        if digest != entry["sha256"].lower():
            sys.exit(
                "ERROR: {0} sha256 {1} does not match MANIFEST.json {2}".format(
                    src, digest, entry["sha256"]
                )
            )
        shutil.copy2(src, os.path.join(dest_dir, filename))
        staged.append(filename)
    return staged


def _assert_vendor_covered(needed, staged):
    """Refuse when a mod's vendor manifest ({filename: {"sha256": ...}})
    needs a .wotmod that isn't staged under the same name + sha256."""
    for filename, entry in needed.items():
        if not filename.endswith(".wotmod"):
            continue
        have = staged.get(filename)
        if not have or have["sha256"].lower() != entry["sha256"].lower():
            sys.exit(
                "ERROR: vendor dependency {0} (sha256 {1}) is not in the "
                "staged vendor set -- re-pin it to the bundled copy.".format(
                    filename, entry["sha256"]
                )
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
    if os.path.isdir(VENDOR_DEST):
        shutil.rmtree(VENDOR_DEST)

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

    # After the loop: spotting_calculator's tree was just verified clean at
    # its release tag, so its vendor dir is the tagged copy.
    vendor_dir = os.path.join(VENDOR_SRC, "vendor")
    with open(os.path.join(vendor_dir, "MANIFEST.json")) as f:
        manifest = json.load(f)
    vendor = _stage_vendor(vendor_dir, manifest, VENDOR_DEST)
    with open(HP_MANIFEST) as f:
        _assert_vendor_covered(json.load(f), manifest)
    shutil.copy2(OPENWG_LICENSE, VENDOR_DEST)
    for prefix, define_name in VENDOR_DEFINES:
        match = [v for v in vendor if v.startswith(prefix)]
        if len(match) != 1:
            sys.exit("ERROR: expected one {0}*.wotmod in vendor, found {1}".format(prefix, match))
        defines.append((define_name, match[0]))
        print("Staged vendor: {0}".format(match[0]))

    iss_path = os.path.join(PAYLOAD, "payload.iss")
    with open(iss_path, "w") as f:
        for define_name, value in defines:
            f.write('#define {0} "{1}"\n'.format(define_name, value))

    _self_check(defines)
    print("Wrote: {0}".format(iss_path))


def _self_check(defines):
    """One runnable check: one staged payload + Wotmod/IdPrefix/Sha define
    per mod, plus one staged file + Wotmod define per vendor dependency."""
    n, nv = len(MODS), len(VENDOR_DEFINES)
    staged = glob.glob(os.path.join(PAYLOAD, "*.wotmod"))
    assert len(staged) == n, "expected {0} .wotmod files in payload\\, found {1}".format(n, len(staged))
    vendor = glob.glob(os.path.join(VENDOR_DEST, "*.wotmod"))
    assert len(vendor) == nv, "expected {0} vendor .wotmods, found {1}".format(nv, len(vendor))
    for suffix, want in (("Wotmod", n + nv), ("IdPrefix", n), ("Sha", n)):
        got = len([k for k, _ in defines if k.endswith(suffix)])
        assert got == want, "expected {0} {1} defines, found {2}".format(want, suffix, got)


if __name__ == "__main__":
    main()
