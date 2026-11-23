"""Tests for scripts/version.py (canonical version/build metadata).

Run from the repository root:

    python3 Tests/test_version.py

or through discovery:

    python3 -m unittest discover -s Tests -p 'test_version.py'

Every test builds its own temporary fixture tree; the real checkout is never
read or written.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.version import (  # noqa: E402  (path setup must run first)
    Version,
    VersionError,
    check_version,
    load_version,
    sync_version,
)

INFO_PLIST_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleExecutable</key>
\t<string>CCloud</string>
\t<key>CFBundleShortVersionString</key>
\t<string>{version}</string>
\t<key>CFBundleVersion</key>
\t<string>{build}</string>
</dict>
</plist>
"""

METADATA_PATHS = (
    "Info.plist",
    "flutter_app/pubspec.yaml",
    "webos_app/app/appinfo.json",
    "webos_app/service/com.ccloud.tv.service/package.json",
    "webos_app/package.json",
    "webos_app/app/js/version.js",
)


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def _read(path: Path) -> str:
    with open(path, "r", encoding="utf-8", newline="") as handle:
        return handle.read()


def _seed_repo(
    root: Path,
    *,
    version: str = "2.0.0",
    build: int = 22,
    pubspec: str = "1.0.8+9",
    appinfo: str = "1.0.0",
    service: str = "1.0.0",
    npm: str = "1.0.0",
    js_version: str = "1.0.0",
    js_build: str = "9",
    write_js: bool = True,
) -> None:
    """Write a fixture whose canonical file is valid but platform files drift."""

    _write(
        root / "version.json",
        json.dumps(
            {"product": "CCloud", "version": version, "build": build},
            ensure_ascii=False,
        )
        + "\n",
    )
    _write(
        root / "Info.plist",
        INFO_PLIST_TEMPLATE.format(version=version, build=build),
    )
    _write(
        root / "flutter_app/pubspec.yaml",
        f"name: ccloud\ndescription: fixture\nversion: {pubspec}\n",
    )
    _write(
        root / "webos_app/app/appinfo.json",
        json.dumps({"id": "com.ccloud.tv", "version": appinfo}, indent=2) + "\n",
    )
    _write(
        root / "webos_app/service/com.ccloud.tv.service/package.json",
        json.dumps(
            {"name": "com.ccloud.tv.service", "version": service}, indent=2
        )
        + "\n",
    )
    _write(
        root / "webos_app/package.json",
        json.dumps({"name": "ccloud-webos", "version": npm}, indent=2) + "\n",
    )
    if write_js:
        _write(
            root / "webos_app/app/js/version.js",
            f'window.CCLOUD_VERSION = "{js_version}";\n'
            f'window.CCLOUD_BUILD = "{js_build}";\n',
        )


class VersionFileTests(unittest.TestCase):
    def test_load_version_returns_canonical_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root)
            self.assertEqual(load_version(root), Version("CCloud", "2.0.0", 22))

    def test_load_version_rejects_invalid_values(self):
        cases = [
            ({"product": "CCloud", "version": "2.0", "build": 22}, "semantic"),
            (
                {"product": "CCloud", "version": "2.0.0-beta", "build": 22},
                "semantic",
            ),
            ({"product": "CCloud", "version": "v2.0.0", "build": 22}, "semantic"),
            ({"product": "CCloud", "version": "2.0.0", "build": 0}, "build"),
            ({"product": "CCloud", "version": "2.0.0", "build": -1}, "build"),
            ({"product": "CCloud", "version": "2.0.0", "build": "22"}, "build"),
            ({"product": "CCloud", "version": "2.0.0", "build": 2.5}, "build"),
            ({"product": "CCloud", "version": "2.0.0", "build": True}, "build"),
            ({"product": "CCloud", "version": "2.0.0"}, "build"),
            ({"product": "CCloud", "version": "2.0.0", "build": 22, "extra": 1}, "extra"),
            ({"product": "", "version": "2.0.0", "build": 22}, "product"),
        ]
        for payload, needle in cases:
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                _write(root / "version.json", json.dumps(payload))
                with self.assertRaises(VersionError) as ctx:
                    load_version(root)
                self.assertIn(needle, str(ctx.exception))

    def test_load_version_rejects_missing_or_malformed_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(VersionError) as ctx:
                load_version(root)
            self.assertIn("version.json", str(ctx.exception))

            _write(root / "version.json", "{not json")
            with self.assertRaises(VersionError) as ctx:
                load_version(root)
            self.assertIn("invalid JSON", str(ctx.exception))

            _write(root / "version.json", "[]")
            with self.assertRaises(VersionError) as ctx:
                load_version(root)
            self.assertIn("object", str(ctx.exception))


