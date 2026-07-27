local Config = require("config")
local Keybindings = require("keybindings")
local DarnMenu = require("darnmenu")
local UEHelpers = require("UEHelpers")

local MOD = "PerfectPlacement"

local State = {
    SEARCHING = "searching",
    READY = "ready",
    FREEZING = "freezing",
    EDITING = "editing",
    UNFREEZING = "unfreezing",
}

local state = State.SEARCHING
local preview_actor = nil
local transform_actor = nil
local preview_root_component = nil
local preview_root_previous_mobility = nil
local desired_location = nil
local desired_rotation = nil
local current_move_step = nil
local transform_loop_started = false
local preview_tick_was_enabled = nil
local builder_component = nil
local cached_builder_component = nil
local cached_construction_widget = nil
local builder_tick_was_enabled = nil
local lifecycle_monitor_started = false
local lifecycle_monitor_last_tick = -1000.0
local lifecycle_ui_refresh_ticks = 0
local builder_fallback_scan_cooldown = 0
local construction_guide_mode = nil
local building_mode_exit_checks = 0
local unfrozen_ui_builder_component = nil
local unfrozen_ui_preview_visible = nil
local notification_generation = 0
local locked_preview_name = nil
local release_preview
local update_construction_hotkey_guide
local locked_origin_location = nil
local locked_origin_rotation = nil
local locked_origin_pivot = nil
local last_preview_overlap_state = nil
local rotation_pivot = nil
local rotation_pivot_local_offset = nil
local preview_relative_location = nil
local preview_relative_rotation = nil
local freeze_transition_generation = 0
local freeze_transition_input_locked = false
local keyguide_hook_registered = false
local KEYGUIDE_SETUP_PATH = "/Game/Pal/Blueprint/UI/UserInterface/InGame/Construction/WBP_IngameConstruction.WBP_IngameConstruction_C:SetupKeyGuide"
local perfect_placement_ui_host = nil
local ui_host_missing_was_logged = false
local keycap_ui_host = nil
local resolved_bindings = nil
local keycap_texture_cache = {}

local LIFECYCLE_INTERVAL_MS = 100
local IDLE_UI_REFRESH_TICKS = 5
local BUILDER_FALLBACK_RETRY_TICKS = 10
local FREEZE_TRANSITION_SETTLE_MS = 500
local retained_async_callbacks = {}
local retained_async_callback_serial = 0

local function log(message)
    print(string.format("[%s] %s\n", MOD, message))
end

DarnMenu.apply_settings(Config, log)
current_move_step = Config.movement.normal

local function retain_async_callback(callback, label)
    retained_async_callback_serial = retained_async_callback_serial + 1
    local callback_id = retained_async_callback_serial
    local retained_callback
    retained_callback = function(...)
        local ok, error_message = pcall(callback, ...)
        retained_async_callbacks[callback_id] = nil
        if not ok then
            log(string.format(
                "%s failed: %s",
                label or "Asynchronous callback",
                tostring(error_message)
            ))
        end
    end
    retained_async_callbacks[callback_id] = retained_callback
    return retained_callback, callback_id
end

local function execute_in_game_thread_retained(callback, label)
    local retained_callback, callback_id =
        retain_async_callback(callback, label)
    local ok, error_message = pcall(
        ExecuteInGameThread,
        retained_callback
    )
    if not ok then
        retained_async_callbacks[callback_id] = nil
        log(string.format(
            "Could not queue %s: %s",
            label or "game-thread callback",
            tostring(error_message)
        ))
        return false
    end
    return true
end

local function execute_in_game_thread_with_retained_delay(
    delay_ms,
    callback,
    label
)
    local delayed_callback, callback_id =
        retain_async_callback(function()
            execute_in_game_thread_retained(callback, label)
        end, label)
    local ok, error_message = pcall(
        ExecuteWithDelay,
        delay_ms,
        delayed_callback
    )
    if not ok then
        retained_async_callbacks[callback_id] = nil
        log(string.format(
            "Could not queue %s: %s",
            label or "delayed game-thread callback",
            tostring(error_message)
        ))
        return false
    end
    return true
end

local function begin_freeze_transition(next_state)
    freeze_transition_generation = freeze_transition_generation + 1
    freeze_transition_input_locked = true
    state = next_state
    return freeze_transition_generation
end

local function complete_freeze_transition(transition_id, stable_state)
    if transition_id ~= freeze_transition_generation then
        return
    end
    state = stable_state
    freeze_transition_input_locked = false
end

local function settle_freeze_transition(transition_id, stable_state)
    local queued = execute_in_game_thread_with_retained_delay(
        FREEZE_TRANSITION_SETTLE_MS,
        function()
            complete_freeze_transition(transition_id, stable_state)
        end,
        "Freeze transition settle callback"
    )
    if not queued then
        complete_freeze_transition(transition_id, stable_state)
    end
end

local function load_resolved_bindings()
    DarnMenu.register(log)

    local configured_bindings = {}
    for _, action in ipairs(Keybindings.action_order) do
        local configured = Config.bindings ~= nil and Config.bindings[action] or nil
        if configured == nil and action == "toggle_freeze" and Config.bindings ~= nil then
            configured = Config.bindings.toggle_lock
        end
        configured_bindings[action] = configured
    end

    local darnmenu_bindings = DarnMenu.load(Keybindings.action_order, log)
    if darnmenu_bindings ~= nil then
        for action, binding in pairs(darnmenu_bindings) do
            configured_bindings[action] = binding
        end
    end
    return Keybindings.resolve(configured_bindings, log)
end
resolved_bindings = load_resolved_bindings()

local function verbose(message)
    if Config.diagnostics.verbose then
        log(message)
    end
end

local function is_valid(object)
    if object == nil then
        return false
    end

    local ok, result = pcall(function()
        return object:IsValid()
    end)
    return ok and result == true
end

local function full_name(object)
    if not is_valid(object) then
        return "<invalid>"
    end

    local ok, value = pcall(function()
        return object:GetFullName()
    end)
    if ok then
        return tostring(value)
    end
    return "<name unavailable>"
end

local KEYCAP_IMAGE_SLOTS = {
    move_left = { "Num4Icon" },
    move_right = { "Num6Icon" },
    move_forward = { "Num8Icon" },
    move_back = { "Num2Icon" },
    move_up = { "Num3Icon" },
    move_down = { "Num1Icon" },
    reset = { "Num5Icon" },
    rotate_left = { "Num7Icon" },
    rotate_right = { "Num9Icon" },
    step_down = { "NumMinusIcon" },
    step_up = { "NumPlusIcon" },
    toggle_freeze = {
        "FreezeMouseWheelButtonIcon",
        "UnfreezeMouseWheelButtonIcon",
    },
    copy_piece = { "CopyMouseWheelButtonIcon" },
}

-- Preferred companion-widget contract. Each child is an instance of
-- WBP_PerfectPlacement_KeyChord and exposes:
-- SetChord(CtrlTexture, AltTexture, ShiftTexture, PrimaryTexture,
--          ShowCtrl, ShowAlt, ShowShift).
local CHORD_WIDGET_SLOTS = {
    move_left = { "MoveLeftChord" },
    move_right = { "MoveRightChord" },
    move_forward = { "MoveForwardChord" },
    move_back = { "MoveBackwardChord" },
    move_up = { "MoveUpChord" },
    move_down = { "MoveDownChord" },
    reset = { "ResetChord" },
    rotate_left = { "RotateLeftChord" },
    rotate_right = { "RotateRightChord" },
    step_down = { "StepDownChord" },
    step_up = { "StepUpChord" },
    toggle_freeze = { "FreezeChord", "UnfreezeChord" },
    copy_piece = { "CopyChord" },
}

local function load_keycap_texture(asset)
    if asset == nil then
        return nil
    end

    local cached = keycap_texture_cache[asset.texture_object_path]
    if is_valid(cached) then
        return cached
    end

    local load_ok, loaded = pcall(function()
        -- LoadAsset needs the full UObject path. Passing only the package path
        -- makes UE4SS return a UPackage and logs "could be a package", which
        -- leaves the UMG Image brush blank.
        return LoadAsset(asset.texture_object_path)
    end)
    if load_ok and is_valid(loaded) then
        keycap_texture_cache[asset.texture_object_path] = loaded
        return loaded
    end

    local find_ok, found = pcall(function()
        return StaticFindObject(asset.texture_object_path)
    end)
    if find_ok and is_valid(found) then
        keycap_texture_cache[asset.texture_object_path] = found
        return found
    end

    log("Could not load Palworld keycap: " .. asset.texture_path)
    return nil
end

local function set_keycap_image(host, property_name, texture, hide_on_failure)
    local image_ok, image = pcall(function()
        return host[property_name]
    end)
    if not image_ok or not is_valid(image) then
        log("Companion UI keycap image is missing: " .. property_name)
        return false
    end

    if not is_valid(texture) then
        if hide_on_failure then
            pcall(function()
                image:SetVisibility(1)
            end)
        end
        return false
    end

    local set_ok, set_error = pcall(function()
        image:SetBrushFromTexture(texture, false)
        image:SetVisibility(0)
    end)
    if not set_ok then
        log(string.format(
            "Could not update keycap image %s: %s",
            property_name,
            tostring(set_error)
        ))
        return false
    end
    return true
