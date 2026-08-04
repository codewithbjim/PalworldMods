local Servers = {}

local source_path = debug.getinfo(1, "S").source:gsub("^@", "")
local script_directory = source_path:match("^(.*[\\/])") or ""
local config_path = script_directory .. "config.lua"
local MAX_NAME_BYTES = 128
local MAX_GUID_BYTES = 128
local MAX_PASSWORD_BYTES = 512

local function trimmed(value)
    if type(value) ~= "string" then
        return nil
    end
    return value:match("^%s*(.-)%s*$")
end

local function truncate_utf8(value, maximum_bytes)
    if #value <= maximum_bytes then
        return value
    end
    local cut = maximum_bytes
    local next_byte = value:byte(cut + 1)
    if next_byte ~= nil and next_byte >= 0x80 and next_byte <= 0xBF then
        while cut > 0 do
            local byte = value:byte(cut)
            if byte == nil or byte < 0x80 or byte > 0xBF then
                break
            end
            cut = cut - 1
        end
        cut = math.max(0, cut - 1)
    end
    return value:sub(1, cut)
end

local function sanitized_text(value, maximum_bytes, collapse_whitespace)
    local result = trimmed(value)
    if result == nil then
        return nil
    end
    if result:match("^UObject:%s*[0-9A-Fa-fx]+$")
        or result:match("^TrivialObject:%s*[0-9A-Fa-fx]+$")
        or result:match("^RemoteUnrealParam:")
    then
        return nil
    end
    result = result:gsub("[%z\1-\31\127]", " ")
    if collapse_whitespace then
        result = result:gsub("%s+", " ")
    end
    result = truncate_utf8(result, maximum_bytes)
    return trimmed(result)
end

local function finite_number(value, minimum, maximum)
    local number = tonumber(value)
    if number == nil or number ~= number
        or number == math.huge or number == -math.huge
    then
        return nil
    end
    if minimum ~= nil and number < minimum then
        return nil
    end
    if maximum ~= nil and number > maximum then
        return nil
    end
    return number
end

function Servers.validate_address(value)
    local address = trimmed(value)
    if address == nil or address == "" then
        return nil, "address is empty"
    end
    if #address > 253 then
        return nil, "address is too long"
    end
    if address:find("[%s|;?/#\\]") then
        return nil, "address contains an unsafe character"
    end

    local host, port = address:match("^([%w%.%-]+):(%d+)$")
    if host == nil then
        host = address:match("^([%w%.%-]+)$")
    end
    if host == nil or host:sub(1, 1) == "." or host:sub(-1) == "." then
        return nil, "address must be a hostname or IPv4 address"
    end
    if host:find("..", 1, true) or host:find("--", 1, true) then
        return nil, "address contains an invalid host label"
    end
    for label in host:gmatch("[^.]+") do
        if label:sub(1, 1) == "-" or label:sub(-1) == "-" then
            return nil, "address contains an invalid host label"
        end
    end
    if host:match("^%d+%.%d+%.%d+%.%d+$") then
        local parts = 0
        for part in host:gmatch("%d+") do
            parts = parts + 1
            if tonumber(part) > 255 then
                return nil, "IPv4 octets must be between 0 and 255"
            end
        end
        if parts ~= 4 then
            return nil, "IPv4 address must contain four octets"
        end
    end
    if port ~= nil then
        local number = tonumber(port)
        if number == nil or number < 1 or number > 65535 then
            return nil, "port must be between 1 and 65535"
        end
    end
    return address
end

function Servers.load(configured)
    local result = {}
    local warnings = {}
    local seen_addresses = {}
    if type(configured) ~= "table" then
        return result, { "servers must be a table" }
    end

    for source_index, entry in ipairs(configured) do
        if type(entry) ~= "table" then
            warnings[#warnings + 1] = string.format(
                "slot %d was ignored because it is not a table",
                source_index
            )
        elseif entry.enabled ~= false then
            local address, address_error = Servers.validate_address(entry.address)
            local name = sanitized_text(entry.name, MAX_NAME_BYTES, true)
            if address == nil then
                warnings[#warnings + 1] = string.format(
                    "slot %d was ignored: %s",
                    source_index,
                    address_error
                )
            else
                local address_key = address:lower()
                if seen_addresses[address_key] then
                    warnings[#warnings + 1] = string.format(
                        "slot %d was ignored because its address duplicates an earlier slot",
                        source_index
                    )
                    goto continue
                end
                seen_addresses[address_key] = true
                if name == nil or name == "" then
                    name = "Server " .. tostring(source_index)
                end
                local world_guid = sanitized_text(
                    entry.world_guid,
                    MAX_GUID_BYTES,
                    true
                )
                if world_guid == "" then
                    world_guid = nil
                end
                local password = type(entry.password) == "string"
                    and truncate_utf8(
                        entry.password:gsub("%z", ""),
                        MAX_PASSWORD_BYTES
                    )
                    or nil
                if password == "" then
                    password = nil
                end
                result[#result + 1] = {
                    name = name,
                    address = address,
                    source_index = source_index,
                    players = finite_number(entry.players, 0, 1000000),
                    max_players = finite_number(entry.max_players, 1, 1000000),
                    ping = finite_number(entry.ping, 0, 999999),
                    world_guid = world_guid,
                    password = password,
                    password_protected = entry.password_protected == true
                        or password ~= nil,
                    discovered = entry.discovered == true,
                }
            end
        end
        ::continue::
    end
    return result, warnings
