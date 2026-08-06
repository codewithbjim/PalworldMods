# Palworld Server Control: Physical Server Setup

This is a one-time setup for the person with physical access to the Windows computer running the Palworld dedicated server. No PowerShell command needs to be entered.

## 1. Extract and open the application

Extract `PalworldServerControl-WebView2-win-x64.zip`, then double-click `PalworldServerControl.exe`.

If Windows reports that the .NET 8 Desktop Runtime is missing, install the Microsoft .NET 8 Desktop Runtime for x64 and open the application again. The Microsoft Edge WebView2 Evergreen Runtime is also required and is normally already present on current Windows 10 and Windows 11 installations.

## 2. Select the local PalServer folder

On the connection screen, select **Use this machine** to detect the local PalServer folder automatically. If detection does not find it, select **Choose server folder** and browse to the folder containing `PalServer.exe`, such as `D:\PalServer`.

Select **Test connection**, then select **Use this location**. The application validates and remembers the folder.

## 3. Install the server helper

Select **Install Server Helper**. Windows will display a User Account Control prompt; select **Yes** to approve the one-time administrator operation. The PowerShell-based installer runs hidden, so no console or command entry is required.

The bundled installer installs the local control helper, creates and starts the `PalServer Control Agent` scheduled task, enables Palworld's REST API, preserves any existing structured ServerControl startup settings, and creates a timestamped configuration backup. Wait for the GUI to display **Server helper installed**, then select **Done**. Review **Startup Arguments** in the GUI before the helper next starts PalServer, especially if the old SteamCMD launch script supplied custom arguments.

## 4. Restart Palworld once

Manually restart the Palworld dedicated server once after installation so the REST API setting takes effect. This is the only required manual server restart.

## 5. Confirm operation

Open `PalworldServerControl.exe` again. The dashboard should change from **Unavailable** to reporting the server status after the helper responds.

On a remote client computer, the same GUI can connect through a network path such as `\\SERVER\PalServer`. Use the **Connection** button in the upper-right corner whenever the saved server location needs to be changed.

The server computer does not need to keep a console window open, and the server administrator does not need to remain signed in. Future start, stop, restart, and configuration operations can be performed through the GUI.

## Updating the helper

After replacing `PalworldServerControl.exe` with a newer version, open the GUI, select **Connection**, confirm the local server folder with **Use this location**, and select **Reinstall / Update Helper**. Approve the Windows UAC prompt. This refreshes the installed agent without requiring PowerShell or removing the saved startup settings.

The helper creates `requests`, `responses`, and `processing` folders plus `status.json` and `startup-settings.json` under `ServerControl`. These are required runtime data. Temporary files may appear briefly during an atomic write, but they should not accumulate.
