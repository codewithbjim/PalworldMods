package.path = "QuickConnectManager/Scripts/?.lua;" .. package.path

local delayed = {}
local completion_hook = nil
local ping_complete_hook = nil
local ping_failure_hook = nil
local ping_host = nil
local invalidated_address = nil
local native_request_count = 0
local bp_request = nil
local empty_count = 0
local discovered = nil
local completion_count = 0
local last_server_row = nil

local function object(address)
    return {
        IsValid = function()
            return true
        end,
        GetAddress = function()
            return address
        end,
    }
end

local controller = object("controller")
local join_class = object("join-class")
local server_row_class = object("server-row-class")
local subsystem_class = object("subsystem-class")
local ping_cache_subsystem = object("ping-cache-subsystem")
ping_cache_subsystem.AddPingResultCache = function(_, address, ping)
    if ping == -1 then
        invalidated_address = address
    end
end
local subsystem_library = object("subsystem-library")
subsystem_library.GetGameInstanceSubsystem = function()
    return ping_cache_subsystem
end
local rows = {
    {
        ServerListType = 2,
        ServerAddress = "127.0.0.1",
        ServerPort = 8211,
        ServerName = "Stale History Row",
        Ping = 17,
        NowPlayerNum = 1,
        MaxPlayerNum = 32,
        IsLocked = false,
        WorldGUID = "fixture-stale",
    },
}
local cached_array = {
    Empty = function()
        empty_count = empty_count + 1
        rows = {}
    end,
    ForEach = function(_, callback)
        for index, row in ipairs(rows) do
            callback(index, row)
        end
    end,
}
local widget = object("history-widget")
widget.CachedServerDisplayInfo = cached_array
widget.SetVisibility = function() end
widget.RemoveFromParent = function() end
widget.RequestGetServerListBP = function(_, ...)
    bp_request = { ... }
    rows = {
        {
            -- Palworld can tag the live enriched result as Community even
            -- though it was returned by the History query.
            ServerListType = 1,
            ServerAddress = "127.0.0.1:8211",
            ServerPort = 27015,
            ServerName = "Fresh History Row",
            Ping = 42,
            NowPlayerNum = 3,
            MaxPlayerNum = 0,
            IsLocked = false,
            WorldGUID = "fixture-fresh",
        },
        {
            -- The paired History placeholder has no live status and must not
            -- replace the enriched result above.
            ServerListType = 2,
            ServerAddress = "127.0.0.1:8211",
            ServerPort = 8211,
            ServerName = "History Placeholder",
            Ping = -1,
            NowPlayerNum = -1,
            MaxPlayerNum = 32,
            IsLocked = false,
            WorldGUID = "fixture-fresh",
        },
    }
    completion_hook({
        get = function()
            return widget
        end,
    })
end
widget.RequestGetServerList = function()
    native_request_count = native_request_count + 1
end

local widget_library = object("widget-library")
local server_row_sequence = 0
widget_library.Create = function(_, _, class)
    if class == join_class then
        return widget
    end
    server_row_sequence = server_row_sequence + 1
    local row_widget = object("server-row-widget-" .. tostring(server_row_sequence))
    last_server_row = row_widget
    row_widget.SetVisibility = function() end
    row_widget.RemoveFromParent = function() end
    row_widget.SetupByServerDisplayData = function(_, display_data)
        ping_host = display_data.ServerAddress
        ping_complete_hook(
            {
                get = function()
                    return row_widget
                end,
            },
            object("ping-operation"),
            display_data.ServerAddress,
            {
                get = function()
                    return 57
                end,
            }
        )
    end
    return row_widget
end

package.preload.UEHelpers = function()
    return {
        GetPlayerController = function()
            return controller
        end,
        GetGameInstance = function()
            return nil
        end,
        FindOrAddFName = function(value)
            return value
        end,
    }
end

function StaticFindObject(path)
    if path == "/Game/Pal/Blueprint/UI/Title/WBP_JoinGame.WBP_JoinGame_C" then
        return join_class
    end
    if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then
        return widget_library
    end
    if path == "/Script/Engine.Default__SubsystemBlueprintLibrary" then
        return subsystem_library
    end
    if path == "/Script/PocketpairUser.PocketpairUserSubsystem" then
        return subsystem_class
    end
    if path == "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect_ListContent.WBP_Title_WorldSelect_ListContent_C" then
        return server_row_class
    end
    return nil
end

function RegisterHook(path, callback)
    if path == "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect_ListContent.WBP_Title_WorldSelect_ListContent_C:OnPingComplete" then
        ping_complete_hook = callback
    elseif path == "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect_ListContent.WBP_Title_WorldSelect_ListContent_C:OnPingFailure" then
        ping_failure_hook = callback
    else
        completion_hook = callback
    end
    return true
end

function ExecuteInGameThread(callback)
    callback()
end

function ExecuteWithDelay(delay, callback)
    delayed[#delayed + 1] = {
        delay = delay,
        callback = callback,
    }
end

local function run_delay(delay)
    for index, item in ipairs(delayed) do
        if item.delay == delay then
            table.remove(delayed, index)
            item.callback()
            return true
        end
    end
    return false
end

local Discovery = require("discovery")
local failures = 0
local function expect(label, condition)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. "\n")
    end
end

local started = Discovery.start({
    save_cache = false,
    on_complete = function(servers)
        completion_count = completion_count + 1
        discovered = servers
    end,
})

expect("refresh request starts", started == true)
expect("request waits for widget construction", bp_request == nil)
expect("settle callback exists", run_delay(750))
expect("stale cached rows are cleared", empty_count == 1)
expect("Palworld History wrapper is used", bp_request ~= nil)
expect("History filter passed to wrapper", bp_request[1] == 2)
expect("empty region passed to wrapper", bp_request[2] == "")
expect("first page passed to wrapper", bp_request[3] == 0)
expect("empty search passed to wrapper", bp_request[4] == "")
expect("Latest sort passed to wrapper", bp_request[5] == 0)
expect("low-level fallback not used", native_request_count == 0)
expect("result collection callback exists", run_delay(250))
expect("stock row ping receives Palworld's display data", ping_host == "127.0.0.1:8211")
expect("stock ping cache is invalidated before setup", invalidated_address == ping_host)
expect("stock row ping completion callback exists", run_delay(0))
expect("one fresh server collected", type(discovered) == "table" and #discovered == 1)
expect("stock row ping replaces server-list cache", discovered[1].ping == 57)
expect("fresh player count collected", discovered[1].players == 3)
expect("embedded game port is normalized", discovered[1].address == "127.0.0.1:8211")
expect("missing capacity does not reject status row", discovered[1].max_players == nil)

-- A native operation may complete again after the row has been released or
-- after the bounded timeout has already settled the request. Both paths must be
-- harmless and must not publish a second status result.
ping_complete_hook(
    {
        get = function()
            return last_server_row
        end,
    },
    object("late-ping-operation"),
    ping_host,
    99
)
expect("late released-row ping is ignored", not run_delay(0))
expect("settled ping timeout is harmless", run_delay(3000))
expect("request timeout is harmless after completion", run_delay(30000))
expect("discovery completes only once", completion_count == 1)
expect("late callbacks cannot replace the settled ping", discovered[1].ping == 57)

if failures > 0 then
    error(string.format("%d test(s) failed", failures))
end
print("Quick Connect Manager fresh refresh tests passed")
