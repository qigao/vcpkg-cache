#!/usr/bin/env python3
"""Restore one SHA-256 locked native package/tool locally or in GitHub Actions.

Transport and extraction belong to the existing shared helpers. Product repos
select exact versions, host/target payloads, required files and SDK validation.
"""
from __future__ import annotations

import argparse
from contextlib import redirect_stdout
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from urllib.parse import urlsplit


def load_helper(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


packages = load_helper("native_dependency_packages", "github-packages.py")
archives = load_helper("native_dependency_archives", "setup-compiler-toolchain.py")


def normalized(path):
    """Also accepts PureWindowsPath for platform-independent output regression tests."""
    value = path.as_posix()
    if any(ord(c) < 32 for c in value):
        raise ValueError("control character in exported path")
    return value


def relative(value, allow_root=False):
    if allow_root and value == ".":
        return ()
    return archives.safe_path(value)


def contained(root, value):
    path = root.joinpath(*relative(value, allow_root=True))
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"payload path escapes selected root: {value}")
    return path


def validate_request(args):
    if args.kind == "locked":
        lock = json.loads(Path(args.lock_file).read_text(encoding="utf-8"))
        if not isinstance(lock, dict) or lock.get("schema") != 1 or not isinstance(lock.get("source"), dict):
            raise ValueError("unsupported native dependency lock")
        source = lock["source"]
        if args.sha256 and args.sha256.lower() != str(lock.get("sha256", "")).lower():
            raise ValueError("SHA-256 override differs from dependency lock")
        args.sha256 = lock.get("sha256", "")
        args.kind = source.get("kind")
        if args.kind == "package" and source.get("feed") == "https://nuget.pkg.github.com/qigao/index.json":
            args.package_id, args.version = source.get("id", ""), source.get("version", "")
        elif args.kind == "url":
            args.url = source.get("url", "")
        else:
            raise ValueError("unsupported locked source/feed")
    if not isinstance(args.sha256, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", args.sha256):
        raise ValueError("an exact SHA-256 (64 hexadecimal digits) is required")
    args.sha256 = args.sha256.lower()
    relative(args.payload, allow_root=True)
    for value in args.require + args.add_path + args.executable:
        relative(value, allow_root=True)
    if args.env_prefix and not re.fullmatch(r"[A-Z][A-Z0-9_]*", args.env_prefix):
        raise ValueError("env-prefix must be an uppercase environment variable prefix")
    if args.kind == "package":
        if not isinstance(args.package_id, str) or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", args.package_id):
            raise ValueError("invalid package ID")
        if not isinstance(args.version, str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?", args.version):
            raise ValueError("an exact NuGet package version is required; no floating/latest")
    else:
        if not isinstance(args.url, str):
            raise ValueError("invalid locked tool URL")
        parsed = urlsplit(args.url)
        if parsed.query or parsed.fragment:
            raise ValueError("tool URL must not contain a query or fragment")
        name = parsed.path.lower()
        if not name.endswith((".zip", ".tar.xz")):
            raise ValueError("tool URL must select a .zip or .tar.xz archive")
        if not archives._download_url_allowed(args.url, ("github.com", "raw.githubusercontent.com")):
            raise ValueError("tool URL must use HTTPS on github.com or raw.githubusercontent.com")
    for key, needed in (("GITHUB_OUTPUT", args.github_output),
                        ("GITHUB_ENV", bool(args.env_prefix)),
                        ("GITHUB_PATH", bool(args.add_path))):
        if needed and not os.environ.get(key):
            raise ValueError(f"{key} is required for the requested Actions exports")


def source_descriptor(args):
    if args.kind == "package":
        return {"kind": "package", "feed": "https://nuget.pkg.github.com/qigao/index.json",
                "id": args.package_id, "version": args.version}
    return {"kind": "url", "url": args.url}


def validate_payload(root, args):
    if not root.is_dir():
        raise ValueError(f"missing selected payload directory: {args.payload}")
    for value in args.require + args.executable:
        required = contained(root, value)
        if not required.is_file() or required.stat().st_size == 0:
            raise ValueError(f"missing or empty required payload file: {value}")
    for value in args.executable:
        executable = contained(root, value)
        executable.chmod(executable.stat().st_mode | 0o111)
    for value in args.add_path:
        if not contained(root, value).is_dir():
            raise ValueError(f"missing PATH directory: {value}")


def reuse_installation(destination, args):
    receipt_path = destination / "receipt.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    payload = destination / "payload"
    if payload.is_symlink() or not payload.is_dir():
        raise ValueError("existing payload must be a real installation directory")
    root = contained(payload, args.payload)
    expected = {"schema": 1, "source": source_descriptor(args), "sha256": args.sha256,
                "payload": args.payload, "root": normalized(root), "receipt": normalized(receipt_path),
                "required_files": args.require, "executables": args.executable,
                "path": [normalized(contained(root, p)) for p in args.add_path]}
    if receipt != expected:
        raise ValueError("existing installation does not match lock/payload/options; choose a fresh destination")
    validate_payload(root, args)
    return receipt


def restore(args, *, feed=None, download=None):
    validate_request(args)
    # Refuse the caller's symlink before resolve(), including dangling symlinks.
    requested = Path(args.destination).expanduser().absolute()
    if args.reuse and requested.is_dir() and not requested.is_symlink():
        receipt = reuse_installation(requested.resolve(), args)
        export_receipt(args, receipt)
        return receipt
    if requested.exists() or requested.is_symlink():
        raise ValueError("destination must be fresh; existing installations are never replaced")
    destination = requested.resolve()
    normalized(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".native-dependency-", dir=destination.parent) as temporary:
        stage = Path(temporary)
        if args.kind == "package":
            archive = stage / "source.nupkg"
            if feed is None:
                feed = packages.NugetFeed(packages.Curl())
            # Hash verification happens in the transport helper BEFORE opening the ZIP.
            with redirect_stdout(sys.stderr):
                feed.package(args.package_id, args.version, archive, expected_sha256=args.sha256)
        else:
            suffix = ".tar.xz" if urlsplit(args.url).path.lower().endswith(".tar.xz") else ".zip"
            archive = stage / ("source" + suffix)
            (download or archives.verified_download)(args.url, archive, args.sha256,
                                                    limit=archives.MAX_ARCHIVE)
        # Independently enforce the lock even for a substituted transport.
        if packages.sha256(archive) != args.sha256:
            raise ValueError("dependency SHA-256 mismatch")
        tree = stage / "installed"
        payload = tree / "payload"
        archives.safe_extract(archive, payload)
        root = contained(payload, args.payload)
        validate_payload(root, args)
        installed_root = destination / root.relative_to(tree)
        receipt_path = destination / "receipt.json"
        receipt = {"schema": 1, "source": source_descriptor(args), "sha256": args.sha256,
                   "payload": args.payload, "root": normalized(installed_root),
                   "receipt": normalized(receipt_path), "required_files": args.require,
                   "executables": args.executable,
                   "path": [normalized(installed_root.joinpath(*relative(p, allow_root=True)))
                            for p in args.add_path]}
        (tree / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        # Publish only a completely verified installation, on the same filesystem.
        if destination.exists() or destination.is_symlink():
            raise ValueError("destination appeared during restore")
        tree.rename(destination)
    export_receipt(args, receipt)
    return receipt


def export_receipt(args, receipt):
    if args.github_output:
        append_lines("GITHUB_OUTPUT", [f"{key}={receipt[key]}" for key in ("root", "receipt", "sha256")])
    if args.env_prefix:
        append_lines("GITHUB_ENV", [f"{args.env_prefix}_ROOT={receipt['root']}",
                                  f"{args.env_prefix}_SHA256={args.sha256}",
                                  f"{args.env_prefix}_RECEIPT={receipt['receipt']}"])
    if args.add_path:
        append_lines("GITHUB_PATH", receipt["path"])


def resolve_package(args, *, feed=None):
    """An explicit update operation: download once and write an exact version/hash lock.

    The computed digest pins the selected bytes for later restores. It is not
    an independently signed or publisher-provided attestation.
    """
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", args.package_id):
        raise ValueError("invalid package ID")
    if args.version != "latest" and not re.fullmatch(r"\d+\.\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?", args.version):
        raise ValueError("resolve requires an exact version or the explicit literal latest")
    feed = feed or packages.NugetFeed(packages.Curl())
    version = feed.latest_stable(args.package_id) if args.version == "latest" else args.version
    output = Path(args.output_lock).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".native-lock-", dir=output.parent) as temporary:
        archive = Path(temporary) / "source.nupkg"
        with redirect_stdout(sys.stderr):
            feed.package(args.package_id, version, archive)
        lock = {"schema": 1, "source": {"kind": "package",
                "feed": "https://nuget.pkg.github.com/qigao/index.json",
                "id": args.package_id, "version": version}, "sha256": packages.sha256(archive)}
        staged = Path(temporary) / "lock.json"
        staged.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
        staged.replace(output)
    return lock


def append_lines(key, lines):
    with Path(os.environ[key]).open("a", encoding="utf-8", newline="\n") as output:
        output.write("\n".join(lines) + "\n")


def parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--destination", required=True)
    common.add_argument("--sha256", default="", help="required for package/url; read from lock for locked")
    common.add_argument("--reuse", action="store_true", help="reuse a local installation only when its receipt and required files match")
    common.add_argument("--payload", default=".", help="relative payload directory; explicit host/target selection")
    common.add_argument("--require", action="append", default=[], help="nonempty file relative to selected payload; repeatable")
    common.add_argument("--executable", action="append", default=[], help="required file to grant execute bits; never executed by setup")
    common.add_argument("--add-path", action="append", default=[], help="payload directory to append to GITHUB_PATH; repeatable")
    common.add_argument("--env-prefix", default="", help="export PREFIX_ROOT/SHA256/RECEIPT to GITHUB_ENV")
    common.add_argument("--github-output", action="store_true", help="export root/receipt/sha256 to GITHUB_OUTPUT")
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="kind", required=True)
    package = sub.add_parser("package", parents=[common], help="qigao GitHub Packages nupkg; requires GH_TOKEN")
    package.add_argument("package_id")
    package.add_argument("version")
    url = sub.add_parser("url", parents=[common], help="public GitHub .zip/.tar.xz; no token")
    url.add_argument("url")
    locked = sub.add_parser("locked", parents=[common], help="restore an exact source/version/hash from a JSON lock")
    locked.add_argument("lock_file")
    resolve = sub.add_parser("resolve", help="explicitly resolve an SDK/tool package version and write a lock; not a vcpkg ABI resolver")
    resolve.add_argument("package_id")
    resolve.add_argument("--version", required=True, help="exact package version or explicit latest stable selection")
    resolve.add_argument("--output-lock", required=True)
    return result


def main():
    try:
        args = parser().parse_args()
        print(json.dumps(resolve_package(args) if args.kind == "resolve" else restore(args), indent=2))
        return 0
    except (ValueError, OSError) as exc:
        print(f"native dependency restore failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
