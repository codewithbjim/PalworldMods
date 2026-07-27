-- Optional DarnMenu integration for Perfect Placement.
--
-- DarnMenu writes player changes to Mods/shared/PerfectPlacement_user.lua.
-- config.lua remains the standalone baseline when DarnMenu is not installed.

local M = {}

local SCHEMA_NAME = "PerfectPlacement"
local USER_CONFIG_NAME = "PerfectPlacement_user"
local SCHEMA_VERSION = 5

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
}

-- DarnMenu 1.6.2's keychord control stores a primary UE4SS key name plus
-- CONTROL/ALT/SHIFT toggles. keybindings.lua canonicalizes those names.
local SCHEMA_SOURCE = [==[
return {
  schemaVersion = 5,
  tab = "Perfect Placement",
  order = 100,
  target = "PerfectPlacement_user",
  note = "Requires DarnMenu 1.6.2 or newer. Bindings apply after restarting Palworld.",
  applyNote = "Saved. Restart Palworld to apply binding changes.",
  live = false,
  defaults = {
    toggle_freeze = { key = "MIDDLE_MOUSE_BUTTON", modifiers = {} },
    copy_piece = { key = "MIDDLE_MOUSE_BUTTON", modifiers = { "SHIFT" } },
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
  },
  sections = {
    { title = "Preview", options = {
      { path = "toggle_freeze", label = "Freeze or unfreeze preview", kind = "keychord" },
      { path = "copy_piece", label = "Copy targeted build piece", kind = "keychord" },
    }},
    { title = "Movement", options = {
      { path = "move_left", label = "Move left", kind = "keychord" },
      { path = "move_right", label = "Move right", kind = "keychord" },
      { path = "move_forward", label = "Move forward", kind = "keychord" },
      { path = "move_back", label = "Move back", kind = "keychord" },
      { path = "move_up", label = "Move up", kind = "keychord" },
      { path = "move_down", label = "Move down", kind = "keychord" },
    }},
    { title = "Rotation and step", options = {
      { path = "rotate_left", label = "Rotate left", kind = "keychord" },
      { path = "rotate_right", label = "Rotate right", kind = "keychord" },
      { path = "reset", label = "Reset transform", kind = "keychord" },
      { path = "step_down", label = "Decrease move step", kind = "keychord" },
      { path = "step_up", label = "Increase move step", kind = "keychord" },
    }},
  },
}
]==]

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
