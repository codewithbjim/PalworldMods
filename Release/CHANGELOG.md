# Changelog

## 0.2.0-beta.1

Major update: experimental gamepad support.

- Add experimental gamepad controls for freezing, copying, moving, rotating, changing the movement step, resetting, and unfreezing a construction preview.
- Add configurable gamepad chords in `Scripts/config.lua`, including D-pad directions combined with `LT`, `RT`, or both triggers.
- Add dedicated unfrozen and frozen controller guides built from reusable gamepad-chord widgets.
- Resolve controller icons from Palworld's stock keyguide textures at runtime.
- Keep unfrozen controller input limited to `L3` and `L3 + D-pad Down` so normal Palworld building controls remain available.
- Expand DarnMenu support to Freeze, Copy, and all eleven adjustment bindings.
- Capture left, right, middle, and side mouse buttons through DarnMenu and render complete chords with Palworld's stock keyguide textures.
- Add `Ctrl`, `Alt`, and `Shift` keycap toggles to every DarnMenu binding, including Copy's default `Shift + Middle mouse` chord.
- Load saved DarnMenu bindings and restore their placement-control keycaps after restarting Palworld.
- Automatically release a frozen preview before menus and other unrelated Palworld UI actions take over.
- Hide the placement guide as construction UI closes and restore it when an active preview resumes.
- Replace steady-state unfrozen lifecycle polling with bounded, event-driven recovery checks.
- Retain asynchronous UE4SS callbacks and contain callback errors so a transient UI failure does not permanently stop placement-guide updates.
- Avoid a UE4SS native crash during world transitions by skipping the companion guide's redundant initial hide and re-resolving deferred widget hosts instead of retaining stale object wrappers.

Experimental testing notice:

- Gamepad support has not been tested on physical controller hardware by the author and requires community testing.
- When reporting controller issues, include the controller model, whether Steam Input is enabled, the configured chord, reproduction steps, and the relevant UE4SS log section.

Known DarnMenu limitation:

- DarnMenu supports `Ctrl`, `Alt`, and `Shift` modifier toggles, but primary-input capture does not include arrows, Space, Enter, Tab, Escape, Backspace, punctuation keys, or mouse-wheel scrolling.

## 0.1.5

- Add Mod Config Menu support for configurable placement-control key chords.
- Render configured controls with Palworld's stock keyboard and mouse keycaps.
- Support any combination of Ctrl, Alt, and Shift modifiers for every action.
- Reload saved bindings and recover the placement-control UI after reopening a world.
- Read the UTF-16LE configuration files written by Mod Config Menu.
- Ignore movement-step key input when no frozen build preview is active.
- Standardize player-facing terminology on Freeze and Unfreeze.

Known issue:

- Mod Config Menu currently does not map or show symbol keys and mouse bindings correctly. Use letter, number, function, navigation, or numpad keys in MCM until that upstream issue is fixed.

Compatibility note:

- Perfect Placement bindings may become intermittent when the same chord is registered by another mod or by UE4SS's built-in `Keybinds` mod. Check all UE4SS and mod keybinds for conflicts, then remap one of the overlapping actions.

## 0.1.4

- Allow middle-click to freeze or release a preview while Palworld's Ctrl or Alt build modifier is held.

## 0.1.3

- Fix the Workshop `LogicMods` install rule so `PerfectPlacement.pak` is copied directly to `Pal/Content/Paks/LogicMods` instead of a nested `LogicMods/LogicMods` directory.
- Make Numpad 1/3 vertical movement work when NumLock is either on or off.
- Clean stale `Scripts` and `LogicMods` payload directories when rebuilding a Workshop package while preserving its uploader metadata.

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
