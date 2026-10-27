"""Fail-closed budget for the remaining legacy Mono/NuGet native CI callers.

Existing old-action usage is *technical debt*, never a permission to grow
its footprint. Allowed counts are ceilings, not targets; future migration
PRs can reduce them without temporarily breaking unrelated CI.
"""
from __future__ import annotations

from pathlib import Path
import re
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_DIR = ".github/workflows"
LEGACY_MAX = {
    ".github/workflows/gmssl-x509-candidate.yml": 1,
    ".github/workflows/turbomedia-media-cache.yml": 1,
    ".github/workflows/warm-cache.yml": 12,
}
LEGACY_WRITE_MAX = {
    ".github/workflows/turbomedia-media-cache.yml": 1,
    ".github/workflows/warm-cache.yml": 7,
}
LEGACY_TOTAL_MAX = 14
WRITER_TOTAL_MAX = 8

USES = re.compile(r'^\s*(?:-\s*)?uses:\s*["\x27]?([^\s"#\x27]+)', re.I)
OLD = re.compile(
    r'^(?:\./\.github/actions/setup-vcpkg-cache|'
    r'qigao/vcpkg-cache/\.github/actions/setup-vcpkg-cache@[^\s]+)$',
    re.I,
)
WRITE_MODE = re.compile(r'^\s*mode:\s*["\x27]?readwrite["\x27]?\s*(?:#.*)?$', re.I)


def inspect(root: Path) -> tuple[dict[str, int], dict[str, int]]:
    legacy = {}
    write = {}
    locations = sorted((root / WORKFLOW_DIR).glob("*.yml"))
    locations.extend(sorted((root / WORKFLOW_DIR).glob("*.yaml")))
    locations.extend(sorted((root / ".github/actions").glob("**/action.yml")))
    if not locations:
        raise AssertionError("No active native workflow or composite action was scanned")
    for file in locations:
        rel = file.relative_to(root).as_posix()
        count = 0
        writers = 0
        for line in file.read_text(encoding="utf-8").splitlines():
            # Comments are inert, but quote-wrapped action references are real.
            if line.lstrip().startswith("#"):
                continue
            match = USES.match(line)
            if match and OLD.fullmatch(match[1]):
                count += 1
            if WRITE_MODE.fullmatch(line):
                writers += 1
        if count:
            legacy[rel] = count
        if writers:
            write[rel] = writers
    return legacy, write


def enforce(legacy: dict[str, int], write: dict[str, int]) -> None:
    for file, observed in legacy.items():
        if observed > LEGACY_MAX.get(file, 0):
            raise AssertionError(
                f"Forbidden new Mono/NuGet cache action in {file}: "
                f"observed={observed}, ceiling={LEGACY_MAX.get(file, 0)}")
    for file, observed in write.items():
        if observed > LEGACY_WRITE_MAX.get(file, 0):
            raise AssertionError(
                f"Forbidden new native cache writer in {file}: "
                f"observed={observed}, ceiling={LEGACY_WRITE_MAX.get(file, 0)}")
    if sum(legacy.values()) > LEGACY_TOTAL_MAX:
        raise AssertionError("Legacy native cache call-site count increased")
    if sum(write.values()) > WRITER_TOTAL_MAX:
        raise AssertionError("Legacy native readwrite producer count increased")


class NativeCurlOnlyMigrationBudget(unittest.TestCase):
    def test_real_repository_cannot_grow_legacy_native_cache(self):
        legacy, writer = inspect(ROOT)
        enforce(legacy, writer)
        print(f"legacy_native_action_count={sum(legacy.values())} "
              f"legacy_readwrite_count={sum(writer.values())}", flush=True)

    def test_new_unlisted_legacy_workflow_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "Forbidden new Mono"):
            enforce({".github/workflows/new.yml": 1}, {})
        with self.assertRaisesRegex(AssertionError, "Forbidden new native cache writer"):
            enforce({}, {".github/workflows/new.yml": 1})

    def test_current_legacy_ceiling_cannot_expand(self):
        path = ".github/workflows/warm-cache.yml"
        with self.assertRaisesRegex(AssertionError, "Forbidden new Mono"):
            enforce({path: LEGACY_MAX[path] + 1}, {})
        with self.assertRaisesRegex(AssertionError, "Forbidden new native cache writer"):
            enforce({}, {path: LEGACY_WRITE_MAX[path] + 1})

    def test_lower_counts_are_allowed_for_incremental_migration(self):
        enforce({path: max(0, count - 1)
                 for path, count in LEGACY_MAX.items()},
                {path: max(0, count - 1)
                 for path, count in LEGACY_WRITE_MAX.items()})

    def test_composite_action_and_quoted_action_are_counted(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            action = root / ".github/actions/untrusted/action.yml"
            action.parent.mkdir(parents=True)
            action.write_text(
                'runs:\n  using: composite\n  steps:\n'
                '    - uses: "qigao/vcpkg-cache/.github/actions/setup-vcpkg-cache@master"\n')
            wf = root / ".github/workflows/new.yml"
            wf.parent.mkdir(parents=True)
            wf.write_text(
                'jobs:\n  test:\n    steps:\n'
                "      - uses: './.github/actions/setup-vcpkg-cache'\n"
                "        with:\n          mode: readwrite\n")
            legacy, writers = inspect(root)
            self.assertEqual(legacy[".github/actions/untrusted/action.yml"], 1)
            self.assertEqual(legacy[".github/workflows/new.yml"], 1)
            self.assertEqual(writers[".github/workflows/new.yml"], 1)
            with self.assertRaises(AssertionError):
                enforce(legacy, writers)


if __name__ == "__main__":
    unittest.main()
