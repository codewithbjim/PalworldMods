# Perfect Placement configurable gamepad Blueprint guide

This guide adds gamepad-only support to the existing Perfect Placement
companion widget. It preserves the existing keyboard/mouse implementation.

The configurable design deliberately sends **physical controller chords** from
Blueprint to Lua. Blueprint never decides that a button means Move, Rotate, or
Reset. Lua reads `Config.gamepad.bindings`, maps each physical chord to an
action, and performs that action.

That separation allows all of these frozen bindings:

```text
D-pad direction
LT + D-pad direction
RT + D-pad direction
LT + RT + D-pad direction
LB
RB
L3
R3
```

For example, all of these are valid:

```lua
move_up = {
    key = "DPAD_UP",
    modifiers = { "LT" },
}

step_up = {
    key = "DPAD_RIGHT",
    modifiers = { "RT" },
}

reset = {
    key = "DPAD_DOWN",
    modifiers = { "LT", "RT" },
}
```

## 1. Understand the safety boundary

Perfect Placement uses two state-specific input actors:

```text
BP_PP_UnfrozenGamepadInput
BP_PP_FrozenGamepadInput
```

The frozen actor may consume the D-pad, triggers, shoulders, L3, and R3 because
normal preview placement is suspended.

The unfrozen actor must preserve Palworld's normal building controls. It only
captures these two physical chords:

```text
L3
L3 + D-pad Down
```

Consequently:

- frozen actions are freely remappable among the supported frozen chords;
- unfrozen Freeze and Copy may swap those two captured chords;
- an unfrozen action cannot be assigned to LT, RT, X, Y, or another uncaptured
  Palworld control;
- unsupported and duplicate bindings are logged and ignored by Lua.

## 2. Default controller configuration

The default configuration is:

```lua
gamepad = {
    enabled = true,
    poll_interval_ms = 25,
    maximum_actions_per_poll = 32,

    invert_forward_back = false,
    invert_height = false,
    swap_rotate_buttons = false,

    repeat_delay_ms = 300,
    repeat_interval_ms = 80,

    bindings = {
        unfrozen = {
            toggle_freeze = {
                key = "L3",
            },
            copy_piece = {
                key = "DPAD_DOWN",
                modifiers = { "L3" },
            },
        },
        frozen = {
            move_left = "DPAD_LEFT",
            move_right = "DPAD_RIGHT",
            move_forward = "DPAD_UP",
            move_back = "DPAD_DOWN",
            move_up = {
                key = "DPAD_UP",
                modifiers = { "LT" },
            },
            move_down = {
                key = "DPAD_DOWN",
                modifiers = { "LT" },
            },
            rotate_left = "LB",
            rotate_right = "RB",
            step_down = {
                key = "DPAD_LEFT",
                modifiers = { "LT" },
            },
            step_up = {
                key = "DPAD_RIGHT",
                modifiers = { "LT" },
            },
            reset = "R3",
            toggle_freeze = "L3",
        },
    },
}
```

`invert_forward_back`, `invert_height`, and `swap_rotate_buttons` are applied
after chord resolution. Lua also updates the displayed bindings so each action
row continues to show what that physical chord actually does.

`repeat_delay_ms` and `repeat_interval_ms` remain reserved until hold-repeat is
implemented. Do not build Tick-based repeating input in this version.

## 3. Use Palworld's stock keyguide textures

Do not import or cook the FModel PNG exports.

In FModel, use this exported content path only as a visual reference:

```text
Pal/Content/Pal/Texture/UI/KeyGuide
```

Lua loads these stock game assets at runtime:

```text
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_CrossU.T_KeyGuide_CrossU
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_CrossD.T_KeyGuide_CrossD
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_CrossL.T_KeyGuide_CrossL
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_CrossR.T_KeyGuide_CrossR
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_L1.T_KeyGuide_L1
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_L2.T_KeyGuide_L2
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_L3.T_KeyGuide_L3
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_R1.T_KeyGuide_R1
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_R2.T_KeyGuide_R2
/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_R3.T_KeyGuide_R3
```

Every Image must be inside a `32 × 32` Size Box.

Leave every Image brush empty in the Widget Designer. On every
`Set Brush From Texture` node:

```text
Match Size = false
```

Enabling Match Size replaces the desired display size with the source texture
size and can squash the icon inside the smaller layout.

## 4. Create the three enums

Create this Blueprint Enumeration:

```text
EPP_GamepadInputMode
```

Entries:

```text
Disabled
Unfrozen
Frozen
```

Create a second Blueprint Enumeration:

```text
EPP_GamepadPhysicalInput
```

Use these entries exactly:

```text
Unfrozen_L3
Unfrozen_L3_DPadDown

Frozen_DPadUp
Frozen_DPadDown
Frozen_DPadLeft
Frozen_DPadRight

Frozen_LT_DPadUp
Frozen_LT_DPadDown
Frozen_LT_DPadLeft
Frozen_LT_DPadRight

Frozen_RT_DPadUp
Frozen_RT_DPadDown
Frozen_RT_DPadLeft
Frozen_RT_DPadRight

Frozen_LT_RT_DPadUp
Frozen_LT_RT_DPadDown
Frozen_LT_RT_DPadLeft
Frozen_LT_RT_DPadRight

Frozen_LB
Frozen_RB
Frozen_R3
Frozen_L3
```

The enum names are Blueprint-side routing names. Lua communicates through the
Integer property names created later.

Create the four-direction routing enum:

```text
EPP_DPadDirection
```

Entries:

```text
Up
Down
Left
Right
```

## 5. Confirm the widget switcher structure

Open:

```text
WBP_PerfectPlacement_KeyGuide
```

Keep the existing placement-state switcher:

```text
GuideStateSwitcher
├─ UnfrozenGuide
└─ FrozenGuide
```

Inside each state, use an input-device switcher:

```text
UnfrozenInputSwitcher
├─ KeyboardUnfrozenGuide       index 0
└─ GamepadUnfrozenGuide        index 1

FrozenInputSwitcher
├─ KeyboardFrozenGuide         index 0
└─ GamepadFrozenGuide          index 1
```

Do not combine placement state and input device into one four-page switcher.
Lua placement state and last-used input device change independently.

## 6. Create the reusable gamepad chord widget

Create a User Widget:

```text
WBP_PerfectPlacement_GamepadChord
```

Build this exact hierarchy:

```text
HorizontalBox: Root
├─ SizeBox: Modifier1Box                         [32 × 32]
│  └─ Image: Modifier1Icon
├─ TextBlock: Modifier1Separator                 "+"
├─ SizeBox: Modifier2Box                         [32 × 32]
│  └─ Image: Modifier2Icon
├─ TextBlock: Modifier2Separator                 "+"
└─ SizeBox: PrimaryBox                           [32 × 32]
   └─ Image: PrimaryIcon
```

Mark these eight widgets as variables:

```text
Modifier1Box
Modifier1Icon
Modifier1Separator
Modifier2Box
Modifier2Icon
Modifier2Separator
PrimaryBox
PrimaryIcon
```

Set all three Size Boxes to:

```text
Width Override  = 32
Height Override = 32
```

Leave all three Image brushes empty. Set both separator TextBlocks to `+`.

Designer visibility:

```text
Modifier1Box       = Collapsed
Modifier1Separator = Collapsed
Modifier2Box       = Collapsed
Modifier2Separator = Collapsed
PrimaryBox         = Collapsed
```

Keep every Horizontal Box slot on Auto rather than Fill. Compile and save the
reusable widget.

Lua updates these named child widgets directly. Do not rename their internal
variables per action, and do not enable Match Size.

## 7. Replace each hand-built keycap group with a widget instance

Open `WBP_PerfectPlacement_KeyGuide`. In the Palette, find:

```text
WBP_PerfectPlacement_GamepadChord
```

For each action, remove the hand-built group of three Size Boxes and two plus
TextBlocks. Drag one reusable chord widget instance into the same location.

Keep the existing `KeyGuideOverlay` styling. Every grouping Vertical Box has
exactly two `KeyGuideOverlay` children. Frozen Unfreeze is the only standalone
row outside the three grouped columns.

Use this authoritative parent hierarchy:

```text
GamepadUnfrozenGuide
└─ GamepadUnfrozenKeyGroups                         VerticalBox
   ├─ GamepadFreezeRow                              KeyGuideOverlay
   │  └─ RowContent
   │     └─ GamepadFreezeContent                    HorizontalBox
   │        ├─ GamepadFreezeKeycaps                 HorizontalBox
   │        │  └─ GP_UnfrozenToggleFreezeChord
   │        └─ GamepadFreezeLabel                   "Freeze"
   └─ GamepadCopyRow                                KeyGuideOverlay
      └─ RowContent
         └─ GamepadCopyContent                      HorizontalBox
            ├─ GamepadCopyKeycaps                   HorizontalBox
            │  └─ GP_UnfrozenCopyChord
            └─ GamepadCopyLabel                     "Copy"

GamepadFrozenGuide
├─ GamepadUnfreezeRow                               KeyGuideOverlay
│  └─ RowContent
│     └─ GamepadUnfreezeContent                     HorizontalBox
│        ├─ GamepadUnfreezeKeycaps                  HorizontalBox
│        │  └─ GP_FrozenToggleFreezeChord
│        └─ GamepadUnfreezeLabel                    "Unfreeze"
└─ GamepadMoveContent                               HorizontalBox
   ├─ GamepadMoveKeyGroups                          VerticalBox
   │  ├─ GamepadMoveHorizontalRow                   KeyGuideOverlay
   │  │  └─ RowContent
   │  │     └─ GamepadMoveHorizontalContent         HorizontalBox
   │  │        ├─ GamepadMoveHorizontalKeycaps      HorizontalBox
   │  │        │  ├─ GP_FrozenMoveLeftChord
   │  │        │  ├─ GamepadMoveHorizontalSeparator "/"
   │  │        │  └─ GP_FrozenMoveRightChord
   │  │        └─ GamepadMoveHorizontalLabel        "Left / Right"
   │  └─ GamepadMoveDepthRow                        KeyGuideOverlay
   │     └─ RowContent
   │        └─ GamepadMoveDepthContent              HorizontalBox
   │           ├─ GamepadMoveDepthKeycaps           HorizontalBox
   │           │  ├─ GP_FrozenMoveForwardChord
   │           │  ├─ GamepadMoveDepthSeparator      "/"
   │           │  └─ GP_FrozenMoveBackChord
   │           └─ GamepadMoveDepthLabel             "Forward / Back"
   ├─ GamepadAdjustKeyGroups                        VerticalBox
   │  ├─ GamepadMoveVerticalRow                     KeyGuideOverlay
   │  │  └─ RowContent
   │  │     └─ GamepadMoveVerticalContent           HorizontalBox
   │  │        ├─ GamepadMoveVerticalKeycaps        HorizontalBox
   │  │        │  ├─ GP_FrozenMoveUpChord
   │  │        │  ├─ GamepadMoveVerticalSeparator   "/"
   │  │        │  └─ GP_FrozenMoveDownChord
   │  │        └─ GamepadMoveVerticalLabel          "Raise / Lower"
   │  └─ GamepadRotateRow                           KeyGuideOverlay
   │     └─ RowContent
   │        └─ GamepadRotateContent                 HorizontalBox
   │           ├─ GamepadRotateKeycaps              HorizontalBox
   │           │  ├─ GP_FrozenRotateLeftChord
   │           │  ├─ GamepadRotateSeparator         "/"
   │           │  └─ GP_FrozenRotateRightChord
   │           └─ GamepadRotateLabel                "Rotate Left / Right"
   └─ GamepadStepResetKeyGroups                     VerticalBox
      ├─ GamepadStepRow                             KeyGuideOverlay
      │  └─ RowContent
      │     └─ GamepadStepContent                   HorizontalBox
      │        ├─ GamepadStepKeycaps                HorizontalBox
      │        │  ├─ GP_FrozenStepDownChord
      │        │  ├─ GamepadStepSeparator           "/"
      │        │  └─ GP_FrozenStepUpChord
      │        ├─ GamepadStepActionLabel            "Step Down / Up"
      │        └─ GamepadStepLabel
      └─ GamepadResetRow                            KeyGuideOverlay
         └─ RowContent
            └─ GamepadResetContent                  HorizontalBox
               ├─ GamepadResetKeycaps               HorizontalBox
               │  └─ GP_FrozenResetChord
               └─ GamepadResetLabel                 "Reset"
```

Each `KeyGuideOverlay` retains its own existing `RowBackground` sibling beside
`RowContent`; those repeated internal names belong to the overlay instances and
do not need action-specific renaming.

Mark every chord-widget instance as a variable.

## 8. Name the fourteen reusable instances

Use these exact instance names:

