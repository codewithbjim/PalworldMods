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
        use_palworld_keycaps = true,

        -- Keep the old stock-widget experiment disabled. It is retained in
        -- main.lua only as an optional diagnostic fallback while the custom
        -- widget pak is being developed.
        use_stock_keyguide_fallback = false,
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

    validity = {
        -- Experimental. Rechecking overlaps and repainting every material after
        -- frozen movement can cause visible frame-time spikes on large pieces.
        refresh_frozen_feedback = false,
    },

    -- Fallback bindings used when DarnMenu is absent or has no saved override.
    -- Symbolic key names drive both UE4SS input registration and the
    -- keycaps in the companion UI. Supported names include A-Z, 0-9, F1-F12,
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
        freeze_to_piece = {
            key = "MIDDLE_MOUSE",
            modifiers = { "CONTROL", "SHIFT" },
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
