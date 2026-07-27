-- Symbolic Perfect Placement key bindings and Palworld keycap metadata.
--
-- Windows virtual-key values are used deliberately. They are stable across
-- UE4SS versions even when a build exposes different symbolic Key names.

local M = {}

local KEYBOARD_ROOT = "/Game/Pal/Texture/UI/KeyGuide/keyboard/"
local MOUSE_ROOT = "/Game/Pal/Texture/UI/KeyGuide/mouse/"

local keys = {}

local function add_keyboard(name, virtual_key, asset_suffix)
    local asset_name = "T_KeyGuide_Keyboard_" .. asset_suffix
    local package_path = KEYBOARD_ROOT .. asset_name
    keys[name] = {
        virtual_key = virtual_key,
        texture_path = package_path,
        texture_object_path = package_path .. "." .. asset_name,
    }
end

local function add_mouse(name, virtual_key, asset_name)
    local package_path = MOUSE_ROOT .. asset_name
    keys[name] = {
        virtual_key = virtual_key,
        texture_path = package_path,
        texture_object_path = package_path .. "." .. asset_name,
    }
end

for index = 0, 9 do
    add_keyboard(tostring(index), 0x30 + index, tostring(index))
    add_keyboard("NUMPAD_" .. tostring(index), 0x60 + index, "Num" .. tostring(index))
end

-- These two vertical-edit keys are also registered with the navigation-key
-- codes Windows reports for the same physical keys while NumLock is off.
keys.NUMPAD_1.alternate_virtual_key = 0x23 -- End
keys.NUMPAD_3.alternate_virtual_key = 0x22 -- Page Down

for index = 0, 25 do
    local letter = string.char(string.byte("A") + index)
    add_keyboard(letter, 0x41 + index, letter)
end

for index = 1, 12 do
    add_keyboard("F" .. tostring(index), 0x6F + index, "F" .. tostring(index))
end

add_keyboard("BACKSPACE", 0x08, "BackSpace")
add_keyboard("TAB", 0x09, "Tab")
add_keyboard("ENTER", 0x0D, "Enter")
add_keyboard("PAUSE", 0x13, "Pause")
add_keyboard("CAPS_LOCK", 0x14, "CapsLock")
add_keyboard("ESCAPE", 0x1B, "Esc")
add_keyboard("SPACE", 0x20, "Space")
add_keyboard("PAGE_UP", 0x21, "PageUp")
add_keyboard("PAGE_DOWN", 0x22, "PageDown")
add_keyboard("END", 0x23, "End")
add_keyboard("HOME", 0x24, "Home")
add_keyboard("LEFT", 0x25, "Left")
add_keyboard("UP", 0x26, "Up")
add_keyboard("RIGHT", 0x27, "Right")
add_keyboard("DOWN", 0x28, "Down")
add_keyboard("INSERT", 0x2D, "Insert")
add_keyboard("DELETE", 0x2E, "Delete")
add_keyboard("NUMPAD_MULTIPLY", 0x6A, "NumAsterisk")
add_keyboard("NUMPAD_ADD", 0x6B, "NumPlus")
add_keyboard("NUMPAD_SUBTRACT", 0x6D, "NumMinus")
add_keyboard("NUMPAD_DECIMAL", 0x6E, "NumPeriod")
add_keyboard("NUMPAD_DIVIDE", 0x6F, "NumSlash")
add_keyboard("SEMICOLON", 0xBA, "Semicolon")
add_keyboard("EQUALS", 0xBB, "And")
add_keyboard("COMMA", 0xBC, "Comma")
add_keyboard("MINUS", 0xBD, "Hyphen")
add_keyboard("PERIOD", 0xBE, "Period")
add_keyboard("SLASH", 0xBF, "Slash")
add_keyboard("TILDE", 0xC0, "Tilde")
add_keyboard("LEFT_BRACKET", 0xDB, "LeftBracket")
add_keyboard("BACKSLASH", 0xDC, "Backslash")
add_keyboard("RIGHT_BRACKET", 0xDD, "RightBracket")
add_keyboard("APOSTROPHE", 0xDE, "Apostrophe")

-- Names and casing match the FModel export under
-- Pal/Content/Pal/Texture/UI/KeyGuide/mouse.
add_mouse("LEFT_MOUSE", 0x01, "T_MenuKeyGuide_MouseButtonLeft")
add_mouse("RIGHT_MOUSE", 0x02, "T_MenuKeyGuide_MouseButtonRight")
add_mouse("MIDDLE_MOUSE", 0x04, "T_MenuKeyGuide_MouseWheelButton")
add_mouse("MOUSE_BUTTON_4", 0x05, "T_MenuKeyGuide_MouseButton4")
add_mouse("MOUSE_BUTTON_5", 0x06, "T_MenuKeyGuide_MouseButton5")

