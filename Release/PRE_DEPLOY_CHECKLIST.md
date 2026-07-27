# Perfect Placement pre-deploy checklist

Complete this checklist against the exact Nexus archive and Workshop package
that will be uploaded. A release is blocked if any required item fails or
cannot be explained.

## 1. Prepare the candidate

- [ ] Use a disposable test world or a verified backup.
- [ ] Update `Info.json`, DarnMenu schema version, load-time version logging,
      changelogs, release readme, and publishing-script defaults.
- [ ] Build the Nexus archive with `Release/build-release.ps1`.
- [ ] Build a clean Workshop candidate:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\Release\build-workshop-package.ps1 `
    -Destination .\Release\Dist\Workshop-<version> `
    -Version <version>
  ```

- [ ] Run the automated release gate:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\Release\Test-Release.ps1 `
    -Version <version>
  ```

- [ ] Validate every Lua file with Lua 5.3 `luac -p` or an equivalent parser.
      Use `-RequireLuaCompiler` above when `luac` is installed.
- [ ] Confirm the candidate commit contains only intended release changes.
- [ ] Confirm `git status --short` is clean before tagging.

## 2. Clean-install smoke test

- [ ] Close Palworld completely before replacing files.
- [ ] Remove or temporarily rename the previously installed Perfect Placement
      Lua folder and PAK so stale modules cannot influence the test.
- [ ] Extract the candidate archive into the game directory.
- [ ] Confirm UE4SS loads the expected version without Lua errors.
- [ ] Open a disposable world, enter build mode, and display a preview.
- [ ] Confirm the frozen and unfrozen guides show the expected bindings.

## 3. Freeze lifecycle stress test

- [ ] Freeze and Unfreeze normally at least 20 consecutive times.
- [ ] Rapidly press Freeze for at least 10 seconds. Only one transition should
      occur at a time, with no crash or stuck preview.
- [ ] Press movement, rotation, reset, step-up, and step-down repeatedly during
      the first second after Freeze.
- [ ] Repeat the previous test during Unfreeze.
- [ ] Hold `Ctrl`, `Alt`, and `Ctrl+Alt` while repeatedly using the default
      middle-mouse Freeze binding.
- [ ] Move vertically for at least 30 seconds, then Unfreeze and Freeze again.
      Confirm controls still respond and the UE4SS log has no `Ref was not
      function`, `removing hook`, or invalid-callback cleanup message.
- [ ] Confirm the preview never becomes permanently frozen, duplicated,
      invisible, detached from Palworld control, or impossible to place.

## 4. Transform-control stress test

- [ ] Move in all six directions at every supported movement step.
- [ ] Rotate left and right through at least one complete 360-degree cycle.
- [ ] Alternate movement and rotation rapidly for at least 30 seconds.
- [ ] Spam Reset while alternating movement and rotation.
- [ ] Verify the vertical lower and upper clamps.
- [ ] Freeze a valid preview, move it into an invalid area, then move it clear.
      Confirm the mesh changes blue -> red -> blue and the warning matches each
      state without Unfreezing.
- [ ] Repeat starting from an invalid preview. Confirm the object remains at
      the exact user-controlled transform during every validity repaint.
- [ ] Spam movement, rotation, and Reset across a validity boundary. Confirm
      refreshes coalesce, the builder never retargets toward the camera, and
      the preview does not remain red after the result becomes valid.
- [ ] Confirm no repeated error floods appear in the UE4SS log.

## 5. Palworld lifecycle interactions

- [ ] Freeze, then press Escape. Confirm the Perfect Placement guide and toast
      disappear within one second and remain hidden during normal gameplay.
- [ ] Freeze, then open and close the build menu. Confirm no frozen or unfrozen
      control menu remains after construction mode closes.
- [ ] Return to construction after each exit test and confirm the unfrozen guide
      appears only when a live placement preview exists.
- [ ] Freeze, then select a different build piece.
- [ ] Freeze, then place the current piece through Palworld's normal path.
- [ ] Freeze, then cancel or destroy the active preview.
- [ ] Leave the world while frozen, load another world, and repeat.
- [ ] Return to the title screen and reload the same world at least three times.
- [ ] Quit the game while frozen and confirm the next launch is healthy.

## 6. Copy and DarnMenu binding tests

- [ ] Copy a different build piece with the eyedropper.
- [ ] Attempt to copy while Freeze or Unfreeze is settling.
- [ ] Use `Ctrl+Shift+Middle Mouse` on a piece matching the active preview.
      Confirm the preview moves to the targeted piece's location and rotation,
      freezes there, and Reset returns to that captured transform.
- [ ] Repeat copy-and-freeze while targeting a different piece type. Confirm
      the replacement preview is created before it moves or freezes.
- [ ] Copy-and-freeze pieces with non-zero yaw in several orientations and
      confirm no checker/preview snap offset is applied twice.
- [ ] Rapidly spam copy-and-freeze for at least 10 seconds. Confirm only one
      switch transaction runs at a time and no stale preview is frozen.
- [ ] Aim at empty space and non-build actors, then use copy-and-freeze.
      Confirm it fails cleanly without changing the active preview.
- [ ] Confirm a copied preview overlapping the source is marked invalid, then
      move it clear and verify it becomes valid.
- [ ] Confirm the DarnMenu Preview section exposes the copy-and-freeze chord.
      The bundled companion guide has no separate row for this action.
- [ ] Change every configurable binding once and reopen the world.
- [ ] Test a binding with each supported modifier and one multi-modifier chord.
- [ ] Confirm the page appears under `ESC → Mod Options` with DarnMenu 1.6.2+
      and every control uses the native keychord editor.
- [ ] Confirm changes are written to
      `Mods/shared/PerfectPlacement_user.lua` and apply after relaunch.
- [ ] Change each exposed movement setting, relaunch, and confirm the guide and
      transform controls use the saved values.
- [ ] Verify DarnMenu rejects out-of-range numeric values and Perfect Placement
      rejects invalid values placed into the shared file by hand.
- [ ] Set movement minimum above maximum by hand and confirm both limits safely
      fall back to `config.lua` with one clear log message.
- [ ] Toggle verbose logging, relaunch, and confirm the saved value applies.
- [ ] Remove or disable DarnMenu and confirm Perfect Placement safely falls
      back to `Scripts/config.lua` without a Lua error.
- [ ] Test NumLock on and off for Numpad 1/3.
- [ ] Check for conflicts with UE4SS `Keybinds` and other installed mods.
- [ ] Confirm configured keycaps and action labels refresh correctly.
- [ ] Reopen construction mode and reload the world repeatedly; confirm each
      control fires once per keypress and the log contains only one Perfect
      Placement startup line.

## 7. Soak and compatibility

- [ ] Record a frame-time baseline for at least five minutes with Perfect
      Placement disabled, then repeat outside construction mode with the
      candidate enabled. Confirm there is no rhythmic hitch near 500 ms
      intervals.
- [ ] Remain in construction mode with an unfrozen preview for five minutes,
      then repeat while frozen. Confirm there is no repeating frame-time spike.
- [ ] Enter and exit construction mode at least 20 times and travel or reload
      the world. Confirm the guide still follows the current live widget without
      periodic UObject-scan stutter.
- [ ] Remain in construction mode and edit pieces continuously for 10 minutes.
- [ ] Watch frame time and confirm there is no progressive slowdown.
- [ ] Review the complete UE4SS log for errors, stale-object warnings, or
      rapidly repeated messages.
- [ ] Test host and client behavior if multiplayer support is claimed.
- [ ] Test a dedicated server if dedicated-server support is claimed.

## 8. Evidence and acceptance

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
| Controller | N/A unless supported |
| Tester | |
| Date | |
| UE4SS log reviewed | Yes / No |
| Failures or waivers | |

Release acceptance requires:

- [ ] No crash, hang, native access violation, or unrecoverable frozen state.
- [ ] No unexpected Lua errors or repeating error floods.
- [ ] Every advertised control and lifecycle interaction passes.
- [ ] Automated release gate passes against the final archive.
- [ ] The release commit is tagged with an annotated
      `<package-name>-v<version>` tag.
- [ ] The tag resolves to the exact candidate commit.

## 9. Publish safely

- [ ] Run the Nexus uploader in dry-run mode and confirm the candidate ZIP
      remains present with the same SHA-256 afterward.
- [ ] Confirm the dry run targets the intended mod, existing file, version,
      category, archive, and description.
- [ ] Publish the same SHA-256-verified archive without rebuilding it.
- [ ] Push the release commit and annotated tag.
- [ ] Download the published file once and compare its SHA-256 or extracted
      payload hashes with the local candidate.
