# Perfect Placement release assets

`PerfectPlacement_NativeUI_P.pak` is the consolidated resource pak that inserts the empty `VerticalBox_PP` scaffold into Palworld's cooked `WBP_IngameConstruction` widget and carries the cooked, event-driven controller bridge formerly shipped as a separate LogicMod pak.

`PerfectPlacement_NativeUI_P.pak.sha256` pins the expected binary. Both package builders and the release gate reject a different pak.

The former `PerfectPlacement.pak` LogicMod and its checksum were retired for 0.3.0-alpha.1. Published 0.2.x tags retain their exact historical release inputs.

Rebuild and replace either pak only when its corresponding Blueprint or native scaffold changes. Update the checksum in the same release commit.
