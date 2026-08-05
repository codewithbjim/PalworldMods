# Quick Connect Manager pre-deploy checklist

Complete this checklist against the exact Nexus archive and Workshop directory that will be uploaded. A release is blocked if a required item fails or cannot be explained.

## 1. Prepare the candidate

- [ ] Confirm Palworld is closed before replacing installed runtime files.
- [ ] Update the Nexus/source and staged Workshop manifests to `0.2.0-hotfix.1` and align each channel's changelog and publishing metadata.
- [ ] Confirm `thumbnail.png` is under 1 MB and `NEXUS_IMAGE.png` is the approved full-resolution gallery image.
- [ ] Verify the unchanged cooked window-shell PAK against its checked-in checksum; rebuild it only if the cooked asset changes.
- [ ] Build the Nexus archive with `Release/QuickConnectManager/build-release.ps1`.
- [ ] Build a clean Workshop directory with `Release/QuickConnectManager/build-workshop-package.ps1`.
- [ ] Run `Release/QuickConnectManager/Test-Release.ps1 -Version 0.2.0-hotfix.1 -WorkshopVersion 0.2.0-hotfix.1` against the final archive and Workshop directory.
- [ ] Parse every shipped Lua file with Lua 5.3 or 5.4 syntax rules and execute all deterministic tests under `QuickConnectManager/tests`.
- [ ] Confirm the release archive and Workshop directory contain no `discovery_cache.lua`, `.bak`, `.tmp`, `.previous`, test fixture, real server address, world GUID, or saved password.
- [ ] Confirm the candidate commit contains only intended release changes and uses `virtualbjörn` with the repository noreply address in Git metadata.

## 2. Clean manual-install test

- [ ] Use a clean Palworld installation or temporarily move the existing QuickConnectManager folder and UI PAK.
- [ ] Extract the Nexus archive into the Palworld folder containing `Pal`.
- [ ] Confirm the Nexus Lua payload installs to `Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager` and its PAK installs to `Pal\Content\Paks\~mods`.
- [ ] Confirm UE4SS loads Quick Connect Manager once without Lua errors, callback-GC warnings, or package-load spam.
- [ ] Confirm the panel appears on the initial title screen without opening Join Multiplayer Game.
- [ ] Confirm startup logs complete one History status and stock server-row ping pass before the first "Quick Connect launch panel opened" entry.
- [ ] Confirm the normal title menu remains clickable and the Quick Connect panel is not modal.
- [ ] Confirm the panel hides while the stock mod disclaimer is visible and returns exactly once after it closes.
- [ ] Repeat with the installed disclaimer-suppression mod and confirm Quick Connect still appears exactly once.

## 3. First-install discovery and configuration

- [ ] Start with the default disabled fixture and no discovery cache, then confirm one History discovery runs and only active compatible recent servers are retained.
- [ ] Confirm the generated `config.lua` contains server name, address, world GUID, password-required state, and a Palworld-saved password when available.
- [ ] Confirm `discovery_cache.lua` contains no plaintext password.
- [ ] Relaunch at least three times and confirm automatic discovery does not run again after the initial list is populated.
- [ ] Select normal Refresh and confirm it updates status and credentials without replacing or rediscovering the configured list.
- [ ] Confirm normal Refresh and Shift+Refresh preserve every matching saved world name.
- [ ] Change network conditions or query at several intervals and confirm Refresh does not reuse an identical construction-time ping snapshot when Palworld reports a new value.
- [ ] Confirm each Refresh logs completion or a bounded timeout for Palworld's stock server-row ping operations and never leaves a pending ping batch alive.
- [ ] Hold either Shift key while selecting Refresh and confirm one forced discovery replaces the automatically managed list.
- [ ] Remove a discovered server, refresh, and confirm it stays removed; force-sync and confirm the documented resync behavior.
- [ ] Interrupt or deny a config/cache write in a disposable copy and confirm the active file remains valid or is restored from the recoverable replacement.

## 4. Connection and title-return stress

- [ ] Connect to an available server without a password and confirm travel succeeds.
- [ ] Add a server through the integrated editor and confirm it is absent from `config.lua` before travel and present only after successful gameplay entry.
- [ ] Add another server with the same requested name and confirm only the manual addition receives the lowest available numeric suffix.
- [ ] Join a new server through Palworld's stock Join Multiplayer Game screen and confirm the dedicated server name is saved exactly without a generated suffix.
- [ ] Modify address, name, and password in game; confirm an address change clears stale world GUID and status metadata while a name-only change preserves metadata.
- [ ] Confirm a launch-panel row click reaches Palworld's native join flow without relying on an EngineTick-delayed connection callback.
- [ ] Connect to a password-protected server with a Palworld-saved password and confirm no "No password has been entered" dialog appears.
- [ ] Test an unavailable server, wrong password, version mismatch, and timeout; dismiss each dialog and confirm the panel returns exactly once when the main menu becomes visible.
- [ ] Repeat failed connection and title return at least 20 times while alternating servers.
- [ ] Confirm the panel hides immediately after selecting a server and never duplicates during the connection attempt.
- [ ] Confirm lock, Add, Refresh, Modify, and garbage textures remain rendered after every error dialog and panel rebuild.
- [ ] Open Join Multiplayer Game, return to the title page, and repeat at least 10 times; confirm one panel and one action per click.
- [ ] Enter a local world, return to title, join a server, disconnect, and return to title; confirm the panel reappears once after each transition.

