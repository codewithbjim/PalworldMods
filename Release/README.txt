PERFECT PLACEMENT 0.3.0-RC.1
============================

RELEASE CANDIDATE
-----------------
This build changes how Perfect Placement integrates with Palworld's construction UI. Test it in a disposable world or with a verified save backup before using it for an important build.

REQUIREMENT
-----------
A Palworld-compatible UE4SS installation.

OPTIONAL DARNMENU INTEGRATION
-----------------------------
DarnMenu 1.6.2 or newer adds in-game Mod Options. DarnUI is installed as DarnMenu's own dependency. Perfect Placement works without either one.

INSTALLATION
------------
Extract this archive into the Palworld installation folder containing "Pal". Allow folders to merge.

Expected files:
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\enabled.txt
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Info.json
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\main.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\config.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\darnmenu.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\keybindings.lua
  Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement\Scripts\runtime.lua
  Pal\Content\Paks\~mods\PerfectPlacement_NativeUI_P.pak

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
Ctrl + Shift + middle mouse
                   Copy targeted piece, match its transform, and freeze

Vertical movement is limited to 25 cm below and 650 cm above the initially frozen position. Numpad 1/3 vertical movement works with NumLock either on or off.

Mouse bindings are ignored unless Palworld has an active construction preview. Middle mouse still freezes or releases the preview while Ctrl or Alt is held for Palworld build controls. Normal middle-mouse Pal commands remain unaffected.

GAMEPAD
-------
Full gamepad support is bundled with Perfect Placement Core, including the native input DLL required for D-pad Up and LB/RB interception.

L3                 Freeze / unfreeze
L3 + D-pad Down    Copy targeted build piece
L3 + D-pad Up      Copy targeted piece, match its transform, and freeze
D-pad              Move horizontally while frozen
LT + D-pad Up/Down Move up / down while frozen
LT + D-pad Left/Right
                   Decrease / increase movement step
LB / RB            Rotate left / right
R3                 Reset to the frozen transform

The optional native gamepad bridge reports complete physical controller chords to Lua only when pressed; Perfect Placement does not run a recurring Lua gamepad input poll. The visible placement controls are rendered inside Palworld's construction guide by PerfectPlacement_NativeUI_P.pak, and their input-device state follows Palworld's CommonInput subsystem. Advanced controller bindings are available in Scripts\config.lua.

For troubleshooting construction UI churn, temporarily set diagnostics.ui_lifecycle_counters to true in Scripts\config.lua. Perfect Placement logs aggregate Setup, Destruct, host, and guide-transition counts every five seconds; restore the default false value for normal play and release builds.

DARNMENU (OPTIONAL)
-------------------
Open ESC > Mod Options > Perfect Placement to edit controls and settings. Apply changes, then restart Palworld. Saved overrides live in:
  Pal\Binaries\Win64\UE4SS\Mods\shared\PerfectPlacement_user.lua

The page also configures movement-step values, step multiplier, vertical limits, controller preferences, verbose diagnostic logging, and live frozen-validity feedback. Live validity feedback defaults to On and can be disabled if its collision and material refresh causes stutter.

Without DarnMenu, the built-in controls remain available. Scripts\config.lua supplies the defaults when no saved override exists.

KEYBIND COMPATIBILITY
---------------------
Bindings may become intermittent when the same chord is registered by another mod or by UE4SS's built-in Keybinds mod. Check all UE4SS and mod keybinds for conflicts, then remap one of the overlapping actions.

UNINSTALL
---------
Delete the PerfectPlacement UE4SS mod folder and PerfectPlacement_NativeUI_P.pak. Remove legacy Pal\Content\Paks\LogicMods\PerfectPlacement.pak if upgrading from 0.2.0.
