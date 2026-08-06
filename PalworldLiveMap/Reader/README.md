# External reader probe

This project is a clean-room, read-only interoperability reader for Palworld. It attaches to the gameplay process with Windows query/read permissions, discovers Unreal globals by signature, resolves reflected property offsets, samples the local player's transform, and periodically classifies validated actors from loaded levels. It does not inject code, call into Palworld, write process memory, or modify game files.

## Build and self-test

```powershell
dotnet build .\PalworldLiveMap\Reader\PalworldLiveMap.Reader.csproj -c Release
dotnet run --project .\PalworldLiveMap\Reader\PalworldLiveMap.Reader.csproj -c Release -- --self-test
```

## Live probe

Start Palworld and enter a disposable test world, then run:

```powershell
dotnet run --project .\PalworldLiveMap\Reader\PalworldLiveMap.Reader.csproj -c Release -- --once
```

Omit `--once` to sample continuously at 10 Hz. Use `--interval-ms=250` to choose another bounded interval and press `Ctrl+C` to detach.

Use `--samples=50` for a bounded performance run. The probe prints average, 95th-percentile, and maximum read times before detaching.

Electron starts the compiled reader with `--json-lines`. Player snapshots remain at 10 Hz, while `entities` messages are emitted on a separate throttled interval (`--entity-scan-ms=2000`, allowed range 500–30000 ms). Every standard-output line is an independent JSON telemetry, entity, or status object; human diagnostics are suppressed so the Electron main process can parse the stream safely.

The signatures and reflection layout are version-sensitive. A failed validation must stop the reader; do not weaken validation or guess an address after a Palworld update. External memory readers may be incompatible with future anti-cheat or platform policies, so validate the applicable rules before using or distributing one.