```text
GP_UnfrozenToggleFreezeChord
GP_UnfrozenCopyChord

GP_FrozenMoveLeftChord
GP_FrozenMoveRightChord
GP_FrozenMoveForwardChord
GP_FrozenMoveBackChord
GP_FrozenMoveUpChord
GP_FrozenMoveDownChord
GP_FrozenRotateLeftChord
GP_FrozenRotateRightChord
GP_FrozenStepDownChord
GP_FrozenStepUpChord
GP_FrozenResetChord
GP_FrozenToggleFreezeChord
```

The five `/` separators belong to their paired parent rows and do not need to
be variables. The exact separator names are:

```text
GamepadMoveHorizontalSeparator
GamepadMoveDepthSeparator
GamepadMoveVerticalSeparator
GamepadRotateSeparator
GamepadStepSeparator
```

If Unreal generated a name such as `MoveXLabelText_1`, rename it to the
corresponding exact label name. For the Left/Right row, use:

```text
GamepadMoveHorizontalLabel
```

Add or keep:

```text
GamepadStepLabel
```

Mark it as a variable. `RefreshGuide` updates it with the current movement
increment. Compile the parent widget and confirm all fourteen chord instances
appear in its Variables panel.

## 9. Add the gamepad configuration gate

In `WBP_PerfectPlacement_KeyGuide`, create:

```text
GamepadEnabled: Boolean
Default: true
Private: false
Instance Editable: false
Expose on Spawn: false
```

Lua writes this exact public property:

```lua
host.GamepadEnabled = Config.gamepad.enabled ~= false
```

Create:

```text
bUsingGamepad: Boolean
Default: false
Private: true
```

Create or update:

```text
SetUsingGamepad(UsingGamepad: Boolean)
```

Graph:

```text
Branch(GamepadEnabled)
├─ false:
│  Branch(bUsingGamepad)
│  ├─ false → Return
│  └─ true
│     → Set bUsingGamepad = false
│     → RefreshInputGuide
└─ true:
   UsingGamepad != bUsingGamepad
   → Branch
     ├─ false → Return
     └─ true
        → Set bUsingGamepad = UsingGamepad
        → RefreshInputGuide
```

`RefreshInputGuide`:

```text
GamepadEnabled AND bUsingGamepad
→ Select Integer
    false = 0
    true  = 1
→ UnfrozenInputSwitcher.SetActiveWidgetIndex
→ FrozenInputSwitcher.SetActiveWidgetIndex
```

Never hide the keyboard guide merely because gamepad support is disabled.

## 10. Create all physical serial properties

In `WBP_PerfectPlacement_KeyGuide`, create these public Integer variables:

```text
GamepadUnfrozenL3Serial
GamepadUnfrozenL3DPadDownSerial

GamepadFrozenDPadUpSerial
GamepadFrozenDPadDownSerial
GamepadFrozenDPadLeftSerial
GamepadFrozenDPadRightSerial

GamepadFrozenLTDPadUpSerial
GamepadFrozenLTDPadDownSerial
GamepadFrozenLTDPadLeftSerial
GamepadFrozenLTDPadRightSerial

GamepadFrozenRTDPadUpSerial
GamepadFrozenRTDPadDownSerial
GamepadFrozenRTDPadLeftSerial
GamepadFrozenRTDPadRightSerial

GamepadFrozenLTRTDPadUpSerial
GamepadFrozenLTRTDPadDownSerial
GamepadFrozenLTRTDPadLeftSerial
GamepadFrozenLTRTDPadRightSerial

GamepadFrozenLBSerial
GamepadFrozenRBSerial
GamepadFrozenR3Serial
GamepadFrozenL3Serial
```

For every serial:

```text
Default value      0
Private            false
Instance Editable  false
Expose on Spawn    false
```

These are physical input counters. Do not name them after actions such as
`GamepadMoveUpSerial`. Action-named counters would hard-code the mapping in
Blueprint and defeat configuration.

Never reset a serial to zero. Lua remembers its last observed value and
processes the positive difference.

## 11. Create QueueGamepadPhysicalInput

In `WBP_PerfectPlacement_KeyGuide`, create:

```text
QueueGamepadPhysicalInput(
    PhysicalInput: EPP_GamepadPhysicalInput
)
```

Add:

```text
Switch on EPP_GamepadPhysicalInput
```

Each enum branch increments its matching Integer by one.

Example:

```text
Frozen_LT_RT_DPadUp
→ Get GamepadFrozenLTRTDPadUpSerial
→ Integer + Integer
    B = 1
→ Set GamepadFrozenLTRTDPadUpSerial
→ Return
```

Map every enum entry:

