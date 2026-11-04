"""Fetch missing Ubuntu PulseAudio runtime packages with curl, without installing a service."""
import ctypes
import hashlib
import os
from pathlib import Path
import shlex
import subprocess

root = Path("build-pulse/runtime").resolve()
root.mkdir(parents=True, exist_ok=True)
plan = subprocess.check_output(["apt-get", "--print-uris", "--yes", "--download-only", "install", "libpulse0"], text=True)
print(plan, flush=True)
for line in plan.splitlines():
    if not line.startswith("'"):
        continue
    url, filename, size, digest = shlex.split(line)
    target = root / filename
    subprocess.run(["curl", "--fail", "--location", url, "-o", str(target)], check=True)
    algorithm, expected = digest.split(":", 1)
    algorithm = {"MD5Sum": "md5"}.get(algorithm, algorithm.lower())
    payload = target.read_bytes()
    if len(payload) != int(size) or hashlib.new(algorithm, payload).hexdigest() != expected:
        raise RuntimeError("Ubuntu package identity mismatch: " + filename)
    subprocess.run(["dpkg-deb", "--extract", str(target), str(root)], check=True)
paths = [root / "usr/lib/x86_64-linux-gnu", root / "usr/lib/x86_64-linux-gnu/pulseaudio",
         root / "lib/x86_64-linux-gnu"]
value = ":".join(map(str, paths))
with open(os.environ["GITHUB_ENV"], "a") as output:
    output.write("LD_LIBRARY_PATH=" + value + "\n")
subprocess.run(["python3", "-c", "import ctypes; ctypes.CDLL('libpulse.so.0'); print('real libpulse load succeeded')"],
               env=dict(os.environ, LD_LIBRARY_PATH=value), check=True)
