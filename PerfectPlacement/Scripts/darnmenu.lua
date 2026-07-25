-- Optional DarnMenu integration for Perfect Placement.
--
-- DarnMenu stores only player-changed values in Mods/shared. config.lua
-- remains the baseline, while DarnMenu values override only the actions the
-- player explicitly changed there.

local M = {}

local SCHEMA_NAME = "PerfectPlacement"
local USER_CONFIG_NAME = "PerfectPlacement_user"
local SCHEMA_VERSION = 4

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

local SCHEMA_SOURCE = [==[
return {
  schemaVersion = 4,
  tab = "Perfect Placement",
  order = 100,
  target = "PerfectPlacement_user",
  note = "Bindings apply after restarting Palworld.",
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
      { path = "toggle_freeze", label = "Freeze or unfreeze preview",
        kind = "keychord" },
      { path = "copy_piece", label = "Copy targeted build piece",
        kind = "keychord" },
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

local LEGACY_SCHEMA_SOURCE = [==[
return {
  schemaVersion = 2,
  tab = "Perfect Placement",
  order = 100,
  target = "PerfectPlacement_user",
  note = "Bindings apply after restarting Palworld. Update DarnMenu to edit Ctrl, Alt, or Shift chords and the Copy binding.",
  applyNote = "Saved. Restart Palworld to apply binding changes.",
  live = false,
  defaults = {
    toggle_freeze = "MIDDLE_MOUSE_BUTTON",
    move_left = "NUM_FOUR",
    move_right = "NUM_SIX",
    move_forward = "NUM_EIGHT",
    move_back = "NUM_TWO",
    move_up = "NUM_THREE",
    move_down = "NUM_ONE",
    rotate_left = "NUM_SEVEN",
    rotate_right = "NUM_NINE",
    reset = "NUM_FIVE",
    step_down = "SUBTRACT",
    step_up = "ADD",
  },
  sections = {
    { title = "Preview", options = {
      { path = "toggle_freeze", label = "Freeze or unfreeze preview",
        kind = "keycapture",
        help = "Mouse buttons 1-5 and DarnMenu's supported keyboard keys." },
    }},
    { title = "Movement", options = {
      { path = "move_left", label = "Move left", kind = "keycapture" },
      { path = "move_right", label = "Move right", kind = "keycapture" },
      { path = "move_forward", label = "Move forward", kind = "keycapture" },
      { path = "move_back", label = "Move back", kind = "keycapture" },
      { path = "move_up", label = "Move up", kind = "keycapture" },
      { path = "move_down", label = "Move down", kind = "keycapture" },
    }},
    { title = "Rotation and step", options = {
      { path = "rotate_left", label = "Rotate left", kind = "keycapture" },
      { path = "rotate_right", label = "Rotate right", kind = "keycapture" },
      { path = "reset", label = "Reset transform", kind = "keycapture" },
      { path = "step_down", label = "Decrease move step", kind = "keycapture" },
      { path = "step_up", label = "Increase move step", kind = "keycapture",
        help = "DarnMenu supports F1-F12, letters, digits, numpad keys, Ins/Del/Home/End/PgUp/PgDn, and mouse buttons 1-5." },
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
    if directory == nil then
        return nil
    end
    return directory .. "..\\..\\shared\\"
end

local function read_table(path)
    local chunk = loadfile(path)
    if chunk == nil then
        return nil
    end
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= "table" then
        return nil
    end
    return value
end

local function write_schema(path, source)
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
    file:write(source)
    file:close()
    return true
end

local function write_index(path, names)
    local file = io.open(path, "wb")
    if file == nil then
        return false
    end
    file:write("return {\n")
    for _, name in ipairs(names) do
        file:write(string.format("  %q,\n", name))
    end
    file:write("}\n")
    file:close()
    return true
end

function M.register(report)
    local report_message = report or function() end
    local shared = shared_directory()
    if shared == nil then
        report_message("DarnMenu schema registration skipped: script path is unavailable.")
        return false
    end

    local schema_path = shared .. "DarnMenu_schema_" .. SCHEMA_NAME .. ".lua"
    local caps = read_table(shared .. "DarnMenu_caps.lua")
    local caps_revision = caps ~= nil and tonumber(caps.rev) or 0
    local supports_keychord = caps ~= nil
        and (caps.keychord == true or caps_revision >= 4)
    local schema_source = supports_keychord
        and SCHEMA_SOURCE
        or LEGACY_SCHEMA_SOURCE
    if not write_schema(schema_path, schema_source) then
        -- Expected when neither DarnMenu nor its shared directory is installed.
        -- Perfect Placement remains fully functional.
        return false
    end

    local index_path = shared .. "DarnMenu_schema_index.lua"
    local names = read_table(index_path)
    if names == nil then
        local existing_index = io.open(index_path, "rb")
        if existing_index ~= nil then
            existing_index:close()
            report_message(
                "DarnMenu schema index is unreadable; leaving it unchanged."
            )
            return false
        end
        names = {}
    end
    local found = false
    for _, name in ipairs(names) do
        if name == SCHEMA_NAME then
            found = true
            break
        end
    end
    if not found then
        names[#names + 1] = SCHEMA_NAME
        if not write_index(index_path, names) then
            report_message("DarnMenu schema index could not be updated.")
            return false
        end
    end
    if not supports_keychord then
        report_message(
            "Installed DarnMenu does not expose key-chord editing; "
                .. "using the legacy single-input page."
        )
    end
    return true
end

local function copy_darnmenu_binding(raw)
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

    -- Also accept the boolean shape used by some older config UIs. The main
    -- keybinding resolver canonicalizes aliases, removes duplicates, and keeps
    -- CONTROL, ALT, SHIFT in a stable order.
    if raw.control == true or raw.ctrl == true
        or raw.bControl == true or raw.bCtrl == true then
        binding.modifiers[#binding.modifiers + 1] = "CONTROL"
    end
    if raw.alt == true or raw.bAlt == true then
        binding.modifiers[#binding.modifiers + 1] = "ALT"
    end
    if raw.shift == true or raw.bShift == true then
        binding.modifiers[#binding.modifiers + 1] = "SHIFT"
    end
    return binding
end

function M.load(action_order, report)
    local report_message = report or function() end
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
        local binding = copy_darnmenu_binding(user[action])
        if SUPPORTED_ACTIONS[action] and binding ~= nil then
            bindings[action] = binding
            loaded_count = loaded_count + 1
        end
    end
    if loaded_count == 0 then
        return nil
    end

    report_message(string.format(
        "Loaded %d DarnMenu bindings from Mods/shared/%s.lua (schema v%d).",
        loaded_count,
        USER_CONFIG_NAME,
        SCHEMA_VERSION
    ))
    return bindings
end

return M
