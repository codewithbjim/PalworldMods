-- Loader for the cooked Perfect Placement Blueprint input bridge from the regular
-- _P.pak while preserving Palworld's event-driven controller input path.

local M = {}
local Instance = {}
Instance.__index = Instance

local retained_instances = {}
local retained_serial = 0

local MOD_ACTOR_CLASS = "ModActor_C"
local MOD_ACTOR_PACKAGE = "/Game/Mods/PerfectPlacement/ModActor"
local MOD_ACTOR_CLASS_PATH =
    "BlueprintGeneratedClass " .. MOD_ACTOR_PACKAGE .. "." .. MOD_ACTOR_CLASS
local PLAYER_CONTROLLER_RETRY_MS = 250
local PLAYER_CONTROLLER_MAX_ATTEMPTS = 40
local GAMEPAD_INPUT_PRIORITY = 10000

local function default_log(message)
    print("[PerfectPlacement] " .. tostring(message))
end

local function default_is_valid(object)
    if object == nil then
        return false
    end
    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    return ok and valid == true
end

local function unwrap(value)
    if value == nil then
        return nil
    end
    local ok, result = pcall(function()
        return value:get()
    end)
    if ok and result ~= nil then
        return result
    end
    return value
end

local function object_full_name(object)
    if object == nil then
        return nil
    end
    local ok, name = pcall(function()
        return object:GetFullName()
    end)
    if ok and type(name) == "string" then
        return name
    end
    return nil
end

function Instance:_find_existing_actor(world)
    local ok, actors = pcall(FindAllOf, MOD_ACTOR_CLASS)
    if not ok or type(actors) ~= "table" then
        return nil
    end
    local world_name = object_full_name(world)
    for _, actor in ipairs(actors) do
        if self.is_valid(actor) then
            local class_ok, class_name = pcall(function()
                return actor:GetClass():GetFullName()
            end)
            local actor_world_ok, actor_world_name = pcall(function()
                return object_full_name(actor:GetWorld())
            end)
            if class_ok
                and class_name == MOD_ACTOR_CLASS_PATH
                and actor_world_ok
                and actor_world_name == world_name
            then
                return actor
            end
        end
    end
    return nil
end

function Instance:_actor_matches_world(actor, world)
    if not self.is_valid(actor) or not self.is_valid(world) then
        return false
    end
    local ok, matches = pcall(function()
        return actor:GetClass():GetFullName() == MOD_ACTOR_CLASS_PATH
            and object_full_name(actor:GetWorld()) == object_full_name(world)
    end)
    return ok and matches == true
end

function Instance:_load_actor_class()
    local ue_helpers = self.ue_helpers
    if type(ue_helpers) ~= "table"
        or type(ue_helpers.FindOrAddFName) ~= "function"
    then
        return nil, "UEHelpers.FindOrAddFName is unavailable"
    end
    local helpers_ok, helpers = pcall(
        StaticFindObject,
        "/Script/AssetRegistry.Default__AssetRegistryHelpers"
    )
    if not helpers_ok or not self.is_valid(helpers) then
        return nil, "AssetRegistryHelpers is unavailable"
    end

    local fname_ok, package_name, asset_name = pcall(function()
        return ue_helpers.FindOrAddFName(MOD_ACTOR_PACKAGE),
            ue_helpers.FindOrAddFName(MOD_ACTOR_CLASS)
    end)
    if not fname_ok then
        return nil, "could not create ModActor asset names: "
            .. tostring(package_name)
    end

    local asset_ok, actor_class = pcall(function()
        return helpers:GetAsset({
            PackageName = package_name,
            AssetName = asset_name,
        })
    end)
    if not asset_ok or not self.is_valid(actor_class) then
        return nil, "ModActor_C could not be loaded from the consolidated _P.pak"
    end
    return actor_class
end

function Instance:_destroy_stale_actor(actor)
    if not self.is_valid(actor) then
        return true
    end
    local destroy_ok, destroy_error = pcall(function()
        actor:K2_DestroyActor()
    end)
    if not destroy_ok then
        self.log("Companion bridge hot-reload cleanup failed: "
            .. tostring(destroy_error))
        return false
    end
    self.log("Replaced the surviving companion bridge after a Lua reload.")
    return true
end

function Instance:_local_player_controller_ready()
    local ue_helpers = self.ue_helpers
    if type(ue_helpers) ~= "table"
        or type(ue_helpers.GetPlayerController) ~= "function"
    then
        return false, "UEHelpers.GetPlayerController is unavailable"
    end
    local controller_ok, controller = pcall(function()
        return ue_helpers:GetPlayerController()
    end)
    if not controller_ok then
        return false, tostring(controller)
    end
    if not self.is_valid(controller) then
        return false, "local player controller is unavailable"
    end
    return true
