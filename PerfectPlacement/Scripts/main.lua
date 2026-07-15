local Config = require("config")

local MOD = "PerfectPlacement"

-- Windows virtual-key values are used deliberately. They are stable across
-- UE4SS versions even when a build exposes different symbolic Key names.
local VK = {
    PAGE_UP = 0x21,
    PAGE_DOWN = 0x22,
    LEFT = 0x25,
    UP = 0x26,
    RIGHT = 0x27,
    DOWN = 0x28,
    OPEN_BRACKET = 0xDB,
    CLOSE_BRACKET = 0xDD,
    Q = 0x51,
    E = 0x45,
    F6 = 0x75,
    F7 = 0x76,
    F8 = 0x77,
}

local State = {
    SEARCHING = "searching",
    READY = "ready",
    EDITING = "editing",
}

local state = State.SEARCHING
local preview_actor = nil
local desired_location = nil
local desired_rotation = nil
local current_move_step = Config.movement.normal
local transform_loop_started = false

local function log(message)
    print(string.format("[%s] %s\n", MOD, message))
end

local function verbose(message)
    if Config.diagnostics.verbose then
        log(message)
    end
end

local function is_valid(object)
    if object == nil then
        return false
    end

    local ok, result = pcall(function()
        return object:IsValid()
    end)
    return ok and result == true
end

local function full_name(object)
    if not is_valid(object) then
        return "<invalid>"
    end

    local ok, value = pcall(function()
        return object:GetFullName()
    end)
    if ok then
        return tostring(value)
    end
    return "<name unavailable>"
end

