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
    WAITING_FOR_PREVIEW = "waiting_for_preview",
}

local state = State.SEARCHING
local preview_actor = nil
local transform_actor = nil
local preview_root_component = nil
local preview_root_previous_mobility = nil
local desired_location = nil
local desired_rotation = nil
local current_move_step = Config.movement.normal
local transform_loop_started = false
local transform_loop_callback = nil
local transform_game_thread_callback = nil
local transform_direct_loop_callback = nil
local transform_check_pending = false
local transform_loop_error_was_logged = false
local preview_tick_was_enabled = nil
local builder_component = nil
local cached_builder_component = nil
local builder_tick_was_enabled = nil
local lifecycle_monitor_started = false
local lifecycle_recovery_checks_remaining = 0
local lifecycle_check_pending = false
local lifecycle_monitor_loop_callback = nil
local lifecycle_game_thread_callback = nil
local lifecycle_direct_loop_callback = nil
local lifecycle_monitor_error_was_logged = false
local lifecycle_suppression_idle_ticks = 0
local builder_fallback_scan_cooldown = 0
local construction_guide_mode = nil
local building_mode_exit_checks = 0
local unfrozen_ui_builder_component = nil
local unfrozen_ui_preview_visible = nil
local unfrozen_ui_suppressed_preview_name = nil
local unfrozen_ui_suppression_saw_inactive = false
local notification_generation = 0
local locked_preview_name = nil
local release_preview
local update_construction_hotkey_guide
local ensure_auto_unfreeze_hooks
local start_lifecycle_monitor
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
local gamepad_monitor_started = false
local gamepad_serial_host_name = nil
local gamepad_last_serials = {}
local active_gamepad_physical_serials = nil
local gamepad_monitor_loop_callback = nil
local gamepad_game_thread_callback = nil
local gamepad_direct_loop_callback = nil
local gamepad_poll_pending = false
local gamepad_monitor_error_was_logged = false
local resolved_gamepad_bindings = nil
local resolved_gamepad_chord_actions = nil
local auto_unfreeze_hooked_paths = {}
local construction_ui_notify_callback = nil
local ui_host_notify_callback = nil
local ui_host_refresh_generation = 0
local ui_host_refresh_pending = false
local retained_async_callbacks = {}
local retained_async_callback_serial = 0

local LIFECYCLE_INTERVAL_MS = 100
local LIFECYCLE_INITIAL_RECOVERY_CHECKS = 100
local LIFECYCLE_EVENT_RECOVERY_CHECKS = 20
local LIFECYCLE_SUPPRESSION_FALLBACK_TICKS = 10
local BUILDER_FALLBACK_RETRY_TICKS = 10
local FREEZE_TRANSITION_SETTLE_MS = 500
local PAL_BUILDING_FUNCTION_ROOT =
    "/Game/Pal/Blueprint/UI/BuildMenu/WBP_PalBuilding"
    .. ".WBP_PalBuilding_C:"
local PAL_INPUT_LISTENER_FUNCTION_ROOT =
    "/Game/Pal/Blueprint/UI/WBP_PalHUD_InGame_InputListener"
    .. ".WBP_PalHUD_InGame_InputListener_C:"
local PAL_INGAME_CONSTRUCTION_CLASS_PATH =
    "/Game/Pal/Blueprint/UI/UserInterface/InGame/Construction/"
    .. "WBP_IngameConstruction.WBP_IngameConstruction_C"
local PAL_INGAME_CONSTRUCTION_FUNCTION_ROOT =
    PAL_INGAME_CONSTRUCTION_CLASS_PATH .. ":"

local function log(message)
    print(string.format("[%s] %s\n", MOD, message))
end

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