end

function Instance:_schedule_player_controller_retry()
    if self.requested_mode == "hidden"
        or self.retry_pending
        or self.retry_attempts >= PLAYER_CONTROLLER_MAX_ATTEMPTS
        or type(self.delay) ~= "function"
    then
        return false
    end

    self.retry_pending = true
    self.retry_attempts = self.retry_attempts + 1
    local generation = self.world_generation
    local queued = self.delay(
        PLAYER_CONTROLLER_RETRY_MS,
        function()
            if not self.started then
                return
            end
            if generation ~= self.world_generation then
                return
            end
            self.retry_pending = false
            local ok, ready, reason = pcall(
                self.ensure_current_world,
                self
            )
            if not ok then
                self.log("Companion bridge retry recovered from an error: "
                    .. tostring(ready))
            elseif not ready
                and self.retry_attempts >= PLAYER_CONTROLLER_MAX_ATTEMPTS
            then
                self.log("Companion input bridge stopped waiting: "
                    .. tostring(reason))
            end
        end,
        "Companion bridge player-controller retry"
    )
    if queued ~= true then
        self.retry_pending = false
        return false
    end
    return true
end

function Instance:ensure(world_value)
    if self.requested_mode == "hidden" then
        return false, "companion input is hidden"
    end
    local world = unwrap(world_value)
    if not self.is_valid(world) then
        return false, "world is unavailable"
    end

    if self:_actor_matches_world(self.actor, world) then
        return true
    end
    if self.spawn_in_progress then
        return false, "companion input bridge spawn is already in progress"
    end
    -- ModActor captures Get Player Controller(0) during BeginPlay and passes it
    -- to both child input actors. RegisterLoadMapPostHook can run before that
    -- controller exists; spawning here would permanently initialize controller
    -- input with nil even though the widget and Lua hook otherwise look healthy.
    local controller_ready, controller_error =
        self:_local_player_controller_ready()
    if not controller_ready then
        self:_schedule_player_controller_retry()
        return false, controller_error
    end


    -- UE4SS Restart All Mods reloads Lua without tearing down the cooked actor.
    -- Replace that survivor so BeginPlay captures the now-valid controller and
    -- rebuilds device detection plus both child input actors from clean state.
    local existing = self:_find_existing_actor(world)
    if self.is_valid(existing) and not self:_destroy_stale_actor(existing) then
        self.actor = existing
        self.missing_logged = false
        return true
    end

    local actor_class, load_error = self:_load_actor_class()
    if not self.is_valid(actor_class) then
        if not self.missing_logged then
            self.log("Companion input bridge is not ready: " .. tostring(load_error))
            self.missing_logged = true
        end
        return false, load_error
    end

    self.spawn_in_progress = true
    local spawn_ok, actor = pcall(function()
        return world:SpawnActor(actor_class, {}, {})
    end)
    self.spawn_in_progress = false
    if not spawn_ok or not self.is_valid(actor) then
        local reason = spawn_ok and "SpawnActor returned an invalid actor"
            or tostring(actor)
        self.log("Companion input bridge spawn failed: " .. reason)
        return false, reason
    end

    self.actor = actor
    self.forced_gamepad_input_mode = nil
    self.retry_pending = false
    self.retry_attempts = 0
    self.missing_logged = false
    self.log("Companion input bridge spawned from the consolidated _P.pak: "
        .. tostring(object_full_name(actor)))
    return true
end

function Instance:ensure_current_world()
    local ue_helpers = self.ue_helpers
    if type(ue_helpers) ~= "table"
        or type(ue_helpers.GetWorld) ~= "function"
    then
        return false, "UEHelpers.GetWorld is unavailable"
    end
    local world_ok, world = pcall(function()
        return ue_helpers.GetWorld()
    end)
    if not world_ok then
        return false, tostring(world)
    end
    return self:ensure(world)
end

