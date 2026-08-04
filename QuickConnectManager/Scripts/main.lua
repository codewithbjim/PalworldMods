local config_ok, Config = pcall(require, "config")
local config_error = nil
if not config_ok or type(Config) ~= "table" then
    config_error = Config
    Config = {}
end
local Discovery = require("discovery")
local Servers = require("servers")
local Connections = require("connections")

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
local refresh_blocks_actions = false
local discovery_needed = false
local launch_ui = nil
local bootstrap_config_needed = false
local callback_sequence = 0
local pending_callbacks = {}
local permanent_callbacks = {}
local pending_reconcile_addresses = {}
local reconcile_start_scheduled = false
for _, entry in ipairs(entries) do
    if entry.world_guid == nil or entry.world_guid == "" then
        pending_reconcile_addresses[entry.address:lower()] = true
    end
end

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

local function connect_entry(entry, source, already_on_game_thread)
    if refresh_blocks_actions then
        verbose("Ignored a connect request while server status was refreshing.")
        return false
    end
    if connecting then
        verbose("Ignored a repeated connect request during the cooldown.")
        return false
    end
    connecting = true
    log(string.format("Connecting to %s via %s.", entry.name, source))

    if already_on_game_thread == true then
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

local function connect(index, source, already_on_game_thread)
    local entry = entries[index]
    if entry == nil then
        log("No enabled server exists in slot " .. tostring(index) .. ".")
        return false
    end

    selected_slot = index
    return connect_entry(entry, source, already_on_game_thread)
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
    local reconciled = 0
    local metadata_changed = false
    if replace_listing and auto_managed then
        if reason ~= "first-install" then
            for _, discovered_entry in ipairs(discovered_entries) do
                local existing_index = Servers.find_index(
                    entries,
                    discovered_entry.address,
                    discovered_entry.world_guid
                )
                if existing_index ~= nil then
                    discovered_entry.name = entries[existing_index].name
                end
            end
        end
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
        local status_by_host = {}
        local configured_host_counts = {}
        local function endpoint_host(address)
            return type(address) == "string"
                and address:match("^([%w%.%-]+):%d+$")
                or nil
        end
        for _, discovered_entry in ipairs(discovered_entries) do
            status_by_address[discovered_entry.address:lower()] = discovered_entry
            local discovered_host = endpoint_host(discovered_entry.address)
            if discovered_host ~= nil then
                discovered_host = discovered_host:lower()
                if status_by_host[discovered_host] == nil then
                    status_by_host[discovered_host] = discovered_entry
                else
                    status_by_host[discovered_host] = false
                end
            end
            if type(discovered_entry.world_guid) == "string"
                and discovered_entry.world_guid ~= ""
            then
                status_by_world_guid[discovered_entry.world_guid:lower()] = discovered_entry
            end
        end
        for _, entry in ipairs(entries) do
            local configured_host = endpoint_host(entry.address)
            if configured_host ~= nil then
                configured_host = configured_host:lower()
                configured_host_counts[configured_host] =
                    (configured_host_counts[configured_host] or 0) + 1
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
            if status == nil then
                local configured_host = endpoint_host(entry.address)
                configured_host = configured_host ~= nil
                    and configured_host:lower()
                    or nil
                if configured_host ~= nil
                    and configured_host_counts[configured_host] == 1
                    and type(status_by_host[configured_host]) == "table"
                then
                    status = status_by_host[configured_host]
                end
            end
            if status ~= nil then
                local reconcile_key = entry.address:lower()
                local was_pending = reason == "post-connection-fetch"
                    and pending_reconcile_addresses[reconcile_key] == true
                entry.players = status.players
                entry.max_players = status.max_players or entry.max_players
                entry.ping = status.ping
                local next_world_guid = status.world_guid or entry.world_guid
                local next_name = entry.name
                if reason == "post-connection-fetch"
                    and type(status.name) == "string"
                    and status.name ~= ""
                then
                    next_name = status.name
                end
                local next_protected = entry.password_protected == true
                    or status.password_protected == true
                local next_password = status.password or entry.password
                if entry.world_guid ~= next_world_guid
                    or entry.name ~= next_name
                    or entry.password_protected ~= next_protected
                    or entry.password ~= next_password
                then
                    metadata_changed = true
                end
                entry.world_guid = next_world_guid
                entry.name = next_name
                entry.password_protected = next_protected
                entry.password = next_password
                if was_pending
                    and type(status.world_guid) == "string"
                    and status.world_guid ~= ""
                then
                    pending_reconcile_addresses[reconcile_key] = nil
                    local restored, restore_error = Discovery.restore(entry.address)
                    if not restored then
                        log("Reconciled server removal marker could not be cleared: "
                            .. tostring(restore_error))
                    end
                    reconciled = reconciled + 1
                end
                matched = matched + 1
            else
                entry.players = nil
                entry.max_players = nil
                entry.ping = nil
            end
        end
        if metadata_changed
            and (reason == "status-refresh" or reason == "startup-refresh"
                or reason == "post-connection-fetch")
        then
            persist_server_config(reason == "post-connection-fetch"
                and "Post-connection Recent Servers metadata"
                or "Server metadata refresh")
        end
    end

    if reason == "status-refresh" then
        call_ui("set_statuses", entries)
    else
        call_ui("set_entries", entries, "No active recent servers found")
    end
    return #discovered_entries, matched, reconciled
