# Palworld live-map interoperability research

## Palworld 1.0 map assets

- The clean world texture is `Pal/Content/Pal/Texture/UI/Map/T_WorldMap` and exports at 8192×8192.
- Palworld 1.0 has a separate `T_TreeMap` texture, also 8192×8192, with a distinct coordinate transform.
- Dungeon entrances belong on a static location layer. Palworld does not provide a single cave minimap texture; interior layouts are a separate procedural-layout feature.
- Map textures are game assets and remain local-only. The repository stores transforms and an installation pipeline, not the images.
- The current asset dimensions and coordinate calibration were cross-checked against the MIT-licensed `deafdudecomputers/PalworldSaveTools` project; its code and bundled images are not redistributed here.
- The Electron filter hierarchy and displayed reference counts were compared with `palworld.gg/map` on 2026-08-05. The implementation is original and does not use that site's source code, hosted icons, or marker records.
- Sidebar artwork is installed locally from the user's game-data export and remains ignored by Git.

This document records behavioral and metadata observations needed to build an independent live-map reader. It is not a specification of, or source-code substitute for, the inspected Overwolf application. Do not copy or redistribute its binary, JavaScript, map artwork, marker database, private endpoints, or authentication material.

## Inspected version

- Overwolf application: `Palworld` / Palworld Interactive Map, version 2.29.0, by Leon Machens.
- Overwolf extension ID: `ebafpjfhleenmkcmdhlbdchpdalblhiellgfmmbb`.
- Managed plugin assembly: `Palworld.dll`, assembly version 1.0.0.1, 40,448 bytes.
- Plugin SHA-256: `433F5C8C1F4B0AE34D590D642DF3C3A3CB2FD4A9258BF1E2D059C1210FA87AA8`.
- Inspection date: 2026-08-05.

## Verified architecture

The live reader is external to Palworld. It attaches to `Palworld-Win64-Shipping` or `Palworld-Wingdk-Shipping`, scans the main executable module for Unreal global structures, and reads game state with Windows `ReadProcessMemory`. Public plugin methods dispatch their work with `Task.Run`, so sampling does not execute on Palworld's game thread.

The plugin exports three high-level asynchronous operations:

- `GetPlayer(callback, error)`
- `GetActors(types, callback, error)`
- `GetDungeonFloorPlan(callback, error)`

The player result contains an address, actor type, character name, X/Y/Z coordinates, yaw, and map name. Actor results contain an address, type, X/Y/Z coordinates, yaw, discovery state, and map name.

## Process and Unreal discovery

The inspected plugin opens the process with access mask `0x38`, which includes VM operation, VM read, and VM write. Its observed behavior uses reads. An independent implementation should request only the minimum query/read permissions needed and must never write to Palworld memory.

The plugin signature-scans the main module to resolve Unreal globals. The inspected version uses these identifying patterns or anchors:

- FName pool: `74 09 48 8D 15 ? ? ? ? EB 16`
- Global object array: `48 8B 05 ? ? ? ? 48 8B 0C C8 ? 8D 04 D1 EB ?`
- World pointer: a `48 89 05` reference located near the string `    SeamlessTravel FlushLevelStreaming`

The world anchor is stored as UTF-16 in the current executable. Treating it as ASCII causes discovery to fail safely.

After locating the globals, it validates names such as `ByteProperty` and dynamically discovers several reflection-layout offsets instead of assuming every offset remains fixed across builds. Initial layout values observed in the assembly include:

| Structure member | Initial offset |
| --- | ---: |
| UObject outer | `0x20` |
| UObject class | `0x10` |
| UObject name | `0x18` |
| UStruct super | `0x40` |
| UStruct child properties | `0x50` |
| UStruct children | `0x48` |
| FField name | `0x28` |
| FField class | `0x08` |
| FField next | `0x20` |
| FProperty offset | `0x4C` |
| FProperty size | `0x78` |

