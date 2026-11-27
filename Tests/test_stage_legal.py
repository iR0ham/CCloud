"""Regression tests for canonical legal staging.

Run from the repository root:

    python3 Tests/test_stage_legal.py

Every filesystem test uses a temporary fixture tree; the real checkout is
never staged or reset.
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts import stage_legal  # noqa: E402  (path setup must run first)


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _seed_canonical(root: Path) -> None:
    for name in stage_legal.DOCUMENTS:
        _write(root / name, f"canonical {name}\n")
    _write(root / stage_legal.DISTRIBUTION_STATUS, "canonical distribution status\n")
    for name in stage_legal.LICENSES:
        _write(root / "Legal" / "licenses" / name, f"canonical {name}\n")


class LegalStagingTests(unittest.TestCase):
    def test_windows_workflow_uses_root_safe_staging_command(self):
        workflow = (REPO_ROOT / ".github/workflows/build-windows.yml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("../scripts/stage_legal.py", workflow)
        self.assertEqual(workflow.count("python scripts/stage_legal.py android"), 2)

    def test_flutter_assets_declare_nested_legal_layout(self):
        pubspec = (REPO_ROOT / "flutter_app/pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("    - assets/legal/Legal/\n", pubspec)
        self.assertIn("    - assets/legal/Legal/licenses/\n", pubspec)
        self.assertNotIn("    - assets/legal/licenses/\n", pubspec)

    def test_reset_directory_replaces_symlink_without_deleting_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            target = Path(tmp) / "target"
            root.mkdir()
            target.mkdir()
            sentinel = target / "keep.txt"
            _write(sentinel, "keep\n")
            link = root / "legal"
            link.symlink_to(target, target_is_directory=True)

            with mock.patch.object(stage_legal, "ROOT", root):
                result = stage_legal.reset_directory(link)

            self.assertEqual(result, link.resolve())
            self.assertFalse(link.is_symlink())
            self.assertTrue(link.is_dir())
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep\n")
            self.assertEqual(list(link.iterdir()), [])

    def test_macos_rejects_resolved_destination_outside_resources(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            resources = Path(tmp) / "build/CCloud.app/Contents/Resources"
            outside = Path(tmp) / "outside"
            root.mkdir()
            resources.mkdir(parents=True)
            outside.mkdir()
            sentinel = outside / "licenses/keep.txt"
            _write(sentinel, "keep\n")
            (resources / "escape").symlink_to(outside, target_is_directory=True)

            with mock.patch.object(stage_legal, "ROOT", root):
                with self.assertRaises(SystemExit):
                    stage_legal.reset_directory(
                        resources / "escape/licenses",
                        expected_root=resources,
                    )

            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep\n")

    def test_macos_staging_preserves_symlink_targets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            build_root = Path(tmp) / "build"
            resources = build_root / "CCloud.app/Contents/Resources"
            outside = Path(tmp) / "outside"
            _seed_canonical(root)
            resources.parent.mkdir(parents=True)
            outside.mkdir()
            resource_sentinel = outside / "resources/keep.txt"
            legal_sentinel = outside / "legal/keep.txt"
            document_target = outside / "notice.txt"
            _write(resource_sentinel, "keep resources\n")
            _write(legal_sentinel, "keep legal\n")
            _write(document_target, "keep notice\n")
            resources.symlink_to(outside / "resources", target_is_directory=True)
            (outside / "resources/Legal").symlink_to(
                outside / "legal", target_is_directory=True
            )
            (outside / "resources/NOTICE").symlink_to(document_target)

            with mock.patch.object(stage_legal, "ROOT", root), mock.patch.dict(
                os.environ, {"CCLOUD_OUT": str(build_root)}
            ):
                count = stage_legal.stage_macos()

            self.assertEqual(count, 14)
            self.assertEqual(
                resource_sentinel.read_text(encoding="utf-8"), "keep resources\n"
            )
            self.assertEqual(legal_sentinel.read_text(encoding="utf-8"), "keep legal\n")
            self.assertEqual(document_target.read_text(encoding="utf-8"), "keep notice\n")
            self.assertFalse(resources.is_symlink())
            self.assertFalse((resources / "Legal").is_symlink())
            self.assertFalse((resources / "NOTICE").is_symlink())
            self.assertEqual(
                (resources / "NOTICE").read_text(encoding="utf-8"),
                "canonical NOTICE\n",
            )
            self.assertEqual(
                (resources / "Legal/DISTRIBUTION_STATUS.md").read_text(
                    encoding="utf-8"
                ),
                "canonical distribution status\n",
            )
            self.assertEqual(
                len(list((resources / "Legal/licenses").glob("*.txt"))), 10
            )

    def test_flutter_and_webos_package_all_notice_references(self):
        referenced = (
            "THIRD_PARTY_NOTICES.md",
            "SOURCES.md",
            "Legal/DISTRIBUTION_STATUS.md",
            "Legal/licenses/MIT-code3-dev-CCloud.txt",
        )
        stages = (
            ("flutter", stage_legal.stage_flutter, Path("flutter_app/assets/legal")),
            ("webos", stage_legal.stage_webos, Path("webos_app/app/legal")),
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            _seed_canonical(root)
            with mock.patch.object(stage_legal, "ROOT", root):
                for name, stage, relative in stages:
                    with self.subTest(platform=name):
                        self.assertEqual(stage(), 14)
                        legal = root / relative
                        self.assertEqual(
                            (legal / "NOTICE").read_text(encoding="utf-8"),
                            "canonical NOTICE\n",
                        )
                        for path in referenced:
                            self.assertTrue((legal / path).is_file(), path)
                        self.assertTrue((legal / "Legal/licenses").is_dir())
                        self.assertEqual(
                            len(list((legal / "Legal/licenses").glob("*.txt"))), 10
                        )
                        self.assertFalse((legal / "licenses").exists())


if __name__ == "__main__":
    unittest.main()
