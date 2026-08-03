package.preload.UEHelpers = function()
    return {
        GetWorld = function()
            return nil
        end,
        GetPlayerController = function()
            return nil
        end,
        FindOrAddFName = function(value)
            return value
        end,
    }
end
package.path = "QuickConnectManager/Scripts/?.lua;" .. package.path

local delayed = {}
local game_thread_calls = 0
local notifications = {}

function ExecuteInGameThread(callback)
    game_thread_calls = game_thread_calls + 1
    callback()
end

function ExecuteWithDelay(delay, callback)
    delayed[#delayed + 1] = {
        delay = delay,
        callback = callback,
    }
end

function NotifyOnNewObject(class_name, callback)
    notifications[class_name] = (notifications[class_name] or 0) + 1
end

function FindAllOf()
    return {}
end

local LaunchUI = require("launch_ui")
local failures = 0

local function delayed_count(delay)
    local count = 0
    for _, item in ipairs(delayed) do
        if item.delay == delay then
            count = count + 1
        end
    end
    return count
end

local function expect(label, condition)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. "\n")
    end
end

local started = LaunchUI.start({
    entries = {},
    ready = false,
    log = function() end,
})
local delayed_after_first_start = #delayed
local game_threads_after_first_start = game_thread_calls
local restarted = LaunchUI.start({
    entries = {},
    log = function() end,
})

expect("first start accepted", started == true)
expect("duplicate start rejected", restarted == false)
expect("deferred startup does not queue a panel render", delayed_count(50) == 0)
expect("one title notification", notifications[
    "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_TitleMenu.WBP_TitleMenu_C"
] == 1)
expect("one disclaimer notification", notifications[
    "/Game/Pal/Blueprint/UI/Mods/WBP_ModDisclaimerDialog.WBP_ModDisclaimerDialog_C"
] == 1)
expect(
    "duplicate start does not start another lifecycle poll",
    game_thread_calls == game_threads_after_first_start
)
expect("first lifecycle poll schedules one successor", delayed_after_first_start == 1)

LaunchUI.set_entries({}, "Refresh complete")
expect("entry update still waits for a stable title widget", delayed_count(50) == 0)

-- Run one delayed lifecycle callback. A serialized poll consumes one callback
-- and schedules exactly one successor rather than accumulating overlapping work.
local next_poll = table.remove(delayed, 1)
next_poll.callback()
expect("serialized lifecycle poll queues one successor", #delayed == 1)

if failures > 0 then
    error(string.format("%d test(s) failed", failures))
end
print("Quick Connect Manager launch UI tests passed")