end

function Servers.resolve(entries, value)
    if type(entries) ~= "table" or #entries == 0 then
        return nil
    end
    if type(value) == "number" or tostring(value):match("^%d+$") then
        local index = tonumber(value)
        if index ~= nil then
            return entries[index], index
        end
    end

    local wanted = trimmed(tostring(value or "")):lower()
    for index, entry in ipairs(entries) do
        if entry.name:lower() == wanted then
            return entry, index
        end
    end
    return nil
end

function Servers.unique_name(entries, value, ignored_index)
    local base = sanitized_text(value, MAX_NAME_BYTES, true)
    if base == nil or base == "" then
        base = "Server"
    end
    local used = {}
    for index, entry in ipairs(type(entries) == "table" and entries or {}) do
        if index ~= ignored_index and type(entry) == "table"
            and type(entry.name) == "string"
        then
            used[entry.name:lower()] = true
        end
    end
    if not used[base:lower()] then
        return base
    end
    local suffix = 2
    while used[(base .. " " .. tostring(suffix)):lower()] do
        suffix = suffix + 1
    end
    return truncate_utf8(base, math.max(0, MAX_NAME_BYTES - #tostring(suffix) - 1))
        .. " " .. tostring(suffix)
end

function Servers.find_index(entries, address, world_guid)
    local wanted_address = Servers.validate_address(address)
    local wanted_guid = sanitized_text(world_guid, MAX_GUID_BYTES, true)
    if wanted_address ~= nil then
        wanted_address = wanted_address:lower()
    end
    if wanted_guid ~= nil then
        wanted_guid = wanted_guid:lower()
    end
    for index, entry in ipairs(type(entries) == "table" and entries or {}) do
        if wanted_address ~= nil and type(entry.address) == "string"
            and entry.address:lower() == wanted_address
        then
            return index
        end
        if wanted_guid ~= nil and wanted_guid ~= ""
            and type(entry.world_guid) == "string"
            and entry.world_guid:lower() == wanted_guid
        then
            return index
        end
    end
    return nil
end

local function copy_live_metadata(target, source)
    for _, key in ipairs({
        "players",
        "max_players",
        "ping",
        "world_guid",
        "password_protected",
    }) do
        if source[key] ~= nil then
            target[key] = source[key]
        end
    end
    if source.password ~= nil then
        target.password = source.password
        target.password_protected = source.password ~= ""
            or source.password_protected == true
    end
end

function Servers.upsert_connected(entries, candidate, options)
    entries = type(entries) == "table" and entries or {}
    options = type(options) == "table" and options or {}
    local normalized, warnings = Servers.load({ candidate })
    local incoming = normalized[1]
    if incoming == nil then
        return nil, nil, warnings[1] or "server details are invalid"
    end
    local index = Servers.find_index(entries, incoming.address, incoming.world_guid)
    if index ~= nil then
        local existing = entries[index]
        existing.address = incoming.address
        copy_live_metadata(existing, incoming)
        if options.replace_existing_name == true then
            existing.name = incoming.name
        end
        if incoming.discovered == true then
            existing.discovered = true
        end
        return existing, index, nil, false
    end
    if options.unique_name == true then
        incoming.name = Servers.unique_name(entries, incoming.name)
    end
    entries[#entries + 1] = incoming
    return incoming, #entries, nil, true
end

function Servers.modify(entries, index, changes)
    entries = type(entries) == "table" and entries or {}
    changes = type(changes) == "table" and changes or {}
    local existing = entries[index]
    if type(existing) ~= "table" then
        return nil, "server slot does not exist"
    end
    local address, address_error = Servers.validate_address(changes.address)
    if address == nil then
        return nil, address_error
    end
    local name = sanitized_text(changes.name, MAX_NAME_BYTES, true)
    if name == nil or name == "" then
        return nil, "server name is empty"
    end
    local duplicate_index = Servers.find_index(entries, address)
    if duplicate_index ~= nil and duplicate_index ~= index then
        return nil, "server address is already saved"
    end
    local password = type(changes.password) == "string"
        and truncate_utf8(changes.password:gsub("%z", ""), MAX_PASSWORD_BYTES)
        or ""
    local address_changed = existing.address:lower() ~= address:lower()
    existing.name = name
    existing.address = address
    existing.password = password ~= "" and password or nil
    existing.password_protected = password ~= ""
    if address_changed then
        existing.players = nil
        existing.max_players = nil
        existing.ping = nil
        existing.world_guid = nil
    end
    return existing, nil, address_changed
end

local function find_server_table(source)
    local table_start, open_brace = source:find("servers%s*=%s*{")
    if table_start == nil then
        return nil, nil
    end
    local depth = 0
    local quote = nil
    local escaped = false
    local line_comment = false
    local block_comment = false
    local long_string = false
    local index = open_brace
    while index <= #source do
        local character = source:sub(index, index)
        local pair = source:sub(index, index + 1)
        if line_comment then
            if character == "\n" then
                line_comment = false
            end
        elseif block_comment then
            if pair == "]]" then
                block_comment = false
                index = index + 1
            end
        elseif long_string then
            if pair == "]]" then
                long_string = false
                index = index + 1
            end
        elseif quote ~= nil then
            if escaped then
                escaped = false
            elseif character == "\\" then
                escaped = true
            elseif character == quote then
                quote = nil
            end
        elseif pair == "--" then
            if source:sub(index + 2, index + 3) == "[[" then
                block_comment = true
                index = index + 3
            else
                line_comment = true
                index = index + 1
            end
        elseif pair == "[[" then
            long_string = true
            index = index + 1
        elseif character == "\"" or character == "'" then
            quote = character
        elseif character == "{" then
            depth = depth + 1
        elseif character == "}" then
            depth = depth - 1
            if depth == 0 then
                return table_start, index
            end
        end
        index = index + 1
    end
    return nil, nil
end

local function serialize_server_table(entries)
    local lines = { "servers = {" }
    for _, entry in ipairs(entries) do
        local address = Servers.validate_address(entry.address)
        if address ~= nil then
            local name = trimmed(entry.name) or address
            lines[#lines + 1] = "        {"
            lines[#lines + 1] = string.format("            name = %q,", name)
            lines[#lines + 1] = string.format("            address = %q,", address)
            lines[#lines + 1] = "            enabled = true,"
            if type(entry.world_guid) == "string" and entry.world_guid ~= "" then
                lines[#lines + 1] = string.format(
                    "            world_guid = %q,",
                    entry.world_guid
                )
            end
            if entry.password_protected == true then
                lines[#lines + 1] = "            password_protected = true,"
            end
            if type(entry.password) == "string" and entry.password ~= "" then
                lines[#lines + 1] = string.format(
                    "            password = %q,",
                    entry.password
                )
            end
            if entry.discovered == true then
                lines[#lines + 1] = "            discovered = true,"
            end
            lines[#lines + 1] = "        },"
        end
    end
    lines[#lines + 1] = "    }"
    return table.concat(lines, "\n")
end

local function replace_file(path, contents)
    local temporary_path = path .. ".tmp"
    local previous_path = path .. ".previous"
    os.remove(temporary_path)
    local output, open_error = io.open(temporary_path, "wb")
    if output == nil then
        return false, open_error
    end
    local write_ok, write_error = pcall(function()
        output:write(contents)
        output:flush()
        output:close()
    end)
    if not write_ok then
        pcall(function()
            output:close()
        end)
        os.remove(temporary_path)
        return false, write_error
    end

    os.remove(previous_path)
    local backed_up, backup_error = os.rename(path, previous_path)
    if not backed_up then
        os.remove(temporary_path)
        return false, backup_error
    end
    local replaced, replace_error = os.rename(temporary_path, path)
    if not replaced then
        os.rename(previous_path, path)
        os.remove(temporary_path)
        return false, replace_error
    end
    os.remove(previous_path)
    return true
end

function Servers.write_config_servers(entries)
    local input, read_error = io.open(config_path, "rb")
    if input == nil then
        return false, read_error
    end
    local source = input:read("*a")
    input:close()
    local table_start, table_end = find_server_table(source)
    if table_start == nil then
        return false, "servers table was not found in config.lua"
    end

    local backup_path = config_path .. ".bak"
    local existing_backup = io.open(backup_path, "rb")
    if existing_backup ~= nil then
        existing_backup:close()
    else
        local backup, backup_error = io.open(backup_path, "wb")
        if backup == nil then
            return false, backup_error
        end
        local backup_ok, backup_write_error = pcall(function()
            backup:write(source)
            backup:flush()
            backup:close()
        end)
        if not backup_ok then
            pcall(function()
                backup:close()
            end)
            os.remove(backup_path)
            return false, backup_write_error
        end
    end

    local updated = source:sub(1, table_start - 1)
        .. serialize_server_table(entries)
        .. source:sub(table_end + 1)
    return replace_file(config_path, updated)
end

return Servers
