#!/usr/bin/env python3
"""Validate each embedded bash block in the GmSSL Crypto handoff workflow.

A lost '$' anchor/closing quote inside a workflow can make a GitHub Actions
run fail during YAML parsing, before any test job exists. This independent
guard is also executed by the pre-existing GmSSL registry workflow.
"""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys


def extract_run_blocks(contents: str) -> list[tuple[int, str]]:
    lines = contents.splitlines()
    blocks = []
    i = 0
    while i < len(lines):
        match = re.fullmatch(r"(\s*)run:\s*\|[-+]?\s*", lines[i])
        if not match:
            i += 1
            continue
        start = i + 1
        base = len(match.group(1))
        body = []
        i += 1
        while i < len(lines):
            line = lines[i]
            indent = len(line) - len(line.lstrip(" "))
            if line.strip() and indent <= base:
                break
            body.append(line[base + 2:] if len(line) >= base + 2 else "")
            i += 1
        blocks.append((start, "\n".join(body) + "\n"))
    return blocks


def validate(contents: str) -> list[str]:
    issues = []
    if contents.count("uses: actions/upload-artifact@v4") != 1:
        issues.append("handoff must have exactly one final artifact upload step")
    if contents.count("python3 tools/verify_gmssl_crypto_handoff.py") != 3:
        issues.append("source verifier must run once standalone and twice for deterministic export")
    if "ports/gmssl/**" not in contents:
        issues.append("port source changes must trigger the handoff provenance gate")
    if not re.search(
        r"(?m)^\s*if grep -Eq '.*\)\$' \".*archive-files[.]txt\"; then\s*$",
        contents,
    ):
        issues.append("complete-filelist packaging exclusion gate missing")
    blocks = extract_run_blocks(contents)
    if len(blocks) != 2:
        issues.append(f"expected two real shell qualification blocks; got {len(blocks)}")
    for line, script in blocks:
        process = subprocess.run(
            ["bash", "-n"], input=script, text=True,
            capture_output=True, check=False,
        )
        if process.returncode:
            issues.append(
                f"run block at line {line} invalid bash: {process.stderr.strip()}"
            )
    return issues


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    path = root / ".github/workflows/gmssl-crypto-handoff.yml"
    issues = validate(path.read_text(encoding="utf-8"))
    for issue in issues:
        print("GmSSL handoff CI syntax: FAIL:", issue, file=sys.stderr)
    if not issues:
        print("GmSSL handoff CI syntax: PASS (two executed Bash stages)")
    return int(bool(issues))


if __name__ == "__main__":
    raise SystemExit(main())