| Enum entry | Integer property |
| --- | --- |
| `Unfrozen_L3` | `GamepadUnfrozenL3Serial` |
| `Unfrozen_L3_DPadDown` | `GamepadUnfrozenL3DPadDownSerial` |
| `Frozen_DPadUp` | `GamepadFrozenDPadUpSerial` |
| `Frozen_DPadDown` | `GamepadFrozenDPadDownSerial` |
| `Frozen_DPadLeft` | `GamepadFrozenDPadLeftSerial` |
| `Frozen_DPadRight` | `GamepadFrozenDPadRightSerial` |
| `Frozen_LT_DPadUp` | `GamepadFrozenLTDPadUpSerial` |
| `Frozen_LT_DPadDown` | `GamepadFrozenLTDPadDownSerial` |
| `Frozen_LT_DPadLeft` | `GamepadFrozenLTDPadLeftSerial` |
| `Frozen_LT_DPadRight` | `GamepadFrozenLTDPadRightSerial` |
| `Frozen_RT_DPadUp` | `GamepadFrozenRTDPadUpSerial` |
| `Frozen_RT_DPadDown` | `GamepadFrozenRTDPadDownSerial` |
| `Frozen_RT_DPadLeft` | `GamepadFrozenRTDPadLeftSerial` |
| `Frozen_RT_DPadRight` | `GamepadFrozenRTDPadRightSerial` |
| `Frozen_LT_RT_DPadUp` | `GamepadFrozenLTRTDPadUpSerial` |
| `Frozen_LT_RT_DPadDown` | `GamepadFrozenLTRTDPadDownSerial` |
| `Frozen_LT_RT_DPadLeft` | `GamepadFrozenLTRTDPadLeftSerial` |
| `Frozen_LT_RT_DPadRight` | `GamepadFrozenLTRTDPadRightSerial` |
| `Frozen_LB` | `GamepadFrozenLBSerial` |
| `Frozen_RB` | `GamepadFrozenRBSerial` |
| `Frozen_R3` | `GamepadFrozenR3Serial` |
| `Frozen_L3` | `GamepadFrozenL3Serial` |

Compile after wiring all 22 branches.

## 12. Create the input-mode dispatcher

In `WBP_PerfectPlacement_KeyGuide`, create an Event Dispatcher:

```text
RequestGamepadInputMode
```

Add one input:

```text
Mode: EPP_GamepadInputMode
```

Update the widget state functions.

`ShowUnfrozenGuide`:

```text
Set bGuideFrozen = false
→ GuideStateSwitcher.SetActiveWidgetIndex(0)
→ RefreshInputGuide
→ GuidePanel.SetVisibility(Visible)
→ Branch(GamepadEnabled)
  ├─ false → RequestGamepadInputMode(Disabled)
  └─ true  → RequestGamepadInputMode(Unfrozen)
```

`ShowFrozenGuide`:

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

`HideGuide`:

```text
GuidePanel.SetVisibility(Collapsed)
→ RequestGamepadInputMode(Disabled)
```

Do not reset `bUsingGamepad` when the placement state changes.

## 13. Create BP_PP_UnfrozenGamepadInput

Create an Actor Blueprint:

```text
BP_PP_UnfrozenGamepadInput
```

Class Defaults:

```text
Auto Receive Input = Disabled
Block Input        = false
Input Priority     = 10
```

Variables:

```text
KeyGuideWidget: WBP_PerfectPlacement_KeyGuide reference
PlayerController: PlayerController reference
bL3Held: Boolean
bCopyChordUsed: Boolean
```

Create:

```text
Initialize(
    InWidget: WBP_PerfectPlacement_KeyGuide,
    InPlayerController: PlayerController
)
```

Graph:

```text
Set KeyGuideWidget = InWidget
→ Set PlayerController = InPlayerController
```

Create:

```text
ActivateInput
```

```text
Set bL3Held = false
→ Set bCopyChordUsed = false
→ Enable Input(PlayerController)
```

Create:

```text
DeactivateInput
```

```text
Set bL3Held = false
→ Set bCopyChordUsed = false
→ Disable Input(PlayerController)
```

## 14. Wire the unfrozen physical chords

Add the controller L3 event.

L3 Pressed:

```text
Set bL3Held = true
→ Set bCopyChordUsed = false
```

L3 Released:

