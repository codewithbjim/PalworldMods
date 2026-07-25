# Perfect Placement shared and keyboard Blueprint guide

This is the authoritative step-by-step guide for the shared Perfect Placement
widget, keyboard/mouse key-guide pages, input-device switching, and toast.

For controller action actors, trigger combinations, physical serials, and the
final gamepad hierarchy, continue with
[GAMEPAD_BLUEPRINT_GUIDE.md](GAMEPAD_BLUEPRINT_GUIDE.md).

Lua remains authoritative for:

- discovering the active placement preview;
- freezing and unfreezing;
- copying, moving, rotating, stepping, and resetting;
- resolving keyboard bindings from DarnMenu or `config.lua`;
- resolving gamepad physical chords from `Config.gamepad.bindings`;
- loading Palworld's stock keycap textures;
- deciding when the guide and toast appear.

Blueprint provides the visual widget, input-device selection, toast animation,
and the physical gamepad bridge.

## 1. Required assets

Use these assets under `Content/Mods/PerfectPlacement/`:

```text
ModActor
WBP_PerfectPlacement_KeyGuide
UI/WBP_PerfectPlacement_KeyGuideOverlay
UI/WBP_PerfectPlacement_KeyChord
UI/WBP_PerfectPlacement_GamepadChord
EPP_GamepadInputMode
EPP_DPadDirection
EPP_GamepadPhysicalInput
BP_PP_UnfrozenGamepadInput
BP_PP_FrozenGamepadInput
```

This guide builds the first four assets and the shared parts of `ModActor`.
The gamepad guide builds the remaining controller-specific assets.

## 2. Build the reusable KeyGuideOverlay

Open or create:

```text
UI/WBP_PerfectPlacement_KeyGuideOverlay
```

Build:

```text
Overlay: Root
├─ Border: RowBackground                         Fill, Fill
│  └─ Named Slot: RowContent
├─ SizeBox: TopLeftDot                           Left, Top
│  └─ Border: TopLeftDotFill
├─ SizeBox: TopRightDot                          Right, Top
│  └─ Border: TopRightDotFill
├─ SizeBox: BottomLeftDot                        Left, Bottom
│  └─ Border: BottomLeftDotFill
└─ SizeBox: BottomRightDot                       Right, Bottom
   └─ Border: BottomRightDotFill
```

Set the root visibility behavior to:

```text
Not Hit-Testable (Self & All Children)
```

Set every dot Size Box to `3 × 3`.

Render Transform translations:

| Dot | X | Y |
| --- | ---: | ---: |
| Top left | -1 | -1 |
| Top right | 1 | -1 |
| Bottom left | -1 | 1 |
| Bottom right | 1 | 1 |

Use a white brush for the dot Borders and tint them with the existing
Perfect Placement row-dot color.

Create these Instance Editable variables:

```text
BackgroundColor: Linear Color
DotColor: Linear Color
ContentPadding: Margin
DotSize: Float = 3.0
```

Mark the background, dot boxes, and dot fills as variables.

In `Pre Construct`:

1. Apply `BackgroundColor` to `RowBackground`.
2. Apply `ContentPadding` to `RowBackground`.
3. Apply `DotColor` to all four dot fills.
4. Apply `DotSize` to Width Override and Height Override on all four dot
   Size Boxes.

Compile and save.

Every action row in both keyboard and gamepad pages uses this overlay.
Repeated internal names such as `RowBackground` and `RowContent` belong to the
overlay instances and do not need action-specific renaming.

## 3. Build the reusable keyboard chord widget

Open or create:

```text
UI/WBP_PerfectPlacement_KeyChord
```

Build this exact hierarchy:

