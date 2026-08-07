-- Lifecycle boundary for all controller-specific Perfect Placement
-- behavior. The shared placement runtime may dispatch actions through this
-- facade, but controller code never receives direct access to preview state.

local Gamepad = require("gamepad")
local CompanionBridge = require("companion_bridge")

local M = {}
local Instance = {}
Instance.__index = Instance

local function script_directory()
    if debug == nil or debug.getinfo == nil then
        return nil
    end
    local source = debug.getinfo(1, "S").source
    if type(source) ~= "string" or string.sub(source, 1, 1) ~= "@" then
        return nil
    end
    return string.match(string.sub(source, 2), "^(.*[\\/])")
end

local function native_mode_path()
    local directory = script_directory()
    if directory == nil then
        return nil
    end
    return directory .. "..\\native_gamepad_mode.txt"
end

local function default_log(message)
    print("[PerfectPlacement] " .. tostring(message))
end

function Instance:is_enabled()
    return self.enabled == true
end

function Instance:start()
    if not self.enabled then
        return false, "gamepad support is disabled"
    end
    if self.started then
        return true
    end

    self.started = true
    local bridge_ok, bridge_reason = self.bridge:start()
    if not bridge_ok then
        self.started = false
        return false, bridge_reason
    end
    self.log("Isolated gamepad feature started.")
    return true
end

function Instance:attach_host(host)
    if not self.enabled or not self.started then
        return false
    end
    return self.input:attach_host(host)
end

function Instance:detach_host(host)
    if self.input == nil then
        return true
    end
    return self.input:detach_host(host)
end

function Instance:set_mode(mode)
    if not self.enabled or not self.started then
        return false, "gamepad support is disabled"
    end
    self.mode = mode
    self:_write_native_mode(mode)
    return self.bridge:set_gamepad_input_mode(mode)
end

function Instance:_write_native_mode(mode)
    if type(self.native_mode_path) ~= "string" then
        return false
    end
    local file = io.open(self.native_mode_path, "wb")
    if file == nil then
        if not self.native_mode_write_failed then
            self.native_mode_write_failed = true
            self.log("Native gamepad mode file could not be written.")
        end
        return false
    end
    file:write(tostring(mode or "hidden"))
    file:close()
    self.native_mode_write_failed = false
    return true
end

function Instance:dispatch_native_physical(index)
    if not self.enabled or not self.started or self.input == nil then
        return false
    end
    return self.input:dispatch_native_physical(index)
end

function Instance:set_using_gamepad(using_gamepad)
    if not self.enabled or not self.started or self.input == nil then
        return false
    end
    return self.input:set_using_gamepad(using_gamepad)
end

function Instance:ensure_current_world()
    if not self.enabled or not self.started then
        return false, "gamepad support is disabled"
    end
    return self.bridge:ensure_current_world()
end

function Instance:get_resolved_bindings()
    if self.input == nil then
        return {}, {}
    end
    return self.input:get_resolved_bindings()
end

function Instance:get_keycap_texture(token)
    if self.input == nil then
        return nil
    end
    return self.input:get_keycap_texture(token)
end

function Instance:shutdown()
    if self.input ~= nil then
        self.input:shutdown()
    end
    if self.bridge ~= nil then
        self.bridge:shutdown()
    end
    self.started = false
    self.mode = "hidden"
    self:_write_native_mode("hidden")
    self.log("Isolated gamepad feature stopped.")
    return true
end

function M.new(options)
    options = options or {}
    if type(options.dispatch_action) ~= "function" then
        error("gamepad_feature.new requires dispatch_action")
    end

    local config = options.config or {}
    local gamepad_config = config.gamepad or config
    local enabled = gamepad_config.enabled == true
    local resolved_native_mode_path = options.native_mode_path
    if resolved_native_mode_path == nil then
        resolved_native_mode_path = native_mode_path()
    end
    local instance = setmetatable({
        enabled = enabled,
        started = false,
        log = type(options.log) == "function" and options.log or default_log,
        input = nil,
        bridge = nil,
        mode = "hidden",
        get_host = options.get_host,
        native_mode_path = resolved_native_mode_path,
        native_mode_write_failed = false,
    }, Instance)

    -- A disabled feature constructs no input adapter or companion bridge. This
    -- is the kill-switch guarantee used to protect the PC-only runtime.
    if not enabled then
        return instance
    end

    local gamepad_module = options.gamepad_module or Gamepad
    local companion_bridge_module = options.companion_bridge_module
        or CompanionBridge
    instance.input = gamepad_module.new({
        config = config,
        log = instance.log,
        is_valid = options.is_valid,
        dispatch_action = options.dispatch_action,
        enabled_property = options.enabled_property,
        load_keycap_texture = options.load_keycap_texture,
        get_host = options.get_host,
        register_hook = options.register_hook,
        unregister_hook = options.unregister_hook,
    })
    instance.bridge = companion_bridge_module.new({
        log = instance.log,
        is_valid = options.is_valid,
        ue_helpers = options.ue_helpers,
        delay = options.delay,
        execute_in_game_thread = options.execute_in_game_thread,
        unregister_load_map_post_hook = options.unregister_load_map_post_hook,
    })
    return instance
end

return M
