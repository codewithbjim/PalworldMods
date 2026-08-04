# Quick Connect Manager

Quick Connect Manager is a UE4SS Lua mod for keeping named Palworld dedicated-server shortcuts. Its native server selector is shown automatically on Palworld's launch screen, and selecting a server connects immediately through Unreal's normal client-travel path. It does not alter the server, authentication, saves, or gameplay.

## Configure servers

Edit `Scripts/config.lua` and add entries to `servers`. Disabled example entries are ignored.

```lua
servers = {
    { name = "Friends", address = "play.example.com:8211", password = "optional" },
    { name = "LAN", address = "192.168.1.20:8211" },
},
```

Restart Quick Connect Manager after changing the file. Addresses accept a hostname or IPv4 address and an optional port. URL options, commands, spaces, and embedded address passwords are rejected. The separate optional `password` field is supported and is stored as plain text in this local configuration file; passwords are never printed by the mod.

On the mod's first launch, if no enabled server has been added, Quick Connect asks Palworld for the user's History server list. Only currently available, version-compatible results with valid status data are retained. World GUIDs, password-required state, and any password already saved by Palworld are added to the generated `config.lua`; the discovery cache deliberately omits the password. The bootstrap runs only once. Adding any enabled entry to `config.lua` takes precedence over the cache. Hold Shift while selecting Refresh to force a new discovery and replace the automatically managed server list.

## Launch-screen selector

The non-modal selector panel appears automatically on the right side when Palworld's title screen becomes available. It uses Palworld's common-window and common-button widgets directly; DarnUI and DarnMenu are not required. The normal title menu remains available. If Palworld's mod disclaimer is visible, Quick Connect hides until it closes. Its launch-screen lifecycle is independent of the disclaimer, so mods that suppress the disclaimer do not suppress Quick Connect.

Select a server row to connect immediately. A lock icon marks password-protected servers. Refresh asks Palworld for current History status and saved credentials for the existing rows; it does not rediscover or replace the configured list. Shift+Refresh explicitly performs a full discovery sync. The separate `X` action removes an automatically discovered server from Quick Connect and remembers that choice across refreshes. If a server password changes, reconnect once through Palworld's Join Multiplayer Game flow, then use Refresh to update the saved password in `config.lua`. Set `ui.show_on_launch = false` in `Scripts/config.lua` to disable the automatic selector.

## Other connection controls

Press `Ctrl+Shift+F1` through `Ctrl+Shift+F8` to connect to the corresponding enabled server. The enabled entries are packed into shortcut slots in their listed order.

The UE4SS console also supports:

```text
qc list
qc connect 1
qc connect "Friends"
qc select 1
qc connect
qc next
qc previous
```

Server names are matched without regard to capitalization. `qc connect` without a name or slot connects to the currently selected entry. Selection lasts until the mod is restarted.

## Requirements

Quick Connect Manager requires Palworld's UE4SS Experimental package. It is client-side only and does not need to be installed on the dedicated server.

## Install

For Steam Workshop, subscribe to the item, launch Palworld, and enable Quick Connect Manager under **Options > Mod Management**.

For a Nexus/manual installation, close Palworld and extract the archive into the Palworld installation folder containing `Pal`. The archive installs the Lua mod under `Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager` and the cooked UI under `Pal\Content\Paks\~mods\QuickConnectManager_UI_P.pak`. If the UE4SS installation uses `mods.txt`, add `QuickConnectManager : 1`.

Do not install the Nexus and Steam Workshop versions at the same time. When switching from Workshop to Nexus, remove the managed `Mods\NativeMods\UE4SS\Mods\QuickConnectManager` copy and `Pal\Content\Paks\~WorkshopMods\QuickConnectManager` before installing the Nexus archive.

## Runtime safety

The panel exists only on Palworld's title world. Runtime callbacks validate Unreal objects before use, isolate hook and refresh failures, serialize title polling so delayed jobs cannot accumulate, and release transient widgets after title transitions or failed construction. Configuration and discovery-cache updates use recoverable replacement files rather than truncating the active file in place.

## Current limitations

- Saved server passwords are local plain text in `config.lua`; protect that file and do not include it in shared logs or mod archives.
- Manually configured servers remain config-based; the panel can remove only automatically discovered entries.
- The compact launch selector displays the first three enabled servers; all configured entries remain available through console commands.
- Refresh uses Palworld's History query, so a manually configured server receives updated status only when it is also present in the user's History list.
- IPv6 addresses are not supported yet.
