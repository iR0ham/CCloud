"""Regression tests for SOURCES.md provenance digest enforcement.

Run from the repository root:

    python3 Tests/test_verify_provenance.py

Every structural test uses a temporary fixture tree; the real checkout is only
read, never written. The `abc` digest literal below is the published NIST/SEC1
SHA-256 test vector, so the recomputation is checked against an independently
derived value instead of against the code under test.
"""

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts import verify_provenance  # noqa: E402  (path setup must run first)

ABC_SHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
OTHER_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
ZERO_SHA256 = "0" * 64


def _seed_license(root: Path, name: str, body: bytes) -> None:
    directory = root / "Legal" / "licenses"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / name).write_bytes(body)


class ProvenanceParsingTests(unittest.TestCase):
    def test_bullet_and_table_forms_are_both_parsed(self):
        document = "\n".join(
            [
                "### Component",
                "",
                "- Retained text: `Legal/licenses/MIT-one.txt`",
                f"- Text SHA-256: `{ABC_SHA256}`",
                "",
                "| Retained text | Source URL | Text SHA-256 |",
                "| --- | --- | --- |",
                f"| `Legal/licenses/GPL-2.0.txt` | https://ftp.gnu.org/gnu/Licenses/gpl-2.0.txt | `{OTHER_SHA256}` |",
            ]
        )
        entries, problems = verify_provenance.parse_provenance(document)
        self.assertEqual(problems, [])
        self.assertEqual(
            [(entry.path, entry.digest) for entry in entries],
            [
                ("Legal/licenses/MIT-one.txt", ABC_SHA256),
                ("Legal/licenses/GPL-2.0.txt", OTHER_SHA256),
            ],
        )

    def test_archive_table_rows_are_not_treated_as_retained_files(self):
        document = "\n".join(
            [
                "| Package | Version | Archive URL | Archive SHA-256 |",
                "| --- | --- | --- | --- |",
                f"| media_kit | 1.2.6 | https://pub.dev/api/archives/media_kit-1.2.6.tar.gz | `{ZERO_SHA256}` |",
                "- Retained text: `Legal/licenses/MIT-one.txt`",
                f"- Text SHA-256: `{ABC_SHA256}`",
            ]
        )
        entries, problems = verify_provenance.parse_provenance(document)
        self.assertEqual(problems, [])
        self.assertEqual([entry.path for entry in entries], ["Legal/licenses/MIT-one.txt"])

    def test_retained_text_without_digest_is_a_problem(self):
        document = "\n".join(
            [
                "- Retained text: `Legal/licenses/MIT-one.txt`",
                "- License source: https://example.test/LICENSE",
            ]
        )
        entries, problems = verify_provenance.parse_provenance(document)
        self.assertEqual(entries, [])
        self.assertEqual(len(problems), 1)
        self.assertIn("has no `Text SHA-256` entry", problems[0])
        self.assertIn("MIT-one.txt", problems[0])

    def test_truncated_digest_is_rejected_instead_of_skipped(self):
        document = "\n".join(
            [
                "- Retained text: `Legal/licenses/MIT-one.txt`",
                f"- Text SHA-256: `{ABC_SHA256[:63]}`",
            ]
        )
        entries, problems = verify_provenance.parse_provenance(document)
        self.assertEqual(entries, [])
        self.assertEqual(len(problems), 1)
        self.assertIn("is not a 64-hex SHA-256 value", problems[0])

    def test_digest_without_retained_text_is_a_problem(self):
        entries, problems = verify_provenance.parse_provenance(
            f"- Text SHA-256: `{ABC_SHA256}`"
        )
        self.assertEqual(entries, [])
        self.assertEqual(len(problems), 1)
        self.assertIn("has no retained text", problems[0])


