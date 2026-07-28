# Perfect Placement

Perfect Placement is a Palworld 1.0 UE4SS Lua mod prototype. It is designed to freeze a building preview in world space, leave the player free to walk around, and provide precise camera-relative transform controls before final placement.

## Current status

The mod resolves the active placement preview directly through the local player's builder component. Its controls can freeze, move, rotate, reset, copy, and release that preview. Final placement remains under Palworld's control.

## Installation for development

1. Install a Palworld 1.0-compatible UE4SS build and verify that its console opens correctly.
2. Copy this `PerfectPlacement` directory into the UE4SS `Mods` directory.
3. If your UE4SS installation still uses `mods.txt`, add:

   ```text
   PerfectPlacement : 1
   ```

4. Start a disposable test world. Do not develop against your only save.
5. Enter build mode and make a building preview visible.
6. Middle-click to freeze or unfreeze the selected preview.

## Controls and configuration

Controls only change the preview while it is frozen. Player movement remains on Palworld's normal controls. The table below shows the defaults.

| Action | Normal | Fine | Coarse |
| --- | --- | --- | --- |
| Move left/right | `Numpad 4/6` | Use `Numpad -`, then move | Use `Numpad +`, then move |
| Move forward/back | `Numpad 8/2` | Use `Numpad -`, then move | Use `Numpad +`, then move |
| Move up/down | `Numpad 3/1` | Use `Numpad -`, then move | Use `Numpad +`, then move |
| Rotate yaw | `Numpad 7/9` | Configure rotation step | Configure rotation step |
| Reset to frozen transform | `Numpad 5` | — | — |

Numpad 1/3 vertical movement works with NumLock either on or off.

Additional controls:

- `Numpad -` and `Numpad +`: decrease or increase the movement step
- Middle-click still freezes or unfreezes a preview while Palworld's `Ctrl` or `Alt` build modifier is held
- Middle mouse: freeze or unfreeze the selected preview
- `Shift+Middle mouse`: copy the build piece under the cursor
- `Ctrl+Shift+Middle mouse`: copy the targeted piece, match its position and rotation, and freeze the replacement preview

Default movement increments are 1 cm, 10 cm, and 100 cm. Default rotation increments are 1, 5, and 15 degrees. Edit `Scripts/config.lua` to change them.

Optional: with DarnMenu 1.6.2 or newer installed, Perfect Placement appears under **ESC → Mod Options**. Its native key-chord controls support a primary key plus any combination of `Ctrl`, `Alt`, and `Shift`. DarnMenu saves changed controls and settings to `Mods/shared/PerfectPlacement_user.lua`. Restart Palworld after applying changes because Perfect Placement reads that file when its Lua mod starts; startup keybinds also cannot be unregistered safely.

The same page exposes the starting, minimum, and maximum movement steps; the step multiplier; vertical movement limits; verbose diagnostic logging; and live frozen-validity feedback. Live validity feedback is enabled by default so a moved frozen preview follows its current placeable state. Disable it if refreshing collision and materials causes stutter on your system. These settings are validated both by DarnMenu and again when Perfect Placement loads the shared file.

Without DarnMenu, Perfect Placement's built-in controls remain available. It uses the defaults in `Scripts/config.lua` when no saved `Mods/shared/PerfectPlacement_user.lua` override exists. DarnUI is supplied as DarnMenu's own dependency; Perfect Placement does not require either mod and does not create a separate DarnUI overlay.

The companion guide resolves its displayed controls to Palworld's stock keycap textures. Invalid, conflicting, or unsupported bindings fall back to their defaults and are reported in the UE4SS log. Every action supports any combination of `Ctrl`, `Alt`, and `Shift`; displayed modifiers use that order before the primary key. Stock keycaps are also available for left, right, and middle mouse buttons plus mouse buttons 4 and 5.

DarnMenu's capture set supports F1-F12, letters, top-row and numpad digits, numpad operators, and Insert/Delete/Home/End/Page Up/Page Down. Existing default mouse bindings remain valid, but mouse buttons cannot currently be captured as replacement keys through DarnMenu.

Compatibility note: bindings may become intermittent when the same chord is registered by another mod or by UE4SS's built-in `Keybinds` mod. Check all UE4SS and mod keybinds for conflicts, then remap one of the overlapping actions.

Horizontal movement follows the frozen build piece's orientation. The piece's yaw defines the movement axes, while the camera decides which aligned axis is forward; Numpad 8 therefore moves away from the camera without drifting off the piece's orientation. The movement directions turn when the piece is rotated. Vertical movement is clamped from 25 cm below to 650 cm above the initially frozen position. The upward range corresponds to two standard wall levels.

While frozen, Perfect Placement suspends the local player's builder component and applies transforms only when an edit key is pressed. Continuous per-frame transform enforcement is disabled to avoid overloading the game thread.

## Required live discovery

In the UE4SS console, use **Dump CXX Headers** and **Generate Lua Types**. Search the generated Pal headers for:

```text
BuildObject
BuildMode
BuildPlacement
Placement
Preview
Indicator
CanBuild
RequestBuild
TryBuild
DecideBuild
```

The integration needs five verified bindings:

1. The component controlling player build mode.
2. The temporary preview/indicator actor.
3. The function that updates preview position from the camera trace.
4. The local confirmation function.
5. The server-authoritative function that validates and creates the structure.

The finished state flow will be:

```text
normal preview -> first confirm -> frozen editing
frozen editing -> cancel -> normal preview
frozen editing -> final confirm -> normal Palworld validation/commit
```

The final confirmation must call Palworld's original server-authoritative path. The mod must not spawn a completed build object directly.

## Known limitation of the Lua prototype

UE4SS `RegisterKeyBind` observes chorded keys but may not consume the underlying game input on every UE4SS/Palworld build. The production version should add a small Blueprint Logic Mod using a high-priority Enhanced Input Mapping Context. That context should be enabled only during frozen editing and consume only the complete Perfect Placement chords, leaving unmodified player controls alone.
