#!/usr/bin/env python3
"""Canonical CCloud version and global build number.

`version.json` at the repository root is the single source of truth. Platform
metadata is generated from it by `sync` and validated by `check`; no build or
packaging script may carry a version literal of its own.

Commands:
    python3 scripts/version.py show
    python3 scripts/version.py sync
    python3 scripts/version.py check
    python3 scripts/version.py check --tag v2.0.0

Only the Python standard library is used, so the script runs unchanged on the
macOS, Linux and Windows GitHub Actions runners.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

VERSION_FILE = "version.json"

# ASCII-only, exactly three numeric components: the build number is separate.
SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")

# Android's versionCode is a signed 32-bit value capped at 2100000000. Catching
# an oversized canonical build here keeps the failure at the source instead of
# inside a Gradle build.
MAX_ANDROID_VERSION_CODE = 2_100_000_000

INFO_PLIST = "Info.plist"
PUBSPEC = "flutter_app/pubspec.yaml"
WEBOS_APPINFO = "webos_app/app/appinfo.json"
WEBOS_SERVICE_PACKAGE = "webos_app/service/com.ccloud.tv.service/package.json"
WEBOS_NPM_PACKAGE = "webos_app/package.json"
WEBOS_VERSION_JS = "webos_app/app/js/version.js"

# Every file `sync` owns and `check` validates. webOS metadata carries no
# separate build field (appinfo.json/package.json only have `version`), so the
# build number reaches webOS through the generated js/version.js instead.
PLATFORM_METADATA = (
    INFO_PLIST,
    PUBSPEC,
    WEBOS_APPINFO,
    WEBOS_SERVICE_PACKAGE,
    WEBOS_NPM_PACKAGE,
    WEBOS_VERSION_JS,
)


class VersionError(Exception):
    """Canonical data is invalid or a platform file drifted from it."""


@dataclass(frozen=True)
class Version:
    product: str
    version: str
    build: int

    @property
    def flutter_version(self) -> str:
        """The `version:` value pubspec.yaml (and thus Flutter) consumes."""
        return f"{self.version}+{self.build}"


# --------------------------------------------------------------------------- io


def _read(path: Path) -> str:
    # newline="" keeps LF/CRLF exactly as checked in; a Windows runner must not
    # silently rewrite every metadata file it merely validates.
    with open(path, "r", encoding="utf-8", newline="") as handle:
        return handle.read()


def _read_required(path: Path, rel: str) -> str:
    try:
        return _read(path)
    except OSError as exc:
        raise VersionError(
            f"{rel}: cannot read file: {exc.strerror or exc}"
        ) from exc


def _write_if_changed(path: Path, text: str) -> None:
    try:
        if _read(path) == text:
            return
    except OSError:
        pass
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


# ----------------------------------------------------------------- canonical load


def load_version(root: Path) -> Version:
    """Read and validate `<root>/version.json`."""

    path = Path(root) / VERSION_FILE
    try:
        text = _read(path)
    except OSError as exc:
        raise VersionError(
            f"{VERSION_FILE}: cannot read canonical version file: "
            f"{exc.strerror or exc}"
        ) from exc

    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise VersionError(f"{VERSION_FILE}: invalid JSON: {exc}") from exc

    if not isinstance(data, dict):
        raise VersionError(f"{VERSION_FILE}: expected a JSON object")

    required = {"product", "version", "build"}
    missing = sorted(required - set(data))
    extra = sorted(set(data) - required)
    if missing:
        raise VersionError(
            f"{VERSION_FILE}: missing field(s): {', '.join(missing)}"
        )
    if extra:
        raise VersionError(
            f"{VERSION_FILE}: unexpected field(s): {', '.join(extra)}"
        )

    product = data["product"]
    version = data["version"]
    build = data["build"]

    if not isinstance(product, str) or not product.strip():
        raise VersionError(f"{VERSION_FILE}: product must be a non-empty string")
    if not isinstance(version, str) or not SEMVER_RE.fullmatch(version):
        raise VersionError(
            f"{VERSION_FILE}: version must be semantic x.y.z, got {version!r}"
        )
    # type(...) is int, not isinstance, because bool would pass isinstance.
    if type(build) is not int or build <= 0:
        raise VersionError(
            f"{VERSION_FILE}: build must be a positive integer, got {build!r}"
        )
    if build > MAX_ANDROID_VERSION_CODE:
        raise VersionError(
            f"{VERSION_FILE}: build {build} exceeds Android's versionCode "
            f"maximum {MAX_ANDROID_VERSION_CODE}"
        )

    return Version(product=product, version=version, build=build)


# ---------------------------------------------------------------- text transforms


def _plist_pattern(key: str) -> re.Pattern[str]:
    return re.compile(
        r"<key>" + re.escape(key) + r"</key>\s*<string>([^<]*)</string>"
    )


def _plist_value(text: str, key: str, rel: str) -> str:
    matches = _plist_pattern(key).findall(text)
    if len(matches) != 1:
        raise VersionError(
            f"{rel}: expected exactly one {key} <string>, found {len(matches)}"
        )
    return matches[0]


def _replace_plist_string(text: str, key: str, value: str, rel: str) -> str:
    pattern = re.compile(
        r"(<key>" + re.escape(key) + r"</key>\s*<string>)([^<]*)(</string>)"
    )
    count = len(pattern.findall(text))
    if count != 1:
        raise VersionError(
            f"{rel}: expected exactly one {key} <string>, found {count}"
        )
    # A lambda keeps backslashes in `value` from being read as group references.
    return pattern.sub(
        lambda match: match.group(1) + value + match.group(3),
        text,
        count=1,
    )


# `\r?` sits inside group 3 so a CRLF checkout keeps its line ending when the
# value is substituted; a trailing `\s*` would absorb the `\r` outside the
# captured text and the replacement would silently drop it.
PUBSPEC_VERSION_RE = re.compile(
    r"^(version:[ \t]*)(\S+)([ \t]*(?:#.*)?\r?)$", re.MULTILINE
)


def _pubspec_version(text: str, rel: str) -> str:
    matches = PUBSPEC_VERSION_RE.findall(text)
    if len(matches) != 1:
        raise VersionError(
            f"{rel}: expected exactly one top-level `version:` line, "
            f"found {len(matches)}"
        )
    return matches[0][1]


def _replace_pubspec_version(text: str, value: str, rel: str) -> str:
    matches = PUBSPEC_VERSION_RE.findall(text)
    if len(matches) != 1:
        raise VersionError(
            f"{rel}: expected exactly one top-level `version:` line, "
            f"found {len(matches)}"
        )
    return PUBSPEC_VERSION_RE.sub(
        lambda match: match.group(1) + value + match.group(3),
        text,
        count=1,
    )


JSON_VERSION_RE = re.compile(r'("version"[ \t]*:[ \t]*")([^"\\]*)(")')


def _load_json_object(text: str, rel: str) -> dict:
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise VersionError(f"{rel}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise VersionError(f"{rel}: expected a JSON object")
    return data


def _replace_json_version(text: str, value: str, rel: str) -> str:
    _load_json_object(text, rel)
    count = len(JSON_VERSION_RE.findall(text))
    if count != 1:
        raise VersionError(
            f'{rel}: expected exactly one "version" field, found {count}'
        )
    return JSON_VERSION_RE.sub(
        lambda match: match.group(1) + value + match.group(3),
        text,
        count=1,
    )


def _render_version_js(version: Version) -> str:
    return (
        "/* Generated by scripts/version.py from version.json. Do not edit by hand. */\n"
        f'window.CCLOUD_VERSION = "{version.version}";\n'
        f'window.CCLOUD_BUILD = "{version.build}";\n'
    )


def _version_js_values(text: str, rel: str) -> tuple[str, str]:
    version_match = re.search(
        r'window\.CCLOUD_VERSION[ \t]*=[ \t]*"([^"]*)"[ \t]*;', text
    )
    build_match = re.search(
        r'window\.CCLOUD_BUILD[ \t]*=[ \t]*"([^"]*)"[ \t]*;', text
    )
    missing = [
        name
        for name, match in (
            ("window.CCLOUD_VERSION", version_match),
            ("window.CCLOUD_BUILD", build_match),
        )
        if match is None
    ]
    if missing:
        raise VersionError(
            f"{rel}: missing assignment(s): {', '.join(missing)}"
        )
    assert version_match is not None and build_match is not None
    return version_match.group(1), build_match.group(1)


# ----------------------------------------------------------------------- commands


def sync_version(root: Path) -> Version:
    """Regenerate every platform metadata file from `version.json`."""

    root = Path(root)
    version = load_version(root)
    planned: list[tuple[Path, str]] = []

    # Read and transform everything before writing anything: an invalid or
    # incomplete tree must fail without leaving a half-synced repository.
    plist_text = _read_required(root / INFO_PLIST, INFO_PLIST)
    plist_text = _replace_plist_string(
        plist_text, "CFBundleShortVersionString", version.version, INFO_PLIST
    )
    plist_text = _replace_plist_string(
        plist_text, "CFBundleVersion", str(version.build), INFO_PLIST
    )
    planned.append((root / INFO_PLIST, plist_text))

    pubspec_text = _read_required(root / PUBSPEC, PUBSPEC)
    pubspec_text = _replace_pubspec_version(
        pubspec_text, version.flutter_version, PUBSPEC
    )
    planned.append((root / PUBSPEC, pubspec_text))

    for rel in (WEBOS_APPINFO, WEBOS_SERVICE_PACKAGE, WEBOS_NPM_PACKAGE):
        text = _read_required(root / rel, rel)
        text = _replace_json_version(text, version.version, rel)
        planned.append((root / rel, text))

    planned.append((root / WEBOS_VERSION_JS, _render_version_js(version)))

    for path, text in planned:
        path.parent.mkdir(parents=True, exist_ok=True)
        _write_if_changed(path, text)

    return version


def check_version(root: Path, tag: str | None = None) -> Version:
    """Validate `version.json` and every generated platform file."""

    root = Path(root)
    version = load_version(root)
    errors: list[str] = []

    def expect(rel: str, field: str, actual: object, expected: str) -> None:
        if actual != expected:
            errors.append(f"{rel}: {field} is {actual!r}, expected {expected!r}")

    try:
        plist_text = _read(root / INFO_PLIST)
        for key, expected in (
            ("CFBundleShortVersionString", version.version),
            ("CFBundleVersion", str(version.build)),
        ):
            try:
                actual = _plist_value(plist_text, key, INFO_PLIST)
            except VersionError as exc:
                errors.append(str(exc))
            else:
                expect(INFO_PLIST, key, actual, expected)
    except OSError as exc:
        errors.append(f"{INFO_PLIST}: cannot read file: {exc.strerror or exc}")

    try:
        pubspec_text = _read(root / PUBSPEC)
        try:
            actual = _pubspec_version(pubspec_text, PUBSPEC)
        except VersionError as exc:
            errors.append(str(exc))
        else:
            expect(PUBSPEC, "version", actual, version.flutter_version)
    except OSError as exc:
        errors.append(f"{PUBSPEC}: cannot read file: {exc.strerror or exc}")

    for rel in (WEBOS_APPINFO, WEBOS_SERVICE_PACKAGE, WEBOS_NPM_PACKAGE):
        try:
            data = _load_json_object(_read(root / rel), rel)
        except OSError as exc:
            errors.append(f"{rel}: cannot read file: {exc.strerror or exc}")
        except VersionError as exc:
            errors.append(str(exc))
        else:
            if "version" not in data:
                errors.append(f"{rel}: missing version field")
            else:
                expect(rel, "version", data["version"], version.version)

    try:
        js_version, js_build = _version_js_values(
            _read(root / WEBOS_VERSION_JS), WEBOS_VERSION_JS
        )
    except OSError as exc:
        errors.append(
            f"{WEBOS_VERSION_JS}: cannot read file: {exc.strerror or exc}"
        )
    except VersionError as exc:
        errors.append(str(exc))
    else:
        expect(
            WEBOS_VERSION_JS, "window.CCLOUD_VERSION", js_version, version.version
        )
        expect(
            WEBOS_VERSION_JS, "window.CCLOUD_BUILD", js_build, str(version.build)
        )

    if tag is not None:
        expected_tag = f"v{version.version}"
        if tag.strip() != expected_tag:
            errors.append(
                f"release tag {tag!r} does not match {expected_tag!r} "
                f"(version {version.version})"
            )

    if errors:
        raise VersionError("\n".join(errors))
    return version


# ---------------------------------------------------------------------------- cli


def _default_root() -> Path:
    return Path(__file__).resolve().parent.parent


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Canonical CCloud version/build metadata."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=_default_root(),
        help="repository root containing version.json (default: this checkout)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("show", help="print the canonical version as JSON")
    subparsers.add_parser(
        "sync", help="write platform metadata from version.json"
    )
    check_parser = subparsers.add_parser(
        "check", help="validate canonical data and platform metadata"
    )
    check_parser.add_argument(
        "--tag",
        help="require this release tag to equal v<version>, e.g. v2.0.0",
    )

    args = parser.parse_args(argv)

    try:
        if args.command == "show":
            version = load_version(args.root)
            print(
                json.dumps(
                    {
                        "product": version.product,
                        "version": version.version,
                        "build": version.build,
                    },
                    ensure_ascii=False,
                )
            )
        elif args.command == "sync":
            version = sync_version(args.root)
            print(
                f"synced {version.product} {version.version} "
                f"(build {version.build})"
            )
        else:
            version = check_version(args.root, args.tag)
            suffix = f", tag {args.tag}" if args.tag else ""
            print(
                f"ok: {version.product} {version.version} "
                f"(build {version.build}{suffix})"
            )
    except (VersionError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
