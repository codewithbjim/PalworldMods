# Quick Connect Manager changelog

## 0.2.0 - 2026-08-05

### Added

- Add gamepad-compatible Add Server and Modify Server forms directly inside the launch panel with editable address, name, and password fields.
- Save successful connections made through Palworld's Join Multiplayer Game screen automatically, using the dedicated server's name for new entries.
- Add the approved Palworld plus, refresh, edit, and garbage textures for server-list actions.

### Changed

- Save manual Add Server entries only after Palworld successfully enters gameplay and generate the lowest available numeric name suffix only for those manual additions.
- Allow every saved server to be modified or removed in game, clear stale metadata when an address changes, and preserve saved world names during every refresh.
- Add controller focus navigation, native controller text entry, Confirm, and Cancel behavior while retaining mouse and keyboard support.
- Use Palworld's native address and password-field archetypes, add the password lock indicator, and reduce the Add and Delete icon sizes.
- Mirror Palworld's server browser by showing per-row ping spinners and updating only player and ping widgets during a normal refresh.
- Block background server actions in QCM while leaving both CommonUI rendering layers enabled, avoiding Palworld's white disabled brushes and applying a dark translucent inactive background.
- Highlight the server row currently being modified with a muted blue disabled background until Confirm or Cancel closes the editor.
- Draw QCM-owned hit-test-invisible backgrounds directly over inactive button bounds so dark and modified-row blue states do not depend on private native widget children.
- Reconcile successful connections from Palworld's Recent Servers after returning to the title screen, including the server name, world GUID, lock state, player count, and ping.

## 0.1.1 - 2026-08-04

### Fixed

- Add vertical scrolling to the three-row launch-screen server viewport so every configured server remains selectable.
- Require an exact client-version match for History rows with invalid ping or player-count data; fully valid rows may differ only in the final build number while retaining the same `X.Y.Z` version.
- Retain version-compatible direct-IP History entries whose live status is unavailable and prefer richer live metadata when Palworld returns duplicate endpoints.

## 0.1.1-hotfix.1 - 2026-08-04

### Fixed

- Target the Workshop `Paks` directory so `QuickConnectManager_UI_P.pak` is installed as a patch PAK under `Pal\Content\Paks\~WorkshopMods\QuickConnectManager` instead of using the individual file as the install target.

## 0.1.0 - 2026-08-04

### Added

- Add a native non-modal Quick Connect panel to Palworld's title screen with server names, player counts, ping, password indicators, refresh, and removal controls.
- Render the lock icon at 27x27 and use larger Refresh and removal icons for clearer title-screen controls.
- Import active recent dedicated servers from Palworld's History list on the first launch and preserve the generated list until Shift+Refresh explicitly resyncs it.
- Connect through Palworld's native join-game flow, including saved password restoration by world GUID and host address.
- Provide Ctrl+Shift+F1 through Ctrl+Shift+F8 shortcuts and `qc` console commands for configured servers.
