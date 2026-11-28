# Media-specific ABI producer

Tracks #319 and qigao/turbomedia#280. The foundation release stays separate.
The workflow uses TurboMedia's exact manifest and product overlays directly
from an immutable product commit, currently `dfb4541dceb758b84699ce3df47a111dfe9ad4ec`, with the
published v0.1.9 infrastructure. No recipes are copied into the default
foundation manifest. PR CI qualifies all seven native target/host profiles;
manual dispatch can select one profile for investigation.

Producer CI #2 completed Linux x64: 10 existing ABI hits and 13 missing
packages built, 23 staged ABI archives. The new matrix must qualify the
other six profiles as well. Each job stages canonical ABI ZIPs and the
preinstalled target/host closure. The assembly job verifies every ZIP,
installed archive, recipe Git object identity and shared infrastructure
contract; it publishes only a seven-profile installed-closure supplement,
per-profile ABI digest indexes and the manifest. Individual ABI ZIPs
remain in the producing workflow artifacts. No new release is created
by pull-request CI.

Once all seven profiles pass and the PR is merged, explicitly dispatch
the workflow on master with `platform=all`, the exact product recipe commit
and `publish_release=true` to publish `turbomedia-media-v0.1.9-1`.
That supplement is not the ordinary foundation release or a new Salts SDK
version. Do not replace its tag/assets; new recipe bytes require a new
supplement identity. Normal TurboMedia builds restore the checksum-qualified
installed closure, never compile third-party ports. Source builds belong
only to this producer. Native product CI remains a separate required gate.
