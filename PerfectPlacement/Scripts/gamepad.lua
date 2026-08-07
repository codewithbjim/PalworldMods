-- Gamepad input adapter for Perfect Placement.
--
-- The companion Blueprint owns device input and calls
-- QueueGamepadPhysicalInput once for each physical chord. This module maps
-- those physical inputs to configurable logical actions, then hands the action
-- to main.lua's guarded dispatcher. Problematic native-consumed buttons enter
-- through dispatch_native_physical; neither path polls controller state.

local M = {}
local Instance = {}
Instance.__index = Instance

local C = {
    hook_path =
        "/Game/Mods/PerfectPlacement/WBP_PerfectPlacement_KeyGuide"
        .. ".WBP_PerfectPlacement_KeyGuide_C:"
        .. "QueueGamepadPhysicalInput",
    source = "gamepad",
    keyguide_root = "/Game/Pal/Texture/UI/KeyGuide/",
    keycap_assets = {
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
    },
    chord_widgets = {
        unfrozen = {
            toggle_freeze = "GP_UnfrozenToggleFreezeChord",
            copy_piece = "GP_UnfrozenCopyChord",
            freeze_to_piece = "GP_UnfrozenCopyFreezeChord",
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
    },
    modifier_order = {
        L3 = 1,
        LT = 2,
        RT = 3,
    },
    action_order = {
        unfrozen = {
            "toggle_freeze",
            "copy_piece",
            "freeze_to_piece",
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
    },
    defaults = {
        unfrozen = {
            toggle_freeze = "L3",
            copy_piece = {
                key = "DPAD_DOWN",
                modifiers = { "L3" },
            },
            freeze_to_piece = {
                key = "DPAD_UP",
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
    supported = {
        unfrozen = {
            L3 = true,
            ["L3+DPAD_DOWN"] = true,
            ["L3+DPAD_UP"] = true,
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
    },
    physical = {
        [0] = {
            name = "Unfrozen_L3",
            state = "unfrozen",
            chord = "L3",
            serial = "GamepadUnfrozenL3Serial",
        },
        [1] = {
            name = "Unfrozen_L3_DPadDown",
            state = "unfrozen",
            chord = "L3+DPAD_DOWN",
            serial = "GamepadUnfrozenL3DPadDownSerial",
        },
        [2] = {
            name = "Frozen_DPadUp",
            state = "frozen",
            chord = "DPAD_UP",
            serial = "GamepadFrozenDPadUpSerial",
        },
        [3] = {
            name = "Frozen_DPadDown",
            state = "frozen",
            chord = "DPAD_DOWN",
            serial = "GamepadFrozenDPadDownSerial",
        },
        [4] = {
            name = "Frozen_DPadLeft",
            state = "frozen",
            chord = "DPAD_LEFT",
            serial = "GamepadFrozenDPadLeftSerial",
        },
        [5] = {
            name = "Frozen_DPadRight",
            state = "frozen",
            chord = "DPAD_RIGHT",
            serial = "GamepadFrozenDPadRightSerial",
        },
        [6] = {
            name = "Frozen_LT_DPadUp",
            state = "frozen",
            chord = "LT+DPAD_UP",
            serial = "GamepadFrozenLTDPadUpSerial",
        },
        [7] = {
            name = "Frozen_LT_DPadDown",
            state = "frozen",
            chord = "LT+DPAD_DOWN",
            serial = "GamepadFrozenLTDPadDownSerial",
        },
        [8] = {
            name = "Frozen_LT_DPadLeft",
            state = "frozen",
            chord = "LT+DPAD_LEFT",
            serial = "GamepadFrozenLTDPadLeftSerial",
        },
        [9] = {
            name = "Frozen_LT_DPadRight",
            state = "frozen",
            chord = "LT+DPAD_RIGHT",
            serial = "GamepadFrozenLTDPadRightSerial",
        },
        [10] = {
            name = "Frozen_RT_DPadUp",
            state = "frozen",
            chord = "RT+DPAD_UP",
            serial = "GamepadFrozenRTDPadUpSerial",
        },
        [11] = {
            name = "Frozen_RT_DPadDown",
            state = "frozen",
            chord = "RT+DPAD_DOWN",
            serial = "GamepadFrozenRTDPadDownSerial",
        },
        [12] = {
            name = "Frozen_RT_DPadLeft",
            state = "frozen",
            chord = "RT+DPAD_LEFT",
            serial = "GamepadFrozenRTDPadLeftSerial",
        },
        [13] = {
            name = "Frozen_RT_DPadRight",
            state = "frozen",
            chord = "RT+DPAD_RIGHT",
            serial = "GamepadFrozenRTDPadRightSerial",
        },
        [14] = {
            name = "Frozen_LT_RT_DPadUp",
            state = "frozen",
            chord = "LT+RT+DPAD_UP",
            serial = "GamepadFrozenLTRTDPadUpSerial",
        },
        [15] = {
            name = "Frozen_LT_RT_DPadDown",
            state = "frozen",
            chord = "LT+RT+DPAD_DOWN",
            serial = "GamepadFrozenLTRTDPadDownSerial",
        },
        [16] = {
            name = "Frozen_LT_RT_DPadLeft",
            state = "frozen",
            chord = "LT+RT+DPAD_LEFT",
            serial = "GamepadFrozenLTRTDPadLeftSerial",
        },
        [17] = {
            name = "Frozen_LT_RT_DPadRight",
            state = "frozen",
            chord = "LT+RT+DPAD_RIGHT",
            serial = "GamepadFrozenLTRTDPadRightSerial",
        },
        [18] = {
            name = "Frozen_LB",
            state = "frozen",
            chord = "LB",
            serial = "GamepadFrozenLBSerial",
        },
        [19] = {
            name = "Frozen_RB",
            state = "frozen",
            chord = "RB",
            serial = "GamepadFrozenRBSerial",
        },
        [20] = {
            name = "Frozen_R3",
            state = "frozen",
            chord = "R3",
            serial = "GamepadFrozenR3Serial",
        },
        [21] = {
            name = "Frozen_L3",
            state = "frozen",
            chord = "L3",
            serial = "GamepadFrozenL3Serial",
        },
        -- Appended after the original 22 entries so every published enum value
        -- keeps its existing numeric identity.
        [22] = {
            name = "Unfrozen_L3_DPadUp",
            state = "unfrozen",
            chord = "L3+DPAD_UP",
            serial = "GamepadUnfrozenCopyFreezeSerial",
            serial_aliases = {
                "GamepadUnfrozenL3DPadUpSerial",
            },
        },
    },
}

-- A successful hook retains its adapter for the lifetime of the Lua mod.
-- UE4SS has previously collected callbacks whose final Lua owner disappeared.
local retained_instances = {}
local retained_instance_serial = 0

local function default_log()
end

local function default_is_valid(value)
    return value ~= nil
end

local function normalize_token(value)
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

local function normalize_binding(binding)
    if binding == false then
        return nil, "disabled"
    end

    local key = binding
    local modifiers = {}
    if type(binding) == "table" then
        if binding.disabled then
            return nil, "disabled"
        end
        key = binding.key
        if type(binding.modifiers) == "table" then
            for _, modifier in ipairs(binding.modifiers) do
                modifiers[#modifiers + 1] = modifier
            end
        end
    end

    key = normalize_token(key)
    if key == nil or key == "" then
        return nil, "missing key"
    end

    local normalized_modifiers = {}
    local seen = {}
    for _, modifier in ipairs(modifiers) do
        local normalized = normalize_token(modifier)
        if C.modifier_order[normalized] == nil then
            return nil, "unsupported modifier " .. tostring(modifier)
        end
        if not seen[normalized] then
            seen[normalized] = true
            normalized_modifiers[#normalized_modifiers + 1] = normalized
        end
    end
    table.sort(normalized_modifiers, function(left, right)
        return C.modifier_order[left] < C.modifier_order[right]
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

local function remap_preference(config, action)
    if config.invert_forward_back then
        if action == "move_forward" then
            return "move_back"
        elseif action == "move_back" then
            return "move_forward"
        end
    end
    if config.invert_height then
        if action == "move_up" then
            return "move_down"
        elseif action == "move_down" then
            return "move_up"
        end
    end
    if config.swap_rotate_buttons then
        if action == "rotate_left" then
            return "rotate_right"
        elseif action == "rotate_right" then
            return "rotate_left"
        end
    end
    return action
end

local function config_section(config)
    if type(config) ~= "table" then
        return {}
    end
    if type(config.gamepad) == "table" then
        return config.gamepad
    end
    return config
end

local function enum_name_key(value)
    local name = string.upper(tostring(value or ""))
    name = string.gsub(name, "^.*::", "")
    name = string.gsub(name, "[^A-Z0-9]", "")
    return name
end

local function decode_integer(value)
    if type(value) == "number" then
        local integer = math.floor(value)
        if integer == value and C.physical[integer] ~= nil then
            return integer
        end
        return nil
    end
    if type(value) == "string" then
        local numeric = string.match(value, "^%s*(%-?%d+)%s*$")
        if numeric ~= nil then
            local integer = tonumber(numeric)
            if C.physical[integer] ~= nil then
                return integer
            end
        end
        local candidate = enum_name_key(value)
        for index = 0, 22 do
            if candidate == enum_name_key(C.physical[index].name) then
                return index
            end
        end
    end
    return nil
end

local function decode_enum(value)
    local current = value
    local seen = {}
    for _ = 1, 4 do
        local decoded = decode_integer(current)
        if decoded ~= nil then
            return decoded
        end
        if current == nil or seen[current] then
            break
        end
        seen[current] = true

        local next_value = nil
        local get_ok, got = pcall(function()
            return current:get()
        end)
        if get_ok and got ~= nil and got ~= current then
            next_value = got
        else
            for _, property_name in ipairs({
                "Value",
                "value",
                "EnumValue",
                "enum_value",
            }) do
                local property_ok, property_value = pcall(function()
                    return current[property_name]
                end)
                if property_ok
                    and property_value ~= nil
                    and property_value ~= current
                then
                    next_value = property_value
                    break
                end
            end
        end
        if next_value == nil then
            local text_ok, text = pcall(tostring, current)
            if text_ok then
                return decode_integer(text)
            end
            break
        end
        current = next_value
    end
    return nil
end

local function unwrap_context(context)
    if context == nil then
        return nil
    end
    local unwrap_ok, unwrapped = pcall(function()
        return context:get()
    end)
    if unwrap_ok and unwrapped ~= nil then
        return unwrapped
    end
    return context
end

local function object_identity(object)
    if object == nil then
        return nil
    end
    local full_name_ok, full_name = pcall(function()
        return object:GetFullName()
    end)
    if full_name_ok and full_name ~= nil then
        return tostring(full_name)
    end
    local text_ok, text = pcall(tostring, object)
    if text_ok then
        return text
    end
    return nil
end

function Instance:_log(message)
    pcall(self.log, message)
end

function Instance:_is_valid(value)
    local ok, valid = pcall(self.is_valid, value)
    return ok and valid == true
end

function Instance:_resolve_bindings()
    local resolved = {
        unfrozen = {},
        frozen = {},
    }
    local chord_actions = {
        unfrozen = {},
        frozen = {},
    }
    local configured_states = self.config.bindings or {}

    for _, state_name in ipairs({ "unfrozen", "frozen" }) do
        local configured = configured_states[state_name] or {}
        for _, action in ipairs(C.action_order[state_name]) do
            local raw_binding = configured[action]
            if raw_binding == nil then
                raw_binding = C.defaults[state_name][action]
            end

            local binding, binding_error = normalize_binding(raw_binding)
            if binding == nil then
                if binding_error ~= "disabled" then
                    self:_log(string.format(
                        "Gamepad binding %s.%s ignored: %s.",
                        state_name,
                        action,
                        tostring(binding_error)
                    ))
                end
            elseif not C.supported[state_name][binding.chord] then
                self:_log(string.format(
                    "Gamepad binding %s.%s ignored: %s is not captured in %s mode.",
                    state_name,
                    action,
                    binding.chord,
                    state_name
                ))
            elseif chord_actions[state_name][binding.chord] ~= nil then
                self:_log(string.format(
                    "Gamepad binding %s.%s ignored: %s is already assigned to %s.",
                    state_name,
                    action,
                    binding.chord,
                    chord_actions[state_name][binding.chord]
                ))
            else
                local effective_action =
                    remap_preference(self.config, action)
                resolved[state_name][effective_action] = binding
                chord_actions[state_name][binding.chord] =
                    effective_action
            end
        end
    end

    self.resolved_bindings = resolved
    self.chord_actions = chord_actions
end

function Instance:_read_serial(host, property_name)
    if not self:_is_valid(host) then
        return nil
    end
    local ok, value = pcall(function()
        return host[property_name]
    end)
    if not ok or value == nil then
        return nil
    end
    return tonumber(value)
end

function Instance:_read_physical_serial(host, physical)
    local value = self:_read_serial(host, physical.serial)
    if value ~= nil then
        return value
    end
    for _, property_name in ipairs(physical.serial_aliases or {}) do
        value = self:_read_serial(host, property_name)
        if value ~= nil then
            return value
        end
    end
    return nil
end

function Instance:_baseline_serials(host)
    self.serials = {}
    for index = 0, 22 do
        local physical = C.physical[index]
        local value = self:_read_physical_serial(host, physical)
        if value ~= nil then
            self.serials[index] = value
        end
    end
end

function Instance:_call_ui(callback, ...)
    if type(callback) ~= "function" then
        return true
    end
    local ok, error_message = pcall(callback, ...)
    if not ok then
        self:_log("Gamepad UI callback failed: " .. tostring(error_message))
    end
    return ok
end

function Instance:_apply_enabled(host, enabled)
    local bridge_enabled = enabled == true
    if type(self.set_enabled) == "function" then
        return self:_call_ui(self.set_enabled, host, bridge_enabled)
    end
    local ok, error_message = pcall(function()
        host[self.enabled_property] = bridge_enabled
    end)
    if not ok then
        self:_log("Could not update GamepadEnabled: "
            .. tostring(error_message))
    end
    return ok
end

function Instance:_keycap_asset(token)
    local asset_name = C.keycap_assets[token]
    if asset_name == nil then
        return nil
    end
    local texture_path = C.keyguide_root .. asset_name
    return {
        texture_path = texture_path,
        texture_object_path = texture_path .. "." .. asset_name,
    }
end

function Instance:_load_keycap(token)
    local asset = self:_keycap_asset(token)
    if asset == nil then
        return nil
    end
    if type(self.load_keycap_texture) == "function" then
        local ok, texture = pcall(self.load_keycap_texture, asset)
        if ok and self:_is_valid(texture) then
            return texture
        end
        return nil
    end

    local cached = self.texture_cache[asset.texture_object_path]
    if self:_is_valid(cached) then
        return cached
    end

    local load_ok, loaded = pcall(function()
        return LoadAsset(asset.texture_object_path)
    end)
    if load_ok and self:_is_valid(loaded) then
        self.texture_cache[asset.texture_object_path] = loaded
        return loaded
    end

    local find_ok, found = pcall(function()
        return StaticFindObject(asset.texture_object_path)
    end)
    if find_ok and self:_is_valid(found) then
        self.texture_cache[asset.texture_object_path] = found
        return found
    end
    self:_log("Could not load gamepad keycap: " .. asset.texture_path)
    return nil
end

function Instance:_set_chord_widget(host, property_name, binding)
    local widget_ok, widget = pcall(function()
        return host[property_name]
    end)
    if not widget_ok or not self:_is_valid(widget) then
        return false
    end

    local ok, error_message = pcall(function()
        local modifier1_box = widget.Modifier1Box
        local modifier1_icon = widget.Modifier1Icon
        local modifier1_separator = widget.Modifier1Separator
        local modifier2_box = widget.Modifier2Box
        local modifier2_icon = widget.Modifier2Icon
        local modifier2_separator = widget.Modifier2Separator
        local primary_box = widget.PrimaryBox
        local primary_icon = widget.PrimaryIcon
        if not self:_is_valid(modifier1_box)
            or not self:_is_valid(modifier1_icon)
            or not self:_is_valid(modifier1_separator)
            or not self:_is_valid(modifier2_box)
            or not self:_is_valid(modifier2_icon)
            or not self:_is_valid(modifier2_separator)
            or not self:_is_valid(primary_box)
            or not self:_is_valid(primary_icon)
        then
            error("one or more gamepad chord children are unavailable")
        end

        for _, box in ipairs({
            modifier1_box,
            modifier2_box,
            primary_box,
        }) do
            box:SetWidthOverride(32.0)
            box:SetHeightOverride(32.0)
        end

        local modifiers = binding ~= nil and binding.modifiers or {}
        local modifier1 = self:_load_keycap(modifiers[1])
        local modifier2 = self:_load_keycap(modifiers[2])
        local primary = binding ~= nil
            and self:_load_keycap(binding.key)
            or nil
        local show_modifier1 = self:_is_valid(modifier1)
        local show_modifier2 = self:_is_valid(modifier2)
        local show_primary = self:_is_valid(primary)

        if show_modifier1 then
            modifier1_icon:SetBrushFromTexture(modifier1, false)
        end
        if show_modifier2 then
            modifier2_icon:SetBrushFromTexture(modifier2, false)
        end
        if show_primary then
            primary_icon:SetBrushFromTexture(primary, false)
        end
        modifier1_box:SetVisibility(show_modifier1 and 0 or 1)
        modifier1_separator:SetVisibility(show_modifier1 and 0 or 1)
        modifier2_box:SetVisibility(show_modifier2 and 0 or 1)
        modifier2_separator:SetVisibility(show_modifier2 and 0 or 1)
        primary_box:SetVisibility(show_primary and 0 or 1)
    end)
    if not ok then
        self:_log(string.format(
            "Could not update gamepad chord widget %s: %s",
            property_name,
            tostring(error_message)
        ))
        return false
    end
    return true
end

function Instance:_apply_gamepad_keycaps(host)
    local applied = 0
    for state_name, slots in pairs(C.chord_widgets) do
        local state_bindings = self.resolved_bindings[state_name] or {}
        for action, property_name in pairs(slots) do
            if self:_set_chord_widget(
                host,
                property_name,
                state_bindings[action]
            ) then
                applied = applied + 1
            end
        end
    end
    if applied > 0 then
        self:_log(string.format(
            "Configured gamepad key chords applied to %d companion widgets.",
            applied
        ))
    end
    return applied
end

function Instance:_attach_host(host, start_hook)
    if not self:_is_valid(host) then
        self.host_identity = nil
        self.serials = {}
        return false
    end

    self.host_identity = object_identity(host)
    self:_baseline_serials(host)
    if start_hook and self.enabled and not self.started then
        self:start()
    end
    -- Leave the Blueprint input actors disabled when the Lua event hook is not
    -- available. This avoids consuming controller input without a dispatcher.
    self:_apply_enabled(host, self.enabled and self.started)
    self:_apply_gamepad_keycaps(host)
    self:_call_ui(
        self.apply_keycaps,
        host,
        self.resolved_bindings,
        self.chord_actions
    )
    self:_call_ui(
        self.on_host_attached,
        host,
        self.enabled and self.started,
        self.resolved_bindings
    )

    return true
end

function Instance:_ensure_event_host(context)
    local event_host = unwrap_context(context)
    if not self:_is_valid(event_host) then
        return nil, false
    end

    local identity = object_identity(event_host)
    if self.host_identity == nil
        or identity == nil
        or identity ~= self.host_identity
    then
        self:_attach_host(event_host, false)
        return event_host, true
    end
    return event_host, false
end

function Instance:_dispatch_physical(index, host, fallback)
    local physical = C.physical[index]
    if physical == nil then
        return false
    end

    if host ~= nil then
        local current = self:_read_physical_serial(host, physical)
        if current ~= nil then
            self.serials[index] = current
        end
    end

    local state_actions = self.chord_actions[physical.state] or {}
    local action = state_actions[physical.chord]
    if action == nil then
        if not self.unmapped_input_logged[index] then
            self.unmapped_input_logged[index] = true
            self:_log("Gamepad physical input has no active binding: "
                .. physical.name)
        end
        return false
    end

    local dispatch_ok, dispatched_or_error = pcall(
        self.dispatch_action,
        action,
        C.source,
        {
            physical_input = index,
            physical_name = physical.name,
            state = physical.state,
            chord = physical.chord,
            counter_fallback = fallback == true,
        }
    )
    if not dispatch_ok then
        self:_log("Gamepad action dispatch failed: "
            .. tostring(dispatched_or_error))
        return false
    end
    if dispatched_or_error == false then
        self:_log("Gamepad action dispatch was rejected: " .. action)
        return false
    end
    if not self.dispatched_input_logged[index] then
        self.dispatched_input_logged[index] = true
        self:_log("Gamepad physical input reached Lua: "
            .. physical.name .. " -> " .. action)
    end
    return true
end

function Instance:_mark_gamepad_input(host)
    if not self:_is_valid(host) then
        return false
    end
    local ok, error_message = pcall(function()
        host:SetUsingGamepad(true)
    end)
    if not ok and not self.device_guide_error_logged then
        self.device_guide_error_logged = true
        self:_log("Could not switch the companion guide to gamepad input: "
            .. tostring(error_message))
    end
    return ok
end

function Instance:set_using_gamepad(using_gamepad)
    local host = nil
    if type(self.get_host) == "function" then
        local host_ok, current_host = pcall(self.get_host)
        if host_ok then
            host = current_host
        end
    end
    if not self:_is_valid(host) then
        return false
    end
    local ok, error_message = pcall(function()
        host:SetUsingGamepad(using_gamepad == true)
    end)
    if not ok and not self.device_guide_error_logged then
        self.device_guide_error_logged = true
        self:_log("Could not update the companion guide input device: "
            .. tostring(error_message))
    end
    return ok
end

function Instance:_dispatch_counter_delta(host, event_fallback)
    if event_fallback and not self.counter_fallback_logged then
        self.counter_fallback_logged = true
        self:_log(
            "Gamepad enum argument was unavailable; using event-triggered "
            .. "counter detection without polling."
        )
    end

    local changed = {}
    for index = 0, 22 do
        local physical = C.physical[index]
        local current = self:_read_physical_serial(host, physical)
        local previous = self.serials[index]
        if current ~= nil then
            self.serials[index] = current
            if previous ~= nil and current > previous then
                changed[#changed + 1] = index
            end
        end
    end

    -- QueueGamepadPhysicalInput represents one physical input. If counters
    -- contain a stale burst, advance every baseline but dispatch only the first
    -- changed chord so an old input cannot be replayed into the build preview.
    if #changed > 0 then
        return self:_dispatch_physical(changed[1], host, true)
    end
    return false
end

function Instance:_on_hook(context, physical_input)
    if not self.enabled or not self.started then
        return
    end

    local host, host_was_replaced = self:_ensure_event_host(context)
    self:_mark_gamepad_input(host)
    local index = decode_enum(physical_input)
    if index ~= nil then
        self:_dispatch_physical(index, host, false)
        return
    end

    if not self:_is_valid(host) then
        if not self.missing_host_logged then
            self.missing_host_logged = true
            self:_log(
                "Gamepad event ignored because the KeyGuide host is unavailable."
            )
        end
        return
    end
    self.missing_host_logged = false

    -- A newly discovered host is baselined after this Blueprint call. Dropping
    -- that one undecodable event is safer than replaying historical counters.
    -- Normal integration calls attach_host when the widget is created, so this
    -- path is only a defensive fallback.
    if host_was_replaced then
        if not self.new_host_drop_logged then
            self.new_host_drop_logged = true
            self:_log(
                "Gamepad host changed during an undecodable event; counters "
                .. "were baselined and that event was ignored."
            )
        end
        return
    end
    self:_dispatch_counter_delta(host, true)
end

function Instance:start()
    if self.started then
        return true
    end
    if self.hook_registration_terminal then
        return false, "gamepad hook registration previously returned incomplete IDs"
    end
    if not self.enabled then
        return false, "gamepad support is disabled"
    end

    local register_hook = self.register_hook or _G.RegisterHook
    if type(register_hook) ~= "function" then
        return false, "RegisterHook is unavailable"
    end

    if self.hook_callback == nil then
        self.hook_callback = function(context, physical_input)
            local ok, error_message = pcall(
                self._on_hook,
                self,
                context,
                physical_input
            )
            if not ok then
                self:_log(
                    "Gamepad Blueprint event recovered from an error: "
                    .. tostring(error_message)
                )
            end
        end
    end

    local hook_ok, pre_id, post_id = pcall(function()
        -- For Blueprint UFunctions in this UE4SS build, callback argument 2 is
        -- invoked after the Blueprint function. Argument 3 is ignored, so one
        -- meaningful callback is registered and both returned IDs are retained.
        return register_hook(C.hook_path, self.hook_callback)
    end)
    if not hook_ok then
        local reason = tostring(pre_id)
        self:_log("Gamepad Blueprint event hook is not loaded: " .. reason)
        return false, reason
    end

    self.hook_pre_id = pre_id
    self.hook_post_id = post_id
    if pre_id == nil or post_id == nil then
        -- The API may already have installed part of the hook even when one ID
        -- is missing. Retain every record, fail closed, and never register the
        -- same callback again into an unknown partial state.
        self.hook_registration_terminal = true
        retained_instance_serial = retained_instance_serial + 1
        self.retention_id = retained_instance_serial
        retained_instances[self.retention_id] = self
        local reason = "the hook returned incomplete IDs"
        self:_log("Gamepad Blueprint event hook is disabled: " .. reason)
        return false, reason
    end

    self.started = true
    retained_instance_serial = retained_instance_serial + 1
    self.retention_id = retained_instance_serial
    retained_instances[self.retention_id] = self
    self:_log("Gamepad Blueprint event hook registered.")
    return true
end

function Instance:attach_host(host)
    return self:_attach_host(host, true)
end

function Instance:detach_host(host)
    if host ~= nil and self.host_identity ~= nil then
        local identity = object_identity(host)
        if identity ~= nil and identity ~= self.host_identity then
            return false
        end
    end
    self.host_identity = nil
    self.serials = {}
    return true
end

function Instance:shutdown()
    self.enabled = false
    self.started = false

    local host = nil
    if type(self.get_host) == "function" then
        local host_ok, current_host = pcall(self.get_host)
        if host_ok then
            host = current_host
        end
    end
    if self:_is_valid(host) then
        self:_apply_enabled(host, false)
    end

    if type(self.unregister_hook) == "function"
        and self.hook_pre_id ~= nil
        and self.hook_post_id ~= nil
    then
        pcall(
            self.unregister_hook,
            C.hook_path,
            self.hook_pre_id,
            self.hook_post_id
        )
    end
    self.hook_pre_id = nil
    self.hook_post_id = nil
    self:detach_host()
    if self.retention_id ~= nil then
        retained_instances[self.retention_id] = nil
        self.retention_id = nil
    end
    return true
end

function Instance:get_resolved_bindings()
    return self.resolved_bindings, self.chord_actions
end

function Instance:get_keycap_texture(token)
    return self:_load_keycap(token)
end

-- NativeInput calls this entry point only for physical buttons that Palworld
-- consumes before the companion Blueprint can receive them. Keeping the
-- physical-to-logical mapping here preserves user remaps and all normal input
-- guards without duplicating placement behavior in native code.
function Instance:dispatch_native_physical(index)
    if not self.enabled or not self.started then
        return false
    end
    local decoded = decode_integer(index)
    if decoded == nil then
        return false
    end
    self:set_using_gamepad(true)
    return self:_dispatch_physical(decoded, nil, false)
end

function M.new(options)
    options = options or {}
    if type(options.dispatch_action) ~= "function" then
        error("gamepad.new requires dispatch_action")
    end

    local instance = setmetatable({
        config = config_section(options.config),
        log = type(options.log) == "function"
            and options.log
            or default_log,
        is_valid = type(options.is_valid) == "function"
            and options.is_valid
            or default_is_valid,
        dispatch_action = options.dispatch_action,
        register_hook = options.register_hook,
        unregister_hook = options.unregister_hook,
        get_host = options.get_host,
        set_enabled = options.set_enabled,
        enabled_property = options.enabled_property or "GamepadEnabled",
        load_keycap_texture = options.load_keycap_texture,
        apply_keycaps = options.apply_keycaps,
        on_host_attached = options.on_host_attached,
        enabled = false,
        started = false,
        serials = {},
        texture_cache = {},
        resolved_bindings = {},
        chord_actions = {},
        dispatched_input_logged = {},
        unmapped_input_logged = {},
    }, Instance)
    instance.enabled = instance.config.enabled == true
    instance:_resolve_bindings()
    return instance
end

M.hook_path = C.hook_path

return M
