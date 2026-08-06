# Palworld Server Control - WebView2

This is the maintained Palworld Server Control client. It uses React, TypeScript, Tailwind CSS v4, shadcn-style components, and Lucide icons hosted in Microsoft Edge WebView2.

## Security boundary

The web UI can call exactly three typed operations: `snapshot.load`, `settings.save`, and `command.send`. The native host validates bridge envelopes, metadata keys, field values, expected file hashes, and the fixed `start`, `stop`, `restart`, and `status` command set. It exposes no host objects and no arbitrary filesystem, shell, PowerShell, or process execution.

The WebView is restricted to the packaged `https://palworld-control.local` virtual origin. External navigation, popups, permissions, DevTools, context menus, browser accelerators, autofill, password saving, and external drops are disabled.

## Build and test

Prerequisites are Node.js with pnpm, the .NET 8 SDK, and the Microsoft Edge WebView2 Evergreen Runtime.

```powershell
pnpm install
pnpm test
pnpm typecheck
pnpm build:web
dotnet run --project host/tests/PalworldServerControl.Host.Tests.csproj -c Release
dotnet publish host/PalworldServerControl.Host.csproj -c Release -r win-x64 --self-contained false -o release/single-file
```

Run `release/single-file/PalworldServerControl.exe`. The publish is a single distributable executable: the native loader, web assets, metadata, and helper installer are bundled and extracted into .NET's per-user bundle cache at launch. On first launch, select a local folder or enter a network share in the **Connection** screen. Automated environments can instead use `--share-root=<path>` or `PALSERVER_SHARE_ROOT`. Use `--screenshot=<png-path>` for packaged-app visual QA.

The framework-dependent package intentionally uses the installed .NET 8 Desktop Runtime and installed WebView2 Evergreen Runtime to keep the distributed application small.