```text
Branch(bL3Held)
├─ false → Return
└─ true:
   Branch(bCopyChordUsed)
   ├─ true → no queue
   └─ false:
      KeyGuideWidget.QueueGamepadPhysicalInput(Unfrozen_L3)
   → Set bL3Held = false
   → Set bCopyChordUsed = false
```

Add D-pad Down Pressed:

```text
Branch(bL3Held)
├─ false → Return
└─ true:
   KeyGuideWidget.QueueGamepadPhysicalInput(Unfrozen_L3_DPadDown)
   → Set bCopyChordUsed = true
```

The delayed L3 release distinguishes an L3 tap from the L3 chord. It prevents
Copy from also queuing Freeze.

Set `Consume Input = false` on both unfrozen events. This lets the events
continue through Palworld's input stack instead of broadly stealing normal
controls whenever an unfrozen preview exists.

Do not add X, Y, LT, RT, R3, View, B, or Menu events to this actor.

## 15. Create BP_PP_FrozenGamepadInput

Create:

```text
BP_PP_FrozenGamepadInput
```

Class Defaults:

```text
Auto Receive Input = Disabled
Block Input        = false
Input Priority     = 20
```

Variables:

```text
KeyGuideWidget: WBP_PerfectPlacement_KeyGuide reference
PlayerController: PlayerController reference
bLeftTriggerHeld: Boolean
bRightTriggerHeld: Boolean
```

Create the same `Initialize`, `ActivateInput`, and `DeactivateInput` functions.

`ActivateInput`:

```text
Set bLeftTriggerHeld = false
→ Set bRightTriggerHeld = false
→ Enable Input(PlayerController)
```

`DeactivateInput`:

```text
Set bLeftTriggerHeld = false
→ Set bRightTriggerHeld = false
→ Disable Input(PlayerController)
```

## 16. Track both trigger modifiers

In Unreal Engine 5.1, add:

```text
Gamepad Left Trigger Axis
```

Graph:

```text
Axis Value >= 0.5
→ Set bLeftTriggerHeld
```

Add:

```text
Gamepad Right Trigger Axis
```

Graph:

```text
Axis Value >= 0.5
→ Set bRightTriggerHeld
```

These input-axis events update the Boolean state directly. Do not add Event
Tick. If the nodes expose Consume Input in their Details panel, enable it in
the frozen actor.

## 17. Create QueueFrozenDPad

In `BP_PP_FrozenGamepadInput`, create:

```text
QueueFrozenDPad(
    Direction: EPP_DPadDirection
)
```

The function first selects the modifier state:

```text
bLeftTriggerHeld?
├─ false:
│  bRightTriggerHeld?
│  ├─ false → Plain
│  └─ true  → RT
└─ true:
   bRightTriggerHeld?
   ├─ false → LT
   └─ true  → LT+RT
```

For each modifier state, switch on `Direction` and queue the corresponding
physical enum value.

Example:

```text
LT+RT state
→ Switch on EPP_DPadDirection
  ├─ Up:
  │  KeyGuideWidget.QueueGamepadPhysicalInput(Frozen_LT_RT_DPadUp)
  ├─ Down:
  │  KeyGuideWidget.QueueGamepadPhysicalInput(Frozen_LT_RT_DPadDown)
  ├─ Left:
  │  KeyGuideWidget.QueueGamepadPhysicalInput(Frozen_LT_RT_DPadLeft)
  └─ Right:
     KeyGuideWidget.QueueGamepadPhysicalInput(Frozen_LT_RT_DPadRight)
```

Wire all sixteen combinations. Compile before connecting the input events.

## 18. Wire the four D-pad events

Add:

```text
D-pad Up Pressed
→ QueueFrozenDPad(Up)

D-pad Down Pressed
→ QueueFrozenDPad(Down)

D-pad Left Pressed
→ QueueFrozenDPad(Left)

D-pad Right Pressed
→ QueueFrozenDPad(Right)
```

Set `Consume Input = true` on all four events.

Do not branch to logical actions here. The actor must not contain nodes named
Move Forward, Raise, Step Up, or Reset. It only reports physical chords.

## 19. Wire the standalone frozen buttons

Add:

```text
LB Pressed
→ KeyGuideWidget.QueueGamepadPhysicalInput(Frozen_LB)

RB Pressed
→ KeyGuideWidget.QueueGamepadPhysicalInput(Frozen_RB)

R3 Pressed
→ KeyGuideWidget.QueueGamepadPhysicalInput(Frozen_R3)

L3 Pressed
→ KeyGuideWidget.QueueGamepadPhysicalInput(Frozen_L3)
```