local aliases = {
    ADD = "NUMPAD_ADD",
    BACK = "BACKSPACE",
    CAPSLOCK = "CAPS_LOCK",
    CTRL = "CONTROL",
    DECIMAL = "NUMPAD_DECIMAL",
    DIVIDE = "NUMPAD_DIVIDE",
    ESC = "ESCAPE",
    LEFTMOUSEBUTTON = "LEFT_MOUSE",
    LEFT_MOUSE_BUTTON = "LEFT_MOUSE",
    MMB = "MIDDLE_MOUSE",
    MIDDLEMOUSEBUTTON = "MIDDLE_MOUSE",
    MIDDLE_MOUSE_BUTTON = "MIDDLE_MOUSE",
    MOUSE_MIDDLE = "MIDDLE_MOUSE",
    MOUSEBUTTON4 = "MOUSE_BUTTON_4",
    MOUSEBUTTON5 = "MOUSE_BUTTON_5",
    MULTIPLY = "NUMPAD_MULTIPLY",
    ZERO = "0",
    ONE = "1",
    TWO = "2",
    THREE = "3",
    FOUR = "4",
    FIVE = "5",
    SIX = "6",
    SEVEN = "7",
    EIGHT = "8",
    NINE = "9",
    NUM_ZERO = "NUMPAD_0",
    NUM_ONE = "NUMPAD_1",
    NUM_TWO = "NUMPAD_2",
    NUM_THREE = "NUMPAD_3",
    NUM_FOUR = "NUMPAD_4",
    NUM_FIVE = "NUMPAD_5",
    NUM_SIX = "NUMPAD_6",
    NUM_SEVEN = "NUMPAD_7",
    NUM_EIGHT = "NUMPAD_8",
    NUM_NINE = "NUMPAD_9",
    LEFTBRACKET = "LEFT_BRACKET",
    NUMPAD0 = "NUMPAD_0",
    NUMPAD1 = "NUMPAD_1",
    NUMPAD2 = "NUMPAD_2",
    NUMPAD3 = "NUMPAD_3",
    NUMPAD4 = "NUMPAD_4",
    NUMPAD5 = "NUMPAD_5",
    NUMPAD6 = "NUMPAD_6",
    NUMPAD7 = "NUMPAD_7",
    NUMPAD8 = "NUMPAD_8",
    NUMPAD9 = "NUMPAD_9",
    NUMPADADD = "NUMPAD_ADD",
    NUMPADDECIMAL = "NUMPAD_DECIMAL",
    NUMPADDIVIDE = "NUMPAD_DIVIDE",
    NUMPADEIGHT = "NUMPAD_8",
    NUMPADFIVE = "NUMPAD_5",
    NUMPADFOUR = "NUMPAD_4",
    NUMPADNINE = "NUMPAD_9",
    NUMPADONE = "NUMPAD_1",
    NUMPADSUBTRACT = "NUMPAD_SUBTRACT",
    NUMPADMULTIPLY = "NUMPAD_MULTIPLY",
    NUMPADSEVEN = "NUMPAD_7",
    NUMPADSIX = "NUMPAD_6",
    NUMPADTHREE = "NUMPAD_3",
    NUMPADTWO = "NUMPAD_2",
    NUMPADZERO = "NUMPAD_0",
    NUMPAD_MINUS = "NUMPAD_SUBTRACT",
    NUMPAD_PLUS = "NUMPAD_ADD",
    PAGEDOWN = "PAGE_DOWN",
    PAGEUP = "PAGE_UP",
    PGDN = "PAGE_DOWN",
    PGUP = "PAGE_UP",
    INS = "INSERT",
    DEL = "DELETE",
    RETURN = "ENTER",
    RIGHTMOUSEBUTTON = "RIGHT_MOUSE",
    RIGHT_MOUSE_BUTTON = "RIGHT_MOUSE",
    RIGHTBRACKET = "RIGHT_BRACKET",
    SPACEBAR = "SPACE",
    SUBTRACT = "NUMPAD_SUBTRACT",
    THUMBMOUSEBUTTON = "MOUSE_BUTTON_4",
    THUMBMOUSEBUTTON2 = "MOUSE_BUTTON_5",
    XBUTTON1 = "MOUSE_BUTTON_4",
    XBUTTON2 = "MOUSE_BUTTON_5",
    HYPHEN = "MINUS",
}

local defaults = {
    move_left = { key = "NUMPAD_4" },
    move_right = { key = "NUMPAD_6" },
    move_forward = { key = "NUMPAD_8" },
    move_back = { key = "NUMPAD_2" },
    move_up = { key = "NUMPAD_3" },
    move_down = { key = "NUMPAD_1" },
    reset = { key = "NUMPAD_5" },
    rotate_left = { key = "NUMPAD_7" },
    rotate_right = { key = "NUMPAD_9" },
    step_down = { key = "NUMPAD_SUBTRACT" },
    step_up = { key = "NUMPAD_ADD" },
    toggle_freeze = { key = "MIDDLE_MOUSE" },
    copy_piece = { key = "MIDDLE_MOUSE", modifiers = { "SHIFT" } },
}

local action_order = {
    "move_left",
    "move_right",
    "move_forward",
    "move_back",
    "move_up",
    "move_down",
    "reset",
    "rotate_left",
    "rotate_right",
    "step_down",
    "step_up",
    "toggle_freeze",
    "copy_piece",
}

