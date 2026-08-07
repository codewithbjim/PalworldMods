local MOD_NAME = "KeepWorking"
local MOD_VERSION = "0.1.0"
local EXPECTED_GAME_BUILD = "24181527"
local HELPER_MODULE_NAME = "AltTabWorkContinuationFocus"
local EXPECTED_HELPER_SUFFIX = "\\keepworking\\scripts\\alttabworkcontinuationfocus.dll"
local CANDIDATE_MAX_AGE_MS = 2000
local FOCUS_POLL_INTERVAL_MS = 100
local RETURN_GATE_RETRY_INTERVAL_MS = 100
local RETURN_GATE_MAX_RETRY_ATTEMPTS = 50
local RETURN_LISTENER_CLASS =
    "/Game/Pal/Blueprint/UI/WBP_PalHUD_InGame_InputListener.WBP_PalHUD_InGame_InputListener_C"
local RETURN_GATE_FUNCTION_CANDIDATES = {
    RETURN_LISTENER_CLASS .. ":CanOpenAnyUI",
    RETURN_LISTENER_CLASS .. ":Can_Open_Any_UI",
    RETURN_LISTENER_CLASS .. ":Can Open Any UI",
}

local sequence = 0
local startedAtWall = os.time()
local installedHooks = {}
local failedHooks = {}
local candidate = nil
local armed = nil
local pendingSuppression = nil
local implementationReady = false
local candidateGeneration = 0
local returnUiGeneration = 0
local returnGateHookReady = false
local returnGateHookPath = nil
local returnGateRegistrationTerminal = false
local returnGateNotifyReady = false
local returnGateRetryReady = false
local returnGateListenerObserved = false
local returnGateHookIds = nil
local returnGateRetryAttempts = 0
local returnGateRetryScheduled = false
local mapHookReady = false
local candidateTimerReady = false
local recomputeImplementationReadiness = nil
local scheduleReturnGateInstall = nil
local NATIVE_TRUE_SENTINEL = {}

