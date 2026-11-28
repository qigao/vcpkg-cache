# Media-specific ABI producer

Tracks #319 and qigao/turbomedia#280. The normal foundation SDK remains separate.
The workflow consumes TurboMedia's exact manifest and its own overlays directly
from an immutable product commit. It does not add FFmpeg to the default shared
manifest, copy the product recipes, or silently replace an existing SDK.

The compiler/tool/cache source is the published v0.1.9 infrastructure commit
`ec58174a83d92c8423feeb9d4aac05219bb03424`. The producer restores existing exact ABI archives from v0.1.9,
builds missing media ports only in this dedicated source producer, and stages
the shared publisher's ABI ZIPs and per-triplet digest index. Native Linux/macOS
use the runner's Clang, Windows uses LLVM-MinGW, and Android uses NDK.
The initial PR qualifies the complete Linux x64 media closure; manual workflow
dispatch can build all seven architecture profiles with the same product pin.

A successful producer run stages artifacts, not a new GitHub Release. Review
actual port results, verify all required profiles and combine only matching
ABI identities before publishing a separate immutable media supplement.
The downstream build must resolve the explicit media release and require
`--only-binarycaching`. It must never rebuild media ports on a cache miss.
Do not replace the existing foundation cache release or claim the full media
graph is qualified from one profile.

No remote package or release publication is triggered by this workflow.
