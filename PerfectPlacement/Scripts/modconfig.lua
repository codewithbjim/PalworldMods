-- Minimal Mod Config Menu reader for PerfectPlacement.modconfig.json.
--
-- The menu owns the JSON file and updates each option's "live" chord. Perfect
-- Placement reads those values once during startup because UE4SS does not
-- provide a safe way to unregister and replace key binds while the mod runs.

local M = {}

local function append_utf8(result, codepoint)
    if codepoint <= 0x7F then
        result[#result + 1] = string.char(codepoint)
    elseif codepoint <= 0x7FF then
        result[#result + 1] = string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0xFFFF then
        result[#result + 1] = string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    else
        result[#result + 1] = string.char(
            0xF0 + math.floor(codepoint / 0x40000),
            0x80 + (math.floor(codepoint / 0x1000) % 0x40),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end
end

local function decode_utf16(document, big_endian)
    local result = {}
    local index = 3
    while index + 1 <= #document do
        local first = string.byte(document, index)
        local second = string.byte(document, index + 1)
        local codepoint = big_endian
            and ((first * 0x100) + second)
            or (first + (second * 0x100))
        index = index + 2

        if codepoint >= 0xD800
            and codepoint <= 0xDBFF
            and index + 1 <= #document
        then
            local low_first = string.byte(document, index)
            local low_second = string.byte(document, index + 1)
            local low = big_endian
                and ((low_first * 0x100) + low_second)
                or (low_first + (low_second * 0x100))
            if low >= 0xDC00 and low <= 0xDFFF then
                codepoint = 0x10000
                    + ((codepoint - 0xD800) * 0x400)
                    + (low - 0xDC00)
                index = index + 2
            end
        end

        append_utf8(result, codepoint)
    end
    return table.concat(result)
end

local function decode_document(document)
    if string.sub(document, 1, 2) == "\255\254" then
        return decode_utf16(document, false), "UTF-16LE"
    end
    if string.sub(document, 1, 2) == "\254\255" then
        return decode_utf16(document, true), "UTF-16BE"
    end
    if string.sub(document, 1, 3) == "\239\187\191" then
        return string.sub(document, 4), "UTF-8 BOM"
    end
    return document, "UTF-8"
end

local function escape_pattern(value)
    return string.gsub(value, "([^%w])", "%%%1")
end

local function find_object_for_key(document, key)
    local _, marker_end = string.find(
        document,
        '"' .. escape_pattern(key) .. '"%s*:%s*'
    )
    if marker_end == nil then
        return nil
    end

    local object_start = string.find(document, "{", marker_end + 1, true)
    if object_start == nil then
        return nil
    end

    local depth = 0
    local in_string = false
    local escaped = false
    for index = object_start, #document do
        local character = string.sub(document, index, index)
        if in_string then
            if escaped then
                escaped = false
            elseif character == "\\" then
                escaped = true
            elseif character == '"' then
                in_string = false
            end
        elseif character == '"' then
            in_string = true
        elseif character == "{" then
            depth = depth + 1
        elseif character == "}" then
            depth = depth - 1
            if depth == 0 then
                return string.sub(document, object_start, index)
            end
        end
    end
    return nil
end

local function string_field(object_text, field)
    return string.match(
        object_text,
        '"' .. escape_pattern(field) .. '"%s*:%s*"([^"]+)"'
    )
end

local function boolean_field(object_text, field)
    local value = string.match(
        object_text,
        '"' .. escape_pattern(field) .. '"%s*:%s*(%a+)'
    )
    return value == "true"
end

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

local function read_config_file(filename)
    local candidates = {}
    local source_directory = script_directory()
    if source_directory ~= nil then
        candidates[#candidates + 1] = source_directory .. "..\\" .. filename
        candidates[#candidates + 1] = source_directory .. "../" .. filename
    end
    candidates[#candidates + 1] = "ue4ss\\Mods\\PerfectPlacement\\" .. filename
    candidates[#candidates + 1] = "Mods\\PerfectPlacement\\" .. filename

    for _, path in ipairs(candidates) do
        local file = io.open(path, "rb")
        if file ~= nil then
            local content = file:read("*a")
            file:close()
            local decoded, encoding = decode_document(content)
            return decoded, path, encoding
        end
    end
    return nil, nil
end

function M.load(filename, action_order, report)
    local report_message = report or function() end
    local document, path, encoding = read_config_file(filename)
    if document == nil then
        report_message("Mod Config Menu file was not found; using config.lua bindings.")
        return nil
    end

    local bindings = {}
    local loaded_count = 0
    for _, action in ipairs(action_order) do
        local option_object = find_object_for_key(document, action)
        -- Preserve existing user settings from the pre-Freeze terminology.
        if option_object == nil and action == "toggle_freeze" then
            option_object = find_object_for_key(document, "toggle_lock")
        end
        local live_object = option_object ~= nil
            and find_object_for_key(option_object, "live")
            or nil
        local key = live_object ~= nil and string_field(live_object, "key") or nil
        if key ~= nil then
            local modifiers = {}
            if boolean_field(live_object, "bCtrl") then
                modifiers[#modifiers + 1] = "CONTROL"
            end
            if boolean_field(live_object, "bAlt") then
                modifiers[#modifiers + 1] = "ALT"
            end
            if boolean_field(live_object, "bShift") then
                modifiers[#modifiers + 1] = "SHIFT"
            end
            if boolean_field(live_object, "bCmd") then
                report_message(
                    "Binding '" .. action .. "' uses unsupported Command modifier; ignoring it."
                )
            end
            bindings[action] = {
                key = key,
                modifiers = modifiers,
            }
            loaded_count = loaded_count + 1
        end
    end

    if loaded_count == 0 then
        report_message("Mod Config Menu file contains no readable live keybinds.")
        return nil
    end
    report_message(string.format(
        "Loaded %d Mod Config Menu bindings from %s (%s).",
        loaded_count,
        path,
        encoding
    ))
    return bindings
end

M.decode_document = decode_document

return M