local function emit(eventName, fields)
    sequence = sequence + 1
    local parts = {
        string.format("[%s]", MOD_NAME),
        string.format("seq=%04d", sequence),
        "wall=" .. tostring(os.time()),
        "wallDelta=" .. tostring(os.time() - startedAtWall),
        "event=" .. tostring(eventName),
    }

    if fields then
        for _, field in ipairs(fields) do
            parts[#parts + 1] = tostring(field)
        end
    end

    print(table.concat(parts, " | ") .. "\n")
end

local function unwrapParam(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok then return result end
    return value
end

local function scalar(value)
    local raw = unwrapParam(value)
    if raw == nil then return nil end
    if type(raw) == "boolean" or type(raw) == "number" or type(raw) == "string" then
        return raw
    end

    local numberOk, numberValue = pcall(tonumber, raw)
    if numberOk and numberValue ~= nil then return numberValue end
    return raw
end

local function safeValue(value)
    local raw = scalar(value)
    if raw == nil then return "nil" end
    return tostring(raw)
end

local function validObject(value)
    local object = unwrapParam(value)
    if object == nil then return nil end

    local ok, valid = pcall(function() return object:IsValid() end)
    if not ok or not valid then return nil end
    return object
end

local function objectAddress(value)
    local object = validObject(value)
    if object == nil then return nil end

    local ok, address = pcall(function() return object:GetAddress() end)
    if not ok then return nil end
    return tonumber(address)
end

local function safeObjectName(value)
    local object = validObject(value)
    if object == nil then return "invalid" end

    local ok, name = pcall(function() return object:GetFullName() end)
    if ok and name ~= nil then return tostring(name) end
    return "address=" .. tostring(objectAddress(object))
end

local function interactionSnapshot(value)
    local object = validObject(value)
    if object == nil then
        return {
            address = nil,
            interacting = nil,
            toggle = nil,
            action = nil,
            text = "object=invalid",
        }
    end

    local address = objectAddress(object)
    local interactingOk, interacting = pcall(function() return object:IsInteracting() end)
    local toggleOk, toggle = pcall(function() return object:IsToggleInteracting() end)
    local actionOk, action = pcall(function() return object:GetTriggeringActionType() end)

    interacting = interactingOk and scalar(interacting) or nil
    toggle = toggleOk and scalar(toggle) or nil
    action = actionOk and tonumber(scalar(action)) or nil

    return {
        object = object,
        address = address,
        interacting = interacting,
        toggle = toggle,
        action = action,
        text = table.concat({
            "object=" .. safeObjectName(object),
            "address=" .. tostring(address),
            "interacting=" .. tostring(interacting),
            "toggle=" .. tostring(toggle),
            "action=" .. tostring(action),
        }, ","),
    }
end

local function isActiveManualInteraction(snapshot)
    return snapshot ~= nil and
        snapshot.address ~= nil and
        snapshot.interacting == true and
        snapshot.toggle == true and
        snapshot.action == 1
end

local function clearState(reason)
    local hadState = candidate ~= nil or armed ~= nil or pendingSuppression ~= nil
    candidate = nil
    armed = nil
    pendingSuppression = nil
    if hadState then
        emit("state.cleared", { "reason=" .. tostring(reason) })
    end
end

local function guardCallback(label, callback)
    return function(...)
        local ok, callbackError = xpcall(callback, debug.traceback, ...)

        if not ok then
            emit("callback.error", {
                "callback=" .. tostring(label),
                "error=" .. tostring(callbackError),
            })
        end

        return nil
    end
end

local helperPath, helperSearchError = nil, "package.searchpath unavailable"
local packageTable = type(package) == "table" and package or nil
local searcher = packageTable and packageTable.searchpath or nil
if type(searcher) == "function" then
    local searchOk, pathOrError, searchError = pcall(
        searcher,
        HELPER_MODULE_NAME,
        packageTable.cpath
    )
    if searchOk then
        helperPath = pathOrError
        helperSearchError = searchError
    else
        helperSearchError = pathOrError
    end
end

if helperPath ~= nil then
    local normalizedHelperPath = helperPath:gsub("/", "\\"):lower()
    if normalizedHelperPath:sub(-#EXPECTED_HELPER_SUFFIX) ~= EXPECTED_HELPER_SUFFIX then
        helperSearchError = "helper resolved outside the expected mod directory: " .. helperPath
        helperPath = nil
    end
end

local isForegroundNative = nil
local isRecentFocusLossNative = nil
local wasRecentFocusLossFromNoForegroundNative = nil
local isRecentFocusGainNative = nil
local didRecentFocusGainHaveAltNative = nil
local didRecentFocusGainHaveTabNative = nil
local consumeRecentFocusGainNative = nil
local isFKeyDownNative = nil
local focusPollReady = false

if helperPath ~= nil then
    local loader = packageTable and packageTable.loadlib or nil
    local function loadNativeExport(exportName)
        if type(loader) ~= "function" then
            return false, nil, "package.loadlib unavailable"
        end

        local ok, functionOrError, loadError, loadWhere = pcall(
            loader,
            helperPath,
            exportName
        )
        if not ok then
            return false, nil, tostring(functionOrError)
        end
        if type(functionOrError) ~= "function" then
            return false, nil, tostring(loadError or loadWhere or "non-function export")
        end
        return true, functionOrError, nil
    end

    local foregroundLoadOk, foregroundFunction, foregroundLoadError =
        loadNativeExport("pal_focus_is_foreground")
    local recentLoadOk, recentFunction, recentLoadError =
        loadNativeExport("pal_focus_is_recent_loss")
    local sourceLoadOk, sourceFunction, sourceLoadError =
        loadNativeExport("pal_focus_last_recent_loss_from_no_foreground")
    local gainLoadOk, gainFunction, gainLoadError =
        loadNativeExport("pal_focus_is_recent_gain")
    local gainAltLoadOk, gainAltFunction, gainAltLoadError =
        loadNativeExport("pal_focus_last_recent_gain_had_alt")
    local gainTabLoadOk, gainTabFunction, gainTabLoadError =
        loadNativeExport("pal_focus_last_recent_gain_had_tab")
    local consumeGainLoadOk, consumeGainFunction, consumeGainLoadError =
        loadNativeExport("pal_focus_consume_recent_gain")
    local fKeyLoadOk, fKeyFunction, fKeyLoadError =
        loadNativeExport("pal_focus_is_f_down")

    if foregroundLoadOk and recentLoadOk and sourceLoadOk and
        gainLoadOk and gainAltLoadOk and gainTabLoadOk and consumeGainLoadOk and
        fKeyLoadOk and
        type(foregroundFunction) == "function" and
        type(recentFunction) == "function" and
        type(sourceFunction) == "function" and
        type(gainFunction) == "function" and
        type(gainAltFunction) == "function" and
        type(gainTabFunction) == "function" and
        type(consumeGainFunction) == "function" and
        type(fKeyFunction) == "function"
    then
        isForegroundNative = foregroundFunction
        isRecentFocusLossNative = recentFunction
        wasRecentFocusLossFromNoForegroundNative = sourceFunction
        isRecentFocusGainNative = gainFunction
        didRecentFocusGainHaveAltNative = gainAltFunction
        didRecentFocusGainHaveTabNative = gainTabFunction
        consumeRecentFocusGainNative = consumeGainFunction
        isFKeyDownNative = fKeyFunction
        emit("bridge.loaded", { "path=" .. tostring(helperPath) })
    else
        emit("bridge.failed", {
            "path=" .. tostring(helperPath),
            "foregroundError=" .. tostring(foregroundLoadError),
            "recentError=" .. tostring(recentLoadError),
            "sourceError=" .. tostring(sourceLoadError),
            "gainError=" .. tostring(gainLoadError),
            "gainAltError=" .. tostring(gainAltLoadError),
            "gainTabError=" .. tostring(gainTabLoadError),
            "consumeGainError=" .. tostring(consumeGainLoadError),
            "fKeyError=" .. tostring(fKeyLoadError),
        })
    end
else
    emit("bridge.failed", { "searchError=" .. tostring(helperSearchError) })
end

local function queryNativeBoolean(nativeFunction)
    if type(nativeFunction) ~= "function" then
        return nil, "native function unavailable"
    end

    -- The helper returns this private existing argument for true, or no result for false.
    local ok, value = pcall(nativeFunction, NATIVE_TRUE_SENTINEL)
    if not ok then return nil, tostring(value) end
    if rawequal(value, NATIVE_TRUE_SENTINEL) then return true, nil end
    if value == nil then return false, nil end
    return nil, "unexpected native result: " .. tostring(value)
end

local function startFocusPoll()
    if type(isForegroundNative) ~= "function" then
        return false, "foreground function unavailable"
    end

    local ok, pollError = pcall(function()
        LoopAsync(FOCUS_POLL_INTERVAL_MS, function()
            local foreground, queryError = queryNativeBoolean(isForegroundNative)
            if foreground == nil then
                -- Stop silently; the native 500 ms continuity bound then fails neutral.
                local _ = queryError
                return true
            end
            return false
        end)
    end)

    if not ok then return false, tostring(pollError) end
    return true, nil
end

local function onStartInteractPre(context, actionType, isToggle)
    if not implementationReady then return end

    local action = tonumber(scalar(actionType))
    local toggle = scalar(isToggle)

    if action == 1 and toggle == true then
        clearState("new-action1-toggle-start")
        local snapshot = interactionSnapshot(context)
        candidateGeneration = candidateGeneration + 1
        local generation = candidateGeneration
        candidate = {
            object = snapshot.object,
            address = snapshot.address,
            generation = generation,
        }

        local scheduleOk, handleOrError = pcall(
            ExecuteInGameThreadWithDelay,
            CANDIDATE_MAX_AGE_MS,
            guardCallback("candidate-expiry", function()
                if candidate ~= nil and candidate.generation == generation then
                    clearState("candidate-expired")
                end
            end)
        )
        if not scheduleOk or type(handleOrError) ~= "number" then
            emit("candidate.rejected", {
                "reason=expiry-schedule-failed",
                "error=" .. tostring(handleOrError),
            })
            clearState("candidate-expiry-schedule-failed")
            return
        end
        candidate.expiryHandle = handleOrError

        emit("candidate.started", {
            "requestedAction=" .. tostring(action),
            "requestedToggle=" .. tostring(toggle),
            "state=" .. snapshot.text,
        })
    end
end

local function onStartInteractPost(context, actionType, isToggle)
    if candidate == nil then return end

    local snapshot = interactionSnapshot(context)
    if snapshot.address ~= candidate.address or not isActiveManualInteraction(snapshot) then
        clearState("start-post-not-active-action1-toggle")
        return
    end

    emit("candidate.active", { "state=" .. snapshot.text })
end

local function onWorkStartResult(context, requestId, result)
    local resultValue = tonumber(scalar(result))
    if candidate == nil then return end
    if not implementationReady then
        clearState("work-start-result-while-implementation-inactive")
        return
    end
    if resultValue ~= 0 then
        clearState("work-start-rejected-or-malformed")
        return
    end

    local elapsedOk, elapsedOrError = pcall(
        GetDelayedActionTimeElapsed,
        candidate.expiryHandle
    )
    local elapsedMs = elapsedOk and tonumber(elapsedOrError) or nil
    local snapshot = interactionSnapshot(candidate.object)
    if elapsedMs == nil or
        elapsedMs < 0 or
        elapsedMs >= CANDIDATE_MAX_AGE_MS or
        snapshot.address ~= candidate.address or
        not isActiveManualInteraction(snapshot)
    then
        clearState("accepted-work-without-current-candidate")
        return
    end

    local foreground, foregroundError = queryNativeBoolean(isForegroundNative)
    if foreground ~= true then
        emit("arm.rejected", {
            "reason=foreground-not-confirmed",
            "foreground=" .. tostring(foreground),
            "error=" .. tostring(foregroundError),
        })
        clearState("foreground-not-confirmed")
        return
    end

    armed = {
        object = candidate.object,
        address = candidate.address,
        returnUiPendingGeneration = nil,
    }
    candidate = nil
    emit("work.armed", {
        "result=" .. tostring(resultValue),
        "component=" .. safeObjectName(context),
        "state=" .. snapshot.text,
    })
end

local function onCanOpenAnyUI(context, canOpenUI)
    if not implementationReady or not returnGateHookReady or armed == nil then return end

    local pendingReturnGeneration = armed.returnUiPendingGeneration
    if type(pendingReturnGeneration) ~= "number" or scalar(canOpenUI) ~= true then return end

    -- This hook can be called frequently by the HUD. Keep its normal path to one
    -- native query, with no UObject inspection, diagnostic table, or log write.
    local consumedGain, consumeError = queryNativeBoolean(consumeRecentFocusGainNative)
    if consumedGain ~= true then
        if consumedGain == nil then
            emit("return-ui.consume-failed", { "error=" .. tostring(consumeError) })
            clearState("return-ui-native-query-failed")
        end
        return
    end

    local snapshot = interactionSnapshot(armed.object)
    if snapshot.address ~= armed.address or not isActiveManualInteraction(snapshot) then
        emit("return-ui.context-mismatch", {
            "armedAddress=" .. tostring(armed.address),
            "state=" .. snapshot.text,
        })
        clearState("return-ui-without-armed-active-context")
        return
    end

    if armed.returnUiPendingGeneration == pendingReturnGeneration then
        armed.returnUiPendingGeneration = nil
    end
    local setOk, setError = pcall(function() canOpenUI:set(false) end)
    if not setOk then
        emit("return-ui.block-failed", {
            "error=" .. tostring(setError),
            "tokenConsumed=true",
            "state=" .. snapshot.text,
        })
        return
    end

    emit("return-ui.blocked", {
        "originalCanOpen=true",
        "replacementCanOpen=false",
        "consumedGain=" .. tostring(consumedGain),
        "generation=" .. tostring(pendingReturnGeneration),
        "state=" .. snapshot.text,
    })
end

local function onEndInteractPre(context, actionType)
    pendingSuppression = nil

    local originalAction = tonumber(scalar(actionType))
    if not implementationReady or originalAction ~= 1 or armed == nil then return end

    local snapshot = interactionSnapshot(context)
    if snapshot.address ~= armed.address or not isActiveManualInteraction(snapshot) then
        emit("action1-end.context-mismatch", {
            "armedAddress=" .. tostring(armed.address),
            "state=" .. snapshot.text,
        })
        clearState("action1-end-without-armed-active-context")
        return
    end

    local recentFocusLoss, bridgeError = queryNativeBoolean(isRecentFocusLossNative)
    local recentInitial = recentFocusLoss
    local foreground = nil
    local foregroundError = nil
    local recentRetry = nil
    local recentRetryError = nil
    local focusDetection = recentFocusLoss == true and "initial" or "none"

    if recentFocusLoss ~= true then
        foreground, foregroundError = queryNativeBoolean(isForegroundNative)

        -- The OS foreground transition can land between the initial recent-loss
        -- sample and this foreground sample. If this call observes background,
        -- immediately consume the edge it may just have recorded.
        if recentInitial == false and foreground == false then
            recentRetry, recentRetryError = queryNativeBoolean(isRecentFocusLossNative)
            if recentRetry == true then
                recentFocusLoss = true
                focusDetection = "foreground-confirmed-retry"
            end
        end
    end

    local fKeyDown, fKeyError = queryNativeBoolean(isFKeyDownNative)
    local preserveFocusedNonFEnd =
        foreground == true and fKeyDown == false

    if recentFocusLoss ~= true and not preserveFocusedNonFEnd then
        emit("action1-end.passed", {
            "recentInitial=" .. tostring(recentInitial),
            "foreground=" .. tostring(foreground),
            "recentRetry=" .. tostring(recentRetry),
            "fKeyDown=" .. tostring(fKeyDown),
            "bridgeError=" .. tostring(
                bridgeError or foregroundError or recentRetryError or fKeyError
            ),
            "state=" .. snapshot.text,
        })
        return
    end

    local noForegroundSource = nil
    local sourceError = nil
    if recentFocusLoss == true then
        noForegroundSource, sourceError =
            queryNativeBoolean(wasRecentFocusLossFromNoForegroundNative)
        if noForegroundSource == nil then
            emit("action1-end.passed", {
                "reason=provenance-query-error",
                "sourceError=" .. tostring(sourceError),
                "state=" .. snapshot.text,
            })
            return
        end
    end

    local focusSource = "unavailable"
    if preserveFocusedNonFEnd then
        focusSource = "focused-non-f-end"
    elseif noForegroundSource == true then
        focusSource = "no-foreground-window"
    elseif noForegroundSource == false then
        focusSource = "foreground-window-process"
    end

    local setOk, setError = pcall(function() actionType:set(0) end)
    if not setOk then
        emit("focus-release.rewrite-failed", {
            "error=" .. tostring(setError),
            "state=" .. snapshot.text,
        })
        return
    end

    pendingSuppression = {
        address = snapshot.address,
        originalAction = originalAction,
        focusRelease = recentFocusLoss == true,
    }
    emit("focus-release.rewritten", {
        "originalAction=" .. tostring(originalAction),
        "replacementAction=0",
        "focusDetection=" .. focusDetection,
        "recentInitial=" .. tostring(recentInitial),
        "foreground=" .. tostring(foreground),
        "recentRetry=" .. tostring(recentRetry),
        "focusSource=" .. focusSource,
        "fKeyDown=" .. tostring(fKeyDown),
        "sourceError=" .. tostring(sourceError),
        "state=" .. snapshot.text,
    })
end

local function onEndInteractPost(context, actionType)
    local snapshot = interactionSnapshot(context)

    if pendingSuppression ~= nil and snapshot.address == pendingSuppression.address then
        local suppression = pendingSuppression
        local rewriteHeld = isActiveManualInteraction(snapshot)
        emit(rewriteHeld and "focus-release.preserved" or "focus-release.not-preserved", {
            "observedAction=" .. safeValue(actionType),
            "state=" .. snapshot.text,
        })
        pendingSuppression = nil

        if not rewriteHeld then
            clearState("action-rewrite-did-not-preserve-interaction")
        elseif suppression.focusRelease and
            armed ~= nil and snapshot.address == armed.address
        then
            returnUiGeneration = returnUiGeneration + 1
            armed.returnUiPendingGeneration = returnUiGeneration
            emit("return-ui.armed", {
                "reason=verified-preserved-focus-release",
                "generation=" .. tostring(returnUiGeneration),
                "state=" .. snapshot.text,
            })
        end
        return
    end

    if armed ~= nil and snapshot.address == armed.address and tonumber(scalar(actionType)) == 1 then
        clearState("action1-end-completed")
    end
end

local function onTerminateInteractPre(context)
    if armed == nil and candidate == nil then return end
    local address = objectAddress(context)
    if (armed ~= nil and address == armed.address) or
        (candidate ~= nil and address == candidate.address)
    then
        clearState("terminate-interact")
    end
end

local function onWorkEndRequest(context, workId)
    if armed ~= nil or candidate ~= nil then
        clearState("explicit-work-end-request")
    end
end

local hookSpecs = {
    {
        path = "/Script/Pal.PalInteractComponent:StartTriggerInteract",
        pre = onStartInteractPre,
        post = onStartInteractPost,
    },
    {
        path = "/Script/Pal.PalInteractComponent:EndTriggerInteract",
        pre = onEndInteractPre,
        post = onEndInteractPost,
    },
    {
        path = "/Script/Pal.PalInteractComponent:TerminateInteract",
        pre = onTerminateInteractPre,
    },
    {
        path = "/Script/Pal.PalNetworkWorkProgressComponent:ReceiveStartPlayerWork_ToRequestClient",
        pre = onWorkStartResult,
    },
    {
        path = "/Script/Pal.PalNetworkWorkProgressComponent:RequestEndPlayerWork_ToServer",
        pre = onWorkEndRequest,
    },
}

local function installHook(spec)
    local guardedPre = guardCallback(spec.path .. ":pre", spec.pre)
    local guardedPost = spec.post and guardCallback(spec.path .. ":post", spec.post) or nil
    local ok, preId, postId

    if guardedPost ~= nil then
        ok, preId, postId = pcall(RegisterHook, spec.path, guardedPre, guardedPost)
    else
        ok, preId, postId = pcall(RegisterHook, spec.path, guardedPre)
    end

    if ok and type(preId) == "number" and type(postId) == "number" then
        installedHooks[spec.path] = {
            pre = preId,
            post = postId,
            preCallback = guardedPre,
            postCallback = guardedPost,
        }
        emit("hook.installed", {
            "path=" .. spec.path,
            "preId=" .. tostring(preId),
            "postId=" .. tostring(postId),
        })
        return
    end

    failedHooks[spec.path] = tostring(preId)
    emit("hook.failed", {
        "path=" .. spec.path,
        "error=" .. tostring(preId),
    })
end

local returnGateHookCallback = guardCallback(
    "return-ui-gate:after",
    onCanOpenAnyUI
)

local function installReturnGateHook(reason)
    if returnGateHookReady then return true end
    if returnGateRegistrationTerminal then
        return false, "return hook registration previously failed after UFunction preflight"
    end

    local lastError = "no candidate UFunction is loaded"
    for _, path in ipairs(RETURN_GATE_FUNCTION_CANDIDATES) do
        local findOk, functionObjectOrError = pcall(StaticFindObject, path)
        if not findOk then
            lastError = "StaticFindObject failed for " .. path .. ": " ..
                tostring(functionObjectOrError)
        elseif validObject(functionObjectOrError) ~= nil then
            local ok, preId, postId = pcall(RegisterHook, path, returnGateHookCallback)
            if ok and type(preId) == "number" and type(postId) == "number" then
                returnGateHookReady = true
                returnGateHookPath = path
                returnGateHookIds = {
                    pre = preId,
                    post = postId,
                    callback = returnGateHookCallback,
                }
                emit("return-hook.installed", {
                    "reason=" .. tostring(reason),
                    "path=" .. path,
                    "preId=" .. tostring(preId),
                    "postId=" .. tostring(postId),
                    "semantics=blueprint-after-out-param",
                })
                if recomputeImplementationReadiness ~= nil then
                    recomputeImplementationReadiness("return-hook-installed")
                end
                return true
            end

            returnGateRegistrationTerminal = true
            if ok then
                lastError = string.format(
                    "invalid IDs for %s: pre=%s post=%s",
                    path,
                    tostring(preId),
                    tostring(postId)
                )
            else
                lastError = tostring(preId)
            end

            emit("return-hook.registration-failed", {
                "reason=" .. tostring(reason),
                "path=" .. path,
                "error=" .. tostring(lastError),
                "retryable=false",
            })
            return false, lastError
        end
    end

    return false, lastError
end

scheduleReturnGateInstall = function(reason)
    if returnGateHookReady or returnGateRetryScheduled then return true end
    if returnGateRegistrationTerminal then
        return false, "return hook registration is terminal"
    end
    if type(ExecuteInGameThreadWithDelay) ~= "function" then
        return false, "ExecuteInGameThreadWithDelay unavailable"
    end
    if returnGateRetryAttempts >= RETURN_GATE_MAX_RETRY_ATTEMPTS then
        return false, "retry limit reached"
    end

    local scheduleOk, handleOrError = pcall(
        ExecuteInGameThreadWithDelay,
        RETURN_GATE_RETRY_INTERVAL_MS,
        guardCallback("return-hook:game-thread-retry", function()
            returnGateRetryScheduled = false
            if returnGateHookReady then return end

            returnGateRetryAttempts = returnGateRetryAttempts + 1
            local installOk, installError = installReturnGateHook(
                tostring(reason) .. "-attempt-" .. tostring(returnGateRetryAttempts)
            )
            if installOk then return end

            emit("return-hook.retry-attempt-failed", {
                "attempt=" .. tostring(returnGateRetryAttempts),
                "maxAttempts=" .. tostring(RETURN_GATE_MAX_RETRY_ATTEMPTS),
                "error=" .. tostring(installError),
            })

            local retryOk, retryError = scheduleReturnGateInstall(reason)
            if not retryOk then
                emit("return-hook.retry-stopped", {
                    "attempts=" .. tostring(returnGateRetryAttempts),
                    "error=" .. tostring(retryError),
                })
            end
        end)
    )

    if not scheduleOk or type(handleOrError) ~= "number" then
        return false, tostring(handleOrError)
    end

    returnGateRetryScheduled = true
    return true, nil
end

local function countEntries(entries)
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    return count
end

recomputeImplementationReadiness = function(reason)
    local wasReady = implementationReady
    implementationReady =
        mapHookReady and
        candidateTimerReady and
        focusPollReady and
        returnGateHookReady and
        isForegroundNative ~= nil and
        isRecentFocusLossNative ~= nil and
        wasRecentFocusLossFromNoForegroundNative ~= nil and
        isRecentFocusGainNative ~= nil and
        didRecentFocusGainHaveAltNative ~= nil and
        didRecentFocusGainHaveTabNative ~= nil and
        consumeRecentFocusGainNative ~= nil and
        isFKeyDownNative ~= nil and
        countEntries(installedHooks) == #hookSpecs and
        countEntries(failedHooks) == 0

    if implementationReady ~= wasReady then
        emit(implementationReady and "implementation.ready" or "implementation.inactive", {
            "reason=" .. tostring(reason),
            "returnHookReady=" .. tostring(returnGateHookReady),
            "returnHookPath=" .. tostring(returnGateHookPath),
            "installed=" .. tostring(countEntries(installedHooks)),
            "failed=" .. tostring(countEntries(failedHooks)),
        })
    end

    if wasReady and not implementationReady then
        clearState("implementation-became-inactive")
    end
end

emit("startup", {
    "version=" .. MOD_VERSION,
    "expectedGameBuild=" .. EXPECTED_GAME_BUILD,
    "mode=guarded-action-rewrite",
})

local immediateReturnHookOk, immediateReturnHookError =
    installReturnGateHook("startup")
if not immediateReturnHookOk then
    emit("return-hook.waiting", {
        "class=" .. RETURN_LISTENER_CLASS,
        "error=" .. tostring(immediateReturnHookError),
    })
end

local returnNotifyOk, returnNotifyError = pcall(
    NotifyOnNewObject,
    RETURN_LISTENER_CLASS,
    function(listener)
        returnGateListenerObserved = true
        emit("return-listener.constructed", {
            "listener=" .. safeObjectName(listener),
        })

        local retryOk, retryError = scheduleReturnGateInstall("listener-observed")
        if retryOk then
            emit("return-hook.retry-scheduled", {
                "intervalMs=" .. tostring(RETURN_GATE_RETRY_INTERVAL_MS),
                "maxAttempts=" .. tostring(RETURN_GATE_MAX_RETRY_ATTEMPTS),
            })
        else
            emit("return-hook.retry-schedule-failed", {
                "error=" .. tostring(retryError),
            })
        end
        return returnGateHookReady
    end
)
returnGateNotifyReady = returnNotifyOk
if returnNotifyOk then
    emit("return-listener.notification-installed")
else
    emit("return-listener.notification-failed", {
        "error=" .. tostring(returnNotifyError),
    })
end

returnGateRetryReady = type(ExecuteInGameThreadWithDelay) == "function"
if returnGateRetryReady then
    emit("return-hook.retry-ready", {
        "intervalMs=" .. tostring(RETURN_GATE_RETRY_INTERVAL_MS),
        "maxAttempts=" .. tostring(RETURN_GATE_MAX_RETRY_ATTEMPTS),
        "thread=game",
    })
else
    emit("return-hook.retry-failed", {
        "error=ExecuteInGameThreadWithDelay unavailable",
    })
end

local foregroundAtStartup, startupBridgeError = queryNativeBoolean(isForegroundNative)
emit("bridge.sample", {
    "foreground=" .. tostring(foregroundAtStartup),
    "error=" .. tostring(startupBridgeError),
})

candidateTimerReady =
    type(ExecuteInGameThreadWithDelay) == "function" and
    type(GetDelayedActionTimeElapsed) == "function"

local guardedMapPost = guardCallback("load-map:post", function(
    engine, world, url, pendingGame, errorMessage
)
    clearState("map-load")
    emit("map.post", {
        "world=" .. safeObjectName(world),
    })
end)

local mapHookOk, mapHookError = pcall(RegisterLoadMapPostHook, guardedMapPost)
if mapHookOk then
    mapHookReady = true
    emit("map-hook.installed")
else
    emit("map-hook.failed", { "error=" .. tostring(mapHookError) })
end

if mapHookReady and
    candidateTimerReady and
    isForegroundNative ~= nil and
    isRecentFocusLossNative ~= nil and
    wasRecentFocusLossFromNoForegroundNative ~= nil and
    isRecentFocusGainNative ~= nil and
    didRecentFocusGainHaveAltNative ~= nil and
    didRecentFocusGainHaveTabNative ~= nil and
    consumeRecentFocusGainNative ~= nil and
    isFKeyDownNative ~= nil
then
    local focusPollError
    focusPollReady, focusPollError = startFocusPoll()
    if focusPollReady then
        emit("focus-poll.started", {
            "intervalMs=" .. tostring(FOCUS_POLL_INTERVAL_MS),
        })
        for _, spec in ipairs(hookSpecs) do installHook(spec) end
        recomputeImplementationReadiness("startup-hooks")
        if not implementationReady then
            clearState("incomplete-hook-set")
            emit("inactive", {
                "reason=incomplete-hook-set-or-return-gate-waiting",
                "returnHookReady=" .. tostring(returnGateHookReady),
                "returnHookPath=" .. tostring(returnGateHookPath),
            })
        end
    else
        emit("inactive", {
            "reason=focus-poll-unavailable",
            "error=" .. tostring(focusPollError),
        })
    end
else
    local inactiveReason = "native-foreground-bridge-unavailable"
    if not mapHookReady then
        inactiveReason = "map-hook-unavailable"
    elseif not candidateTimerReady then
        inactiveReason = "candidate-timer-unavailable"
    end
    emit("inactive", { "reason=" .. inactiveReason })
end

emit("ready", {
    "bridgeReady=" .. tostring(
        isForegroundNative ~= nil and
        isRecentFocusLossNative ~= nil and
        wasRecentFocusLossFromNoForegroundNative ~= nil and
        isRecentFocusGainNative ~= nil and
        didRecentFocusGainHaveAltNative ~= nil and
        didRecentFocusGainHaveTabNative ~= nil and
        consumeRecentFocusGainNative ~= nil and
        isFKeyDownNative ~= nil
    ),
    "focusPollReady=" .. tostring(focusPollReady),
    "mapHookReady=" .. tostring(mapHookReady),
    "candidateTimerReady=" .. tostring(candidateTimerReady),
    "returnHookReady=" .. tostring(returnGateHookReady),
    "returnHookPath=" .. tostring(returnGateHookPath),
    "returnNotifyReady=" .. tostring(returnGateNotifyReady),
    "returnRetryReady=" .. tostring(returnGateRetryReady),
    "implementationReady=" .. tostring(implementationReady),
    "installed=" .. tostring(countEntries(installedHooks)),
    "failed=" .. tostring(countEntries(failedHooks)),
    "hotReloadSupported=false",
})
