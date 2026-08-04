local Discovery = {}
local UEHelpers = require("UEHelpers")
local Servers = require("servers")

local JOIN_PACKAGE = "/Game/Pal/Blueprint/UI/Title/WBP_JoinGame"
local JOIN_CLASS = JOIN_PACKAGE .. ".WBP_JoinGame_C"
local JOIN_ASSET_NAME = "WBP_JoinGame_C"
local COMPLETE_EVENT = JOIN_CLASS .. ":OnCompleteGetServerListEvent"
local WIDGET_LIBRARY = "/Script/UMG.Default__WidgetBlueprintLibrary"
local SERVER_ROW_PACKAGE =
    "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect_ListContent"
local SERVER_ROW_CLASS = SERVER_ROW_PACKAGE .. ".WBP_Title_WorldSelect_ListContent_C"
local SERVER_ROW_ASSET_NAME = "WBP_Title_WorldSelect_ListContent_C"
local PING_COMPLETE_EVENT = SERVER_ROW_CLASS .. ":OnPingComplete"
local PING_FAILURE_EVENT = SERVER_ROW_CLASS .. ":OnPingFailure"
local SUBSYSTEM_LIBRARY = "/Script/Engine.Default__SubsystemBlueprintLibrary"
local POCKETPAIR_SUBSYSTEM_CLASS =
    "/Script/PocketpairUser.PocketpairUserSubsystem"
local PAL_UTILITY = "/Script/Pal.Default__PalUtility"
local HISTORY_FILTER = 2
local LATEST_SORT = 0
local MAX_ACCEPTED_PING = 999999
local PING_TIMEOUT_MS = 3000
local MAX_CACHE_BYTES = 262144

local source_path = debug.getinfo(1, "S").source:gsub("^@", "")
local script_directory = source_path:match("^(.*[\\/])") or ""
local cache_path = script_directory .. "discovery_cache.lua"

local state = {
    running = false,
    completed = false,
    request_id = 0,
    widget = nil,
    widget_key = nil,
    request_phase = "idle",
    timeout_scheduled = false,
    connection_widget = nil,
    connection_id = 0,
    hook_registered = false,
    log = function() end,
    on_complete = function() end,
    on_error = function() end,
    removed = {},
    save_cache = true,
    callback_sequence = 0,
    pending_callbacks = {},
    completion_hook_callback = nil,
    ping_complete_hook_registered = false,
    ping_failure_hook_registered = false,
    ping_complete_hook_attempted = false,
    ping_failure_hook_attempted = false,
    ping_complete_callback = nil,
    ping_failure_callback = nil,
    ping_batch = nil,
    ping_rows = {},
}

local function retain_one_shot(callback)
    state.callback_sequence = state.callback_sequence + 1
    local callback_id = state.callback_sequence
    local wrapper = function(...)
        state.pending_callbacks[callback_id] = nil
        return callback(...)
    end
    state.pending_callbacks[callback_id] = wrapper
    return wrapper, callback_id
end

local function release_callback(callback_id)
    state.pending_callbacks[callback_id] = nil
end

local function safe_log(message)
    local value = tostring(message)
    local ok = pcall(state.log, value)
    if not ok then
        pcall(print, "[QuickConnectManager] " .. value .. "\n")
    end
end

local function protected_callback(label, callback, ...)
    if type(callback) ~= "function" then
        return false
    end
    local ok, callback_error = pcall(callback, ...)
    if not ok then
        safe_log(label .. " failed safely: " .. tostring(callback_error))
    end
    return ok
end

local function read_cache_candidate(path)
    if type(io) == "table" and type(io.open) == "function" then
        local input = io.open(path, "rb")
        if input == nil then
            return nil
        end
        local size_ok, size = pcall(function()
            return input:seek("end")
        end)
        pcall(function()
            input:close()
        end)
        if not size_ok or tonumber(size) == nil
            or size < 0 or size > MAX_CACHE_BYTES
        then
            return nil
        end
    end

    local load_ok, loader = pcall(loadfile, path, "t", {})
    if not load_ok or loader == nil then
        return nil
    end
    local ok, value = pcall(loader)
    if not ok or type(value) ~= "table" or value.completed ~= true then
        return nil
    end
    value.servers = type(value.servers) == "table" and value.servers or {}
    value.removed = type(value.removed) == "table" and value.removed or {}
    return value
end

local function read_cache_file()
    return read_cache_candidate(cache_path)
        or read_cache_candidate(cache_path .. ".previous")
end

local function alive(object)
    if object == nil then
        return false
    end
    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    return ok and valid == true
end

local function address_of(object)
    if not alive(object) then
        return nil
    end
    local ok, value = pcall(function()
        return object:GetAddress()
    end)
    return ok and tostring(value) or nil
end

