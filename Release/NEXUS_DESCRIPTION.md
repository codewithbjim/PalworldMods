# Perfect Placement

Freeze a building preview in place, walk around it, and make precise positional and rotational adjustments before handing control back to Palworld.

Perfect Placement is for the moment when vanilla placement is almost right—but the camera, terrain, or snap system will not let you put a piece exactly where you want it.

---

## Highlights

- **Freeze the preview.** Keep the selected build piece fixed in world space while your character and camera remain free.
- **Precise movement.** Nudge the piece forward, backward, left, right, up, or down using configurable centimeter increments.
- **Controlled rotation.** Rotate around the captured build-piece pivot instead of fighting the vanilla camera trace.
- **Instant reset.** Return the preview to the exact position and rotation it had when frozen.
- **Eyedropper.** Copy the build piece under the cursor into the active preview.
- **Copy and freeze.** Copy the targeted piece, transfer its position and rotation, and freeze the replacement preview there.
- **Native guide UI.** The on-screen keyboard, mouse, and controller controls stay visible while a live construction preview is available.
- **Scoped behavior.** Perfect Placement only edits the temporary preview. Final construction remains on Palworld's normal validation and placement path.

---

## Requirements

- Palworld on Windows
- A Palworld-compatible UE4SS installation
- Optional: DarnMenu 1.6.2 or newer for in-game Mod Options

Perfect Placement contains a UE4SS Lua mod and one consolidated resource `_P.pak`; install both parts from the archive.

With DarnMenu installed, configure controls and settings under **ESC → Mod Options → Perfect Placement**. Changes apply after restarting Palworld. Without DarnMenu, the mod uses its built-in bindings and `Scripts/config.lua` defaults unless a saved `Mods/shared/PerfectPlacement_user.lua` override already exists.

The optional DarnMenu page also configures movement steps and limits, controller preferences, verbose diagnostic logging, and live frozen-validity feedback. Live validity feedback is enabled by default and can be disabled if its collision and material refresh causes stutter. DarnUI is installed as DarnMenu's own dependency.

---

## Installation

Extract the archive into the Palworld installation folder containing `Pal`. Allow folders to merge.

The installed files should end up at:

```text
Pal/Binaries/Win64/UE4SS/Mods/PerfectPlacement/
Pal/Content/Paks/~mods/PerfectPlacement_NativeUI_P.pak
```

If your UE4SS build still uses `mods.txt`, add:

```text
PerfectPlacement : 1
```

---

## Controls

### Keyboard and mouse

- **Freeze / unfreeze preview:** Middle mouse
- **Move horizontally:** Numpad 8 / 2 / 4 / 6
- **Move up / down:** Numpad 3 / 1
- **Rotate:** Numpad 7 / 9
- **Decrease / increase movement step:** Numpad - / +
- **Reset to frozen transform:** Numpad 5
- **Copy targeted build piece:** Shift + Middle mouse
- **Copy and freeze to targeted piece:** Ctrl + Shift + Middle mouse

### Gamepad

- **Freeze / unfreeze preview:** L3
- **Copy targeted build piece:** L3 + D-pad Down
- **Copy and freeze to targeted piece:** L3 + D-pad Up
- **Move horizontally:** D-pad
- **Move up / down:** LT + D-pad Up / Down
- **Decrease / increase movement step:** LT + D-pad Left / Right
- **Rotate:** LB / RB
- **Reset to frozen transform:** R3

The key guide appears only while a live construction preview is available. Mouse bindings are ignored without an active preview, so normal middle-mouse Pal commands remain unaffected. Controller actions are Blueprint events and do not use a recurring Lua input poll.

---

## Notes and limitations

- Vertical movement is clamped from 25 cm below to 650 cm above the initially frozen position—an upward range of two standard wall levels.
- In this experimental alpha, Palworld's top-row `4` Replacement Mode input can still fire while a foundation preview is frozen; avoid that key while frozen. Numpad 4 movement is unaffected.
- Install on each client that wants to use the placement controls.
- Test new mod versions in a disposable world before using an important save.
- Other mods that replace the same construction UI or take ownership of the same input bindings may conflict.

---

## Troubleshooting

**Nothing happens when freezing**

Confirm UE4SS loaded `PerfectPlacement` and that `PerfectPlacement_NativeUI_P.pak` is in `Pal/Content/Paks/~mods`.

**The guide appears but the controls do not respond**

Check the UE4SS console/log for `[PerfectPlacement]` errors and confirm Num Lock is enabled for keyboard controls.

**The guide is missing or incomplete**

Remove older Perfect Placement `.pak` files before installing the current one. Do not keep two versions under different filenames.

When reporting a problem, include your Palworld version, UE4SS version, installed mod list, reproduction steps, and the relevant UE4SS log section.

---

## Support and questions

Open an issue on the project repository and include the diagnostic information listed above.

---

## Support the project

If Perfect Placement has been useful and you would like to support continued development, you can leave a tip on [Ko-fi](https://ko-fi.com/virtualbjorn).
