#!/usr/bin/env python3
"""Stage the repository's canonical legal files for platform packaging.

The root NOTICE, THIRD_PARTY_NOTICES.md, SOURCES.md and Legal/ tree are the
only source of truth. Generated platform copies are intentionally ignored by
git and must never be edited independently.

Usage:
    python3 scripts/stage_legal.py macos
    python3 scripts/stage_legal.py android
    python3 scripts/stage_legal.py webos
    python3 scripts/stage_legal.py all

Only the Python standard library is used. The script validates the complete
canonical file set before changing any staging directory.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DOCUMENTS = (
    "NOTICE",
    "THIRD_PARTY_NOTICES.md",
    "SOURCES.md",
)
LICENSES = (
    "MIT-code3-dev-CCloud.txt",
    "MIT-media_kit.txt",
    "MIT-famelack-data.txt",
    "OFL-1.1-Vazirmatn.txt",
    "Unlicense-iptv-org.txt",
    "BSD-3-Clause-ANGLE.txt",
    "GPL-2.0.txt",
    "GPL-3.0.txt",
    "LGPL-2.1.txt",
    "LGPL-3.0.txt",
)
DISTRIBUTION_STATUS = Path("Legal/DISTRIBUTION_STATUS.md")


def validate_canonical_files() -> None:
    required = [ROOT / name for name in DOCUMENTS]
    required.append(ROOT / DISTRIBUTION_STATUS)
    required.extend(ROOT / "Legal" / "licenses" / name for name in LICENSES)

    missing = [path.relative_to(ROOT) for path in required if not path.is_file()]
    if missing:
        names = ", ".join(str(path) for path in missing)
        raise SystemExit(f"error: canonical legal file set is incomplete: {names}")

    empty = [path.relative_to(ROOT) for path in required if path.stat().st_size == 0]
    if empty:
        names = ", ".join(str(path) for path in empty)
        raise SystemExit(f"error: canonical legal files are empty: {names}")


def reset_directory(
    path: Path,
    *,
    expected_root: Path | None = None,
) -> Path:
    root = (expected_root or ROOT).resolve()
    if root == Path(root.anchor):
        raise SystemExit(f"error: refusing to reset an unsafe staging directory: {path}")

    # Check the parent before touching a final-component symlink. This prevents
    # an out-of-scope link from being unlinked when an ancestor already escapes
    # the permitted repository or macOS Resources subtree.
    parent = path.parent.resolve()
    if parent != root and root not in parent.parents:
        raise SystemExit(f"error: refusing to reset an unsafe staging directory: {path}")
    if path.is_symlink():
        path.unlink()

    resolved = path.resolve()
    if resolved == Path(resolved.anchor) or resolved == root or root not in resolved.parents:
        raise SystemExit(f"error: refusing to reset an unsafe staging directory: {path}")
    if resolved.exists():
        if not resolved.is_dir():
            raise SystemExit(f"error: staging destination is not a directory: {path}")
        shutil.rmtree(resolved)
    resolved.mkdir(parents=True, exist_ok=True)
    return resolved


def copy_file(source: Path, destination: Path) -> None:
    if destination.is_symlink():
        destination.unlink()
    elif destination.exists() and not destination.is_file():
        raise SystemExit(f"error: legal staging destination is not a file: {destination}")
    shutil.copy2(source, destination)


def copy_documents(destination: Path) -> int:
    copied = 0
    for name in DOCUMENTS:
        copy_file(ROOT / name, destination / name)
        copied += 1
    return copied


def copy_licenses(
    destination: Path,
    *,
    expected_root: Path | None = None,
) -> int:
    license_dir = reset_directory(destination, expected_root=expected_root)
    copied = 0
    for name in LICENSES:
        copy_file(ROOT / "Legal" / "licenses" / name, license_dir / name)
        copied += 1
    return copied


def copy_legal_tree(
    destination: Path,
    *,
    expected_root: Path | None = None,
) -> int:
    legal = reset_directory(destination / "Legal", expected_root=expected_root)
    copy_file(ROOT / DISTRIBUTION_STATUS, legal / DISTRIBUTION_STATUS.name)
    copied = 1
    copied += copy_licenses(legal / "licenses", expected_root=expected_root)
    return copied


def stage_macos() -> int:
    build_root = Path(os.environ.get("CCLOUD_OUT") or (ROOT / "build"))
    resources = build_root / "CCloud.app" / "Contents" / "Resources"
    if resources.is_symlink():
        resources.unlink()
    resources.mkdir(parents=True, exist_ok=True)
    resources = resources.resolve()
    copied = copy_documents(resources)
    copied += copy_legal_tree(resources, expected_root=resources)
    return copied


def stage_flutter() -> int:
    legal = reset_directory(ROOT / "flutter_app" / "assets" / "legal")
    copied = copy_documents(legal)
    copied += copy_legal_tree(legal)
    return copied


def stage_webos() -> int:
    legal = reset_directory(ROOT / "webos_app" / "app" / "legal")
    copied = copy_documents(legal)
    copied += copy_legal_tree(legal)
    return copied


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "target",
        choices=("macos", "android", "webos", "all"),
        help="platform staging target; android also supplies shared Flutter assets",
    )
    args = parser.parse_args(argv)

    validate_canonical_files()

    stages = {
        "macos": stage_macos,
        "android": stage_flutter,
        "webos": stage_webos,
    }
    targets = tuple(stages) if args.target == "all" else (args.target,)
    for target in targets:
        count = stages[target]()
        print(f"staged {target}: {count} canonical legal files")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except OSError as exc:
        print(f"error: legal staging failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
