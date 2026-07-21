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

    -- When true, Perfect Placement periodically reapplies the stored transform.
    -- This prevents Palworld's normal placement trace from pulling a locked
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
