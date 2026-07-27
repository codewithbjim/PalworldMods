-- Optional DarnMenu integration for Perfect Placement.
--
-- DarnMenu writes player changes to Mods/shared/PerfectPlacement_user.lua.
-- config.lua remains the baseline when no saved player override is available.

local M = {}

local SCHEMA_NAME = "PerfectPlacement"
local USER_CONFIG_NAME = "PerfectPlacement_user"
local SCHEMA_VERSION = 12

local SUPPORTED_ACTIONS = {
    move_left = true,
    move_right = true,
    move_forward = true,
    move_back = true,
    move_up = true,
    move_down = true,
    rotate_left = true,
    rotate_right = true,
    reset = true,
    step_down = true,
    step_up = true,
    toggle_freeze = true,
    copy_piece = true,
    freeze_to_piece = true,
}

-- DarnMenu 1.6.2's keychord control stores a primary UE4SS key name plus
-- CONTROL/ALT/SHIFT toggles. keybindings.lua canonicalizes those names.
local SCHEMA_SOURCE = [==[
return {
  schemaVersion = 12,
  tab = "Perfect Placement",
  order = 100,
  target = "PerfectPlacement_user",
  note = "Optional integration for DarnMenu 1.6.2 or newer. Bindings apply after restarting Palworld.",
  applyNote = "Saved. Restart Palworld to apply binding changes.",
  live = false,
  defaults = {
    toggle_freeze = { key = "MIDDLE_MOUSE_BUTTON", modifiers = {} },
    copy_piece = { key = "MIDDLE_MOUSE_BUTTON", modifiers = { "SHIFT" } },
    freeze_to_piece = {
      key = "MIDDLE_MOUSE_BUTTON", modifiers = { "CONTROL", "SHIFT" }
    },
    move_left = { key = "NUM_FOUR", modifiers = {} },
    move_right = { key = "NUM_SIX", modifiers = {} },
    move_forward = { key = "NUM_EIGHT", modifiers = {} },
    move_back = { key = "NUM_TWO", modifiers = {} },
    move_up = { key = "NUM_THREE", modifiers = {} },
    move_down = { key = "NUM_ONE", modifiers = {} },
    rotate_left = { key = "NUM_SEVEN", modifiers = {} },
    rotate_right = { key = "NUM_NINE", modifiers = {} },
    reset = { key = "NUM_FIVE", modifiers = {} },
    step_down = { key = "SUBTRACT", modifiers = {} },
    step_up = { key = "ADD", modifiers = {} },
    movement_start_cm = 10.0,
    movement_minimum_cm = 0.1,
    movement_maximum_cm = 1000.0,
    movement_step_scale = 10,
    movement_maximum_below_cm = 25.0,
    movement_maximum_above_cm = 650.0,
    refresh_frozen_validity = false,
    use_palworld_keycaps = true,
    verbose_logging = false,
  },
  sections = {
    { title = "Preview", options = {
      { path = "toggle_freeze", label = "Freeze or unfreeze preview", kind = "keychord" },
      { path = "copy_piece", label = "Copy targeted build piece", kind = "keychord" },
      { path = "freeze_to_piece", label = "Copy and freeze to targeted piece",
        kind = "keychord" },
      { path = "refresh_frozen_validity", label = "Live frozen validity feedback",
        kind = "bool",
        help = "Experimental. Repaints valid/error state after movement and may cause stutter." },
    }},
    { title = "Movement bindings", options = {
      { path = "move_left", label = "Move left", kind = "keychord" },
      { path = "move_right", label = "Move right", kind = "keychord" },
      { path = "move_forward", label = "Move forward", kind = "keychord" },
      { path = "move_back", label = "Move back", kind = "keychord" },
      { path = "move_up", label = "Move up", kind = "keychord" },
      { path = "move_down", label = "Move down", kind = "keychord" },
    }},
    { title = "Rotation and step bindings", options = {
      { path = "rotate_left", label = "Rotate left", kind = "keychord" },
      { path = "rotate_right", label = "Rotate right", kind = "keychord" },
      { path = "reset", label = "Reset transform", kind = "keychord" },
      { path = "step_down", label = "Decrease move step", kind = "keychord" },
      { path = "step_up", label = "Increase move step", kind = "keychord" },
    }},
    { title = "Movement settings", options = {
      { path = "movement_start_cm", label = "Starting movement step", kind = "number",
        min = 0.1, max = 1000, step = 0.1, help = "In centimeters." },
      { path = "movement_step_scale", label = "Step multiplier", kind = "enum",
        values = {
          { value = 2, label = "×2" },
          { value = 5, label = "×5" },
          { value = 10, label = "×10" },
        } },
      { subtitle = "Advanced step limits",
        help = "The minimum must not exceed the maximum." },
      { path = "movement_minimum_cm", label = "Minimum movement step", kind = "number",
        min = 0.1, max = 1000, step = 0.1, help = "In centimeters." },
      { path = "movement_maximum_cm", label = "Maximum movement step", kind = "number",
        min = 0.1, max = 1000, step = 1, help = "In centimeters." },
      { path = "movement_maximum_below_cm", label = "Maximum movement below origin",
        kind = "number", min = 0, max = 1000, step = 5,
        help = "In centimeters." },
      { path = "movement_maximum_above_cm", label = "Maximum movement above origin",
        kind = "number", min = 0, max = 5000, step = 10,
        help = "In centimeters." },
    }},
    { title = "Diagnostics", options = {
      { path = "verbose_logging", label = "Verbose UE4SS logging", kind = "bool",
        help = "Enable only while diagnosing a problem; this can produce many log lines." },
    }},
  },
}
]==]