local modifier_assets = {
    SHIFT = {
        texture_path = KEYBOARD_ROOT .. "T_KeyGuide_Keyboard_shift",
        texture_object_path = KEYBOARD_ROOT
            .. "T_KeyGuide_Keyboard_shift.T_KeyGuide_Keyboard_shift",
    },
    CONTROL = {
        texture_path = KEYBOARD_ROOT .. "T_KeyGuide_Keyboard_Ctrl",
        texture_object_path = KEYBOARD_ROOT
            .. "T_KeyGuide_Keyboard_Ctrl.T_KeyGuide_Keyboard_Ctrl",
    },
    ALT = {
        texture_path = KEYBOARD_ROOT .. "T_KeyGuide_Keyboard_Alt",
        texture_object_path = KEYBOARD_ROOT
            .. "T_KeyGuide_Keyboard_Alt.T_KeyGuide_Keyboard_Alt",
    },
}

-- Keep modifier order stable across config.lua, DarnMenu, conflict
-- signatures, UE4SS registration, and the companion widget.
local modifier_order = { "CONTROL", "ALT", "SHIFT" }

local function canonical_name(value)
    if type(value) ~= "string" then
        return nil
    end
    local name = string.upper(value)
    name = string.gsub(name, "[%s%-]+", "_")
    return aliases[name] or name
end

local function copy_list(source)
    local result = {}
    if type(source) == "table" then
        for _, value in ipairs(source) do
            result[#result + 1] = value
        end
    end
    return result
end

local function same_spec(left, right)
    if left.key ~= right.key then
        return false
    end
    if #left.modifiers ~= #right.modifiers then
        return false
    end
    for index, value in ipairs(left.modifiers) do
        if value ~= right.modifiers[index] then
            return false
        end
    end
    return true
end

local function signature(binding)
    return table.concat(binding.modifiers, "+") .. ":" .. binding.key
end

local function parse_spec(action, raw_spec, report)
    local spec = raw_spec
    if type(spec) == "string" then
        spec = { key = spec }
    end
    if type(spec) ~= "table" then
        report(string.format(
            "Binding '%s' must be a key name or table; using its default.",
            action
        ))
        spec = defaults[action]
    end

    local key_name = canonical_name(spec.key)
    if key_name == nil or keys[key_name] == nil then
        report(string.format(
            "Binding '%s' has unknown key '%s'; using %s.",
            action,
            tostring(spec.key),
            defaults[action].key
        ))
        spec = defaults[action]
        key_name = spec.key
    end

    local requested_modifiers = {}
    for _, raw_modifier in ipairs(copy_list(spec.modifiers)) do
        local modifier = canonical_name(raw_modifier)
        if modifier_assets[modifier] == nil then
            report(string.format(
                "Binding '%s' has unknown modifier '%s'; ignoring it.",
                action,
                tostring(raw_modifier)
            ))
        else
            requested_modifiers[modifier] = true
        end
    end
    local modifiers = {}
    for _, modifier in ipairs(modifier_order) do
        if requested_modifiers[modifier] then
            modifiers[#modifiers + 1] = modifier
        end
    end

    return {
        action = action,
        key = key_name,
        modifiers = modifiers,
        key_info = keys[key_name],
        is_default = same_spec(
            { key = key_name, modifiers = modifiers },
            {
                key = defaults[action].key,
                modifiers = copy_list(defaults[action].modifiers),
            }
        ),
    }
end

function M.resolve(configured_bindings, report)
    local report_message = report or function() end
    local source = type(configured_bindings) == "table" and configured_bindings or {}
    local parsed = {}

    for _, action in ipairs(action_order) do
        parsed[action] = parse_spec(
            action,
            source[action] ~= nil and source[action] or defaults[action],
            report_message
        )
    end

    -- Reserve unchanged defaults first. A custom binding cannot silently steal
    -- a default binding from another action.
    local claimed = {}
    local resolved = {}
    for pass = 1, 2 do
        for _, action in ipairs(action_order) do
            local binding = parsed[action]
            if (pass == 1 and binding.is_default) or (pass == 2 and not binding.is_default) then
                local binding_signature = signature(binding)
                local conflict = claimed[binding_signature]
                if conflict ~= nil then
                    report_message(string.format(
                        "Binding '%s' conflicts with '%s'; using its default.",
                        action,
                        conflict
                    ))
                    binding = parse_spec(action, defaults[action], report_message)
                    binding_signature = signature(binding)
                    conflict = claimed[binding_signature]
                end
                if conflict ~= nil then
                    binding.disabled = true
                    report_message(string.format(
                        "Binding '%s' is disabled because its default also conflicts with '%s'.",
                        action,
                        conflict
                    ))
                else
                    claimed[binding_signature] = action
                end
                resolved[action] = binding
            end
        end
    end

    return resolved
end

function M.get_modifier_asset(modifier)
    return modifier_assets[modifier]
end

function M.get_key_info(key)
    return keys[canonical_name(key)]
end

M.action_order = action_order
M.defaults = defaults
M.modifier_order = modifier_order

return M
