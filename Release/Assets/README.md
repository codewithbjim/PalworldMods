# Perfect Placement release assets

`PerfectPlacement.pak` is the exact companion Logic Mod packaged with this release line. It is stored here as a normal tracked release input so an annotated release tag can reproduce the shipped Nexus and Workshop payloads.

`PerfectPlacement.pak.sha256` pins the expected binary. Both package builders and the release gate reject a different PAK.

Rebuild and replace this file only when the companion Blueprint changes. Update the checksum in the same release commit.
