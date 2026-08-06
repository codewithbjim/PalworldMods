# Palworld Dedicated Server Control

This folder contains the WebView2 control panel and its server helper for the Palworld dedicated server.

The client GUI writes fixed command requests to the existing SMB share. A helper running locally on the server processes those requests, starts `PalServer.exe`, and uses Palworld's REST API for graceful shutdowns. No arbitrary PowerShell received from the network is executed.

The server administrator performs the one-time server setup below directly on the server computer. After that setup, the person using the client GUI does not need physical access, Remote Desktop, or Windows administrator access to start, stop, restart, or check the server.

## One-time server setup

On the physical server computer, extract the WebView2 ZIP and double-click `PalworldServerControl.exe`. Select **Use this machine** or **Choose server folder**, validate the local folder containing `PalServer.exe`, and select **Use this location**. Select **Install Server Helper** and approve the normal Windows User Account Control prompt. The bundled installer runs hidden; no PowerShell window or typed command is required.

The installer creates a startup task named `PalServer Control Agent`, enables Palworld's REST API in the active `PalWorldSettings.ini`, preserves any existing structured ServerControl startup settings, and creates a timestamped configuration backup. Review **Startup Arguments** in the GUI if the previous SteamCMD launch script supplied custom arguments. The server administrator must restart PalServer once manually after installation so the REST API setting takes effect. See `webview2-client\PHYSICAL-SERVER-SETUP.md` for the complete handoff instructions.

## Client GUI

Double-click `PalworldServerControl.exe` in the distributed `ServerControl` folder.

Server status and Start, Stop, Restart, and Refresh controls remain visible across the top of the window. When the installed helper can reach Palworld's REST API, the dashboard also reports players, uptime, and server FPS. Configuration categories appear in the left sidebar and can be searched from the settings header.

The distributable executable is built from `webview2-client\PalworldServerControl.exe`. It is one small .NET executable containing the native loader, web assets, metadata, and fixed server-helper installer payload. It requires the .NET 8 Desktop Runtime and Microsoft Edge WebView2 Evergreen Runtime on the client computer.

When the configured server folder is unavailable, the WebView2 application opens an in-app connection setup screen. It can detect a local PalServer installation, open a Windows folder picker, or accept a UNC network-share path. The selected location is validated and remembered locally, and it can be changed later with the **Connection** button in the application header.

Use the in-app **Connection** screen to select a local server folder or enter a network share such as `\\SERVER\PalServer`.

## Configuration editor

The GUI exposes all 119 parameters in the installed SteamCMD `DefaultPalWorldSettings.ini` plus 11 official PalServer startup arguments. Settings are grouped into World & Time, Player Balance, Pal Balance, Resources & Performance, Bases & Guilds, PvP & Death, Gameplay Features, Server & Access, Administration, and Startup Arguments.

Each setting uses one compact full-width row card showing a friendly label, exact parameter name, current value, installed-template default, description, and reset action. A blue left edge identifies values that differ from the installed default. Boolean and enumerated settings use drop-down controls. Administrator and connection passwords remain masked and are changed through a confirmation dialog opened from their setting card.

`Reload` rereads the active configuration and defaults. `Save` validates edited values, refuses to overwrite a file changed since loading, creates timestamped backups, and marks the server for restart. `Save & Restart` saves first and then offers to submit a graceful restart request.

INI settings are saved to `Pal\Saved\Config\WindowsServer\PalWorldSettings.ini`. Startup arguments are saved to `ServerControl\startup-settings.json` and are used the next time the helper launches PalServer. The editor preserves unrecognized INI fields and additional startup arguments.

## Security

- Anyone with write access to the `ServerControl\requests` directory can start, stop, or restart the server. Restrict the SMB share to trusted accounts.
- Do not port-forward the REST API port. The helper accesses it through `localhost` only.
- Stop and restart use Palworld's graceful shutdown endpoint. The helper does not fall back to `Stop-Process`.
- The administrative password is read locally from `PalWorldSettings.ini`; it is never written into request or response files.
- Password values are never displayed in the settings cards or included in controller logs.

## Removal

Run `server\Uninstall-PalServerControl.ps1` as Administrator on the server. This removes the scheduled task and installed helper, but preserves command history and does not revert `RESTAPIEnabled`.