function Instance:set_gamepad_input_mode(mode)
    if mode ~= "hidden" and mode ~= "unfrozen" and mode ~= "frozen" then
        return false, "unsupported gamepad input mode " .. tostring(mode)
    end
    self.requested_mode = mode
    if mode ~= "hidden" and not self.is_valid(self.actor) then
        local ready, reason = self:ensure_current_world()
        if not ready then
            return false, reason
        end
    end
    if not self.is_valid(self.actor) then
        -- Hidden mode during a world transition is intentionally Lua-only.
        -- Never reacquire or touch a companion actor in a splash/title world.
        self.forced_gamepad_input_mode = "hidden"
        return true
    end
    if self.forced_gamepad_input_mode == mode then
        return true
    end

    local ok, error_message = pcall(function()
        local unfrozen = self.actor.UnfrozenInputActor
        local frozen = self.actor.FrozenInputActor
        if not self.is_valid(unfrozen) or not self.is_valid(frozen) then
            error("one or more child input actors are unavailable")
        end

        -- Palworld's construction listeners can sit above the Blueprint's
        -- authored priority of 20 and consume D-pad Up or the shoulders first.
        -- Raise only PP's two input actors; their individual bindings consume
        -- PP chords while bBlockInput remains false for unrelated controls.
        unfrozen.InputPriority = GAMEPAD_INPUT_PRIORITY
        frozen.InputPriority = GAMEPAD_INPUT_PRIORITY

        if mode == "unfrozen" then
            frozen:DeactivateInput()
            unfrozen:ActivateInput()
        elseif mode == "frozen" then
            unfrozen:DeactivateInput()
            frozen:ActivateInput()
        else
            unfrozen:DeactivateInput()
            frozen:DeactivateInput()
        end
    end)
    if not ok then
        self.log("Could not enforce gamepad input mode " .. mode .. ": "
            .. tostring(error_message))
        return false, tostring(error_message)
    end

    self.forced_gamepad_input_mode = mode
    self.log("Enforced gamepad input mode: " .. mode)
    return true
end

function Instance:start()
    if self.started then
        return true
    end
    self.started = true
    self.spawn_in_progress = false

    self.load_map_callback = function(_, world)
        if not self.started then
            return
        end
        self.world_generation = self.world_generation + 1
        self.retry_pending = false
        self.retry_attempts = 0
        local ok, reason = pcall(self.ensure, self, world)
        if not ok then
            self.log("Companion bridge map callback recovered from an error: "
                .. tostring(reason))
        end
    end
    local hook_ok, hook_id = pcall(
        RegisterLoadMapPostHook,
        self.load_map_callback
    )
    if not hook_ok then
        self.started = false
        self.log("Companion bridge map hook was not registered: "
            .. tostring(hook_id))
        return false, hook_id
    end
    self.load_map_hook_id = hook_id

    retained_serial = retained_serial + 1
    self.retention_id = retained_serial
    retained_instances[self.retention_id] = self

    local execute = self.execute_in_game_thread or _G.ExecuteInGameThread
    if type(execute) == "function" then
        local callback = function()
            local call_ok, ready, reason = pcall(
                self.ensure_current_world,
                self
            )
            if not call_ok then
                self.log("Companion bridge startup recovered from an error: "
                    .. tostring(ready))
            elseif not ready and not self.missing_logged then
                self.log("Companion input bridge is waiting for a live world: "
                    .. tostring(reason))
                self.missing_logged = true
            end
        end
        self.startup_callback = callback
        local queued_ok, queue_error = pcall(execute, callback)
        if not queued_ok then
            self.log("Companion bridge startup could not be queued: "
                .. tostring(queue_error))
        end
    end
    return true
end

function Instance:shutdown()
    self.started = false
    self.world_generation = self.world_generation + 1
    self.retry_pending = false
    self.forced_gamepad_input_mode = nil

    if self.is_valid(self.actor) then
        pcall(function()
            local unfrozen = self.actor.UnfrozenInputActor
            local frozen = self.actor.FrozenInputActor
            if self.is_valid(unfrozen) then
                unfrozen:DeactivateInput()
            end
            if self.is_valid(frozen) then
                frozen:DeactivateInput()
            end
            self.actor:K2_DestroyActor()
        end)
    end
    self.actor = nil

    if type(self.unregister_load_map_post_hook) == "function"
        and self.load_map_hook_id ~= nil
    then
        pcall(self.unregister_load_map_post_hook, self.load_map_hook_id)
    end
    self.load_map_hook_id = nil
    if self.retention_id ~= nil then
        retained_instances[self.retention_id] = nil
        self.retention_id = nil
    end
    return true
end

function M.new(options)
    options = options or {}
    return setmetatable({
        log = type(options.log) == "function" and options.log or default_log,
        is_valid = type(options.is_valid) == "function"
            and options.is_valid or default_is_valid,
        execute_in_game_thread = options.execute_in_game_thread,
        delay = options.delay,
        ue_helpers = options.ue_helpers,
        unregister_load_map_post_hook = options.unregister_load_map_post_hook,
        started = false,
        missing_logged = false,
        forced_gamepad_input_mode = nil,
        requested_mode = "hidden",
        retry_attempts = 0,
        retry_pending = false,
        world_generation = 0,
    }, Instance)
end

return M
