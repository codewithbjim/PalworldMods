# Changelog

## 0.1.2

Input handling hotfix.

- Restore vertical preview movement on `Numpad 3/1`, constrained from 25 cm below to 650 cm above the initially frozen position. The upward range aligns with two standard wall levels.
- Update the in-game keyboard guide with the vertical movement controls.
- Ignore middle-mouse bindings unless Palworld has a live construction preview, preventing normal Pal attack commands from triggering preview discovery, opening build UI, or causing a gameplay stutter.
- Resolve the active preview directly from the local builder component instead of running a global preview-object scan when middle mouse is pressed.
- Remove the legacy `Alt+F6`, `Alt+F7`, `Alt+F8`, `Ctrl+Middle mouse`, and `Alt+Middle mouse` bindings. The runtime now registers only the controls shown by the in-game key guide.

## 0.1.1

Performance hotfix based on the initial cache patch supplied by Nexus community contributor DoubleGx0.

- Cache the local player's `BuilderComponent` instead of rediscovering it every 500 ms outside build mode.
- Return from direct player lookups before falling back to a global `PalPlayerCharacter` object scan.
- Queue frozen-preview safety checks on the game thread at 10 Hz, while idle key-guide checks now cross onto the game thread at only 2 Hz.
- Back off failed global player scans for approximately five seconds while continuing to retry inexpensive direct lookups.
- Disable verbose diagnostics by default to avoid unnecessary console and log traffic.
- Keep the unfinished gamepad guide hidden until controller actions have a supported runtime input path.

## 0.1.0

Initial Nexus release.

- Freeze a live construction preview and walk around it without losing its position.
- Move and rotate frozen pieces in precise, configurable increments.
- Reset a frozen piece to the transform it had when it was frozen.
- Copy the build piece under the cursor into the active preview.
- Camera-aware movement remains aligned to the piece's own axes.
- Native in-game keyboard and mouse key guide.
- Frozen/unfrozen notifications and live movement-step display.
