PERFECT PLACEMENT 0.1.6-RELEASE
=======================

REQUIREMENT
-----------
A Palworld-compatible UE4SS installation and DarnMenu 1.6.2 or newer.
DarnUI is installed as DarnMenu's dependency.

INSTALLATION
------------
Extract this archive into the Palworld installation folder containing "Pal".
Allow folders to merge.

Expected files:
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\enabled.txt
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Info.json
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\main.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\config.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\darnmenu.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\keybindings.lua
  Pal\Content\Paks\LogicMods\PerfectPlacement.pak

If your UE4SS build uses mods.txt, add:
  PerfectPlacement : 1

KEYBOARD / MOUSE
----------------
Middle mouse       Freeze / unfreeze
Numpad 8/2/4/6     Move horizontally
Numpad 3/1         Move up / down
Numpad 7/9         Rotate
Numpad -/+         Decrease / increase movement step
Numpad 5           Reset to the frozen transform
Shift + middle mouse
                   Copy targeted build piece

Vertical movement is limited to 25 cm below and 650 cm above the initially frozen position.
Numpad 1/3 vertical movement works with NumLock either on or off.

Mouse bindings are ignored unless Palworld has an active construction preview.
Middle mouse still freezes or releases the preview while Ctrl or Alt is held for Palworld build controls.
Normal middle-mouse Pal commands remain unaffected.

Gamepad placement controls are not supported in this release.

DARNMENU
--------
Open ESC > Mod Options > Perfect Placement to edit key chords. Apply changes,
then restart Palworld. Saved overrides live in:
  Pal\Binaries\Win64\UE4SS\Mods\shared\PerfectPlacement_user.lua

The page also configures movement-step values, step multiplier, vertical
limits, and verbose diagnostic logging.

Without DarnMenu or a saved override, Scripts\config.lua supplies the defaults.

KEYBIND COMPATIBILITY
---------------------
Bindings may become intermittent when the same chord is registered by another
mod or by UE4SS's built-in Keybinds mod. Check all UE4SS and mod keybinds for
conflicts, then remap one of the overlapping actions.

UNINSTALL
---------
Delete the PerfectPlacement UE4SS mod folder and PerfectPlacement.pak.