local function contains_any(value, fragments)
    for _, fragment in ipairs(fragments) do
        if string.find(value, fragment, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function candidate_score(object)
    local name = full_name(object)
    if contains_any(name, Config.diagnostics.rejected_name_fragments) then
        return -1000
    end

    local score = 0
    for index, fragment in ipairs(Config.diagnostics.preferred_name_fragments) do
        if string.find(name, fragment, 1, true) ~= nil then
            score = score + (#Config.diagnostics.preferred_name_fragments - index + 1)
        end
    end


    for _, property_name in ipairs(Config.diagnostics.simulation_state_properties) do
        local ok, value = pcall(function()
            return object[property_name]
        end)
        if ok and value ~= nil then
            local rendered = tostring(value)
            verbose(string.format(
                "Candidate property %s=%s name=%s",
                property_name,
                rendered,
                name
            ))
            if value == 1 or string.find(rendered, "Simulation", 1, true) ~= nil then
                score = score + 100
            end
        end
    end
    return score
end

local function safe_find_all_of(class_name)
    local ok, objects = pcall(function()
        return FindAllOf(class_name)
    end)
    if not ok or objects == nil then
        return {}
    end
    return objects
end

local function discover_preview()
    local best_actor = nil
    local best_score = -1000
    local candidates_seen = 0

    for _, class_name in ipairs(Config.diagnostics.preview_class_names) do
        local objects = safe_find_all_of(class_name)
        for _, object in ipairs(objects) do
            if is_valid(object) then
                candidates_seen = candidates_seen + 1
                local score = candidate_score(object)
                verbose(string.format(
                    "Candidate class=%s score=%d name=%s",
                    class_name,
                    score,
                    full_name(object)
                ))
                if score > best_score then
                    best_score = score
                    best_actor = object
                end
            end
        end
    end

    if not is_valid(best_actor) then
        state = State.SEARCHING
        log(string.format(
            "No preview candidate found (%d objects checked). Open build mode, display a preview, then press Ctrl+F6.",
            candidates_seen
        ))
        return false
    end

    preview_actor = best_actor
    state = State.READY
    log("Selected preview candidate: " .. full_name(preview_actor))
    return true
end

local function read_preview_transform()
    if not is_valid(preview_actor) then
        return false
    end

    local ok, location, rotation = pcall(function()
        return preview_actor:K2_GetActorLocation(), preview_actor:K2_GetActorRotation()
    end)
    if not ok or location == nil or rotation == nil then
        log("The selected object does not expose the expected Actor transform methods.")
        return false
    end

    desired_location = {
        X = location.X,
        Y = location.Y,
        Z = location.Z,
    }
    desired_rotation = {
        Pitch = rotation.Pitch,
        Yaw = rotation.Yaw,
        Roll = rotation.Roll,
    }
    return true
end

local function apply_preview_transform()
    if state ~= State.EDITING or not is_valid(preview_actor) then
        return false
    end
    if desired_location == nil or desired_rotation == nil then
        return false
    end

    local ok, error_message = pcall(function()
        preview_actor:K2_SetActorLocationAndRotation(
            desired_location,
            desired_rotation,
            false,
            {},
            true
        )
    end)
    if not ok then
        log("Failed to apply preview transform: " .. tostring(error_message))
        return false
    end
    return true
end

local function start_transform_loop()
    if transform_loop_started or not Config.hold_locked_transform then
        return
    end
    transform_loop_started = true

    LoopAsync(Config.transform_refresh_ms, function()
        if state == State.EDITING then
            ExecuteInGameThread(function()
                apply_preview_transform()
            end)
        end
    end)
end

local function begin_editing()
    if not is_valid(preview_actor) and not discover_preview() then
        return
    end
    if not read_preview_transform() then
        return
    end

    state = State.EDITING
    start_transform_loop()
    log(string.format(
        "Preview locked. Move step %.1f cm; rotation step %.1f degrees.",
        current_move_step,
        Config.rotation.normal
    ))
end

local function release_preview()
    if state ~= State.EDITING then
        return
    end
    state = State.READY
    desired_location = nil
    desired_rotation = nil
    log("Preview released to Palworld placement control.")
end

local function get_camera_yaw()
    if not Config.camera_relative_movement then
        return 0.0
    end

    local ok, yaw = pcall(function()
        local controller = UEHelpers:GetPlayerController()
        if controller == nil or not controller:IsValid() then
            return 0.0
        end

        local camera = controller.PlayerCameraManager
        if camera ~= nil and camera:IsValid() then
            return camera:K2_GetActorRotation().Yaw
        end
        return controller:GetControlRotation().Yaw
    end)
    if ok and yaw ~= nil then
        return yaw
    end
    return 0.0
end

local function move_preview(forward_amount, right_amount, up_amount, distance_override)
    if state ~= State.EDITING or desired_location == nil then
        return
    end

    local distance = distance_override or current_move_step
    local yaw_radians = math.rad(get_camera_yaw())
    local forward_x = math.cos(yaw_radians)
    local forward_y = math.sin(yaw_radians)
    local right_x = -forward_y
    local right_y = forward_x

    desired_location.X = desired_location.X
        + (forward_x * forward_amount * distance)
        + (right_x * right_amount * distance)
    desired_location.Y = desired_location.Y
        + (forward_y * forward_amount * distance)
        + (right_y * right_amount * distance)
    desired_location.Z = desired_location.Z + (up_amount * distance)

    ExecuteInGameThread(function()
        apply_preview_transform()
    end)
end

local function rotate_preview(yaw_amount, degrees_override)
    if state ~= State.EDITING or desired_rotation == nil then
        return
    end
    desired_rotation.Yaw = desired_rotation.Yaw
        + (yaw_amount * (degrees_override or Config.rotation.normal))

    ExecuteInGameThread(function()
        apply_preview_transform()
    end)
end

local function change_move_step(multiplier)
    current_move_step = math.max(
        Config.movement.minimum,
        math.min(Config.movement.maximum, current_move_step * multiplier)
    )
    log(string.format("Move step: %.1f cm", current_move_step))
end

local function register_chord(key, modifiers, callback)
    local ok, error_message = pcall(function()
        RegisterKeyBind(key, modifiers, callback)
    end)
    if not ok then
        log(string.format(
            "Could not register key 0x%X: %s",
            key,
            tostring(error_message)
        ))
    end
end

local CTRL = { ModifierKey.CONTROL }
local CTRL_SHIFT = { ModifierKey.CONTROL, ModifierKey.SHIFT }
local CTRL_ALT = { ModifierKey.CONTROL, ModifierKey.ALT }

-- Normal placement increments.
register_chord(VK.LEFT, CTRL, function() move_preview(0, -1, 0) end)
register_chord(VK.RIGHT, CTRL, function() move_preview(0, 1, 0) end)
register_chord(VK.UP, CTRL, function() move_preview(1, 0, 0) end)
register_chord(VK.DOWN, CTRL, function() move_preview(-1, 0, 0) end)
register_chord(VK.PAGE_UP, CTRL, function() move_preview(0, 0, 1) end)
register_chord(VK.PAGE_DOWN, CTRL, function() move_preview(0, 0, -1) end)

-- Fine increments.
register_chord(VK.LEFT, CTRL_SHIFT, function() move_preview(0, -1, 0, Config.movement.fine) end)
register_chord(VK.RIGHT, CTRL_SHIFT, function() move_preview(0, 1, 0, Config.movement.fine) end)
register_chord(VK.UP, CTRL_SHIFT, function() move_preview(1, 0, 0, Config.movement.fine) end)
register_chord(VK.DOWN, CTRL_SHIFT, function() move_preview(-1, 0, 0, Config.movement.fine) end)
register_chord(VK.PAGE_UP, CTRL_SHIFT, function() move_preview(0, 0, 1, Config.movement.fine) end)
register_chord(VK.PAGE_DOWN, CTRL_SHIFT, function() move_preview(0, 0, -1, Config.movement.fine) end)

-- Coarse increments.
register_chord(VK.LEFT, CTRL_ALT, function() move_preview(0, -1, 0, Config.movement.coarse) end)
register_chord(VK.RIGHT, CTRL_ALT, function() move_preview(0, 1, 0, Config.movement.coarse) end)
register_chord(VK.UP, CTRL_ALT, function() move_preview(1, 0, 0, Config.movement.coarse) end)
register_chord(VK.DOWN, CTRL_ALT, function() move_preview(-1, 0, 0, Config.movement.coarse) end)
register_chord(VK.PAGE_UP, CTRL_ALT, function() move_preview(0, 0, 1, Config.movement.coarse) end)
register_chord(VK.PAGE_DOWN, CTRL_ALT, function() move_preview(0, 0, -1, Config.movement.coarse) end)

register_chord(VK.Q, CTRL, function() rotate_preview(-1) end)
register_chord(VK.E, CTRL, function() rotate_preview(1) end)
register_chord(VK.Q, CTRL_SHIFT, function() rotate_preview(-1, Config.rotation.fine) end)
register_chord(VK.E, CTRL_SHIFT, function() rotate_preview(1, Config.rotation.fine) end)
register_chord(VK.Q, CTRL_ALT, function() rotate_preview(-1, Config.rotation.coarse) end)
register_chord(VK.E, CTRL_ALT, function() rotate_preview(1, Config.rotation.coarse) end)

register_chord(VK.OPEN_BRACKET, CTRL, function()
    change_move_step(1.0 / Config.movement.step_scale)
end)
register_chord(VK.CLOSE_BRACKET, CTRL, function()
    change_move_step(Config.movement.step_scale)
end)

-- Development controls. The final-confirm and cancel hooks remain in the
-- Palworld adapter milestone because their 1.0 function paths need a live dump.
register_chord(VK.F6, CTRL, discover_preview)
register_chord(VK.F7, CTRL, function()
    if state == State.EDITING then
        release_preview()
    else
        begin_editing()
    end
end)
register_chord(VK.F8, CTRL, function()
    log("Writing UE4SS actor dump; search it for BuildObject, Preview, Indicator, or Placement.")
    DumpAllActors()
end)

log("Loaded development build 0.1.0-dev")
log("Open build mode, show a preview, press Ctrl+F6 to discover it, then Ctrl+F7 to lock it.")
