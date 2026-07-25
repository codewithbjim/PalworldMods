PERFECT PLACEMENT 0.2.0-beta.2
=======================

REQUIREMENT
-----------
A Palworld-compatible UE4SS installation and DarnMenu.

INSTALLATION
------------
Extract this archive into the Palworld installation folder containing "Pal".
Allow folders to merge.

Expected files:
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\enabled.txt
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Info.json
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\thumbnail.png
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\main.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\config.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\keybindings.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\darnmenu.lua
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

EXPERIMENTAL GAMEPAD
--------------------
Gamepad support requires the companion Perfect Placement Logic Mod.
The default controller controls are:

L3                   Freeze / unfreeze
L3 + D-pad Down      Copy targeted build piece while unfrozen
D-pad Left / Right   Move left / right while frozen
D-pad Up / Down      Move forward / back while frozen
LT + D-pad Up / Down Raise / lower while frozen
LB / RB              Rotate left / right while frozen
LT + D-pad Left/Right
                     Decrease / increase movement step while frozen
R3                   Reset to the frozen transform

Controller chords are configured under gamepad.bindings in Scripts\config.lua.
Frozen D-pad actions may be combined with LT, RT, or both triggers. The
controller guide resolves Palworld's stock keyguide textures at runtime.

Gamepad support has not been tested on physical controller hardware by the
author and requires community testing. When reporting a problem, include the
controller model, Steam Input status, configured chord, reproduction steps,
and relevant UE4SS log lines.

DARNMENU
--------
Perfect Placement appears under Escape > Mod Options. DarnMenu can configure
Freeze, Copy, and all eleven adjustment bindings, including mouse buttons.
Select the Ctrl, Alt, or Shift keycaps to add modifiers to any binding.
Restart Palworld after applying changes.

KEYBIND COMPATIBILITY
---------------------
Bindings may become intermittent when the same chord is registered by another
mod or by UE4SS's built-in Keybinds mod. Check all UE4SS and mod keybinds for
conflicts, then remap one of the overlapping actions.

UNINSTALL
---------
Delete the PerfectPlacement UE4SS mod folder and PerfectPlacement.pak.
