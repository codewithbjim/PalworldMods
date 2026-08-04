# Quick Connect Manager

Quick Connect Manager adds a native, non-modal, gamepad-compatible dedicated-server selector and editor to Palworld's launch screen. Select a server row to connect immediately while the normal title menu remains available.

## Features

- Shows server names, current players, ping, and password-required state on the title screen.
- Adds, modifies, and removes saved servers in game through an editor integrated into the launch panel.
- Saves a manual Add entry only after a successful connection and automatically saves successful connections made through Palworld's Join Multiplayer Game screen.
- Supports D-pad, left stick, controller Confirm, controller Cancel, and Palworld-native controller text entry in addition to mouse and keyboard.
- Scrolls through every configured server while retaining a compact three-row viewport.
- Imports active recent dedicated servers from Palworld's History list when the mod is first installed with no enabled server configured.
- Requires exact client versions for incomplete History status and permits fully valid rows only when `X.Y.Z` matches.
- Uses Refresh for status and saved-credential updates without changing saved world names; Shift+Refresh explicitly rediscovers an automatically managed list while preserving matching names.
- Connects through Palworld's native join-game flow and restores passwords already saved by Palworld.
- Keeps Ctrl+Shift+F1 through Ctrl+Shift+F8 shortcuts and `qc` console commands available when the panel is disabled.
- Does not modify servers, authentication, saves, worlds, or regular gameplay.

## Requirement

Install Palworld's UE4SS Experimental package before installing Quick Connect Manager.

## Installation

Close Palworld and extract the archive into the Palworld installation folder containing `Pal`. The Lua payload installs under `Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager`; the cooked panel installs as `Pal\Content\Paks\~mods\QuickConnectManager_UI_P.pak`.

Do not install the Nexus and Steam Workshop versions at the same time. When switching from Workshop to Nexus, remove the managed `Mods\NativeMods\UE4SS\Mods\QuickConnectManager` copy and `Pal\Content\Paks\~WorkshopMods\QuickConnectManager` before installing this archive.

## Passwords

Saved server passwords are stored as plain text in the local `Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager\Scripts\config.lua`. Passwords are never written to the discovery cache or diagnostic output. Protect the configuration file and do not upload it in logs or support archives.

Passwords can be updated through Modify Server or refreshed from Palworld's saved credential after a successful Join Multiplayer connection.
