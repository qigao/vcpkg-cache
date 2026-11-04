"""Real libpulse failure lifecycle comparison; no fake provider or sanitizer suppression."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import socket
import threading
import time

original, patched, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
source = Path(__file__).with_name("pulse_init.c")
expected = {
    "original": "9019743287e443c55e5737a7297f38e5e358561701d6db2d905afb114390c410",
    "patched": "6fc8a4c2b37da54e520ff5045db1eb85451b57d55d4e7d7a765f704dc0dd9458",
}
for label, directory in [("original", original), ("patched", patched)]:
    digest = hashlib.sha256((directory / "miniaudio.h").read_bytes()).hexdigest()
    if digest != expected[label]:
        raise RuntimeError(f"{label}: unexpected header {digest}")
    binary = output.resolve() / label
    subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-D_GNU_SOURCE", "-O1", "-g",
                    "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                    "-I" + str(directory.resolve()), str(source.resolve()),
                    "-ldl", "-lm", "-lpthread", "-o", str(binary)], check=True)
    for scenario in ["invalid-address", "absent-server", "peer-close"]:
        env = dict(os.environ, ASAN_OPTIONS="detect_leaks=1:halt_on_error=1:abort_on_error=0",
                   UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1", LSAN_OPTIONS="exitcode=23")
        command = [str(binary), scenario]
        if scenario == "peer-close":
            address = output.resolve() / "peer.sock"
            listener = socket.socket(socket.AF_UNIX)
            listener.bind(str(address))
            listener.listen(32)
            listener.settimeout(60)
            accepted = []
            def close_peers():
                for _ in range(32):
                    peer, _ = listener.accept()
                    with peer:
                        time.sleep(0.01)
                    accepted.append(1)
            worker = threading.Thread(target=close_peers)
            worker.start()
            command.append("unix:" + str(address))
        result = subprocess.run(command, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        if scenario == "peer-close":
            worker.join(timeout=65)
            listener.close()
            address.unlink()
            if worker.is_alive() or len(accepted) != 32:
                raise RuntimeError("Real Unix peer lifecycle did not complete")
        (output / f"{label}-{scenario}.log").write_text(result.stdout)
        print(f"{label} {scenario}: exit={result.returncode}", flush=True)
        print(result.stdout, flush=True)
        counts = "connect_failures=32 wait_failures=0" if scenario != "peer-close" else "connect_failures=0 wait_failures=32"
        marker = f"scenario={scenario} iterations=32 result=-203 {counts}"
        if marker not in result.stdout:
            raise RuntimeError("Lifecycle/error/branch assertions did not finish")
        if label == "original":
            if result.returncode != 23 or "SUMMARY: AddressSanitizer:" not in result.stdout or "leaked in" not in result.stdout:
                raise RuntimeError("Expected real baseline leak was not reproduced")
        elif result.returncode != 0 or "Sanitizer" in result.stdout:
            raise RuntimeError("Patched provider failed sanitizer qualification")