Set `Consume Input = true` on all four events.

These physical buttons are also configurable. Their default actions are merely
defined in `Config.gamepad.bindings.frozen`.

## 20. Add ModActor references

Open:

```text
ModActor
```

Create:

```text
KeyGuideWidget: WBP_PerfectPlacement_KeyGuide reference
UnfrozenInputActor: BP_PP_UnfrozenGamepadInput reference
FrozenInputActor: BP_PP_FrozenGamepadInput reference
PlayerController: PlayerController reference
```

In BeginPlay:

```text
Get Player Controller(0)
→ Set PlayerController

Create Widget(WBP_PerfectPlacement_KeyGuide)
→ Set KeyGuideWidget
→ Add to Viewport

Bind Event to KeyGuideWidget.RequestGamepadInputMode
→ bound event calls SetGamepadInputMode(Mode)

Spawn Actor BP_PP_UnfrozenGamepadInput
→ Set UnfrozenInputActor
→ Initialize(KeyGuideWidget, PlayerController)
→ DeactivateInput

Spawn Actor BP_PP_FrozenGamepadInput
→ Set FrozenInputActor
→ Initialize(KeyGuideWidget, PlayerController)
→ DeactivateInput

SetGamepadInputMode(Disabled)
```

Use Is Valid checks after widget creation and both Spawn Actor nodes.

## 21. Create ModActor.SetGamepadInputMode

Create:

```text
SetGamepadInputMode(
    Mode: EPP_GamepadInputMode
)
```

First enforce configuration:

```text
Is Valid(KeyGuideWidget)
→ Branch(KeyGuideWidget.GamepadEnabled)
  ├─ false:
  │  Is Valid(UnfrozenInputActor) → DeactivateInput
  │  Is Valid(FrozenInputActor)   → DeactivateInput
  │  Return
  └─ true:
     Switch on EPP_GamepadInputMode
```

`Disabled`:

```text
UnfrozenInputActor.DeactivateInput
FrozenInputActor.DeactivateInput
```

`Unfrozen`:

```text
FrozenInputActor.DeactivateInput
UnfrozenInputActor.ActivateInput
```

`Frozen`:

```text
UnfrozenInputActor.DeactivateInput
FrozenInputActor.ActivateInput
```

Always deactivate the old actor before activating the new one.

## 22. Add controller-device detection

Controller button and stick events should call:

```text
KeyGuideWidget.SetUsingGamepad(true)
```

For stick axes, apply an absolute threshold of approximately:

```text
0.35
```

This avoids switching the guide because of stick drift.

Existing keyboard and mouse detection should call:

```text
KeyGuideWidget.SetUsingGamepad(false)
```

Set device-detection events to `Consume Input = false`.

## 23. Lua physical chord contract

Lua reads the 22 widget serials and resolves them through:

```text
Config.gamepad.bindings
```

Examples:

```text
GamepadFrozenRTDPadRightSerial increments
→ physical chord RT+DPAD_RIGHT
→ look up configured frozen action
→ apply direction/swap preference
→ call that action's Lua callback
```

```text
GamepadFrozenLBSerial increments
→ physical chord LB
→ look up configured frozen action
→ call that action's Lua callback
```

The runtime:

- normalizes key and modifier names;
- sorts trigger modifiers into stable `LT`, then `RT` order;
- rejects unsupported chords;
- rejects duplicate chords within one state;
- caps replay with `maximum_actions_per_poll`;
- refreshes action-row keycaps from the effective configuration.

Configuration changes require reopening the world or restarting Palworld.

## 24. Lua-driven configurable keycaps

Every action row is populated from its resolved binding.

For:

```lua
reset = {
    key = "DPAD_DOWN",
    modifiers = { "LT", "RT" },
}
```

Lua finds `GP_FrozenResetChord` on the parent widget and updates these internal
children:

```text
Modifier1Icon      = T_KeyGuide_L2
Modifier1Box       = Visible
Modifier1Separator = Visible
Modifier2Icon      = T_KeyGuide_R2
Modifier2Box       = Visible
Modifier2Separator = Visible
PrimaryIcon        = T_KeyGuide_CrossD
PrimaryBox         = Visible
```

For:

```lua
reset = "R3"
```

Lua collapses both modifier boxes and separators, then updates:

```text
GP_FrozenResetChord.PrimaryIcon = T_KeyGuide_R3
GP_FrozenResetChord.PrimaryBox  = Visible
```

Do not assign fallback textures in Blueprint. A missing or invalid configured
binding should collapse its chord widgets rather than display a misleading
default.

## 25. Editor validation

### Widget

Verify:

1. `WBP_PerfectPlacement_GamepadChord` contains the eight exact internal
   variable names from Step 6.
2. Its three Images have empty brushes.
3. Its three Size Boxes are `32 × 32`.
4. The parent widget exposes all fourteen exact chord-instance names.
5. Unfrozen contains exactly the Freeze and Copy overlay rows.
6. Frozen Unfreeze is the only standalone row.
7. `GamepadMoveKeyGroups`, `GamepadAdjustKeyGroups`, and
   `GamepadStepResetKeyGroups` each contain exactly two overlays.
8. All five paired rows use the exact separator and label names from Steps 7
   and 8.
9. Every `Set Brush From Texture` call has Match Size disabled.
10. Keyboard pages remain at switcher index 0.
11. Gamepad pages remain at switcher index 1.

### Physical serials

Temporarily print every enum entry passed into
`QueueGamepadPhysicalInput`.

Verify:

1. Plain D-pad queues a plain frozen enum.
2. Holding only LT queues an LT enum.
3. Holding only RT queues an RT enum.
4. Holding LT and RT queues an LT+RT enum.
5. Releasing either trigger immediately changes the selected chord family.
6. L3+Down while unfrozen queues only the chord entry.
7. Releasing L3 after the unfrozen chord does not also queue plain L3.

Remove Print String nodes after testing.

### Input ownership

Verify:

1. Disabled mode enables neither input actor.
2. Unfrozen mode enables only the unfrozen actor.
3. Frozen mode enables only the frozen actor.
4. Unfrozen X, Y, LT, RT, R3, View, B, and Menu remain untouched.
5. Frozen D-pad, LT, RT, LB, RB, L3, and R3 are consumed.

## 26. Configuration validation

Test each of these configurations separately.

### RT plus D-pad

```lua
step_up = {
    key = "DPAD_RIGHT",
    modifiers = { "RT" },
}
```

Verify:

- RT + D-pad Right increases the step;
- the Step Up row displays RT + D-pad Right;
- LT + D-pad Right no longer performs Step Up unless assigned elsewhere.

### Both triggers plus D-pad

```lua
reset = {
    key = "DPAD_DOWN",
    modifiers = { "RT", "LT" },
}
```

Verify:

- modifier order is normalized to LT + RT;
- LT + RT + D-pad Down resets;
- the Reset row displays both trigger icons and D-pad Down.

### Duplicate chord

Assign two frozen actions to the same chord.

Verify:

- Lua logs the duplicate;
- the first action in the stable action order keeps the chord;
- the rejected action row has no displayed chord;
- one physical press never executes two actions.

### Unsupported unfrozen chord

Assign unfrozen Copy to `RT`.

Verify:

- Lua logs that RT is not captured in unfrozen mode;
- the Copy chord widgets remain collapsed;
- Palworld's unfrozen RT placement behavior is unchanged.

### Disabled gamepad support

Set:

```lua
enabled = false
```

Verify:

- the keyboard guide remains visible;
- controller events cannot select a gamepad panel;
- both gamepad input actors remain disabled;
- the Lua gamepad serial monitor does not start.

## 27. In-game validation

After cooking the Blueprint pak and deploying the Lua runtime:

1. Start Palworld with keyboard/mouse.
2. Enter build mode and create a placement preview.
3. Touch the controller and confirm the unfrozen controller page appears.
4. Confirm the keyguide textures came from Palworld and are not cooked into
   the mod.
5. Confirm every icon is 32 × 32 and unsquashed.
6. Test unfrozen Freeze and Copy.
7. Freeze the preview.
8. Test every plain D-pad binding.
9. Test all four LT + D-pad combinations.
10. Test all four RT + D-pad combinations.
11. Test at least one LT + RT + D-pad binding.
12. Test LB, RB, L3, and R3 after remapping them to different frozen actions.
13. Confirm X, Y, LT, RT, R3, View, B, and Menu retain their Palworld behavior
    after returning to unfrozen mode.
14. Exit build mode and confirm both input actors are disabled.

The implementation is complete only when the displayed chord, queued physical
serial, configured action, and resulting Lua callback all agree.