class SyncTests(unittest.TestCase):
    def test_sync_converges_drifted_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root)

            self.assertEqual(sync_version(root), Version("CCloud", "2.0.0", 22))
            self.assertEqual(check_version(root), Version("CCloud", "2.0.0", 22))

            plist = _read(root / "Info.plist")
            self.assertIn("<string>2.0.0</string>", plist)
            self.assertIn("<string>22</string>", plist)
            # Unrelated plist content is preserved, not regenerated.
            self.assertIn("<key>CFBundleExecutable</key>", plist)

            pubspec = _read(root / "flutter_app/pubspec.yaml")
            self.assertIn("version: 2.0.0+22", pubspec)
            self.assertIn("description: fixture", pubspec)

            for rel in (
                "webos_app/app/appinfo.json",
                "webos_app/service/com.ccloud.tv.service/package.json",
                "webos_app/package.json",
            ):
                self.assertEqual(
                    json.loads(_read(root / rel))["version"], "2.0.0"
                )

            self.assertEqual(
                _read(root / "webos_app/app/js/version.js"),
                "/* Generated by scripts/version.py from version.json. "
                "Do not edit by hand. */\n"
                'window.CCLOUD_VERSION = "2.0.0";\n'
                'window.CCLOUD_BUILD = "22";\n',
            )

    def test_sync_creates_version_js(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root, write_js=False)
            self.assertFalse((root / "webos_app/app/js/version.js").exists())

            sync_version(root)

            text = _read(root / "webos_app/app/js/version.js")
            self.assertIn('window.CCLOUD_VERSION = "2.0.0";', text)
            self.assertIn('window.CCLOUD_BUILD = "22";', text)

    def test_sync_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root)

            sync_version(root)
            first = {rel: _read(root / rel) for rel in METADATA_PATHS}

            sync_version(root)
            second = {rel: _read(root / rel) for rel in METADATA_PATHS}

            self.assertEqual(first, second)

    def test_sync_preserves_crlf_pubspec(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root)
            _write(
                root / "flutter_app/pubspec.yaml",
                "name: ccloud\r\ndescription: fixture\r\nversion: 1.0.8+9\r\n",
            )

            sync_version(root)

            text = _read(root / "flutter_app/pubspec.yaml")
            self.assertIn("version: 2.0.0+22\r\n", text)
            self.assertIn("description: fixture\r\n", text)
            self.assertEqual(text.count("\n"), text.count("\r\n"))
            self.assertEqual(check_version(root), Version("CCloud", "2.0.0", 22))

    def test_sync_validates_canonical_before_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root, version="2.0", build=22)  # invalid semver
            before = _read(root / "flutter_app/pubspec.yaml")

            with self.assertRaises(VersionError):
                sync_version(root)

            self.assertEqual(_read(root / "flutter_app/pubspec.yaml"), before)


