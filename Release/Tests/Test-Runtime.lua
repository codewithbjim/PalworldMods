if _VERSION ~= "Lua 5.4" then
    error("Perfect Placement runtime tests require Lua 5.4; found " .. _VERSION)
end

local repo_root = arg and arg[1]
if type(repo_root) ~= "string" or repo_root == "" then
    error("Usage: lua Test-Runtime.lua <repository-root>")
end
repo_root = repo_root:gsub("\\", "/"):gsub("/+$", "")
package.path = repo_root .. "/PerfectPlacement/Scripts/?.lua;" .. package.path

package.loaded.runtime = nil
local Runtime = require("runtime")
local Keybindings = require("keybindings")

local function fail(message)
    error(message, 2)
end

local function assert_true(value, message)
    if value ~= true then
        fail(message or ("expected true, got " .. tostring(value)))
    end
end

local function assert_false(value, message)
    if value ~= false then
        fail(message or ("expected false, got " .. tostring(value)))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        fail(string.format(
            "%s (expected %s, got %s)",
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ))
    end
end

local function assert_contains(values, fragment, message)
    for _, value in ipairs(values) do
        if tostring(value):find(fragment, 1, true) then
            return
        end
    end
    fail(message or ("missing log fragment: " .. fragment))
end

local ue4ss_api_names = {
    "CancelDelayedAction",
    "EGameThreadMethod",
    "EngineTickAvailable",
    "ExecuteInGameThread",
    "ExecuteInGameThreadWithDelay",
    "ExecuteWithDelay",
    "IsValidDelayedActionHandle",
    "LoopInGameThreadAfterFrames",
    "LoopInGameThreadWithDelay",
    "PauseDelayedAction",
    "UnpauseDelayedAction",
}

local function clear_ue4ss_api()
    for _, name in ipairs(ue4ss_api_names) do
        _G[name] = nil
    end
end

