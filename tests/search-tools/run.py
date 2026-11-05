"""Build the candidate port and test the packaged executable, without consumers."""
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[2]
build = repo / 'build-search-tools'
manifest = build / 'manifest'
manifest.mkdir(parents=True, exist_ok=True)
baseline = json.loads((repo / 'vcpkg.json').read_text())['builtin-baseline']
(manifest / 'vcpkg.json').write_text(json.dumps({
    'name': 'ugrep-native-protocol', 'version-string': '1',
    'builtin-baseline': baseline, 'dependencies': ['ugrep']}) + '\n')
triplet = os.environ['TOOL_TRIPLET']
installed = build / 'installed'
vcpkg = Path(os.environ['VCPKG_ROOT']) / ('vcpkg.exe' if os.name == 'nt' else 'vcpkg')
subprocess.run([str(vcpkg), 'install', f'--x-manifest-root={manifest}',
                f'--x-install-root={installed}', f'--triplet={triplet}',
                f'--host-triplet={triplet}', f'--overlay-ports={repo / "ports"}',
                f'--overlay-triplets={repo / "triplets"}'], check=True,
               env={**os.environ, 'VCPKG_BINARY_SOURCES': 'clear'})
prefix = installed / triplet
tool = prefix / 'tools/ugrep' / ('ugrep.exe' if os.name == 'nt' else 'ugrep')
subprocess.run([sys.executable, str(repo / 'tests/search-tools/protocol.py'), str(tool)],
               cwd=build, check=True)
if os.name == 'nt':
    # Static MinGW and PCRE2: only OS imports may remain. An absent dump tool
    # fails the qualification; there is no alternate inspection backend.
    dump = subprocess.check_output(['llvm-objdump', '-p', str(tool)], text=True)
    for line in dump.splitlines():
        if 'DLL Name:' in line:
            name = line.split('DLL Name:', 1)[1].strip().lower()
            assert name in {'kernel32.dll', 'msvcrt.dll', 'ucrtbase.dll', 'ws2_32.dll',
                            'advapi32.dll', 'user32.dll', 'shell32.dll'} or name.startswith('api-ms-win-'), name
elif sys.platform == 'darwin':
    dump = subprocess.check_output(['otool', '-L', str(tool)], text=True)
    for line in dump.splitlines()[1:]:
        assert line.strip().startswith(('/usr/lib/', '/System/Library/')), line
else:
    dump = subprocess.check_output(['ldd', str(tool)], text=True)
    assert 'pcre2' not in dump.lower(), dump
print(dump)
