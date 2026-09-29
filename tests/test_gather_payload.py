# -*- coding: utf-8 -*-
"""Tests for build/gather_payload.py's sibling-tree and payload guards.

Run: python -m pytest tests -q
"""
import os
import subprocess
import sys
import zipfile

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "build"))

import gather_payload  # noqa: E402


def _git(repo, *args):
    subprocess.check_call(["git", "-C", repo] + list(args))


def _init_repo(tmp_path, version, tag=True, dirty=False):
    repo = str(tmp_path)
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "test@example.com")
    _git(repo, "config", "user.name", "Test")
    (tmp_path / "file.txt").write_text("x")
    _git(repo, "add", "file.txt")
    _git(repo, "commit", "-q", "-m", "init")
    if tag:
        _git(repo, "tag", "v" + version)
    if dirty:
        (tmp_path / "file.txt").write_text("y")
    return repo


def test_verify_sibling_clean_returns_head_sha(tmp_path):
    repo = _init_repo(tmp_path, "1.2.3")
    sha = gather_payload._verify_sibling_clean(repo, "1.2.3")
    assert len(sha) == 40


def test_verify_sibling_clean_rejects_dirty_tree(tmp_path):
    repo = _init_repo(tmp_path, "1.2.3", dirty=True)
    with pytest.raises(SystemExit):
        gather_payload._verify_sibling_clean(repo, "1.2.3")


def test_verify_sibling_clean_rejects_missing_tag(tmp_path):
    repo = _init_repo(tmp_path, "1.2.3", tag=False)
    with pytest.raises(SystemExit):
        gather_payload._verify_sibling_clean(repo, "1.2.3")


def _make_wotmod(tmp_path, name, pyc_bytes):
    path = tmp_path / name
    with zipfile.ZipFile(str(path), "w") as zf:
        zf.writestr("res/scripts/client/gui/mods/mod_x.pyc", pyc_bytes)
    return str(path)


def test_assert_no_absolute_pyc_paths_allows_relative(tmp_path):
    path = _make_wotmod(
        tmp_path, "ok.wotmod", b"res/scripts/client/gui/mods/mod_x.py"
    )
    gather_payload._assert_no_absolute_pyc_paths(path)  # no raise


def test_assert_no_absolute_pyc_paths_rejects_windows_leak(tmp_path):
    path = _make_wotmod(
        tmp_path,
        "leak.wotmod",
        b"C:\\Users\\Dmytro Vasylkivskyi\\repo\\src\\res\\scripts\\client\\mod_x.py",
    )
    with pytest.raises(SystemExit):
        gather_payload._assert_no_absolute_pyc_paths(path)


def _vendor(tmp_path, content=b"vendor-bytes"):
    import hashlib

    src = tmp_path / "src"
    src.mkdir()
    (src / "a.dep_1.0.wotmod").write_bytes(content)
    manifest = {
        "_comment": "ignored",
        "a.dep_1.0.wotmod": {"sha256": hashlib.sha256(b"vendor-bytes").hexdigest()},
    }
    return str(src), manifest, str(tmp_path / "dest")


def test_stage_vendor_copies_on_sha_match(tmp_path):
    src, manifest, dest = _vendor(tmp_path)
    staged = gather_payload._stage_vendor(src, manifest, dest)
    assert staged == ["a.dep_1.0.wotmod"]
    assert os.path.isfile(os.path.join(dest, "a.dep_1.0.wotmod"))


def test_stage_vendor_rejects_sha_mismatch(tmp_path):
    src, manifest, dest = _vendor(tmp_path, content=b"tampered")
    with pytest.raises(SystemExit):
        gather_payload._stage_vendor(src, manifest, dest)
    assert not os.path.exists(os.path.join(dest, "a.dep_1.0.wotmod"))