class ProvenanceVerificationTests(unittest.TestCase):
    def test_digest_mismatch_names_the_offending_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_license(root, "MIT-one.txt", b"abc")
            document = "\n".join(
                [
                    "- Retained text: `Legal/licenses/MIT-one.txt`",
                    f"- Text SHA-256: `{ZERO_SHA256}`",
                ]
            )
            entries, parse_problems = verify_provenance.parse_provenance(document)
            self.assertEqual(parse_problems, [])
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(verified, 0)
            self.assertEqual(len(problems), 1)
            self.assertIn("digest mismatch for Legal/licenses/MIT-one.txt", problems[0])
            self.assertIn(ABC_SHA256, problems[0])

    def test_missing_retained_file_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Legal" / "licenses").mkdir(parents=True)
            document = "\n".join(
                [
                    "- Retained text: `Legal/licenses/MIT-gone.txt`",
                    f"- Text SHA-256: `{ABC_SHA256}`",
                ]
            )
            entries, _ = verify_provenance.parse_provenance(document)
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(verified, 0)
            self.assertIn("retained file is missing: Legal/licenses/MIT-gone.txt", problems[0])

    def test_packaged_license_without_documentation_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_license(root, "MIT-one.txt", b"abc")
            _seed_license(root, "MIT-undocumented.txt", b"abc")
            document = "\n".join(
                [
                    "- Retained text: `Legal/licenses/MIT-one.txt`",
                    f"- Text SHA-256: `{ABC_SHA256}`",
                ]
            )
            entries, _ = verify_provenance.parse_provenance(document)
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(verified, 1)
            self.assertEqual(len(problems), 1)
            self.assertIn("MIT-undocumented.txt", problems[0])
            self.assertIn("no digest entry", problems[0])

    def test_retained_path_cannot_escape_the_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "checkout"
            (root / "Legal" / "licenses").mkdir(parents=True)
            outside = Path(tmp) / "outside.txt"
            outside.write_bytes(b"abc")
            document = "\n".join(
                [
                    "- Retained text: `../outside.txt`",
                    f"- Text SHA-256: `{ABC_SHA256}`",
                ]
            )
            entries, _ = verify_provenance.parse_provenance(document)
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(verified, 0)
            self.assertEqual(len(problems), 1)
            self.assertIn("must stay inside the checkout", problems[0])

    def test_documented_symlink_cannot_leave_the_checkout(self):
        # A committed symlink is invisible to the lexical `..` rejection above: the
        # joined path still opens bytes outside the checkout, so without a
        # canonicalized containment re-check the escaped text verifies against a
        # real digest. The link body is deliberately the published `abc` vector so a
        # digest mismatch cannot masquerade as the failure; the non-link half proves
        # this same document, digest and layout verify green once the bytes are
        # inside the checkout.
        #
        # Two problems are expected, not one, and that is the point of the pairing.
        # An escaping path is no longer counted as a documented retained text, so the
        # directory sweep independently reports the license tree entry that nothing
        # inside the checkout actually accounts for. Before the ordering was fixed, the
        # lexical spelling satisfied the sweep and the only visible symptom was the
        # containment message, which is precisely the "the sweep keeps counting it as
        # documented" behaviour this test exists to prevent.
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / "checkout"
            root.joinpath("Legal", "licenses").mkdir(parents=True)
            external = base / "external"
            external.mkdir()
            escaped = external / "MIT-one.txt"
            escaped.write_bytes(b"abc")
            root.joinpath("Legal", "licenses", "MIT-one.txt").symlink_to(escaped)
            document = "\n".join(
                [
                    "- Retained text: `Legal/licenses/MIT-one.txt`",
                    f"- Text SHA-256: `{ABC_SHA256}`",
                ]
            )
            entries, parse_problems = verify_provenance.parse_provenance(document)
            self.assertEqual(parse_problems, [])
            self.assertEqual(verify_provenance.sha256_of(escaped), ABC_SHA256)
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(verified, 0)
            self.assertEqual(len(problems), 2, problems)
            containment = [p for p in problems if "must stay inside the checkout" in p]
            self.assertEqual(len(containment), 1, problems)
            self.assertIn("Legal/licenses/MIT-one.txt", containment[0])
            sweep = [p for p in problems if "retained license tree" in p]
            self.assertEqual(len(sweep), 1, problems)
            self.assertIn("MIT-one.txt", sweep[0])
            # Same document, retained copy actually inside the checkout.
            link = root.joinpath("Legal", "licenses", "MIT-one.txt")
            link.unlink()
            link.write_bytes(b"abc")
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(verified, 1)
            self.assertEqual(problems, [])

    def test_license_text_nested_one_level_is_still_swept(self):
        # The sweep is recursive, and the documented key is the relative path rather
        # than the file name. Two halves, because either alone passes on a
        # name-only implementation: an undocumented nested text must be reported, and
        # a documented nested text must verify without the sweep inventing a duplicate
        # complaint for the same bytes.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nested = root / "Legal" / "licenses" / "third-party"
            nested.mkdir(parents=True)
            (nested / "MIT-two.txt").write_bytes(b"abc")
            document = "\n".join(
                [
                    "- Retained text: `Legal/licenses/MIT-one.txt`",
                    f"- Text SHA-256: `{ABC_SHA256}`",
                ]
            )
            (root / "Legal" / "licenses" / "MIT-one.txt").write_bytes(b"abc")
            entries, _ = verify_provenance.parse_provenance(document)
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(verified, 1)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("third-party/MIT-two.txt", problems[0])
            self.assertIn("retained license tree", problems[0])

            documented_nested = "\n".join(
                [
                    "- Retained text: `Legal/licenses/MIT-one.txt`",
                    f"- Text SHA-256: `{ABC_SHA256}`",
                    "- Retained text: `Legal/licenses/third-party/MIT-two.txt`",
                    f"- Text SHA-256: `{ABC_SHA256}`",
                ]
            )
            entries, _ = verify_provenance.parse_provenance(documented_nested)
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(problems, [])
            self.assertEqual(verified, 2)

    def test_conflicting_duplicate_entries_are_reported(self):
        document = "\n".join(
            [
                "- Retained text: `Legal/licenses/MIT-one.txt`",
                f"- Text SHA-256: `{ABC_SHA256}`",
                "- Retained text: `Legal/licenses/MIT-one.txt`",
                f"- Text SHA-256: `{ZERO_SHA256}`",
            ]
        )
        entries, _ = verify_provenance.parse_provenance(document)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_license(root, "MIT-one.txt", b"abc")
            verified, problems = verify_provenance.verify_provenance(
                root, entries, verbose=False
            )
            self.assertEqual(verified, 1)
            self.assertTrue(
                any("documented twice with different digests" in p for p in problems),
                problems,
            )

    def test_sha256_matches_the_published_abc_vector(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "abc.txt"
            target.write_bytes(b"abc")
            self.assertEqual(verify_provenance.sha256_of(target), ABC_SHA256)


class ProvenanceAgainstRepositoryTests(unittest.TestCase):
    def _run_main(self, argv: list[str]) -> tuple[int, str, str]:
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = verify_provenance.main(argv)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_repository_ledger_verifies_and_reports_the_count(self):
        license_dir = REPO_ROOT / "Legal" / "licenses"
        on_disk = sorted(path.name for path in license_dir.iterdir() if path.is_file())
        code, stdout, stderr = self._run_main([])
        self.assertEqual(stderr, "")
        self.assertEqual(code, 0)
        self.assertIn(
            f"provenance: {len(on_disk)} retained files verified against SOURCES.md",
            stdout,
        )
        entries, problems = verify_provenance.parse_provenance(
            (REPO_ROOT / "SOURCES.md").read_text(encoding="utf-8")
        )
        self.assertEqual(problems, [])
        documented = sorted(entry.path.rsplit("/", 1)[1] for entry in entries)
        self.assertEqual(documented, on_disk)
        self.assertGreaterEqual(len(on_disk), 1)

    def test_mutated_license_byte_breaks_the_gate(self):
        # Controlled mutation, applied to a copy of the real document so the
        # checkout is untouched: the gate must fail on the digest, not skip it.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in sorted((REPO_ROOT / "Legal" / "licenses").iterdir()):
                _seed_license(root, name.name, name.read_bytes())
            (root / "SOURCES.md").write_text(
                (REPO_ROOT / "SOURCES.md").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self.assertEqual(self._run_main(["--root", str(root), "--quiet"])[0], 0)
            (root / "Legal" / "licenses" / "GPL-2.0.txt").write_bytes(
                (root / "Legal" / "licenses" / "GPL-2.0.txt").read_bytes() + b"\n"
            )
            code, _stdout, stderr = self._run_main(["--root", str(root), "--quiet"])
            self.assertEqual(code, 1)
            self.assertIn("digest mismatch for Legal/licenses/GPL-2.0.txt", stderr)


if __name__ == "__main__":
    unittest.main()