## 5. Refresh and UI re-render stress

- [ ] Select Refresh at least 20 consecutive times, waiting for each result, and confirm player counts and ping update without duplicate requests.
- [ ] Rapidly select Refresh during an active request and confirm additional requests are ignored without callback or widget errors.
- [ ] Confirm server rows, removal buttons, console connects, and hotkeys are ignored while REFRESHING, then become available after completion or failure.
- [ ] Leave and return to the title screen during a refresh; confirm no panel attaches to an obsolete title widget and no late ping result is published twice.
- [ ] Alternate Refresh and Shift+Refresh for at least 10 completed cycles.
- [ ] Remove rows before and after refreshes and confirm the separate garbage control never triggers the server-row connection action.
- [ ] Navigate Add, Refresh, every row action, all three fields, Confirm, and Cancel with D-pad and left stick; confirm controller text entry, focus scrolling, and focus restoration.
- [ ] Confirm long server names clip cleanly, hints remain fully visible, and no invalid metadata reaches the panel.
- [ ] Confirm the panel shows three rows at a time and vertical scrolling reaches every additional enabled entry.
- [ ] Review UE4SS.log and confirm each render produces one "Quick Connect launch panel opened" entry rather than multiple entries for the same visible panel.

## 6. Regular-gameplay soak

- [ ] Record a frame-time baseline with the mod disabled, then remain in regular gameplay with the candidate enabled for at least 30 minutes.
- [ ] Confirm no Quick Connect widget appears in gameplay, pause menus, construction UI, inventory, map, or loading screens.
- [ ] Travel, die and respawn, open menus, build, fast travel, and return to title without a crash, access violation, callback-GC warning, or recurring log flood.
- [ ] Confirm no launch-UI lifecycle timer remains scheduled during gameplay, connection confirmation stops on the first valid non-title world/controller, and gameplay-origin network events do not start polling.
- [ ] Use UE4SS Restart All Mods once on the title screen and once in a disposable gameplay session; confirm callbacks are reclaimed cleanly and the next title render contains one panel.

## 7. Workshop candidate

- [ ] Place the staged package in a disposable Workshop content directory and confirm `Info.json`, `Scripts`, `Paks`, and `thumbnail.png` are recognized by Palworld Mod Uploader.
- [ ] Confirm the Lua InstallRule installs to `Mods\NativeMods\UE4SS\Mods\QuickConnectManager`.
- [ ] Confirm the Paks InstallRule installs `QuickConnectManager_UI_P.pak` to `Pal\Content\Paks\~WorkshopMods\QuickConnectManager`.
- [ ] Enable the Workshop candidate under Options > Mod Management and repeat the initial title, one refresh, one successful connection, and one failed connection test.
- [ ] Confirm updating the Workshop version replaces runtime files but preserves the installed user's `config.lua` behavior expected by Palworld's official loader.

## 8. Evidence and acceptance

| Field | Result |
| --- | --- |
| Nexus version | |
| Workshop version | |
| Commit | |
| Annotated tag | |
| Nexus archive SHA-256 | |
| Workshop payload hashes verified | Yes / No |
| Palworld build | |
| UE4SS Experimental build | |
| Manual install tested | Yes / No |
| Workshop install tested | Yes / No |
| Gameplay soak duration | |
| UE4SS log reviewed | Yes / No |
| Failures or waivers | |

Release acceptance requires:

- [ ] No crash, hang, native access violation, duplicate panel, stuck refresh, or unrecoverable missing panel.
- [ ] No unexpected Lua error, callback-GC warning, stale-object access, or repeating error flood.
- [ ] Password-protected and unprotected connections both pass.
- [ ] Failed connections and all tested title transitions restore exactly one panel.
- [ ] Automated release gate passes against the exact final archive and Workshop directory.
- [ ] The final release commit is verified on `origin/main` and tagged with the annotated `quick-connect-manager-v0.2.0-hotfix.1` source tag.

## 9. Publish safely

- [ ] Upload the SHA-256-verified Nexus archive without rebuilding it and confirm the version changelog is at most 255 characters.
- [ ] Upload the already tested Workshop directory without restaging it and use `WORKSHOP_CHANGELOG.txt` for change notes.
- [ ] Verify the published Nexus download and subscribed Workshop payload against the local candidate hashes.
- [ ] Push the verified `main` release commit and annotated tag, then confirm the tag resolves to the published source commit.