The dynamic validation uses known Unreal names including `World`, `/Script/Engine`, `Object`, `PersistentLevel`, `NetDriver`, `K2_GetWorldSettings`, `ObjectProperty`, and `StreamingLevelsToConsider`.

## Player traversal

The verified semantic chain is:

```text
GWorld
  -> OwningGameInstance
  -> LocalPlayers[0]
  -> PlayerController
  -> AcknowledgedPawn
  -> RootComponent
  -> RelativeLocation / RelativeRotation
```

Position is read as three doubles and rotation as an Unreal rotator. The player name is reached through `PlayerState -> AcountInitData -> CharacterName` in the inspected build. The spelling `AcountInitData` is the game field spelling observed by the plugin.

The map interface exposes an in-game coordinate transform with scale `459`, X offset `-158000`, and Y offset `123888`, rounded to integers. This appears to be a display-coordinate conversion; raw Unreal coordinates should remain the canonical transport values.

## Actor traversal

Actor sampling walks the world's `Levels` collection and the actor arrays for each level. It obtains an actor's `RootComponent`, `RelativeLocation`, and `RelativeRotation`. It can filter by requested actor class/type names. Observed special handling includes:

- Pal detection through `StaticCharacterParameterComponent -> IsPal`.
- Pal owner/controller filtering involving `Owner` and `MonsterAIController_Otomo`.
- Discovery state for relic objects through `bPickedInClient`.
- Dungeon map selection and coordinate transformation before results are returned.

The map UI requests only the actor categories needed by active filters. A replacement should preserve that demand-driven behavior so broad world scans are avoided when no actor layer is visible.

## Clean-room replacement boundary

The independent implementation should use the observations above only as interoperability facts. Its implementation should be written from scratch with the following boundaries:

1. A separate .NET process attaches read-only to the running Palworld executable.
2. Signature discovery and Unreal reflection walking are independently implemented and covered by fixture tests.
3. Sampling occurs on background threads, with bounded rates and cancellation when the game exits.
4. The latest immutable snapshot is published through a named pipe, memory-mapped file, or loopback WebSocket; no per-sample disk writes are allowed.
5. The UI renders independently sourced map tiles and marker data. It does not embed or proxy the inspected application's website.
6. No Overwolf binary, minified bundle, endpoint credentials, user secrets, map artwork, or marker database is included.

## Recommended first slice

Build a read-only console probe before rebuilding the map UI. It should attach to Palworld, resolve the world pointer, traverse the player chain, and print X/Y/Z/yaw at a bounded rate. Success criteria are stable readings while moving, no measurable game-thread frame-time regression, clean detachment when Palworld exits, and recovery after a game restart. Actor and dungeon scanning should follow only after that probe is reliable.

## Probe validation

The clean-room .NET 8 probe was validated against the Steam `Palworld-Win64-Shipping` process on 2026-08-05. It requested access mask `0x410` (query information plus VM read), scanned the 159.6 MiB main module in 0.37–0.52 seconds, validated FName index 3 as `ByteProperty`, resolved the current FName pool and world pointer, dynamically resolved the player-chain property offsets, and returned live X/Y/Z/yaw values.

A bounded 50-sample run at 10 Hz completed without read errors. Including the first cold reflection traversal, average read time was 0.546 ms, 95th-percentile time was 1.150 ms, and maximum time was 17.493 ms. Warm cached reads were generally 0.04–0.07 ms. These measurements cover the external reader only and do not yet include actor scanning or UI transport.

## Open questions

- Confirm signatures against both the Steam and WinGDK executables after each Palworld update.
- Determine the minimal process query access supported on all target Windows versions.
- Independently validate the Unreal reflection walker against generated UE4SS headers or the installed mapping file.
- Establish a lawful, redistributable source for map tiles and marker metadata.
- Measure safe actor scan frequency and maximum per-cycle work before enabling large marker layers.
