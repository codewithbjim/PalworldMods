local M = {}

function M.new(log, retained_history)
    local retained_callbacks = {}
    local retained_callback_order = {}
    local completed_callbacks = {}
    local retained_callback_serial = 0
    local history_limit = math.max(
        1,
        math.floor(tonumber(retained_history) or 256)
    )

    local function report(message)
        if type(log) == "function" then
            log(message)
        end
    end

    local function discard(callback_id)
        retained_callbacks[callback_id] = nil
        completed_callbacks[callback_id] = nil
        for index = #retained_callback_order, 1, -1 do
            if retained_callback_order[index] == callback_id then
                table.remove(retained_callback_order, index)
                return
            end
        end
    end

    local function prune(active_callback_id)
        if #retained_callback_order <= history_limit then
            return
        end

        local index = 1
        while #retained_callback_order > history_limit
            and index <= #retained_callback_order
        do
            local callback_id = retained_callback_order[index]
            if callback_id ~= active_callback_id
                and completed_callbacks[callback_id]
            then
                retained_callbacks[callback_id] = nil
                completed_callbacks[callback_id] = nil
                table.remove(retained_callback_order, index)
            else
                index = index + 1
            end
        end
    end

    local function retain(callback, label)
        retained_callback_serial = retained_callback_serial + 1
        local callback_id = retained_callback_serial
        local retained_callback
        retained_callback = function(...)
            local ok, error_message = pcall(callback, ...)
            -- Keep a bounded history. Releasing the final Lua reference from
            -- inside an EngineTick invocation can make UE4SS revisit an
            -- invalid registry entry while retiring the one-shot callback.
            completed_callbacks[callback_id] = true
            prune(callback_id)
            if not ok then
                report(string.format(
                    "%s failed: %s",
                    label or "Asynchronous callback",
                    tostring(error_message)
                ))
            end
        end
        retained_callbacks[callback_id] = retained_callback
        retained_callback_order[#retained_callback_order + 1] = callback_id
        return retained_callback, callback_id
    end

    local execute
    execute = function(callback, label)
        local retained_callback, callback_id = retain(callback, label)
        local ok, error_message = pcall(function()
            -- Never force the shared ProcessEvent dispatcher. EngineTick keeps
            -- this mod's callbacks isolated from invalid global hook entries.
            if EngineTickAvailable == true
                and EGameThreadMethod ~= nil
                and EGameThreadMethod.EngineTick ~= nil
            then
                ExecuteInGameThread(
                    retained_callback,
                    EGameThreadMethod.EngineTick
                )
            else
                ExecuteInGameThread(retained_callback)
            end
        end)
        if not ok then
            discard(callback_id)
            report(string.format(
                "Could not queue %s: %s",
                label or "game-thread callback",
                tostring(error_message)
            ))
            return false
        end
        return true
    end

    local function delay(delay_ms, callback, label, enqueue_failure_callback)
        if type(ExecuteInGameThreadWithDelay) == "function" then
            local retained_callback, callback_id = retain(callback, label)
            local ok, handle_or_error = pcall(
                ExecuteInGameThreadWithDelay,
                delay_ms,
                retained_callback
            )
            if ok and handle_or_error ~= nil then
                return true
            end
            discard(callback_id)
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

        local delayed_callback, callback_id = retain(function()
            local enqueued = execute(callback, label)
            if not enqueued and enqueue_failure_callback ~= nil then
                local failure_ok, failure_error =
                    pcall(enqueue_failure_callback)
                if not failure_ok then
                    report(string.format(
                        "%s enqueue-failure recovery failed: %s",
                        label or "Delayed game-thread callback",
                        tostring(failure_error)
                    ))
                end
            end
        end, label)
        local ok, error_message = pcall(
            ExecuteWithDelay,
            delay_ms,
            delayed_callback
        )
        if not ok then
            discard(callback_id)
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
        execute = execute,
        delay = delay,
    }
end

return M