end

local function has_modifier(binding, expected)
    if binding == nil or binding.disabled then
        return false
    end
    for _, modifier in ipairs(binding.modifiers) do
        if modifier == expected then
            return true
        end
    end
    return false
end

local function set_chord_widget(
    host,
    property_name,
    binding,
    primary_texture,
    modifier_textures
)
    local widget_ok, widget = pcall(function()
        return host[property_name]
    end)
    if not widget_ok or not is_valid(widget) then
        return false
    end

    -- UE4SS can locate and invoke the Blueprint SetChord function, but on the
    -- current Palworld build its Texture2D/Boolean arguments do not reach the
    -- graph reliably. Update the named child widgets directly instead.
    local direct_ok = pcall(function()
        local ctrl_icon = widget.CtrlIcon
        local alt_icon = widget.AltIcon
        local shift_icon = widget.ShiftIcon
        local primary_icon = widget.PrimaryIcon
        local ctrl_box = widget.CtrlBox
        local alt_box = widget.AltBox
        local shift_box = widget.ShiftBox
        local primary_box = widget.PrimaryBox
        local ctrl_separator = widget.CtrlSeparator
        local alt_separator = widget.AltSeparator
        local shift_separator = widget.ShiftSeparator

        if not is_valid(ctrl_icon)
            or not is_valid(alt_icon)
            or not is_valid(shift_icon)
            or not is_valid(primary_icon)
            or not is_valid(ctrl_box)
            or not is_valid(alt_box)
            or not is_valid(shift_box)
            or not is_valid(primary_box)
            or not is_valid(ctrl_separator)
            or not is_valid(alt_separator)
            or not is_valid(shift_separator)
        then
            error("one or more chord child widgets are missing")
        end

        -- Palworld's stock keycaps are 40x40. Match the texture and enforce a
        -- square SizeBox so HorizontalBox constraints cannot distort it.
        ctrl_icon:SetBrushFromTexture(modifier_textures.CONTROL, true)
        alt_icon:SetBrushFromTexture(modifier_textures.ALT, true)
        shift_icon:SetBrushFromTexture(modifier_textures.SHIFT, true)
        primary_icon:SetBrushFromTexture(primary_texture, true)
        for _, keycap_box in ipairs({
            ctrl_box,
            alt_box,
            shift_box,
            primary_box,
        }) do
            keycap_box:SetWidthOverride(40.0)
            keycap_box:SetHeightOverride(40.0)
        end

        ctrl_box:SetVisibility(has_modifier(binding, "CONTROL") and 0 or 1)
        alt_box:SetVisibility(has_modifier(binding, "ALT") and 0 or 1)
        shift_box:SetVisibility(has_modifier(binding, "SHIFT") and 0 or 1)
        ctrl_separator:SetVisibility(has_modifier(binding, "CONTROL") and 0 or 1)
        alt_separator:SetVisibility(has_modifier(binding, "ALT") and 0 or 1)
        shift_separator:SetVisibility(has_modifier(binding, "SHIFT") and 0 or 1)
        primary_box:SetVisibility(
            binding ~= nil
                and not binding.disabled
                and is_valid(primary_texture)
                and 0
                or 1
        )
    end)
    if direct_ok then
        return true
    end

    local callback = widget.SetChord
    if callback == nil then
        log("Companion chord widget is missing SetChord: " .. property_name)
        return false
    end

    local set_ok, set_error = pcall(function()
        callback(
            widget,
            modifier_textures.CONTROL,
            modifier_textures.ALT,
            modifier_textures.SHIFT,
            primary_texture,
            has_modifier(binding, "CONTROL"),
            has_modifier(binding, "ALT"),
            has_modifier(binding, "SHIFT")
        )
    end)
    if not set_ok then
        log(string.format(
            "Could not update chord widget %s: %s",
            property_name,
            tostring(set_error)
        ))
        return false
    end
    return true
end

local function apply_configured_keycaps(host)
    local ui_config = Config.ui or {}
    if not ui_config.use_palworld_keycaps or not is_valid(host) then
        return
    end
    if is_valid(keycap_ui_host) and full_name(keycap_ui_host) == full_name(host) then
        return
    end

    local modifier_textures = {}
    for _, modifier in ipairs(Keybindings.modifier_order) do
        modifier_textures[modifier] = load_keycap_texture(
            Keybindings.get_modifier_asset(modifier)
        )
    end

    local chord_widgets_updated = 0
    local chord_widget_actions = {}
    for _, action in ipairs(Keybindings.action_order) do
        local binding = resolved_bindings[action]
        local texture = nil
        if binding ~= nil and not binding.disabled then
            texture = load_keycap_texture(binding.key_info)
        end

        local action_uses_chord_widget = false
        for _, property_name in ipairs(CHORD_WIDGET_SLOTS[action] or {}) do
            if set_chord_widget(
                host,
                property_name,
                binding,
                texture,
                modifier_textures
            ) then
                action_uses_chord_widget = true
                chord_widgets_updated = chord_widgets_updated + 1
            end
        end

        if not action_uses_chord_widget then
            for _, property_name in ipairs(KEYCAP_IMAGE_SLOTS[action] or {}) do
                set_keycap_image(
                    host,
                    property_name,
                    texture,
                    binding == nil or binding.disabled or not binding.is_default
                )
            end
        else
            chord_widget_actions[action] = true
        end
    end

    local copy_binding = resolved_bindings.copy_piece
    if not chord_widget_actions.copy_piece then
        local modifier = copy_binding ~= nil and copy_binding.modifiers[1] or nil
        local modifier_texture = modifier_textures[modifier]
        set_keycap_image(
            host,
            "LShiftIcon",
            modifier_texture,
            modifier == nil or modifier_texture == nil
        )
        if copy_binding ~= nil and #copy_binding.modifiers > 1 then
            log("Legacy companion UI can show only the first Copy modifier.")
        end
    end

    keycap_ui_host = host
    if chord_widgets_updated > 0 then
        log(string.format(
            "Configured Palworld key chords applied to %d companion widgets.",
            chord_widgets_updated
        ))
    else
        log("Configured Palworld keycaps applied through the legacy companion UI.")
    end
end

