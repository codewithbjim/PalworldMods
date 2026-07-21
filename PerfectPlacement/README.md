# Perfect Placement

Perfect Placement is a Palworld 1.0 UE4SS Lua mod prototype. It is designed to
lock a building preview in world space, leave the player free to walk around,
and provide precise camera-relative transform controls before final placement.

## Current status

This repository contains the complete input, configuration, transform, and
diagnostic scaffold. The Palworld-specific preview selection and final
placement hooks are deliberately treated as a development adapter: their exact
class and function names must be verified against a live Palworld 1.0 UE4SS
header dump. They should not be guessed because an incorrect final-placement
hook could consume resources twice or create invalid save data.

The current development controls let you discover a likely preview actor, lock
it, move it, rotate it, and release it back to Palworld.

## Installation for development

1. Install a Palworld 1.0-compatible UE4SS build and verify that its console
   opens correctly.
2. Copy this `PerfectPlacement` directory into the UE4SS `Mods` directory.
3. If your UE4SS installation still uses `mods.txt`, add:

   ```text
   PerfectPlacement : 1
   ```

4. Start a disposable test world. Do not develop against your only save.
5. Enter build mode and make a building preview visible.
6. Press `Alt+F6` to scan configured class names for a preview candidate.
7. Read the UE4SS console and confirm the selected object's full name.
8. Middle-click to lock or release the selected preview (`Alt+F7` is the fallback).

If discovery finds nothing, press `Alt+F8`. UE4SS will write an actor dump.
Search the dump for `BuildObject`, `Preview`, `Indicator`, and `Placement`, then
add the relevant class name to `Scripts/config.lua`.

## Controls

Controls only change the preview while it is locked. Player movement remains on
Palworld's normal controls.

| Action | Normal | Fine | Coarse |
| --- | --- | --- | --- |
| Move left/right | `Numpad 4/6` | Use `Numpad -`, then move | Use `Numpad +`, then move |
| Move forward/back | `Numpad 8/2` | Use `Numpad -`, then move | Use `Numpad +`, then move |
| Move vertically | Disabled | Disabled | Disabled |
| Rotate yaw | `Numpad 7/9` | Configure rotation step | Configure rotation step |
| Reset to locked transform | `Numpad 5` | — | — |

Additional development controls:

- `Numpad -` and `Numpad +`: decrease or increase the movement step
- `Alt+F6`: discover and select a preview candidate
- Middle mouse: lock or release the selected preview
- `Alt+Middle mouse`: copy the build piece under the cursor
- `Alt+F7`: fallback lock/release hotkey
- `Alt+F8`: dump all actors for discovery

Default movement increments are 1 cm, 10 cm, and 100 cm. Default rotation
increments are 1, 5, and 15 degrees. Edit `Scripts/config.lua` to change them.
Horizontal movement follows the locked build piece's orientation. The piece's
yaw defines the movement axes, while the camera decides which aligned axis is
forward; Numpad 8 therefore moves away from the camera without drifting off the
piece's orientation. The movement directions turn when the piece is rotated.
Vertical key bindings are currently disabled until terrain
and structural-support validation is complete.

While locked, Perfect Placement suspends the local player's builder component
and applies transforms only when an edit key is pressed. Continuous per-frame
transform enforcement is disabled to avoid overloading the game thread.

## Required live discovery

In the UE4SS console, use **Dump CXX Headers** and **Generate Lua Types**. Search
the generated Pal headers for:

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
normal preview -> first confirm -> locked editing
locked editing -> cancel -> normal preview
locked editing -> final confirm -> normal Palworld validation/commit
```

The final confirmation must call Palworld's original server-authoritative path.
The mod must not spawn a completed build object directly.

## Known limitation of the Lua prototype

UE4SS `RegisterKeyBind` observes chorded keys but may not consume the underlying
game input on every UE4SS/Palworld build. The production version should add a
small Blueprint Logic Mod using a high-priority Enhanced Input Mapping Context.
That context should be enabled only during locked editing and consume only the
complete Perfect Placement chords, leaving unmodified player controls alone.
