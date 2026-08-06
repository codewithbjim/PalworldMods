# Palworld Live Map

Palworld Live Map is a private, ad-free Electron desktop map for Palworld 1.0. A standalone .NET reader obtains the local player's transform and loaded-world map entities with read-only process access and streams snapshots to Electron over standard output. Electron forwards them to the isolated renderer through a narrow IPC bridge. No local server, telemetry file, injection, or process-memory write is used.

The retired UE4SS/file-polling producer must not be deployed.

## MVP features

- Live player position, heading, and altitude through the external reader.
- Throttled loaded-world discovery for sidebar layers such as Fast Travel, Lifmunk Effigies, treasure, skill fruit, resources, towers, dungeons, NPCs, and Pals.
- Full-resolution 8192x8192 Palpagos and World Tree maps with separate coordinate calibration.
- Follow-player mode, automatic World/Tree selection, free panning, cursor-centered zooming, and fit-to-window.
- Named custom markers persisted in Electron renderer storage.
- Searchable, collapsible filter groups with compact layer chips, active counts, and show/hide-all controls.
- GPU-composited map movement with overlay redraws only when state changes.
- Isolated renderer: context isolation and sandboxing enabled, Node integration disabled, navigation and new windows denied.
- No advertisements, analytics, accounts, copied Overwolf code, or remote services.

## Install local map assets

Place `T_WorldMap.webp` and `T_TreeMap.webp` in a local source directory, then run:

```powershell
.\Assets\Install-MapAssets.ps1 -SourceDirectory <directory>
```

The installer validates both images as 8192x8192, copies them into `App\assets\maps`, and records their SHA-256 hashes. The images and generated manifest are ignored by Git because they remain Pocketpair game assets.

For the filter artwork, run `Assets\Install-IconAssets.ps1 -SourceDirectory <game-data-icons-directory>`. It installs and hashes the local Pal portraits, eggs, materials, structures, and item icons used by the sidebar. These game assets are also ignored by Git.

Supplemental map-filter textures downloaded for private use from the Palworld.gg map belong in `App\assets\icons` as local-only PNG files. They are ignored by Git alongside the extracted game textures; the catalog retains symbol fallbacks if a local texture is absent.

Run `Assets\Install-PalCatalog.ps1 -GameDataDirectory <game-data-directory>` to generate the complete searchable Pals Locations section and install its local portraits from `characters.json` and `icons\pals`.

## Build and run Electron

From `PalworldLiveMap`:

```powershell
dotnet build .\Reader\PalworldLiveMap.Reader.csproj -c Release
pnpm install
pnpm start
```

Electron 43.2.0 is pinned in the lockfile. Start Palworld and enter a world; the Electron main process automatically launches the reader and retries when the game is not running. Closing Electron stops the child reader.

After the first build and dependency install, launch directly with `Start-PalworldLiveMap.ps1`.

Useful checks:

```powershell
pnpm test
pnpm check
.\Reader\bin\Release\net8.0-windows\PalworldLiveMap.Reader.exe --self-test
```

## Architecture and privacy

- `electron/main.cjs` owns the desktop window and reader process.
- `electron/preload.cjs` exposes narrow player-telemetry and loaded-entity subscriptions to the renderer.
- `App/` contains the renderer and cannot access Node.js or the filesystem.
- `Reader/` opens Palworld with query/read permissions only.
- No network service is required. The old loopback PowerShell server remains only as a browser test harness.

## Current limitations

- Loaded actors are live game state, not a permanent global database; unloaded locations still require the reference-map datasets.
- Respawn points and any locations that are not represented by loaded Unreal actors remain reference-data-only layers.
- The desktop window does not yet have an always-on-top compact overlay mode.
- A packaged installer and automatic local game-asset extraction are not built yet.