```text
HorizontalBox: Root
├─ SizeBox: CtrlBox                              32 × 32
│  └─ Image: CtrlIcon
├─ TextBlock: CtrlSeparator                      "+"
├─ SizeBox: AltBox                               32 × 32
│  └─ Image: AltIcon
├─ TextBlock: AltSeparator                       "+"
├─ SizeBox: ShiftBox                             32 × 32
│  └─ Image: ShiftIcon
├─ TextBlock: ShiftSeparator                     "+"
└─ SizeBox: PrimaryBox                           32 × 32
   └─ Image: PrimaryIcon
```

Mark these eleven widgets as variables:

```text
CtrlBox
CtrlIcon
CtrlSeparator
AltBox
AltIcon
AltSeparator
ShiftBox
ShiftIcon
ShiftSeparator
PrimaryBox
PrimaryIcon
```

`Root` does not need to be a variable.

Set all four Size Boxes to:

```text
Width Override  = 32
Height Override = 32
```

Keep the Horizontal Box slots on Auto rather than Fill.

Leave all four Image brushes empty. Lua loads the selected Palworld keycaps.

Initial visibility:

```text
CtrlBox       = Collapsed
CtrlSeparator = Collapsed
AltBox        = Collapsed
AltSeparator  = Collapsed
ShiftBox      = Collapsed
ShiftSeparator = Collapsed
PrimaryBox    = Collapsed
```

Keep Match Size disabled on every Set Brush From Texture call.

Lua updates the named child widgets directly. A Blueprint `SetChord` function
may be kept for editor testing, but the shipping runtime does not depend on its
arguments reaching the cooked graph.

Compile and save.

## 4. Create the parent widget switchers

Open:

```text
WBP_PerfectPlacement_KeyGuide
```

The shared outer structure is:

```text
CanvasPanel: Root
├─ Border: GuidePanel
│  └─ VerticalBox: GuideContent
│     ├─ TextBlock: TitleText
│     └─ WidgetSwitcher: GuideStateSwitcher
│        ├─ UnfrozenGuide                         index 0
│        │  └─ WidgetSwitcher: UnfrozenInputSwitcher
│        │     ├─ KeyboardUnfrozenGuide           index 0
│        │     └─ GamepadUnfrozenGuide            index 1
│        └─ FrozenGuide                           index 1
│           └─ WidgetSwitcher: FrozenInputSwitcher
│              ├─ KeyboardFrozenGuide             index 0
│              └─ GamepadFrozenGuide              index 1
└─ Border: ToastPanel
   └─ TextBlock: ToastText
```

Set:

```text
Root visibility behavior        Not Hit-Testable (Self & All Children)
GuidePanel anchor               Bottom Center
ToastPanel anchor               Top Center
GuidePanel initial visibility   Collapsed
ToastPanel initial visibility   Collapsed
GuideStateSwitcher index        0
UnfrozenInputSwitcher index     0
FrozenInputSwitcher index       0
```

Do not manually collapse any switcher child. A Widget Switcher handles child
visibility itself.

Mark these as variables:

```text
GuidePanel
GuideStateSwitcher
UnfrozenInputSwitcher
FrozenInputSwitcher
KeyboardStepLabel
GamepadStepLabel
ToastPanel
ToastText
```

## 5. Build the keyboard/mouse hierarchy

The keyboard pages mirror the final gamepad grouping:

- Unfrozen has exactly two KeyGuideOverlay rows.
- Frozen Unfreeze is a standalone row.
- Frozen transform controls use three Vertical Boxes.
- Each grouping Vertical Box contains exactly two KeyGuideOverlay children.

Use this authoritative hierarchy:

```text
KeyboardUnfrozenGuide
└─ KeyboardUnfrozenKeyGroups                          VerticalBox
   ├─ KeyboardFreezeRow                               KeyGuideOverlay
   │  └─ RowContent
   │     └─ KeyboardFreezeContent                     HorizontalBox
   │        ├─ KeyboardFreezeKeycaps                  HorizontalBox
   │        │  └─ FreezeChord
   │        └─ KeyboardFreezeLabel                    "Freeze"
   └─ KeyboardCopyRow                                 KeyGuideOverlay
      └─ RowContent
         └─ KeyboardCopyContent                       HorizontalBox
            ├─ KeyboardCopyKeycaps                    HorizontalBox
            │  └─ CopyChord
            └─ KeyboardCopyLabel                      "Copy"

KeyboardFrozenGuide
├─ KeyboardUnfreezeRow                                KeyGuideOverlay
│  └─ RowContent
│     └─ KeyboardUnfreezeContent                      HorizontalBox
│        ├─ KeyboardUnfreezeKeycaps                   HorizontalBox
│        │  └─ UnfreezeChord
│        └─ KeyboardUnfreezeLabel                     "Unfreeze"
└─ KeyboardMoveContent                                HorizontalBox
   ├─ KeyboardMoveKeyGroups                           VerticalBox
   │  ├─ KeyboardMoveHorizontalRow                    KeyGuideOverlay
   │  │  └─ RowContent
   │  │     └─ KeyboardMoveHorizontalContent          HorizontalBox
   │  │        ├─ KeyboardMoveHorizontalKeycaps       HorizontalBox
   │  │        │  ├─ MoveLeftChord
   │  │        │  ├─ KeyboardMoveHorizontalSeparator "/"
   │  │        │  └─ MoveRightChord
   │  │        └─ KeyboardMoveHorizontalLabel         "Left / Right"
   │  └─ KeyboardMoveDepthRow                         KeyGuideOverlay
   │     └─ RowContent
   │        └─ KeyboardMoveDepthContent               HorizontalBox
   │           ├─ KeyboardMoveDepthKeycaps            HorizontalBox
   │           │  ├─ MoveForwardChord
   │           │  ├─ KeyboardMoveDepthSeparator       "/"
   │           │  └─ MoveBackwardChord
   │           └─ KeyboardMoveDepthLabel              "Forward / Back"
   ├─ KeyboardAdjustKeyGroups                         VerticalBox
   │  ├─ KeyboardMoveVerticalRow                      KeyGuideOverlay
   │  │  └─ RowContent
   │  │     └─ KeyboardMoveVerticalContent            HorizontalBox
   │  │        ├─ KeyboardMoveVerticalKeycaps         HorizontalBox
   │  │        │  ├─ MoveUpChord
   │  │        │  ├─ KeyboardMoveVerticalSeparator    "/"
   │  │        │  └─ MoveDownChord
   │  │        └─ KeyboardMoveVerticalLabel           "Raise / Lower"
   │  └─ KeyboardRotateRow                            KeyGuideOverlay
   │     └─ RowContent
   │        └─ KeyboardRotateContent                  HorizontalBox
   │           ├─ KeyboardRotateKeycaps               HorizontalBox
   │           │  ├─ RotateLeftChord
   │           │  ├─ KeyboardRotateSeparator          "/"
   │           │  └─ RotateRightChord
   │           └─ KeyboardRotateLabel                 "Rotate Left / Right"
   └─ KeyboardStepResetKeyGroups                      VerticalBox
      ├─ KeyboardStepRow                              KeyGuideOverlay
      │  └─ RowContent
      │     └─ KeyboardStepContent                    HorizontalBox
      │        ├─ KeyboardStepKeycaps                 HorizontalBox
      │        │  ├─ StepDownChord
      │        │  ├─ KeyboardStepSeparator            "/"
      │        │  └─ StepUpChord
      │        ├─ KeyboardStepActionLabel             "Step Down / Up"
      │        └─ KeyboardStepLabel
      └─ KeyboardResetRow                             KeyGuideOverlay
         └─ RowContent
            └─ KeyboardResetContent                   HorizontalBox
               ├─ KeyboardResetKeycaps                HorizontalBox
               │  └─ ResetChord
               └─ KeyboardResetLabel                  "Reset"
```

Every name in this hierarchy is unique in the parent Widget Tree.

The five `/` TextBlocks do not need to be variables:

```text
KeyboardMoveHorizontalSeparator
KeyboardMoveDepthSeparator
KeyboardMoveVerticalSeparator
KeyboardRotateSeparator
KeyboardStepSeparator
```

## 6. Name the fourteen keyboard chord instances

Drag one `WBP_PerfectPlacement_KeyChord` instance into each keycaps container.

Use these exact parent instance names:

```text
MoveLeftChord
MoveRightChord
MoveForwardChord
MoveBackwardChord
MoveUpChord
MoveDownChord
RotateLeftChord
RotateRightChord
ResetChord
StepDownChord
StepUpChord
FreezeChord
UnfreezeChord
CopyChord
```

Enable Is Variable on all fourteen.

Lua looks up these names directly. Do not rename `MoveBackwardChord` to
`MoveBackChord`; the current runtime contract uses `MoveBackwardChord`.

After the reusable instances work in a cooked build, remove obsolete
parent-level keyboard Image variables such as `Num1Icon`, `Num8Icon`, or
`FreezeMouseWheelButtonIcon`. The reusable chord widget replaces them.

## 7. Build the gamepad pages

Do not recreate controller instructions in this file.

Build `GamepadUnfrozenGuide` and `GamepadFrozenGuide` using:

[GAMEPAD_BLUEPRINT_GUIDE.md](GAMEPAD_BLUEPRINT_GUIDE.md)

The final gamepad guide uses:

- `WBP_PerfectPlacement_GamepadChord`;
- fourteen named chord instances;
- the same KeyGuideOverlay styling;
- a standalone Unfreeze row;
- three frozen two-row grouping columns;
- physical chord serials rather than logical action serials.

Return here after the gamepad pages exist.

## 8. Create shared parent variables

In `WBP_PerfectPlacement_KeyGuide`, create:

```text
MoveStepCm: Float
    Default: 10.0
    Private: false

bUsingGamepad: Boolean
    Default: false
    Private: true

bGuideFrozen: Boolean
    Default: false
    Private: true

GamepadEnabled: Boolean
    Default: true
    Private: false
```

Lua writes `MoveStepCm` and `GamepadEnabled` directly.

## 9. Create RefreshGuide

Create a public function:

```text
RefreshGuide
```

Graph:

1. Get `MoveStepCm`.
2. Convert Float to Text.
3. Set Minimum Fractional Digits to `0`.
4. Set Maximum Fractional Digits to `1`.
5. Disable grouping.
6. Format:

```text
Step ({Value} cm)
```

7. Set the result on `KeyboardStepLabel`.
8. Set the same result on `GamepadStepLabel`.

Lua updates `MoveStepCm` before calling this function.

## 10. Create RefreshInputGuide

Create:

```text
RefreshInputGuide
```

Calculate:

```text
GamepadEnabled AND bUsingGamepad
→ Select Integer
    false = 0
    true  = 1
```

Apply the selected index to:

```text
UnfrozenInputSwitcher.SetActiveWidgetIndex
FrozenInputSwitcher.SetActiveWidgetIndex
```

Always update both input switchers. Do not change `GuideStateSwitcher` or
`GuidePanel` visibility here.

## 11. Create SetUsingGamepad

Create:

```text
SetUsingGamepad(
    UsingGamepad: Boolean
)
```

Graph:

```text
Branch(GamepadEnabled)
├─ false:
│  Branch(bUsingGamepad)
│  ├─ false → Return
│  └─ true:
│     Set bUsingGamepad = false
│     → RefreshInputGuide
└─ true:
   UsingGamepad != bUsingGamepad
   → Branch
     ├─ false → Return
     └─ true:
        Set bUsingGamepad = UsingGamepad
        → RefreshInputGuide
```

This prevents a stale controller event from selecting a gamepad page when
gamepad support is disabled.

## 12. Create the gamepad input-mode dispatcher

Create an Event Dispatcher in the parent widget:

