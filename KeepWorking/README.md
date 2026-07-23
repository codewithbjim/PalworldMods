# Keep Working

Keep Working preserves an already-started, toggle-based manual workstation job
when Palworld loses focus or the player opens an in-game window with `Esc` or
`Tab`.

## Requirements

- Palworld 1.0 on Windows/Steam.
- Okaetsu's Palworld-specific UE4SS release.
- **Single button press for hold interactions** enabled in Palworld's options.

The mod deliberately does not support the traditional hold-`F` input mode.

## Behavior

1. Start a manual workstation job with `F`.
2. Wait for the player to begin working.
3. Alt-tab, press the Windows key, or open an in-game window.
4. Work continues until the job completes or Palworld terminates it for a
   normal non-input reason.
5. Pressing `F` while Palworld is focused follows the normal cancellation path.

The mod sends no keys and does not change work speed, resources, saves, server
settings, or Pal workers.

## Implementation

The Lua runtime arms only after Palworld accepts a toggle-based action-1 work
interaction. It rewrites that interaction's `EndTriggerInteract` action to
`None` only when either:

- Windows reports a recent foreground-to-background transition, or
- Palworld is foregrounded and the physical `F` key is not down, indicating a
  menu/input-mode cancellation rather than a deliberate `F` cancellation.

A small native DLL provides foreground-transition and physical-key state. It
uses only `KERNEL32.dll` and `USER32.dll`, sends no input, installs no hook,
starts no process, and performs no network access.

## Installation

Exit Palworld, then copy `KeepWorking` into:

```text
Pal\Binaries\Win64\ue4ss\Mods
```

The runtime payload consists of:

```text
KeepWorking/enabled.txt
KeepWorking/Info.json
KeepWorking/Scripts/main.lua
KeepWorking/Scripts/AltTabWorkContinuationFocus.dll
```

A full Palworld restart is required after updating the native DLL.

## Performance design

The retired prototype called `FindAllOf("PlayerController")` indirectly every
100 ms and caused severe FPS loss. This overhaul contains no player lookup,
`FindAllOf`, UObject polling loop, per-frame callback, or recurring game-thread
work. Its interaction hooks run only at lifecycle events. The potentially frequent
UI hook returns before inspecting parameters unless a focus-return gate is pending;
while pending, its normal path performs one native query with no UObject inspection
or log write. The only periodic work is a 100 ms native foreground sample consisting
of `GetForegroundWindow`, `GetWindowThreadProcessId`, and a monotonic timestamp.

## Acceptance test

Compare these cases with the mod disabled and enabled:

1. Idle and normal traversal: FPS and frametime should remain effectively
   unchanged.
2. Start toggle work, alt-tab, wait, and return: work should continue.
3. Start toggle work and open `Tab`: Inventory should open and work continue.
4. Start toggle work and open `Esc`: the menu should open and work continue.
5. Start toggle work and press focused `F`: work should cancel normally.
6. Let a job finish: completion should follow Palworld's normal path.

## Attribution and license

The guarded interaction/focus implementation is adapted from
[Vercadi/Palworld-AltTabWorkContinuation](https://github.com/Vercadi/Palworld-AltTabWorkContinuation),
released under the MIT License. The upstream copyright and license notice are
preserved in `LICENSE`. Keep Working adds focused non-`F` cancellation handling
for intentional in-game windows and adapts the runtime to this repository.