local function execute_with_retained_delay(delay_ms, callback, label)
    local retained_callback, callback_id =
        retain_async_callback(callback, label)
    local ok, error_message = pcall(
        ExecuteWithDelay,
        delay_ms,
        retained_callback
    )
    if not ok then
        retained_async_callbacks[callback_id] = nil
        log(string.format(
            "Could not queue %s: %s",
            label or "delayed callback",
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
    if type(ExecuteInGameThreadWithDelay) == "function" then
        local retained_callback, callback_id =
            retain_async_callback(callback, label)
        local ok, error_message = pcall(
            ExecuteInGameThreadWithDelay,
            delay_ms,
            retained_callback
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

    return execute_with_retained_delay(delay_ms, function()
        execute_in_game_thread_retained(callback, label)
    end, label)
end

local function start_repeating_game_thread_action(
    delay_ms,
    callback,
    label
)
    if type(ExecuteInGameThreadWithDelay) ~= "function" then
        return nil
    end

    local scheduled_callback
    scheduled_callback = function()
        local callback_ok, callback_error = pcall(callback)
        if not callback_ok then
            log(string.format(
                "%s failed: %s",
                label or "Repeating game-thread callback",
                tostring(callback_error)
            ))
        end

        if not execute_in_game_thread_with_retained_delay(
            delay_ms,
            scheduled_callback,
            label
        ) then
            log(string.format(
                "%s stopped because its next pass could not be queued.",
                label or "Repeating game-thread callback"
            ))
        end
    end

    if not execute_in_game_thread_with_retained_delay(
        delay_ms,
        scheduled_callback,
        label
    ) then
        return nil
    end
    return scheduled_callback
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

local function settle_freeze_transition(
    transition_id,
    stable_state
)
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

local GAMEPAD_STATE_ACTION_ORDER = {
    unfrozen = {
        "toggle_freeze",
        "copy_piece",
    },
    frozen = {
        "move_left",
        "move_right",
        "move_forward",
        "move_back",
        "move_up",
        "move_down",
        "rotate_left",
        "rotate_right",
        "step_down",
        "step_up",
        "reset",
        "toggle_freeze",
    },
}

local GAMEPAD_MODIFIER_ORDER = {
    L3 = 1,
    LT = 2,
    RT = 3,
}

local GAMEPAD_SUPPORTED_CHORDS = {
    unfrozen = {
        L3 = true,
        ["L3+DPAD_DOWN"] = true,
    },
    frozen = {
        DPAD_UP = true,
        DPAD_DOWN = true,
        DPAD_LEFT = true,
        DPAD_RIGHT = true,
        ["LT+DPAD_UP"] = true,
        ["LT+DPAD_DOWN"] = true,
        ["LT+DPAD_LEFT"] = true,
        ["LT+DPAD_RIGHT"] = true,
        ["RT+DPAD_UP"] = true,
        ["RT+DPAD_DOWN"] = true,
        ["RT+DPAD_LEFT"] = true,
        ["RT+DPAD_RIGHT"] = true,
        ["LT+RT+DPAD_UP"] = true,
        ["LT+RT+DPAD_DOWN"] = true,
        ["LT+RT+DPAD_LEFT"] = true,
        ["LT+RT+DPAD_RIGHT"] = true,
        LB = true,
        RB = true,
        R3 = true,
        L3 = true,
    },
}

local function normalize_gamepad_token(value)
    if type(value) ~= "string" then
        return nil
    end
    local token = string.upper(value)
    token = string.gsub(token, "[%s%-]+", "_")
    if token == "DPADUP" then
        return "DPAD_UP"
    elseif token == "DPADDOWN" then
        return "DPAD_DOWN"
    elseif token == "DPADLEFT" then
        return "DPAD_LEFT"
    elseif token == "DPADRIGHT" then
        return "DPAD_RIGHT"
    end
    return token
end

local function normalize_gamepad_binding(binding)
    local key = binding
    local modifiers = {}
    if type(binding) == "table" then
        if binding.disabled then
            return nil, "binding is disabled"
        end
        key = binding.key
        if type(binding.modifiers) == "table" then
            for _, modifier in ipairs(binding.modifiers) do
                modifiers[#modifiers + 1] = modifier
            end
        end
    end

    key = normalize_gamepad_token(key)
    if key == nil or key == "" then
        return nil, "missing key"
    end

    local normalized_modifiers = {}
    local seen = {}
    for _, modifier in ipairs(modifiers) do
        local normalized = normalize_gamepad_token(modifier)
        if GAMEPAD_MODIFIER_ORDER[normalized] == nil then
            return nil, "unsupported modifier " .. tostring(modifier)
        end
        if not seen[normalized] then
            seen[normalized] = true
            normalized_modifiers[#normalized_modifiers + 1] = normalized
        end
    end
    table.sort(normalized_modifiers, function(left, right)
        return GAMEPAD_MODIFIER_ORDER[left] < GAMEPAD_MODIFIER_ORDER[right]
    end)

    local chord_parts = {}
    for _, modifier in ipairs(normalized_modifiers) do
        chord_parts[#chord_parts + 1] = modifier
    end
    chord_parts[#chord_parts + 1] = key
    return {
        key = key,
        modifiers = normalized_modifiers,
        chord = table.concat(chord_parts, "+"),
    }
end

local function configured_gamepad_action(action)
    local gamepad = Config.gamepad or {}
    if gamepad.invert_forward_back then
        if action == "move_forward" then
            return "move_back"
        elseif action == "move_back" then
            return "move_forward"
        end
    end
    if gamepad.invert_height then
        if action == "move_up" then
            return "move_down"
        elseif action == "move_down" then
            return "move_up"
        end
    end
    if gamepad.swap_rotate_buttons then
        if action == "rotate_left" then
            return "rotate_right"
        elseif action == "rotate_right" then
            return "rotate_left"
        end
    end
    return action
end

local function load_resolved_gamepad_bindings()
    local gamepad = Config.gamepad or {}
    local configured_states = gamepad.bindings or {}
    local resolved = {
        unfrozen = {},
        frozen = {},
    }
    local chord_actions = {
        unfrozen = {},
        frozen = {},
    }

    for state_name, action_order in pairs(GAMEPAD_STATE_ACTION_ORDER) do
        local configured = configured_states[state_name] or {}
        local supported = GAMEPAD_SUPPORTED_CHORDS[state_name]
        for _, action in ipairs(action_order) do
            local binding, binding_error =
                normalize_gamepad_binding(configured[action])
            if binding == nil then
                log(string.format(
                    "Gamepad binding %s.%s ignored: %s.",
                    state_name,
                    action,
                    binding_error
                ))
            elseif not supported[binding.chord] then
                log(string.format(
                    "Gamepad binding %s.%s ignored: chord %s is not captured in %s mode.",
                    state_name,
                    action,
                    binding.chord,
                    state_name
                ))
            elseif chord_actions[state_name][binding.chord] ~= nil then
                log(string.format(
                    "Gamepad binding %s.%s ignored: chord %s is already assigned to %s.",
                    state_name,
                    action,
                    binding.chord,
                    chord_actions[state_name][binding.chord]
                ))
            else
                local effective_action = configured_gamepad_action(action)
                resolved[state_name][effective_action] = binding
                chord_actions[state_name][binding.chord] = effective_action
            end
        end
    end
    return resolved, chord_actions
end

resolved_gamepad_bindings, resolved_gamepad_chord_actions =
    load_resolved_gamepad_bindings()

local function verbose(message)
    if Config.diagnostics.verbose then
        log(message)
    end
end

local function request_lifecycle_recovery(check_count)
    local requested = math.max(1, math.floor(
        tonumber(check_count) or LIFECYCLE_EVENT_RECOVERY_CHECKS
    ))
    lifecycle_recovery_checks_remaining = math.max(
        lifecycle_recovery_checks_remaining,
        requested
    )
    if start_lifecycle_monitor ~= nil
        and not lifecycle_monitor_started
    then
        start_lifecycle_monitor()
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

local GAMEPAD_KEYGUIDE_ROOT = "/Game/Pal/Texture/UI/KeyGuide/"

local function gamepad_keyguide_asset(asset_name)
    local texture_path = GAMEPAD_KEYGUIDE_ROOT .. asset_name
    return {
        texture_path = texture_path,
        texture_object_path = texture_path .. "." .. asset_name,
    }
end

local GAMEPAD_KEYCAP_ASSETS = {
    DPAD_UP = "T_KeyGuide_CrossU",
    DPAD_DOWN = "T_KeyGuide_CrossD",
    DPAD_LEFT = "T_KeyGuide_CrossL",
    DPAD_RIGHT = "T_KeyGuide_CrossR",
    LB = "T_KeyGuide_L1",
    LT = "T_KeyGuide_L2",
    L3 = "T_KeyGuide_L3",
    RB = "T_KeyGuide_R1",
    RT = "T_KeyGuide_R2",
    R3 = "T_KeyGuide_R3",
}

-- Preferred gamepad contract. Each parent property is an instance of
-- WBP_PerfectPlacement_GamepadChord. Lua updates its named child widgets
-- directly because cooked Blueprint function arguments are not reliable in
-- the current Palworld/UE4SS combination.
local GAMEPAD_CHORD_WIDGET_SLOTS = {
    unfrozen = {
        toggle_freeze = "GP_UnfrozenToggleFreezeChord",
        copy_piece = "GP_UnfrozenCopyChord",
    },
    frozen = {
        move_left = "GP_FrozenMoveLeftChord",
        move_right = "GP_FrozenMoveRightChord",
        move_forward = "GP_FrozenMoveForwardChord",
        move_back = "GP_FrozenMoveBackChord",
        move_up = "GP_FrozenMoveUpChord",
        move_down = "GP_FrozenMoveDownChord",
        rotate_left = "GP_FrozenRotateLeftChord",
        rotate_right = "GP_FrozenRotateRightChord",
        step_down = "GP_FrozenStepDownChord",
        step_up = "GP_FrozenStepUpChord",
        reset = "GP_FrozenResetChord",
        toggle_freeze = "GP_FrozenToggleFreezeChord",
    },
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

local function set_gamepad_chord_widget(host, property_name, binding)
    local widget_ok, widget = pcall(function()
        return host[property_name]
    end)
    if not widget_ok or not is_valid(widget) then
        log("Companion gamepad chord widget is missing: " .. property_name)
        return false
    end

    local direct_ok, direct_error = pcall(function()
        local modifier1_box = widget.Modifier1Box
        local modifier1_icon = widget.Modifier1Icon
        local modifier1_separator = widget.Modifier1Separator
        local modifier2_box = widget.Modifier2Box
        local modifier2_icon = widget.Modifier2Icon
        local modifier2_separator = widget.Modifier2Separator
        local primary_box = widget.PrimaryBox
        local primary_icon = widget.PrimaryIcon

        if not is_valid(modifier1_box)
            or not is_valid(modifier1_icon)
            or not is_valid(modifier1_separator)
            or not is_valid(modifier2_box)
            or not is_valid(modifier2_icon)
            or not is_valid(modifier2_separator)
            or not is_valid(primary_box)
            or not is_valid(primary_icon)
        then
            error("one or more gamepad chord child widgets are missing")
        end

        for _, keycap_box in ipairs({
            modifier1_box,
            modifier2_box,
            primary_box,
        }) do
            keycap_box:SetWidthOverride(32.0)
            keycap_box:SetHeightOverride(32.0)
        end

        local modifier_count =
            binding ~= nil and #binding.modifiers or 0
        local modifier1_texture = nil
        local modifier2_texture = nil
        local primary_texture = nil

        if modifier_count >= 1 then
            local asset_name = GAMEPAD_KEYCAP_ASSETS[binding.modifiers[1]]
            if asset_name ~= nil then
                modifier1_texture =
                    load_keycap_texture(gamepad_keyguide_asset(asset_name))
            end
        end
        if modifier_count >= 2 then
            local asset_name = GAMEPAD_KEYCAP_ASSETS[binding.modifiers[2]]
            if asset_name ~= nil then
                modifier2_texture =
                    load_keycap_texture(gamepad_keyguide_asset(asset_name))
            end
        end
        if binding ~= nil then
            local asset_name = GAMEPAD_KEYCAP_ASSETS[binding.key]
            if asset_name ~= nil then
                primary_texture =
                    load_keycap_texture(gamepad_keyguide_asset(asset_name))
            end
        end

        local show_modifier1 = is_valid(modifier1_texture)
        local show_modifier2 = is_valid(modifier2_texture)
        local show_primary = is_valid(primary_texture)

        if show_modifier1 then
            modifier1_icon:SetBrushFromTexture(modifier1_texture, false)
        end
        if show_modifier2 then
            modifier2_icon:SetBrushFromTexture(modifier2_texture, false)
        end
        if show_primary then
            primary_icon:SetBrushFromTexture(primary_texture, false)
        end

        modifier1_box:SetVisibility(show_modifier1 and 0 or 1)
        modifier1_separator:SetVisibility(show_modifier1 and 0 or 1)
        modifier2_box:SetVisibility(show_modifier2 and 0 or 1)
        modifier2_separator:SetVisibility(show_modifier2 and 0 or 1)
        primary_box:SetVisibility(show_primary and 0 or 1)
    end)
    if not direct_ok then
        log(string.format(
            "Could not update gamepad chord widget %s: %s",
            property_name,
            tostring(direct_error)
        ))
        return false
    end
    return true
end

local function apply_gamepad_keycaps(host)
    local applied = 0
    for state_name, slots in pairs(GAMEPAD_CHORD_WIDGET_SLOTS) do
        local state_bindings = resolved_gamepad_bindings[state_name] or {}
        for action, property_name in pairs(slots) do
            if set_gamepad_chord_widget(
                host,
                property_name,
                state_bindings[action]
            ) then
                applied = applied + 1
            end
        end
    end
    return applied
end

local function apply_gamepad_widget_config(host)
    if not is_valid(host) then
        return
    end
    local ui_config = Config.ui or {}
    local gamepad = Config.gamepad or {}
    local property_name = ui_config.gamepad_enabled_property
        or "GamepadEnabled"
    -- This property is part of the new Blueprint contract. Keep the assignment
    -- optional so the Lua mod remains compatible with an older companion pak
    -- while the widget is being rebuilt.
    pcall(function()
        host[property_name] = gamepad.enabled ~= false
    end)
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

        -- Keep Match Size disabled and let the square SizeBox control the
        -- displayed dimensions. Matching the 40x40 source brush inside a
        -- smaller slot can distort the rendered keycap.
        ctrl_icon:SetBrushFromTexture(modifier_textures.CONTROL, false)
        alt_icon:SetBrushFromTexture(modifier_textures.ALT, false)
        shift_icon:SetBrushFromTexture(modifier_textures.SHIFT, false)
        primary_icon:SetBrushFromTexture(primary_texture, false)
        for _, keycap_box in ipairs({
            ctrl_box,
            alt_box,
            shift_box,
            primary_box,
        }) do
            keycap_box:SetWidthOverride(32.0)
            keycap_box:SetHeightOverride(32.0)
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

    local gamepad_keycaps_updated = apply_gamepad_keycaps(host)
    keycap_ui_host = host
    if chord_widgets_updated > 0 then
        log(string.format(
            "Configured Palworld key chords applied to %d companion widgets; "
                .. "%d stock gamepad keycaps applied.",
            chord_widgets_updated,
            gamepad_keycaps_updated
        ))
    else
        log(string.format(
            "Configured Palworld keycaps applied through the legacy companion UI; "
                .. "%d stock gamepad keycaps applied.",
            gamepad_keycaps_updated
        ))
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
    if ui_host_refresh_pending then
        return nil
    end
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
        apply_gamepad_widget_config(host)
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
        apply_gamepad_widget_config(host)
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
    if state ~= State.EDITING or not is_valid(transform_actor) then
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

    transform_game_thread_callback =
        transform_game_thread_callback or function()
            local apply_ok, apply_error =
                pcall(apply_preview_transform)
            transform_check_pending = false
            if not apply_ok then
                if not transform_loop_error_was_logged then
                    log("Transform loop recovered from an error: "
                        .. tostring(apply_error))
                    transform_loop_error_was_logged = true
                end
            else
                transform_loop_error_was_logged = false
            end
        end
    if type(ExecuteInGameThreadWithDelay) == "function" then
        transform_direct_loop_callback =
            start_repeating_game_thread_action(
                Config.transform_refresh_ms,
                function()
                if state == State.EDITING then
                    transform_game_thread_callback()
                end
                end,
                "Transform game-thread loop"
            )
        if transform_direct_loop_callback ~= nil then
            return
        end
        log("Could not start the game-thread transform loop.")
    end
    transform_loop_callback = transform_loop_callback or function()
        if state ~= State.EDITING then
            if transform_check_pending then
                return
            end
            transform_loop_started = false
            return true
        end
        if transform_check_pending then
            return
        end
        transform_check_pending = true
        local queue_ok, queue_error = pcall(
            ExecuteInGameThread,
            transform_game_thread_callback
        )
        if not queue_ok then
            transform_check_pending = false
            if not transform_loop_error_was_logged then
                log("Could not queue the transform loop: "
                    .. tostring(queue_error))
                transform_loop_error_was_logged = true
            end
        end
    end
    LoopAsync(Config.transform_refresh_ms, transform_loop_callback)
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
    if mode_ok and not in_building_mode then
        building_mode_exit_checks = building_mode_exit_checks + 1
        if building_mode_exit_checks >= 5 then
            return true, "Palworld exited building mode"
        end
    elseif mode_ok then
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

local function process_lifecycle_check()
    if state == State.FREEZING or state == State.UNFREEZING then
        return
    end
    if state == State.EDITING then
        if lifecycle_recovery_checks_remaining > 0 then
            if update_construction_hotkey_guide(
                true,
                false,
                false
            ) then
                lifecycle_recovery_checks_remaining = 0
            end
        end
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
            -- Recovery windows retry direct helpers every check. Expensive
            -- global scans retain their own backoff.
            builder_fallback_scan_cooldown =
                BUILDER_FALLBACK_RETRY_TICKS
        elseif builder_fallback_scan_cooldown > 0 then
            builder_fallback_scan_cooldown =
                builder_fallback_scan_cooldown - 1
        end
    end

    if not is_valid(unfrozen_ui_builder_component) then
        return
    end
    local hooks_ready = ensure_auto_unfreeze_hooks()

    local status_ok, in_building_mode, has_preview, active_preview =
        pcall(function()
            local in_mode =
                unfrozen_ui_builder_component:IsInBuildingMode()
            local checker =
                unfrozen_ui_builder_component.InstallChecker
            local target = nil
            if is_valid(checker) then
                target = checker.TargetBuildObject
            end
            return in_mode, is_valid(target), target
        end)

    local should_show = status_ok
        and in_building_mode
        and has_preview
    if unfrozen_ui_suppressed_preview_name ~= nil then
        if not should_show then
            -- A registered hook is not proof that Palworld has finished the
            -- transition. Keep recovery alive until the old preview becomes
            -- inactive and a valid replacement is observed.
            unfrozen_ui_suppression_saw_inactive = true
            should_show = false
        elseif unfrozen_ui_suppression_saw_inactive then
            unfrozen_ui_suppressed_preview_name = nil
            unfrozen_ui_suppression_saw_inactive = false
        elseif is_valid(active_preview) then
            local active_preview_name = full_name(active_preview)
            if unfrozen_ui_suppressed_preview_name ~= "<unknown>"
                and active_preview_name
                    ~= unfrozen_ui_suppressed_preview_name
            then
                unfrozen_ui_suppressed_preview_name = nil
                unfrozen_ui_suppression_saw_inactive = false
            else
                should_show = false
            end
        else
            should_show = false
        end
    end
    local ui_converged = true
    if should_show ~= unfrozen_ui_preview_visible then
        if not should_show and unfrozen_ui_preview_visible == nil then
            -- The companion widget and Palworld's construction guide both
            -- start hidden. Treat the first idle observation as converged
            -- instead of resolving Blueprint functions while their widgets
            -- are still completing construction during a world transition.
            unfrozen_ui_preview_visible = false
        else
            local ui_updated = update_construction_hotkey_guide(
                false,
                false,
                not should_show
            )
            if ui_updated then
                unfrozen_ui_preview_visible = should_show
            else
                unfrozen_ui_preview_visible = nil
                ui_converged = false
            end
        end
    end

    if state == State.WAITING_FOR_PREVIEW
        and should_show
        and unfrozen_ui_suppressed_preview_name == nil
        and unfrozen_ui_preview_visible == true
    then
        complete_freeze_transition(
            freeze_transition_generation,
            State.READY
        )
        verbose("Replacement preview settled; unfrozen controls are ready.")
    end

    if not status_ok then
        if cached_builder_component == unfrozen_ui_builder_component then
            cached_builder_component = nil
        end
        unfrozen_ui_builder_component = nil
        unfrozen_ui_preview_visible = nil
        builder_fallback_scan_cooldown = 0
    elseif unfrozen_ui_suppressed_preview_name == nil
        and hooks_ready
        and ui_converged
    then
        -- Hooks now own stable unfrozen visibility. Once state has converged,
        -- stop scheduling game-thread checks until an explicit event wakes
        -- recovery again.
        lifecycle_recovery_checks_remaining = 0
    end
end

start_lifecycle_monitor = function()
    if lifecycle_monitor_started then
        return
    end
    lifecycle_monitor_started = true

    lifecycle_game_thread_callback =
        lifecycle_game_thread_callback or function()
            local check_ok, check_error =
                pcall(process_lifecycle_check)
            lifecycle_check_pending = false
            if not check_ok then
                if not lifecycle_monitor_error_was_logged then
                    log("Lifecycle monitor recovered from an error: "
                        .. tostring(check_error))
                    lifecycle_monitor_error_was_logged = true
                end
                request_lifecycle_recovery(
                    LIFECYCLE_EVENT_RECOVERY_CHECKS
                )
            else
                lifecycle_monitor_error_was_logged = false
            end
        end

    lifecycle_monitor_loop_callback =
        lifecycle_monitor_loop_callback or function()
            if lifecycle_check_pending then
                return
            end
            if state ~= State.EDITING then
                if lifecycle_recovery_checks_remaining > 0 then
                    lifecycle_recovery_checks_remaining =
                        lifecycle_recovery_checks_remaining - 1
                    lifecycle_suppression_idle_ticks = 0
                elseif unfrozen_ui_suppressed_preview_name ~= nil then
                    lifecycle_suppression_idle_ticks =
                        lifecycle_suppression_idle_ticks + 1
                    if lifecycle_suppression_idle_ticks
                        < LIFECYCLE_SUPPRESSION_FALLBACK_TICKS
                    then
                        return
                    end
                    lifecycle_suppression_idle_ticks = 0
                else
                    lifecycle_suppression_idle_ticks = 0
                    lifecycle_monitor_started = false
                    return true
                end
            end

            lifecycle_check_pending = true
            local queue_ok, queue_error = pcall(
                ExecuteInGameThread,
                lifecycle_game_thread_callback
            )
            if not queue_ok then
                lifecycle_check_pending = false
                if not lifecycle_monitor_error_was_logged then
                    log("Could not queue the lifecycle monitor: "
                        .. tostring(queue_error))
                    lifecycle_monitor_error_was_logged = true
                end
                request_lifecycle_recovery(
                    LIFECYCLE_EVENT_RECOVERY_CHECKS
                )
            end
        end

    if type(ExecuteInGameThreadWithDelay) == "function" then
        lifecycle_direct_loop_callback =
            start_repeating_game_thread_action(
                LIFECYCLE_INTERVAL_MS,
                function()
                if state ~= State.EDITING
                    and state ~= State.FREEZING
                    and state ~= State.UNFREEZING
                then
                    if lifecycle_recovery_checks_remaining > 0 then
                        lifecycle_recovery_checks_remaining =
                            lifecycle_recovery_checks_remaining - 1
                        lifecycle_suppression_idle_ticks = 0
                    elseif unfrozen_ui_suppressed_preview_name ~= nil
                    then
                        lifecycle_suppression_idle_ticks =
                            lifecycle_suppression_idle_ticks + 1
                        if lifecycle_suppression_idle_ticks
                            < LIFECYCLE_SUPPRESSION_FALLBACK_TICKS
                        then
                            return
                        end
                        lifecycle_suppression_idle_ticks = 0
                    else
                        lifecycle_suppression_idle_ticks = 0
                        return
                    end
                end
                lifecycle_game_thread_callback()
                end,
                "Lifecycle game-thread loop"
            )
        if lifecycle_direct_loop_callback ~= nil then
            return
        end
        log("Could not start the game-thread lifecycle loop.")
    end

    LoopAsync(
        LIFECYCLE_INTERVAL_MS,
        lifecycle_monitor_loop_callback
    )
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

local function hide_unfrozen_guide_for_action(action_name)
    local active_component, _, active_preview =
        find_active_build_context(false)
    if not is_valid(active_preview)
        and unfrozen_ui_preview_visible ~= true
    then
        return
    end

    unfrozen_ui_suppression_saw_inactive = false
    if is_valid(active_preview) then
        unfrozen_ui_suppressed_preview_name = full_name(active_preview)
    else
        unfrozen_ui_suppressed_preview_name = "<unknown>"
    end
    if is_valid(active_component) then
        unfrozen_ui_builder_component = active_component
    end
    request_lifecycle_recovery(LIFECYCLE_EVENT_RECOVERY_CHECKS)
    if update_perfect_placement_ui(false, false, true) then
        unfrozen_ui_preview_visible = false
    else
        unfrozen_ui_preview_visible = nil
    end
    verbose("Hid the unfrozen guide before Palworld action: "
        .. tostring(action_name) .. ".")
end

local function resume_unfrozen_guide_from_construction(action_name)
    if state == State.EDITING
        or state == State.FREEZING
        or state == State.UNFREEZING
    then
        return
    end
    request_lifecycle_recovery(LIFECYCLE_EVENT_RECOVERY_CHECKS)
    local hooks_ready = ensure_auto_unfreeze_hooks()

    local active_component, _, active_preview =
        find_active_build_context(false)
    if not is_valid(active_component) or not is_valid(active_preview) then
        return
    end

    unfrozen_ui_suppressed_preview_name = nil
    unfrozen_ui_suppression_saw_inactive = false
    unfrozen_ui_builder_component = active_component
    if update_perfect_placement_ui(false, false, false) then
        unfrozen_ui_preview_visible = true
        if state == State.WAITING_FOR_PREVIEW then
            complete_freeze_transition(
                freeze_transition_generation,
                State.READY
            )
        end
        if hooks_ready then
            lifecycle_recovery_checks_remaining = 0
        end
    else
        unfrozen_ui_preview_visible = nil
    end
    verbose("Restored the unfrozen guide after Palworld construction event: "
        .. tostring(action_name) .. ".")
end

ensure_auto_unfreeze_hooks = function()
    local safety = Config.auto_unfreeze or {}
    if safety.enabled == false then
        return true
    end
    local all_hooks_registered = true

    local function register_action_hook(function_path, action_name)
        if auto_unfreeze_hooked_paths[function_path] then
            return true
        end
        local captured_action_name = action_name
        local hook_ok, pre_id, post_id = pcall(function()
            return RegisterHook(function_path, function()
                local action_ok, action_error = pcall(function()
                    if state == State.EDITING
                        and release_preview ~= nil
                    then
                        log("Auto-unfreezing before Palworld action: "
                            .. captured_action_name .. ".")
                        release_preview(
                            "Palworld action: " .. captured_action_name
                        )
                    else
                        hide_unfrozen_guide_for_action(
                            captured_action_name
                        )
                    end
                end)
                if not action_ok then
                    log("Palworld action pre-hook failed for "
                        .. captured_action_name .. ": "
                        .. tostring(action_error))
                end
            end, function()
                local post_ok, post_error = pcall(function()
                    ensure_auto_unfreeze_hooks()
                    request_lifecycle_recovery(
                        LIFECYCLE_EVENT_RECOVERY_CHECKS
                    )
                end)
                if not post_ok then
                    log("Palworld action post-hook failed for "
                        .. captured_action_name .. ": "
                        .. tostring(post_error))
                end
            end)
        end)
        if hook_ok and (pre_id ~= nil or post_id ~= nil) then
            auto_unfreeze_hooked_paths[function_path] = true
            return true
        end
        verbose("Auto-unfreeze hook is not loaded yet: "
            .. function_path)
        return false
    end

    local function register_resume_hook(function_path, action_name)
        if auto_unfreeze_hooked_paths[function_path] then
            return true
        end
        local captured_action_name = action_name
        local hook_ok, pre_id, post_id = pcall(function()
            return RegisterHook(function_path, function()
            end, function()
                local resume_ok, resume_error = pcall(
                    resume_unfrozen_guide_from_construction,
                    captured_action_name
                )
                if not resume_ok then
                    log("Construction resume post-hook failed for "
                        .. captured_action_name .. ": "
                        .. tostring(resume_error))
                end
            end)
        end)
        if hook_ok and (pre_id ~= nil or post_id ~= nil) then
            auto_unfreeze_hooked_paths[function_path] = true
            return true
        end
        verbose("Construction resume hook is not loaded yet: "
            .. function_path)
        return false
    end

    for _, function_name in ipairs(safety.building_action_functions or {}) do
        if not register_action_hook(
            PAL_BUILDING_FUNCTION_ROOT .. function_name,
            function_name
        ) then
            all_hooks_registered = false
        end
    end
    for _, function_name in ipairs(
        safety.input_listener_action_functions or {}
    ) do
        if not register_action_hook(
            PAL_INPUT_LISTENER_FUNCTION_ROOT .. function_name,
            function_name
        ) then
            all_hooks_registered = false
        end
    end
    for _, function_name in ipairs(
        safety.construction_resume_functions or {}
    ) do
        if not register_resume_hook(
            PAL_INGAME_CONSTRUCTION_FUNCTION_ROOT .. function_name,
            function_name
        ) then
            all_hooks_registered = false
        end
    end
    return all_hooks_registered
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
    return companion_ui_updated
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

        execute_in_game_thread_with_retained_delay(1800, function()
            if generation ~= notification_generation then
                return
            end
            pcall(function()
                if is_valid(toast) then
                    toast:AnmEvent_Out()
                end
            end)
        end, "Preview notification game-thread callback")
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
    ensure_auto_unfreeze_hooks()
    unfrozen_ui_suppressed_preview_name = nil
    unfrozen_ui_suppression_saw_inactive = false
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
    lifecycle_recovery_checks_remaining = 0
    transform_check_pending = false
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
    transform_check_pending = false
    building_mode_exit_checks = 0
    local is_manual_unfreeze = reason == "manual"
    local no_active_preview = reason == "preview object was destroyed"
        or reason == "Palworld cleared the build preview"
    local builder_became_invalid =
        reason == "builder component became invalid"
    local left_construction = reason == "Palworld exited building mode"
        or builder_became_invalid
    local menu_or_other_action = string.find(
        tostring(reason),
        "Palworld action:",
        1,
        true
    ) == 1
    local preview_was_rebuilt =
        reason == "Palworld replaced the selected build preview"
        or reason == "Palworld committed the build preview"
    local waiting_for_preview =
        menu_or_other_action or preview_was_rebuilt
    if waiting_for_preview then
        request_lifecycle_recovery(LIFECYCLE_EVENT_RECOVERY_CHECKS)
        unfrozen_ui_suppression_saw_inactive = false
        if locked_preview_name ~= nil then
            unfrozen_ui_suppressed_preview_name = locked_preview_name
        elseif is_valid(preview_actor) then
            unfrozen_ui_suppressed_preview_name = full_name(preview_actor)
        else
            unfrozen_ui_suppressed_preview_name = "<unknown>"
        end
    else
        lifecycle_recovery_checks_remaining = 0
        unfrozen_ui_suppressed_preview_name = nil
        unfrozen_ui_suppression_saw_inactive = false
    end
    unfrozen_ui_builder_component = builder_component
    local should_show_unfrozen =
        not (left_construction or no_active_preview or waiting_for_preview)
    local ui_updated = update_construction_hotkey_guide(
        false,
        is_manual_unfreeze,
        left_construction or no_active_preview or waiting_for_preview
    )
    if ui_updated then
        unfrozen_ui_preview_visible = should_show_unfrozen
    else
        unfrozen_ui_preview_visible = nil
        request_lifecycle_recovery(
            LIFECYCLE_EVENT_RECOVERY_CHECKS
        )
    end
    if not no_active_preview then
        set_preview_tick_enabled(preview_tick_was_enabled ~= false)
    end
    preview_tick_was_enabled = nil
    if not builder_became_invalid then
        set_builder_tick_enabled(builder_tick_was_enabled ~= false)
    end
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
    if waiting_for_preview then
        state = State.WAITING_FOR_PREVIEW
    else
        state = State.READY
        settle_freeze_transition(transition_id, State.READY)
    end
    return true
end

local function move_preview(forward_amount, right_amount, up_amount, distance_override)
    if state ~= State.EDITING or desired_location == nil then
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
    if state ~= State.EDITING or desired_rotation == nil then
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
    if state ~= State.EDITING or locked_origin_location == nil
        or locked_origin_rotation == nil then
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
    if state ~= State.EDITING
        or not is_valid(preview_actor)
        or desired_location == nil
    then
        verbose("Move-step input ignored: no frozen preview is active.")
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
    if freeze_transition_input_locked then
        verbose("Eyedropper ignored while placement state settles.")
        return
    end
    if state == State.EDITING then
        log("Eyedropper ignored while the preview is frozen.")
        return
    end
    execute_in_game_thread_retained(function()
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
                execute_in_game_thread_with_retained_delay(1, function()
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
                        log("Could not start copied build preview: "
                            .. tostring(delayed_error))
                    end
                end, "Copied preview game-thread callback")
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
    end, "Eyedropper game-thread callback")
end

local function register_chord(key, modifiers, callback)
    local ok, error_message = pcall(function()
        local queued_callback = function()
            local queue_ok, queue_error = pcall(
                ExecuteInGameThread,
                callback
            )
            if not queue_ok then
                log("Could not queue input callback: "
                    .. tostring(queue_error))
            end
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

local GAMEPAD_PHYSICAL_SERIALS = {
    { state = "unfrozen", chord = "L3", property = "GamepadUnfrozenL3Serial" },
    {
        state = "unfrozen",
        chord = "L3+DPAD_DOWN",
        property = "GamepadUnfrozenL3DPadDownSerial",
    },

    { state = "frozen", chord = "DPAD_UP", property = "GamepadFrozenDPadUpSerial" },
    { state = "frozen", chord = "DPAD_DOWN", property = "GamepadFrozenDPadDownSerial" },
    { state = "frozen", chord = "DPAD_LEFT", property = "GamepadFrozenDPadLeftSerial" },
    { state = "frozen", chord = "DPAD_RIGHT", property = "GamepadFrozenDPadRightSerial" },
    { state = "frozen", chord = "LT+DPAD_UP", property = "GamepadFrozenLTDPadUpSerial" },
    { state = "frozen", chord = "LT+DPAD_DOWN", property = "GamepadFrozenLTDPadDownSerial" },
    { state = "frozen", chord = "LT+DPAD_LEFT", property = "GamepadFrozenLTDPadLeftSerial" },
    { state = "frozen", chord = "LT+DPAD_RIGHT", property = "GamepadFrozenLTDPadRightSerial" },
    { state = "frozen", chord = "RT+DPAD_UP", property = "GamepadFrozenRTDPadUpSerial" },
    { state = "frozen", chord = "RT+DPAD_DOWN", property = "GamepadFrozenRTDPadDownSerial" },
    { state = "frozen", chord = "RT+DPAD_LEFT", property = "GamepadFrozenRTDPadLeftSerial" },
    { state = "frozen", chord = "RT+DPAD_RIGHT", property = "GamepadFrozenRTDPadRightSerial" },
    { state = "frozen", chord = "LT+RT+DPAD_UP", property = "GamepadFrozenLTRTDPadUpSerial" },
    { state = "frozen", chord = "LT+RT+DPAD_DOWN", property = "GamepadFrozenLTRTDPadDownSerial" },
    { state = "frozen", chord = "LT+RT+DPAD_LEFT", property = "GamepadFrozenLTRTDPadLeftSerial" },
    { state = "frozen", chord = "LT+RT+DPAD_RIGHT", property = "GamepadFrozenLTRTDPadRightSerial" },
    { state = "frozen", chord = "LB", property = "GamepadFrozenLBSerial" },
    { state = "frozen", chord = "RB", property = "GamepadFrozenRBSerial" },
    { state = "frozen", chord = "R3", property = "GamepadFrozenR3Serial" },
    { state = "frozen", chord = "L3", property = "GamepadFrozenL3Serial" },
}

local function get_active_gamepad_physical_serials()
    if active_gamepad_physical_serials ~= nil then
        return active_gamepad_physical_serials
    end

    active_gamepad_physical_serials = {}
    local index = 1
    while index <= #GAMEPAD_PHYSICAL_SERIALS do
        local physical_input = GAMEPAD_PHYSICAL_SERIALS[index]
        local state_actions =
            resolved_gamepad_chord_actions[physical_input.state] or {}
        if state_actions[physical_input.chord] ~= nil then
            active_gamepad_physical_serials[
                #active_gamepad_physical_serials + 1
            ] = physical_input
        end
        index = index + 1
    end
    return active_gamepad_physical_serials
end

local function read_gamepad_serial(host, property_name)
    local ok, value = pcall(function()
        return host[property_name]
    end)
    if not ok or value == nil then
        return nil
    end
    return tonumber(value)
end

local function initialize_gamepad_serials(host)
    gamepad_last_serials = {}
    gamepad_serial_host_name = full_name(host)
    local physical_inputs = get_active_gamepad_physical_serials()
    local index = 1
    while index <= #physical_inputs do
        local physical_input = physical_inputs[index]
        local value = read_gamepad_serial(host, physical_input.property)
        if value ~= nil then
            gamepad_last_serials[physical_input.property] = value
        end
        index = index + 1
    end
end

local function process_gamepad_actions()
    local gamepad = Config.gamepad or {}
    if gamepad.enabled == false then
        return
    end

    local host = find_perfect_placement_ui_host()
    if not is_valid(host) then
        gamepad_serial_host_name = nil
        gamepad_last_serials = {}
        return
    end

    if gamepad_serial_host_name == nil then
        initialize_gamepad_serials(host)
        return
    end

    local maximum_actions = math.max(
        1,
        math.floor(tonumber(gamepad.maximum_actions_per_poll) or 32)
    )
    local physical_inputs = get_active_gamepad_physical_serials()
    local index = 1
    while index <= #physical_inputs do
        local physical_input = physical_inputs[index]
        local property_name = physical_input.property
        local current = read_gamepad_serial(host, property_name)
        if current ~= nil then
            local previous = gamepad_last_serials[property_name]
            gamepad_last_serials[property_name] = current
            if previous ~= nil and current > previous then
                local state_actions =
                    resolved_gamepad_chord_actions[physical_input.state] or {}
                local action = state_actions[physical_input.chord]
                local callback = action_callbacks[action]
                local count = math.floor(math.min(
                    current - previous,
                    maximum_actions
                ))
                if action ~= nil and callback ~= nil then
                    local action_index = 1
                    while action_index <= count do
                        callback()
                        action_index = action_index + 1
                    end
                end
            end
        end
        index = index + 1
    end
end

local function start_gamepad_monitor()
    local gamepad = Config.gamepad or {}
    if gamepad_monitor_started or gamepad.enabled == false then
        return
    end
    gamepad_monitor_started = true

    local interval_ms = math.max(
        10,
        tonumber(gamepad.poll_interval_ms) or 50
    )
    gamepad_game_thread_callback = gamepad_game_thread_callback or function()
        local process_ok, process_error = pcall(process_gamepad_actions)
        gamepad_poll_pending = false
        if not process_ok then
            if not gamepad_monitor_error_was_logged then
                log("Gamepad monitor recovered from an error: "
                    .. tostring(process_error))
                gamepad_monitor_error_was_logged = true
            end
            gamepad_serial_host_name = nil
            gamepad_last_serials = {}
        else
            gamepad_monitor_error_was_logged = false
        end
    end
    gamepad_monitor_loop_callback = gamepad_monitor_loop_callback or function()
        if gamepad_poll_pending then
            return
        end
        gamepad_poll_pending = true
        local queue_ok, queue_error = pcall(
            ExecuteInGameThread,
            gamepad_game_thread_callback
        )
        if not queue_ok then
            gamepad_poll_pending = false
            if not gamepad_monitor_error_was_logged then
                log("Could not queue the gamepad monitor: "
                    .. tostring(queue_error))
                gamepad_monitor_error_was_logged = true
            end
        end
    end
    if type(ExecuteInGameThreadWithDelay) == "function" then
        gamepad_direct_loop_callback =
            start_repeating_game_thread_action(
                interval_ms,
                function()
                gamepad_game_thread_callback()
                end,
                "Gamepad game-thread loop"
            )
        if gamepad_direct_loop_callback ~= nil then
            return
        end
        log("Could not start the game-thread gamepad loop.")
    end
    LoopAsync(interval_ms, gamepad_monitor_loop_callback)
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
        or state == State.WAITING_FOR_PREVIEW
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

local UI_HOST_CLASS_PATH =
    "/Game/Mods/PerfectPlacement/WBP_PerfectPlacement_KeyGuide"
    .. ".WBP_PerfectPlacement_KeyGuide_C"

construction_ui_notify_callback = function()
    local notify_ok, notify_error = pcall(function()
        ensure_auto_unfreeze_hooks()
        request_lifecycle_recovery(
            LIFECYCLE_EVENT_RECOVERY_CHECKS
        )
    end)
    if not notify_ok then
        log("Construction UI notification failed: "
            .. tostring(notify_error))
    end
end
local construction_notify_ok, construction_notify_error = pcall(
    NotifyOnNewObject,
    PAL_INGAME_CONSTRUCTION_CLASS_PATH,
    construction_ui_notify_callback
)
if not construction_notify_ok then
    log("Could not register construction UI lifecycle notification: "
        .. tostring(construction_notify_error))
end

ui_host_notify_callback = function()
    -- Never retain the NotifyOnNewObject UObject across the construction
    -- delay. It may be destroyed by another map transition before the delayed
    -- callback runs, and even IsValid() cannot safely recover from an expired
    -- UE4SS remote wrapper.
    ui_host_refresh_generation = ui_host_refresh_generation + 1
    local generation = ui_host_refresh_generation
    ui_host_refresh_pending = true
    perfect_placement_ui_host = nil
    keycap_ui_host = nil
    active_gamepad_physical_serials = nil
    gamepad_serial_host_name = nil
    gamepad_last_serials = {}
    ui_host_missing_was_logged = false
    cached_builder_component = nil
    unfrozen_ui_builder_component = nil
    unfrozen_ui_preview_visible = nil
    builder_fallback_scan_cooldown = 0

    local delay_queued = execute_in_game_thread_with_retained_delay(
        250,
        function()
            if generation ~= ui_host_refresh_generation then
                return
            end

            ui_host_refresh_pending = false
            request_lifecycle_recovery(
                LIFECYCLE_INITIAL_RECOVERY_CHECKS
            )
            find_perfect_placement_ui_host()
        end,
        "Companion UI refresh game-thread callback"
    )
    if not delay_queued and generation == ui_host_refresh_generation then
        ui_host_refresh_pending = false
    end
end
local ui_notify_ok, ui_notify_error = pcall(
    NotifyOnNewObject,
    UI_HOST_CLASS_PATH,
    ui_host_notify_callback
)
if not ui_notify_ok then
    log("Could not register companion UI lifecycle notification: "
        .. tostring(ui_notify_error))
end

-- Register whichever Palworld UI functions are already loaded. Native
-- construction-object notifications retry registration when placement UI is
-- created later.
ensure_auto_unfreeze_hooks()

-- The game-thread lifecycle loop stays registered but becomes a cheap no-op
-- after stable unfrozen state converges. Hooks and object notifications wake
-- recovery; frozen previews keep safety checks active.
request_lifecycle_recovery(LIFECYCLE_INITIAL_RECOVERY_CHECKS)
start_gamepad_monitor()

log("Loaded Perfect Placement 0.2.0-beta.3")
log("Companion key-guide UI bridge revision 29 loaded.")
log("Open build mode, show a preview, then middle-click to freeze it.")
