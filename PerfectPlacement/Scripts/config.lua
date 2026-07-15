-- Perfect Placement user settings.
-- Unreal Engine uses centimeters for world-space distances.

return {
    movement = {
        fine = 1.0,
        normal = 10.0,
        coarse = 100.0,
        minimum = 0.1,
        maximum = 1000.0,
        step_scale = 10.0,
    },

    rotation = {
        fine = 1.0,
        normal = 5.0,
        coarse = 15.0,
    },

    -- Movement is calculated from the camera yaw. Vertical movement always
    -- follows world Z, so looking up or down does not change the move step.
    camera_relative_movement = true,

    -- When true, Perfect Placement periodically reapplies the stored transform.
    -- This prevents Palworld's normal placement trace from pulling a locked
    -- preview back to the crosshair while the player walks around.
    hold_locked_transform = true,
    transform_refresh_ms = 16,

    diagnostics = {
        verbose = true,

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