end

local function start_discovery(reason, already_on_game_thread, target_addresses)
    if refresh_active then
        log("A server status refresh is already in progress.")
        return false
    end
    refresh_active = true
    refresh_blocks_actions = reason == "first-install"
        or reason == "startup-refresh"
        or reason == "force-sync"
    local replace_listing = reason == "first-install" or reason == "force-sync"
    local discovery_ok, started = pcall(Discovery.start, {
        log = log,
        already_on_game_thread = already_on_game_thread == true,
        target_addresses = target_addresses,
        save_cache = replace_listing,
        on_complete = function(discovered)
            refresh_active = false
            refresh_blocks_actions = false
            local count, matched, reconciled = apply_discovery_result(
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
            elseif reason == "post-connection-fetch" then
                if reconciled > 0 then
                    log(string.format(
                        "Post-connection Recent Servers metadata reconciled %d targeted server(s).",
                        reconciled
                    ))
                else
                    log("Post-connection Recent Servers did not yet provide a usable GUID; reconciliation remains queued.")
                end
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
            refresh_blocks_actions = false
            log("Server status refresh unavailable: " .. tostring(message))
            if reason == "first-install" then
                call_ui("set_entries", {}, "Recent-server discovery unavailable")
            elseif reason == "startup-refresh" then
                call_ui("set_entries", entries, "Server status refresh unavailable")
            elseif reason ~= "post-connection-fetch" then
                call_ui("show_refresh_result", false)
            else
                log("Post-connection Recent Servers metadata was unavailable.")
            end
        end,
    })
    if not discovery_ok then
        refresh_active = false
        refresh_blocks_actions = false
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
        refresh_blocks_actions = false
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
    elseif reason == "post-connection-fetch" then
        log("Post-connection Recent Servers metadata fetch started.")
    end
    if reason == "force-sync" or reason == "status-refresh" then
        call_ui("set_refreshing", true)
    end
    return true
end

local function remove_entry(index)
    if refresh_blocks_actions then
        log("Server removal was ignored while status was refreshing.")
        return false
    end
    local entry = entries[index]
    if entry == nil then
        log("Server removal was ignored because the slot does not exist.")
        return false
    end
    if entry.discovered == true then
        local removed, remove_error = Discovery.remove(entry.address)
        if not removed then
            log("Could not save the removed server: " .. tostring(remove_error))
            return false
        end
    end
    table.remove(entries, index)
    if selected_slot > #entries then
        selected_slot = math.max(1, #entries)
    end
    call_ui("set_entries", entries, "No active recent servers found")
    persist_server_config("Server removal")
    log("Removed a server from Quick Connect.")
    return true
end

local function modify_entry(index, values)
    if refresh_blocks_actions or connecting then
        return false
    end
    local previous = entries[index]
    local previous_address = previous ~= nil and previous.address or nil
    local previously_discovered = previous ~= nil and previous.discovered == true
    local updated, update_error, address_changed = Servers.modify(entries, index, values)
    if updated == nil then
        log("Server modification was ignored: " .. tostring(update_error))
        return false
    end
    if address_changed and previously_discovered then
        Discovery.remove(previous_address)
        updated.discovered = false
    end
    persist_server_config("Server modification")
    call_ui("set_entries", entries, "No active recent servers found")
    register_hotkeys()
    return true
end

local function add_and_connect(values)
    if refresh_blocks_actions or connecting or type(values) ~= "table" then
        return false
    end
    if type(values.name) ~= "string"
        or values.name:match("^%s*(.-)%s*$") == ""
    then
        return false
    end
    local normalized, warnings = Servers.load({ {
        name = values.name,
        address = values.address,
        password = values.password,
        password_protected = type(values.password) == "string"
            and values.password ~= "",
        discovered = false,
    } })
    local candidate = normalized[1]
    if candidate == nil then
        log("Manual server connection was ignored: "
            .. tostring(warnings[1] or "invalid server details"))
        return false
    end
    candidate.name = Servers.unique_name(entries, candidate.name)
    candidate.source = "manual"
    Connections.stage_manual(candidate)
    if not connect_entry(candidate, "launch-screen Add Server", true) then
        Connections.cancel_manual()
        return false
    end
    return true
end

Connections.start({
    log = log,
    on_success = function(candidate)
        local manual = candidate.source == "manual"
        local entry, index, upsert_error, added = Servers.upsert_connected(
            entries,
            candidate,
                {
                    unique_name = manual or candidate.generated_name == true,
                    -- Reconnecting through Add Server means the user explicitly
                    -- supplied this name. Native joins still preserve saved names.
                    replace_existing_name = manual,
                }
        )
        if entry == nil then
            log("Successful server connection could not be saved: "
                .. tostring(upsert_error))
            return
        end
        selected_slot = index
        persist_server_config(added
            and "Successful server connection"
            or "Connected server metadata refresh")
        register_hotkeys()
        call_ui("set_entries", entries, "No active recent servers found")
        local restored, restore_error = Discovery.restore(entry.address)
        if not restored then
            log("Connected server removal marker could not be cleared: "
                .. tostring(restore_error))
        end
        log(added
            and "Added the successfully connected server to Quick Connect."
            or "Updated metadata for the successfully connected server.")
        pending_reconcile_addresses[entry.address:lower()] = true
    end,
})

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
                return remove_entry(index)
            end,
            modify = function(index, values)
                return modify_entry(index, values)
            end,
            add = function(values)
                return add_and_connect(values)
            end,
            connection_failed = function()
                Connections.cancel_manual()
            end,
            title_available = function()
                if reconcile_start_scheduled
                    or refresh_active
                    or next(pending_reconcile_addresses) == nil
                then
                    return
                end
                reconcile_start_scheduled = true
                local callback, callback_id = retain_one_shot(function()
                    reconcile_start_scheduled = false
                    local targets = {}
                    for address in pairs(pending_reconcile_addresses) do
                        targets[#targets + 1] = address
                    end
                    if #targets > 0 then
                        start_discovery("post-connection-fetch", false, targets)
                    end
                end)
                local ok, schedule_error = pcall(ExecuteWithDelay, 1, callback)
                if not ok then
                    release_callback(callback_id)
                    reconcile_start_scheduled = false
                    log("Post-connection metadata fetch could not be scheduled: "
                        .. tostring(schedule_error))
                end
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
