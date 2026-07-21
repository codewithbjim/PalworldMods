# Perfect Placement key-guide Blueprint

This companion Logic Mod renders keyboard/mouse and gamepad key guides. It
does not depend on Common Input. `ModActor` detects the most recently used
device with ordinary Blueprint input events and tells the widget which guide
to display. Lua owns placement state and calls the widget's public API.

## Assets

Use these exact assets under `Content/Mods/PerfectPlacement/`:

- `WBP_PerfectPlacement_KeyGuide` — User Widget
- `ModActor` — Actor Blueprint used as the Logic Mod entry point

Import the required key-guide textures under
`Content/Mods/PerfectPlacement/UI/Icons/`. For each texture use UI texture
group, UserInterface2D (RGBA), sRGB enabled, no mipmaps, clamp X/Y, and Never
Stream. Keep the original dimensions.

## Widget hierarchy

Create this hierarchy in `WBP_PerfectPlacement_KeyGuide`:

```text
CanvasPanel (Root)
├─ Border: GuidePanel
│  └─ VerticalBox: GuideContent
│     ├─ TextBlock: TitleText
│     └─ WidgetSwitcher: GuideStateSwitcher
│        ├─ VerticalBox: UnfrozenGuide                 [index 0]
│        │  └─ WidgetSwitcher: UnfrozenInputSwitcher
│        │     ├─ VerticalBox: KeyboardUnfrozenGuide  [index 0]
│        │     │  ├─ HorizontalBox: FreezeRow         [MMB] Freeze
│        │     │  └─ HorizontalBox: CopyRow           [Alt]+[MMB] Copy
│        │     └─ VerticalBox: GamepadUnfrozenGuide   [index 1]
│        │        ├─ HorizontalBox: FreezeRow         [R3] Freeze
│        │        └─ HorizontalBox: CopyRow           [Y] Copy
│        └─ VerticalBox: FrozenGuide                   [index 1]
│           └─ WidgetSwitcher: FrozenInputSwitcher
│              ├─ VerticalBox: KeyboardFrozenGuide    [index 0]
│              │  ├─ HorizontalBox: MoveRow           [Num 8/2/4/6] Move
│              │  ├─ HorizontalBox: RotateRow         [Num 7/9] Rotate
│              │  ├─ HorizontalBox: StepRow           [Num -/+] Step
│              │  ├─ HorizontalBox: ResetRow          [Num 5] Reset
│              │  └─ HorizontalBox: UnlockRow         [MMB] Unlock
│              └─ VerticalBox: GamepadFrozenGuide     [index 1]
│                 ├─ HorizontalBox: MoveRow           [D-pad] Move
│                 ├─ HorizontalBox: RotateRow         [LB][RB] Rotate
│                 ├─ HorizontalBox: StepRow           [LT]+[D-pad LR] Step
│                 ├─ HorizontalBox: ResetRow          [L3] Reset
│                 └─ HorizontalBox: UnlockRow         [R3] Unlock
└─ Border: ToastPanel
   └─ TextBlock: ToastText
```

Each bracketed key is an Image widget followed by a Text Block label. Mark
`GuidePanel`, all three switchers, `KeyboardStepLabel`, `GamepadStepLabel`,
`ToastPanel`, and `ToastText` as variables. Child order determines every
switcher index shown above.

Set the root to Not Hit-Testable (Self & All Children). Anchor `GuidePanel`
bottom-center and `ToastPanel` top-center. Start both panels Collapsed.

## Widget variables

Create:

- Public Float `MoveStepCm`, default `10.0`
- Private Boolean `bUsingGamepad`, default `false`
- Private Boolean `bGuideFrozen`, default `false`

## Widget functions

### `RefreshInputGuide`

Select integer `1` when `bUsingGamepad` is true, otherwise `0`. Call Set Active
Widget Index with that value on both `UnfrozenInputSwitcher` and
`FrozenInputSwitcher`.

### `SetUsingGamepad`

Add Boolean input `UsingGamepad`. If it differs from `bUsingGamepad`, store it
and call `RefreshInputGuide`. This function may be public so `ModActor` can call
it through its typed widget reference.