local SETTING_SPECS = {
    movement_start_cm = {
        section = "movement", field = "normal", kind = "number",
        minimum = 0.1, maximum = 1000.0,
    },
    movement_minimum_cm = {
        section = "movement", field = "minimum", kind = "number",
        minimum = 0.1, maximum = 1000.0,
    },
    movement_maximum_cm = {
        section = "movement", field = "maximum", kind = "number",
        minimum = 0.1, maximum = 1000.0,
    },
    movement_step_scale = {
        section = "movement", field = "step_scale", kind = "enum",
        allowed = { [2] = true, [5] = true, [10] = true },
    },
    movement_maximum_below_cm = {
        section = "movement", field = "maximum_below_initial_cm", kind = "number",
        minimum = 0.0, maximum = 1000.0,
    },
    movement_maximum_above_cm = {
        section = "movement", field = "maximum_above_initial_cm", kind = "number",
        minimum = 0.0, maximum = 5000.0,
    },
    refresh_frozen_validity = {
        section = "validity", field = "refresh_frozen_feedback", kind = "boolean",
    },
    use_palworld_keycaps = {
        section = "ui", field = "use_palworld_keycaps", kind = "boolean",
    },
    verbose_logging = {
        section = "diagnostics", field = "verbose", kind = "boolean",
    },
}

local function script_directory()
    if debug == nil or debug.getinfo == nil then
        return nil
    end
    local source = debug.getinfo(1, "S").source
    if type(source) ~= "string" or string.sub(source, 1, 1) ~= "@" then
        return nil
    end
    return string.match(string.sub(source, 2), "^(.*[\\/])")
end

local function shared_directory()
    local directory = script_directory()
    return directory ~= nil and directory .. "..\\..\\shared\\" or nil
end

local function read_table(path)
    local chunk = loadfile(path)
    if chunk == nil then
        return nil
    end
    local ok, value = pcall(chunk)
    return ok and type(value) == "table" and value or nil
end

local function write_file_if_changed(path, source)
    local existing = io.open(path, "rb")
    if existing ~= nil then
        local content = existing:read("*a")
        existing:close()
        if content == source then
            return true
        end
    end
    local file = io.open(path, "wb")
    if file == nil then
        return false
    end
    local ok = pcall(function()
        file:write(source)
    end)
    file:close()
    return ok
end

