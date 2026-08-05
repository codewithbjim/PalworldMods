local Connections = {}
local UEHelpers = require("UEHelpers")

local CONNECT_EVENT =
    "/Script/Pal.PalUIJoinGameBase:ConnectServerByAddress"
local CLIENT_TRAVEL_EVENT = "/Script/Engine.PlayerController:ClientTravelInternal"
local SERVER_ROW_CLASS =
    "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect_ListContent"
    .. ".WBP_Title_WorldSelect_ListContent_C"
local SERVER_ROW_CLICK_EVENT = SERVER_ROW_CLASS .. ":"
    .. "BndEvt__WBP_Title_WorldSelect_ListContent_WBP_PalInvisibleButton_"
    .. "K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature"
local TITLE_MAP = "/Game/Pal/Maps/Title/PL_Title"
local POLL_MS = 750
local PENDING_TIMEOUT_MS = 180000
local PAL_NAMES = {
    "Lamball", "Cattiva", "Chikipi", "Lifmunk", "Foxparks", "Fuack",
    "Sparkit", "Tanzee", "Pengullet", "Daedream", "Depresso", "Cremis",
    "Vixy", "Hoocrates", "Teafant", "Killamari", "Mau", "Celaray",
    "Direhowl", "Tocotoco", "Flopie", "Mozzarina", "Bristla", "Gobfin",
    "Hangyu", "Mossanda", "Woolipop", "Caprity", "Melpaca", "Eikthyrdeer",
    "Nitewing", "Ribbuny", "Incineram", "Cinnamoth", "Arsox", "Dumud",
    "Galeclaw", "Robinquill", "Gorirat", "Beegarde", "Elizabee", "Grintale",
    "Swee", "Sweepa", "Chillet", "Univolt", "Foxcicle", "Pyrin",
    "Reindrix", "Rayhound", "Dazzi", "Lunaris",
}

local state = {
    started = false,
    polling = false,
    generation = 0,
    hook_registered = false,
    hook_failure_logged = false,
    hook_callback = nil,
    travel_hook_registered = false,
    travel_hook_failure_logged = false,
    travel_hook_callback = nil,
    row_hook_registered = false,
    row_hook_failure_logged = false,
    row_hook_callback = nil,
    row_notification_armed = false,
    row_notification_callback = nil,
    pending = nil,
    was_title = false,
    sequence = 0,
    log = function() end,
    on_success = function() end,
    callback_sequence = 0,
    pending_callbacks = {},
}

local poll

local function safe_log(message)
    pcall(state.log, tostring(message))
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

local function unwrap(value)
    for _ = 1, 4 do
        if value == nil then
            return nil
        end
        local ok, result = pcall(function()
            return value:get()
        end)
        if not ok or result == nil or result == value then
            break
        end
        value = result
    end
    return value
end

local function text(value)
    value = unwrap(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value:match("^%s*(.-)%s*$")
    end
    local converted_ok, converted = pcall(function()
        return value:ToString()
    end)
    if converted_ok and converted ~= nil then
        value = unwrap(converted)
    end
    local ok, result = pcall(tostring, value)
    result = ok and result:match("^%s*(.-)%s*$") or ""
    if result:match("^UObject:%s*[0-9A-Fa-fx]+$")
        or result:match("^TrivialObject:%s*[0-9A-Fa-fx]+$")
        or result:match("^RemoteUnrealParam:")
    then
        return ""
    end
    return result
end

local function number(value)
    value = unwrap(value)
    local result = tonumber(value)
    if result == nil then
        result = tonumber(text(value):match("%-?%d+"))
    end
    return result
end

local function property(object, name)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object[name]
    end)
    return ok and unwrap(value) or nil
end

local function retain_one_shot(callback)
    state.callback_sequence = state.callback_sequence + 1
    local id = state.callback_sequence
    local wrapper = function(...)
        state.pending_callbacks[id] = nil
        return callback(...)
    end
    state.pending_callbacks[id] = wrapper
    return wrapper, id
end

local function schedule(delay_ms, callback)
    local generation = state.generation
    local wrapped, id = retain_one_shot(function()
        if state.started and generation == state.generation then
            callback()
        end
    end)
    local ok = pcall(ExecuteWithDelay, delay_ms, wrapped)
    if not ok then
        state.pending_callbacks[id] = nil
    end
    return ok
