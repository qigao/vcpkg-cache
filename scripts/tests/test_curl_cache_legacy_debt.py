"""Reject legacy native cache callers and Mono commands in active CI."""
from __future__ import annotations

from pathlib import Path
import re
import shlex
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_DIR = ".github/workflows"
USES = re.compile(r'^\s*(?:-\s*)?uses:\s*["\x27]?([^\s"#\x27]+)', re.I)
OLD = re.compile(
    r'^(?:\./\.github/actions/setup-vcpkg-cache|'
    r'qigao/vcpkg-cache/\.github/actions/setup-vcpkg-cache@[^\s]+)$',
    re.I,
)
WRITE_MODE = re.compile(r'^\s*mode:\s*["\x27]?readwrite["\x27]?\s*(?:#.*)?$', re.I)
RUN = re.compile(r'^(\s*)(?:-\s*)?run:\s*(.*)$')
MONO_PACKAGE = re.compile(r'mono(?:[-@][\w.+-]+)?', re.I)
PACKAGE_MANAGERS = {'apt-get', 'apt', 'brew', 'choco', 'yum', 'dnf',
                    'apk', 'pacman', 'port', 'pkg', 'winget'}
SEPARATOR = re.compile(r'[;&|()\n]+')


def workflow_files(root: Path) -> list[Path]:
    locations = []
    for extension in ("yml", "yaml"):
        locations.extend((root / WORKFLOW_DIR).glob(f"*.{extension}"))
        locations.extend((root / ".github/actions").glob(f"**/action.{extension}"))
    if not locations:
        raise AssertionError("No active native workflow or composite action was scanned")
    return sorted(locations)


def run_commands(contents: str) -> list[str]:
    """Read inline and indented YAML run commands without treating comments as code."""
    commands = []
    lines = contents.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        index += 1
        match = RUN.match(line)
        if not match:
            continue
        command = match[2].strip()
        if command and command[0] in "|>":
            parts = []
            indent = len(match[1])
            while index < len(lines):
                following = lines[index]
                if following.strip() and len(following) - len(following.lstrip()) <= indent:
                    break
                index += 1
                if not following.lstrip().startswith("#"):
                    parts.append(following.strip())
            command = (" " if command[0] == ">" else "\n").join(parts)
        elif command[:1] in ('"', "'") and command[-1:] == command[:1]:
            command = command[1:-1]
        # Shell and PowerShell continuations are one command for policy purposes.
        command = re.sub(r"(?:\\|" + chr(96) + r")\s*\n\s*", " ", command)
        commands.append(command)
    return commands


def invokes_or_installs_mono(command: str) -> bool:
    # Shell-style tokenization preserves quoted grep patterns and echo text as
    # data, and recognizes comments only outside quotes. It also handles quoted
    # PowerShell executable paths, including paths containing spaces.
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    tokens = list(lexer)
    at_command = True
    for index, token in enumerate(tokens):
        if SEPARATOR.fullmatch(token):
            at_command = True
            continue
        if not at_command:
            continue
        if token in {"sudo", "env", "command", "exec", "if", "then", "else", "do"}:
            continue
        if token.startswith("-") or re.match(r"[A-Za-z_][A-Za-z_0-9]*=", token):
            continue
        at_command = False
        executable = token.replace("\\", "/").rsplit("/", 1)[-1].lower()
        if executable in {"mono", "mono.exe"}:
            return True
        if executable not in PACKAGE_MANAGERS:
            continue
        arguments = []
        for argument in tokens[index + 1:]:
            if SEPARATOR.fullmatch(argument):
                break
            arguments.append(argument)
        if any(arg in {"install", "add", "-S"} for arg in arguments) and any(
                MONO_PACKAGE.fullmatch(arg) for arg in arguments):
            return True
    return False


def inspect(root: Path) -> tuple[dict[str, int], dict[str, int]]:
    legacy = {}
    write = {}
    for file in workflow_files(root):
        rel = file.relative_to(root).as_posix()
        contents = file.read_text(encoding="utf-8")
        count = 0
        writers = 0
        for line in contents.splitlines():
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
        for command in run_commands(contents):
            if invokes_or_installs_mono(command):
                raise AssertionError(
                    f"Forbidden Mono installation or execution in {rel}: {command}")
    return legacy, write