```text
RequestGamepadInputMode(
    Mode: EPP_GamepadInputMode
)
```

The dispatcher keeps the widget independent of a direct `ModActor` reference.
The gamepad guide connects it to the two state-specific controller actors.

## 13. Create the public state functions

Lua calls these functions by exact name.

### ShowUnfrozenGuide

```text
Set bGuideFrozen = false
→ GuideStateSwitcher.SetActiveWidgetIndex(0)
→ RefreshInputGuide
→ GuidePanel.SetVisibility(Visible)
→ Branch(GamepadEnabled)
  ├─ false → RequestGamepadInputMode(Disabled)
  └─ true  → RequestGamepadInputMode(Unfrozen)
```

### ShowFrozenGuide

```text
Set bGuideFrozen = true
→ GuideStateSwitcher.SetActiveWidgetIndex(1)
→ RefreshInputGuide
→ RefreshGuide
→ GuidePanel.SetVisibility(Visible)
→ Branch(GamepadEnabled)
  ├─ false → RequestGamepadInputMode(Disabled)
  └─ true  → RequestGamepadInputMode(Frozen)
```

### HideGuide

```text
GuidePanel.SetVisibility(Collapsed)
→ RequestGamepadInputMode(Disabled)
```

Do not reset `bUsingGamepad`, switcher indexes, or toast state in `HideGuide`.

Required public API:

```text
ShowFrozenGuide
ShowUnfrozenGuide
HideGuide
RefreshGuide
ShowFrozenToast
ShowUnfrozenToast
HideToast
MoveStepCm
GamepadEnabled
```

## 14. Build the combined toast animation

Keep one animation:

```text
Toast
```

Recommended Render Opacity track on `ToastPanel`:

```text
0.00 s → 0
0.15 s → 1
1.25 s → 1
1.50 s → 0
```

Optionally animate translation Y from `-12` to `0` during the first `0.15`
seconds.

Leave Restore State disabled.

### ShowFrozenToast

```text
Stop Animation: Toast
→ ToastText.SetText("Preview Frozen")
→ ToastPanel.SetVisibility(Not Hit-Testable Self Only)
→ Play Animation: Toast
```

### ShowUnfrozenToast

```text
Stop Animation: Toast
→ ToastText.SetText("Preview Unfrozen")
→ ToastPanel.SetVisibility(Not Hit-Testable Self Only)
→ Play Animation: Toast
```

### HideToast

```text
Stop Animation: Toast
→ ToastPanel.SetVisibility(Collapsed)
```

The animation ends transparent. Lua calls `HideToast` when the complete UI
should be removed.

## 15. Configure shared ModActor setup

Open:

```text
ModActor
```

Class Defaults:

```text
Auto Receive Input = Player 0
Block Input        = false
Input Priority     = 0
```

Create:

```text
KeyGuideWidget: WBP_PerfectPlacement_KeyGuide reference
PlayerController: PlayerController reference
```

In BeginPlay:

```text
Get Player Controller(0)
→ Set PlayerController
→ Enable Input
    Target = Self
    Player Controller = PlayerController
→ Create Widget
    Class = WBP_PerfectPlacement_KeyGuide
    Owning Player = PlayerController
→ Set KeyGuideWidget
→ Add to Viewport
    ZOrder = 50
```

Do not call a Show function during BeginPlay. Lua decides whether a valid build
preview exists.

The gamepad guide extends this BeginPlay flow by binding
`RequestGamepadInputMode` and spawning the two controller actors.

## 16. Add input-device detection

`CommonInputSubsystem` is not available in this project. Use native Blueprint
input detection.

### Any Key

Add `Event Any Key` to `ModActor`.

Set:

```text
Consume Input       = false
Execute When Paused = false
```

From its Key output:

```text
Key
→ Is Gamepad Key
→ Branch
```

True:

```text
Is Valid(KeyGuideWidget)
→ KeyGuideWidget.SetUsingGamepad(true)
```

