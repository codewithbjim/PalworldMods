# Perfect Placement

Freeze a building preview in place, walk around it, and make precise positional
and rotational adjustments before handing control back to Palworld.

Perfect Placement is for the moment when vanilla placement is almost right—but
the camera, terrain, or snap system will not let you put a piece exactly where
you want it.
give me bbcode
---

## Highlights

- **Freeze the preview.** Keep the selected build piece fixed in world space
  while your character and camera remain free.
- **Precise movement.** Nudge the piece forward, backward, left, or right using
  configurable centimeter increments.
- **Controlled rotation.** Rotate around the captured build-piece pivot instead
  of fighting the vanilla camera trace.
- **Instant reset.** Return the preview to the exact position and rotation it
  had when frozen.
- **Eyedropper.** Copy the build piece under the cursor into the active preview.
- **Native guide UI.** The on-screen controls switch between keyboard/mouse and
  gamepad layouts based on the latest detected input.
- **Scoped behavior.** Perfect Placement only edits the temporary preview. Final
  construction remains on Palworld's normal validation and placement path.

---

## Requirements

- Palworld on Windows
- A Palworld-compatible UE4SS installation

Perfect Placement contains both a UE4SS Lua mod and a Logic Mod `.pak`; install
both parts.

---

## Installation

Extract the archive into the Palworld installation folder containing `Pal`.
Allow folders to merge.

The installed files should end up at:

```text
Pal/Binaries/Win64/UE4SS/Mods/PerfectPlacement/
Pal/Content/Paks/LogicMods/PerfectPlacement.pak
```

If your UE4SS build still uses `mods.txt`, add:

```text
PerfectPlacement : 1
```

---

## Controls

### Keyboard and mouse

| Action | Control |
|---|---|
| Freeze / unfreeze preview | Middle mouse |
| Move | Numpad 8 / 2 / 4 / 6 |
| Rotate | Numpad 7 / 9 |
| Decrease / increase movement step | Numpad - / + |
| Reset to frozen transform | Numpad 5 |
| Copy targeted build piece | Alt + Middle mouse |

### Gamepad

| Action | Control |
|---|---|
| Freeze / unfreeze preview | R3 |
| Move | D-pad |
| Rotate | LB / RB |
| Adjust movement step | LT + D-pad left / right |
| Reset to frozen transform | L3 |
| Copy targeted build piece | Y |

The key guide appears only while a live construction preview is available.

---

## Notes and limitations

- Horizontal adjustment is currently supported; vertical adjustment is disabled
  until terrain and structural-support validation is fully verified.
- Install on each client that wants to use the placement controls.
- Test new mod versions in a disposable world before using an important save.
- Other mods that replace the same construction UI or take ownership of the same
  input bindings may conflict.

---

## Troubleshooting

**Nothing happens when freezing**

Confirm UE4SS loaded `PerfectPlacement` and that `PerfectPlacement.pak` is in
`Pal/Content/Paks/LogicMods`.

**The guide appears but the controls do not respond**

Check the UE4SS console/log for `[PerfectPlacement]` errors and confirm Num Lock
is enabled for keyboard controls.

**The guide is missing or incomplete**

Remove older Perfect Placement `.pak` files before installing the current one.
Do not keep two versions under different filenames.

When reporting a problem, include your Palworld version, UE4SS version, installed
mod list, reproduction steps, and the relevant UE4SS log section.

---

## Support and questions

Open an issue on the project repository and include the diagnostic information
listed above.