local function contains_any(value, fragments)
    for _, fragment in ipairs(fragments) do
        if string.find(value, fragment, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function candidate_score(object)
    local name = full_name(object)
    if contains_any(name, Config.diagnostics.rejected_name_fragments) then
        return -1000
    end

    local score = 0
    for index, fragment in ipairs(Config.diagnostics.preferred_name_fragments) do
        if string.find(name, fragment, 1, true) ~= nil then
            score = score + (#Config.diagnostics.preferred_name_fragments - index + 1)
        end
    end


    for _, property_name in ipairs(Config.diagnostics.simulation_state_properties) do
        local ok, value = pcall(function()
            return object[property_name]
        end)
        if ok and value ~= nil then
            local rendered = tostring(value)
            verbose(string.format(
                "Candidate property %s=%s name=%s",
                property_name,
                rendered,
                name
            ))
            if value == 1 or string.find(rendered, "Simulation", 1, true) ~= nil then
                score = score + 100
            end
        end
    end
    return score
end

local function safe_find_all_of(class_name)
    local ok, objects = pcall(function()
        return FindAllOf(class_name)
    end)
    if not ok or objects == nil then
        return {}
    end
    return objects
end

local function find_perfect_placement_ui_host()
    if is_valid(perfect_placement_ui_host) then
        return perfect_placement_ui_host
    end

    local ui_config = Config.ui or {}
    local class_name = ui_config.host_class_name or "WBP_PerfectPlacement_KeyGuide_C"
    local ok, host = pcall(function()
        return FindFirstOf(class_name)
    end)
    if ok and is_valid(host) then
        perfect_placement_ui_host = host
        ui_host_missing_was_logged = false
        apply_configured_keycaps(host)
        log("Companion UI host found: " .. full_name(host))
        return host
    end

    if not ui_host_missing_was_logged then
        log("Companion UI host is not loaded yet (expected " .. class_name .. ").")
        ui_host_missing_was_logged = true
    end
    return nil
end

local function call_ui_host_function(host, function_name)
    local callback = host[function_name]
    if callback == nil then
        error("UI host function is missing: " .. tostring(function_name))
    end
    callback(host)
end

local function update_perfect_placement_ui(is_locked, show_transition_toast, hide_all)
    local host = find_perfect_placement_ui_host()
    if not is_valid(host) then
        return false
    end

    local ui_config = Config.ui or {}
    local ok, error_message = pcall(function()
        local move_step_property = ui_config.move_step_property or "MoveStepCm"
        host[move_step_property] = current_move_step

        if hide_all then
            call_ui_host_function(
                host,
                ui_config.hide_function or "HideGuide"
            )
            call_ui_host_function(
                host,
                ui_config.hide_toast_function or "HideToast"
            )
        elseif is_locked then
            call_ui_host_function(
                host,
                ui_config.show_frozen_guide_function or "ShowFrozenGuide"
            )
            if show_transition_toast ~= false then
                call_ui_host_function(
                    host,
                    ui_config.show_frozen_toast_function or "ShowFrozenToast"
                )
            end
        else
            call_ui_host_function(
                host,
                ui_config.show_unfrozen_guide_function or "ShowUnfrozenGuide"
            )
            if show_transition_toast then
                call_ui_host_function(
                    host,
                    ui_config.show_unfrozen_toast_function or "ShowUnfrozenToast"
                )
            else
                call_ui_host_function(
                    host,
                    ui_config.hide_toast_function or "HideToast"
                )
            end
        end
    end)
    if not ok then
        log("Companion UI update failed: " .. tostring(error_message))
        perfect_placement_ui_host = nil
        return false
    end
    return true
end

local function refresh_perfect_placement_ui()
    if state ~= State.EDITING then
        return
    end
    local host = find_perfect_placement_ui_host()
    if not is_valid(host) then
        return
    end

    local ui_config = Config.ui or {}
    local ok, error_message = pcall(function()
        host[ui_config.move_step_property or "MoveStepCm"] = current_move_step
        call_ui_host_function(
            host,
            ui_config.refresh_function or "RefreshGuide"
        )
    end)
    if not ok then
        log("Companion UI refresh failed: " .. tostring(error_message))
        perfect_placement_ui_host = nil
    end
end

local function discover_preview()
    local best_actor = nil
    local best_score = -1000
    local candidates_seen = 0

    for _, class_name in ipairs(Config.diagnostics.preview_class_names) do
        local objects = safe_find_all_of(class_name)
        for _, object in ipairs(objects) do
            if is_valid(object) then
                candidates_seen = candidates_seen + 1
                local score = candidate_score(object)
                verbose(string.format(
                    "Candidate class=%s score=%d name=%s",
                    class_name,
                    score,
                    full_name(object)
                ))
                if score > best_score then
                    best_score = score
                    best_actor = object
                end
            end
        end
    end

    if not is_valid(best_actor) then
        state = State.SEARCHING
        log(string.format(
            "No preview candidate found (%d objects checked).",
            candidates_seen
        ))
        return false
    end

    preview_actor = best_actor
    state = State.READY
    log("Selected preview candidate: " .. full_name(preview_actor))
    return true
end

local function read_preview_transform()
    if not is_valid(transform_actor) then
        return false
    end

    local ok, location, rotation = pcall(function()
        return transform_actor:K2_GetActorLocation(), transform_actor:K2_GetActorRotation()
    end)
    if not ok or location == nil or rotation == nil then
        log("The selected object does not expose the expected Actor transform methods.")
        return false
    end

    desired_location = {
        X = location.X,
        Y = location.Y,
        Z = location.Z,
    }
    desired_rotation = {
        Pitch = rotation.Pitch,
        Yaw = rotation.Yaw,
        Roll = rotation.Roll,
    }
    log(string.format(
        "Frozen transform source %s at (%.1f, %.1f, %.1f)",
        full_name(transform_actor),
        desired_location.X,
        desired_location.Y,
        desired_location.Z
    ))
    return true
end

local function apply_preview_transform()
    if freeze_transition_input_locked
        or state ~= State.EDITING
        or not is_valid(builder_component)
        or not is_valid(transform_actor)
        or not is_valid(preview_actor)
    then
        return false
    end
    if desired_location == nil or desired_rotation == nil then
        return false
    end

    local ok, error_message = pcall(function()
        if is_valid(transform_actor) then
            transform_actor:K2_SetActorLocationAndRotation(
                desired_location,
                desired_rotation,
                false,
                {},
                true
            )
        end
        if is_valid(preview_actor) then
            local preview_location = desired_location
            local preview_rotation = desired_rotation
            if preview_relative_location ~= nil and preview_relative_rotation ~= nil then
                local yaw = math.rad(desired_rotation.Yaw)
                preview_location = {
                    X = desired_location.X
                        + (math.cos(yaw) * preview_relative_location.X)
                        - (math.sin(yaw) * preview_relative_location.Y),
                    Y = desired_location.Y
                        + (math.sin(yaw) * preview_relative_location.X)
                        + (math.cos(yaw) * preview_relative_location.Y),
                    Z = desired_location.Z + preview_relative_location.Z,
                }
                preview_rotation = {
                    Pitch = desired_rotation.Pitch + preview_relative_rotation.Pitch,
                    Yaw = desired_rotation.Yaw + preview_relative_rotation.Yaw,
                    Roll = desired_rotation.Roll + preview_relative_rotation.Roll,
                }
            end
            preview_actor:K2_SetActorLocationAndRotation(
                preview_location,
                preview_rotation,
                false,
                {},
                true
            )
        end
    end)
    if not ok then
        log("Failed to apply preview transform: " .. tostring(error_message))
        return false
    end
    return true
end

local function start_transform_loop()
    if transform_loop_started or not Config.hold_locked_transform then
        return
    end
    transform_loop_started = true

    LoopAsync(Config.transform_refresh_ms, function()
        if state == State.EDITING then
            ExecuteInGameThread(function()
                apply_preview_transform()
            end)
        end
    end)
end

local function set_preview_tick_enabled(enabled)
    if not is_valid(preview_actor) then
        return false
    end

    local ok, error_message = pcall(function()
        preview_actor:SetActorTickEnabled(enabled)
    end)
    if not ok then
        log("Could not change preview actor tick state: " .. tostring(error_message))
        return false
    end
    return true
end

local function builder_component_from_player(player)
    if not is_valid(player) then
        return nil
    end

    local component_ok, component = pcall(function()
        return player.BuilderComponent
    end)
    if component_ok and is_valid(component) then
        cached_builder_component = component
        builder_fallback_scan_cooldown = 0
        verbose("Cached BuilderComponent on " .. full_name(player))
        return component
    end
    return nil
end

local function find_builder_component(allow_global_scan)
    if is_valid(cached_builder_component) then
        return cached_builder_component
    end
    cached_builder_component = nil

    local helper_ok, helper_pawn = pcall(function()
        return UEHelpers:GetPlayerPawn()
    end)
    if helper_ok then
        local component = builder_component_from_player(helper_pawn)
        if component ~= nil then
            return component
        end
    end

    local controller_ok, controller = pcall(function()
        return UEHelpers:GetPlayerController()
    end)
    if controller_ok and is_valid(controller) then
        local pawn_ok, controller_pawn = pcall(function()
            return controller:GetPawn()
        end)
        if pawn_ok then
            local component = builder_component_from_player(controller_pawn)
            if component ~= nil then
                return component
            end
        end

        local acknowledged_ok, acknowledged_pawn = pcall(function()
            return controller.AcknowledgedPawn
        end)
        if acknowledged_ok then
            local component = builder_component_from_player(acknowledged_pawn)
            if component ~= nil then
                return component
            end
        end
    end

    if allow_global_scan == false then
        return nil
    end

    verbose("Direct BuilderComponent lookup failed; scanning local player objects.")
    for _, player in ipairs(safe_find_all_of("PalPlayerCharacter")) do
        if is_valid(player) then
            local local_ok, is_local = pcall(function()
                return player:IsLocallyControlled()
            end)
            if local_ok and is_local then
                local component = builder_component_from_player(player)
                if component ~= nil then
                    return component
                end
            end
        end
    end
    return nil
end

local function find_active_build_context(allow_global_scan)
    local component = find_builder_component(allow_global_scan)
    if not is_valid(component) then
        return nil, nil, nil
    end

    local status_ok, in_building_mode, checker, target = pcall(function()
        local active_checker = component.InstallChecker
        local active_target = nil
        if is_valid(active_checker) then
            active_target = active_checker.TargetBuildObject
        end
        return component:IsInBuildingMode(), active_checker, active_target
    end)
    if not status_ok or not in_building_mode
        or not is_valid(checker) or not is_valid(target) then
        return nil, nil, nil
    end
    return component, checker, target
end

local function set_builder_tick_enabled(enabled)
    if builder_component == nil or not builder_component:IsValid() then
        return false
    end
    local ok, error_message = pcall(function()
        builder_component:SetComponentTickEnabled(enabled)
    end)
    if not ok then
        log("Could not change builder component tick state: " .. tostring(error_message))
        return false
    end
    return true
end

local function construction_ui_is_active()
    -- The builder component and preview can remain valid after construction
    -- mode closes, particularly while their ticks are suspended for Freeze.
    -- Live construction widgets supply an independent lifecycle signal. Check
    -- every instance because Unreal can retain a stale hidden widget while a
    -- newer construction screen is active.
    local function query_widget_visibility(construction)
        local visibility_ok, visible = pcall(function()
            return construction:IsVisible()
        end)
        if visibility_ok then
            return visible == true
        end

        local viewport_ok, in_viewport = pcall(function()
            return construction:IsInViewport()
        end)
        if viewport_ok then
            return in_viewport == true
        end
        return nil
    end

    local saw_valid_widget = is_valid(cached_construction_widget)
    local visibility_query_supported = false
    if saw_valid_widget then
        local cached_visibility =
            query_widget_visibility(cached_construction_widget)
        if cached_visibility == true then
            return true
        end
        visibility_query_supported = cached_visibility ~= nil
    end

    for _, construction in ipairs(safe_find_all_of("WBP_IngameConstruction_C")) do
        if is_valid(construction) and construction ~= cached_construction_widget then
            saw_valid_widget = true
            local visible = query_widget_visibility(construction)
            if visible ~= nil then
                visibility_query_supported = true
                if visible == true then
                    cached_construction_widget = construction
                    return true
                end
            end
        end
    end

    if not saw_valid_widget or visibility_query_supported then
        cached_construction_widget = nil
        return false
    end
    -- Older Palworld/UE4SS combinations may expose neither query. Treat that
    -- as unknown so the established builder checks remain authoritative.
    return nil
end

local function should_release_locked_preview()
    if state ~= State.EDITING then
        return false, nil
    end
    if not is_valid(preview_actor) then
        return true, "preview object was destroyed"
    end
    if builder_component == nil or not builder_component:IsValid() then
        return true, "builder component became invalid"
    end

    local mode_ok, in_building_mode = pcall(function()
        return builder_component:IsInBuildingMode()
    end)
    local construction_ui_active = construction_ui_is_active()
    local observed_construction_exit = (mode_ok and not in_building_mode)
        or construction_ui_active == false
    if observed_construction_exit then
        building_mode_exit_checks = building_mode_exit_checks + 1
        if building_mode_exit_checks >= 5 then
            if construction_ui_active == false then
                return true, "Palworld closed the construction UI"
            end
            return true, "Palworld exited building mode"
        end
    elseif (mode_ok and in_building_mode) or construction_ui_active == true then
        building_mode_exit_checks = 0
    end

    local target_ok, current_target = pcall(function()
        local checker = builder_component.InstallChecker
        if checker == nil or not checker:IsValid() then
            return nil
        end
        return checker.TargetBuildObject
    end)
    if target_ok then
        if not is_valid(current_target) then
            return true, "Palworld cleared the build preview"
        end
        if locked_preview_name ~= nil and full_name(current_target) ~= locked_preview_name then
            return true, "Palworld replaced the selected build preview"
        end
    end

    local state_ok, preview_state = pcall(function()
        return preview_actor.CurrentState
    end)
    if state_ok and preview_state ~= nil then
        local rendered_state = tostring(preview_state)
        if preview_state ~= 1 and string.find(rendered_state, "Simulation", 1, true) == nil then
            return true, "Palworld committed the build preview"
        end
    end
    return false, nil
end

local function start_lifecycle_monitor()
    if lifecycle_monitor_started then
        return
    end
    lifecycle_monitor_started = true
    LoopAsync(LIFECYCLE_INTERVAL_MS, function()
        lifecycle_monitor_last_tick = os.clock()
        if state == State.FREEZING or state == State.UNFREEZING then
            return
        end
        -- Frozen previews need responsive safety checks. Outside editing, do
        -- not enqueue game-thread work until the 2 Hz guide refresh is due.
        if state ~= State.EDITING then
            lifecycle_ui_refresh_ticks = lifecycle_ui_refresh_ticks + 1
            if lifecycle_ui_refresh_ticks < IDLE_UI_REFRESH_TICKS then
                return
            end
            lifecycle_ui_refresh_ticks = 0
        else
            lifecycle_ui_refresh_ticks = 0
        end

        ExecuteInGameThread(function()
            if state == State.FREEZING or state == State.UNFREEZING then
                return
            end
            if state == State.EDITING then
                local should_release, reason = should_release_locked_preview()
                if should_release then
                    log("Auto-releasing frozen preview: " .. tostring(reason) .. ".")
                    release_preview(reason)
                end
                return
            end

            if not is_valid(unfrozen_ui_builder_component) then
                unfrozen_ui_builder_component = nil
                local allow_global_scan = builder_fallback_scan_cooldown <= 0
                local candidate = find_builder_component(allow_global_scan)
                if is_valid(candidate) then
                    unfrozen_ui_builder_component = candidate
                    unfrozen_ui_preview_visible = nil
                elseif allow_global_scan then
                    -- Direct helpers are retried every idle refresh. A failed
                    -- full UObject scan is backed off for roughly five seconds.
                    builder_fallback_scan_cooldown = BUILDER_FALLBACK_RETRY_TICKS
                elseif builder_fallback_scan_cooldown > 0 then
                    builder_fallback_scan_cooldown = builder_fallback_scan_cooldown - 1
                end
            end

            if not is_valid(unfrozen_ui_builder_component) then
                return
            end

            local status_ok, in_building_mode, has_preview = pcall(function()
                local in_mode = unfrozen_ui_builder_component:IsInBuildingMode()
                local checker = unfrozen_ui_builder_component.InstallChecker
                local target = nil
                if is_valid(checker) then
                    target = checker.TargetBuildObject
                end
                return in_mode, is_valid(target)
            end)

            local construction_ui_active = construction_ui_is_active()
            local should_show = status_ok
                and in_building_mode
                and has_preview
                and construction_ui_active ~= false
            if should_show ~= unfrozen_ui_preview_visible then
                unfrozen_ui_preview_visible = should_show
                update_construction_hotkey_guide(false, false, not should_show)
            end

            if not status_ok then
                if cached_builder_component == unfrozen_ui_builder_component then
                    cached_builder_component = nil
                end
                unfrozen_ui_builder_component = nil
                unfrozen_ui_preview_visible = nil
                builder_fallback_scan_cooldown = 0
            end
        end)
    end)
end

local function refresh_locked_validity()
    if state ~= State.EDITING or not is_valid(builder_component) then
        return
    end
    local ok, operation_result = pcall(function()
        return builder_component:IsEnableBuild()
    end)
    if not ok or operation_result == nil then
        return
    end

    local operation_text = tostring(operation_result)
    local operation_number = tonumber(operation_text)
    local is_placeable = operation_number == 60
        or string.find(operation_text, "Success", 1, true) ~= nil
    if last_preview_overlap_state == is_placeable then
        return
    end
    last_preview_overlap_state = is_placeable
    log(string.format(
        "Frozen preview is %s (operation result: %s).",
        is_placeable and "placeable" or "not placeable",
        operation_text
    ))
end

local function object_path_from_full_name(name)
    local separator = string.find(name, " ", 1, true)
    if separator == nil then
        return name
    end
    return string.sub(name, separator + 1)
end

local function find_live_keyguide_row(construction, row_name)
    local construction_path = object_path_from_full_name(full_name(construction))
    local fallback = nil
    local transient_fallback = nil
    for _, candidate in ipairs(safe_find_all_of("WBP_Ingameconstruction_KeyGuide_C")) do
        if is_valid(candidate) then
            local candidate_name = full_name(candidate)
            if string.find(candidate_name, row_name, 1, true) ~= nil then
                if fallback == nil then
                    fallback = candidate
                end
                -- Runtime UMG instances are created in /Engine/Transient.
                -- Cooked WidgetTree templates under /Game are valid UObjects
                -- too, but changing them does not affect the displayed guide.
                local is_transient = string.find(
                    candidate_name,
                    "/Engine/Transient.",
                    1,
                    true
                ) ~= nil
                if transient_fallback == nil and is_transient then
                    transient_fallback = candidate
                end
                -- Runtime child widgets are outered to the owning construction
                -- instance's WidgetTree, so their full path contains the exact
                -- parent instance path. This avoids generated-property offsets.
                if is_transient and construction_path ~= "<invalid>"
                    and string.find(candidate_name, construction_path, 1, true) ~= nil then
                    return candidate
                end
            end
        end
    end
    return transient_fallback or fallback
end

local function setup_text_keyguide_row(construction, row_name, guide_text)
    local row = find_live_keyguide_row(construction, row_name)
    if not is_valid(row) then
        return false, "row not found"
    end
    -- Setup accepts Palworld UI action-table row names, not literal key names.
    -- Our numpad bindings have no UI action rows, so use the stock row's text
    -- block and collapse its glyph container instead of spawning blank icons.
    local ok, error_message = pcall(function()
        row.HorizontalBox_46:SetVisibility(1)
        row.Text_Main:SetText(FText(guide_text))
        row.Text_Main:SetVisibility(0)
        row:SetVisibility(0)
    end)
    return ok, error_message
end

local function set_default_rotate_guide_hidden(construction, hidden)
    local rotate_row = find_live_keyguide_row(
        construction,
        "WBP_Ingameconstruction_KeyGuide_Rotate"
    )
    if not is_valid(rotate_row) then
        log("Default mouse-wheel Rotate guide row was not found.")
        return false
    end
    rotate_row:SetVisibility(hidden and 1 or 0)
    return true
end

local function set_replacement_mode_guide_hidden(construction, hidden)
    -- Palworld assigns Rotate/Axis Alignment variants across generic live rows
    -- 5, 6, and 7 according to the current construction state. Collapse all
    -- three while Perfect Placement owns the frozen preview, then restore them
    -- when control returns to Palworld.
    local found_generic_row = false
    for _, row_name in ipairs({
        "WBP_Ingameconstruction_KeyGuide_5",
        -- "WBP_Ingameconstruction_KeyGuide_6",
        -- "WBP_Ingameconstruction_KeyGuide_7",
    }) do
        -- These are BlueprintReadOnly child-widget properties on the live
        -- WBP_IngameConstruction instance. Prefer them over FindAllOf, which
        -- can return a valid cooked WidgetTree template with the same name.
        local direct_ok, row = pcall(function()
            return construction[row_name]
        end)
        if not direct_ok or not is_valid(row) then
            row = find_live_keyguide_row(construction, row_name)
        end
        if is_valid(row) then
            row:SetVisibility(hidden and 1 or 0)
            found_generic_row = true
            verbose(string.format(
                "%s native guide row %s: %s",
                hidden and "Collapsed" or "Restored",
                row_name,
                full_name(row)
            ))
        end
    end
    if found_generic_row then
        return true
    end

    local replacement_row = nil
    for _, class_name in ipairs({ "BP_PalTextBlock_C", "TextBlock" }) do
        for _, text_widget in ipairs(safe_find_all_of(class_name)) do
            if is_valid(text_widget) then
                local text_ok, current_text = pcall(function()
                    local value = text_widget:GetText()
                    local string_ok, value_string = pcall(function()
                        return value:ToString()
                    end)
                    return string_ok and value_string or tostring(value)
                end)
                local normalized_text = string.lower(tostring(current_text))
                if text_ok and (
                    string.find(normalized_text, "axis alignment mode", 1, true) ~= nil
                    or string.find(normalized_text, "replacement mode", 1, true) ~= nil
                ) then
                    local row_name = string.match(
                        full_name(text_widget),
                        "(WBP_Ingameconstruction_KeyGuide_[%w_]+)%.WidgetTree"
                    )
                    if row_name ~= nil then
                        replacement_row = find_live_keyguide_row(construction, row_name)
                        if is_valid(replacement_row) then
                            log("Axis Alignment Mode uses live row " .. row_name .. ".")
                            break
                        end
                    end
                end
            end
        end
        if is_valid(replacement_row) then
            break
        end
    end
    if not is_valid(replacement_row) then
        log("Axis Alignment Mode guide row was not found.")
        return false
    end
    replacement_row:SetVisibility(hidden and 1 or 0)
    return true
end

local function set_native_locked_controls_hidden(construction, hidden)
    if not is_valid(construction) then
        return
    end
    -- Diagnostic isolation: leave the separately named Rotate row untouched
    -- while mapping generic construction rows 5/6/7.
    -- set_default_rotate_guide_hidden(construction, hidden)
    set_replacement_mode_guide_hidden(construction, hidden)
end

local function apply_locked_keyguide(construction)
    if state ~= State.EDITING or not is_valid(construction) then
        return
    end
    set_default_rotate_guide_hidden(construction, true)
    set_replacement_mode_guide_hidden(construction, true)
    for _, dormant_row_name in ipairs({
        "WBP_Ingameconstruction_KeyGuide_5",
        "WBP_Ingameconstruction_KeyGuide_7",
    }) do
        local dormant_row = find_live_keyguide_row(construction, dormant_row_name)
        if is_valid(dormant_row) then
            dormant_row:SetVisibility(1)
        end
    end
    -- Palworld's state graph keeps dormant rows 5 and 7 collapsed even after
    -- their child widgets are made visible. Row 6 has a live single-line
    -- layout slot, so keep the complete guide compact enough to fit that slot.
    local row_ok, row_error = setup_text_keyguide_row(
        construction,
        "WBP_Ingameconstruction_KeyGuide_6",
        "8/2/4/6 Move | 3/1 Up/Down | 7/9 Rotate | MMB Unfreeze"
    )
    if row_ok then
        log("Frozen construction key guide applied as a compact text row.")
        return
    end
    log("WBP_Ingameconstruction_KeyGuide_6 text setup failed: " .. tostring(row_error))
    log("Frozen construction key guide was not changed because text setup failed.")
end

local function hide_locked_keyguide(construction)
    if not is_valid(construction) then
        return
    end
    set_default_rotate_guide_hidden(construction, false)
    set_replacement_mode_guide_hidden(construction, false)
    for _, row_name in ipairs({
        "WBP_Ingameconstruction_KeyGuide_5",
        "WBP_Ingameconstruction_KeyGuide_6",
        "WBP_Ingameconstruction_KeyGuide_7",
    }) do
        local row = find_live_keyguide_row(construction, row_name)
        if is_valid(row) then
            pcall(function()
                row.HorizontalBox_46:SetVisibility(0)
            end)
            row:SetVisibility(1)
        end
    end
end

local function ensure_keyguide_hook()
    if keyguide_hook_registered then
        return true
    end
    local ok, pre_id, post_id = pcall(function()
        return RegisterHook(KEYGUIDE_SETUP_PATH, function()
            -- The guide must be changed after the Blueprint has rebuilt its
            -- rows. A no-op pre-hook keeps the UE4SS hook signature explicit.
        end, function(context)
            local construction = context
            local unwrap_ok, unwrapped = pcall(function()
                return context:get()
            end)
            if unwrap_ok and unwrapped ~= nil then
                construction = unwrapped
            end
            local apply_ok, apply_error = pcall(function()
                if Config.ui ~= nil and not Config.ui.use_stock_keyguide_fallback then
                    if state == State.EDITING then
                        set_native_locked_controls_hidden(construction, true)
                    end
                else
                    apply_locked_keyguide(construction)
                end
            end)
            if not apply_ok then
                log("Could not apply hooked construction guide: " .. tostring(apply_error))
            end
        end)
    end)
    if not ok or (pre_id == nil and post_id == nil) then
        log("Construction key-guide hook is not loaded yet.")
        return false
    end
    keyguide_hook_registered = true
    log("Construction key-guide post-hook registered.")
    return true
end

update_construction_hotkey_guide = function(is_locked, show_transition_toast, hide_all)
    local companion_ui_updated = update_perfect_placement_ui(
        is_locked,
        show_transition_toast,
        hide_all
    )

    local ok, error_message = pcall(function()
        if is_locked then
            ensure_keyguide_hook()
        end
        local construction = FindFirstOf("WBP_IngameConstruction_C")
        if not is_valid(construction) then
            log("Construction key-guide widget instance was not found.")
            return
        end
        set_native_locked_controls_hidden(construction, is_locked)

        -- The companion widget supplies Perfect Placement's own controls, but
        -- the stock Rotate and Axis Alignment rows still need to be suppressed
        -- while their inputs are unavailable during a frozen preview.
        if companion_ui_updated then
            return
        end
        if Config.ui ~= nil and not Config.ui.use_stock_keyguide_fallback then
            return
        end
        if is_locked then
            apply_locked_keyguide(construction)
        else
            hide_locked_keyguide(construction)
        end
        local model = construction.CachedModel
        if not is_valid(model) then
            model = FindFirstOf("PalUIBuildingModel")
        end
        if is_valid(model) then
            -- Rebuild through Palworld's own function. The Blueprint post-hook
            -- applies the frozen text while the widget context is guaranteed live.
            construction:SetupKeyGuide(model)
            -- Also reapply directly for UE4SS builds that do not invoke the
            -- Blueprint post-hook for calls originating from Lua.
            if is_locked then
                apply_locked_keyguide(construction)
            end
        else
            log("No live PalUIBuildingModel was found; skipped native guide rebuild.")
        end
    end)
    if not ok then
        log("Could not refresh construction hotkey guide: " .. tostring(error_message))
    end
end

local function show_preview_notification(message, color)
    notification_generation = notification_generation + 1
    local generation = notification_generation
    local ok, error_message = pcall(function()
        local player_ui = FindFirstOf("WBP_PlayerUI_C")
        local toast = nil
        if is_valid(player_ui) then
            toast = player_ui.WBP_Ingame_Message
        end
        if not is_valid(toast) then
            toast = FindFirstOf("WBP_Ingame_Message_C")
        end
        if not is_valid(toast) or not is_valid(toast.BP_PalRichTextBlock_C_89) then
            return
        end

        toast.BP_PalRichTextBlock_C_89:SetText(FText(message))
        toast:SetVisibility(0)
        if color == "green" then
            toast:AnmEvent_Green()
        elseif color == "red" then
            toast:AnmEvent_Red()
        else
            toast:AnmEvent_Blue()
        end
        toast:AnmEvent_In()

        ExecuteWithDelay(1800, function()
            ExecuteInGameThread(function()
                if generation ~= notification_generation then
                    return
                end
                pcall(function()
                    if is_valid(toast) then
                        toast:AnmEvent_Out()
                    end
                end)
            end)
        end)
    end)
    if not ok then
        log("Could not show preview status notification: " .. tostring(error_message))
    end
end

local function begin_editing()
    -- Keybinds are global in UE4SS. Resolve only the local player's live build
    -- context here so MMB is a cheap no-op during normal gameplay.
    local active_component, active_checker, active_preview = find_active_build_context(false)
    if active_component == nil then
        return false
    end
    local previous_state = state
    local transition_id = begin_freeze_transition(State.FREEZING)

    builder_component = active_component
    unfrozen_ui_builder_component = nil
    unfrozen_ui_preview_visible = nil
    transform_actor = active_checker
    preview_actor = active_preview
    log("Using InstallChecker target: " .. full_name(preview_actor))

    local root_ok, root_component = pcall(function()
        return preview_actor.RootComponent
    end)
    if root_ok and is_valid(root_component) then
        preview_root_component = root_component
        local mobility_ok, mobility = pcall(function()
            return root_component.Mobility
        end)
        if mobility_ok then
            preview_root_previous_mobility = mobility
        end
        pcall(function()
            root_component:SetMobility(2)
        end)
        log("Preview hierarchy preserved; root component set movable.")
    end

    if not read_preview_transform() then
        if is_valid(preview_root_component)
            and preview_root_previous_mobility ~= nil
        then
            pcall(function()
                preview_root_component:SetMobility(
                    preview_root_previous_mobility
                )
            end)
        end
        builder_component = nil
        transform_actor = nil
        preview_actor = nil
        preview_root_component = nil
        preview_root_previous_mobility = nil
        complete_freeze_transition(transition_id, previous_state)
        return false
    end
    local preview_transform_ok, preview_location, preview_rotation = pcall(function()
        return preview_actor:K2_GetActorLocation(), preview_actor:K2_GetActorRotation()
    end)
    if preview_transform_ok and preview_location ~= nil and preview_rotation ~= nil then
        local world_offset_x = preview_location.X - desired_location.X
        local world_offset_y = preview_location.Y - desired_location.Y
        local checker_yaw = math.rad(desired_rotation.Yaw)
        preview_relative_location = {
            X = (math.cos(checker_yaw) * world_offset_x)
                + (math.sin(checker_yaw) * world_offset_y),
            Y = (-math.sin(checker_yaw) * world_offset_x)
                + (math.cos(checker_yaw) * world_offset_y),
            Z = preview_location.Z - desired_location.Z,
        }
        preview_relative_rotation = {
            Pitch = preview_rotation.Pitch - desired_rotation.Pitch,
            Yaw = preview_rotation.Yaw - desired_rotation.Yaw,
            Roll = preview_rotation.Roll - desired_rotation.Roll,
        }
        log(string.format(
            "Preserved snap offset: location=(%.1f, %.1f, %.1f), yaw=%.1f.",
            preview_relative_location.X,
            preview_relative_location.Y,
            preview_relative_location.Z,
            preview_relative_rotation.Yaw
        ))
    else
        preview_relative_location = nil
        preview_relative_rotation = nil
    end
    locked_origin_location = {
        X = desired_location.X,
        Y = desired_location.Y,
        Z = desired_location.Z,
    }
    locked_origin_rotation = {
        Pitch = desired_rotation.Pitch,
        Yaw = desired_rotation.Yaw,
        Roll = desired_rotation.Roll,
    }
    local bounds_ok, bounds_origin = pcall(function()
        local origin = {}
        local extent = {}
        preview_actor:GetActorBounds(false, origin, extent, false)
        return origin
    end)
    if bounds_ok and bounds_origin ~= nil
        and bounds_origin.X ~= nil and bounds_origin.Y ~= nil and bounds_origin.Z ~= nil then
        rotation_pivot = {
            X = bounds_origin.X,
            Y = bounds_origin.Y,
            Z = bounds_origin.Z,
        }
        local offset_x = rotation_pivot.X - desired_location.X
        local offset_y = rotation_pivot.Y - desired_location.Y
        local yaw = math.rad(desired_rotation.Yaw)
        rotation_pivot_local_offset = {
            X = (math.cos(yaw) * offset_x) + (math.sin(yaw) * offset_y),
            Y = (-math.sin(yaw) * offset_x) + (math.cos(yaw) * offset_y),
            Z = rotation_pivot.Z - desired_location.Z,
        }
        log(string.format(
            "Rotation pivot captured at bounds center (%.1f, %.1f, %.1f).",
            rotation_pivot.X,
            rotation_pivot.Y,
            rotation_pivot.Z
        ))
    else
        rotation_pivot = nil
        rotation_pivot_local_offset = nil
        log("Could not capture preview bounds; rotation will use Palworld's install pivot.")
    end
    if rotation_pivot ~= nil then
        locked_origin_pivot = {
            X = rotation_pivot.X,
            Y = rotation_pivot.Y,
            Z = rotation_pivot.Z,
        }
    else
        locked_origin_pivot = nil
    end
    last_preview_overlap_state = nil
    local tick_query_ok, tick_enabled = pcall(function()
        return preview_actor:IsActorTickEnabled()
    end)
    preview_tick_was_enabled = tick_query_ok and tick_enabled or true
    if set_preview_tick_enabled(false) then
        log("Preview actor tick suspended for frozen editing.")
    end

    if builder_component ~= nil then
        local builder_tick_query_ok, builder_tick_enabled = pcall(function()
            return builder_component:IsComponentTickEnabled()
        end)
        builder_tick_was_enabled = builder_tick_query_ok and builder_tick_enabled or true
        if set_builder_tick_enabled(false) then
            log("Player builder component tick suspended for frozen editing.")
        end
    else
        log("Could not find the local player's BuilderComponent.")
    end

    state = State.EDITING
    lifecycle_ui_refresh_ticks = 0
    building_mode_exit_checks = 0
    locked_preview_name = full_name(preview_actor)
    update_construction_hotkey_guide(true)
    start_transform_loop()
    start_lifecycle_monitor()
    log(string.format(
        "Preview frozen. Move step %.1f cm; rotation step %.1f degrees.",
        current_move_step,
        Config.rotation.normal
    ))
    refresh_locked_validity()
    settle_freeze_transition(transition_id, State.EDITING)
    return true
end

release_preview = function(reason)
    if state ~= State.EDITING then
        return false
    end
    local transition_id = begin_freeze_transition(State.UNFREEZING)
    lifecycle_ui_refresh_ticks = 0
    building_mode_exit_checks = 0
    local is_manual_unfreeze = reason == "manual"
    local no_active_preview = reason == "preview object was destroyed"
        or reason == "Palworld cleared the build preview"
    local left_construction = reason == "Palworld exited building mode"
        or reason == "Palworld closed the construction UI"
        or reason == "builder component became invalid"
    unfrozen_ui_builder_component = builder_component
    unfrozen_ui_preview_visible = not (left_construction or no_active_preview)
    update_construction_hotkey_guide(
        false,
        is_manual_unfreeze,
        left_construction or no_active_preview
    )
    set_preview_tick_enabled(preview_tick_was_enabled ~= false)
    preview_tick_was_enabled = nil
    set_builder_tick_enabled(builder_tick_was_enabled ~= false)
    builder_tick_was_enabled = nil
    builder_component = nil
    transform_actor = nil
    if is_valid(preview_root_component) and preview_root_previous_mobility ~= nil then
        pcall(function()
            preview_root_component:SetMobility(preview_root_previous_mobility)
        end)
    end
    preview_root_component = nil
    preview_root_previous_mobility = nil
    locked_preview_name = nil
    locked_origin_location = nil
    locked_origin_rotation = nil
    locked_origin_pivot = nil
    last_preview_overlap_state = nil
    rotation_pivot = nil
    rotation_pivot_local_offset = nil
    preview_relative_location = nil
    preview_relative_rotation = nil
    desired_location = nil
    desired_rotation = nil
    log("Preview released to Palworld placement control.")
    settle_freeze_transition(transition_id, State.READY)
    return true
end

local function move_preview(forward_amount, right_amount, up_amount, distance_override)
    if freeze_transition_input_locked
        or state ~= State.EDITING
        or not is_valid(builder_component)
        or not is_valid(transform_actor)
        or not is_valid(preview_actor)
        or desired_location == nil
        or desired_rotation == nil
    then
        verbose("Move input ignored while the frozen preview is unavailable or settling.")
        return
    end

    local distance = distance_override or current_move_step
    -- The piece yaw defines the movement grid. The camera decides which of the
    -- four piece-local directions is currently "forward", keeping Numpad 8
    -- moving away from the player without allowing off-axis movement.
    local piece_yaw = desired_rotation.Yaw
    if preview_relative_rotation ~= nil then
        piece_yaw = piece_yaw + preview_relative_rotation.Yaw
    end
    local yaw_radians = math.rad(piece_yaw)
    local piece_forward_x = math.cos(yaw_radians)
    local piece_forward_y = math.sin(yaw_radians)
    local piece_right_x = -piece_forward_y
    local piece_right_y = piece_forward_x

    local camera_forward_x = piece_forward_x
    local camera_forward_y = piece_forward_y
    local camera_ok, camera_forward = pcall(function()
        if builder_component ~= nil and builder_component:IsValid() then
            local owner_camera = builder_component.OwnerCamera
            if owner_camera ~= nil and owner_camera:IsValid() then
                return owner_camera:GetForwardVector()
            end
        end
        local controller = UEHelpers:GetPlayerController()
        if controller ~= nil and controller:IsValid() then
            local camera = controller.PlayerCameraManager
            if camera ~= nil and camera:IsValid() then
                return camera:GetActorForwardVector()
            end
        end
        return nil
    end)
    if camera_ok and camera_forward ~= nil then
        local camera_length = math.sqrt(
            (camera_forward.X * camera_forward.X)
            + (camera_forward.Y * camera_forward.Y)
        )
        if camera_length > 0.001 then
            camera_forward_x = camera_forward.X / camera_length
            camera_forward_y = camera_forward.Y / camera_length
        end
    end

    local forward_dot = (camera_forward_x * piece_forward_x)
        + (camera_forward_y * piece_forward_y)
    local right_dot = (camera_forward_x * piece_right_x)
        + (camera_forward_y * piece_right_y)
    local forward_x
    local forward_y
    if math.abs(forward_dot) >= math.abs(right_dot) then
        local direction = forward_dot >= 0.0 and 1.0 or -1.0
        forward_x = piece_forward_x * direction
        forward_y = piece_forward_y * direction
    else
        local direction = right_dot >= 0.0 and 1.0 or -1.0
        forward_x = piece_right_x * direction
        forward_y = piece_right_y * direction
    end
    local right_x = -forward_y
    local right_y = forward_x
    verbose(string.format(
        "Camera-aligned movement on piece yaw %.1f: forward=(%.3f, %.3f)",
        piece_yaw,
        forward_x,
        forward_y
    ))

    local previous_x = desired_location.X
    local previous_y = desired_location.Y
    local previous_z = desired_location.Z
    desired_location.X = desired_location.X
        + (forward_x * forward_amount * distance)
        + (right_x * right_amount * distance)
    desired_location.Y = desired_location.Y
        + (forward_y * forward_amount * distance)
        + (right_y * right_amount * distance)
    desired_location.Z = desired_location.Z + (up_amount * distance)
    if locked_origin_location ~= nil then
        local minimum_z = locked_origin_location.Z - Config.movement.maximum_below_initial_cm
        local maximum_z = locked_origin_location.Z + Config.movement.maximum_above_initial_cm
        local requested_z = desired_location.Z
        desired_location.Z = math.max(minimum_z, math.min(maximum_z, desired_location.Z))
        if desired_location.Z ~= requested_z then
            log(string.format(
                "Vertical movement clamped at %.1f cm relative to the initial position.",
                desired_location.Z - locked_origin_location.Z
            ))
        end
    end
    if rotation_pivot ~= nil then
        rotation_pivot.X = rotation_pivot.X + (desired_location.X - previous_x)
        rotation_pivot.Y = rotation_pivot.Y + (desired_location.Y - previous_y)
        rotation_pivot.Z = rotation_pivot.Z + (desired_location.Z - previous_z)
    end

    if apply_preview_transform() then
        refresh_locked_validity()
    end
    verbose(string.format(
        "Move input applied: location=(%.1f, %.1f, %.1f)",
        desired_location.X,
        desired_location.Y,
        desired_location.Z
    ))
end

local function rotate_preview(yaw_amount, degrees_override)
    if freeze_transition_input_locked
        or state ~= State.EDITING
        or not is_valid(builder_component)
        or not is_valid(transform_actor)
        or not is_valid(preview_actor)
        or desired_location == nil
        or desired_rotation == nil
    then
        verbose("Rotate input ignored while the frozen preview is unavailable or settling.")
        return
    end
    desired_rotation.Yaw = desired_rotation.Yaw
        + (yaw_amount * (degrees_override or Config.rotation.normal))
    if rotation_pivot ~= nil and rotation_pivot_local_offset ~= nil then
        local yaw = math.rad(desired_rotation.Yaw)
        local rotated_offset_x = (math.cos(yaw) * rotation_pivot_local_offset.X)
            - (math.sin(yaw) * rotation_pivot_local_offset.Y)
        local rotated_offset_y = (math.sin(yaw) * rotation_pivot_local_offset.X)
            + (math.cos(yaw) * rotation_pivot_local_offset.Y)
        desired_location.X = rotation_pivot.X - rotated_offset_x
        desired_location.Y = rotation_pivot.Y - rotated_offset_y
        desired_location.Z = rotation_pivot.Z - rotation_pivot_local_offset.Z
    end

    if apply_preview_transform() then
        refresh_locked_validity()
    end
end

local function reset_preview_transform()
    if freeze_transition_input_locked
        or state ~= State.EDITING
        or not is_valid(builder_component)
        or not is_valid(transform_actor)
        or not is_valid(preview_actor)
        or locked_origin_location == nil
        or locked_origin_rotation == nil
    then
        verbose("Reset input ignored while the frozen preview is unavailable or settling.")
        return
    end

    desired_location = {
        X = locked_origin_location.X,
        Y = locked_origin_location.Y,
        Z = locked_origin_location.Z,
    }
    desired_rotation = {
        Pitch = locked_origin_rotation.Pitch,
        Yaw = locked_origin_rotation.Yaw,
        Roll = locked_origin_rotation.Roll,
    }
    if locked_origin_pivot ~= nil then
        rotation_pivot = {
            X = locked_origin_pivot.X,
            Y = locked_origin_pivot.Y,
            Z = locked_origin_pivot.Z,
        }
    end

    if apply_preview_transform() then
        refresh_locked_validity()
        log("Preview reset to its original frozen transform.")
    end
end

local function change_move_step(multiplier)
    if freeze_transition_input_locked
        or state ~= State.EDITING
        or not is_valid(builder_component)
        or not is_valid(transform_actor)
        or not is_valid(preview_actor)
        or desired_location == nil
    then
        verbose("Move-step input ignored while the frozen preview is unavailable or settling.")
        return
    end
    current_move_step = math.max(
        Config.movement.minimum,
        math.min(Config.movement.maximum, current_move_step * multiplier)
    )
    log(string.format("Move step: %.1f cm", current_move_step))
    refresh_perfect_placement_ui()
end

local function actor_from_hit_result(hit_result)
    if UnrealVersion:IsBelow(5, 0) then
        return hit_result.Actor:Get()
    elseif UnrealVersion:IsBelow(5, 4) then
        return hit_result.HitObjectHandle.Actor:Get()
    end
    return hit_result.HitObjectHandle.ReferenceObject:Get()
end

local function copy_looked_at_build_piece()
    if freeze_transition_input_locked
        or state == State.FREEZING
        or state == State.UNFREEZING
    then
        verbose("Eyedropper ignored while placement state settles.")
        return
    end
    if state == State.EDITING then
        log("Eyedropper ignored while the preview is frozen.")
        return
    end
    ExecuteInGameThread(function()
        local ok, error_message = pcall(function()
            local component, active_checker, active_preview = find_active_build_context(false)
            if component == nil then
                log("Eyedropper ignored: no placement preview is active.")
                return
            end
            local player = component:GetOwner()
            local camera = component.OwnerCamera
            if not is_valid(player) or not is_valid(camera) then
                error("player build camera is unavailable")
            end

            local start_location = camera:K2_GetComponentLocation()
            local forward = camera:GetForwardVector()
            local end_location = {
                X = start_location.X + (forward.X * 50000.0),
                Y = start_location.Y + (forward.Y * 50000.0),
                Z = start_location.Z + (forward.Z * 50000.0),
            }
            local hit_result = {}
            local transparent = { R = 0, G = 0, B = 0, A = 0 }
            local was_hit = UEHelpers.GetKismetSystemLibrary():LineTraceSingle(
                player,
                start_location,
                end_location,
                0,
                false,
                { player },
                0,
                hit_result,
                true,
                transparent,
                transparent,
                0.0
            )
            if not was_hit then
                error("no object was found under the cursor")
            end

            local target = actor_from_hit_result(hit_result)
            if not is_valid(target) then
                error("the traced actor is invalid")
            end
            local id_ok, build_object_id = pcall(function()
                return target.BuildObjectId
            end)
            if not id_ok or build_object_id == nil or tostring(build_object_id) == "None" then
                error("target is not a copyable Pal build object: " .. full_name(target))
            end

            local active_id_ok, active_build_object_id = pcall(function()
                return active_preview.BuildObjectId
            end)
            local names_ok, target_id_name, active_id_name = pcall(function()
                return build_object_id:ToString(), active_build_object_id:ToString()
            end)
            if active_id_ok and names_ok and target_id_name == active_id_name then
                log("Eyedropper ignored: looked-at piece already matches the active preview.")
                return
            end

            local building_model = FindFirstOf("PalUIBuildingModel")
            if is_valid(building_model) then
                building_model:FinishBuilding()
                -- FinishBuilding creates the menu-side selection model. Handoff
                -- on the next async tick to minimize or eliminate visible menu flash.
                ExecuteWithDelay(1, function()
                    ExecuteInGameThread(function()
                        local delayed_ok, delayed_error = pcall(function()
                            if not is_valid(target) then
                                error("copied source actor became invalid")
                            end
                            local delayed_build_object_id = target.BuildObjectId
                            local ui_model = FindFirstOf("PalUIBuildModel")
                            if not is_valid(ui_model) then
                                ui_model = FindFirstOf("BP_PalUIBuildModel_C")
                            end
                            if not is_valid(ui_model) then
                                error("build-menu model did not become available")
                            end
                            ui_model:StartBuildObject(delayed_build_object_id)
                            log(string.format(
                                "Copied build preview started from %s.",
                                full_name(target)
                            ))
                        end)
                        if not delayed_ok then
                            log("Could not start copied build preview: " .. tostring(delayed_error))
                        end
                    end)
                end)
            else
                local ui_model = FindFirstOf("PalUIBuildModel")
                if not is_valid(ui_model) then
                    ui_model = FindFirstOf("BP_PalUIBuildModel_C")
                end
                if not is_valid(ui_model) then
                    error("no active Palworld building model is available")
                end
                ui_model:StartBuildObject(build_object_id)
            end
            preview_actor = nil
            state = State.SEARCHING
            log("Queued copied build piece from " .. full_name(target) .. ".")
        end)
        if not ok then
            log("Could not copy looked-at build piece: " .. tostring(error_message))
        end
    end)
end

local function register_chord(key, modifiers, callback)
    local ok, error_message = pcall(function()
        local queued_callback = function()
            local queued_generation = freeze_transition_generation
            local queued_during_transition =
                freeze_transition_input_locked
                or state == State.FREEZING
                or state == State.UNFREEZING
            execute_in_game_thread_retained(function()
                if queued_during_transition
                    or queued_generation ~= freeze_transition_generation
                then
                    verbose("Discarded stale queued input after a placement transition.")
                    return
                end
                callback()
            end, "Input game-thread callback")
        end
        if modifiers == nil or #modifiers == 0 then
            RegisterKeyBind(key, queued_callback)
        else
            RegisterKeyBind(key, modifiers, queued_callback)
        end
    end)
    if not ok then
        log(string.format(
            "Could not register key 0x%X: %s",
            key,
            tostring(error_message)
        ))
    end
end

local MODIFIER_VALUES = {
    SHIFT = ModifierKey.SHIFT,
    CONTROL = ModifierKey.CONTROL,
    ALT = ModifierKey.ALT,
}

local function same_modifier_names(left, right)
    if #left ~= #right then
        return false
    end
    for index, value in ipairs(left) do
        if value ~= right[index] then
            return false
        end
    end
    return true
end

local action_callbacks = {}
local action_numlock_alternates = {}
local registered_action_chords = {}

local function binding_uses_virtual_key(binding, virtual_key)
    return binding.key_info.virtual_key == virtual_key
        or binding.key_info.alternate_virtual_key == virtual_key
end

local function register_current_action_binding(action)
    local binding = resolved_bindings[action]
    if binding == nil or binding.disabled then
        log("Skipping disabled binding: " .. action)
        return nil
    end

    local modifiers = {}
    for _, modifier_name in ipairs(binding.modifiers) do
        modifiers[#modifiers + 1] = MODIFIER_VALUES[modifier_name]
    end

    local virtual_keys = { binding.key_info.virtual_key }
    if action_numlock_alternates[action]
        and binding.key_info.alternate_virtual_key ~= nil
    then
        virtual_keys[#virtual_keys + 1] = binding.key_info.alternate_virtual_key
    end

    registered_action_chords[action] = registered_action_chords[action] or {}
    for _, virtual_key in ipairs(virtual_keys) do
        local registration_signature = tostring(virtual_key)
            .. ":"
            .. table.concat(binding.modifiers, "+")
        if not registered_action_chords[action][registration_signature] then
            local captured_virtual_key = virtual_key
            local captured_modifiers = {}
            for index, value in ipairs(binding.modifiers) do
                captured_modifiers[index] = value
            end
            register_chord(captured_virtual_key, modifiers, function()
                local current = resolved_bindings[action]
                if current ~= nil
                    and not current.disabled
                    and binding_uses_virtual_key(current, captured_virtual_key)
                    and same_modifier_names(
                        current.modifiers,
                        captured_modifiers
                    )
                then
                    action_callbacks[action]()
                end
            end)
            registered_action_chords[action][registration_signature] = true
        end
    end
    return binding
end

local function register_action(action, callback, include_numlock_alternate)
    action_callbacks[action] = callback
    action_numlock_alternates[action] = include_numlock_alternate == true
    return register_current_action_binding(action)
end

-- Numeric keypad controls avoid Palworld's build UI and snap bindings.
register_action("move_left", function() move_preview(0, -1, 0) end)
register_action("move_right", function() move_preview(0, 1, 0) end)
register_action("move_forward", function() move_preview(1, 0, 0) end)
register_action("move_back", function() move_preview(-1, 0, 0) end)
register_action("move_up", function() move_preview(0, 0, 1) end, true)
register_action("move_down", function() move_preview(0, 0, -1) end, true)
-- On Windows, these same physical keypad keys report navigation-key virtual
-- codes while NumLock is off. The alternate metadata keeps that behavior when
-- the configured vertical keys remain on Numpad 1/3.
register_action("reset", reset_preview_transform)
register_action("rotate_left", function() rotate_preview(-1) end)
register_action("rotate_right", function() rotate_preview(1) end)

register_action("step_down", function()
    change_move_step(1.0 / Config.movement.step_scale)
end)
register_action("step_up", function()
    change_move_step(Config.movement.step_scale)
end)

local function configured_chord_is_claimed(key, modifiers, except_action)
    for action, binding in pairs(resolved_bindings) do
        if action ~= except_action
            and binding ~= nil
            and not binding.disabled
            and binding.key == key
            and same_modifier_names(binding.modifiers, modifiers)
        then
            return true
        end
    end
    return false
end

local function toggle_preview_freeze()
    if freeze_transition_input_locked
        or state == State.FREEZING
        or state == State.UNFREEZING
    then
        verbose("Freeze toggle ignored while placement state settles.")
        return
    end
    if state == State.EDITING then
        log("Manual unfreeze requested.")
        release_preview("manual")
    else
        begin_editing()
    end
end
register_action("toggle_freeze", toggle_preview_freeze)
-- Palworld uses Ctrl and Alt for contextual build-piece controls while the
-- preview is still active. UE4SS matches modifier chords explicitly, so plain
-- MMB does not fire while either modifier is held unless each combination is
-- registered separately.
local function register_supplemental_freeze_chord(
    modifier_names,
    modifier_values
)
    register_chord(0x04, modifier_values, function()
        local current = resolved_bindings.toggle_freeze
        if current ~= nil
            and not current.disabled
            and current.key == "MIDDLE_MOUSE"
            and #current.modifiers == 0
            and not configured_chord_is_claimed(
                current.key,
                modifier_names,
                "toggle_freeze"
            )
        then
            toggle_preview_freeze()
        end
    end)
end
register_supplemental_freeze_chord(
    { "CONTROL" },
    { ModifierKey.CONTROL }
)
register_supplemental_freeze_chord(
    { "ALT" },
    { ModifierKey.ALT }
)
register_supplemental_freeze_chord(
    { "CONTROL", "ALT" },
    { ModifierKey.CONTROL, ModifierKey.ALT }
)
register_action("copy_piece", copy_looked_at_build_piece)

local function refresh_keycaps_for_ui_host(host)
    keycap_ui_host = nil
    if is_valid(host) then
        apply_configured_keycaps(host)
    end
    log("Refreshed placement keycaps for the new UI host.")
end

local UI_HOST_CLASS_PATH =
    "/Game/Mods/PerfectPlacement/WBP_PerfectPlacement_KeyGuide"
    .. ".WBP_PerfectPlacement_KeyGuide_C"

local ui_notify_ok, ui_notify_error = pcall(
    NotifyOnNewObject,
    UI_HOST_CLASS_PATH,
    function(host)
        ExecuteWithDelay(250, function()
            ExecuteInGameThread(function()
                if not is_valid(host) then
                    return
                end

                perfect_placement_ui_host = host
                keycap_ui_host = nil
                ui_host_missing_was_logged = false
                cached_builder_component = nil
                unfrozen_ui_builder_component = nil
                unfrozen_ui_preview_visible = nil
                builder_fallback_scan_cooldown = 0
                lifecycle_ui_refresh_ticks = 0

                refresh_keycaps_for_ui_host(host)

                if os.clock() - lifecycle_monitor_last_tick > 1.0 then
                    lifecycle_monitor_started = false
                    start_lifecycle_monitor()
                    log("Placement UI lifecycle monitor restarted for the new world.")
                end
            end)
        end)
    end
)
if not ui_notify_ok then
    log("Could not register companion UI lifecycle notification: "
        .. tostring(ui_notify_error))
end

-- Start the shared lifecycle/UI monitor immediately so the unfrozen guide can
-- appear before the player uses Perfect Placement for the first time.
start_lifecycle_monitor()

log("Loaded Perfect Placement 0.1.6-release")
log("Companion key-guide UI bridge revision 22 loaded.")
log("Open build mode, show a preview, then middle-click to freeze it.")
