QUICK CONNECT MANAGER 0.2.0
===========================

REQUIREMENT
-----------
Palworld's UE4SS Experimental package.

INSTALLATION
------------
Close Palworld, then extract this archive into the Palworld installation folder containing "Pal". Allow folders to merge.

Expected files:
  Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\enabled.txt
  Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Info.json
  Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Scripts\config.lua
  Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Scripts\connections.lua
  Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Scripts\discovery.lua
  Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Scripts\launch_ui.lua
  Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Scripts\main.lua
  Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Scripts\servers.lua
  Pal\Content\Paks\~mods\QuickConnectManager_UI_P.pak

Do not install the Nexus and Steam Workshop versions at the same time. When switching from Workshop to Nexus, remove Mods\NativeMods\UE4SS\Mods\QuickConnectManager and Pal\Content\Paks\~WorkshopMods\QuickConnectManager before installing this archive.

If the UE4SS installation uses mods.txt, add:
  QuickConnectManager : 1

USAGE
-----
The Quick Connect panel appears automatically on Palworld's launch screen. Select a listed server to connect, use the plus button to add a server, use the pencil to modify it, use the garbage button to remove it, or use Refresh to update status and saved credentials without changing saved world names.

The Add and Modify forms are integrated into the panel and support mouse, keyboard, D-pad, left stick, controller Confirm, controller Cancel, and Palworld's native controller text entry. Manual Add entries are saved only after a successful connection. Connections made through Palworld's Join Multiplayer Game screen are also added automatically after success.

On the first launch with no enabled server configured, the mod imports only active recent dedicated servers from Palworld's History list. Later launches reuse the generated configuration and do not rediscover servers unless Shift+Refresh is used.

PASSWORDS
---------
Saved server passwords are written as plain text to Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Scripts\config.lua. Protect that local file and do not include it in logs, screenshots, support bundles, or shared archives.

UNINSTALL
---------
Delete the QuickConnectManager UE4SS mod folder and QuickConnectManager_UI_P.pak.
