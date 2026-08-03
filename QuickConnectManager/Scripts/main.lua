local config_ok, Config = pcall(require, "config")
local config_error = nil
if not config_ok or type(Config) ~= "table" then
    config_error = Config
    Config = {}
end
local Discovery = require("discovery")
local Servers = require("servers")

local MOD = "QuickConnectManager"
local configured_entries, warnings = Servers.load(Config.servers)
local entries = configured_entries
local function bounded_integer(value, fallback, minimum, maximum)
    local number = tonumber(value)
    if number == nil or number ~= number
        or number == math.huge or number == -math.huge
    then
        return fallback
    end
    number = math.floor(number)
    if number < minimum or number > maximum then
        return fallback
    end
    return number
end

local selected_slot = bounded_integer(Config.selected_slot, 1, 1, 100000)
local connecting = false
local refresh_active = false
local discovery_needed = false
local launch_ui = nil
local bootstrap_config_needed = false
local callback_sequence = 0
local pending_callbacks = {}
local permanent_callbacks = {}

local function retain_one_shot(callback)
    callback_sequence = callback_sequence + 1
    local callback_id = callback_sequence
    local wrapper = function(...)
        pending_callbacks[callback_id] = nil
        return callback(...)
    end
    pending_callbacks[callback_id] = wrapper
    return wrapper, callback_id
end

local function release_callback(callback_id)
    pending_callbacks[callback_id] = nil
end

local configured_server_declared = false
if type(Config.servers) == "table" then
    for _, configured in ipairs(Config.servers) do
        if type(configured) == "table" and configured.enabled ~= false then
            configured_server_declared = true
            break
        end
    end
end

local auto_managed = not configured_server_declared
if #configured_entries > 0 then
    auto_managed = true
    for _, entry in ipairs(configured_entries) do
        if entry.discovered ~= true then
            auto_managed = false
            break
        end
    end
end

local function apply_cached_status(target, cached)
    local status_by_address = {}
    for _, cached_entry in ipairs(cached) do
        status_by_address[cached_entry.address:lower()] = cached_entry
    end
    for _, entry in ipairs(target) do
        local status = status_by_address[entry.address:lower()]
        entry.players = status ~= nil and status.players or nil
        entry.max_players = status ~= nil and status.max_players or nil
        entry.ping = status ~= nil and status.ping or nil
    end
end

