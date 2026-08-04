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

local launch_ui_file = assert(io.open("QuickConnectManager/Scripts/launch_ui.lua", "rb"))
local launch_ui_source = launch_ui_file:read("*a")
launch_ui_file:close()

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
expect("lifecycle poll stops outside title", delayed_after_first_start == 0)
expect(
    "server rows use a vertical scroll container",
    launch_ui_source:find('construct("/Script/UMG.ScrollBox"', 1, true) ~= nil
)
expect(
    "server list renders every entry",
    launch_ui_source:find("for index = 1, #state.entries do", 1, true) ~= nil
)
expect(
    "server list is not capped at the viewport row count",
    launch_ui_source:find("math.min(#state.entries, MAX_ROWS)", 1, true) == nil
)
expect(
    "add texture uses the approved Palworld asset",
    launch_ui_source:find("T_prt_add_plus", 1, true) ~= nil
)
expect(
    "modify texture uses the approved Palworld asset",
    launch_ui_source:find("T_icon_Guild_Edit", 1, true) ~= nil
)
expect(
    "delete texture uses the approved Palworld asset",
    launch_ui_source:find("T_icon_garbage", 1, true) ~= nil
)
expect(
    "editor uses Palworld native editable text",
    launch_ui_source:find('construct("/Script/Pal.PalEditableTextBox"', 1, true) ~= nil
)
expect(
    "editor copies Palworld join and password input archetypes",
    launch_ui_source:find("PalEditableTextBox_IP", 1, true) ~= nil
        and launch_ui_source:find("PalEditableTextBox_111", 1, true) ~= nil
)
expect(
    "password editor field includes the native lock texture",
    launch_ui_source:find("state.lock_texture", 1, true) ~= nil
        and launch_ui_source:find("password == true", 1, true) ~= nil
)
expect(
    "approved action icon sizes are retained",
    launch_ui_source:find("local ADD_ICON_SIZE = 14", 1, true) ~= nil
        and launch_ui_source:find("local REMOVE_ICON_SIZE = 27", 1, true) ~= nil
)
expect(
    "refresh uses Palworld-style per-row ping loading",
    launch_ui_source:find('construct("/Script/UMG.CircularThrobber"', 1, true) ~= nil
        and launch_ui_source:find("function LaunchUI.set_statuses", 1, true) ~= nil
)
expect(
    "open editor blocks background actions without disabled white styling",
    launch_ui_source:find("and action.kind ~= \"editor_confirm\"", 1, true) ~= nil
        and launch_ui_source:find("set_native_button_interactive", 1, true) ~= nil
        and launch_ui_source:find("button.WBP_PalInvisibleButton", 1, true) ~= nil
        and launch_ui_source:find("input:SetIsEnabled(true)", 1, true) ~= nil
        and launch_ui_source:find("add_inactive_button_background", 1, true) ~= nil
        and launch_ui_source:find('construct("/Script/UMG.Image"', 1, true) ~= nil
        and launch_ui_source:find('state.editor_mode == "modify"', 1, true) ~= nil
        and launch_ui_source:find("B = 0.38", 1, true) ~= nil
        and launch_ui_source:find("button:SetIsEnabled(state.editor_mode == nil)", 1, true) == nil
)
expect(
    "one-shot native actions reject duplicate delegate delivery",
    launch_ui_source:find("registration.consumed == true", 1, true) ~= nil
        and launch_ui_source:find("registration.consumed = true", 1, true) ~= nil
        and launch_ui_source:find("panel_logged_title_key", 1, true) ~= nil
)
expect(
    "editor expands the existing panel",
    launch_ui_source:find("EXPANDED_PANEL_HEIGHT", 1, true) ~= nil
        and launch_ui_source:find('state.editor_mode == "add"', 1, true) ~= nil
)
expect(
    "gamepad navigation routes dpad and cancel",
    launch_ui_source:find("Gamepad_DPad_Down", 1, true) ~= nil
        and launch_ui_source:find("Gamepad_FaceButton_Right", 1, true) ~= nil
)

LaunchUI.set_entries({}, "Refresh complete")
expect("entry update still waits for a stable title widget", delayed_count(50) == 0)

expect(
    "gameplay lifecycle has no delayed callbacks",
    #delayed == 0
        and launch_ui_source:find("return nil", 1, true) ~= nil
        and launch_ui_source:find("if not state.lifecycle_polling then", 1, true) ~= nil
)
expect(
    "metadata fetch waits for a stable title and cancels after leaving it",
    launch_ui_source:find("Stable title metadata readiness", 1, true) ~= nil
        and launch_ui_source:find("state.title_context_revision == revision", 1, true) ~= nil
        and launch_ui_source:find("state.title_available", 1, true) ~= nil
)
if failures > 0 then
    error(string.format("%d test(s) failed", failures))
end
print("Quick Connect Manager launch UI tests passed")
