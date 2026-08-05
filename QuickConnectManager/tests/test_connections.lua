package.path = "QuickConnectManager/Scripts/?.lua;" .. package.path

local function object(values)
    values = values or {}
    values.IsValid = function()
        return true
    end
    return values
end

local world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Title/PL_Title"
    end,
})
local controller = object({ PlayerState = object() })

local function unreal_string(value)
    return object({
        ToString = function()
            return value
        end,
    })
end

local function unreal_guid(a, b, c, d)
    return object({ A = a, B = b, C = c, D = d })
end

package.preload.UEHelpers = function()
    return {
        GetWorld = function()
            return world
        end,
        GetPlayerController = function()
            return controller
        end,
        GetGameInstance = function()
            return nil
        end,
    }
end

local delayed = {}
local hooks = {}
function ExecuteWithDelay(delay, callback)
    delayed[#delayed + 1] = { delay = delay, callback = callback }
    return true
end
function ExecuteInGameThread(callback)
    callback()
    return true
end
function RegisterHook(path, callback)
    hooks[path] = callback
    return 1, 2
end

local successes = {}
local Connections = require("connections")
Connections.start({
    on_success = function(candidate)
        successes[#successes + 1] = candidate
    end,
})

local failures = 0
local function expect(label, condition)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. "\n")
    end
end

local hook_callback = hooks[
    "/Script/Pal.PalUIJoinGameBase:ConnectServerByAddress"
]
local travel_hook_callback = hooks[
    "/Script/Engine.PlayerController:ClientTravelInternal"
]
local row_hook_callback = hooks[
    "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect_ListContent"
        .. ".WBP_Title_WorldSelect_ListContent_C:"
        .. "BndEvt__WBP_Title_WorldSelect_ListContent_WBP_PalInvisibleButton_"
        .. "K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature"
]
expect("native connection hook registered", type(hook_callback) == "function")
expect("generic network travel hook registered", type(travel_hook_callback) == "function")
expect("dedicated server row hook registered", type(row_hook_callback) == "function")
Connections.stage_manual({
    name = "Lamball 2",
    address = "manual.example:8211",
    password = "fixture-password",
})
hook_callback(object(), "RemoteUnrealParam: 000001AABBCCDD", 8211)
world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Forest/Forest"
    end,
    GameState = object({
        ServerName = unreal_string("Dedicated Server Must Not Replace Manual Name"),
        WorldGUID = unreal_guid(0x11111111, 0x22222222, 0x33333333, 0x44444444),
    }),
})
table.remove(delayed, 1).callback()
expect(
    "manual candidate commits after gameplay transition",
    #successes == 1 and successes[1].source == "manual"
        and successes[1].name == "Lamball 2"
        and successes[1].address == "manual.example:8211"
        and successes[1].world_guid == "11111111222222223333333344444444"
        and successes[1].password == "fixture-password"
)

world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Title/PL_Title"
    end,
})
local display = object({
    ServerName = "Dedicated Chillet",
    ServerAddress = "stock.example",
    ServerPort = 8211,
    WorldGUID = "AAAABBBBCCCCDDDDEEEEFFFF00001111",
})
hook_callback(object({ ClickedServerInfo = display }), "stock.example", 8211)
world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Forest/Forest"
    end,
    GameState = object(),
})
table.remove(delayed, 1).callback()
expect(
    "stock join keeps dedicated server name",
    #successes == 2 and successes[2].source == "stock"
        and successes[2].name == "Dedicated Chillet"
        and successes[2].world_guid == "AAAABBBBCCCCDDDDEEEEFFFF00001111"
)

world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Title/PL_Title"
    end,
})
local function remote_string(value)
    return {
        get = function()
            return unreal_string(value)
        end,
    }
end
hook_callback(object(), remote_string("native-ip.example"), remote_string("8211"))
world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Forest/Forest"
    end,
    GameState = object({
        ServerName = unreal_string("Native IP Mossanda"),
        WorldGUID = unreal_guid(0xABCDEF01, 0x23456789, 0x0BADF00D, 0x76543210),
    }),
})
table.remove(delayed, 1).callback()
expect(
    "native Connect via IP unwraps FString hook parameters",
    #successes == 3 and successes[3].source == "stock"
        and successes[3].address == "native-ip.example:8211"
        and successes[3].generated_name == true
        and successes[3].name ~= "native-ip.example:8211"
        and successes[3].name ~= "Native IP Mossanda"
        and successes[3].world_guid == "ABCDEF01234567890BADF00D76543210"
)

world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Title/PL_Title"
    end,
})
travel_hook_callback(object(), remote_string("travel.example:8211?listen"))
world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Forest/Forest"
    end,
    GameState = object(),
})
table.remove(delayed, 1).callback()
expect(
    "generic ClientTravel server URL is tracked",
    #successes == 4 and successes[4].address == "travel.example:8211"
        and successes[4].generated_name == true
)

world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Title/PL_Title"
    end,
})
local row_display = object({
    ServerName = "Dedicated Row Foxparks",
    ServerAddress = "row.example:8211",
    ServerPort = 27015,
    WorldGUID = "1234567890ABCDEF1234567890ABCDEF",
})
row_hook_callback(object({ CachedServerDisplayData = row_display }))
world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Forest/Forest"
    end,
    GameState = object(),
})
table.remove(delayed, 1).callback()
expect(
    "dedicated server-list row selection captures display metadata",
    #successes == 5 and successes[5].address == "row.example:8211"
        and successes[5].name == "Dedicated Row Foxparks"
        and successes[5].world_guid == "1234567890ABCDEF1234567890ABCDEF"
)

world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Title/PL_Title"
    end,
})
controller = object()
travel_hook_callback(object(), remote_string("no-player-state.example:8211"))
world = object({
    GetFullName = function()
        return "/Game/Pal/Maps/Forest/Forest"
    end,
    GameState = object(),
})
table.remove(delayed, 1).callback()
expect(
    "gameplay confirmation does not wait for an exposed PlayerState",
    #successes == 6
        and successes[6].address == "no-player-state.example:8211"
        and #delayed == 0
)

travel_hook_callback(object(), remote_string("gameplay-only.example:8211"))
expect(
    "network events first observed during gameplay do not start recurring polling",
    #successes == 6 and #delayed == 0
)

if failures > 0 then
    error(string.format("%d test(s) failed", failures))
end
print("Quick Connect Manager connection tracking tests passed")