local function serialize_index(names)
    local result = { "return {\n" }
    for _, name in ipairs(names) do
        result[#result + 1] = string.format("  %q,\n", name)
    end
    result[#result + 1] = "}\n"
    return table.concat(result)
end

function M.register(report)
    local report_message = report or function() end
    local shared = shared_directory()
    if shared == nil then
        report_message("DarnMenu schema registration skipped: script path is unavailable.")
        return false
    end

    local schema_path = shared .. "DarnMenu_schema_" .. SCHEMA_NAME .. ".lua"
    if not write_file_if_changed(schema_path, SCHEMA_SOURCE) then
        return false
    end

    local index_path = shared .. "DarnMenu_schema_index.lua"
    local names = read_table(index_path)
    if names == nil then
        local existing = io.open(index_path, "rb")
        if existing ~= nil then
            existing:close()
            report_message("DarnMenu schema index is unreadable; leaving it unchanged.")
            return false
        end
        names = {}
    end
    for _, name in ipairs(names) do
        if name == SCHEMA_NAME then
            return true
        end
    end
    names[#names + 1] = SCHEMA_NAME
    if not write_file_if_changed(index_path, serialize_index(names)) then
        report_message("DarnMenu schema index could not be updated.")
        return false
    end
    report_message("Registered Perfect Placement options with DarnMenu.")
    return true
end

local function copy_binding(raw)
    if type(raw) == "string" then
        return { key = raw }
    end
    if type(raw) ~= "table" or type(raw.key) ~= "string" then
        return nil
    end
    local binding = { key = raw.key, modifiers = {} }
    if type(raw.modifiers) == "table" then
        for _, modifier in ipairs(raw.modifiers) do
            if type(modifier) == "string" then
                binding.modifiers[#binding.modifiers + 1] = modifier
            end
        end
    end
    return binding
end

local function number_is_finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function M.apply_settings(config, report)
    if type(config) ~= "table" then
        return 0
    end
    local shared = shared_directory()
    local user = shared ~= nil
        and read_table(shared .. USER_CONFIG_NAME .. ".lua")
        or nil
    if user == nil then
        return 0
    end

    local report_message = report or function() end
    local original_minimum = config.movement.minimum
    local original_maximum = config.movement.maximum
    local loaded_count = 0
    for path, spec in pairs(SETTING_SPECS) do
        local value = user[path]
        if value ~= nil then
            local valid = false
            if spec.kind == "boolean" then
                valid = type(value) == "boolean"
            elseif spec.kind == "number" then
                valid = number_is_finite(value)
                    and value >= spec.minimum
                    and value <= spec.maximum
            elseif spec.kind == "enum" then
                valid = spec.allowed[value] == true
            end

            local section = config[spec.section]
            if valid and type(section) == "table" then
                section[spec.field] = value
                loaded_count = loaded_count + 1
            else
                report_message(string.format(
                    "DarnMenu setting '%s' is invalid; using config.lua default.",
                    path
                ))
            end
        end
    end

    if config.movement.minimum > config.movement.maximum then
        config.movement.minimum = original_minimum
        config.movement.maximum = original_maximum
        report_message(
            "DarnMenu movement minimum exceeds maximum; both limits use config.lua defaults."
        )
    end
    config.movement.normal = math.max(
        config.movement.minimum,
        math.min(config.movement.maximum, config.movement.normal)
    )

    if loaded_count > 0 then
        report_message(string.format(
            "Loaded %d DarnMenu settings (schema v%d).",
            loaded_count,
            SCHEMA_VERSION
        ))
    end
    return loaded_count
end

function M.load(action_order, report)
    local shared = shared_directory()
    if shared == nil then
        return nil
    end
    local user = read_table(shared .. USER_CONFIG_NAME .. ".lua")
    if user == nil then
        return nil
    end

    local bindings = {}
    local loaded_count = 0
    for _, action in ipairs(action_order) do
        local binding = copy_binding(user[action])
        if SUPPORTED_ACTIONS[action] and binding ~= nil then
            bindings[action] = binding
            loaded_count = loaded_count + 1
        end
    end
    if loaded_count == 0 then
        return nil
    end

    local report_message = report or function() end
    report_message(string.format(
        "Loaded %d DarnMenu bindings from Mods/shared/%s.lua (schema v%d).",
        loaded_count,
        USER_CONFIG_NAME,
        SCHEMA_VERSION
    ))
    return bindings
end

return M