local function string_value(value)
    if type(value) == "string" then
        return value
    end
    local unwrap_ok, unwrapped = pcall(function()
        return value:get()
    end)
    if unwrap_ok and unwrapped ~= value then
        return tostring(unwrapped or "")
    end
    local ok, converted = pcall(function()
        return value:ToString()
    end)
    if ok then
        return tostring(converted)
    end
    return tostring(value or "")
end

local function number_value(value)
    local direct = tonumber(value)
    if direct ~= nil then
        return direct
    end
    local ok, unwrapped = pcall(function()
        return value:get()
    end)
    return ok and tonumber(unwrapped) or nil
end

local function boolean_value(value)
    if type(value) == "boolean" then
        return value
    end
    local ok, unwrapped = pcall(function()
        return value:get()
    end)
    return ok and unwrapped == true
end

local function version_parts(value)
    local major, minor, patch, build = string_value(value):match(
        "[vV]?(%d+)%.(%d+)%.(%d+)%.(%d+)"
    )
    if major == nil then
        return nil
    end
    return {
        tonumber(major),
        tonumber(minor),
        tonumber(patch),
        tonumber(build),
    }
end

local function current_game_version(world_context)
    local utility_ok, utility = pcall(StaticFindObject, PAL_UTILITY)
    if not utility_ok or not alive(utility) then
        return nil
    end
    local version_ok, version = pcall(function()
        return utility:GetDisplayVersion(world_context)
    end)
    if not version_ok then
        return nil
    end
    return version_parts(version)
end

local function is_compatible_version(server_value, player_version, exact)
    local server_version = version_parts(server_value)
    if server_version == nil or player_version == nil then
        return false
    end
    if server_version[1] ~= player_version[1]
        or server_version[2] ~= player_version[2]
        or server_version[3] ~= player_version[3]
    then
        return false
    end
    return not exact or server_version[4] == player_version[4]
end

local function restore_saved_password(widget, world_guid, host, port, locked)
    if not locked or not alive(widget) then
        return nil
    end
    local function clear_password()
        pcall(function()
            widget.RestoredPassword = ""
        end)
    end
    local function read_password()
        local ok, password = pcall(function()
            return string_value(widget.RestoredPassword)
        end)
        return ok and password ~= "" and password or nil
    end
    clear_password()
    if world_guid ~= "" then
        pcall(function()
            widget:RestorePasswordForServerByGUID(world_guid)
        end)
        local password = read_password()
        if password ~= nil then
            return password
        end
    end
    clear_password()
    pcall(function()
        widget:RestorePasswordForServer(host, math.floor(port))
    end)
    return read_password()
end