class CheckTests(unittest.TestCase):
    def _synced_root(self, tmp: str) -> Path:
        root = Path(tmp)
        _seed_repo(root)
        sync_version(root)
        return root

    def test_check_accepts_synced_tree_and_matching_tag(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._synced_root(tmp)
            self.assertEqual(check_version(root), Version("CCloud", "2.0.0", 22))
            self.assertEqual(
                check_version(root, "v2.0.0"), Version("CCloud", "2.0.0", 22)
            )

    def test_check_rejects_conflicting_tag(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._synced_root(tmp)
            for tag in ("v2.0.1", "2.0.0", "windows-1.0.8", "v2.0.0-rc1"):
                with self.subTest(tag=tag):
                    with self.assertRaises(VersionError) as ctx:
                        check_version(root, tag)
                    self.assertIn("tag", str(ctx.exception))

    def test_check_detects_drift_in_each_metadata_file(self):
        def replace(rel: str, old: str, new: str):
            def mutate(root: Path) -> None:
                path = root / rel
                text = _read(path)
                self.assertIn(old, text)
                _write(path, text.replace(old, new, 1))

            return mutate

        def write_json(rel: str, version: str):
            def mutate(root: Path) -> None:
                _write(
                    root / rel,
                    json.dumps({"name": "fixture", "version": version}) + "\n",
                )

            return mutate

        cases = [
            (
                "Info.plist",
                replace(
                    "Info.plist",
                    "<string>2.0.0</string>",
                    "<string>1.9.9</string>",
                ),
                "CFBundleShortVersionString",
            ),
            (
                "Info.plist",
                replace("Info.plist", "<string>22</string>", "<string>999</string>"),
                "CFBundleVersion",
            ),
            (
                "flutter_app/pubspec.yaml",
                replace(
                    "flutter_app/pubspec.yaml",
                    "version: 2.0.0+22",
                    "version: 1.0.8+9",
                ),
                "version",
            ),
            (
                "webos_app/app/appinfo.json",
                write_json("webos_app/app/appinfo.json", "1.0.0"),
                "version",
            ),
            (
                "webos_app/service/com.ccloud.tv.service/package.json",
                write_json(
                    "webos_app/service/com.ccloud.tv.service/package.json",
                    "1.0.0",
                ),
                "version",
            ),
            (
                "webos_app/package.json",
                write_json("webos_app/package.json", "1.0.0"),
                "version",
            ),
            (
                "webos_app/app/js/version.js",
                replace(
                    "webos_app/app/js/version.js",
                    'window.CCLOUD_VERSION = "2.0.0";',
                    'window.CCLOUD_VERSION = "1.0.0";',
                ),
                "CCLOUD_VERSION",
            ),
            (
                "webos_app/app/js/version.js",
                replace(
                    "webos_app/app/js/version.js",
                    'window.CCLOUD_BUILD = "22";',
                    'window.CCLOUD_BUILD = "9";',
                ),
                "CCLOUD_BUILD",
            ),
        ]

        for rel, mutate, needle in cases:
            with self.subTest(target=rel, field=needle), tempfile.TemporaryDirectory() as tmp:
                root = self._synced_root(tmp)
                mutate(root)
                with self.assertRaises(VersionError) as ctx:
                    check_version(root)
                message = str(ctx.exception)
                self.assertIn(rel, message)
                self.assertIn(needle, message)

    def test_check_reports_missing_version_js(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._synced_root(tmp)
            (root / "webos_app/app/js/version.js").unlink()

            with self.assertRaises(VersionError) as ctx:
                check_version(root)

            message = str(ctx.exception)
            self.assertIn("webos_app/app/js/version.js", message)
            self.assertIn("cannot read", message)

    def test_check_reports_invalid_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._synced_root(tmp)
            _write(root / "webos_app/app/appinfo.json", "{broken")

            with self.assertRaises(VersionError) as ctx:
                check_version(root)

            message = str(ctx.exception)
            self.assertIn("webos_app/app/appinfo.json", message)
            self.assertIn("invalid JSON", message)


if __name__ == "__main__":
    unittest.main()
