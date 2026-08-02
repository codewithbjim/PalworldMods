# Perfect Placement pre-deploy checklist

Complete this checklist against the exact Nexus archive and Workshop package that will be uploaded. A release is blocked if any required item fails or cannot be explained.

## 1. Prepare the candidate

- [ ] Use a disposable test world or a verified backup.
- [ ] Update `Info.json`, DarnMenu schema version, load-time version logging, changelogs, release readme, and publishing-script defaults.
- [ ] Confirm every prose paragraph and list item in release text files occupies one physical line unless its layout is intentionally preformatted.
- [ ] Build the Nexus archive with `Release/build-release.ps1`.
- [ ] Build a clean Workshop candidate:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\Release\build-workshop-package.ps1 `
    -Destination .\Release\Dist\Workshop-<version> `
    -Version <version>
  ```

- [ ] Run the automated release gate and confirm the Lua 5.4 scheduler stress suite passes:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\Release\Test-Release.ps1 `
    -Version <version>
  ```

- [ ] Validate every Lua file with Lua 5.4 `luac -p` or an equivalent parser. Use `-RequireLuaCompiler` above when `luac` is installed.
- [ ] Confirm the candidate commit contains only intended release changes.
- [ ] Confirm `git status --short` is clean before tagging.

## 2. Clean-install smoke test

- [ ] Close Palworld completely before replacing files.
- [ ] Remove or temporarily rename the previously installed Perfect Placement Lua folder, legacy LogicMod pak, and NativeUI pak so stale modules cannot influence the test.
- [ ] Extract the candidate archive into the game directory.
- [ ] Confirm UE4SS loads the expected version without Lua errors.
- [ ] Open a disposable world, enter build mode, and display a preview.
- [ ] Confirm `PerfectPlacement_NativeUI_P.pak` is loaded and the frozen and unfrozen guides appear inside Palworld's construction widget.
- [ ] Confirm no `PerfectPlacement.pak` remains under `Pal\Content\Paks\LogicMods` and the log reports that the companion input bridge spawned from the consolidated `_P.pak`.
- [ ] Confirm the unfrozen guide shows Freeze, Copy Piece, and Copy and Freeze as soon as a live preview exists.
- [ ] Confirm the frozen guide shows horizontal movement, height, rotation, current step, Reset, and Unfreeze with native-sized keyboard or gamepad keycaps.
- [ ] Confirm Build, Back to Build Menu, and Quit building remain visible while Rotate, Axis Alignment, and Replacement Mode consume no row space only while frozen.
- [ ] Repeat Freeze and Unfreeze at least 20 times and confirm stock rows return in their original order without duplicates, empty slots, or progressive spacing changes.
- [ ] Open DarnMenu and the ESC menu during construction and confirm no crash occurs; the release must not contain a global UMG `SetVisibility` hook.

## 3. Freeze lifecycle stress test

- [ ] Freeze a preview and leave all controls untouched for at least two minutes. Confirm it remains frozen, frame pacing stays even, and no recurring lifecycle work or `Auto-releasing frozen preview` entry appears in `UE4SS.log`.
- [ ] Freeze and Unfreeze normally at least 20 consecutive times.
- [ ] Rapidly press Freeze for at least 10 seconds. Only one transition should occur at a time, with no crash or stuck preview.
- [ ] Press movement, rotation, reset, step-up, and step-down repeatedly during the first second after Freeze.
- [ ] Repeat the previous test during Unfreeze.
- [ ] Hold `Ctrl`, `Alt`, and `Ctrl+Alt` while repeatedly using the default middle-mouse Freeze binding.
- [ ] Spam movement, rotation, Reset, validity changes, and Copy and Freeze for 30 seconds. Then Unfreeze and Freeze again; controls must respond and the log must have no EngineTick exception, callback-ref error, hook removal, or access violation.
- [ ] Confirm the preview never becomes permanently frozen, duplicated, invisible, detached from Palworld control, or impossible to place.

## 4. Transform-control stress test

- [ ] Move in all six directions at every supported movement step.
- [ ] Rotate left and right through at least one complete 360-degree cycle.
- [ ] Rotate High Quality Hot Spring through a complete 360-degree cycle while frozen and confirm its Palworld install point remains fixed.
- [ ] Alternate movement and rotation rapidly for at least 30 seconds.
- [ ] Spam Reset while alternating movement and rotation.
- [ ] Verify the vertical lower and upper clamps.
- [ ] With live frozen-validity feedback at its default On setting, move a frozen preview blue -> red -> blue and confirm the warning follows the placeable state.
- [ ] Disable live frozen-validity feedback, relaunch, then spam movement, rotation, and Reset across validity boundaries and confirm the refresh stays disabled.
- [ ] While live feedback is enabled, confirm the object remains at the exact user-controlled transform and monitor frame pacing while spamming movement.
- [ ] Confirm no repeated error floods appear in the UE4SS log.

## 5. Palworld lifecycle interactions

- [ ] Freeze, then press Escape. Confirm the Perfect Placement guide and toast disappear within one second and remain hidden during normal gameplay.
- [ ] Freeze, then open and close the build menu. Confirm no frozen or unfrozen control menu remains after construction mode closes.
- [ ] Return to construction after each exit test and confirm the unfrozen guide appears only when a live placement preview exists.
- [ ] Hold an unfrozen preview for at least two minutes while moving the camera, rotating, and changing pieces; confirm frame pacing remains stable and the companion guide never hides and reappears.
- [ ] Freeze, then select a different build piece.
- [ ] Freeze, then place the current piece through Palworld's normal path.
- [ ] Freeze, then cancel or destroy the active preview.
- [ ] Leave the world while frozen, load another world, and repeat.
- [ ] Return to the title screen and reload the same world at least three times.
- [ ] Quit the game while frozen and confirm the next launch is healthy.

## 6. Copy and DarnMenu binding tests

- [ ] Copy a different build piece with the eyedropper.
- [ ] Attempt to copy while Freeze or Unfreeze is settling.
- [ ] Use `Ctrl+Shift+Middle Mouse` on a piece matching the active preview. Confirm the preview moves to the targeted piece's location and rotation, freezes there, and Reset returns to that captured transform.
- [ ] Repeat copy-and-freeze while targeting a different piece type. Confirm the replacement preview is created before it moves or freezes.
- [ ] Copy-and-freeze pieces with non-zero yaw in several orientations and confirm no checker/preview snap offset is applied twice.
- [ ] Rapidly spam copy-and-freeze for at least 10 seconds. Confirm only one switch transaction runs at a time and no stale preview is frozen.
- [ ] Aim at empty space and non-build actors, then use copy-and-freeze. Confirm it fails cleanly without changing the active preview.
- [ ] Confirm a copied preview overlapping the source is marked invalid, then move it clear and verify it becomes valid.
- [ ] Confirm the DarnMenu Preview section and bundled companion guide both show the configured copy-and-freeze chord.
- [ ] Change every configurable binding once and reopen the world.
- [ ] Test a binding with each supported modifier and one multi-modifier chord.
- [ ] Confirm the page appears under `ESC → Mod Options` with DarnMenu 1.6.2+ and every control uses the native keychord editor.
- [ ] Confirm changes are written to `Mods/shared/PerfectPlacement_user.lua` and apply after relaunch.
- [ ] Change each exposed movement setting, relaunch, and confirm the guide and transform controls use the saved values.
- [ ] Verify DarnMenu rejects out-of-range numeric values and Perfect Placement rejects invalid values placed into the shared file by hand.
- [ ] Set movement minimum above maximum by hand and confirm both limits safely fall back to `config.lua` with one clear log message.
- [ ] Toggle verbose logging, relaunch, and confirm the saved value applies.
- [ ] Toggle live frozen-validity feedback, relaunch, and confirm the saved value applies; verify a missing saved value keeps the feature On.
- [ ] Temporarily move `Mods/shared/PerfectPlacement_user.lua`, remove or disable both DarnMenu and DarnUI, and confirm Perfect Placement starts without a missing-dependency or Lua error and uses `Scripts/config.lua` defaults.
- [ ] Restore the saved player override while DarnMenu and DarnUI remain disabled, then confirm Perfect Placement loads the override without requiring either optional mod.
- [ ] Test NumLock on and off for Numpad 1/3.
- [ ] Check for conflicts with UE4SS `Keybinds` and other installed mods.
- [ ] Confirm configured keycaps and action labels refresh correctly.
- [ ] Reopen construction mode and reload the world repeatedly; confirm each control fires once per keypress and the log contains only one Perfect Placement startup line.

## 7. Gamepad integration

Record `Pass`, `Fail`, or `N/A` for each row. A supported controller release cannot use `N/A` for the default-control rows.

| Scenario | Result |
| --- | --- |
| L3 freezes and unfreezes exactly once per press | |
| L3 + D-pad Down copies without also firing plain L3 | |
| L3 + D-pad Up copies the targeted transform and freezes without also firing plain L3 | |
| Plain D-pad moves in all four horizontal directions while frozen | |
| LT + D-pad Up/Down moves vertically and LT + D-pad Left/Right changes the step | |
| LB/RB rotates and R3 resets while frozen | |
| RT and LT+RT D-pad chords dispatch correctly after temporary `config.lua` remapping | |
| Direction inversion and rotation-button swapping match both behavior and guide icons after relaunch | |
| Disabling gamepad support keeps the keyboard guide available and prevents controller capture | |
| Leaving the controller idle for five minutes produces no recurring Lua gamepad work or rhythmic stutter | |
| Rapid controller movement, rotation, reset, Freeze, and Unfreeze input does not duplicate actions or remove a hook | |
| Recreating the guide or reloading a world does not replay old serial counters | |
| Alternating mouse and controller input refreshes the displayed device guide once per device change rather than once per axis event | |

- [ ] Confirm each physical press produces one `QueueGamepadPhysicalInput` callback and one guarded Lua action.
- [ ] Inspect the compiled ModActor `ReceiveEndPlay` graph and confirm the two `Destroy Actor` Target pins are `UnfrozenInputActor` and `FrozenInputActor`, never `Self`.
- [ ] Confirm the UE4SS log has no incomplete-hook, callback-GC, `Ref was not function`, or repeated gamepad error.

## 8. Soak and compatibility

- [ ] Record a frame-time baseline for at least five minutes with Perfect Placement disabled, then repeat outside construction mode with the candidate enabled. Confirm there is no rhythmic hitch near 500 ms intervals.
- [ ] Remain in construction mode with an unfrozen preview for five minutes, then repeat while frozen. Confirm there is no repeating frame-time spike.
- [ ] Enter and exit construction mode at least 20 times and travel or reload the world. Confirm the guide still follows the current live widget without periodic UObject-scan stutter.
- [ ] Temporarily enable `diagnostics.ui_lifecycle_counters`, confirm repeated Setup callbacks produce no additional mode transitions, host acquisitions, or hide/show calls after convergence, then restore the default `false` value before rebuilding.
- [ ] With lifecycle counters enabled, repeatedly enter and leave construction mode and confirm child key-guide Destruct events are counted but only the top-level construction root transitions the companion guide to hidden.
- [ ] Remain in construction mode and edit pieces continuously for 10 minutes.
- [ ] Watch frame time and confirm there is no progressive slowdown.
- [ ] Review the complete UE4SS log for errors, stale-object warnings, or rapidly repeated messages.
- [ ] Test host and client behavior if multiplayer support is claimed.
- [ ] Test a dedicated server if dedicated-server support is claimed.

## 9. Evidence and acceptance

Record the result before publishing:

| Field | Result |
| --- | --- |
| Version | |
| Commit | |
| Annotated tag | |
| Archive SHA-256 | |
| Palworld build | |
| UE4SS build | |
| Test world | |
| Keyboard/mouse | |
| Controller | Required for 0.3.0-alpha.1 |
| Tester | |
| Date | |
| UE4SS log reviewed | Yes / No |
| Failures or waivers | |

Release acceptance requires:

- [ ] No crash, hang, native access violation, or unrecoverable frozen state.
- [ ] No unexpected Lua errors or repeating error floods.
- [ ] Every advertised control and lifecycle interaction passes.
- [ ] Automated release gate passes against the final archive.
- [ ] The release commit is tagged with an annotated `<package-name>-v<version>` tag.
- [ ] The tag resolves to the exact candidate commit.

## 10. Publish safely

- [ ] Run the Nexus uploader in dry-run mode and confirm the candidate ZIP remains present with the same SHA-256 afterward.
- [ ] Confirm the dry run targets the intended mod, existing file, version, category, archive, description, and version changelog.
- [ ] Publish the same SHA-256-verified archive without rebuilding it.
- [ ] Confirm Nexus reports the new release as the current mod version instead of leaving the previous version current.
- [ ] Confirm the published Nexus version changelog matches `NEXUS_VERSION_CHANGELOG.txt` and was not appended twice.
- [ ] Push the release commit and annotated tag.
- [ ] Download the published file once and compare its SHA-256 or extracted payload hashes with the local candidate.