-- A successful first-install crawl writes a small local cache, including an
-- intentionally empty result. Auto-populated config entries reuse the cache
-- for their last status, while manually configured entries take precedence.
if auto_managed and #configured_entries > 0 then
    local discovery_cache = Discovery.load_cache()
    if discovery_cache ~= nil then
        local cached_entries, cache_warnings = Servers.load(discovery_cache.servers)
        apply_cached_status(entries, cached_entries)
        for _, warning in ipairs(cache_warnings) do
            warnings[#warnings + 1] = "discovery cache: " .. warning
        end
    end
elseif #configured_entries == 0 and not configured_server_declared then
    local discovery_cache = Discovery.load_cache()
    if discovery_cache ~= nil then
        local cached_entries, cache_warnings = Servers.load(discovery_cache.servers)
        entries = cached_entries
        bootstrap_config_needed = true
        for _, warning in ipairs(cache_warnings) do
            warnings[#warnings + 1] = "discovery cache: " .. warning
        end
    else
        discovery_needed = true
    end
end

local function log(message)
    print(string.format("[%s] %s\n", MOD, tostring(message)))
end

local function run_on_game_thread(label, callback)
    local game_thread_callback, callback_id = retain_one_shot(function()
        local callback_ok, callback_error = pcall(callback)
        if not callback_ok then
            log(label .. " failed safely: " .. tostring(callback_error))
        end
    end)
    local queued, queue_error = pcall(ExecuteInGameThread, game_thread_callback)
    if not queued then
        release_callback(callback_id)
        log(label .. " could not enter the game thread: " .. tostring(queue_error))
    end
    return queued
end

local function call_ui(method, ...)
    if type(launch_ui) ~= "table" or type(launch_ui[method]) ~= "function" then
        return false
    end
    local ok, result = pcall(launch_ui[method], ...)
    if not ok then
        log("Launch UI " .. method .. " failed safely: " .. tostring(result))
        return false
    end
    return true, result
end

local function verbose(message)
    if Config.diagnostics ~= nil and Config.diagnostics.verbose == true then
        log(message)
    end
end

local function persist_server_config(context)
    local saved, save_error = Servers.write_config_servers(entries)
    if not saved then
        log(context .. " could not update config.lua: " .. tostring(save_error))
        return false
    end
    log(context .. " updated config.lua with the Quick Connect server list.")
    return true
end

local function output(device, message)
    if device ~= nil then
        local ok = pcall(function()
            device:Log(string.format("[%s] %s", MOD, tostring(message)))
        end)
        if ok then
            return
        end
    end
    log(message)
end

local function selected_entry()
    if #entries == 0 then
        return nil
    end
    if selected_slot > #entries then
        selected_slot = 1
    end
    return entries[selected_slot]
end

local function begin_native_connection(entry)
    local ok, started, error_message = pcall(Discovery.connect, entry)
    if not ok or not started then
        log(
            "Connection failed to start: "
                .. tostring(error_message or started)
        )
        return false
    end
    return true
end

local function connect(index, source, already_on_game_thread)
    if refresh_active then
        verbose("Ignored a connect request while server status was refreshing.")
        return false
    end
    if connecting then
        verbose("Ignored a repeated connect request during the cooldown.")
        return false
    end
    local entry = entries[index]
    if entry == nil then
        log("No enabled server exists in slot " .. tostring(index) .. ".")
        return false
    end

    connecting = true
    selected_slot = index
    log(string.format("Connecting to %s via %s.", entry.name, source))

    if already_on_game_thread == true then
        -- UMG button hooks already execute on the game thread. Calling the
        -- native join flow here avoids handing the critical connect callback to
        -- UE4SS's delayed EngineTick queue, where a stale callback registry can
        -- otherwise discard it after a mod reload.
        if not begin_native_connection(entry) then
            connecting = false
            return false
        end
    else
        local queued = run_on_game_thread("Connection request", function()
            if not begin_native_connection(entry) then
                call_ui("restore_after_failed_connect")
            end
        end)
        if not queued then
            connecting = false
            call_ui("restore_after_failed_connect")
            return false
        end
    end

    local cooldown = bounded_integer(Config.connect_cooldown_ms, 2000, 250, 60000)
    local cooldown_callback, callback_id = retain_one_shot(function()
        connecting = false
    end)
    local cooldown_ok, cooldown_error = pcall(
        ExecuteWithDelay,
        cooldown,
        cooldown_callback
    )
    if not cooldown_ok then
        release_callback(callback_id)
        connecting = false
        log("Connection cooldown could not be scheduled: " .. tostring(cooldown_error))
    end
    return true
end

local function select_relative(delta)
    if #entries == 0 then
        log("No enabled servers are configured.")
        return
    end
    selected_slot = ((selected_slot - 1 + delta) % #entries) + 1
    local entry = entries[selected_slot]
    log(string.format("Selected slot %d: %s (%s).", selected_slot, entry.name, entry.address))
end

local function list_entries(device)
    if #entries == 0 then
        output(device, "No enabled servers are configured. Edit Scripts/config.lua, then restart the mod.")
        return
    end
    output(device, "Configured dedicated servers:")
    for index, entry in ipairs(entries) do
        local marker = index == selected_slot and "*" or " "
        output(device, string.format("%s %d: %s (%s)", marker, index, entry.name, entry.address))
    end
end

local function usage(device)
    output(device, "Usage: qc list | qc connect [slot|name] | qc select <slot|name> | qc next | qc previous")
end

local function handle_command(_, parameters, device)
    parameters = type(parameters) == "table" and parameters or {}
    local action = tostring(parameters[1] or "list"):lower()
    if action == "list" then
        list_entries(device)
    elseif action == "next" then
        select_relative(1)
    elseif action == "previous" or action == "prev" then
        select_relative(-1)
    elseif action == "connect" then
        local entry, index
        if parameters[2] == nil then
            entry = selected_entry()
            index = selected_slot
        else
            entry, index = Servers.resolve(entries, parameters[2])
        end
        if entry == nil then
            output(device, "Server slot or exact name was not found.")
        else
            connect(index, "console command")
        end
    elseif action == "select" then
        local entry, index = Servers.resolve(entries, parameters[2])
        if entry == nil then
            output(device, "Server slot or exact name was not found.")
        else
            selected_slot = index
            output(device, string.format("Selected slot %d: %s (%s).", index, entry.name, entry.address))
        end
    else
        local entry, index = Servers.resolve(entries, parameters[1])
        if entry ~= nil then
            connect(index, "console command")
        else
            usage(device)
        end
    end
    return true
end

local function log_warnings(values)
    for _, warning in ipairs(values) do
        log("Configuration warning: " .. warning)
    end
end

if config_error ~= nil then
    log("Configuration could not be loaded; safe defaults are active: " .. tostring(config_error))
end
log_warnings(warnings)
permanent_callbacks.console = handle_command

for _, command in ipairs({ "qc", "quickconnect" }) do
    local registered, register_error = pcall(
        RegisterConsoleCommandHandler,
        command,
        handle_command
    )
    if not registered then
        log("Console command '" .. command .. "' could not be registered: " .. tostring(register_error))
    end
end

local registered_hotkeys = {}
local function register_hotkeys()
    if Config.hotkeys ~= nil and Config.hotkeys.enabled == false then
        return
    end
    local max_slots = bounded_integer(
        Config.hotkeys ~= nil and Config.hotkeys.max_slots or 8,
        8,
        1,
        8
    )
    for index = 1, math.min(#entries, max_slots) do
        if not registered_hotkeys[index] then
            local slot = index
            local hotkey_callback = function()
                local callback_ok, callback_error = pcall(
                    connect,
                    slot,
                    "Ctrl+Shift+F" .. tostring(slot)
                )
                if not callback_ok then
                    log("Hotkey callback failed safely: " .. tostring(callback_error))
                end
            end
            local registered, register_error = pcall(
                RegisterKeyBind,
                0x6F + slot,
                { ModifierKey.CONTROL, ModifierKey.SHIFT },
                hotkey_callback
            )
            if registered then
                registered_hotkeys[index] = hotkey_callback
                permanent_callbacks["hotkey_" .. tostring(index)] = hotkey_callback
            else
                log("Hotkey slot " .. tostring(index) .. " could not be registered: " .. tostring(register_error))
            end
        end
    end
end

register_hotkeys()

if bootstrap_config_needed then
    persist_server_config("First-install cache import")
end

local function apply_discovery_result(discovered, replace_listing, reason)
    local discovered_entries, discovery_warnings = Servers.load(discovered)
    log_warnings(discovery_warnings)

    local matched = 0
    local metadata_changed = false
    if replace_listing and auto_managed then
        entries = discovered_entries
        selected_slot = 1
        register_hotkeys()
        persist_server_config(reason == "first-install"
            and "Automatic server discovery"
            or "Forced server discovery")
        matched = #entries
    else
        local status_by_address = {}
        local status_by_world_guid = {}
        for _, discovered_entry in ipairs(discovered_entries) do
            status_by_address[discovered_entry.address:lower()] = discovered_entry
            if type(discovered_entry.world_guid) == "string"
                and discovered_entry.world_guid ~= ""
            then
                status_by_world_guid[discovered_entry.world_guid:lower()] = discovered_entry
            end
        end
        for _, entry in ipairs(entries) do
            local status = status_by_address[entry.address:lower()]
            if status == nil
                and type(entry.world_guid) == "string"
                and entry.world_guid ~= ""
            then
                status = status_by_world_guid[entry.world_guid:lower()]
            end
            if status ~= nil then
                entry.players = status.players
                entry.max_players = status.max_players or entry.max_players
                entry.ping = status.ping
                local next_world_guid = status.world_guid or entry.world_guid
                local next_protected = status.password_protected == true
                local next_password = next_protected
                    and (status.password or entry.password)
                    or nil
                if entry.world_guid ~= next_world_guid
                    or entry.password_protected ~= next_protected
                    or entry.password ~= next_password
                then
                    metadata_changed = true
                end
                entry.world_guid = next_world_guid
                entry.password_protected = next_protected
                entry.password = next_password
                matched = matched + 1
            else
                entry.players = nil
                entry.max_players = nil
                entry.ping = nil
            end
        end
        if (reason == "status-refresh" or reason == "startup-refresh")
            and auto_managed and metadata_changed
        then
            persist_server_config("Server credential refresh")
        end
    end

    call_ui("set_entries", entries, "No active recent servers found")
    return #discovered_entries, matched
end

local function start_discovery(reason)
    if refresh_active then
        log("A server status refresh is already in progress.")
        return false
    end
    refresh_active = true
    local replace_listing = reason == "first-install" or reason == "force-sync"
    local discovery_ok, started = pcall(Discovery.start, {
        log = log,
        save_cache = replace_listing,
        on_complete = function(discovered)
            refresh_active = false
            local count, matched = apply_discovery_result(
                discovered,
                replace_listing,
                reason
            )
            if reason == "first-install" then
                log(string.format(
                    "First-install discovery retained %d active recent server(s).",
                    count
                ))
            elseif reason == "startup-refresh" then
                log(string.format(
                    "Initial server status refresh updated %d of %d configured server(s).",
                    matched,
                    #entries
                ))
            elseif reason == "force-sync" then
                log(string.format(
                    "Forced server discovery retained %d active recent server(s).",
                    count
                ))
                call_ui("show_refresh_result", true, true)
            else
                log(string.format(
                    "Server status refresh updated %d of %d configured server(s).",
                    matched,
                    #entries
                ))
                call_ui("show_refresh_result", true)
            end
        end,
        on_error = function(message)
            refresh_active = false
            log("Server status refresh unavailable: " .. tostring(message))
            if reason == "first-install" then
                call_ui("set_entries", {}, "Recent-server discovery unavailable")
            elseif reason == "startup-refresh" then
                call_ui("set_entries", entries, "Server status refresh unavailable")
            else
                call_ui("show_refresh_result", false)
            end
        end,
    })
    if not discovery_ok then
        refresh_active = false
        log("Server status refresh failed safely: " .. tostring(started))
        if reason == "startup-refresh" then
            call_ui("set_entries", entries, "Server status refresh unavailable")
        else
            call_ui("show_refresh_result", false)
        end
        return false
    end
    if not started then
        refresh_active = false
        log("A server status refresh is already in progress.")
        if reason == "startup-refresh" then
            call_ui("set_entries", entries, "Server status refresh unavailable")
        end
        return false
    end
    if reason == "force-sync" then
        log("Forced Palworld History server discovery started.")
    elseif reason == "status-refresh" then
        log("Palworld History status-only refresh started.")
    elseif reason == "startup-refresh" then
        log("Initial Palworld History status refresh started before panel render.")
    end
    if reason == "force-sync" or reason == "status-refresh" then
        call_ui("set_refreshing", true)
    end
    return true
end

local function remove_discovered_entry(index)
    if refresh_active then
        log("Server removal was ignored while status was refreshing.")
        return false
    end
    local entry = entries[index]
    if entry == nil or entry.discovered ~= true then
        log("Only automatically discovered servers can be removed from the panel.")
        return false
    end
    local removed, remove_error = Discovery.remove(entry.address)
    if not removed then
        log("Could not save the removed server: " .. tostring(remove_error))
        return false
    end
    table.remove(entries, index)
    if selected_slot > #entries then
        selected_slot = math.max(1, #entries)
    end
    call_ui("set_entries", entries, "No active recent servers found")
    persist_server_config("Server removal")
    log("Removed an automatically discovered server from Quick Connect.")
    return true
end

local current = selected_entry()
local startup_refresh_needed = not discovery_needed and #entries > 0
log(string.format("Loaded with %d enabled server(s).", #entries))
if current ~= nil then
    log(string.format("Selected slot %d: %s (%s).", selected_slot, current.name, current.address))
end
log("Use 'qc list' in the UE4SS console for commands.")

if Config.ui == nil or Config.ui.show_on_launch ~= false then
    local ui_ok, ui_module = pcall(require, "launch_ui")
    if not ui_ok or type(ui_module) ~= "table" then
        log("Launch UI could not be loaded; console and hotkeys remain available: " .. tostring(ui_module))
    else
        launch_ui = ui_module
        call_ui("start", {
            entries = entries,
            ready = not (discovery_needed or startup_refresh_needed),
            empty_message = discovery_needed
                and "Finding active recent servers..."
                or "No active recent servers found",
            connect = function(index)
                return connect(index, "launch-screen UI", true)
            end,
            refresh = function(force_sync)
                return start_discovery(
                    force_sync == true and "force-sync" or "status-refresh"
                )
            end,
            remove = function(index)
                return remove_discovered_entry(index)
            end,
            status = function(entry)
                local players = tonumber(entry.players)
                local max_players = tonumber(entry.max_players)
                local ping = tonumber(entry.ping)
                return {
                    players = players ~= nil and max_players ~= nil
                        and string.format("%d/%d", players, max_players)
                        or nil,
                    ping = ping ~= nil and math.floor(ping) or nil,
                }
            end,
            log = log,
        })
    end
end

if discovery_needed then
    log("No configured servers or discovery cache found; starting first-install history discovery.")
    start_discovery("first-install")
elseif startup_refresh_needed then
    start_discovery("startup-refresh")
end
