local M = {}

function M.new(log, options)
    options = options or {}

    local fallback_queue = {}
    local fallback_head = 1
    local fallback_tail = 0
    local fallback_pending = false
    local fallback_saturated = false
    local fallback_queue_limit = math.max(
        1,
        math.floor(tonumber(options.queue_limit) or 256)
    )
    local owned_callbacks = {}
    local fallback_drain

    local function report(message)
        if type(log) == "function" then
            log(message)
        end
    end

    local function invoke(callback, label)
        local ok, error_message = pcall(callback)
        if not ok then
            report(string.format(
                "%s failed: %s",
                label or "Asynchronous callback",
                tostring(error_message)
            ))
        end
        return ok
    end

    local function queue_size()
        if fallback_tail < fallback_head then
            return 0
        end
        return fallback_tail - fallback_head + 1
    end

    local function reset_empty_queue()
        if fallback_head > fallback_tail then
            fallback_queue = {}
            fallback_head = 1
            fallback_tail = 0
            fallback_saturated = false
        end
    end

    local function schedule_fallback_drain()
        if fallback_pending then
            return true
        end
        if type(ExecuteInGameThread) ~= "function" then
            report("Could not queue game-thread work: "
                .. "ExecuteInGameThread is unavailable.")
            return false
        end

        fallback_pending = true
        local ok, error_message = pcall(function()
            if EngineTickAvailable == true
                and EGameThreadMethod ~= nil
                and EGameThreadMethod.EngineTick ~= nil
            then
                ExecuteInGameThread(
                    fallback_drain,
                    EGameThreadMethod.EngineTick
                )
            else
                ExecuteInGameThread(fallback_drain)
            end
        end)
        if not ok then
            fallback_pending = false
            report("Could not queue the stable game-thread drain: "
                .. tostring(error_message))
            return false
        end
        return true
    end

    fallback_drain = function()
        local processed = 0
        while fallback_head <= fallback_tail
            and processed < fallback_queue_limit
        do
            local job = fallback_queue[fallback_head]
            fallback_queue[fallback_head] = nil
            fallback_head = fallback_head + 1
            processed = processed + 1
            if job ~= nil then
                invoke(job.callback, job.label)
            end
        end

        if fallback_head <= fallback_tail then
            report("The stable game-thread drain reached its safety limit; "
                .. "remaining fallback work was discarded.")
            fallback_queue = {}
            fallback_head = 1
            fallback_tail = 0
        end
        reset_empty_queue()
        fallback_pending = false
    end

    local function execute(callback, label)
        if type(callback) ~= "function" then
            report("Could not queue game-thread work: callback is not a function.")
            return false
        end
        if queue_size() >= fallback_queue_limit then
            if not fallback_saturated then
                fallback_saturated = true
                report("Game-thread input burst reached the safety limit; "
                    .. "additional repeated input was coalesced.")
            end
            return false
        end

        fallback_tail = fallback_tail + 1
        fallback_queue[fallback_tail] = {
            callback = callback,
            label = label,
        }
        if fallback_pending or schedule_fallback_drain() then
            return true
        end

        fallback_queue[fallback_tail] = nil
        fallback_tail = fallback_tail - 1
        reset_empty_queue()
        return false
    end

    local function cancel_record(record)
        if record == nil or not record.active then
            return true
        end
        if type(CancelDelayedAction) ~= "function" then
            return false
        end
        local ok, canceled = pcall(CancelDelayedAction, record.handle)
        if not ok or canceled ~= true then
            return false
        end
        record.active = false
        owned_callbacks[record] = nil
        return true
    end

    local function retire_record(record)
        record.active = false
        owned_callbacks[record] = nil
    end

    local function create_pulse(callback, label, delay_ms)
        if type(callback) ~= "function" then
            report("Could not create a game-thread pulse: "
                .. "callback is not a function.")
            return nil
        end
        if type(PauseDelayedAction) ~= "function"
            or type(UnpauseDelayedAction) ~= "function"
            or type(CancelDelayedAction) ~= "function"
        then
            return function()
                return execute(callback, label)
            end
        end

        local record = {
            active = true,
            callback = nil,
            handle = nil,
            pending = false,
            stop_requested = false,
        }
        record.callback = function()
            if not record.active then
                return
            end
            if record.stop_requested then
                cancel_record(record)
                return
            end

            record.pending = false
            invoke(callback, label)
            if record.pending then
                return
            end

            local pause_ok, paused =
                pcall(PauseDelayedAction, record.handle)
            if not pause_ok or paused ~= true then
                record.stop_requested = true
                local canceled = cancel_record(record)
                report((label or "Input pulse")
                    .. " could not self-pause; cancel result: "
                    .. tostring(canceled) .. ".")
                return
            end
        end

        local create_ok, handle_or_error
        if delay_ms ~= nil
            and type(LoopInGameThreadWithDelay) == "function"
        then
            create_ok, handle_or_error = pcall(
                LoopInGameThreadWithDelay,
                math.max(1, math.floor(tonumber(delay_ms) or 1)),
                record.callback
            )
        elseif type(LoopInGameThreadAfterFrames) == "function"
            and EngineTickAvailable == true
        then
            create_ok, handle_or_error = pcall(
                LoopInGameThreadAfterFrames,
                1,
                record.callback
            )
        elseif type(LoopInGameThreadWithDelay) == "function" then
            create_ok, handle_or_error = pcall(
                LoopInGameThreadWithDelay,
                1,
                record.callback
            )
        else
            record.active = false
            return function()
                return execute(callback, label)
            end
        end

        if not create_ok or handle_or_error == nil then
            record.active = false
            report(string.format(
                "Could not create %s: %s",
                label or "input pulse",
                tostring(handle_or_error)
            ))
            return function()
                return execute(callback, label)
            end
        end

        record.handle = handle_or_error
        owned_callbacks[record] = true
        local pause_ok, paused = pcall(PauseDelayedAction, record.handle)
        if not pause_ok or paused ~= true then
            record.stop_requested = true
            cancel_record(record)
            report((label or "Input pulse")
                .. " could not start paused; using the stable fallback queue.")
            return function()
                return execute(callback, label)
            end
        end

        return function()
            if not record.active or record.stop_requested then
                return execute(callback, label)
            end

            record.pending = true
            local wake_ok, woke =
                pcall(UnpauseDelayedAction, record.handle)
            if wake_ok and woke == true then
                return true
            end

            -- Repeated input while the stable callback is already active or
            -- executing is intentionally coalesced to one action per frame.
            if type(IsValidDelayedActionHandle) == "function" then
                local valid_ok, valid =
                    pcall(IsValidDelayedActionHandle, record.handle)
                if valid_ok and valid == true then
                    return true
                elseif valid_ok and valid == false then
                    retire_record(record)
                    return execute(callback, label)
                end
            end

            record.stop_requested = true
            cancel_record(record)
            report((label or "Input pulse")
                .. " lost its owned action; using the stable fallback queue.")
            return execute(callback, label)
        end
    end

    local function pulse(callback, label)
        return create_pulse(callback, label, nil)
    end

    local function throttle(delay_ms, callback, label)
        return create_pulse(callback, label, delay_ms)
    end

    local function loop(delay_ms, callback, label)
        if type(callback) ~= "function" then
            report("Could not create a game-thread loop: "
                .. "callback is not a function.")
            return nil
        end
        if type(LoopInGameThreadWithDelay) ~= "function"
            or type(CancelDelayedAction) ~= "function"
        then
            report("Could not create " .. (label or "game-thread loop")
                .. ": the owned loop API is unavailable.")
            return nil
        end

        local record = {
            active = true,
            callback = nil,
            handle = nil,
            stop_requested = false,
        }
        record.callback = function()
            if not record.active then
                return
            end
            if record.stop_requested then
                cancel_record(record)
                return
            end
            local ok, should_stop_or_error = pcall(callback)
            if not ok then
                report(string.format(
                    "%s failed: %s",
                    label or "Game-thread loop",
                    tostring(should_stop_or_error)
                ))
                should_stop_or_error = true
            end
            if should_stop_or_error == true then
                record.stop_requested = true
                if not cancel_record(record) then
                    report((label or "Game-thread loop")
                        .. " could not cancel its owned action; "
                        .. "cancellation will be retried.")
                end
            end
        end

        local create_ok, handle_or_error = pcall(
            LoopInGameThreadWithDelay,
            math.max(1, math.floor(tonumber(delay_ms) or 1)),
            record.callback
        )
        if not create_ok or handle_or_error == nil then
            record.active = false
            report(string.format(
                "Could not create %s: %s",
                label or "game-thread loop",
                tostring(handle_or_error)
            ))
            return nil
        end

        record.handle = handle_or_error
        owned_callbacks[record] = true
        return function()
            record.stop_requested = true
            return cancel_record(record)
        end
    end

    local function delay(delay_ms, callback, label, enqueue_failure_callback)
        if type(callback) ~= "function" then
            report("Could not queue delayed work: callback is not a function.")
            return false
        end

        if type(ExecuteInGameThreadWithDelay) == "function" then
            local owned_callback = function()
                invoke(callback, label)
            end
            local ok, handle_or_error = pcall(
                ExecuteInGameThreadWithDelay,
                delay_ms,
                owned_callback
            )
            if ok and handle_or_error ~= nil then
                return true
            end
            report(string.format(
                "Could not queue %s: %s",
                label or "delayed game-thread callback",
                tostring(handle_or_error)
            ))
            return false
        end

        if type(ExecuteWithDelay) ~= "function" then
            report(string.format(
                "Could not queue %s: no delayed-action API is available.",
                label or "delayed game-thread callback"
            ))
            return false
        end

        local delayed_callback = function()
            local enqueued = execute(callback, label)
            if not enqueued and enqueue_failure_callback ~= nil then
                invoke(
                    enqueue_failure_callback,
                    (label or "Delayed game-thread callback")
                        .. " enqueue-failure recovery"
                )
            end
        end
        local ok, error_message = pcall(
            ExecuteWithDelay,
            delay_ms,
            delayed_callback
        )
        if not ok then
            report(string.format(
                "Could not queue %s: %s",
                label or "delayed game-thread callback",
                tostring(error_message)
            ))
            return false
        end
        return true
    end

    return {
        delay = delay,
        execute = execute,
        loop = loop,
        pulse = pulse,
        throttle = throttle,
    }
end

return M
