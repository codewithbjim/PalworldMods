# Perfect Placement native construction guide

`Build-Scaffold.ps1` uses UAssetGUI and the Palworld mappings to add an empty `VerticalBox_PP` to Palworld's cooked `WBP_IngameConstruction` widget. The slot is inserted immediately before the stock construction footer.

`Build-Pak.ps1` packages the generated `.uasset` and `.uexp` together with the cooked, event-driven controller bridge as `PerfectPlacement_NativeUI_P.pak` and writes its SHA-256 sidecar. At runtime the Lua mod populates only its owned container, builds keyboard and gamepad variants once, and switches variants by visibility after Palworld refreshes `SetupKeyGuide`.

The regular `_P.pak` replaces the former separate LogicMods payload. Lua safely reuses or spawns its cooked `ModActor` after each map load; the actor supplies physical controller events that UE4SS Lua cannot otherwise receive reliably.

The runtime detaches Palworld's Rotate, Axis Alignment, and Replacement Mode rows only while a preview is frozen. Widget construction and row detachment are deferred outside Palworld's setup callback, guarded to the current construction-widget generation, and restored on unfreeze.