### `RefreshGuide`

Convert `MoveStepCm` to Text with zero minimum and one maximum fractional digit
and grouping disabled. Format `Step ({Value} cm)`, then set that text on both
`KeyboardStepLabel` and `GamepadStepLabel`.

### `ShowFrozenGuide`

Set `bGuideFrozen` true, set `GuideStateSwitcher` to index 1, call
`RefreshInputGuide`, call `RefreshGuide`, and set `GuidePanel` Visible.

### `ShowUnfrozenGuide`

Set `bGuideFrozen` false, set `GuideStateSwitcher` to index 0, call
`RefreshInputGuide`, and set `GuidePanel` Visible.

### `HideGuide`

Set `GuidePanel` Collapsed. Do not change the switcher indexes or toast.

### Toast functions

Create `ShowFrozenToast`, `ShowUnfrozenToast`, and `HideToast`. The show
functions stop both toast animations, set `ToastText`, make `ToastPanel` Self
Hit Test Invisible, and play the corresponding animation. `HideToast` stops
both animations and collapses `ToastPanel`.

Keep these public names exact because Lua calls them by name:

```text
ShowFrozenGuide
ShowUnfrozenGuide
HideGuide
RefreshGuide
ShowFrozenToast
ShowUnfrozenToast
HideToast
MoveStepCm
```

## ModActor creation and input setup

Set `ModActor` Auto Receive Input to Player 0. Also call Enable Input on
BeginPlay so the actor receives input in the packaged game.

Create variable `KeyGuideWidget` of type
`WBP_PerfectPlacement_KeyGuide Object Reference`.

Build BeginPlay as follows:

```text
Event BeginPlay
→ Get Player Controller (0)
→ Enable Input (Target self, Player Controller result)
→ Create Widget (WBP_PerfectPlacement_KeyGuide, same Owning Player)
→ Set KeyGuideWidget
→ Add to Viewport (ZOrder 50)
```

Do not call a Show function on BeginPlay; Lua decides when a placement preview
exists.

## Device detection without Common Input

Add an `Any Key` event to `ModActor`. From its Key value:

```text
Any Key
→ Is Gamepad Key
→ Branch
```

On true, verify `KeyGuideWidget` is valid and call
`SetUsingGamepad(true)`. On false, test `Is Keyboard Key OR Is Mouse Button`;
if either is true, call `SetUsingGamepad(false)`. Ignore all other key types.

The existing project axes are `Turn` for Mouse X, `LookUp` for Mouse Y,
`TurnRate`/`LookUpRate` for the right stick, and
`MoveForwardController`/`MoveRightController` for the left stick. `Any Key`
normally sees gamepad axes after they cross Unreal's key threshold. If a tested
controller does not switch on stick movement, add the four controller axis
events to `ModActor`: take Absolute of Axis Value, compare it to `0.25`, and
call `SetUsingGamepad(true)` only when above the threshold.

For mouse-only movement switching, use the `Turn` and `LookUp` axis events.
Take Absolute of Axis Value, compare it to `0.05`, and call
`SetUsingGamepad(false)` only when above the threshold. Do not switch on zero
axis events, and do not poll on Tick.

## Toast animations

Create `ToastLockedAnim` and `ToastUnlockedAnim`, each about 1.6 seconds:

1. 0.0 s: opacity 0, translation Y -12
2. 0.12 s: opacity 1, translation Y 0
3. Hold through about 1.25 s
4. 1.6 s: opacity 0

Collapse `ToastPanel` when either animation finishes.

## Smoke test

Temporarily test these flows in editor:

1. Keyboard input selects both keyboard switchers.
2. A gamepad button selects both gamepad switchers.
3. Mouse movement switches back to keyboard/mouse.
4. Frozen and unfrozen state changes preserve the selected device.
5. `MoveStepCm` updates both frozen Step labels.
6. Hidden guides remain hidden when the input device changes.

Remove temporary Show/Hide test events before cooking. Lua owns shipping guide
visibility and placement state.
