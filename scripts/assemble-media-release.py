"""Combine qualified, product-scoped media ABI artifacts without rebuilding ports."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = os.environ["GITHUB_SHA"]
PRODUCT = os.environ["PRODUCT_REF"]
INFRA = os.environ["INFRA_REF"]
FOUNDATION = os.environ["BASE_CACHE_VERSION"]
TAG = os.environ["MEDIA_RELEASE_TAG"]
RUN = os.environ["GITHUB_RUN_ID"]
PROFILES = {
    "linux-x64": ("x64-linux", "x64-linux"),
    "linux-arm64": ("arm64-linux", "arm64-linux"),
    "macos-arm64": ("arm64-osx", "arm64-osx"),
    "windows-x64": ("qigao-x64-windows-llvm-mingw", "qigao-x64-windows-llvm-mingw"),
    "windows-arm64": ("qigao-arm64-windows-llvm-mingw", "qigao-arm64-windows-llvm-mingw"),
    "android-x64": ("x64-android", "x64-linux"),
    "android-arm64": ("arm64-android", "x64-linux"),
}
DIST = ROOT / "dist/media"
DIST.mkdir(parents=True)
recipe = None
contract = None
rows = []


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def stage(source, name, size, sha):
    if (source.name != name or source.stat().st_size != size
            or digest(source) != sha):
        raise ValueError(f"Media cache archive identity mismatch: {source}")
    if size >= 2 * 1024**3:
        raise ValueError(f"Release asset exceeds GitHub limit: {source}")
    target = DIST / name
    if target.exists():
        # An ABI may be shared by multiple host/target plans, but never
        # replace already staged bytes for the same immutable identity.
        if digest(target) != sha:
            raise ValueError(f"Conflicting bytes for one release asset: {name}")
    else:
        shutil.copyfile(source, target)


for profile, (triplet, host) in PROFILES.items():
    root = ROOT / "build/media-release-inputs" / f"media-abi-{profile}-{RUN}"
    index = json.loads((root / f"cache-{triplet}.json").read_text(encoding="utf-8-sig"))
    if (index["source_sha"], index["product_source"], index["infrastructure_source"],
        index["foundation_cache_version"], index["triplet"], index["host_triplet"]) != (
        SOURCE, PRODUCT, INFRA, FOUNDATION, triplet, host):
        raise ValueError(f"Producer provenance mismatch: {profile}")
    current_recipe = index["recipe"]
    if set(current_recipe) != {"manifest", "configuration", "overlays", "triplets"} or not all(
            re.fullmatch(r"[0-9a-f]{40}", x) for x in current_recipe.values()):
        raise ValueError(f"Invalid product recipe identity: {profile}")
    current_contract = {k: index[k] for k in ("cache_revision", "scripts_revision", "tool_revision")}
    if recipe is None:
        recipe, contract = current_recipe, current_contract
    elif recipe != current_recipe or contract != current_contract:
        raise ValueError(f"Mixed recipe or cache contract: {profile}")
    packages = index["packages"]
    if not packages:
        raise ValueError(f"Empty native dependency closure: {profile}")
    seen = set()
    for entry in packages:
        abi = entry["abi"]
        if abi in seen or not re.fullmatch(r"[0-9a-f]{64}", abi) or entry["asset"] != abi + ".zip":
            raise ValueError(f"Invalid ABI index: {profile}")
        seen.add(abi)
        # Keep per-platform ZIPs with the existing shared cache contract in
        # the producer artifact. Publish installed native closures separately:
        # different runners may ZIP equivalent ABI contents differently.
        path = root / entry["asset"]
        if path.stat().st_size != entry["size"] or digest(path) != entry["sha256"]:
            raise ValueError(f"Invalid ABI package archive: {path}")
    installed = index["installed"]
    name = f"installed-{triplet}.tar.xz"
    if installed["asset"] != name or installed["payload"] != "vcpkg_installed":
        raise ValueError(f"Invalid installed closure identity: {profile}")
    stage(root / name, name, installed["size"], installed["sha256"])
    # Publish the exact plan and ABI digests as evidence, not a second
    # default foundation index. The native consumer restores installed bytes.
    index_name = f"cache-{triplet}.json"
    shutil.copyfile(root / index_name, DIST / index_name)
    rows.append({
        "profile": profile, "triplet": triplet, "host_triplet": host,
        "installed": installed, "package_count": len(packages),
        "index": {"name": index_name, "sha256": digest(DIST / index_name),
                  "size": (DIST / index_name).stat().st_size},
    })

manifest = {
    "schema": 1, "repository": "qigao/vcpkg-cache", "tag": TAG,
    "source_sha": SOURCE, "product_source": PRODUCT, "recipe": recipe,
    "infrastructure_source": INFRA, "foundation_cache_version": FOUNDATION,
    "contract": contract, "ci": {"runId": RUN, "runAttempt": os.environ["GITHUB_RUN_ATTEMPT"]},
    "profiles": rows,
}
(DIST / "media-cache-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
with (DIST / "SHA256SUMS").open("w", encoding="utf-8") as output:
    for path in sorted(DIST.iterdir()):
        if path.name != "SHA256SUMS":
            print(f"{digest(path)}  {path.name}", file=output)
print(f"Qualified {len(rows)} media installed closures for {TAG}; product {PRODUCT}")