end

local function world_context()
    local world_ok, world = pcall(UEHelpers.GetWorld)
    if not world_ok or not alive(world) then
        return nil, nil, false
    end
    local name_ok, name = pcall(function()
        return tostring(world:GetFullName())
    end)
    local controller_ok, controller = pcall(UEHelpers.GetPlayerController)
    return world,
        controller_ok and alive(controller) and controller or nil,
        name_ok and name:find(TITLE_MAP, 1, true) ~= nil
end

local function value_from(object, names)
    for _, name in ipairs(names) do
        local value = property(object, name)
        local converted = text(value)
        if converted ~= "" then
            return converted
        end
    end
    return nil
end

local function guid_value(value)
    value = unwrap(value)
    if value == nil then
        return nil
    end
    local direct = text(value):gsub("[{}%-]", "")
    if direct:match("^[0-9A-Fa-f][0-9A-Fa-f]+$") and #direct == 32 then
        return direct:upper()
    end
    local parts = {}
    for _, field in ipairs({ "A", "B", "C", "D" }) do
        local field_value = property(value, field)
        local numeric = number(field_value)
        if numeric == nil then
            return nil
        end
        numeric = math.floor(numeric) % 4294967296
        parts[#parts + 1] = string.format("%08X", numeric)
    end
    return table.concat(parts)
end

local function guid_from(object, names)
    for _, name in ipairs(names) do
        local converted = guid_value(property(object, name))
        if converted ~= nil then
            return converted
        end
    end
    return nil
end

local function random_pal_name(endpoint)
    local seed = tonumber(os.time()) or 0
    for index = 1, #endpoint do
        seed = (seed * 33 + endpoint:byte(index)) % 2147483647
    end
    seed = seed + state.sequence * 97
    return PAL_NAMES[(seed % #PAL_NAMES) + 1]
end

local function enrich_from_gameplay(candidate, world, controller)
    local game_state = property(world, "GameState")
    local player_state = property(controller, "PlayerState")
    -- The name entered in Add Server is user-owned. Only native joins adopt the
    -- dedicated server's reported name.
    if candidate.source ~= "manual" and candidate.generated_name ~= true then
        candidate.name = value_from(game_state, {
            "ServerName",
            "DedicatedServerName",
            "WorldName",
        }) or candidate.name
    end
    candidate.world_guid = guid_from(game_state, {
        "WorldGUID",
        "WorldGuid",
        "WorldId",
    }) or guid_from(player_state, {
        "WorldGUID",
        "WorldGuid",
    }) or candidate.world_guid
    return candidate
end

local function normalize_endpoint(address, port)
    local value = text(address)
    local embedded_host, embedded_port = value:match("^([%w%.%-]+):(%d+)$")
    if embedded_host ~= nil then
        local port_number = tonumber(embedded_port)
        if port_number ~= nil and port_number >= 1 and port_number <= 65535 then
            return embedded_host .. ":" .. tostring(math.floor(port_number))
        end
        return ""
    end
    if value:match("^[%w%.%-]+$") then
        local port_number = number(port) or 8211
        if port_number >= 1 and port_number <= 65535 then
            return value .. ":" .. tostring(math.floor(port_number))
        end
    end
    -- UE4SS can expose an FString hook argument as a wrapper description rather
    -- than its value. Never let that internal text replace a validated endpoint.
    return ""
end

local function captured_candidate(widget, address, port)
    local display = property(widget, "ClickedServerInfo")
    local endpoint = normalize_endpoint(address, port)
    if endpoint == "" and display ~= nil then
        endpoint = normalize_endpoint(
            property(display, "ServerAddress"),
            property(display, "ServerPort")
        )
    end
    local password = value_from(widget, { "RestoredPassword" })
    local game_instance_ok, game_instance = pcall(UEHelpers.GetGameInstance)
    if password == nil and game_instance_ok and alive(game_instance) then
        password = value_from(game_instance, {
            "InputPassword",
            "RestoredPasswordForDisplay",
        })
    end
    local name = display ~= nil and value_from(display, { "ServerName" }) or nil
    local world_guid = display ~= nil and guid_from(display, {
        "WorldGUID",
        "WorldGuid",
    }) or nil
    return {
        name = name or random_pal_name(endpoint),
        address = endpoint,
        world_guid = world_guid,
        password = password,
        password_protected = password ~= nil and password ~= "",
        discovered = true,
        source = "stock",
        generated_name = name == nil,
    }
end

local function captured_display_candidate(display)
    return captured_candidate({ ClickedServerInfo = display }, "", nil)
end

local function merge_pending(candidate)
    if state.pending ~= nil and state.pending.source == "manual" then
        if candidate.address ~= nil and candidate.address ~= "" then
            state.pending.address = candidate.address
        end
        state.pending.world_guid = candidate.world_guid or state.pending.world_guid
        state.pending.password = state.pending.password or candidate.password
        state.pending.password_protected = state.pending.password ~= nil
            and state.pending.password ~= ""
        return
    end
    state.sequence = state.sequence + 1
    candidate.id = state.sequence
    candidate.elapsed_ms = 0
    state.pending = candidate
end

local function mark_observation_context(candidate)
    local _, _, is_title = world_context()
    candidate.observed_on_title = is_title == true
    return candidate
end

local function register_hook()
    if state.hook_registered then
        return true
    end
    state.hook_callback = state.hook_callback or function(context, address, port)
        local ok, candidate = pcall(
            captured_candidate,
            unwrap(context),
            unwrap(address),
            unwrap(port)
        )
        if ok and type(candidate) == "table" and candidate.address ~= "" then
            merge_pending(mark_observation_context(candidate))
            safe_log("Observed a native Palworld server connection attempt.")
            if not state.polling then
                poll()
            end
        elseif not ok then
            safe_log("Could not capture native connection details: " .. tostring(candidate))
        end
    end
    local ok, pre_id, post_id = pcall(
        RegisterHook,
        CONNECT_EVENT,
        state.hook_callback,
        function() end
    )
    state.hook_registered = ok and pre_id ~= nil
    if not state.hook_registered and not state.hook_failure_logged then
        state.hook_failure_logged = true
        safe_log("Native connection observer is not available yet.")
    elseif state.hook_registered then
        state.hook_failure_logged = false
    end
    return state.hook_registered
end

local function endpoint_from_travel_url(url)
    local value = text(url)
    local endpoint = value:match("^([%w%.%-]+:%d+)")
        or value:match("^[%a]+://([%w%.%-]+:%d+)")
    if endpoint == nil then
        return ""
    end
    return normalize_endpoint(endpoint)
end

local function register_travel_hook()
    if state.travel_hook_registered then
        return true
    end
    -- Connect via IP and Recent Servers have richer UI hooks. ClientTravel is
    -- retained only as the fallback for title/cold-start Steam or Discord invites.
    state.travel_hook_callback = state.travel_hook_callback or function(_, url)
        local ok, endpoint = pcall(endpoint_from_travel_url, url)
        if not ok or endpoint == "" then
            return
        end
        if state.pending == nil then
            merge_pending(mark_observation_context({
                name = random_pal_name(endpoint),
                address = endpoint,
                password_protected = false,
                discovered = true,
                source = "stock",
                generated_name = true,
            }))
        end
        safe_log("Observed an Unreal network server travel request.")
        if not state.polling then
            poll()
        end
    end
    local ok, pre_id = pcall(
        RegisterHook,
        CLIENT_TRAVEL_EVENT,
        state.travel_hook_callback,
        function() end
    )
    state.travel_hook_registered = ok and pre_id ~= nil
    if not state.travel_hook_registered and not state.travel_hook_failure_logged then
        state.travel_hook_failure_logged = true
        safe_log("Generic network travel observer is not available yet.")
    elseif state.travel_hook_registered then
        state.travel_hook_failure_logged = false
    end
    return state.travel_hook_registered
end

local function register_server_row_hook()
    if state.row_hook_registered then
        return true
    end
    state.row_hook_callback = state.row_hook_callback or function(context)
        local ok, candidate = pcall(function()
            local row = unwrap(context)
            local display = property(row, "CachedServerDisplayData")
            if display == nil then
                local display_ok, result = pcall(function()
                    return row:GetBindedServerDisplayData()
                end)
                display = display_ok and unwrap(result) or nil
            end
            return captured_display_candidate(display)
        end)
        if not ok or type(candidate) ~= "table" or candidate.address == "" then
            return
        end
        merge_pending(mark_observation_context(candidate))
        safe_log("Observed a Palworld dedicated server-list row selection.")
        if not state.polling then
            poll()
        end
    end
    local ok, pre_id = pcall(
        RegisterHook,
        SERVER_ROW_CLICK_EVENT,
        state.row_hook_callback,
        function() end
    )
    state.row_hook_registered = ok and pre_id ~= nil
    if not state.row_hook_registered and not state.row_hook_failure_logged then
        state.row_hook_failure_logged = true
        safe_log("Dedicated server-list row observer is not available yet.")
    elseif state.row_hook_registered then
        state.row_hook_failure_logged = false
    end
    return state.row_hook_registered
end

local function arm_server_row_notification()
    if state.row_notification_armed then
        return true
    end
    state.row_notification_callback = state.row_notification_callback or function()
        if state.row_hook_registered then
            return
        end
        local registered = register_server_row_hook()
        if registered and state.row_hook_registered then
            safe_log("Dedicated server-list row observer became available.")
        end
    end
    local ok = pcall(
        NotifyOnNewObject,
        SERVER_ROW_CLASS,
        state.row_notification_callback
    )
    state.row_notification_armed = ok
    return ok
end

poll = function()
    state.polling = true
    local queued = pcall(ExecuteInGameThread, function()
        register_hook()
        local world, controller, is_title = world_context()
        if state.pending ~= nil then
            state.pending.elapsed_ms = (state.pending.elapsed_ms or 0) + POLL_MS
            if is_title then
                state.pending.observed_on_title = true
            end
            if state.was_title and not is_title then
                state.pending.left_title = true
            end
            if state.pending.left_title == true and not is_title and alive(world)
                and alive(controller)
            then
                local completed = enrich_from_gameplay(state.pending, world, controller)
                state.pending = nil
                local ok, callback_error = pcall(state.on_success, completed)
                if not ok then
                    safe_log("Successful connection callback failed safely: "
                        .. tostring(callback_error))
                end
            elseif state.pending.observed_on_title == false and not is_title then
                safe_log("Ignored a server connection event observed during gameplay.")
                state.pending = nil
            elseif state.pending.left_title == true and is_title then
                safe_log("Discarded a server connection that returned to the title world.")
                state.pending = nil
            elseif state.pending.elapsed_ms >= PENDING_TIMEOUT_MS then
                safe_log("Discarded an unconfirmed server connection attempt.")
                state.pending = nil
            end
        end
        state.was_title = is_title
        if state.pending ~= nil then
            schedule(POLL_MS, poll)
        else
            state.polling = false
        end
    end)
    if not queued then
        state.polling = false
        safe_log("Connection observer could not enter the game thread.")
    end
end

function Connections.stage_manual(candidate)
    if type(candidate) ~= "table" then
        return false
    end
    state.sequence = state.sequence + 1
    state.pending = {
        id = state.sequence,
        elapsed_ms = 0,
        name = candidate.name,
        address = candidate.address,
        password = candidate.password,
        password_protected = type(candidate.password) == "string"
            and candidate.password ~= "",
        discovered = false,
        source = "manual",
        observed_on_title = select(3, world_context()) == true,
    }
    if state.started and not state.polling then
        poll()
    end
    return true
end

function Connections.cancel_manual()
    if state.pending ~= nil and state.pending.source == "manual" then
        state.pending = nil
        return true
    end
    return false
end

function Connections.start(options)
    options = type(options) == "table" and options or {}
    if state.started then
        return false
    end
    state.log = type(options.log) == "function" and options.log or function() end
    state.on_success = type(options.on_success) == "function"
        and options.on_success
        or function() end
    state.started = true
    state.generation = state.generation + 1
    local _, _, is_title = world_context()
    state.was_title = is_title
    register_hook()
    register_travel_hook()
    register_server_row_hook()
    arm_server_row_notification()
    return true
end

return Connections