local function new_mock(options)
    options = options or {}
    clear_ue4ss_api()

    local state = {
        actions = {},
        cancel_calls = 0,
        created_callbacks = {},
        delayed_handles = {},
        engine_callbacks = {},
        engine_queue = {},
        execute_calls = 0,
        execute_throws = options.execute_throws == true,
        legacy_delay_calls = 0,
        max_engine_pending = 0,
        next_handle = 100,
        pause_calls = 0,
        unpause_calls = 0,
    }

    local function add_action(kind, interval, callback)
        assert(type(callback) == "function", kind .. " callback must be a function")
        state.next_handle = state.next_handle + 1
        local handle = state.next_handle
        state.actions[handle] = {
            callback = callback,
            interval = interval,
            kind = kind,
            paused = false,
            valid = true,
        }
        state.created_callbacks[#state.created_callbacks + 1] = callback
        return handle
    end

    function state:active_action_count(kind)
        local count = 0
        for _, action in pairs(self.actions) do
            if action.valid and (kind == nil or action.kind == kind) then
                count = count + 1
            end
        end
        return count
    end

    function state:first_active_handle(kind)
        for handle, action in pairs(self.actions) do
            if action.valid and (kind == nil or action.kind == kind) then
                return handle
            end
        end
        return nil
    end

    function state:tick_loops()
        local handles = {}
        for handle, action in pairs(self.actions) do
            if action.valid
                and not action.paused
                and (action.kind == "frame-loop"
                    or action.kind == "delay-loop")
            then
                handles[#handles + 1] = handle
            end
        end
        table.sort(handles)
        for _, handle in ipairs(handles) do
            local action = self.actions[handle]
            if action.valid and not action.paused then
                action.callback()
            end
        end
    end

    function state:fire_delayed(handle)
        local action = self.actions[handle]
        assert(action ~= nil and action.valid, "delayed action is not active")
        assert(
            action.kind == "owned-delay" or action.kind == "legacy-delay",
            "action is not a one-shot delay"
        )
        action.valid = false
        action.callback()
    end

    function state:run_engine_tick()
        local callbacks = self.engine_queue
        self.engine_queue = {}
        for _, callback in ipairs(callbacks) do
            callback()
        end
    end

    function state:run_engine_until_idle(limit)
        local remaining = limit or 1000
        while #self.engine_queue > 0 do
            assert(remaining > 0, "engine queue did not become idle")
            remaining = remaining - 1
            self:run_engine_tick()
        end
    end

    EngineTickAvailable = options.engine_tick_available ~= false
    EGameThreadMethod = { EngineTick = "EngineTick" }

    ExecuteInGameThread = function(callback, method)
        assert(type(callback) == "function", "engine callback must be a function")
        if state.execute_throws then
            error("mock ExecuteInGameThread failure")
        end
        if EngineTickAvailable then
            assert_equal(method, EGameThreadMethod.EngineTick, "wrong queue method")
        end
        state.execute_calls = state.execute_calls + 1
        state.engine_callbacks[#state.engine_callbacks + 1] = callback
        state.engine_queue[#state.engine_queue + 1] = callback
        state.max_engine_pending =
            math.max(state.max_engine_pending, #state.engine_queue)
        return true
    end

    if options.frame_loop ~= false then
        LoopInGameThreadAfterFrames = function(frames, callback)
            return add_action("frame-loop", frames, callback)
        end
    end
    if options.delay_loop ~= false then
        LoopInGameThreadWithDelay = function(delay_ms, callback)
            return add_action("delay-loop", delay_ms, callback)
        end
    end

    if options.owned_controls ~= false then
        PauseDelayedAction = function(handle)
            state.pause_calls = state.pause_calls + 1
            local action = state.actions[handle]
            if action == nil or not action.valid then
                return false
            end
            action.paused = true
            return true
        end
        UnpauseDelayedAction = function(handle)
            state.unpause_calls = state.unpause_calls + 1
            local action = state.actions[handle]
            if action == nil or not action.valid or not action.paused then
                return false
            end
            action.paused = false
            return true
        end
        CancelDelayedAction = function(handle)
            state.cancel_calls = state.cancel_calls + 1
            if state.cancel_calls <= (options.cancel_failures or 0) then
                return false
            end
            local action = state.actions[handle]
            if action == nil or not action.valid then
                return false
            end
            action.valid = false
            return true
        end
        IsValidDelayedActionHandle = function(handle)
            local action = state.actions[handle]
            return action ~= nil and action.valid
        end
    end

    if options.owned_delay ~= false then
        ExecuteInGameThreadWithDelay = function(delay_ms, callback)
            local handle = add_action("owned-delay", delay_ms, callback)
            state.delayed_handles[#state.delayed_handles + 1] = handle
            return handle
        end
    end
    if options.legacy_delay ~= false then
        ExecuteWithDelay = function(delay_ms, callback)
            state.legacy_delay_calls = state.legacy_delay_calls + 1
            local handle = add_action("legacy-delay", delay_ms, callback)
            state.delayed_handles[#state.delayed_handles + 1] = handle
        end
    end

    return state
end

local tests = {}

tests["shifted keypad chords use Windows navigation events"] = function()
    local bindings = Keybindings.resolve({
        move_right = {
            key = "NUMPAD_6",
            modifiers = { "SHIFT" },
        },
        move_up = {
            key = "NUMPAD_3",
            modifiers = { "ALT", "SHIFT" },
        },
        move_down = {
            key = "NUMPAD_1",
            modifiers = { "CONTROL", "ALT", "SHIFT" },
        },
        step_down = {
            key = "NUMPAD_DECIMAL",
            modifiers = { "SHIFT" },
        },
    })

    local right = Keybindings.get_shifted_keypad_registration(
        bindings.move_right
    )
    assert_equal(right.virtual_key, 0x27, "Numpad 6 must translate to Right")
    assert_equal(#right.modifiers, 0, "translated Right must omit Shift")

    local up = Keybindings.get_shifted_keypad_registration(bindings.move_up)
    assert_equal(up.virtual_key, 0x22, "Numpad 3 must translate to Page Down")
    assert_equal(#up.modifiers, 1, "translated Page Down modifier count")
    assert_equal(up.modifiers[1], "ALT", "translated Page Down must keep Alt")

    local down = Keybindings.get_shifted_keypad_registration(
        bindings.move_down
    )
    assert_equal(down.virtual_key, 0x23, "Numpad 1 must translate to End")
    assert_equal(#down.modifiers, 2, "translated End modifier count")
    assert_equal(down.modifiers[1], "CONTROL", "translated End must keep Control")
    assert_equal(down.modifiers[2], "ALT", "translated End must keep Alt")

    local decimal = Keybindings.get_shifted_keypad_registration(
        bindings.step_down
    )
    assert_equal(
        decimal.virtual_key,
        0x2E,
        "Numpad Decimal must translate to Delete"
    )
    assert_equal(#decimal.modifiers, 0, "translated Delete must omit Shift")

    assert_equal(
        Keybindings.get_shifted_keypad_registration(bindings.move_left),
        nil,
        "plain keypad chords must not get a Shift translation"
    )
end

tests["pulse owns one paused callback through 10k GC cycles"] = function()
    local mock = new_mock()
    local logs = {}
    local calls = 0
    local runtime = Runtime.new(function(message)
        logs[#logs + 1] = message
    end)
    local trigger = runtime.pulse(function()
        calls = calls + 1
        if calls == 1 then
            error("intentional pulse failure")
        end
    end, "Movement pulse")

    assert_equal(type(trigger), "function", "pulse did not return a trigger")
    assert_equal(mock:active_action_count("frame-loop"), 1, "pulse loop count")
    local handle = mock:first_active_handle("frame-loop")
    local stable_callback = mock.actions[handle].callback
    assert_true(mock.actions[handle].paused, "pulse did not start paused")
    assert_equal(mock.execute_calls, 0, "pulse unexpectedly used one-shot queue")

    for cycle = 1, 10000 do
        for _ = 1, 4 do
            assert_true(trigger(), "pulse trigger rejected a valid action")
        end
        mock:tick_loops()
        assert_true(mock.actions[handle].paused, "pulse did not self-pause")
        assert_equal(
            mock.actions[handle].callback,
            stable_callback,
            "pulse callback identity changed"
        )
        if cycle % 100 == 0 then
            collectgarbage("collect")
        end
    end

    assert_equal(calls, 10000, "pulse did not coalesce repeated triggers")
    assert_equal(#mock.created_callbacks, 1, "pulse created callback churn")
    assert_equal(mock.execute_calls, 0, "pulse fell back during stress test")
    assert_contains(logs, "intentional pulse failure", "pulse error was not logged")
end

tests["throttle reuses one delayed callback under sustained input"] = function()
    local mock = new_mock()
    local calls = 0
    local runtime = Runtime.new()
    local trigger = runtime.throttle(50, function()
        calls = calls + 1
    end, "Validity throttle")

    assert_equal(type(trigger), "function", "throttle trigger missing")
    assert_equal(mock:active_action_count("delay-loop"), 1, "throttle loop count")
    local handle = mock:first_active_handle("delay-loop")
    local stable_callback = mock.actions[handle].callback
    assert_true(mock.actions[handle].paused, "throttle did not start paused")

    for _ = 1, 1000 do
        for _ = 1, 8 do
            assert_true(trigger(), "throttle rejected a valid trigger")
        end
        mock:tick_loops()
        assert_true(mock.actions[handle].paused, "throttle did not self-pause")
        assert_equal(
            mock.actions[handle].callback,
            stable_callback,
            "throttle callback identity changed"
        )
    end

    assert_equal(calls, 1000, "throttle did not coalesce each burst")
    assert_equal(#mock.created_callbacks, 1, "throttle created callback churn")
    assert_equal(mock.execute_calls, 0, "throttle used the one-shot queue")
end

tests["owned loop retains one callback and cancels"] = function()
    local mock = new_mock({ frame_loop = false })
    local calls = 0
    local runtime = Runtime.new()
    local cancel = runtime.loop(25, function()
        calls = calls + 1
    end, "Lifecycle loop")

    assert_equal(type(cancel), "function", "loop did not return a cancel function")
    assert_equal(mock:active_action_count("delay-loop"), 1, "loop count")
    local handle = mock:first_active_handle("delay-loop")
    local stable_callback = mock.actions[handle].callback
    for _ = 1, 5 do
        mock:tick_loops()
        collectgarbage("collect")
        assert_equal(
            mock.actions[handle].callback,
            stable_callback,
            "loop callback identity changed"
        )
    end
    assert_equal(calls, 5, "owned loop did not run five times")
    assert_true(cancel(), "owned loop did not cancel")
    assert_true(cancel(), "owned loop cancellation was not idempotent")
    mock:tick_loops()
    assert_equal(calls, 5, "canceled loop ran again")
end

tests["failed loop cancellation retains ownership and retries"] = function()
    local mock = new_mock({
        cancel_failures = 1,
        frame_loop = false,
    })
    local calls = 0
    local runtime = Runtime.new()
    local cancel = runtime.loop(10, function()
        calls = calls + 1
        return true
    end, "Retrying loop")

    assert_equal(type(cancel), "function", "retry loop was not created")
    mock:tick_loops()
    assert_equal(calls, 1, "retry loop callback count after first tick")
    assert_equal(mock:active_action_count("delay-loop"), 1, "loop retired early")
    mock:tick_loops()
    assert_equal(calls, 1, "loop callback repeated while cancellation retried")
    assert_equal(mock:active_action_count("delay-loop"), 0, "retry did not cancel")
    assert_equal(mock.cancel_calls, 2, "cancellation was not retried once")
end

tests["loop return and error stop only their own action"] = function()
    local mock = new_mock({ frame_loop = false })
    local logs = {}
    local runtime = Runtime.new(function(message)
        logs[#logs + 1] = message
    end)
    local stop_calls = 0
    local cancel_stop = runtime.loop(10, function()
        stop_calls = stop_calls + 1
        return stop_calls == 2
    end, "Self-stopping loop")
    local error_calls = 0
    local cancel_error = runtime.loop(10, function()
        error_calls = error_calls + 1
        error("intentional loop failure")
    end, "Failing loop")

    assert_equal(type(cancel_stop), "function", "self-stopping loop was not created")
    assert_equal(type(cancel_error), "function", "failing loop was not created")
    mock:tick_loops()
    mock:tick_loops()
    assert_equal(stop_calls, 2, "self-stopping loop call count")
    assert_equal(error_calls, 1, "failing loop was not isolated")
    assert_equal(mock:active_action_count("delay-loop"), 0, "loop remained active")
    assert_contains(logs, "intentional loop failure", "loop error was not logged")
end

tests["execute fallback is FIFO with at most one stable drain"] = function()
    local mock = new_mock()
    local logs = {}
    local runtime = Runtime.new(function(message)
        logs[#logs + 1] = message
    end, {
        queue_limit = 128,
    })
    local order = {}

    for value = 1, 100 do
        assert_true(runtime.execute(function()
            order[#order + 1] = value
            if value == 4 then
                error("intentional FIFO failure")
            end
        end, "FIFO job " .. value), "execute rejected FIFO job")
    end

    assert_equal(#mock.engine_queue, 1, "more than one drain was outstanding")
    mock:run_engine_until_idle()
    assert_equal(#order, 100, "FIFO queue skipped work after an error")
    for index = 1, 100 do
        assert_equal(order[index], index, "FIFO order changed")
    end
    assert_equal(mock.execute_calls, 1, "drain rescheduled itself in EngineTick")
    assert_equal(mock.max_engine_pending, 1, "multiple drains were outstanding")
    local stable_callback = mock.engine_callbacks[1]
    for _, callback in ipairs(mock.engine_callbacks) do
        assert_equal(callback, stable_callback, "drain callback identity changed")
    end
    assert_contains(logs, "intentional FIFO failure", "FIFO error was not logged")
end

tests["execute scheduling failure rolls back and can recover"] = function()
    local mock = new_mock({ execute_throws = true })
    local logs = {}
    local runtime = Runtime.new(function(message)
        logs[#logs + 1] = message
    end)
    local calls = 0

    assert_false(runtime.execute(function()
        calls = calls + 1
    end), "failed scheduler was reported as successful")
    assert_equal(calls, 0, "work ran despite scheduler failure")
    assert_equal(#mock.engine_queue, 0, "failed scheduler retained pending work")
    assert_contains(logs, "mock ExecuteInGameThread failure")

    mock.execute_throws = false
    assert_true(runtime.execute(function()
        calls = calls + 1
    end), "scheduler did not recover after a failed enqueue")
    mock:run_engine_until_idle()
    assert_equal(calls, 1, "recovered scheduler did not run new work")
end

tests["delay prefers owned game-thread actions and isolates errors"] = function()
    local mock = new_mock()
    local logs = {}
    local calls = 0
    local runtime = Runtime.new(function(message)
        logs[#logs + 1] = message
    end)

    assert_true(runtime.delay(20, function()
        error("intentional delayed failure")
    end, "First delay"), "first owned delay was rejected")
    assert_true(runtime.delay(30, function()
        calls = calls + 1
    end, "Second delay"), "second owned delay was rejected")
    assert_equal(mock.legacy_delay_calls, 0, "legacy delay was used unexpectedly")
    mock:fire_delayed(mock.delayed_handles[1])
    mock:fire_delayed(mock.delayed_handles[2])
    assert_equal(calls, 1, "delayed error killed subsequent work")
    assert_contains(logs, "intentional delayed failure", "delay error was not logged")
end

tests["legacy delay enters the one-outstanding stable FIFO"] = function()
    local mock = new_mock({ owned_delay = false })
    local runtime = Runtime.new()
    local order = {}

    assert_true(runtime.delay(5, function()
        order[#order + 1] = "first"
    end, "Legacy first"), "legacy delay was rejected")
    assert_true(runtime.delay(5, function()
        order[#order + 1] = "second"
    end, "Legacy second"), "second legacy delay was rejected")
    mock:fire_delayed(mock.delayed_handles[1])
    mock:fire_delayed(mock.delayed_handles[2])
    assert_equal(#mock.engine_queue, 1, "legacy callbacks created drain churn")
    mock:run_engine_until_idle()
    assert_equal(order[1], "first", "legacy FIFO first value")
    assert_equal(order[2], "second", "legacy FIFO second value")
    assert_equal(mock.max_engine_pending, 1, "legacy drain overlap")
end

tests["missing owned pulse API uses the stable execute fallback"] = function()
    local mock = new_mock({
        delay_loop = false,
        frame_loop = false,
        owned_controls = false,
    })
    local calls = 0
    local runtime = Runtime.new()
    local trigger = runtime.pulse(function()
        calls = calls + 1
    end, "Fallback pulse")

    assert_equal(type(trigger), "function", "fallback pulse trigger missing")
    for _ = 1, 8 do
        assert_true(trigger(), "fallback pulse rejected work")
    end
    assert_equal(#mock.engine_queue, 1, "fallback pulse queued multiple drains")
    mock:run_engine_until_idle()
    assert_equal(calls, 8, "fallback pulse lost FIFO work")
    assert_equal(mock.max_engine_pending, 1, "fallback pulse drain overlap")
end

local failures = {}
local passed = 0
local names = {}
for name in pairs(tests) do
    names[#names + 1] = name
end
table.sort(names)

for _, name in ipairs(names) do
    local ok, error_message = pcall(tests[name])
    if ok then
        passed = passed + 1
    else
        failures[#failures + 1] = name .. ": " .. tostring(error_message)
    end
end
clear_ue4ss_api()

if #failures > 0 then
    io.stderr:write(string.format(
        "Perfect Placement runtime tests failed (%d/%d passed):\n",
        passed,
        #names
    ))
    for _, failure in ipairs(failures) do
        io.stderr:write("  - " .. failure .. "\n")
    end
    os.exit(1)
end

print(string.format(
    "Perfect Placement runtime tests passed (%d tests; Lua 5.4).",
    passed
))
