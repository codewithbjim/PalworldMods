# Perfect Placement

Perfect Placement is a Palworld 1.0 UE4SS Lua mod prototype. It is designed to
freeze a building preview in world space, leave the player free to walk around,
and provide precise camera-relative transform controls before final placement.

## Current status

The mod resolves the active placement preview directly through the local
player's builder component. Its controls can freeze, move, rotate, reset, copy,
and release that preview. Final placement remains under Palworld's control.

## Installation for development

1. Install a Palworld 1.0-compatible UE4SS build and verify that its console
   opens correctly.
2. Install and enable DarnMenu.
3. Copy this `PerfectPlacement` directory into the UE4SS `Mods` directory.
4. Install the companion Logic Mod as
   `Pal/Content/Paks/LogicMods/PerfectPlacement.pak`.
5. If your UE4SS installation still uses `mods.txt`, add:

   ```text
   PerfectPlacement : 1
   ```

6. Start a disposable test world. Do not develop against your only save.
7. Enter build mode and make a building preview visible.
8. Middle-click to freeze or unfreeze the selected preview.

## Controls and configuration

Controls only change the preview while it is frozen. Player movement remains on
Palworld's normal controls. The table below shows the defaults.

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

Default movement increments are 1 cm, 10 cm, and 100 cm. Default rotation
increments are 1, 5, and 15 degrees. Edit `Scripts/config.lua` to change them.

DarnMenu is required and adds Perfect Placement under `Escape > Mod Options`.
It can rebind Freeze, Copy, and all eleven adjustment actions, and its saved
choices take precedence over `Scripts/config.lua`. Restart Palworld after
applying changes. Each row renders Palworld keycaps for its primary input and
its optional `Ctrl`, `Alt`, and `Shift` modifiers; select a modifier keycap to
toggle it.

The companion guide resolves the selected keys to Palworld's stock keycap
textures. Invalid, conflicting, or unsupported bindings fall back to their
defaults and are reported in the UE4SS log. Every action supports any
combination of `Ctrl`, `Alt`, and `Shift`; the guide displays them in that
order before the primary key. Stock keycaps are also available for left,
right, and middle mouse buttons plus mouse buttons 4 and 5.

Gamepad input requires the companion Perfect Placement Blueprint pak. Its
bindings are configured under `gamepad.bindings` in `Scripts/config.lua`.
While frozen, actions may use any D-pad direction by itself or with `LT`,
`RT`, or both triggers; `LB`, `RB`, `L3`, and `R3` are also assignable.
Blueprint sends physical chord counters to Lua, so remapping an action also
updates the stock Palworld keycap textures shown in the controller guide.
Unfrozen controls intentionally remain limited to `L3` and
`L3 + D-pad Down` to avoid consuming Palworld's normal building controls.

> [!WARNING]
> Gamepad support in 0.2.0-beta.1 is experimental. The author does not have a gamepad,
> so the controller path has not been tested on physical hardware. Test it in a
> disposable world and report the controller model, Steam Input status,
> configured chord, reproduction steps, and relevant UE4SS log lines.

Known DarnMenu limitation: primary-input capture supports function keys,
letters, digits, numpad keys, Insert, Delete, Home, End, Page Up, Page Down,
and mouse buttons 1-5. Modifier keycaps support any combination of `Ctrl`,
`Alt`, and `Shift`. Primary-input capture does not support arrows, Space,
Enter, Tab, Escape, Backspace, punctuation keys, or mouse-wheel scrolling.

Compatibility note: bindings may become intermittent when the same chord is
registered by another mod or by UE4SS's built-in `Keybinds` mod. Check all
UE4SS and mod keybinds for conflicts, then remap one of the overlapping actions.

Horizontal movement follows the frozen build piece's orientation. The piece's
yaw defines the movement axes, while the camera decides which aligned axis is
forward; Numpad 8 therefore moves away from the camera without drifting off the
piece's orientation. The movement directions turn when the piece is rotated.
Vertical movement is clamped from 25 cm below to 650 cm above the initially
frozen position. The upward range corresponds to two standard wall levels.

While frozen, Perfect Placement suspends the local player's builder component
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
normal preview -> first confirm -> frozen editing
frozen editing -> cancel -> normal preview
frozen editing -> final confirm -> normal Palworld validation/commit
```

The final confirmation must call Palworld's original server-authoritative path.
The mod must not spawn a completed build object directly.

## Known limitation of the Lua prototype

UE4SS `RegisterKeyBind` observes chorded keys but may not consume the underlying
game input on every UE4SS/Palworld build. The production version should add a
small Blueprint Logic Mod using a high-priority Enhanced Input Mapping Context.
That context should be enabled only during frozen editing and consume only the
complete Perfect Placement chords, leaving unmodified player controls alone.
