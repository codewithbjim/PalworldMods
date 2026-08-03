package.path = "QuickConnectManager/Scripts/?.lua;" .. package.path

package.preload.config = function()
    return {
        servers = {
            {
                name = "Fixture Server",
                address = "fixture.example:8211",
                enabled = true,
                discovered = true,
            },
        },
        hotkeys = { enabled = true, max_slots = 1 },
        diagnostics = { verbose = true },
    }
end

local discovery_callbacks = nil
local connection_count = 0
local removal_count = 0
package.preload.discovery = function()
    return {
        load_cache = function()
            return nil
        end,
        start = function(options)
            discovery_callbacks = options
            return true
        end,
        connect = function()
            connection_count = connection_count + 1
            return true
        end,
        remove = function()
            removal_count = removal_count + 1
            return true
        end,
    }
end

local launch_options = nil
package.preload.launch_ui = function()
    return {
        start = function(options)
            launch_options = options
            return true
        end,
        set_entries = function() end,
        set_refreshing = function() end,
        show_refresh_result = function() end,
        restore_after_failed_connect = function() end,
    }
end

ModifierKey = { CONTROL = 1, SHIFT = 2 }
function RegisterConsoleCommandHandler()
    return true
end
function RegisterKeyBind()
    return true
end
function ExecuteInGameThread(callback)
    callback()
end
function ExecuteWithDelay()
    return true
end

local failures = 0
local function expect(label, condition)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. "\n")
    end
end

require("main")

expect("launch UI receives callbacks", type(launch_options) == "table")
expect("startup refresh begins", type(discovery_callbacks) == "table")
expect("startup refresh blocks UI connect", launch_options.connect(1) == false)
expect("startup refresh blocks removal", launch_options.remove(1) == false)
expect("blocked actions do not enter native services", connection_count == 0 and removal_count == 0)

discovery_callbacks.on_complete({
    {
        name = "Fixture Server",
        address = "fixture.example:8211",
        players = 1,
        max_players = 32,
        ping = 40,
        discovered = true,
    },
})

expect("manual refresh starts after startup completion", launch_options.refresh(false) == true)
expect("manual refresh blocks UI connect", launch_options.connect(1) == false)
expect("manual refresh blocks removal", launch_options.remove(1) == false)
expect("manual refresh still isolates native actions", connection_count == 0 and removal_count == 0)

discovery_callbacks.on_complete({
    {
        name = "Fixture Server",
        address = "fixture.example:8211",
        players = 2,
        max_players = 32,
        ping = 41,
        discovered = true,
    },
})

expect("connect is restored after refresh settlement", launch_options.connect(1) == true)
expect("settled connect enters native service once", connection_count == 1)

if failures > 0 then
    error(string.format("%d test(s) failed", failures))
end
print("Quick Connect Manager refresh interlock tests passed")
