"""Extract the SHA-512-pinned upstream CLI gzip without a shell runtime."""
import gzip
from pathlib import Path
import sys

archive, output = map(Path, sys.argv[1:])
with gzip.open(archive, "rb") as stream:
    content = stream.read(128 * 1024 * 1024 + 1)
    if not content or len(content) > 128 * 1024 * 1024:
        raise ValueError("invalid tree-sitter CLI size")
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(content)
