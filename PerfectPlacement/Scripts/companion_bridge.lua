-- Loads the cooked Perfect Placement Blueprint input bridge from the regular
-- _P.pak. This replaces BPModLoader's LogicMods-directory discovery while
-- preserving Palworld's event-driven controller input path.

local M = {}
local Instance = {}
Instance.__index = Instance

local retained_instances = {}
local retained_serial = 0

local MOD_ACTOR_CLASS = "ModActor_C"
local MOD_ACTOR_PACKAGE = "/Game/Mods/PerfectPlacement/ModActor"
local MOD_ACTOR_CLASS_PATH =
    "BlueprintGeneratedClass " .. MOD_ACTOR_PACKAGE .. "." .. MOD_ACTOR_CLASS

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

function Instance:ensure(world_value)
    local world = unwrap(world_value)
    if not self.is_valid(world) then
        return false, "world is unavailable"
    end

    if self:_actor_matches_world(self.actor, world) then
        return true
    end
    local existing = self:_find_existing_actor(world)
    if self.is_valid(existing) then
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

    local spawn_ok, actor = pcall(function()
        return world:SpawnActor(actor_class, {}, {})
    end)
    if not spawn_ok or not self.is_valid(actor) then
        local reason = spawn_ok and "SpawnActor returned an invalid actor"
            or tostring(actor)
        self.log("Companion input bridge spawn failed: " .. reason)
        return false, reason
    end

    self.actor = actor
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


function Instance:start()
    if self.started then
        return true
    end
    self.started = true

    self.load_map_callback = function(_, world)
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

function M.new(options)
    options = options or {}
    return setmetatable({
        log = type(options.log) == "function" and options.log or default_log,
        is_valid = type(options.is_valid) == "function"
            and options.is_valid or default_is_valid,
        execute_in_game_thread = options.execute_in_game_thread,
        ue_helpers = options.ue_helpers,
        started = false,
        missing_logged = false,
    }, Instance)
end

return M