local function serialize_cache(servers)
    local lines = { "return {", "    completed = true,", "    servers = {" }
    for _, server in ipairs(servers) do
        lines[#lines + 1] = "        {"
        lines[#lines + 1] = string.format("            name = %q,", server.name)
        lines[#lines + 1] = string.format("            address = %q,", server.address)
        if tonumber(server.players) ~= nil then
            lines[#lines + 1] = string.format(
                "            players = %d,",
                math.floor(tonumber(server.players))
            )
        end
        if tonumber(server.max_players) ~= nil then
            lines[#lines + 1] = string.format(
                "            max_players = %d,",
                math.floor(tonumber(server.max_players))
            )
        end
        if tonumber(server.ping) ~= nil then
            lines[#lines + 1] = string.format(
                "            ping = %d,",
                math.floor(tonumber(server.ping))
            )
        end
        if type(server.world_guid) == "string" and server.world_guid ~= "" then
            lines[#lines + 1] = string.format(
                "            world_guid = %q,",
                server.world_guid
            )
        end
        if server.password_protected == true then
            lines[#lines + 1] = "            password_protected = true,"
        end
        lines[#lines + 1] = "            discovered = true,"
        lines[#lines + 1] = "        },"
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    removed = {"
    local removed_addresses = {}
    for address, removed in pairs(state.removed) do
        if removed == true and type(address) == "string" then
            removed_addresses[#removed_addresses + 1] = address
        end
    end
    table.sort(removed_addresses)
    for _, address in ipairs(removed_addresses) do
        lines[#lines + 1] = string.format("        [%q] = true,", address)
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

local function write_cache(servers)
    local serialized_ok, contents = pcall(serialize_cache, servers)
    if not serialized_ok then
        return false, contents
    end

    local temporary_path = cache_path .. ".tmp"
    local previous_path = cache_path .. ".previous"
    os.remove(temporary_path)
    local file, open_error = io.open(temporary_path, "wb")
    if file == nil then
        return false, open_error
    end
    local write_ok, write_error = pcall(function()
        file:write(contents)
        file:flush()
        file:close()
    end)
    if not write_ok then
        pcall(function()
            file:close()
        end)
        os.remove(temporary_path)
        return false, write_error
    end

    local existing = io.open(cache_path, "rb")
    if existing ~= nil then
        existing:close()
        os.remove(previous_path)
        local backed_up, backup_error = os.rename(cache_path, previous_path)
        if not backed_up then
            os.remove(temporary_path)
            return false, backup_error
        end
    end
    local replaced, replace_error = os.rename(temporary_path, cache_path)
    if not replaced then
        os.rename(previous_path, cache_path)
        os.remove(temporary_path)
        return false, replace_error
    end
    os.remove(previous_path)
    return true
end

local function release_query_widget()
    if alive(state.widget) then
        pcall(function()
            state.widget:RemoveFromParent()
        end)
    end
    state.widget = nil
    state.widget_key = nil
    state.request_phase = "idle"
    state.timeout_scheduled = false
end

local function release_ping_batch()
    for _, record in pairs(state.ping_rows) do
        if type(record) == "table" and alive(record.widget) then
            pcall(function()
                record.widget:RemoveFromParent()
            end)
        end
    end
    local batch = state.ping_batch
    if type(batch) == "table" and type(batch.servers) == "table" then
        for _, server in ipairs(batch.servers) do
            server._display_data = nil
        end
    end
    state.ping_batch = nil
    state.ping_rows = {}
end

local function ping_values_text(values)
    local sorted = {}
    for _, value in ipairs(type(values) == "table" and values or {}) do
        sorted[#sorted + 1] = value
    end
    table.sort(sorted)
    if #sorted == 0 then
        return "none"
    end
    return table.concat(sorted, ",") .. " ms"
end

local function finish(servers, request_id)
    if request_id ~= state.request_id or state.completed then
        return
    end
    state.completed = true
    state.running = false
    release_query_widget()
    release_ping_batch()

    local visible_servers = {}
    for _, server in ipairs(type(servers) == "table" and servers or {}) do
        server._display_data = nil
        local key = tostring(server.address or ""):lower()
        if state.removed[key] ~= true then
            visible_servers[#visible_servers + 1] = server
        end
    end

    if state.save_cache then
        local saved, save_error = write_cache(visible_servers)
        if not saved then
            safe_log("Server discovery could not save its cache: " .. tostring(save_error))
        end
    end
    protected_callback(
        "Server discovery completion callback",
        state.on_complete,
        visible_servers
    )
end

local function fail(message, request_id)
    if request_id ~= state.request_id or state.completed then
        return
    end
    state.completed = true
    state.running = false
    release_query_widget()
    release_ping_batch()
    protected_callback("Server discovery error callback", state.on_error, message)
end

local function run_request_on_game_thread(request_id, label, callback)
    local game_thread_callback, callback_id = retain_one_shot(function()
        if request_id ~= state.request_id or state.completed then
            return
        end
        local callback_ok, callback_error = pcall(callback)
        if not callback_ok then
            safe_log(label .. " failed safely: " .. tostring(callback_error))
            fail(label .. " failed.", request_id)
        end
    end)
    local queued, queue_error = pcall(ExecuteInGameThread, game_thread_callback)
    if not queued then
        release_callback(callback_id)
        safe_log(label .. " could not enter the game thread: " .. tostring(queue_error))
        fail(label .. " could not enter the game thread.", request_id)
    end
    return queued
end

local function schedule_request(delay_ms, request_id, label, callback)
    local delay = math.max(0, math.floor(tonumber(delay_ms) or 0))
    local delayed_callback, callback_id = retain_one_shot(function()
        run_request_on_game_thread(request_id, label, callback)
    end)
    local scheduled, schedule_error = pcall(ExecuteWithDelay, delay, delayed_callback)
    if not scheduled then
        release_callback(callback_id)
        safe_log(label .. " could not be scheduled: " .. tostring(schedule_error))
        fail(label .. " could not be scheduled.", request_id)
    end
    return scheduled
end

local function collect_live_servers(widget)
    local servers = {}
    local seen = {}
    local quality_by_address = {}
    local player_version = current_game_version(widget)
    local total_rows = 0
    local history_rows = 0
    local rejections = {
        other_type = 0,
        endpoint = 0,
        ping = 0,
        players = 0,
        capacity = 0,
        version = 0,
        duplicate = 0,
        normalization = 0,
    }
    local array_ok, array = pcall(function()
        return widget.CachedServerDisplayInfo
    end)
    if not array_ok or array == nil then
        return servers, total_rows, history_rows, rejections
    end

    pcall(function()
        array:ForEach(function(_, wrapped)
            local row = wrapped
            pcall(function()
                row = wrapped:get()
            end)

            total_rows = total_rows + 1
            local row_type = number_value(row.ServerListType)
            if row_type ~= nil and row_type ~= HISTORY_FILTER then
                -- Palworld's History query can return live-enriched rows tagged
                -- with their underlying Community type. They contain the ping
                -- and player counts that the History placeholder rows omit.
                rejections.other_type = rejections.other_type + 1
            else
                history_rows = history_rows + 1
            end

            local host = string_value(row.ServerAddress):match("^%s*(.-)%s*$")
            local port = number_value(row.ServerPort)
            local embedded_host, embedded_port = host:match("^([%w%.%-]+):(%d+)$")
            if embedded_host ~= nil then
                host = embedded_host
                port = tonumber(embedded_port)
            end
            local ping = number_value(row.Ping)
            local players = number_value(row.NowPlayerNum)
            local max_players = number_value(row.MaxPlayerNum)
            local version = string_value(row.VersionString)
            local locked = boolean_value(row.IsLocked)
            local endpoint_valid = host ~= ""
                and port ~= nil and port >= 1 and port <= 65535
            local ping_valid = ping ~= nil
                and ping >= 0 and ping <= MAX_ACCEPTED_PING
            local players_valid = players ~= nil and players >= 0
            local capacity_valid = max_players ~= nil and max_players > 0
            if not endpoint_valid then
                rejections.endpoint = rejections.endpoint + 1
            end
            if not ping_valid then
                rejections.ping = rejections.ping + 1
            end
            if not players_valid then
                rejections.players = rejections.players + 1
            end
            if not capacity_valid then
                rejections.capacity = rejections.capacity + 1
            end
            local exact_version_required = not ping_valid or not players_valid
            local version_valid = is_compatible_version(
                version,
                player_version,
                exact_version_required
            )
            if not version_valid then
                rejections.version = rejections.version + 1
            end
            -- Rows without complete live status must exactly match the player
            -- build. Fully live rows may differ only in the final build number.
            if endpoint_valid and version_valid then
                local address = host .. ":" .. tostring(math.floor(port))
                local quality = (ping_valid and 1 or 0)
                    + (players_valid and 1 or 0)
                    + (capacity_valid and 1 or 0)
                local existing_index = seen[address]
                if existing_index == nil
                    or quality > (quality_by_address[address] or -1)
                then
                    local name = string_value(row.ServerName):match("^%s*(.-)%s*$")
                    if name == "" then
                        name = address
                    end
                    local world_guid = string_value(row.WorldGUID):match(
                        "^%s*(.-)%s*$"
                    )
                    local password = restore_saved_password(
                        widget,
                        world_guid,
                        host,
                        port,
                        locked
                    )
                    local normalized = Servers.load({ {
                        name = name,
                        address = address,
                        players = players_valid and math.floor(players) or nil,
                        max_players = capacity_valid and math.floor(max_players) or nil,
                        ping = ping_valid and math.floor(ping) or nil,
                        world_guid = world_guid ~= "" and world_guid or nil,
                        password = password,
                        password_protected = locked,
                        discovered = true,
                    } })
                    if normalized[1] ~= nil then
                        normalized[1]._display_data = row
                        if existing_index == nil then
                            servers[#servers + 1] = normalized[1]
                            seen[address] = #servers
                        else
                            servers[existing_index] = normalized[1]
                        end
                        quality_by_address[address] = quality
                    else
                        rejections.normalization = rejections.normalization + 1
                    end
                elseif existing_index ~= nil then
                    rejections.duplicate = rejections.duplicate + 1
                end
            end
        end)
    end)
    return servers, total_rows, history_rows, rejections
end

local function finish_ping_record(row_key, ping)
    local batch = state.ping_batch
    local record = row_key ~= nil and state.ping_rows[row_key] or nil
    if batch == nil
        or record == nil
        or record.request_id ~= batch.request_id
        or batch.request_id ~= state.request_id
        or state.completed
    then
        return
    end

    state.ping_rows[row_key] = nil
    if alive(record.widget) then
        pcall(function()
            record.widget:RemoveFromParent()
        end)
    end
    batch.remaining = math.max(0, batch.remaining - 1)
    local valid_ping = tonumber(ping)
    if valid_ping ~= nil
        and valid_ping >= 0
        and valid_ping <= MAX_ACCEPTED_PING
    then
        valid_ping = math.floor(valid_ping)
        local server = batch.servers[record.server_index]
        if server ~= nil then
            server.ping = valid_ping
        end
        batch.completed = batch.completed + 1
        batch.values[#batch.values + 1] = valid_ping
    end

    if batch.remaining == 0 and batch.starting ~= true then
        local servers = batch.servers
        local completed = batch.completed
        local total = batch.total
        local values = ping_values_text(batch.values)
        local request_id = batch.request_id
        release_ping_batch()
        safe_log(string.format(
            "Stock server-row ping completed for %d of %d server(s); values=%s.",
            completed,
            total,
            values
        ))
        finish(servers, request_id)
    end
end

local function ping_row_key(context)
    local context_ok, object = pcall(function()
        return context:get()
    end)
    if not context_ok then
        object = context
    end
    return address_of(object)
end

local function register_ping_hooks()
    if not state.ping_complete_hook_registered
        and not state.ping_complete_hook_attempted
    then
        state.ping_complete_hook_attempted = true
        state.ping_complete_callback = state.ping_complete_callback
            or function(context, operation, _, time_ms)
                local callback_ok, callback_error = pcall(function()
                    local row_key = ping_row_key(context)
                    local record = row_key ~= nil and state.ping_rows[row_key] or nil
                    if record == nil then
                        return
                    end
                    local ping = number_value(time_ms)
                    schedule_request(0, record.request_id, "Stock server-row ping completion", function()
                        finish_ping_record(row_key, ping)
                    end)
                end)
                if not callback_ok then
                    safe_log(
                        "Stock server-row ping completion failed safely: "
                            .. tostring(callback_error)
                    )
                end
            end
        local ok, registration_result = pcall(
            RegisterHook,
            PING_COMPLETE_EVENT,
            state.ping_complete_callback
        )
        state.ping_complete_hook_registered = ok
            and registration_result ~= nil
            and registration_result ~= false
        if not state.ping_complete_hook_registered then
            safe_log(
                "Stock server-row ping completion hook was unavailable: "
                    .. tostring(registration_result)
            )
        end
    end

    if not state.ping_failure_hook_registered
        and not state.ping_failure_hook_attempted
    then
        state.ping_failure_hook_attempted = true
        state.ping_failure_callback = state.ping_failure_callback
            or function(context, operation)
                local callback_ok, callback_error = pcall(function()
                    local row_key = ping_row_key(context)
                    local record = row_key ~= nil and state.ping_rows[row_key] or nil
                    if record == nil then
                        return
                    end
                    schedule_request(0, record.request_id, "Stock server-row ping failure", function()
                        finish_ping_record(row_key, nil)
                    end)
                end)
                if not callback_ok then
                    safe_log(
                        "Stock server-row ping failure handler failed safely: "
                            .. tostring(callback_error)
                    )
                end
            end
        local ok, registration_result = pcall(
            RegisterHook,
            PING_FAILURE_EVENT,
            state.ping_failure_callback
        )
        state.ping_failure_hook_registered = ok
            and registration_result ~= nil
            and registration_result ~= false
        if not state.ping_failure_hook_registered then
            safe_log(
                "Stock server-row ping failure hook was unavailable: "
                    .. tostring(registration_result)
            )
        end
    end

    return state.ping_complete_hook_registered
end

local function load_server_row_class()
    local existing_ok, existing = pcall(StaticFindObject, SERVER_ROW_CLASS)
    if existing_ok and alive(existing) then
        return existing
    end
    local ok, loaded = pcall(function()
        local helpers = StaticFindObject(
            "/Script/AssetRegistry.Default__AssetRegistryHelpers"
        )
        if not alive(helpers) then
            return nil
        end
        return helpers:GetAsset({
            PackageName = UEHelpers.FindOrAddFName(SERVER_ROW_PACKAGE),
            AssetName = UEHelpers.FindOrAddFName(SERVER_ROW_ASSET_NAME),
        })
    end)
    return ok and alive(loaded) and loaded or nil
end

local function resolve_ping_cache_subsystem(controller)
    local function fallback()
        local first_ok, first = pcall(function()
            return FindFirstOf("PocketpairUserSubsystem")
        end)
        return first_ok and alive(first) and first or nil
    end

    local library_ok, library = pcall(StaticFindObject, SUBSYSTEM_LIBRARY)
    local class_ok, subsystem_class = pcall(
        StaticFindObject,
        POCKETPAIR_SUBSYSTEM_CLASS
    )
    if not library_ok or not alive(library)
        or not class_ok or not alive(subsystem_class)
    then
        return fallback()
    end
    local subsystem_ok, subsystem = pcall(function()
        return library:GetGameInstanceSubsystem(controller, subsystem_class)
    end)
    if subsystem_ok and alive(subsystem) then
        return subsystem
    end

    -- Compatibility fallback only. Prefer the subsystem owned by the current
    -- title GameInstance so a stale object from a previous world cannot receive
    -- cache writes after returning from gameplay.
    return fallback()
end

local function start_stock_row_pings(servers, request_id)
    if request_id ~= state.request_id or state.completed then
        return
    end
    local row_class = load_server_row_class()
    if not alive(row_class) then
        safe_log("Palworld's stock server-row ping service was unavailable; using query values.")
        finish(servers, request_id)
        return
    end
    if not register_ping_hooks() then
        safe_log("Palworld's stock server-row ping callback was unavailable; using query values.")
        finish(servers, request_id)
        return
    end
    local controller_ok, controller = pcall(UEHelpers.GetPlayerController)
    local library_ok, library = pcall(StaticFindObject, WIDGET_LIBRARY)
    if not controller_ok or not alive(controller) or not library_ok or not alive(library) then
        safe_log("Palworld's stock server-row widget could not be created; using query values.")
        finish(servers, request_id)
        return
    end
    local ping_cache_subsystem = resolve_ping_cache_subsystem(controller)

    local batch = {
        request_id = request_id,
        servers = servers,
        remaining = 0,
        completed = 0,
        total = 0,
        values = {},
        starting = true,
    }
    state.ping_batch = batch
    state.ping_rows = {}

    for server_index, server in ipairs(servers) do
        local display_data = server._display_data
        local created_ok, row_widget = pcall(function()
            return library:Create(controller, row_class, controller)
        end)
        local row_key = created_ok and address_of(row_widget) or nil
        if row_key ~= nil and display_data ~= nil then
            local record = {
                request_id = request_id,
                widget = row_widget,
                server_index = server_index,
            }
            state.ping_rows[row_key] = record
            batch.remaining = batch.remaining + 1
            batch.total = batch.total + 1
            server.ping = nil
            pcall(function()
                row_widget:SetVisibility(1)
            end)
            if alive(ping_cache_subsystem) then
                pcall(function()
                    -- SetupByServerDisplayData only sends a packet when this
                    -- stock cache returns -1. Invalidate the exact address used
                    -- by the row so every Quick Connect refresh is genuinely new.
                    ping_cache_subsystem:AddPingResultCache(
                        string_value(display_data.ServerAddress),
                        -1
                    )
                end)
            end
            local setup_ok = pcall(function()
                -- This is the exact path used by Palworld's Dedicated Server
                -- list. The row checks the game's ping cache, constructs a
                -- PingIP operation, binds its Blueprint callbacks, and sends it.
                row_widget:SetupByServerDisplayData(display_data)
            end)
            if not setup_ok then
                finish_ping_record(row_key, nil)
            end
        end
    end

    batch.starting = false

    if batch.total == 0 then
        release_ping_batch()
        safe_log("Palworld's stock server-row ping service created no operations; using query values.")
        finish(servers, request_id)
        return
    end

    if batch.remaining == 0 then
        local completed = batch.completed
        local total = batch.total
        local values = ping_values_text(batch.values)
        release_ping_batch()
        safe_log(string.format(
            "Stock server-row ping completed for %d of %d server(s); values=%s.",
            completed,
            total,
            values
        ))
        finish(servers, request_id)
        return
    end

    schedule_request(PING_TIMEOUT_MS, request_id, "Stock server-row ping timeout", function()
        local current = state.ping_batch
        if current == nil or current.request_id ~= request_id then
            return
        end
        local pending = current.remaining
        local completed = current.completed
        local total = current.total
        local values = ping_values_text(current.values)
        local current_servers = current.servers
        release_ping_batch()
        safe_log(string.format(
            "Stock server-row ping timed out for %d server(s); %d of %d completed; values=%s.",
            pending,
            completed,
            total,
            values
        ))
        finish(current_servers, request_id)
    end)
end

local function schedule_request_timeout(request_id)
    if state.timeout_scheduled then
        return
    end
    state.timeout_scheduled = true
    schedule_request(30000, request_id, "Server history timeout", function()
        if request_id == state.request_id
            and state.running
            and not state.completed
        then
            fail("Palworld's server-history request timed out.", request_id)
        end
    end)
end

local function issue_history_request(request_id)
    if request_id ~= state.request_id
        or state.completed
        or state.request_phase ~= "settling"
        or not alive(state.widget)
    then
        return
    end

    local widget = state.widget
    state.request_phase = "requesting"

    -- WBP_JoinGame can populate CachedServerDisplayInfo during Construct. Clear
    -- that automatic result before issuing the explicit History query so a
    -- refresh cannot redisplay a stale ping/player-count snapshot.
    pcall(function()
        local cached = widget.CachedServerDisplayInfo
        if cached ~= nil then
            cached:Empty()
        end
    end)
    pcall(function()
        widget:SetVisibility(1)
        widget.ServerFilterType = HISTORY_FILTER
        widget.CurrentPage = 0
        widget.bIsShowIgnoreVersionServer = false
    end)

    local request_ok, request_error = pcall(function()
        -- Use the same wrapper as Palworld's History page. Besides issuing the
        -- request, it repopulates CachedServerDisplayInfo for the UI result.
        widget:RequestGetServerListBP(
            HISTORY_FILTER,
            "",
            0,
            "",
            LATEST_SORT
        )
    end)
    if not request_ok then
        request_ok, request_error = pcall(function()
            -- Compatibility fallback for builds where the Blueprint wrapper
            -- is unavailable to UE4SS Lua.
            widget:RequestGetServerList(
                HISTORY_FILTER,
                LATEST_SORT,
                "",
                0,
                "",
                true
            )
        end)
    end
    if not request_ok then
        fail(
            "Palworld's server-history request failed to start: "
                .. tostring(request_error),
            request_id
        )
        return
    end

    schedule_request_timeout(request_id)
end

local function register_completion_hook()
    if state.hook_registered then
        return true
    end
    state.completion_hook_callback = state.completion_hook_callback or function(context)
        local callback_ok, callback_error = pcall(function()
            local context_ok, widget = pcall(function()
                return context:get()
            end)
            if not context_ok or address_of(widget) ~= state.widget_key then
                return
            end
            local request_id = state.request_id
            if state.request_phase == "settling" then
                -- Ignore the widget's automatic Construct-time completion. Its
                -- cached rows are not proof that Refresh performed a new query.
                schedule_request(100, request_id, "Fresh server history request", function()
                    issue_history_request(request_id)
                end)
            elseif state.request_phase == "requesting" then
                state.request_phase = "collecting"
                schedule_request(250, request_id, "Server history result collection", function()
                    if not alive(state.widget) then
                        fail("Palworld's server-history widget became unavailable.", request_id)
                        return
                    end
                    local servers, total_rows, history_rows, rejections =
                        collect_live_servers(state.widget)
                    safe_log(string.format(
                        "Palworld History query returned %d row(s), %d usable; "
                            .. "other_type=%d invalid_endpoint=%d invalid_ping=%d "
                            .. "invalid_players=%d invalid_capacity=%d invalid_version=%d duplicate=%d "
                            .. "normalization=%d.",
                        total_rows,
                        #servers,
                        rejections.other_type,
                        rejections.endpoint,
                        rejections.ping,
                        rejections.players,
                        rejections.capacity,
                        rejections.version,
                        rejections.duplicate,
                        rejections.normalization
                    ))
                    start_stock_row_pings(servers, request_id)
                end)
            end
        end)
        if not callback_ok then
            safe_log(
                "Server history completion hook failed safely: "
                    .. tostring(callback_error)
                )
        end
    end
    local ok, registration_result = pcall(
        RegisterHook,
        COMPLETE_EVENT,
        state.completion_hook_callback
    )
    state.hook_registered = ok and registration_result ~= false
    return state.hook_registered
end

local function load_join_class()
    local existing_ok, existing = pcall(StaticFindObject, JOIN_CLASS)
    if existing_ok and alive(existing) then
        return existing
    end
    local ok, loaded = pcall(function()
        local helpers = StaticFindObject(
            "/Script/AssetRegistry.Default__AssetRegistryHelpers"
        )
        if not alive(helpers) then
            return nil
        end
        return helpers:GetAsset({
            PackageName = UEHelpers.FindOrAddFName(JOIN_PACKAGE),
            AssetName = UEHelpers.FindOrAddFName(JOIN_ASSET_NAME),
        })
    end)
    return ok and alive(loaded) and loaded or nil
end

local function begin_request(attempt, request_id)
    run_request_on_game_thread(request_id, "Server history request", function()
        if request_id ~= state.request_id or state.completed then
            return
        end
        local controller_ok, controller = pcall(UEHelpers.GetPlayerController)
        local class = load_join_class()
        if not controller_ok or not alive(controller) or not alive(class) then
            if attempt < 60 then
                schedule_request(500, request_id, "Server history service retry", function()
                    begin_request(attempt + 1, request_id)
                end)
            else
                fail("Palworld's server-history service was not available.", request_id)
            end
            return
        end
        if not register_completion_hook() then
            fail("Palworld's server-history completion event could not be registered.", request_id)
            return
        end

        local created_ok, widget = pcall(function()
            local library = StaticFindObject(WIDGET_LIBRARY)
            if not alive(library) then
                return nil
            end
            return library:Create(controller, class, controller)
        end)
        if not created_ok or not alive(widget) then
            fail("Palworld's hidden server-history widget could not be created.", request_id)
            return
        end
        state.widget = widget
        state.widget_key = address_of(widget)
        state.request_phase = "settling"
        pcall(function()
            widget:SetVisibility(1)
            widget.ServerFilterType = HISTORY_FILTER
            widget.CurrentPage = 0
            widget.bIsShowIgnoreVersionServer = false
        end)

        -- Give Construct a short window to finish its own query. Its completion
        -- can trigger the request earlier; this delayed path is the fallback.
        schedule_request(750, request_id, "Fresh server history request", function()
            issue_history_request(request_id)
        end)
    end)
end

function Discovery.load_cache()
    local value = read_cache_file()
    if value ~= nil then
        state.removed = value.removed
    end
    return value
end

function Discovery.remove(address)
    local key = tostring(address or ""):match("^%s*(.-)%s*$"):lower()
    if key == "" then
        return false, "server address is empty"
    end
    local cache = read_cache_file() or {
        completed = true,
        servers = {},
        removed = {},
    }
    state.removed = cache.removed
    state.removed[key] = true
    local retained = {}
    for _, server in ipairs(cache.servers) do
        if tostring(server.address or ""):lower() ~= key then
            retained[#retained + 1] = server
        end
    end
    return write_cache(retained)
end

local function find_pal_utility()
    local ok, utility = pcall(function()
        local exact = StaticFindObject("/Script/Pal.Default__PalUtility")
        if alive(exact) then
            return exact
        end
        return FindFirstOf("PalUtility")
    end)
    return ok and alive(utility) and utility or nil
end

function Discovery.connect(entry)
    local address = type(entry) == "table" and entry.address or entry
    local value = tostring(address or ""):match("^%s*(.-)%s*$")
    local host, port_text = value:match("^([%w%.%-]+):(%d+)$")
    if host == nil then
        host = value:match("^([%w%.%-]+)$")
    end
    local port = tonumber(port_text) or 8211
    if host == nil or port < 1 or port > 65535 then
        return false, "server address is invalid"
    end

    local controller_ok, controller = pcall(UEHelpers.GetPlayerController)
    local class = load_join_class()
    if not controller_ok or not alive(controller) or not alive(class) then
        return false, "Palworld's join-game service is unavailable"
    end
    local created_ok, widget = pcall(function()
        local library = StaticFindObject(WIDGET_LIBRARY)
        if not alive(library) then
            return nil
        end
        return library:Create(controller, class, controller)
    end)
    if not created_ok or not alive(widget) then
        return false, "Palworld's join-game widget could not be created"
    end
    state.connection_id = state.connection_id + 1
    local connection_id = state.connection_id
    state.connection_widget = widget
    pcall(function()
        widget:SetVisibility(1)
    end)
    local password = type(entry) == "table" and entry.password or nil
    local world_guid = type(entry) == "table" and entry.world_guid or nil
    pcall(function()
        if type(world_guid) == "string" and world_guid ~= "" then
            widget:RestorePasswordForServerByGUID(world_guid)
        else
            widget:RestorePasswordForServer(host, math.floor(port))
        end
    end)
    if type(password) == "string" and password ~= "" then
        local utility = find_pal_utility()
        if alive(utility) then
            if type(world_guid) == "string" and world_guid ~= "" then
                pcall(function()
                    utility:SaveServerPassword(widget, world_guid, password)
                end)
            end
            pcall(function()
                utility:SetSaveServerPassword(widget, true)
            end)
            pcall(function()
                utility:SetPassword(widget, password)
            end)
        end
        -- Palworld's native password validation reads these values from the
        -- game instance after RestorePasswordForServer has run. Stage the
        -- configured credential last so restoration cannot clear it.
        local game_instance_ok, game_instance = pcall(UEHelpers.GetGameInstance)
        if game_instance_ok and alive(game_instance) then
            pcall(function()
                game_instance.InputPassword = password
                game_instance.RestoredPasswordForDisplay = password
                game_instance.bSaveServerPassword = true
            end)
        end
        pcall(function()
            widget.RestoredPassword = password
            widget.InputIPAddress = value
            widget:SetIsCheckedInputPassword(true)
        end)
    end
    local connected, connect_error = pcall(function()
        widget:ConnectServerByAddress(host, math.floor(port))
    end)
    if not connected then
        pcall(function()
            widget:RemoveFromParent()
        end)
        state.connection_widget = nil
        return false, tostring(connect_error)
    end
    -- Keep the hidden native join widget alive while Palworld starts its async
    -- connection flow, then release only the Lua reference. The controller and
    -- native request retain anything the engine still needs.
    local cleanup_callback, cleanup_callback_id = retain_one_shot(function()
        if connection_id == state.connection_id then
            state.connection_widget = nil
        end
    end)
    local cleanup_scheduled = pcall(
        ExecuteWithDelay,
        60000,
        cleanup_callback
    )
    if not cleanup_scheduled then
        release_callback(cleanup_callback_id)
    end
    return true
end

function Discovery.start(options)
    if state.running then
        return false
    end
    options = type(options) == "table" and options or {}
    state.log = type(options.log) == "function" and options.log or function() end
    state.on_complete = type(options.on_complete) == "function"
        and options.on_complete
        or function() end
    state.on_error = type(options.on_error) == "function"
        and options.on_error
        or function() end
    state.save_cache = options.save_cache ~= false
    local cache = read_cache_file()
    if cache ~= nil then
        state.removed = cache.removed
    end
    release_query_widget()
    release_ping_batch()
    state.request_id = state.request_id + 1
    state.completed = false
    state.running = true
    begin_request(1, state.request_id)
    return true
end

return Discovery