def enforce(legacy: dict[str, int], write: dict[str, int]) -> None:
    if any(legacy.values()):
        raise AssertionError(f"Forbidden Mono/NuGet cache action: {legacy}")
    if any(write.values()):
        raise AssertionError(f"Forbidden native cache writer: {write}")


class NativeCurlOnlyPolicy(unittest.TestCase):
    def test_real_repository_has_no_legacy_native_cache_or_mono_commands(self):
        legacy, writer = inspect(ROOT)
        enforce(legacy, writer)
        self.assertFalse((ROOT / ".github/actions/setup-vcpkg-cache/action.yml").exists())
        print(f"legacy_native_action_count={sum(legacy.values())} "
              f"legacy_readwrite_count={sum(writer.values())}", flush=True)

    def test_no_workflow_gets_a_legacy_allowance(self):
        for path in (".github/workflows/new.yml",
                     ".github/workflows/gmssl-x509-candidate.yml"):
            with self.subTest(path=path):
                with self.assertRaisesRegex(AssertionError, "Forbidden Mono"):
                    enforce({path: 1}, {})
                with self.assertRaisesRegex(AssertionError, "Forbidden native cache writer"):
                    enforce({}, {path: 1})
        enforce({}, {})

    def test_composite_action_and_quoted_action_are_counted(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            action = root / ".github/actions/untrusted/action.yaml"
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
            self.assertEqual(legacy[".github/actions/untrusted/action.yaml"], 1)
            self.assertEqual(legacy[".github/workflows/new.yml"], 1)
            self.assertEqual(writers[".github/workflows/new.yml"], 1)
            with self.assertRaises(AssertionError):
                enforce(legacy, writers)

    def test_mono_installation_and_execution_are_rejected(self):
        commands = (
            "sudo apt-get install -y mono-runtime",
            "apt install mono-complete",
            "brew install mono",
            "choco install mono --yes",
            "dnf install -y mono-core",
            "apk add mono",
            "pacman -S mono",
            "mono nuget.exe restore packages.config",
            "sudo mono /tmp/nuget.exe sources list",
            "/usr/bin/mono --version",
            '& "C:\\tools\\mono.exe" nuget.exe',
            '& "C:\\Program Files\\Mono\\bin\\mono.exe" nuget.exe',
            "echo ready && mono nuget.exe",
            "echo '#ready'; mono nuget.exe",
            "if ready; then mono nuget.exe; fi",
            "sudo apt-get install -y " + "\\\n" + "            mono-runtime",
        )
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            wf = root / ".github/workflows/mono.yml"
            wf.parent.mkdir(parents=True)
            for command in commands:
                with self.subTest(command=command):
                    wf.write_text("steps:\n  - run: |\n      " + command + "\n")
                    with self.assertRaisesRegex(AssertionError, "Forbidden Mono"):
                        inspect(root)
            wf.write_text('steps:\n  - run: "brew install mono"\n')
            with self.assertRaisesRegex(AssertionError, "Forbidden Mono"):
                inspect(root)
            wf.write_text('steps:\n  - run: >\n      sudo apt-get install -y\n      mono-runtime\n')
            with self.assertRaisesRegex(AssertionError, "Forbidden Mono"):
                inspect(root)

    def test_comments_and_descriptions_are_not_commands(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            wf = root / ".github/workflows/curl.yml"
            wf.parent.mkdir(parents=True)
            wf.write_text(
                "# - uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-cache@old\n"
                "steps:\n  - name: Never run mono nuget.exe or brew install mono\n"
                "    run: |\n"
                "      # sudo apt-get install mono-runtime\n"
                "      echo 'Mono is forbidden'\n"
                "      echo 'brew install mono is forbidden'\n"
                "      test \"$(grep -Ec 'mono-complete|brew install mono|dotnet restore' action.yml || true)\" -eq 0\n"
                "      curl -fsSL https://example.test/package -o package # mono is forbidden\n")
            self.assertEqual(inspect(root), ({}, {}))


if __name__ == "__main__":
    unittest.main()
