package.preload.UEHelpers = function()
    return {
        GetPlayerController = function()
            return nil
        end,
        GetGameInstance = function()
            return nil
        end,
        FindOrAddFName = function(value)
            return value
        end,
    }
end
package.path = "QuickConnectManager/Scripts/?.lua;" .. package.path

local logs = {}

function ExecuteInGameThread()
    error("fixture game-thread queue unavailable")
end

function ExecuteWithDelay()
    error("fixture delay queue unavailable")
end

local Discovery = require("discovery")
local failures = 0

local function expect(label, condition)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. "\n")
    end
end

local invalid_started, invalid_message = Discovery.connect("bad host|quit")
expect("reject unsafe connection address", invalid_started == false)
expect("return connection validation message", type(invalid_message) == "string")

local first_start = Discovery.start({
    log = function(message)
        logs[#logs + 1] = message
    end,
    on_error = function()
        error("fixture consumer error")
    end,
})
local second_start = Discovery.start({
    log = function(message)
        logs[#logs + 1] = message
    end,
})

expect("first discovery request accepted", first_start == true)
expect("failed queue clears running state", second_start == true)
expect("queue failure logged instead of escaping", #logs >= 2)

if failures > 0 then
    error(string.format("%d test(s) failed", failures))
end
print("Quick Connect Manager discovery tests passed")