False:

```text
Key Is Keyboard Key
Key Is Mouse Button
→ Boolean OR
→ Branch
  └─ true:
     Is Valid(KeyGuideWidget)
     → KeyGuideWidget.SetUsingGamepad(false)
```

### Mouse movement

Add the existing mouse-look axis events used by the project, normally:

```text
InputAxis Turn
InputAxis LookUp
```

Set Consume Input to false.

For each:

```text
Axis Value
→ Abs
→ > 0.05
→ Branch
  └─ true:
     Is Valid(KeyGuideWidget)
     → SetUsingGamepad(false)
```

### Controller sticks

If `Any Key` does not detect stick movement, add the existing Palworld
controller look/move axis events available in the project.

For each:

```text
Axis Value
→ Abs
→ > 0.35
→ Branch
  └─ true:
     Is Valid(KeyGuideWidget)
     → SetUsingGamepad(true)
```

Set Consume Input to false. Do not use Event Tick.

Input-device detection only changes the nested switcher indexes. It never
shows a hidden guide or changes placement state.

## 17. Keyboard Lua contract

Lua resolves keyboard/mouse bindings from:

1. changed values in `Mods/shared/PerfectPlacement_user.lua`, written by DarnMenu;
2. `Scripts/config.lua` as the baseline.

It then finds each named `WBP_PerfectPlacement_KeyChord` instance and updates:

```text
CtrlBox / CtrlIcon / CtrlSeparator
AltBox / AltIcon / AltSeparator
ShiftBox / ShiftIcon / ShiftSeparator
PrimaryBox / PrimaryIcon
```

Modifier order is always:

```text
Ctrl
Alt
Shift
Primary key
```

Lua uses:

```text
SetBrushFromTexture(Texture, false)
```

The false argument keeps Match Size disabled. The reusable Size Boxes control
the displayed `32 × 32` dimensions.

Changing a keyboard binding and restarting Palworld updates both the registered
UE4SS binding and the displayed Palworld keycap.

## 18. Editor validation

### Reusable overlay

Verify:

1. All four dots appear at the corners.
2. Instance colors and padding update in Pre Construct.
3. `RowContent` accepts the action-specific Horizontal Box.

### Keyboard chord widget

Verify:

1. All eleven required child widgets are variables.
2. All four keycap boxes are `32 × 32`.
3. All Image brushes are empty.
4. Modifiers and separators start Collapsed.
5. Match Size is disabled.

### Parent widget

Verify:

1. All fourteen keyboard chord instances use the exact names from Step 6.
2. Unfrozen has exactly two overlay rows.
3. Frozen Unfreeze is standalone.
4. Each of the three frozen grouping Vertical Boxes has exactly two overlays.
5. Switcher child order is keyboard index 0 and gamepad index 1.
6. `MoveStepCm` updates both step labels.
7. Device switching does not change placement state.
8. Device switching does not reveal a hidden guide.

Remove temporary editor test events before cooking.

## 19. In-game validation

After cooking and deploying:

1. Start with keyboard/mouse.
2. Enter build mode.
3. Confirm the unfrozen keyboard guide appears.
4. Confirm Freeze and Copy show the configured keyboard chords.
5. Freeze the preview.
6. Confirm the frozen keyboard hierarchy matches the gamepad layout.
7. Confirm all movement, rotation, step, reset, and Unfreeze chords display
   their current configuration.
8. Change one DarnMenu binding.
9. Restart Palworld.
10. Confirm both the action and displayed chord use the new binding.
11. Touch the controller and confirm both input switchers select index 1.
12. Move the mouse and confirm they return to index 0.
13. Confirm the combined Freeze/Unfreeze toast animation restarts cleanly.
14. Exit build mode and confirm the guide and toast are hidden.

The gamepad-specific validation continues in
[GAMEPAD_BLUEPRINT_GUIDE.md](GAMEPAD_BLUEPRINT_GUIDE.md).
