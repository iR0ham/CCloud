#!/usr/bin/env python3
"""Verify the retained-text digests recorded in SOURCES.md.

`SOURCES.md` is the human-readable provenance ledger: every license text the
repository redistributes is listed with a SHA-256 for the copy that is retained
under `Legal/licenses/`. Until now nothing proved those values were ever
recomputed, so a modified or truncated license text could keep a valid-looking
digest in the document and stay green in CI.

This script closes that evidence gap offline and deterministically:

* it parses the retained-file / digest pairs from `SOURCES.md` (both the
  ``- Retained text:`` + ``- Text SHA-256:`` bullet form and the ``| path | url
  | digest |`` table form);
* it recomputes SHA-256 for each named file inside the checkout;
* it fails on a mismatch, a missing file, a documented path that escapes the
  checkout (by ``..``, an absolute path, or a committed symlink), a retained
  bullet with no digest, and a license text anywhere under `Legal/licenses/`, at
  any depth, that the document never mentions;
* it prints the number of digests actually verified.

Nothing is fetched. The archive rows in the media_kit table carry pub.dev
download digests for tarballs that are not part of this checkout, so they are
deliberately not treated as retained files: only the first cell of a table row
that looks like a repository-relative path is verified.

Usage:
    python3 scripts/verify_provenance.py
    python3 scripts/verify_provenance.py --quiet
    python3 scripts/verify_provenance.py --root <checkout> --sources <file>

Only the Python standard library is used, so the script runs unchanged on the
Linux, macOS and Windows GitHub Actions runners.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable

ROOT = Path(__file__).resolve().parent.parent

SOURCES_FILE = "SOURCES.md"
# The canonical license directory. Every file in it must be documented, which is
# what makes "add a license text without provenance" fail instead of pass.
RETAINED_LICENSE_DIR = PurePosixPath("Legal/licenses")

HEX64_RE = re.compile(r"^[0-9a-fA-F]{64}$")
RETAINED_BULLET_RE = re.compile(r"^[-*]\s+Retained text:\s*(.*)$")
DIGEST_BULLET_RE = re.compile(r"^[-*]\s+Text SHA-256:\s*(.*)$")
QUOTED_RE = re.compile(r"^`([^`]+)`$")
READ_CHUNK_BYTES = 1024 * 1024


@dataclass(frozen=True)
class ProvenanceEntry:
    """One retained file paired with the digest the document claims for it."""

    path: str
    digest: str
    line: int

    @property
    def location(self) -> str:
        return f"line {self.line}"


def _unquote(value: str) -> str:
    text = value.strip()
    match = QUOTED_RE.match(text)
    return match.group(1).strip() if match else text


def _looks_like_retained_path(value: str) -> bool:
    """Accept repository-relative file paths only, never URLs or bare names.

    The media_kit table uses the same shape with package names in the first cell
    and pub.dev archive digests in the last; those digests describe tarballs that
    are not in this checkout and must not be verified as repository files.
    """
    if not value or "\x00" in value:
        return False
    if "://" in value or value.startswith("/"):
        return False
    pure = PurePosixPath(value)
    if ".." in pure.parts:
        return False
    return len(pure.parts) > 1 or value.endswith((".txt", ".md"))


def _table_cells(line: str) -> list[str] | None:
    stripped = line.strip()
    if not stripped.startswith("|"):
        return None
    cells = [_unquote(cell) for cell in stripped.strip("|").split("|")]
    if not cells:
        return None
    if all(set(cell) <= set("-: ") for cell in cells):
        return None  # markdown alignment row
    return cells


def parse_provenance(text: str) -> tuple[list[ProvenanceEntry], list[str]]:
    """Pair every retained path with its documented SHA-256.

    Returns the entries plus the structural problems found while pairing. A
    retained bullet that never reaches a digest line is a problem, not a skip:
    that is exactly how an undocumented license text would otherwise slip past.
    """
    entries: list[ProvenanceEntry] = []
    problems: list[str] = []
    pending: tuple[str, int] | None = None

    for number, line in enumerate(text.splitlines(), start=1):
        retained = RETAINED_BULLET_RE.match(line)
        if retained:
            if pending is not None:
                problems.append(
                    f"{SOURCES_FILE}:{pending[1]}: retained text `{pending[0]}` has no "
                    "`Text SHA-256` entry before the next one"
                )
            value = _unquote(retained.group(1))
            if not value:
                problems.append(f"{SOURCES_FILE}:{number}: empty retained text path")
                pending = None
            else:
                pending = (value, number)
            continue

        digest = DIGEST_BULLET_RE.match(line)
        if digest:
            value = _unquote(digest.group(1))
            if pending is None:
                problems.append(
                    f"{SOURCES_FILE}:{number}: `Text SHA-256` entry has no retained text "
                    "on a preceding line"
                )
                continue
            if not HEX64_RE.match(value):
                problems.append(
                    f"{SOURCES_FILE}:{number}: digest for `{pending[0]}` is not a 64-hex "
                    f"SHA-256 value: {value or '(empty)'}"
                )
                pending = None
                continue
            entries.append(ProvenanceEntry(path=pending[0], digest=value.lower(), line=number))
            pending = None
            continue

        cells = _table_cells(line)
        if cells is None or len(cells) < 2:
            continue
        claimed = cells[-1]
        if not HEX64_RE.match(claimed):
            continue
        target = cells[0]
        if not _looks_like_retained_path(target):
            continue
        if pending is not None:
            problems.append(
                f"{SOURCES_FILE}:{pending[1]}: retained text `{pending[0]}` has no "
                "`Text SHA-256` entry before a table row"
            )
            pending = None
        entries.append(ProvenanceEntry(path=target, digest=claimed.lower(), line=number))

    if pending is not None:
        problems.append(
            f"{SOURCES_FILE}:{pending[1]}: retained text `{pending[0]}` has no "
            "`Text SHA-256` entry"
        )
    return entries, problems


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(READ_CHUNK_BYTES)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _resolve_within(root: Path, relative: str) -> Path | None:
    """Map a documented path into the checkout, or refuse it.

    The lexical test below catches an absolute path and a literal ``..`` segment,
    but it cannot see a symlink committed inside ``Legal/licenses/``: a bare
    ``root / path`` still resolves through that link when the caller opens it, so
    the digest would be recomputed from bytes living outside the checkout while
    the directory sweep keeps counting the entry as a documented retained text.
    Containment is therefore re-checked on the canonical path, which makes the
    "escapes the checkout" rejection in the module docstring true for links too.
    """
    pure = PurePosixPath(relative.replace("\\", "/"))
    if pure.is_absolute() or ".." in pure.parts:
        return None
    # Resolving canonicalizes the whole component chain, so a link in any segment
    # (not only the file itself) has to land back inside the checkout. Both sides
    # are canonicalized, which keeps the comparison correct when the checkout is
    # reached through a symlinked parent, as on macOS under /var.
    base = root.resolve(strict=False)
    target = (base / Path(*pure.parts)).resolve(strict=False)
    if target != base and base not in target.parents:
        return None
    return target


def _duplicate_conflicts(entries: Iterable[ProvenanceEntry]) -> list[str]:
    seen: dict[str, ProvenanceEntry] = {}
    problems: list[str] = []
    for entry in entries:
        key = entry.path.replace("\\", "/")
        previous = seen.get(key)
        if previous is None:
            seen[key] = entry
            continue
        if previous.digest != entry.digest:
            problems.append(
                f"{SOURCES_FILE}:{entry.line}: `{key}` is documented twice with different "
                f"digests ({previous.digest} at line {previous.line})"
            )
    return problems


def verify_provenance(
    root: Path,
    entries: list[ProvenanceEntry],
    *,
    verbose: bool = True,
) -> tuple[int, list[str]]:
    """Recompute every documented digest and report structural gaps.

    The containment rule is part of this function's own contract, not a courtesy
    of its one current caller: a documented path that resolves outside ``root`` is
    a problem and is never counted as a documented retained text. The second half
    matters because the sweep below decides "this license text was never
    declared" from that set, so an escaping path must not be able to satisfy it.
    """
    problems = _duplicate_conflicts(entries)
    documented: set[str] = set()
    verified = 0

    for entry in sorted(entries, key=lambda item: (item.path.replace("\\", "/"), item.line)):
        key = entry.path.replace("\\", "/")
        target = _resolve_within(root, key)
        if target is None:
            # Deliberately *before* the set add: a path that leaves the checkout is not a
            # retained text this repository ships, and treating it as one would let the
            # lexical spelling of `Legal/licenses/…` satisfy the sweep while the bytes it
            # digests live somewhere else.
            problems.append(
                f"{SOURCES_FILE}:{entry.line}: retained path must stay inside the checkout: {key}"
            )
            continue
        documented.add(key)
        if not target.exists():
            problems.append(f"{SOURCES_FILE}:{entry.line}: retained file is missing: {key}")
            continue
        if not target.is_file():
            problems.append(f"{SOURCES_FILE}:{entry.line}: retained path is not a file: {key}")
            continue
        actual = sha256_of(target)
        if actual != entry.digest:
            problems.append(
                f"{SOURCES_FILE}:{entry.line}: digest mismatch for {key}: "
                f"{SOURCES_FILE} says {entry.digest}, the file is {actual}"
            )
            continue
        verified += 1
        if verbose:
            print(f"provenance: ok {key} ({target.stat().st_size} bytes) {actual}")

    license_dir = root / Path(RETAINED_LICENSE_DIR)
    if not license_dir.is_dir():
        problems.append(f"canonical license directory is missing: {RETAINED_LICENSE_DIR}")
    else:
        # Recursive. The rule this sweep enforces is "nothing sits in the canonical license
        # tree without a documented digest", and a top-level-only scan stops being that rule
        # the moment anyone files a text a level deeper: `scripts/stage_legal.py` ships an
        # explicit name list, so a nested file is neither copied into a package nor verified
        # by anyone, which is the worst of the three states and exactly what a silent skip
        # would allow. `rglob` yields paths relative to the directory, so the key is built
        # from `relative_to` rather than the file name: a name-only key would compare
        # `Legal/licenses/<name>` against a document that says
        # `Legal/licenses/third-party/<name>` and report an undocumented file that is
        # perfectly documented.
        for path in sorted(license_dir.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(license_dir).as_posix()
            key = f"{RETAINED_LICENSE_DIR.as_posix()}/{relative}"
            if key not in documented:
                problems.append(
                    f"{RETAINED_LICENSE_DIR.as_posix()}: {relative} is a license text in the "
                    f"retained license tree but has no digest entry in {SOURCES_FILE}"
                )

    return verified, problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=str(ROOT),
        help="checkout that retained files are resolved against (default: repository root)",
    )
    parser.add_argument(
        "--sources",
        default=SOURCES_FILE,
        help=f"provenance document to parse (default: {SOURCES_FILE}, relative to --root)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="only print the summary line instead of one line per verified digest",
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    sources = Path(args.sources)
    if not sources.is_absolute():
        sources = root / sources
    if not sources.is_file():
        print(f"error: provenance document is missing: {sources}", file=sys.stderr)
        return 1

    entries, problems = parse_provenance(sources.read_text(encoding="utf-8"))
    if not entries:
        problems.append(f"{sources.name}: no retained file / SHA-256 pair was found")

    verified, digest_problems = verify_provenance(root, entries, verbose=not args.quiet)
    problems.extend(digest_problems)

    print(
        f"provenance: {verified} retained files verified against {sources.name} "
        f"(offline, recomputed SHA-256, no network fetch)"
    )
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        print(
            f"error: provenance verification failed: {len(problems)} problem(s); "
            "do not relax this gate, repair the document or the retained file",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
