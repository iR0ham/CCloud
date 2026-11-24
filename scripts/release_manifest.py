#!/usr/bin/env python3
"""Write per-artifact SHA-256 sidecars and a release manifest.

The release workflow runs this against the files that were actually downloaded
from the platform build jobs, so the manifest can never describe an artifact
that was not produced. Only the Python standard library is used.

Usage:
    python3 scripts/release_manifest.py \
        --artifacts release-artifacts \
        --output release-artifacts/release-manifest.json \
        --product CCloud --version 2.0.0 --build 22 \
        --commit <sha> --tag v2.0.0 --run-id <run id>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")

# Only the files a user would download belong in the manifest. Checksum files,
# signing notes and the manifest itself are deliberately excluded.
ARTIFACT_SUFFIXES = {".zip", ".exe", ".apk", ".aab", ".ipk"}


def platform_for(filename: str) -> str:
    lower = filename.lower()
    if "-macos-" in lower:
        return "macOS"
    if "-windows-" in lower:
        return "Windows"
    if "-android-" in lower:
        return "Android/TV"
    if "-webos-" in lower:
        return "webOS"
    raise SystemExit(f"error: cannot classify artifact {filename!r} by platform")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--product", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument(
        "--timestamp",
        help="UTC build timestamp; defaults to now in YYYY-MM-DDTHH:MM:SSZ form",
    )
    args = parser.parse_args(argv)

    if not SEMVER_RE.fullmatch(args.version):
        raise SystemExit(f"error: version must be x.y.z, got {args.version!r}")
    if args.build <= 0:
        raise SystemExit(f"error: build must be positive, got {args.build}")

    root = args.artifacts.resolve()
    output = args.output.resolve()
    if not root.is_dir():
        raise SystemExit(f"error: artifacts directory not found: {root}")

    timestamp = args.timestamp or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )

    artifacts: list[dict[str, object]] = []
    # Materialize the directory listing before writing sidecars so the new
    # *.sha256 files cannot be mistaken for build artifacts.
    for path in sorted(root.iterdir(), key=lambda item: item.name):
        if not path.is_file() or path == output:
            continue
        if path.suffix.lower() not in ARTIFACT_SUFFIXES:
            continue
        platform = platform_for(path.name)
        digest = sha256(path)
        sidecar = path.with_name(path.name + ".sha256")
        sidecar.write_text(f"{digest}  {path.name}\n", encoding="ascii")
        artifacts.append(
            {
                "platform": platform,
                "filename": path.name,
                "sha256": digest,
                "bytes": path.stat().st_size,
            }
        )

    if not artifacts:
        raise SystemExit("error: no release artifacts were found")

    manifest = {
        "schema": 1,
        "product": args.product,
        "version": args.version,
        "build": args.build,
        "commit": args.commit,
        "tag": args.tag,
        "run_id": args.run_id,
        "timestamp": timestamp,
        "artifacts": artifacts,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {output} ({len(artifacts)} artifacts, sha256 sidecars)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
