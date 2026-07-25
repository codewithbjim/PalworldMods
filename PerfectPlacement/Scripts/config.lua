-- Perfect Placement user settings.
-- Unreal Engine uses centimeters for world-space distances.

return {
    ui = {
        -- Implemented by the companion Blueprint Logic Mod. Lua discovers the
        -- spawned host by generated class name and calls its public functions.
        host_class_name = "WBP_PerfectPlacement_KeyGuide_C",
        show_frozen_guide_function = "ShowFrozenGuide",
        show_unfrozen_guide_function = "ShowUnfrozenGuide",
        hide_function = "HideGuide",
        refresh_function = "RefreshGuide",
        show_frozen_toast_function = "ShowFrozenToast",
        show_unfrozen_toast_function = "ShowUnfrozenToast",
        hide_toast_function = "HideToast",
        move_step_property = "MoveStepCm",
        gamepad_enabled_property = "GamepadEnabled",
        use_palworld_keycaps = true,

        -- Keep the old stock-widget experiment disabled. It is retained in
        -- main.lua only as an optional diagnostic fallback while the custom
        -- widget pak is being developed.
        use_stock_keyguide_fallback = false,
    },

    auto_unfreeze = {
        enabled = true,

        -- Palworld build-screen actions that are unsafe while the builder
        -- component and preview tick are suspended. Hooks run before the
        -- original action, restoring normal placement control first.
        building_action_functions = {
            "ReturnToMainMenu",
            "OnEsc",
            "ChangeMode",
            "Destruct",
        },

        -- These functions cover Tab/main-menu screens, Escape, and both forms
        -- of the construction selection menu without polling cached widgets.
        input_listener_action_functions = {
            "OpenMenu_Internal",
            "OpenBuildMenu",
            "OpenBuildRadialMenu",
            "OpenBuildRadialMenuWithSelectedIndex",
            "OnTriggerEscape",
        },

        -- These construction events fire when Palworld has rebuilt the
        -- placement HUD for an active preview. They restore the unfrozen guide
        -- immediately instead of waiting for the lifecycle polling fallback.
        construction_resume_functions = {
            "Setup",
        },
    },

    movement = {
        fine = 1.0,
        normal = 10.0,
        coarse = 100.0,
        minimum = 0.1,
        maximum = 1000.0,
        step_scale = 10.0,
        maximum_below_initial_cm = 25.0,
        maximum_above_initial_cm = 650.0,
    },

    rotation = {
        fine = 1.0,
        normal = 5.0,
        coarse = 15.0,
    },

    -- Gamepad actions are captured as physical chords by the companion
    -- Blueprint and delivered to Lua through monotonically increasing counters.
    -- Frozen bindings may use any captured standalone button or any D-pad
    -- direction combined with LT, RT, or LT+RT. Unfrozen bindings intentionally
    -- remain limited to the two safe chords captured by the unfrozen actor.
    gamepad = {
        enabled = true,
        poll_interval_ms = 50,
        maximum_actions_per_poll = 32,

        -- These preferences are applied after configurable chord resolution.
        invert_forward_back = false,
        invert_height = false,
        swap_rotate_buttons = false,

        -- Reserved for hold-repeat support in the companion Blueprint.
        repeat_delay_ms = 300,
        repeat_interval_ms = 80,

        -- Live Blueprint chord configuration. Supported frozen keys are
        -- DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT, LB, RB, R3, and L3.
        -- D-pad bindings may add LT, RT, or both as modifiers. Supported
        -- unfrozen chords are L3 and L3+DPAD_DOWN only.
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
    },

    -- Baseline bindings. DarnMenu overrides saved keyboard and mouse actions,
    -- including Ctrl/Alt/Shift chords. Symbolic key names drive both UE4SS
    -- input registration and the keycaps in the companion UI. Supported names
    -- include A-Z, 0-9, F1-F12,
    -- navigation keys, common punctuation, NUMPAD_0 through NUMPAD_9, numpad
    -- operators, LEFT_MOUSE, RIGHT_MOUSE, MIDDLE_MOUSE, MOUSE_BUTTON_4, and
    -- MOUSE_BUTTON_5. Every action may use any combination of CONTROL, ALT,
    -- and SHIFT; the UI shows modifiers in that order.
    bindings = {
        move_left = "NUMPAD_4",
        move_right = "NUMPAD_6",
        move_forward = "NUMPAD_8",
        move_back = "NUMPAD_2",
        move_up = "NUMPAD_3",
        move_down = "NUMPAD_1",
        reset = "NUMPAD_5",
        rotate_left = "NUMPAD_7",
        rotate_right = "NUMPAD_9",
        step_down = "NUMPAD_SUBTRACT",
        step_up = "NUMPAD_ADD",
        toggle_freeze = "MIDDLE_MOUSE",
        copy_piece = {
            key = "MIDDLE_MOUSE",
            modifiers = { "SHIFT" },
        },
    },

    -- When true, Perfect Placement periodically reapplies the stored transform.
    -- This prevents Palworld's normal placement trace from pulling a frozen
    -- preview back to the crosshair while the player walks around.
    -- The player BuilderComponent is suspended while editing, so continuous
    -- transform reapplication is unnecessary and can overload the game thread.
    hold_locked_transform = false,
    transform_refresh_ms = 16,

    diagnostics = {
        verbose = false,

        -- These are intentionally isolated here because Palworld 1.0 class
        -- names must be confirmed from a live UE4SS header/actor dump.
        preview_class_names = {
            "PalBuildObject",
            "PalBuildObjectBase",
            "PalBuildObjectIndicator",
            "BP_BuildObject_Base_C",
        },

        -- Name fragments used to rank objects found through FindAllOf.
        preferred_name_fragments = {
            "Preview",
            "Indicator",
            "BuildObject",
        },
        rejected_name_fragments = {
            "Default__",
            "CDO",
        },

        -- APalBuildObject uses the Simulation state for an uncommitted build
        -- object in older public header dumps. The live 1.0 dump must confirm
        -- which of these property names is present.
        simulation_state_properties = {
            "CurrentState",
            "State",
        },
    },
}
