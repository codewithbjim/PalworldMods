local Config = require("config")
local Keybindings = require("keybindings")
local DarnMenu = require("darnmenu")
local Runtime = require("runtime")
local GamepadFeature = require("gamepad_feature")
local UEHelpers = require("UEHelpers")

local MOD = "PerfectPlacement"

local State = {
    SEARCHING = "searching",
    READY = "ready",
    SWITCHING = "switching",
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
local transform_loop_callback = nil
local preview_tick_was_enabled = nil
local builder_component = nil
local cached_builder_component = nil
local cached_pal_utility = nil
local cached_construction_widget = nil
local builder_tick_was_enabled = nil
local release_preview
local update_construction_hotkey_guide
local locked_origin_location = nil
local locked_origin_rotation = nil
local last_preview_overlap_state = nil
local validity_refresh_pending = false
local validity_refresh_generation = 0
local validity_refresh_trigger = nil
local preview_relative_location = nil
local preview_relative_rotation = nil
local preserve_preview_origin_during_rotation = false
local freeze_transition_generation = 0
local freeze_transition_input_locked = false
local keyguide_hook_registered = false
local keyguide_hook_callback = nil
local KEYGUIDE_SETUP_PATH = "/Game/Pal/Blueprint/UI/UserInterface/InGame/Construction/WBP_IngameConstruction.WBP_IngameConstruction_C:SetupKeyGuide"
local CONSTRUCTION_WIDGET_CLASS_NAME = "WBP_IngameConstruction_C"
local perfect_placement_ui_host = nil
local perfect_placement_ui_mode = nil
local ui_host_notify_callback = nil
local construction_ui_notify_callback = nil
local ui_host_setup_pending = false
local ui_host_missing_was_logged = false
local ui_host_lookup_blocked = false
local ui_host_fault_retry_allowed = true
local preferred_ui_host_full_name = nil
local keycap_ui_host = nil
local resolved_bindings = nil
local keycap_texture_cache = {}
local gamepad_feature = nil
local dispatch_action
local registered_keybind_callbacks = {}
local construction_ui_hooks = {}
local construction_ui_generation = 0
local construction_setup_retry_pending = false

local FREEZE_TRANSITION_SETTLE_MS = 500
local VALIDITY_REFRESH_INTERVAL_MS = 50
local FREEZE_TO_PIECE_RETRY_MS = 50
local FREEZE_TO_PIECE_MAX_ATTEMPTS = 60
-- Automatic structural snapping (for example, a wall or roof against a
-- foundation) does not always set BuilderComponent snap mode or retain either
-- InstallStrategy snap cache. In that path the checker remains at the cursor
-- hit while Palworld offsets the visible preview to the structural socket.
-- Ordinary placement keeps both actor origins nearly coincident; allow a
-- generous tolerance for asset/root noise before treating the offset as snap.
local AUTOMATIC_SNAP_OFFSET_THRESHOLD_CM = 25.0

local function log(message)
    print(string.format("[%s] %s\n", MOD, message))
end

DarnMenu.apply_settings(Config, log)
current_move_step = Config.movement.normal
local runtime = Runtime.new(log)

local ui_lifecycle_metrics_enabled = Config.diagnostics ~= nil
    and Config.diagnostics.ui_lifecycle_counters == true
local ui_lifecycle_metrics = {}

local function count_ui_lifecycle_metric(name)
    if not ui_lifecycle_metrics_enabled then
        return
    end
    ui_lifecycle_metrics[name] = (ui_lifecycle_metrics[name] or 0) + 1
end

if ui_lifecycle_metrics_enabled then
    local interval_ms = math.max(
        1000,
        math.floor(tonumber(Config.diagnostics.ui_lifecycle_log_interval_ms) or 5000)
    )
    runtime.loop(interval_ms, function()
        local names = {}
        for name, count in pairs(ui_lifecycle_metrics) do
            if count > 0 then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        if #names > 0 then
            local values = {}
            for _, name in ipairs(names) do
                values[#values + 1] = name .. "=" .. tostring(ui_lifecycle_metrics[name])
                ui_lifecycle_metrics[name] = 0
            end
            log("UI lifecycle counters: " .. table.concat(values, ", "))
        end
        return false
    end, "UI lifecycle diagnostics")
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
    local queued = runtime.delay(
        FREEZE_TRANSITION_SETTLE_MS,
        function()
            complete_freeze_transition(transition_id, stable_state)
        end,
        "Freeze transition settle callback",
        function()
            complete_freeze_transition(transition_id, stable_state)
        end
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

local function class_name_from_full_name(name)
    return string.match(tostring(name), "^([^%s]+)") or tostring(name)
end

local function full_name_is_available(name)
    return type(name) == "string"
        and name ~= "<invalid>"
        and name ~= "<name unavailable>"
end

local function full_name_is_live_exact_class(name, expected_class_name)
    return full_name_is_available(name)
        and class_name_from_full_name(name) == expected_class_name
        and string.find(name, "/Engine/Transient.", 1, true) ~= nil
        and string.find(name, "Default__", 1, true) == nil
end

local function is_live_object_of_exact_class(object, expected_class_name)
    return full_name_is_live_exact_class(
        full_name(object),
        expected_class_name
    )
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
    freeze_to_piece = { "CopyFreezeChord" },
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

local function safe_find_all_of(class_name)
    local ok, objects = pcall(function()
        return FindAllOf(class_name)
    end)
    if not ok or objects == nil then
        return {}
    end
    return objects
end

local function live_companion_ui_host_name(host)
    local ui_config = Config.ui or {}
    local expected_class_name =
        ui_config.host_class_name or "WBP_PerfectPlacement_KeyGuide_C"
    local name = full_name(host)
    if full_name_is_live_exact_class(name, expected_class_name)
        and string.find(name, "WidgetTree", 1, true) == nil
    then
        return name
    end
    return nil
end

local function is_live_companion_ui_host(host)
    return live_companion_ui_host_name(host) ~= nil
end

local function find_perfect_placement_ui_host()
    if ui_host_setup_pending or ui_host_lookup_blocked then
        return nil
    end

    local preferred_name = preferred_ui_host_full_name
    local require_preferred = full_name_is_available(preferred_name)
    local cached_host_name =
        live_companion_ui_host_name(perfect_placement_ui_host)
    if cached_host_name ~= nil
        and (not require_preferred or cached_host_name == preferred_name)
    then
        return perfect_placement_ui_host
    end

    perfect_placement_ui_host = nil
    perfect_placement_ui_mode = nil
    local ui_config = Config.ui or {}
    local class_name = ui_config.host_class_name or "WBP_PerfectPlacement_KeyGuide_C"
    local host_name = nil

    local function accept_candidate(candidate)
        local candidate_name = live_companion_ui_host_name(candidate)
        if candidate_name == nil
            or (require_preferred and candidate_name ~= preferred_name)
        then
            return false
        end
        host_name = candidate_name
        return true
    end

    count_ui_lifecycle_metric("host_search")
    local ok, host = pcall(function()
        return FindFirstOf(class_name)
    end)
    if not ok or not accept_candidate(host) then
        host = nil
        for _, candidate in ipairs(safe_find_all_of(class_name)) do
            if accept_candidate(candidate) then
                host = candidate
                break
            end
        end
    end
    if host ~= nil and host_name ~= nil then
        perfect_placement_ui_host = host
        preferred_ui_host_full_name = host_name
        ui_host_missing_was_logged = false
        ui_host_lookup_blocked = false
        count_ui_lifecycle_metric("host_acquired")
        apply_configured_keycaps(host)
        if gamepad_feature ~= nil then
            gamepad_feature:attach_host(host)
        end
        log("Companion UI host found: " .. full_name(host))
        return host
    end

    if not ui_host_missing_was_logged then
        log("Companion UI host is not loaded yet (expected " .. class_name .. ").")
        ui_host_missing_was_logged = true
    end
    ui_host_lookup_blocked = true
    count_ui_lifecycle_metric("host_missing")
    return nil
end

local function call_ui_host_function(host, function_name)
    local callback = host[function_name]
    if callback == nil then
        error("UI host function is missing: " .. tostring(function_name))
    end
    callback(host)
end

local function quarantine_companion_ui_host(metric_name)
    if gamepad_feature ~= nil then
        gamepad_feature:detach_host()
    end
    perfect_placement_ui_host = nil
    perfect_placement_ui_mode = nil
    ui_host_lookup_blocked = true
    count_ui_lifecycle_metric(metric_name)
    if ui_host_fault_retry_allowed
        and ui_host_notify_callback ~= nil
        and not ui_host_setup_pending
    then
        ui_host_fault_retry_allowed = false
        ui_host_notify_callback()
    end
end

local function update_perfect_placement_ui(is_locked, show_transition_toast, hide_all)
    local requested_mode = hide_all and "hidden"
        or (is_locked and "frozen" or "unfrozen")
    -- SetupKeyGuide can run repeatedly while Palworld updates a live preview.
    -- Re-entering the same Blueprint state also rebuilds the input guide and
    -- toggles its gamepad input actors, so keep ordinary refreshes edge-driven.
    if requested_mode == perfect_placement_ui_mode
        and not show_transition_toast
        and is_live_companion_ui_host(perfect_placement_ui_host)
    then
        return true
    end

    local host = find_perfect_placement_ui_host()
    if not is_live_companion_ui_host(host) then
        return false
    end

    local ui_config = Config.ui or {}
    local previous_mode = perfect_placement_ui_mode
    perfect_placement_ui_mode = requested_mode
    count_ui_lifecycle_metric("mode_" .. tostring(previous_mode) .. "_to_" .. requested_mode)
    local ok, error_message = pcall(function()
        local move_step_property = ui_config.move_step_property or "MoveStepCm"
        host[move_step_property] = current_move_step

        if hide_all then
            count_ui_lifecycle_metric("hide_guide")
            call_ui_host_function(
                host,
                ui_config.hide_function or "HideGuide"
            )
            call_ui_host_function(
                host,
                ui_config.hide_toast_function or "HideToast"
            )
        elseif is_locked then
            count_ui_lifecycle_metric("show_frozen_guide")
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
            count_ui_lifecycle_metric("show_unfrozen_guide")
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

        -- Keep the companion state machine and physical gamepad bridge active
        -- while the visible guide is rendered in Palworld's native widget.
        if not hide_all and ui_config.use_native_construction_guide then
            call_ui_host_function(
                host,
                ui_config.hide_function or "HideGuide"
            )
        end

        if gamepad_feature ~= nil then
            gamepad_feature:set_mode(requested_mode)
        end

    end)
    if not ok then
        log("Companion UI update failed: " .. tostring(error_message))
        quarantine_companion_ui_host("host_update_failure")
        return false
    end
    ui_host_fault_retry_allowed = true
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
        quarantine_companion_ui_host("host_refresh_failure")
    end
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

local function angular_distance(left, right)
    return math.abs(((left - right + 180.0) % 360.0) - 180.0)
end

local function set_actor_transform_verified(actor, location, rotation, label)
    if not is_valid(actor) then
        return false
    end

    local hit_result = {}
    local call_ok, call_error = pcall(function()
        actor:K2_SetActorLocationAndRotation(
            location,
            rotation,
            false,
            hit_result,
            true
        )
    end)

    -- This UE4SS build can throw while marshalling the unused FHitResult after
    -- ProcessEvent has already moved the actor. Verify the actual transform
    -- instead of treating that post-call conversion error as a failed move.
    local verify_ok, actual_location, actual_rotation = pcall(function()
        return actor:K2_GetActorLocation(), actor:K2_GetActorRotation()
    end)
    local reached_target = verify_ok
        and actual_location ~= nil
        and actual_rotation ~= nil
        and math.abs(actual_location.X - location.X) <= 0.5
        and math.abs(actual_location.Y - location.Y) <= 0.5
        and math.abs(actual_location.Z - location.Z) <= 0.5
        and angular_distance(actual_rotation.Pitch, rotation.Pitch) <= 0.1
        and angular_distance(actual_rotation.Yaw, rotation.Yaw) <= 0.1
        and angular_distance(actual_rotation.Roll, rotation.Roll) <= 0.1
    if reached_target then
        if not call_ok then
            verbose(string.format(
                "%s moved successfully despite UE4SS output marshalling error: %s",
                label,
                tostring(call_error)
            ))
        end
        return true
    end

    log(string.format(
        "Failed to apply %s transform: %s",
        label,
        call_ok and "actor did not reach the requested transform"
            or tostring(call_error)
    ))
    return false
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

    local calculate_ok, preview_location, preview_rotation = pcall(function()
        local calculated_location = desired_location
        local calculated_rotation = desired_rotation
        if preview_relative_location ~= nil and preview_relative_rotation ~= nil then
                local yaw = math.rad(desired_rotation.Yaw)
                calculated_location = {
                    X = desired_location.X
                        + (math.cos(yaw) * preview_relative_location.X)
                        - (math.sin(yaw) * preview_relative_location.Y),
                    Y = desired_location.Y
                        + (math.sin(yaw) * preview_relative_location.X)
                        + (math.cos(yaw) * preview_relative_location.Y),
                    Z = desired_location.Z + preview_relative_location.Z,
                }
                calculated_rotation = {
                    Pitch = desired_rotation.Pitch + preview_relative_rotation.Pitch,
                    Yaw = desired_rotation.Yaw + preview_relative_rotation.Yaw,
                    Roll = desired_rotation.Roll + preview_relative_rotation.Roll,
                }
        end
        return calculated_location, calculated_rotation
    end)
    if not calculate_ok then
        log("Failed to calculate preview transform: " .. tostring(preview_location))
        return false
    end

    -- Always attempt both calls. A post-call FHitResult marshal error from the
    -- checker must not prevent the visible preview from receiving its move.
    local checker_applied = set_actor_transform_verified(
        transform_actor,
        desired_location,
        desired_rotation,
        "InstallChecker"
    )
    local preview_applied = set_actor_transform_verified(
        preview_actor,
        preview_location,
        preview_rotation,
        "preview actor"
    )
    return checker_applied and preview_applied
end

local function start_transform_loop()
    if transform_loop_started or not Config.hold_locked_transform then
        return
    end

    if transform_loop_callback == nil then
        transform_loop_callback = function()
            if state ~= State.EDITING then
                transform_loop_started = false
                return true
            end
            local refresh_ok, refresh_error =
                pcall(apply_preview_transform)
            if not refresh_ok then
                transform_loop_started = false
                log("Frozen transform hold failed: "
                    .. tostring(refresh_error))
                return true
            end
            return false
        end
    end

    local cancel = runtime.loop(
        Config.transform_refresh_ms,
        transform_loop_callback,
        "Frozen transform hold"
    )
    if cancel ~= nil then
        transform_loop_started = true
    end
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

local function construction_ui_is_active(allow_fallback_scan)
    -- Reuse the known widget whenever possible. The fallback scan runs only
    -- when entering Freeze so ordinary gameplay remains event-driven.
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

    if is_live_object_of_exact_class(
        cached_construction_widget,
        CONSTRUCTION_WIDGET_CLASS_NAME
    ) then
        local cached_visibility =
            query_widget_visibility(cached_construction_widget)
        if cached_visibility == true or not allow_fallback_scan then
            return cached_visibility
        end
    end

    if not allow_fallback_scan then
        return nil
    end

    -- This fallback is reached only when the builder already reports an active
    -- preview and no usable widget has been cached. Cache the first live result;
    -- SetupKeyGuide's hook refreshes the cache if Palworld replaces the widget.
    local fallback_widget = nil
    for _, construction in ipairs(safe_find_all_of("WBP_IngameConstruction_C")) do
        if is_live_object_of_exact_class(
            construction,
            CONSTRUCTION_WIDGET_CLASS_NAME
        ) and construction ~= cached_construction_widget then
            local visible = query_widget_visibility(construction)
            if visible == true then
                cached_construction_widget = construction
                return true
            end
            if fallback_widget == nil and visible == nil then
                fallback_widget = construction
            end
        end
    end

    if is_valid(fallback_widget) then
        cached_construction_widget = fallback_widget
        return nil
    end
    cached_construction_widget = nil
    return false
end

local function refresh_overlap_component(component, refreshed_components)
    if not is_valid(component) then
        return
    end

    local component_name = full_name(component)
    if refreshed_components[component_name] then
        return
    end
    refreshed_components[component_name] = true

    local ok, error_message = pcall(function()
        local collision_profile = component:GetCollisionProfileName()
        component:SetCollisionProfileName(collision_profile, true)
    end)
    if not ok then
        verbose("Could not refresh overlaps for " .. component_name .. ": " .. tostring(error_message))
    end
end

local function refresh_locked_overlaps()
    local refreshed_components = {}

    local ok, error_message = pcall(function()
        if is_valid(transform_actor) then
            refresh_overlap_component(transform_actor.OverlapCheckComponent, refreshed_components)
            if is_valid(transform_actor.OverlapChecker) then
                refresh_overlap_component(transform_actor.OverlapChecker.Collision, refreshed_components)
            end
        end
        if is_valid(preview_actor) then
            refresh_overlap_component(preview_actor.OverlapCheckCollision, refreshed_components)
            if is_valid(preview_actor.OverlapChecker) then
                refresh_overlap_component(preview_actor.OverlapChecker.Collision, refreshed_components)
            end
        end
    end)
    if not ok then
        verbose("Could not enumerate frozen preview overlap components: " .. tostring(error_message))
    end
end

local function for_each_unreal_array(array, callback, label)
    if array == nil then
        return false
    end

    local ok, error_message = pcall(function()
        array:ForEach(function(index, wrapped_value)
            local value = wrapped_value
            local unwrap_ok, unwrapped_value = pcall(function()
                return wrapped_value:get()
            end)
            if unwrap_ok then
                value = unwrapped_value
            end

            local callback_ok, callback_error = pcall(callback, value, index)
            if not callback_ok then
                verbose(string.format(
                    "%s item failed: %s",
                    label or "Unreal array",
                    tostring(callback_error)
                ))
            end
        end)
    end)
    if not ok then
        verbose(string.format(
            "Could not iterate %s: %s",
            label or "Unreal array",
            tostring(error_message)
        ))
    end
    return ok
end

local function find_pal_utility()
    if is_valid(cached_pal_utility) then
        return cached_pal_utility
    end

    local ok, utility = pcall(function()
        local exact = StaticFindObject("/Script/Pal.Default__PalUtility")
        if is_valid(exact) then
            return exact
        end
        return FindFirstOf("PalUtility")
    end)
    if ok and is_valid(utility) then
        cached_pal_utility = utility
        return utility
    end
    cached_pal_utility = nil
    return nil
end

local function get_building_surface_material_set()
    local utility = find_pal_utility()
    if not is_valid(utility) or not is_valid(preview_actor) then
        return nil
    end

    local ok, material_set = pcall(function()
        local manager = utility:GetMapObjectManager(preview_actor)
        if not is_valid(manager) then
            return nil
        end
        return manager.BuildingSurfaceMaterialSet
    end)
    if ok then
        return material_set
    end
    verbose("Could not resolve Palworld's build surface materials: "
        .. tostring(material_set))
    return nil
end

local function material_is_two_sided(visual_control, mesh, material_index)
    local source_material = nil
    pcall(function()
        source_material =
            visual_control:GetMaterialInstanceNormal(mesh, material_index)
    end)
    if not is_valid(source_material) then
        pcall(function()
            source_material = mesh:GetMaterial(material_index)
        end)
    end
    if not is_valid(source_material) then
        return false
    end

    local base_material = source_material
    pcall(function()
        local resolved_base = source_material:GetBaseMaterial()
        if is_valid(resolved_base) then
            base_material = resolved_base
        end
    end)
    local ok, two_sided = pcall(function()
        return base_material.TwoSided
    end)
    return ok and two_sided == true
end

local function apply_material_to_mesh(
    mesh,
    visual_control,
    regular_material,
    two_sided_material
)
    if not is_valid(mesh) or not is_valid(regular_material) then
        return 0
    end

    local count_ok, material_count = pcall(function()
        return mesh:GetNumMaterials()
    end)
    material_count = count_ok and tonumber(material_count) or 0
    local changed = 0
    for material_index = 0, material_count - 1 do
        local material = regular_material
        if is_valid(two_sided_material)
            and material_is_two_sided(visual_control, mesh, material_index)
        then
            material = two_sided_material
        end

        local set_ok = pcall(function()
            mesh:SetMaterial(material_index, material)
        end)
        if set_ok then
            changed = changed + 1
        end
    end
    return changed
end

local function apply_locked_validity_material(is_placeable)
    local material_set = get_building_surface_material_set()
    if material_set == nil or not is_valid(preview_actor) then
        return false
    end

    local visual_ok, visual_control = pcall(function()
        return preview_actor.VisualCtrl
    end)
    if not visual_ok or not is_valid(visual_control) then
        return false
    end

    local materials_ok, regular_material, two_sided_material, work_material =
        pcall(function()
            if is_placeable then
                return material_set.Highlight,
                    material_set.HighlightTwoSided,
                    material_set.HighlightWorkPositionVisualizer
            end
            return material_set.Error,
                material_set.ErrorTwoSided,
                material_set.ErrorWorkPositionVisualizer
        end)
    if not materials_ok or not is_valid(regular_material) then
        return false
    end

    local changed = 0
    local meshes_ok, meshes = pcall(function()
        return preview_actor.AllMeshes
    end)
    if meshes_ok then
        for_each_unreal_array(meshes, function(mesh)
            changed = changed + apply_material_to_mesh(
                mesh,
                visual_control,
                regular_material,
                two_sided_material
            )
        end, "preview meshes")
    end

    if changed == 0 then
        local main_mesh_ok, main_mesh = pcall(function()
            return preview_actor.MainMesh
        end)
        if main_mesh_ok then
            changed = changed + apply_material_to_mesh(
                main_mesh,
                visual_control,
                regular_material,
                two_sided_material
            )
        end
    end

    if is_valid(work_material) then
        local work_ok, work_visualizers = pcall(function()
            return visual_control.WorkPositionVisualizers
        end)
        if work_ok then
            for_each_unreal_array(work_visualizers, function(component)
                changed = changed + apply_material_to_mesh(
                    component,
                    visual_control,
                    work_material,
                    work_material
                )
            end, "work-position visualizers")
        end
    end
    return changed > 0
end

local function refresh_building_validity_ui()
    local find_ok, widget = pcall(function()
        return FindFirstOf("WBP_PalBuilding_C")
    end)
    local widget_name = find_ok and full_name(widget) or "<invalid>"
    if not find_ok
        or not is_valid(widget)
        or string.find(widget_name, "Default__", 1, true) ~= nil
        or string.find(widget_name, "WidgetTree", 1, true) ~= nil
    then
        return
    end

    local ok, error_message = pcall(function()
        widget:UpdateDisplay()
    end)
    if not ok then
        verbose("Could not refresh Palworld's placement warning: "
            .. tostring(error_message))
    end
end

local function refresh_locked_validity()
    if Config.validity == nil
        or Config.validity.refresh_frozen_feedback ~= true
        or state ~= State.EDITING
        or not is_valid(builder_component)
        or not is_valid(preview_actor)
    then
        return
    end

    -- The builder and preview ticks stay suspended. Recompute the result from
    -- the moved overlaps, then propagate it with Palworld's own live surface
    -- material set and building-widget refresh.
    refresh_locked_overlaps()

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

    local material_updated = apply_locked_validity_material(is_placeable)
    refresh_building_validity_ui()
    if material_updated then
        last_preview_overlap_state = is_placeable
    else
        -- Retry on the next coalesced refresh if the preview's mesh hierarchy
        -- was still being constructed.
        last_preview_overlap_state = nil
        verbose("Frozen validity changed, but no preview material slot was ready.")
    end

    log(string.format(
        "Frozen preview is %s (operation result: %s; material refreshed: %s).",
        is_placeable and "placeable" or "not placeable",
        operation_text,
        tostring(material_updated)
    ))
end

local function ensure_validity_refresh_trigger()
    if validity_refresh_trigger ~= nil then
        return true
    end
    validity_refresh_trigger = runtime.throttle(
        VALIDITY_REFRESH_INTERVAL_MS,
        function()
            if not validity_refresh_pending then
                return
            end

            validity_refresh_pending = false
            if state ~= State.EDITING
                or validity_refresh_generation ~= freeze_transition_generation
            then
                return
            end
            refresh_locked_validity()
        end,
        "Frozen validity refresh"
    )
    return type(validity_refresh_trigger) == "function"
end

ensure_validity_refresh_trigger()

local function schedule_locked_validity_refresh()
    if Config.validity == nil
        or Config.validity.refresh_frozen_feedback ~= true
        or validity_refresh_pending
        or state ~= State.EDITING
    then
        return
    end
    if not ensure_validity_refresh_trigger() then
        return
    end

    validity_refresh_pending = true
    validity_refresh_generation = freeze_transition_generation
    if not validity_refresh_trigger() then
        validity_refresh_pending = false
    end
end

-- The native patch adds one empty VerticalBox_PP immediately ahead of the
-- stock footer. Lua owns only that container and builds four device/state
-- variants once, leaving Palworld's cooked rows and footer untouched.
construction_ui_hooks.__native_guide = {
    instances = {},
}

construction_ui_hooks.__native_guide.construct = function(
    construction,
    class_path
)
    if not is_valid(construction) then
        return nil
    end
    local tree_ok, widget_tree = pcall(function()
        return construction.WidgetTree
    end)
    if not tree_ok or not is_valid(widget_tree) then
        return nil
    end
    local class = StaticFindObject(class_path)
    if not is_valid(class) then
        return nil
    end
    local ok, widget = pcall(function()
        return StaticConstructObject(
            class,
            widget_tree,
            0,
            0,
            0,
            nil,
            false,
            false,
            nil
        )
    end)
    return ok and is_valid(widget) and widget or nil
end

construction_ui_hooks.__native_guide.find_widget = function(
    construction,
    expected_name
)
    if not is_valid(construction) then
        return nil
    end
    local root_ok, root = pcall(function()
        return construction.WidgetTree.RootWidget
    end)
    if not root_ok or not is_valid(root) then
        return nil
    end
    local visited = {}
    local function walk(widget)
        if not is_valid(widget) then
            return nil
        end
        local identity = full_name(widget)
        if visited[identity] then
            return nil
        end
        visited[identity] = true
        local name_ok, name = pcall(function()
            return widget:GetFName():ToString()
        end)
        if name_ok and tostring(name) == expected_name then
            return widget
        end
        local count_ok, count = pcall(function()
            return widget:GetChildrenCount()
        end)
        if count_ok then
            for index = 0, count - 1 do
                local child_ok, child = pcall(function()
                    return widget:GetChildAt(index)
                end)
                if child_ok then
                    local found = walk(child)
                    if is_valid(found) then
                        return found
                    end
                end
            end
        end
        return nil
    end
    return walk(root)
end

construction_ui_hooks.__native_guide.is_gamepad_active = function()
    local subsystem = FindFirstOf("CommonInputSubsystem")
    if not is_valid(subsystem) then
        return false
    end
    local ok, input_type = pcall(function()
        return subsystem.CurrentInputType
    end)
    if not ok then
        return false
    end
    local numeric = tonumber(input_type)
    if numeric == nil then
        local unwrap_ok, unwrapped = pcall(function()
            return input_type:get()
        end)
        numeric = unwrap_ok and tonumber(unwrapped) or nil
    end
    if numeric ~= nil then
        return numeric == 1
    end
    return string.find(
        string.lower(tostring(input_type)),
        "gamepad",
        1,
        true
    ) ~= nil
end

construction_ui_hooks.__native_guide.create_widget = function(
    construction,
    asset_path,
    class_path
)
    local library = StaticFindObject(
        "/Script/UMG.Default__WidgetBlueprintLibrary"
    )
    local widget_class = StaticFindObject(class_path)
    if not is_valid(widget_class) then
        pcall(function()
            LoadAsset(asset_path)
        end)
        widget_class = StaticFindObject(class_path)
    end
    if not is_valid(library) or not is_valid(widget_class) then
        return nil
    end
    local create_ok, widget = pcall(function()
        return library:Create(
            construction,
            widget_class,
            construction:GetOwningPlayer()
        )
    end)
    return create_ok and is_valid(widget) and widget or nil
end

construction_ui_hooks.__native_guide.create_chord = function(
    construction,
    state_name,
    action,
    use_gamepad
)
    local binding = nil
    if use_gamepad and gamepad_feature ~= nil then
        local bindings_ok, gamepad_bindings = pcall(function()
            return gamepad_feature:get_resolved_bindings()
        end)
        if not bindings_ok then
            return nil
        end
        binding = gamepad_bindings ~= nil
            and gamepad_bindings[state_name] ~= nil
            and gamepad_bindings[state_name][action]
            or nil
    else
        binding = resolved_bindings[action]
    end
    if binding == nil or binding.disabled then
        return nil
    end

    local chord = construction_ui_hooks.__native_guide.construct(
        construction,
        "/Script/UMG.HorizontalBox"
    )
    if not is_valid(chord) then
        return nil
    end

    local tokens = {}
    for _, modifier in ipairs(binding.modifiers or {}) do
        tokens[#tokens + 1] = modifier
    end
    tokens[#tokens + 1] = binding.key
    for index, token in ipairs(tokens) do
        local texture = nil
        if use_gamepad and gamepad_feature ~= nil then
            local texture_ok, loaded_texture = pcall(function()
                return gamepad_feature:get_keycap_texture(token)
            end)
            texture = texture_ok and loaded_texture or nil
        else
            local asset = index < #tokens
                and Keybindings.get_modifier_asset(token)
                or binding.key_info
            texture = load_keycap_texture(asset)
        end
        if is_valid(texture) then
            local box = construction_ui_hooks.__native_guide.construct(
                construction,
                "/Script/UMG.SizeBox"
            )
            local image = construction_ui_hooks.__native_guide.construct(
                construction,
                "/Script/UMG.Image"
            )
            if not is_valid(box) or not is_valid(image) then
                return nil
            end
            -- Palworld's input-data brush and the stock key-guide row are both
            -- serialized at 36x36. Match that size and center the child slot;
            -- the default Fill alignment otherwise stretches a smaller box to
            -- the row height without increasing its width.
            local keycap_size = 36.0
            local key_ok, key_slot = pcall(function()
                box:SetWidthOverride(keycap_size)
                box:SetHeightOverride(keycap_size)
                image:SetBrushFromTexture(texture, true)
                box:SetContent(image)
                return chord:AddChildToHorizontalBox(box)
            end)
            if not key_ok then
                return nil
            end
            if is_valid(key_slot) then
                pcall(function()
                    key_slot:SetVerticalAlignment(1)
                end)
                key_slot:SetPadding({
                    Left = 0.0,
                    Top = 0.0,
                    Right = index < #tokens and 3.0 or 0.0,
                    Bottom = 0.0,
                })
            end
        end
    end
    local count_ok, child_count = pcall(function()
        return chord:GetChildrenCount()
    end)
    return count_ok and child_count > 0 and chord or nil
end

construction_ui_hooks.__native_guide.create_action_separator = function(
    construction
)
    local box = construction_ui_hooks.__native_guide.construct(
        construction,
        "/Script/UMG.SizeBox"
    )
    local divider = construction_ui_hooks.__native_guide.construct(
        construction,
        "/Script/UMG.Border"
    )
    if not is_valid(box) or not is_valid(divider) then
        return nil
    end
    local separator_ok = pcall(function()
        box:SetWidthOverride(1.0)
        box:SetHeightOverride(22.0)
        divider:SetBrushColor({
            R = 1.0,
            G = 1.0,
            B = 1.0,
            A = 0.45,
        })
        box:SetContent(divider)
    end)
    return separator_ok and box or nil
end

construction_ui_hooks.__native_guide.create_row = function(
    construction,
    state_name,
    definition,
    use_gamepad
)
    local row = construction_ui_hooks.__native_guide.create_widget(
        construction,
        "/Game/Pal/Blueprint/UI/UserInterface/InGame/Construction/"
            .. "WBP_Ingameconstruction_KeyGuide",
        "/Game/Pal/Blueprint/UI/UserInterface/InGame/Construction/"
            .. "WBP_Ingameconstruction_KeyGuide"
            .. ".WBP_Ingameconstruction_KeyGuide_C"
    )
    if not is_valid(row) then
        return nil
    end
    local row_ok = pcall(function()
        row.HorizontalBox_46:ClearChildren()
        local rendered_actions = 0
        for _, action in ipairs(definition.actions) do
            local chord = construction_ui_hooks.__native_guide.create_chord(
                construction,
                state_name,
                action,
                use_gamepad
            )
            if is_valid(chord) then
                if rendered_actions > 0 then
                    local separator = construction_ui_hooks.__native_guide
                        .create_action_separator(construction)
                    if is_valid(separator) then
                        local separator_slot = row.HorizontalBox_46
                            :AddChildToHorizontalBox(separator)
                        if is_valid(separator_slot) then
                            separator_slot:SetPadding({
                                Left = 4.0,
                                Top = 0.0,
                                Right = 8.0,
                                Bottom = 0.0,
                            })
                            pcall(function()
                                separator_slot:SetVerticalAlignment(2)
                            end)
                        end
                    end
                end
                local chord_slot = row.HorizontalBox_46:AddChildToHorizontalBox(
                    chord
                )
                if is_valid(chord_slot) then
                    chord_slot:SetPadding({
                        Left = 0.0,
                        Top = 0.0,
                        Right = 4.0,
                        Bottom = 0.0,
                    })
                end
                rendered_actions = rendered_actions + 1
            end
        end
        row.Text_Main:SetText(FText(definition.label))
        row.HorizontalBox_46:SetVisibility(0)
        row.Text_Main:SetVisibility(0)
        row:SetVisibility(0)
    end)
    return row_ok and row or nil
end

construction_ui_hooks.__native_guide.populate_panel = function(
    construction,
    panel,
    state_name,
    row_pairs,
    use_gamepad,
    dynamic_rows
)
    for _, pair in ipairs(row_pairs) do
        local horizontal = construction_ui_hooks.__native_guide.construct(
            construction,
            "/Script/UMG.HorizontalBox"
        )
        if not is_valid(horizontal) then
            return false
        end
        for index, definition in ipairs(pair) do
            local row = construction_ui_hooks.__native_guide.create_row(
                construction,
                state_name,
                definition,
                use_gamepad
            )
            if not is_valid(row) then
                return false
            end
            if definition.dynamic_name ~= nil
                and dynamic_rows ~= nil
            then
                dynamic_rows[definition.dynamic_name] =
                    dynamic_rows[definition.dynamic_name] or {}
                table.insert(dynamic_rows[definition.dynamic_name], row)
            end
            local add_ok, row_slot = pcall(function()
                return horizontal:AddChildToHorizontalBox(row)
            end)
            if not add_ok then
                return false
            end
            if is_valid(row_slot) and index < #pair then
                row_slot:SetPadding({
                    Left = 0.0,
                    Top = 0.0,
                    Right = 24.0,
                    Bottom = 0.0,
                })
            end
        end
        local add_ok, horizontal_slot = pcall(function()
            return panel:AddChildToVerticalBox(horizontal)
        end)
        if not add_ok then
            return false
        end
        if is_valid(horizontal_slot) then
            horizontal_slot:SetPadding({
                Left = 0.0,
                Top = 0.0,
                Right = 0.0,
                Bottom = 4.0,
            })
        end
    end
    return true
end

construction_ui_hooks.__native_guide.build = function(construction)
    local guide = construction_ui_hooks.__native_guide
    local instance_key = full_name(construction)
    local previous = guide.instances[instance_key]
    if previous ~= nil then
        if previous.released == true or previous.blocked == true then
            return nil
        end
        if previous.root ~= nil and is_valid(previous.root) then
            return previous
        end
        guide.instances[instance_key] = nil
    end

    local root = guide.find_widget(
        construction,
        "VerticalBox_PP"
    )
    if not is_valid(root) then
        log("Native guide scaffold VerticalBox_PP was not found.")
        return nil
    end
    local count_ok, root_child_count = pcall(function()
        return root:GetChildrenCount()
    end)
    if not count_ok then
        return nil
    end
    if root_child_count > 0 then
        guide.instances[instance_key] = { blocked = true }
        log("Native guide scaffold was already populated without a live cache.")
        return nil
    end

    local keyboard_frozen = guide.construct(
        construction,
        "/Script/UMG.VerticalBox"
    )
    local keyboard_unfrozen = guide.construct(
        construction,
        "/Script/UMG.VerticalBox"
    )
    local gamepad_frozen = guide.construct(
        construction,
        "/Script/UMG.VerticalBox"
    )
    local gamepad_unfrozen = guide.construct(
        construction,
        "/Script/UMG.VerticalBox"
    )
    if not is_valid(keyboard_frozen)
        or not is_valid(keyboard_unfrozen)
        or not is_valid(gamepad_frozen)
        or not is_valid(gamepad_unfrozen)
    then
        return nil
    end
    local attach_ok = pcall(function()
        root:AddChildToVerticalBox(keyboard_frozen)
        root:AddChildToVerticalBox(keyboard_unfrozen)
        root:AddChildToVerticalBox(gamepad_frozen)
        root:AddChildToVerticalBox(gamepad_unfrozen)
    end)
    if not attach_ok then
        return nil
    end

    local move_step_label = string.format(
        "Step Down / Up (%g cm)",
        current_move_step
    )
    local frozen_rows = {
        {
            { actions = { "move_left", "move_right" }, label = "Left / Right" },
            { actions = { "move_forward", "move_back" }, label = "Forward / Back" },
        },
        {
            { actions = { "move_up", "move_down" }, label = "Up / Down" },
            { actions = { "rotate_left", "rotate_right" }, label = "Rotate Left / Right" },
        },
        {
            {
                actions = { "step_down", "step_up" },
                label = move_step_label,
                dynamic_name = "move_step",
            },
            { actions = { "reset" }, label = "Reset" },
        },
        {
            { actions = { "toggle_freeze" }, label = "Unfreeze" },
        },
    }
    local unfrozen_rows = {
        {
            { actions = { "toggle_freeze" }, label = "Freeze" },
            { actions = { "copy_piece" }, label = "Copy Piece" },
        },
        {
            { actions = { "freeze_to_piece" }, label = "Copy and Freeze" },
        },
    }
    local dynamic_rows = {}
    local keyboard_frozen_ok = guide.populate_panel(
        construction,
        keyboard_frozen,
        "frozen",
        frozen_rows,
        false,
        dynamic_rows
    )
    local keyboard_unfrozen_ok = guide.populate_panel(
        construction,
        keyboard_unfrozen,
        "unfrozen",
        unfrozen_rows,
        false,
        nil
    )
    local gamepad_frozen_ok = guide.populate_panel(
        construction,
        gamepad_frozen,
        "frozen",
        frozen_rows,
        true,
        dynamic_rows
    )
    local gamepad_unfrozen_ok = guide.populate_panel(
        construction,
        gamepad_unfrozen,
        "unfrozen",
        unfrozen_rows,
        true,
        nil
    )
    if not keyboard_frozen_ok
        or not keyboard_unfrozen_ok
        or not gamepad_frozen_ok
        or not gamepad_unfrozen_ok
    then
        pcall(function()
            root:ClearChildren()
            root:SetVisibility(1)
        end)
        return nil
    end

    local instance = {
        root = root,
        keyboard_frozen = keyboard_frozen,
        keyboard_unfrozen = keyboard_unfrozen,
        gamepad_frozen = gamepad_frozen,
        gamepad_unfrozen = gamepad_unfrozen,
        dynamic_rows = dynamic_rows,
        mode = nil,
    }
    guide.instances[instance_key] = instance
    log("Crash-isolated native construction guide created.")
    return instance
end

construction_ui_hooks.__native_guide.refresh_move_step = function(construction)
    if not is_valid(construction) then
        return false
    end
    local instance = construction_ui_hooks.__native_guide.instances[
        full_name(construction)
    ]
    if instance == nil or instance.dynamic_rows == nil then
        return false
    end
    local rows = instance.dynamic_rows.move_step or {}
    local label = string.format("Step Down / Up (%g cm)", current_move_step)
    local updated = false
    for _, row in ipairs(rows) do
        if is_valid(row) then
            local row_ok = pcall(function()
                row.Text_Main:SetText(FText(label))
            end)
            updated = row_ok or updated
        end
    end
    return updated
end

construction_ui_hooks.__native_guide.show = function(construction, locked)
    local instance = construction_ui_hooks.__native_guide.build(construction)
    if instance == nil then
        return false
    end
    local use_gamepad = gamepad_feature ~= nil
        and construction_ui_hooks.__native_guide.is_gamepad_active()
    local requested_mode = (use_gamepad and "gamepad:" or "keyboard:")
        .. (locked and "frozen" or "unfrozen")
    if instance.mode == requested_mode then
        return true
    end
    local show_ok = pcall(function()
        instance.root:SetVisibility(0)
        instance.keyboard_frozen:SetVisibility(
            not use_gamepad and locked and 0 or 1
        )
        instance.keyboard_unfrozen:SetVisibility(
            not use_gamepad and not locked and 0 or 1
        )
        instance.gamepad_frozen:SetVisibility(
            use_gamepad and locked and 0 or 1
        )
        instance.gamepad_unfrozen:SetVisibility(
            use_gamepad and not locked and 0 or 1
        )
    end)
    if show_ok then
        instance.mode = requested_mode
    end
    return show_ok
end

construction_ui_hooks.__native_guide.hide = function(construction)
    local instance = construction_ui_hooks.__native_guide.instances[
        full_name(construction)
    ]
    if instance ~= nil and is_valid(instance.root) then
        pcall(function()
            instance.root:SetVisibility(1)
        end)
        instance.mode = "hidden"
    end
end

construction_ui_hooks.__native_guide.release = function(construction)
    if is_valid(construction) then
        local guide = construction_ui_hooks.__native_guide
        local construction_name = full_name(construction)
        guide.instances[construction_name] = { released = true }
        guide.detached_stock_rows[construction_name] = nil
        guide.stock_layout_requests[construction_name] = nil
        guide.stock_layout_modes[construction_name] = nil
    end
end

construction_ui_hooks.__native_guide.stock_locked_row_names = {
    WBP_Ingameconstruction_KeyGuide_Rotate = true,
    WBP_Ingameconstruction_KeyGuide_5 = true,
    WBP_Ingameconstruction_KeyGuide_6 = true,
    WBP_Ingameconstruction_KeyGuide_7 = true,
}
construction_ui_hooks.__native_guide.detached_stock_rows = {}
construction_ui_hooks.__native_guide.stock_layout_requests = {}
construction_ui_hooks.__native_guide.stock_layout_modes = {}
construction_ui_hooks.__native_guide.stock_layout_serial = 0

construction_ui_hooks.__native_guide.capture_vertical_padding = function(widget)
    local padding = { Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 }
    pcall(function()
        local source = widget.Slot.Padding
        padding.Left = tonumber(source.Left) or 0.0
        padding.Top = tonumber(source.Top) or 0.0
        padding.Right = tonumber(source.Right) or 0.0
        padding.Bottom = tonumber(source.Bottom) or 0.0
    end)
    return padding
end

construction_ui_hooks.__native_guide.relayout_panel = function(panel)
    if not is_valid(panel) then
        return
    end
    pcall(function()
        panel:InvalidateLayoutAndVolatility()
    end)
    pcall(function()
        panel:ForceLayoutPrepass()
    end)
end

construction_ui_hooks.__native_guide.detach_stock_rows = function(construction)
    local guide = construction_ui_hooks.__native_guide
    local construction_name = full_name(construction)
    local previous = guide.detached_stock_rows[construction_name]
    if previous ~= nil and is_valid(previous.parent) then
        guide.stock_layout_modes[construction_name] = "frozen"
        return true
    end

    local parent = guide.find_widget(construction, "VerticalBox_144")
    if not is_valid(parent) then
        log("Stock construction-guide parent VerticalBox_144 was not found.")
        return false
    end

    local original = {}
    local original_names = {}
    local targets = {}
    local first_target_index = nil
    local capture_ok, capture_error = pcall(function()
        local child_count = parent:GetChildrenCount()
        for index = 0, child_count - 1 do
            local child = parent:GetChildAt(index)
            if is_valid(child) then
                local child_name = child:GetFName():ToString()
                local item = {
                    widget = child,
                    index = index,
                    padding = guide.capture_vertical_padding(child),
                }
                table.insert(original, item)
                original_names[full_name(child)] = true
                if guide.stock_locked_row_names[child_name] == true then
                    table.insert(targets, item)
                    first_target_index = first_target_index == nil
                        and index
                        or math.min(first_target_index, index)
                end
            end
        end
    end)
    if not capture_ok or #targets == 0 or first_target_index == nil then
        log("Could not capture stock construction rows for detachment: "
            .. tostring(capture_error))
        return false
    end

    table.sort(targets, function(left, right)
        return left.index > right.index
    end)
    local removed = 0
    for _, item in ipairs(targets) do
        local remove_ok, did_remove = pcall(function()
            return parent:RemoveChild(item.widget)
        end)
        if remove_ok and did_remove ~= false then
            removed = removed + 1
        end
    end
    guide.relayout_panel(parent)
    if removed == 0 then
        return false
    end

    guide.detached_stock_rows[construction_name] = {
        parent = parent,
        original = original,
        original_names = original_names,
        first_target_index = first_target_index,
    }
    guide.stock_layout_modes[construction_name] = "frozen"
    log(string.format(
        "Detached %d of %d frozen-only stock construction rows.",
        removed,
        #targets
    ))
    return removed == #targets
end

construction_ui_hooks.__native_guide.restore_stock_rows = function(construction)
    local guide = construction_ui_hooks.__native_guide
    local construction_name = full_name(construction)
    local record = guide.detached_stock_rows[construction_name]
    if record == nil then
        guide.stock_layout_modes[construction_name] = "unfrozen"
        return true
    end
    local parent = record.parent
    if not is_valid(parent) then
        guide.detached_stock_rows[construction_name] = nil
        guide.stock_layout_modes[construction_name] = nil
        return false
    end

    local restore_ok, restore_error = pcall(function()
        local extras = {}
        local child_count = parent:GetChildrenCount()
        for index = record.first_target_index, child_count - 1 do
            local child = parent:GetChildAt(index)
            if is_valid(child)
                and record.original_names[full_name(child)] ~= true
            then
                table.insert(extras, {
                    widget = child,
                    padding = guide.capture_vertical_padding(child),
                })
            end
        end

        for index = child_count - 1, record.first_target_index, -1 do
            parent:RemoveChildAt(index)
        end

        local function append_item(item)
            if not is_valid(item.widget) then
                return
            end
            local slot = parent:AddChildToVerticalBox(item.widget)
            if is_valid(slot) then
                slot:SetPadding(item.padding)
            end
        end
        for _, item in ipairs(record.original) do
            if item.index >= record.first_target_index then
                append_item(item)
            end
        end
        for _, item in ipairs(extras) do
            append_item(item)
        end
    end)
    guide.relayout_panel(parent)
    if not restore_ok then
        log("Could not restore detached stock construction rows: "
            .. tostring(restore_error))
        guide.stock_layout_modes[construction_name] = nil
        return false
    end
    guide.detached_stock_rows[construction_name] = nil
    guide.stock_layout_modes[construction_name] = "unfrozen"
    log("Restored stock construction rows in their original order.")
    return true
end

construction_ui_hooks.__native_guide.schedule_stock_layout = function(
    construction,
    locked
)
    local guide = construction_ui_hooks.__native_guide
    if not is_live_object_of_exact_class(
        construction,
        CONSTRUCTION_WIDGET_CLASS_NAME
    ) then
        return false
    end

    local construction_name = full_name(construction)
    local requested_mode = locked and "frozen" or "unfrozen"
    local existing = guide.stock_layout_requests[construction_name]
    if existing ~= nil and existing.mode == requested_mode then
        count_ui_lifecycle_metric("native_layout_coalesced")
        return true
    end
    local requested_display_mode =
        (gamepad_feature ~= nil and guide.is_gamepad_active()
            and "gamepad:" or "keyboard:")
        .. requested_mode
    local instance = guide.instances[construction_name]
    local display_is_current = instance ~= nil
        and is_valid(instance.root)
        and instance.mode == requested_display_mode
    if existing == nil
        and guide.stock_layout_modes[construction_name] == requested_mode
        and display_is_current
    then
        return true
    end

    guide.stock_layout_serial = guide.stock_layout_serial + 1
    local request_id = guide.stock_layout_serial
    local queued_freeze_generation = freeze_transition_generation
    local queued_construction_generation = construction_ui_generation
    guide.stock_layout_requests[construction_name] = {
        id = request_id,
        mode = requested_mode,
    }
    count_ui_lifecycle_metric("native_layout_queued")

    local queued = runtime.delay(
        75,
        function()
            local request = guide.stock_layout_requests[construction_name]
            if request == nil
                or request.id ~= request_id
                or request.mode ~= requested_mode
            then
                count_ui_lifecycle_metric("native_layout_superseded")
                return
            end
            guide.stock_layout_requests[construction_name] = nil
            if queued_freeze_generation ~= freeze_transition_generation
                or queued_construction_generation ~= construction_ui_generation
                or full_name(construction) ~= construction_name
                or full_name(cached_construction_widget) ~= construction_name
                or not is_live_object_of_exact_class(
                    construction,
                    CONSTRUCTION_WIDGET_CLASS_NAME
                )
                or (locked and state ~= State.EDITING)
                or (not locked and state == State.EDITING)
            then
                count_ui_lifecycle_metric("native_layout_stale")
                return
            end

            local shown = guide.show(construction, locked)
            if locked and not shown then
                guide.stock_layout_modes[construction_name] = nil
                count_ui_lifecycle_metric("native_guide_failed")
                log("Native frozen construction guide could not be displayed; stock rows were preserved.")
                return
            end

            local changed = locked
                and guide.detach_stock_rows(construction)
                or guide.restore_stock_rows(construction)
            if not changed then
                guide.stock_layout_modes[construction_name] = nil
                count_ui_lifecycle_metric("native_layout_failed")
            else
                count_ui_lifecycle_metric("native_layout_applied")
            end
        end,
        "Native construction guide layout",
        function()
            local request = guide.stock_layout_requests[construction_name]
            if request ~= nil and request.id == request_id then
                guide.stock_layout_requests[construction_name] = nil
            end
        end
    )
    if not queued then
        guide.stock_layout_requests[construction_name] = nil
    end
    return queued
end

local function set_native_locked_controls_hidden(construction, hidden)
    if not is_valid(construction) then
        return false
    end
    return construction_ui_hooks.__native_guide.schedule_stock_layout(
        construction,
        hidden
    )
end

local function apply_locked_keyguide(construction)
    if state ~= State.EDITING or not is_valid(construction) then
        return
    end
    set_native_locked_controls_hidden(construction, true)
end

local function hide_locked_keyguide(construction)
    if not is_valid(construction) then
        return
    end
    set_native_locked_controls_hidden(construction, false)
end

local function unfrozen_guide_transition_is_locked()
    return freeze_transition_input_locked
        or state == State.EDITING
        or state == State.FREEZING
        or state == State.UNFREEZING
        or state == State.SWITCHING
end

local function unfrozen_guide_is_stable()
    if unfrozen_guide_transition_is_locked() then
        return false
    end
    if Config.ui ~= nil
        and Config.ui.use_native_construction_guide == true
        and is_valid(cached_construction_widget)
    then
        local instance = construction_ui_hooks.__native_guide.instances[
            full_name(cached_construction_widget)
        ]
        local requested_mode =
            (gamepad_feature ~= nil
                and construction_ui_hooks.__native_guide.is_gamepad_active()
                and "gamepad:" or "keyboard:")
            .. "unfrozen"
        return instance ~= nil
            and is_valid(instance.root)
            and instance.mode == requested_mode
    end
    return perfect_placement_ui_mode == "unfrozen"
        and perfect_placement_ui_host ~= nil
end

local function show_unfrozen_guide_for_active_preview()
    if unfrozen_guide_transition_is_locked() then
        return false
    end
    if construction_ui_is_active(false) ~= true then
        return false
    end

    local active_component, active_checker, active_preview =
        find_active_build_context(false)
    if not is_valid(active_component)
        or not is_valid(active_checker)
        or not is_valid(active_preview)
    then
        return false
    end
    local companion_updated = update_perfect_placement_ui(
        false,
        false,
        false
    )
    if Config.ui ~= nil
        and Config.ui.use_native_construction_guide == true
        and is_valid(cached_construction_widget)
    then
        hide_locked_keyguide(cached_construction_widget)
        return true
    end
    return companion_updated
end

local function ensure_keyguide_hook()
    if keyguide_hook_registered ~= false then
        return keyguide_hook_registered.complete == true
    end
    if keyguide_hook_callback == nil then
        keyguide_hook_callback = function(context)
            count_ui_lifecycle_metric("setup_keyguide")
            if gamepad_feature ~= nil then
                pcall(gamepad_feature.ensure_current_world, gamepad_feature)
                pcall(
                    gamepad_feature.set_using_gamepad,
                    gamepad_feature,
                    construction_ui_hooks.__native_guide.is_gamepad_active()
                )
            end
            local native_ui_enabled = Config.ui ~= nil
                and Config.ui.use_native_construction_guide == true
            if unfrozen_guide_is_stable() and not native_ui_enabled then
                return
            end
            if state ~= State.EDITING
                and unfrozen_guide_transition_is_locked()
            then
                count_ui_lifecycle_metric("setup_keyguide_suppressed")
                return
            end
            local construction = context
            local unwrap_ok, unwrapped = pcall(function()
                return context:get()
            end)
            if unwrap_ok and unwrapped ~= nil then
                construction = unwrapped
            end
            if is_valid(construction) then
                cached_construction_widget = construction
            end
            local apply_ok, apply_error = pcall(function()
                if state == State.EDITING then
                    if native_ui_enabled then
                        construction_ui_hooks.__native_guide.stock_layout_modes[
                            full_name(construction)
                        ] = nil
                        apply_locked_keyguide(construction)
                    end
                    return
                end

                -- SetupKeyGuide can observe the builder between Palworld's
                -- checker and preview assignments. Do not turn that transient
                -- false negative into an unfrozen -> hidden -> unfrozen input
                -- actor cycle. Explicit construction exit hooks still hide it.
                if perfect_placement_ui_mode ~= "unfrozen"
                    and not show_unfrozen_guide_for_active_preview()
                then
                    construction_ui_hooks.__native_guide.hide(construction)
                    update_perfect_placement_ui(false, false, true)
                elseif native_ui_enabled then
                    hide_locked_keyguide(construction)
                end
            end)
            if not apply_ok then
                log("Could not apply hooked construction guide: " .. tostring(apply_error))
            end
        end
    end
    local ok, pre_id, post_id = pcall(function()
        return RegisterHook(
            KEYGUIDE_SETUP_PATH,
            keyguide_hook_callback
        )
    end)
    if not ok then
        verbose("Construction key-guide hook is not loaded yet.")
        return false
    end
    keyguide_hook_registered = {
        callback = keyguide_hook_callback,
        pre_id = pre_id,
        post_id = post_id,
        complete = pre_id ~= nil and post_id ~= nil,
    }
    if not keyguide_hook_registered.complete then
        log("Construction key-guide registration returned incomplete IDs; retries are disabled.")
        return false
    end
    log("Construction key-guide event hook registered.")
    return true
end

local function schedule_construction_setup_retry(construction)
    if construction_setup_retry_pending then
        count_ui_lifecycle_metric("setup_retry_coalesced")
        return true
    end

    construction_setup_retry_pending = true
    local queued_freeze_generation = freeze_transition_generation
    local queued_construction_generation = construction_ui_generation
    local queued_construction_name = full_name(construction)
    count_ui_lifecycle_metric("setup_retry_queued")
    local queued = runtime.delay(
        100,
        function()
            construction_setup_retry_pending = false
            if queued_freeze_generation ~= freeze_transition_generation
                or queued_construction_generation ~= construction_ui_generation
                or unfrozen_guide_transition_is_locked()
            then
                count_ui_lifecycle_metric("setup_retry_stale")
                return
            end
            if not full_name_is_available(queued_construction_name)
                or queued_construction_name ~= full_name(cached_construction_widget)
            then
                count_ui_lifecycle_metric("setup_retry_replaced")
                return
            end
            if unfrozen_guide_is_stable() then
                return
            end
            -- Setup is a resume signal, not an authoritative exit signal. A
            -- failed retry must never hide the frozen guide or disable input.
            show_unfrozen_guide_for_active_preview()
        end,
        "Construction guide Setup retry",
        function()
            construction_setup_retry_pending = false
        end
    )
    if not queued then
        construction_setup_retry_pending = false
    end
    return queued
end

local function ensure_construction_ui_hooks()
    local building_root =
        "/Game/Pal/Blueprint/UI/BuildMenu/WBP_PalBuilding"
        .. ".WBP_PalBuilding_C:"
    local input_root =
        "/Game/Pal/Blueprint/UI/WBP_PalHUD_InGame_InputListener"
        .. ".WBP_PalHUD_InGame_InputListener_C:"
    local construction_root =
        "/Game/Pal/Blueprint/UI/UserInterface/InGame/Construction/"
        .. "WBP_IngameConstruction.WBP_IngameConstruction_C:"
    local all_registered = true

    -- Foundation replacement mode rebuilds the active preview. Report it as
    -- unavailable while Perfect Placement owns a frozen preview; PP keybinds
    -- still run through their own callbacks, but Palworld's unbound action is
    -- prevented from changing modes beneath the paused preview.
    local can_change_replace_path =
        "/Script/Pal.PalUIBuildingModel:CanChangeReplaceModeForBuildObject"
    local replacement_hook = construction_ui_hooks[can_change_replace_path]
    if replacement_hook == nil then
        local pre_callback = function()
            if state == State.EDITING then
                verbose("Blocked Replacement Mode while preview is frozen.")
                return false
            end
            return nil
        end
        -- Supplying a post callback keeps native hooks compatible with UE4SS
        -- builds that require both hook slots, even though this one is a no-op.
        local post_callback = function() end
        local hook_ok, pre_id, post_id = pcall(function()
            return RegisterHook(
                can_change_replace_path,
                pre_callback,
                post_callback
            )
        end)
        if hook_ok then
            replacement_hook = {
                callback = pre_callback,
                post_callback = post_callback,
                pre_id = pre_id,
                post_id = post_id,
                complete = pre_id ~= nil and post_id ~= nil,
            }
            construction_ui_hooks[can_change_replace_path] = replacement_hook
            if not replacement_hook.complete then
                log("Replacement Mode blocker registration returned incomplete IDs; retries are disabled.")
            end
        else
            verbose("Replacement Mode availability query is not loaded yet: "
                .. tostring(pre_id))
        end
    end
    if replacement_hook == nil or replacement_hook.complete ~= true then
        all_registered = false
    end

    local function register_event_hook(function_path, event_name, resumes_guide)
        local existing = construction_ui_hooks[function_path]
        if existing ~= nil then
            return existing.complete == true
        end

        local captured_name = event_name
        local callback = function(context)
            local callback_ok, callback_error = pcall(function()
                if resumes_guide then
                    count_ui_lifecycle_metric("construction_setup")
                    if unfrozen_guide_is_stable()
                        or unfrozen_guide_transition_is_locked()
                    then
                        count_ui_lifecycle_metric("construction_setup_suppressed")
                        return
                    end

                    local construction = context
                    local unwrap_ok, unwrapped = pcall(function()
                        return context:get()
                    end)
                    if unwrap_ok and unwrapped ~= nil then
                        construction = unwrapped
                    end
                    if is_valid(construction) then
                        cached_construction_widget = construction
                    end

                    if show_unfrozen_guide_for_active_preview() then
                        return
                    end
                    schedule_construction_setup_retry(construction)
                    return
                end

                construction_ui_generation = construction_ui_generation + 1
                count_ui_lifecycle_metric("construction_exit")
                if state == State.EDITING and release_preview ~= nil then
                    log("Auto-releasing frozen preview after Palworld action: "
                        .. captured_name .. ".")
                    release_preview("Palworld action: " .. captured_name)
                else
                    update_perfect_placement_ui(false, false, true)
                end
            end)
            if not callback_ok then
                log("Construction UI event failed for "
                    .. captured_name .. ": " .. tostring(callback_error))
            end
        end

        local hook_ok, pre_id, post_id = pcall(function()
            return RegisterHook(function_path, callback)
        end)
        if not hook_ok then
            verbose("Construction UI event is not loaded yet: "
                .. function_path)
            return false
        end

        construction_ui_hooks[function_path] = {
            callback = callback,
            pre_id = pre_id,
            post_id = post_id,
            complete = pre_id ~= nil and post_id ~= nil,
        }
        if pre_id == nil or post_id == nil then
            log("Construction UI event registration returned incomplete IDs; retries are disabled: "
                .. function_path)
            return false
        end
        return true
    end

    for _, function_name in ipairs({
        "ReturnToMainMenu",
        "OnEsc",
        "ChangeMode",
        "Destruct",
    }) do
        if not register_event_hook(
            building_root .. function_name,
            function_name,
            false
        ) then
            all_registered = false
        end
    end

    for _, function_name in ipairs({
        "OpenMenu_Internal",
        "OpenBuildMenu",
        "OpenBuildRadialMenu",
        "OpenBuildRadialMenuWithSelectedIndex",
        "OnTriggerEscape",
    }) do
        if not register_event_hook(
            input_root .. function_name,
            function_name,
            false
        ) then
            all_registered = false
        end
    end

    if not register_event_hook(
        construction_root .. "Setup",
        "Setup",
        true
    ) then
        all_registered = false
    end
    return all_registered
end

update_construction_hotkey_guide = function(is_locked, show_transition_toast, hide_all)
    update_perfect_placement_ui(
        is_locked,
        show_transition_toast,
        hide_all
    )

    local ok, error_message = pcall(function()
        if is_locked then
            ensure_keyguide_hook()
        end
        local construction = cached_construction_widget
        if not is_live_object_of_exact_class(
            construction,
            CONSTRUCTION_WIDGET_CLASS_NAME
        ) then
            construction = FindFirstOf("WBP_IngameConstruction_C")
        end
        if not is_live_object_of_exact_class(
            construction,
            CONSTRUCTION_WIDGET_CLASS_NAME
        ) then
            construction = nil
            for _, candidate in ipairs(safe_find_all_of("WBP_IngameConstruction_C")) do
                if is_live_object_of_exact_class(
                    candidate,
                    CONSTRUCTION_WIDGET_CLASS_NAME
                ) then
                    construction = candidate
                    break
                end
            end
        end
        if not is_live_object_of_exact_class(
            construction,
            CONSTRUCTION_WIDGET_CLASS_NAME
        ) then
            log("Construction key-guide widget instance was not found.")
            return
        end
        cached_construction_widget = construction
        if Config.ui == nil or not Config.ui.use_native_construction_guide then
            return
        end
        if hide_all then
            construction_ui_hooks.__native_guide.hide(construction)
            set_native_locked_controls_hidden(construction, false)
        elseif is_locked then
            apply_locked_keyguide(construction)
        else
            hide_locked_keyguide(construction)
        end
        local model = construction.CachedModel
        if not is_valid(model) then
            model = FindFirstOf("PalUIBuildingModel")
        end
        if is_valid(model) then
            -- Let Palworld refresh its stock rows first. Native child creation
            -- and row detachment are deferred outside this Blueprint callback.
            construction:SetupKeyGuide(model)
            if hide_all then
                construction_ui_hooks.__native_guide.hide(construction)
                set_native_locked_controls_hidden(construction, false)
            elseif is_locked then
                apply_locked_keyguide(construction)
            else
                hide_locked_keyguide(construction)
            end
        else
            log("No live PalUIBuildingModel was found; skipped native guide rebuild.")
        end
    end)
    if not ok then
        log("Could not refresh construction hotkey guide: " .. tostring(error_message))
    end
end

local function cancel_begin_editing(transition_id, previous_state, reason)
    if preview_tick_was_enabled ~= nil then
        set_preview_tick_enabled(preview_tick_was_enabled ~= false)
    end
    if builder_tick_was_enabled ~= nil then
        set_builder_tick_enabled(builder_tick_was_enabled ~= false)
    end
    if is_valid(preview_root_component)
        and preview_root_previous_mobility ~= nil
    then
        pcall(function()
            preview_root_component:SetMobility(preview_root_previous_mobility)
        end)
    end

    builder_component = nil
    transform_actor = nil
    preview_actor = nil
    preview_root_component = nil
    preview_root_previous_mobility = nil
    preview_tick_was_enabled = nil
    builder_tick_was_enabled = nil
    locked_origin_location = nil
    locked_origin_rotation = nil
    last_preview_overlap_state = nil
    preview_relative_location = nil
    preview_relative_rotation = nil
    preserve_preview_origin_during_rotation = false
    desired_location = nil
    desired_rotation = nil
    validity_refresh_pending = false
    complete_freeze_transition(transition_id, previous_state)
    log("Could not freeze preview: " .. tostring(reason))
    return false
end

local function begin_editing(defer_initial_validity)
    -- Keybinds are global in UE4SS. Resolve only the local player's live build
    -- context here so MMB is a cheap no-op during normal gameplay.
    local active_component, active_checker, active_preview = find_active_build_context(false)
    if active_component == nil then
        return false
    end
    construction_ui_is_active(true)
    local previous_state = state
    local transition_id = begin_freeze_transition(State.FREEZING)

    builder_component = active_component
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
        return cancel_begin_editing(
            transition_id,
            previous_state,
            "the preview transform could not be read"
        )
    end
    preserve_preview_origin_during_rotation = false
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

        local horizontal_offset = math.sqrt(
            (preview_relative_location.X * preview_relative_location.X)
            + (preview_relative_location.Y * preview_relative_location.Y)
        )
        local snap_target_found = false
        local strategy_name = "<none>"
        pcall(function()
            local strategy = transform_actor.InstallStrategy
            if not is_valid(strategy) then
                return
            end
            strategy_name = full_name(strategy)
            for _, property_name in ipairs({
                "SnapHitBuildObjectCache",
                "SnapHitActorCache",
            }) do
                local property_ok, target = pcall(function()
                    return strategy[property_name]
                end)
                if property_ok and is_valid(target) then
                    snap_target_found = true
                    break
                end
            end
        end)
        local snap_mode_ok, snap_mode = pcall(function()
            return builder_component:IsSnapMode()
        end)
        local explicit_snap = snap_target_found or (snap_mode_ok and snap_mode == true)
        local inferred_structural_snap =
            horizontal_offset >= AUTOMATIC_SNAP_OFFSET_THRESHOLD_CM
        preserve_preview_origin_during_rotation = horizontal_offset > 0.01
            and (explicit_snap or inferred_structural_snap)
        if preserve_preview_origin_during_rotation then
            local detection = explicit_snap and "explicit" or "structural offset"
            log(string.format(
                "Snapped rotation will preserve preview origin (offset %.1f cm; detection %s; strategy %s).",
                horizontal_offset,
                detection,
                strategy_name
            ))
        end
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
    if not preserve_preview_origin_during_rotation then
        log(string.format(
            "Rotation anchored at Palworld install pivot (%.1f, %.1f, %.1f).",
            desired_location.X,
            desired_location.Y,
            desired_location.Z
        ))
    end
    last_preview_overlap_state = nil
    local tick_query_ok, tick_enabled = pcall(function()
        return preview_actor:IsActorTickEnabled()
    end)
    preview_tick_was_enabled = tick_query_ok and tick_enabled or true
    local preview_tick_suspended = preview_tick_was_enabled == false
        or set_preview_tick_enabled(false)
    if preview_tick_suspended then
        log("Preview actor tick suspended for frozen editing.")
    else
        return cancel_begin_editing(
            transition_id,
            previous_state,
            "the preview actor tick could not be suspended"
        )
    end

    if builder_component ~= nil then
        local builder_tick_query_ok, builder_tick_enabled = pcall(function()
            return builder_component:IsComponentTickEnabled()
        end)
        builder_tick_was_enabled = builder_tick_query_ok and builder_tick_enabled or true
        local builder_tick_suspended = builder_tick_was_enabled == false
            or set_builder_tick_enabled(false)
        if builder_tick_suspended then
            log("Player builder component tick suspended for frozen editing.")
        else
            return cancel_begin_editing(
                transition_id,
                previous_state,
                "the player builder component tick could not be suspended"
            )
        end
    else
        return cancel_begin_editing(
            transition_id,
            previous_state,
            "the local player's BuilderComponent became unavailable"
        )
    end

    state = State.EDITING
    update_construction_hotkey_guide(true)
    start_transform_loop()
    log(string.format(
        "Preview frozen. Move step %.1f cm; rotation step %.1f degrees.",
        current_move_step,
        Config.rotation.normal
    ))
    if defer_initial_validity then
        schedule_locked_validity_refresh()
    else
        refresh_locked_validity()
    end
    settle_freeze_transition(transition_id, State.EDITING)
    return true
end

release_preview = function(reason)
    if state ~= State.EDITING then
        return false
    end
    local transition_id = begin_freeze_transition(State.UNFREEZING)
    validity_refresh_pending = false
    local rendered_reason = tostring(reason)
    local show_unfreeze_toast = reason == "manual"
    local no_active_preview = reason == "preview object was destroyed"
        or reason == "Palworld cleared the build preview"
    local left_construction = reason == "Palworld exited building mode"
        or reason == "Palworld closed the construction UI"
        or reason == "builder component became invalid"
        or string.find(rendered_reason, "Palworld action:", 1, true) ~= nil
    update_construction_hotkey_guide(
        false,
        show_unfreeze_toast,
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
    locked_origin_location = nil
    locked_origin_rotation = nil
    last_preview_overlap_state = nil
    preview_relative_location = nil
    preview_relative_rotation = nil
    preserve_preview_origin_during_rotation = false
    desired_location = nil
    desired_rotation = nil
    log("Preview released to Palworld placement control.")
    settle_freeze_transition(transition_id, State.READY)
    if not (left_construction or no_active_preview) then
        runtime.delay(
            FREEZE_TRANSITION_SETTLE_MS + 50,
            function()
                if transition_id ~= freeze_transition_generation
                    or state ~= State.READY
                then
                    return
                end
                update_construction_hotkey_guide(false, false, false)
            end,
            "Post-unfreeze native guide refresh"
        )
    end
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
    if apply_preview_transform() then
        schedule_locked_validity_refresh()
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
    local preview_anchor_x = nil
    local preview_anchor_y = nil
    if preserve_preview_origin_during_rotation
        and preview_relative_location ~= nil
    then
        local previous_yaw = math.rad(desired_rotation.Yaw)
        preview_anchor_x = desired_location.X
            + (math.cos(previous_yaw) * preview_relative_location.X)
            - (math.sin(previous_yaw) * preview_relative_location.Y)
        preview_anchor_y = desired_location.Y
            + (math.sin(previous_yaw) * preview_relative_location.X)
            + (math.cos(previous_yaw) * preview_relative_location.Y)
    end

    desired_rotation.Yaw = desired_rotation.Yaw
        + (yaw_amount * (degrees_override or Config.rotation.normal))
    if preview_anchor_x ~= nil and preview_anchor_y ~= nil then
        local next_yaw = math.rad(desired_rotation.Yaw)
        desired_location.X = preview_anchor_x
            - (math.cos(next_yaw) * preview_relative_location.X)
            + (math.sin(next_yaw) * preview_relative_location.Y)
        desired_location.Y = preview_anchor_y
            - (math.sin(next_yaw) * preview_relative_location.X)
            - (math.cos(next_yaw) * preview_relative_location.Y)
    end

    if apply_preview_transform() then
        schedule_locked_validity_refresh()
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

    if apply_preview_transform() then
        schedule_locked_validity_refresh()
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
    if is_valid(cached_construction_widget) then
        construction_ui_hooks.__native_guide.refresh_move_step(
            cached_construction_widget
        )
    end
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

local function build_object_id_details(actor)
    local id_ok, build_object_id = pcall(function()
        return actor.BuildObjectId
    end)
    if not id_ok or build_object_id == nil or tostring(build_object_id) == "None" then
        return nil, nil
    end

    local name_ok, id_name = pcall(function()
        return build_object_id:ToString()
    end)
    if not name_ok or id_name == nil then
        return nil, nil
    end
    return build_object_id, tostring(id_name)
end

local function finite_number(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function snapshot_actor_transform(actor)
    local location = actor:K2_GetActorLocation()
    local rotation = actor:K2_GetActorRotation()
    if location == nil
        or rotation == nil
        or not finite_number(location.X)
        or not finite_number(location.Y)
        or not finite_number(location.Z)
        or not finite_number(rotation.Pitch)
        or not finite_number(rotation.Yaw)
        or not finite_number(rotation.Roll)
    then
        error("target build piece returned an invalid transform")
    end
    return {
        X = location.X,
        Y = location.Y,
        Z = location.Z,
    }, {
        Pitch = rotation.Pitch,
        Yaw = rotation.Yaw,
        Roll = rotation.Roll,
    }
end

local function capture_looked_at_build_piece()
    local component, active_checker, active_preview = find_active_build_context(false)
    if component == nil then
        error("no placement preview is active")
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
    local target_name = full_name(target)
    if target == active_preview or target_name == full_name(active_preview) then
        error("the cursor is pointing at the active placement preview")
    end
    local target_state_ok, target_state = pcall(function()
        return target.CurrentState
    end)
    if target_state_ok and target_state ~= nil then
        local rendered_target_state = tostring(target_state)
        if target_state == 1
            or string.find(rendered_target_state, "Simulation", 1, true) ~= nil
        then
            error("the cursor is pointing at a simulated placement preview")
        end
    end
    local build_object_id, build_object_id_name = build_object_id_details(target)
    if build_object_id == nil then
        error("target is not a copyable Pal build object: " .. target_name)
    end
    local active_build_object_id, active_build_object_id_name =
        build_object_id_details(active_preview)
    if active_build_object_id == nil then
        error("active preview does not expose a valid build object ID")
    end
    local target_location, target_rotation = snapshot_actor_transform(target)

    return {
        build_object_id = build_object_id,
        build_object_id_name = build_object_id_name,
        active_build_object_id_name = active_build_object_id_name,
        location = target_location,
        rotation = target_rotation,
        source_name = target_name,
        component = component,
        checker = active_checker,
        preview = active_preview,
    }
end

local function position_preview_at_captured_transform(checker, active_preview, source)
    if not is_valid(checker) or not is_valid(active_preview) then
        return false, "replacement preview context is invalid"
    end

    local rollback_transform = nil
    local ok, error_message = pcall(function()
        local checker_location = checker:K2_GetActorLocation()
        local checker_rotation = checker:K2_GetActorRotation()
        local active_preview_location = active_preview:K2_GetActorLocation()
        local active_preview_rotation = active_preview:K2_GetActorRotation()
        rollback_transform = {
            checker_location = {
                X = checker_location.X,
                Y = checker_location.Y,
                Z = checker_location.Z,
            },
            checker_rotation = {
                Pitch = checker_rotation.Pitch,
                Yaw = checker_rotation.Yaw,
                Roll = checker_rotation.Roll,
            },
            preview_location = {
                X = active_preview_location.X,
                Y = active_preview_location.Y,
                Z = active_preview_location.Z,
            },
            preview_rotation = {
                Pitch = active_preview_rotation.Pitch,
                Yaw = active_preview_rotation.Yaw,
                Roll = active_preview_rotation.Roll,
            },
        }

        local offset_x = active_preview_location.X - checker_location.X
        local offset_y = active_preview_location.Y - checker_location.Y
        local checker_yaw = math.rad(checker_rotation.Yaw)
        local relative_location = {
            X = (math.cos(checker_yaw) * offset_x)
                + (math.sin(checker_yaw) * offset_y),
            Y = (-math.sin(checker_yaw) * offset_x)
                + (math.cos(checker_yaw) * offset_y),
            Z = active_preview_location.Z - checker_location.Z,
        }
        local relative_rotation = {
            Pitch = active_preview_rotation.Pitch - checker_rotation.Pitch,
            Yaw = active_preview_rotation.Yaw - checker_rotation.Yaw,
            Roll = active_preview_rotation.Roll - checker_rotation.Roll,
        }

        local target_checker_rotation = {
            Pitch = source.rotation.Pitch - relative_rotation.Pitch,
            Yaw = source.rotation.Yaw - relative_rotation.Yaw,
            Roll = source.rotation.Roll - relative_rotation.Roll,
        }
        local target_checker_yaw = math.rad(target_checker_rotation.Yaw)
        local rotated_offset_x =
            (math.cos(target_checker_yaw) * relative_location.X)
            - (math.sin(target_checker_yaw) * relative_location.Y)
        local rotated_offset_y =
            (math.sin(target_checker_yaw) * relative_location.X)
            + (math.cos(target_checker_yaw) * relative_location.Y)
        local target_checker_location = {
            X = source.location.X - rotated_offset_x,
            Y = source.location.Y - rotated_offset_y,
            Z = source.location.Z - relative_location.Z,
        }

        checker:K2_SetActorLocationAndRotation(
            target_checker_location,
            target_checker_rotation,
            false,
            {},
            true
        )
        active_preview:K2_SetActorLocationAndRotation(
            source.location,
            source.rotation,
            false,
            {},
            true
        )
    end)
    if not ok then
        if rollback_transform ~= nil then
            pcall(function()
                checker:K2_SetActorLocationAndRotation(
                    rollback_transform.checker_location,
                    rollback_transform.checker_rotation,
                    false,
                    {},
                    true
                )
                active_preview:K2_SetActorLocationAndRotation(
                    rollback_transform.preview_location,
                    rollback_transform.preview_rotation,
                    false,
                    {},
                    true
                )
            end)
        end
        return false, tostring(error_message)
    end
    return true
end

local function abort_piece_switch(transition_id, message)
    if transition_id ~= freeze_transition_generation
        or state ~= State.SWITCHING
    then
        return
    end
    log("Build-piece switch failed: " .. tostring(message))
    preview_actor = nil
    complete_freeze_transition(transition_id, State.SEARCHING)
end

local queue_piece_switch_poll

local function finish_piece_switch(
    transition_id,
    source,
    freeze_after_switch,
    component,
    checker,
    active_preview
)
    if freeze_after_switch then
        local positioned, position_error =
            position_preview_at_captured_transform(checker, active_preview, source)
        if not positioned then
            abort_piece_switch(transition_id, position_error)
            return
        end

        -- The preview is now at the captured world transform. End the switch
        -- transaction and immediately start the normal freeze transaction in
        -- this same game-thread callback, leaving no input-visible gap.
        complete_freeze_transition(transition_id, State.READY)
        local freeze_ok, frozen_or_error = pcall(begin_editing, true)
        if freeze_ok and frozen_or_error then
            log("Copied and froze preview to " .. source.source_name .. ".")
        else
            if not freeze_ok then
                log("Copy-and-freeze transition failed: " .. tostring(frozen_or_error))
                if state == State.EDITING then
                    pcall(release_preview, "copy-and-freeze transition failed")
                elseif state == State.FREEZING then
                    cancel_begin_editing(
                        freeze_transition_generation,
                        State.READY,
                        "copy-and-freeze raised an unexpected transition error"
                    )
                end
            end
            log("Copied the targeted piece, but its replacement preview could not be frozen.")
        end
        return
    end

    cached_builder_component = component
    preview_actor = active_preview
    complete_freeze_transition(transition_id, State.READY)
    log("Copied build preview from " .. source.source_name .. ".")
end

queue_piece_switch_poll = function(
    transition_id,
    source,
    freeze_after_switch,
    attempt,
    stable_preview_name
)
    local current_attempt = attempt
    local current_stable_preview_name = stable_preview_name
    local cancel = runtime.loop(
        FREEZE_TO_PIECE_RETRY_MS,
        function()
            if transition_id ~= freeze_transition_generation
                or state ~= State.SWITCHING
            then
                return true
            end

            local ok, error_message = pcall(function()
                current_attempt = current_attempt + 1
                local component, checker, active_preview =
                    find_active_build_context(false)
                local _, active_id_name = build_object_id_details(active_preview)
                local current_preview_name = is_valid(active_preview)
                    and full_name(active_preview)
                    or nil
                local expected_preview_is_ready = component ~= nil
                    and active_id_name == source.build_object_id_name
                    and current_preview_name ~= nil

                if expected_preview_is_ready
                    and current_preview_name == current_stable_preview_name
                then
                    finish_piece_switch(
                        transition_id,
                        source,
                        freeze_after_switch,
                        component,
                        checker,
                        active_preview
                    )
                    return true
                end

                if current_attempt >= FREEZE_TO_PIECE_MAX_ATTEMPTS then
                    abort_piece_switch(
                        transition_id,
                        "replacement preview did not become ready within "
                            .. tostring(
                                FREEZE_TO_PIECE_RETRY_MS
                                    * FREEZE_TO_PIECE_MAX_ATTEMPTS
                            )
                            .. " ms"
                    )
                    return true
                end

                current_stable_preview_name =
                    expected_preview_is_ready and current_preview_name or nil
                return false
            end)
            if not ok then
                abort_piece_switch(transition_id, error_message)
                return true
            end
            return error_message == true
        end,
        "Build-piece switch readiness check"
    )
    if cancel == nil then
        abort_piece_switch(transition_id, "could not queue the readiness check")
    end
end

local function switch_to_captured_build_piece(source, freeze_after_switch)
    local transition_id = begin_freeze_transition(State.SWITCHING)
    local mode_label = freeze_after_switch and "copy-and-freeze" or "eyedropper"
    log(string.format(
        "Starting %s switch to %s.",
        mode_label,
        source.source_name
    ))

    local finish_ok, finish_error = pcall(function()
        local building_model = FindFirstOf("PalUIBuildingModel")
        if is_valid(building_model) then
            building_model:FinishBuilding()
        end
    end)
    if not finish_ok then
        abort_piece_switch(transition_id, finish_error)
        return
    end

    preview_actor = nil
    local queued = runtime.delay(
        1,
        function()
            if transition_id ~= freeze_transition_generation
                or state ~= State.SWITCHING
            then
                return
            end

            local ok, error_message = pcall(function()
                local ui_model = FindFirstOf("PalUIBuildModel")
                if not is_valid(ui_model) then
                    ui_model = FindFirstOf("BP_PalUIBuildModel_C")
                end
                if not is_valid(ui_model) then
                    error("build-menu model did not become available")
                end
                ui_model:StartBuildObject(source.build_object_id)
                queue_piece_switch_poll(
                    transition_id,
                    source,
                    freeze_after_switch,
                    0,
                    nil
                )
            end)
            if not ok then
                abort_piece_switch(transition_id, error_message)
            end
        end,
        "Build-piece selection handoff",
        function()
            abort_piece_switch(
                transition_id,
                "could not enter the game thread for the selection handoff"
            )
        end
    )
    if not queued then
        abort_piece_switch(transition_id, "could not queue the selection handoff")
    end
end

local function capture_piece_for_action(action_label)
    local ok, source_or_error = pcall(capture_looked_at_build_piece)
    if not ok then
        log(string.format(
            "%s failed: %s.",
            action_label,
            tostring(source_or_error)
        ))
        return nil
    end
    return source_or_error
end

local function copy_looked_at_build_piece()
    if freeze_transition_input_locked
        or state == State.SWITCHING
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

    local source = capture_piece_for_action("Eyedropper")
    if source == nil then
        return
    end
    if source.build_object_id_name == source.active_build_object_id_name then
        log("Eyedropper ignored: looked-at piece already matches the active preview.")
        return
    end
    source.component = nil
    source.checker = nil
    source.preview = nil
    switch_to_captured_build_piece(source, false)
end

local function freeze_to_looked_at_build_piece()
    if freeze_transition_input_locked
        or state == State.SWITCHING
        or state == State.FREEZING
        or state == State.UNFREEZING
    then
        verbose("Copy-and-freeze ignored while placement state settles.")
        return
    end
    if state == State.EDITING then
        log("Copy-and-freeze ignored while the preview is already frozen.")
        return
    end

    local source = capture_piece_for_action("Copy-and-freeze")
    if source == nil then
        return
    end
    if source.build_object_id_name == source.active_build_object_id_name then
        local transition_id = begin_freeze_transition(State.SWITCHING)
        finish_piece_switch(
            transition_id,
            source,
            true,
            source.component,
            source.checker,
            source.preview
        )
        return
    end
    source.component = nil
    source.checker = nil
    source.preview = nil
    switch_to_captured_build_piece(source, true)
end

local function input_transition_is_locked()
    return
        freeze_transition_input_locked
        or state == State.FREEZING
        or state == State.UNFREEZING
        or state == State.SWITCHING
end

local function invoke_guarded_input(
    callback,
    source,
    queued_generation,
    queued_during_transition
)
    if queued_during_transition
        or queued_generation ~= freeze_transition_generation
    then
        verbose("Discarded stale queued "
            .. tostring(source or "input")
            .. " after a placement transition.")
        return false
    end
    callback()
    return true
end

local function queue_input_callback(callback, source)
    local queued_generation = freeze_transition_generation
    local queued_during_transition = input_transition_is_locked()
    return runtime.execute(function()
        invoke_guarded_input(
            callback,
            source,
            queued_generation,
            queued_during_transition
        )
    end, tostring(source or "Input") .. " game-thread callback")
end

local function register_chord(key, modifiers, callback)
    local ok, error_message = pcall(function()
        local queued_generation = freeze_transition_generation
        local queued_during_transition = false
        local pulse_callback = function()
            invoke_guarded_input(
                callback,
                "Keyboard input",
                queued_generation,
                queued_during_transition
            )
        end
        local trigger = runtime.pulse(
            pulse_callback,
            string.format("Keyboard input 0x%X", key)
        )
        if type(trigger) ~= "function" then
            error("could not create a stable game-thread input pulse")
        end
        local queued_callback = function()
            queued_generation = freeze_transition_generation
            queued_during_transition = input_transition_is_locked()
            trigger()
        end
        if modifiers == nil or #modifiers == 0 then
            RegisterKeyBind(key, queued_callback)
        else
            RegisterKeyBind(key, modifiers, queued_callback)
        end
        registered_keybind_callbacks[#registered_keybind_callbacks + 1] =
            queued_callback
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

dispatch_action = function(action, source)
    local callback = action_callbacks[action]
    if type(callback) ~= "function" then
        verbose("Ignored unknown "
            .. tostring(source or "input")
            .. " action: "
            .. tostring(action))
        return false
    end
    if type(IsInGameThread) == "function" then
        local thread_ok, on_game_thread = pcall(IsInGameThread)
        if thread_ok and on_game_thread == true then
            return invoke_guarded_input(
                callback,
                tostring(source or "Input") .. " action " .. tostring(action),
                freeze_transition_generation,
                input_transition_is_locked()
            )
        end
    end
    return queue_input_callback(
        callback,
        tostring(source or "Input") .. " action " .. tostring(action)
    )
end

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

    -- Windows does not report Shift + Numpad keys as Shift-bearing keypad
    -- events. It emits the matching navigation key while Shift is temporarily
    -- absent, so register that translated chord as well.
    local shifted_keypad =
        Keybindings.get_shifted_keypad_registration(binding)
    if shifted_keypad ~= nil then
        local translated_modifier_values = {}
        for _, modifier_name in ipairs(shifted_keypad.modifiers) do
            translated_modifier_values[#translated_modifier_values + 1] =
                MODIFIER_VALUES[modifier_name]
        end
        local registration_signature = tostring(shifted_keypad.virtual_key)
            .. ":WINDOWS_SHIFT_KEYPAD:"
            .. table.concat(shifted_keypad.modifiers, "+")
        if not registered_action_chords[action][registration_signature] then
            local captured_key = binding.key
            local captured_modifiers = {}
            for index, value in ipairs(binding.modifiers) do
                captured_modifiers[index] = value
            end
            register_chord(
                shifted_keypad.virtual_key,
                translated_modifier_values,
                function()
                    local current = resolved_bindings[action]
                    if current ~= nil
                        and not current.disabled
                        and current.key == captured_key
                        and same_modifier_names(
                            current.modifiers,
                            captured_modifiers
                        )
                    then
                        action_callbacks[action]()
                    end
                end
            )
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
register_action("freeze_to_piece", freeze_to_looked_at_build_piece)

gamepad_feature = GamepadFeature.new({
    config = Config,
    log = log,
    is_valid = is_valid,
    dispatch_action = dispatch_action,
    enabled_property = (Config.ui or {}).gamepad_enabled_property
        or "GamepadEnabled",
    load_keycap_texture = load_keycap_texture,
    ue_helpers = UEHelpers,
    delay = function(milliseconds, callback, label)
        return runtime.delay(milliseconds, callback, label)
    end,
    get_host = function()
        return perfect_placement_ui_host
    end,
})

-- Called synchronously by the isolated native XInput bridge. The bridge only
-- forwards buttons that Palworld consumes before Blueprint input dispatch.
_G.PerfectPlacementNativeGamepadPhysical = function(index)
    if gamepad_feature == nil then
        return false
    end
    return gamepad_feature:dispatch_native_physical(index)
end
_G.PerfectPlacementNativeInputDevice = function(_using_gamepad)
    if gamepad_feature == nil then
        return false
    end
    -- Raw-input packets can be synthetic or carry no physical mouse movement.
    -- Palworld filters those before updating CommonInputSubsystem, so never let
    -- the native packet classification override the game's authoritative state.
    -- Queue one game-thread turn so Palworld can commit a meaningful device
    -- transition before the custom and companion guides are synchronized.
    return runtime.execute(function()
        local guide = construction_ui_hooks.__native_guide
        local gamepad_active = guide.is_gamepad_active()
        gamepad_feature:set_using_gamepad(gamepad_active)
        if Config.ui ~= nil
            and Config.ui.use_native_construction_guide == true
            and is_valid(cached_construction_widget)
        then
            guide.show(cached_construction_widget, state == State.EDITING)
        end
    end, "Palworld input-device guide sync")
end
local UI_HOST_CLASS_PATH =
    "/Game/Mods/PerfectPlacement/WBP_PerfectPlacement_KeyGuide"
    .. ".WBP_PerfectPlacement_KeyGuide_C"

ui_host_notify_callback = function(new_object)
    count_ui_lifecycle_metric("host_notify")
    ui_host_lookup_blocked = false
    ui_host_missing_was_logged = false
    if new_object ~= nil then
        local notified_name = live_companion_ui_host_name(new_object)
        if notified_name ~= nil then
            preferred_ui_host_full_name = notified_name
        end
        ui_host_fault_retry_allowed = true
    end
    -- Invalidate the local fast path immediately. Repeated Setup callbacks are
    -- suppressed while the coalesced reacquisition is pending.
    perfect_placement_ui_mode = nil
    if ui_host_setup_pending then
        count_ui_lifecycle_metric("host_notify_coalesced")
        return
    end
    ui_host_setup_pending = true
    local queued = runtime.delay(
        250,
        function()
            ui_host_setup_pending = false
            ensure_keyguide_hook()
            ensure_construction_ui_hooks()
            -- Treat NotifyOnNewObject only as a wake-up signal. Reacquiring on
            -- the game thread avoids retaining a UObject wrapper across a map
            -- transition and delayed callback.
            if gamepad_feature ~= nil then
                gamepad_feature:detach_host()
            end
            perfect_placement_ui_host = nil
            perfect_placement_ui_mode = nil
            keycap_ui_host = nil
            local host = find_perfect_placement_ui_host()
            if not is_valid(host) then
                return
            end

            ui_host_missing_was_logged = false
            cached_builder_component = nil
            -- ModActor also creates this host on the main menu. Never infer
            -- construction mode from host creation alone; require the local
            -- player's live BuilderComponent preview before showing the guide.
            local active_component, active_checker, active_preview =
                find_active_build_context(false)
            local live_frozen = state == State.EDITING
                and is_valid(builder_component)
                and is_valid(preview_actor)
            local live_unfrozen = is_valid(active_component)
                and is_valid(active_checker)
                and is_valid(active_preview)
                and construction_ui_is_active(false) == true
            if live_unfrozen
                and Config.ui ~= nil
                and Config.ui.use_native_construction_guide == true
                and is_valid(cached_construction_widget)
            then
                hide_locked_keyguide(cached_construction_widget)
            end
            update_perfect_placement_ui(
                live_frozen,
                false,
                not (live_frozen or live_unfrozen)
            )
        end,
        "Companion UI host setup",
        function()
            ui_host_setup_pending = false
        end
    )
    if not queued then
        ui_host_setup_pending = false
    end
end

construction_ui_notify_callback = function(construction)
    construction_ui_generation = construction_ui_generation + 1
    count_ui_lifecycle_metric("construction_notify")
    if is_live_object_of_exact_class(
        construction,
        CONSTRUCTION_WIDGET_CLASS_NAME
    ) then
        cached_construction_widget = construction
        local construction_name = full_name(construction)
        construction_ui_hooks.__native_guide.instances[construction_name] = nil
        construction_ui_hooks.__native_guide.detached_stock_rows[
            construction_name
        ] = nil
        construction_ui_hooks.__native_guide.stock_layout_requests[
            construction_name
        ] = nil
        construction_ui_hooks.__native_guide.stock_layout_modes[
            construction_name
        ] = nil
    end
    ensure_keyguide_hook()
    ensure_construction_ui_hooks()
    if not is_live_companion_ui_host(perfect_placement_ui_host)
        and not ui_host_setup_pending
    then
        -- A construction lifecycle wake-up is the recovery path when the
        -- companion notification was missed. Do not pin discovery to an
        -- identity that has already disappeared.
        preferred_ui_host_full_name = nil
        ui_host_notify_callback()
    end
end

do
    local construction_notify_ok, construction_notify_error = pcall(
        NotifyOnNewObject,
        "/Game/Pal/Blueprint/UI/UserInterface/InGame/Construction/"
            .. "WBP_IngameConstruction.WBP_IngameConstruction_C",
        construction_ui_notify_callback
    )
    if not construction_notify_ok then
        log("Could not register construction UI lifecycle notification: "
            .. tostring(construction_notify_error))
    end
end

do
    local ui_notify_ok, ui_notify_error = pcall(
        NotifyOnNewObject,
        UI_HOST_CLASS_PATH,
        ui_host_notify_callback
    )
    if not ui_notify_ok then
        log("Could not register companion UI lifecycle notification: "
            .. tostring(ui_notify_error))
    end
end

ensure_keyguide_hook()
ensure_construction_ui_hooks()

gamepad_feature:start()

log("Loaded Perfect Placement 0.3.0-rc.1")
log("Bundled native gamepad bridge and construction UI revision 1 loaded.")
log("Open build mode, show a preview, then middle-click to freeze it.")
