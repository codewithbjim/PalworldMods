local LaunchUI = {}
local UEHelpers = require("UEHelpers")

local TITLE_CLASS =
    "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_TitleMenu"
    .. ".WBP_TitleMenu_C"
local TITLE_SHORT_CLASS = "WBP_TitleMenu_C"
local TITLE_TICK = TITLE_CLASS .. ":Tick"
local DISCLAIMER_CLASS =
    "/Game/Pal/Blueprint/UI/Mods/WBP_ModDisclaimerDialog"
    .. ".WBP_ModDisclaimerDialog_C"
local PANEL_PACKAGE =
    "/Game/Mods/QuickConnectManager/WBP_QuickConnectPanel"
local PANEL_CLASS = PANEL_PACKAGE .. ".WBP_QuickConnectPanel_C"
local PANEL_ASSET_NAME = "WBP_QuickConnectPanel_C"
local BUTTON_PACKAGE =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_CommonButton"
local BUTTON_CLASS = BUTTON_PACKAGE .. ".WBP_CommonButton_C"
local BUTTON_ASSET_NAME = "WBP_CommonButton_C"
local JOIN_INPUT_PACKAGE =
    "/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect"
local JOIN_INPUT_CLASS = JOIN_INPUT_PACKAGE .. ".WBP_Title_WorldSelect_C"
local JOIN_INPUT_ASSET_NAME = "WBP_Title_WorldSelect_C"
local JOIN_INPUT_TEMPLATE = JOIN_INPUT_CLASS
    .. ":WidgetTree.PalEditableTextBox_IP"
local PASSWORD_INPUT_PACKAGE =
    "/Game/Pal/Blueprint/UI/UserInterface/Title/"
    .. "WBP_Title_WorldSelect_OverlayWindow_InputCode"
local PASSWORD_INPUT_CLASS = PASSWORD_INPUT_PACKAGE
    .. ".WBP_Title_WorldSelect_OverlayWindow_InputCode_C"
local PASSWORD_INPUT_ASSET_NAME =
    "WBP_Title_WorldSelect_OverlayWindow_InputCode_C"
local PASSWORD_INPUT_TEMPLATE = PASSWORD_INPUT_CLASS
    .. ":WidgetTree.PalEditableTextBox_111"
local REFRESH_TEXTURE_PACKAGE =
    "/Game/Pal/Texture/UI/KeyGuide/T_prt_KeyGuide_change"
local REFRESH_TEXTURE_NAME = "T_prt_KeyGuide_change"
local ADD_TEXTURE_PACKAGE =
    "/Game/Pal/Texture/UI/IngameMenu/T_prt_add_plus"
local ADD_TEXTURE_NAME = "T_prt_add_plus"
local EDIT_TEXTURE_PACKAGE =
    "/Game/Pal/Texture/UI/Main_Menu/T_icon_Guild_Edit"
local EDIT_TEXTURE_NAME = "T_icon_Guild_Edit"
local REMOVE_TEXTURE_PACKAGE =
    "/Game/Pal/Texture/UI/Main_Menu/T_icon_garbage"
local REMOVE_TEXTURE_NAME = "T_icon_garbage"
local LOCK_TEXTURE_PACKAGE =
    "/Game/Pal/Texture/UI/Main_Menu/T_Icon_lock"
local LOCK_TEXTURE_NAME = "T_Icon_lock"
local BUTTON_CLICK = BUTTON_CLASS
    .. ":BndEvt__WBP_CommonButton_WBP_PalInvisibleButton_"
    .. "K2Node_ComponentBoundEvent_3_CommonButtonBaseClicked__DelegateSignature"
local WIDGET_LIBRARY = "/Script/UMG.Default__WidgetBlueprintLibrary"

local PANEL_WIDTH = 500
local PANEL_HEIGHT = 300
local EXPANDED_PANEL_HEIGHT = 570
local ROW_X = 22
local ROW_WIDTH = PANEL_WIDTH - 126
local EDIT_X = PANEL_WIDTH - 98
local EDIT_WIDTH = 34
local REMOVE_X = PANEL_WIDTH - 56
local REMOVE_WIDTH = 34
local ROW_HEIGHT = 42
local ROW_GAP = 4
local ROW_START_Y = 77
local MAX_ROWS = 3
local ROW_VIEWPORT_HEIGHT = MAX_ROWS * ROW_HEIGHT + (MAX_ROWS - 1) * ROW_GAP
local REFRESH_ICON_SIZE = 40
local ADD_ICON_SIZE = 14
local EDIT_ICON_SIZE = 28
local LOCK_ICON_SIZE = 27
local REMOVE_ICON_SIZE = 27
local TITLE_POLL_MS = 750
local GAMEPLAY_POLL_MS = 2000

local state = {
    entries = {},
    connect = function() end,
    status = function()
        return nil
    end,
    refresh = function() end,
    remove = function() end,
    modify = function() end,
    add = function() end,
    connection_failed = function() end,
    title_available = function() end,
    refreshing = false,
    refresh_feedback = nil,
    refresh_feedback_revision = 0,
    log = function() end,
    controller = nil,
    title_widget = nil,
    title_widget_key = nil,
    title_menu_visible = nil,
    title_context_revision = 0,
    title_stable = false,
    title_tick_hook_armed = false,
    title_key = nil,
    panel = nil,
    panel_revision = 0,
    panel_logged_title_key = nil,
    title_available_notified_key = nil,
    refresh_button = nil,
    refresh_icon = nil,
    refresh_feedback_label = nil,
    actions = {},
    click_hook_armed = false,
    panel_class = nil,
    button_class = nil,
    join_input_class = nil,
    password_input_class = nil,
    join_input_template = nil,
    password_input_template = nil,
    refresh_texture = nil,
    add_texture = nil,
    edit_texture = nil,
    remove_texture = nil,
    lock_texture = nil,
    build_failed_title_key = nil,
    last_disclaimer_visible = nil,
    dismissed_title_key = nil,
    recovery_title_key = nil,
    recovery_saw_hidden = false,
    connection_attempt_id = 0,
    render_requested = false,
    render_scheduled = false,
    asset_retry_scheduled = false,
    asset_failure_logged_title_key = nil,
    empty_message = "No dedicated servers configured",
    ready = true,
    started = false,
    lifecycle_polling = false,
    generation = 0,
    in_title_context = false,
    title_notification_armed = false,
    disclaimer_notification_armed = false,
    callback_sequence = 0,
    pending_callbacks = {},
    click_hook_callback = nil,
    title_tick_callback = nil,
    title_notification_callback = nil,
    disclaimer_notification_callback = nil,
    editor_mode = nil,
    editor_index = nil,
    editor_draft = nil,
    editor_inputs = {},
    status_widgets = {},
    focus_items = {},
    focus_index = nil,
    gamepad_down = {},
    restore_focus = nil,
    focus_requested = false,
}

local function retain_one_shot(callback)
    state.callback_sequence = state.callback_sequence + 1
    local callback_id = state.callback_sequence
    local wrapper = function(...)
        state.pending_callbacks[callback_id] = nil
        return callback(...)
    end
    state.pending_callbacks[callback_id] = wrapper
    return wrapper, callback_id
end

local function release_callback(callback_id)
    state.pending_callbacks[callback_id] = nil
end

local function safe_log(message)
    local value = tostring(message)
    local ok = pcall(state.log, value)
    if not ok then
        pcall(print, "[QuickConnectManager] " .. value .. "\n")
    end
end

local function protected_call(label, callback, ...)
    if type(callback) ~= "function" then
        safe_log(label .. " was ignored because its callback is unavailable.")
        return false, nil
    end
    local ok, first, second = pcall(callback, ...)
    if not ok then
        safe_log(label .. " failed safely: " .. tostring(first))
        return false, nil
    end
    return true, first, second
end

local function run_on_game_thread(label, callback)
    local generation = state.generation
    local game_thread_callback, callback_id = retain_one_shot(function()
        if not state.started or generation ~= state.generation then
            return
        end
        protected_call(label, callback)
    end)
    local ok, schedule_error = pcall(ExecuteInGameThread, game_thread_callback)
    if not ok then
        release_callback(callback_id)
        safe_log(label .. " could not enter the game thread: " .. tostring(schedule_error))
    end
    return ok
end

local function schedule(delay_ms, label, callback)
    local generation = state.generation
    local delay = math.max(0, math.floor(tonumber(delay_ms) or 0))
    local delayed_callback, callback_id = retain_one_shot(function()
        if not state.started or generation ~= state.generation then
            return
        end
        protected_call(label, callback)
    end)
    local ok, schedule_error = pcall(ExecuteWithDelay, delay, delayed_callback)
    if not ok then
        release_callback(callback_id)
        safe_log(label .. " could not be scheduled: " .. tostring(schedule_error))
    end
    return ok
end

local function schedule_on_game_thread(delay_ms, label, callback)
    return schedule(delay_ms, label .. " delay", function()
        run_on_game_thread(label, callback)
    end)
end

local function alive(object)
    if object == nil then
        return false
    end
    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    return ok and valid == true
end

local function object_address(object)
    if not alive(object) then
        return nil
    end
    local ok, value = pcall(function()
        return object:GetAddress()
    end)
    return ok and tostring(value) or nil
end

local function full_name(object)
    if not alive(object) then
        return "<invalid>"
    end
    local ok, value = pcall(function()
        return object:GetFullName()
    end)
    return ok and tostring(value) or "<unnamed>"
end

local function live_title_widget(object)
    if not alive(object) then
        return false
    end
    local name = full_name(object)
    if name:find("Default__", 1, true) ~= nil
        or name:find("WidgetBlueprintGeneratedClass", 1, true) ~= nil
    then
        return false
    end
    local tree_ok, tree = pcall(function()
        return object.WidgetTree
    end)
    return tree_ok and alive(tree)
end

local function main_menu_is_visible(title_widget)
    if not live_title_widget(title_widget) then
        return false
    end
    local ok, visible = pcall(function()
        -- CanvasPanelMenu is present in the cooked WidgetTree but is not an
        -- exposed Blueprint variable. Start Game is exposed, and IsVisible()
        -- includes the visibility of its CanvasPanelMenu parent.
        local probe = title_widget.WBP_Title_MenuButton_StartLocalGame
        if alive(probe) then
            return probe:IsVisible()
        end
        return title_widget:IsVisible()
    end)
    return ok and visible == true
end

local function construct(class_path, outer, template)
    if not alive(outer) then
        return nil
    end
    local ok, widget = pcall(function()
        local class = StaticFindObject(class_path)
        if not alive(class) then
            return nil
        end
        return StaticConstructObject(
            class,
            outer,
            0,
            0,
            0,
            alive(template) and template or nil,
            false,
            false,
            nil
        )
    end)
    return ok and alive(widget) and widget or nil
end

local function canvas_add(canvas, widget, x, y, width, height, z)
    if not alive(canvas) or not alive(widget) then
        return false
    end
    return pcall(function()
        local slot = canvas:AddChildToCanvas(widget)
        if not alive(slot) then
            error("canvas refused a child")
        end
        slot:SetAnchors({
            Minimum = { X = 0, Y = 0 },
            Maximum = { X = 0, Y = 0 },
        })
        slot:SetAlignment({ X = 0, Y = 0 })
        slot:SetPosition({ X = x, Y = y })
        slot:SetSize({ X = width, Y = height })
        slot:SetZOrder(z or 1)
    end)
end

local function set_text_style(text, template, font_size, alpha, justification)
    pcall(function()
        text:SetJustification(justification or 0)
        if alive(template) then
            text:SetFont(template.Font)
            text:SetColorAndOpacity(template.ColorAndOpacity)
            text:SetShadowColorAndOpacity(template.ShadowColorAndOpacity)
            text:SetShadowOffset(template.ShadowOffset)
        end
        local font = text.Font
        font.Size = font_size
        text:SetFont(font)
        if alpha ~= nil then
            text:SetColorAndOpacity({
                SpecifiedColor = { R = 1, G = 1, B = 1, A = alpha },
                ColorUseRule = 0,
            })
        end
        text:SetVisibility(4)
    end)
end

local function make_text(
    tree,
    template,
    value,
    font_size,
    alpha,
    justification
)
    local text = construct("/Script/UMG.TextBlock", tree)
    if not alive(text) then
        return nil
    end
    pcall(function()
        text:SetText(FText(tostring(value)))
    end)
    set_text_style(text, template, font_size, alpha, justification)
    return text
end

local function make_rule(tree, alpha)
    local image = construct("/Script/UMG.Image", tree)
    if not alive(image) then
        return nil
    end
    pcall(function()
        image:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = alpha or 0.18 })
        image:SetVisibility(4)
    end)
    return image
end

local function make_icon(tree, texture, alpha)
    if not alive(texture) then
        return nil
    end
    local size_ok, width, height = pcall(function()
        return texture:Blueprint_GetSizeX(), texture:Blueprint_GetSizeY()
    end)
    if not size_ok or tonumber(width) == nil or tonumber(height) == nil
        or tonumber(width) <= 0 or tonumber(height) <= 0
    then
        return nil
    end
    local image = construct("/Script/UMG.Image", tree)
    if not alive(image) then
        return nil
    end
    local ok = pcall(function()
        image:SetBrushFromTexture(texture, true)
        image:SetColorAndOpacity({
            R = 1,
            G = 1,
            B = 1,
            A = alpha or 1,
        })
        image:SetVisibility(4)
    end)
    return ok and image or nil
end

local function make_native_button(owner, action)
    if not alive(owner) then
        return nil
    end
    local ok, button = pcall(function()
        local library = StaticFindObject(WIDGET_LIBRARY)
        local class = state.button_class
        if not alive(library) or not alive(class) then
            return nil
        end
        return library:Create(owner, class, owner:GetOwningPlayer())
    end)
    if not ok or not alive(button) then
        return nil
    end
    pcall(function()
        button:SetText(FText(""))
        button:Setup(false)
    end)
    local key = object_address(button)
    if key == nil then
        pcall(function()
            button:RemoveFromParent()
        end)
        return nil
    end
    state.actions[key] = {
        ref = button,
        identity = full_name(button),
        panel_revision = state.panel_revision,
        action = action,
    }
    return button
end

local function set_native_button_interactive(button)
    if not alive(button) then
        return
    end
    -- Disabling either WBP_CommonButton or its CommonUI input target invokes
    -- a bright white disabled brush. Keep both render-enabled and enforce the
    -- disabled state in handle_action plus the gamepad focus list instead.
    pcall(function()
        button:SetIsEnabled(true)
    end)
    pcall(function()
        local input = button.WBP_PalInvisibleButton
        if alive(input) then
            input:SetIsEnabled(true)
        end
    end)
end

local function add_inactive_button_background(
    canvas,
    tree,
    x,
    y,
    width,
    height,
    highlighted
)
    if state.editor_mode == nil then
        return
    end
    local background = construct("/Script/UMG.Image", tree)
    if alive(background) then
        pcall(function()
            background:SetColorAndOpacity(highlighted == true and {
                R = 0.025,
                G = 0.22,
                B = 0.38,
                A = 0.94,
            } or {
                R = 0.055,
                G = 0.065,
                B = 0.075,
                A = 0.96,
            })
            background:SetVisibility(4)
        end)
        canvas_add(canvas, background, x, y, width, height, 3)
    end
end

local function make_editable_text(tree, value, hint, password)
    local template = password == true
        and state.password_input_template
        or state.join_input_template
    local input = construct("/Script/Pal.PalEditableTextBox", tree, template)
    if not alive(input) then
        input = construct("/Script/UMG.EditableTextBox", tree)
    end
    if not alive(input) then
        return nil
    end
    pcall(function()
        local style = input.WidgetStyle
        local transparent = {
            SpecifiedColor = { R = 1, G = 1, B = 1, A = 0 },
            ColorUseRule = 0,
        }
        local foreground = {
            SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 },
            ColorUseRule = 0,
        }
        style.BackgroundImageNormal.TintColor = transparent
        style.BackgroundImageHovered.TintColor = transparent
        style.BackgroundImageFocused.TintColor = transparent
        style.BackgroundImageReadOnly.TintColor = transparent
        style.BackgroundColor = transparent
        style.ForegroundColor = foreground
        style.FocusedForegroundColor = foreground
        input.WidgetStyle = style
    end)
    pcall(function()
        input:SetText(FText(tostring(value or "")))
        input:SetHintText(FText(tostring(hint or "")))
        input:SetIsPassword(password == true)
        input:SetIsReadOnly(false)
        input:SetIsEnabled(true)
        input:SetVisibility(0)
        input:SetForegroundColor({ R = 1, G = 1, B = 1, A = 1 })
    end)
    return input
end

local function make_input_surface(tree, value, hint, password, width, height)
    local surface = construct("/Script/UMG.CanvasPanel", tree)
    local input = make_editable_text(tree, value, hint, password)
    if not alive(surface) or not alive(input) then
        return nil, input
    end

    local background = construct("/Script/UMG.Image", tree)
    if alive(background) then
        pcall(function()
            background:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.5 })
            background:SetVisibility(4)
        end)
        canvas_add(surface, background, 0, 0, width, height, 1)
    end
    local borders = {
        { x = 0, y = 0, width = width, height = 1 },
        { x = 0, y = height - 1, width = width, height = 1 },
        { x = 0, y = 0, width = 1, height = height },
        { x = width - 1, y = 0, width = 1, height = height },
    }
    for _, border in ipairs(borders) do
        local rule = make_rule(tree, 0.5)
        if alive(rule) then
            canvas_add(
                surface,
                rule,
                border.x,
                border.y,
                border.width,
                border.height,
                2
            )
        end
    end

    local input_x = 12
    if password == true then
        local lock = make_icon(tree, state.lock_texture, 0.92)
        local lock_size = 22
        if alive(lock) then
            canvas_add(
                surface,
                lock,
                8,
                (height - lock_size) / 2,
                lock_size,
                lock_size,
                4
            )
            input_x = 38
        end
    end
    canvas_add(surface, input, input_x, 0, width - input_x - 10, height, 3)
    return surface, input
end

local function editable_value(input)
    if not alive(input) then
        return ""
    end
    local ok, value = pcall(function()
        return input:GetText()
    end)
    if not ok or value == nil then
        return ""
    end
    local converted_ok, converted = pcall(function()
        return value:ToString()
    end)
    if converted_ok and converted ~= nil then
        return tostring(converted)
    end
    local text_ok, result = pcall(tostring, value)
    return text_ok and result or ""
end

local function register_focus(widget, action)
    if not alive(widget) then
        return nil
    end
    state.focus_items[#state.focus_items + 1] = {
        ref = widget,
        action = action,
    }
    local index = #state.focus_items
    local wanted = state.restore_focus
    if type(wanted) == "table" and type(action) == "table"
        and wanted.kind == action.kind
        and wanted.index == action.index
    then
        state.focus_index = index
        state.restore_focus = nil
        state.focus_requested = true
    end
    return index
end

local function focus_at(index)
    if #state.focus_items == 0 then
        state.focus_index = nil
        return false
    end
    index = ((tonumber(index) or 1) - 1) % #state.focus_items + 1
    local item = state.focus_items[index]
    if not alive(item.ref) then
        return false
    end
    state.focus_index = index
    pcall(function()
        item.ref:SetUserFocus(state.controller)
    end)
    pcall(function()
        item.ref:SetKeyboardFocus()
    end)
    return true
end

local function make_style_probe(owner)
    if not alive(owner) then
        return nil, nil
    end
    local ok, button = pcall(function()
        local library = StaticFindObject(WIDGET_LIBRARY)
        local class = state.button_class
        if not alive(library) or not alive(class) then
            return nil
        end
        return library:Create(owner, class, owner:GetOwningPlayer())
    end)
    if not ok or not alive(button) then
        return nil, nil
    end
    local text_ok, text = pcall(function()
        return button.Text_Main
    end)
    return button, text_ok and alive(text) and text or nil
end

local function forget_panel()
    state.panel_revision = state.panel_revision + 1
    state.render_requested = false
    state.actions = {}
    if alive(state.panel) then
        pcall(function()
            state.panel:RemoveFromParent()
        end)
    end
    state.panel = nil
    state.refresh_button = nil
    state.refresh_icon = nil
    state.refresh_feedback_label = nil
    state.last_disclaimer_visible = nil
    state.editor_inputs = {}
    state.status_widgets = {}
    state.focus_items = {}
    state.focus_index = nil
end

local function discard_unattached_panel(panel)
    state.actions = {}
    if alive(panel) then
        pcall(function()
            panel:RemoveFromParent()
        end)
    end
end

local function disclaimer_is_visible()
    local ok, dialogs = pcall(FindAllOf, "WBP_ModDisclaimerDialog_C")
    if not ok or type(dialogs) ~= "table" then
        return false
    end
    for _, dialog in ipairs(dialogs) do
        if alive(dialog) then
            -- Some disclaimer-suppression mods leave the widget attached to
            -- the viewport and only collapse it. IsInViewport() alone would
            -- therefore hide Quick Connect forever.
            local visible_ok, visible = pcall(function()
                return dialog:IsVisible()
            end)
            local viewport_ok, in_viewport = pcall(function()
                return dialog:IsInViewport()
            end)
            if viewport_ok then
                if in_viewport == true and (not visible_ok or visible == true) then
                    return true
                end
            elseif visible_ok and visible == true then
                return true
            end
            if not viewport_ok and not visible_ok then
                local visibility_ok, visibility = pcall(function()
                    return dialog.Visibility
                end)
                if not visibility_ok or (visibility ~= 1 and visibility ~= 2) then
                    return true
                end
            end
        end
    end
    return false
end

local function apply_disclaimer_visibility()
    if not alive(state.panel) then
        return
    end
    local blocked = disclaimer_is_visible()
    if blocked == state.last_disclaimer_visible then
        return
    end
    state.last_disclaimer_visible = blocked
    pcall(function()
        state.panel:SetVisibility(blocked and 1 or 0)
    end)
end

local build_panel
local update_refresh_controls

local function request_panel_render(delay_ms)
    if not state.ready or not state.title_stable then
        return false
    end
    state.render_requested = true
    if state.render_scheduled then
        return
    end
    state.render_scheduled = true
    local scheduled = schedule_on_game_thread(
        delay_ms or 50,
        "Launch panel render",
        function()
            state.render_scheduled = false
            if not state.render_requested then
                return
            end
            state.render_requested = false
            if not alive(state.panel) then
                build_panel()
            end
        end
    )
    if not scheduled then
        state.render_scheduled = false
    end
end

local function schedule_asset_retry()
    if state.asset_retry_scheduled then
        return
    end
    state.asset_retry_scheduled = true
    local scheduled = schedule_on_game_thread(
        1000,
        "Launch panel asset retry",
        function()
            state.asset_retry_scheduled = false
            if not alive(state.panel)
                and main_menu_is_visible(state.title_widget)
                and state.dismissed_title_key ~= state.title_key
            then
                request_panel_render()
            end
        end
    )
    if not scheduled then
        state.asset_retry_scheduled = false
    end
end

local function input_key_down(key_name)
    if not alive(state.controller) then
        return false
    end
    local key = {
        KeyName = UEHelpers.FindOrAddFName(key_name),
    }
    local ok, pressed = pcall(function()
        return state.controller:IsInputKeyDown(key)
    end)
    return ok and pressed == true
end

local function shift_is_down()
    return input_key_down("LeftShift") or input_key_down("RightShift")
end

local function editor_values()
    return {
        address = editable_value(state.editor_inputs.address),
        name = editable_value(state.editor_inputs.name),
        password = editable_value(state.editor_inputs.password),
    }
end

local function rebuild_panel()
    forget_panel()
    state.build_failed_title_key = nil
    request_panel_render()
end

local function open_editor(mode, index)
    state.editor_mode = mode
    state.editor_index = index
    state.restore_focus = mode == "modify"
        and { kind = "modify_open", index = index }
        or { kind = "add_open" }
    if mode == "modify" and state.entries[index] ~= nil then
        local entry = state.entries[index]
        state.editor_draft = {
            address = entry.address or "",
            name = entry.name or "",
            password = entry.password or "",
        }
    else
        state.editor_draft = {
            address = "",
            name = "",
            password = "",
        }
    end
    rebuild_panel()
end

local function close_editor()
    state.editor_mode = nil
    state.editor_index = nil
    state.editor_draft = nil
    rebuild_panel()
end

local function begin_connection_action(callback, ...)
    state.connection_attempt_id = state.connection_attempt_id + 1
    local attempt_id = state.connection_attempt_id
    state.dismissed_title_key = state.title_key
    state.recovery_title_key = state.title_key
    state.recovery_saw_hidden = false
    forget_panel()
    local connect_ok, accepted = protected_call(
        "Launch panel connect action",
        callback,
        ...
    )
    if not connect_ok or accepted == false then
        state.connection_attempt_id = state.connection_attempt_id + 1
        state.dismissed_title_key = nil
        state.recovery_title_key = nil
        state.recovery_saw_hidden = false
        state.build_failed_title_key = nil
        request_panel_render()
        return false
    end
    schedule_on_game_thread(10000, "Failed connection panel recovery", function()
        if attempt_id ~= state.connection_attempt_id then
            return
        end
        state.dismissed_title_key = nil
        state.recovery_title_key = nil
        state.recovery_saw_hidden = false
        state.build_failed_title_key = nil
        if main_menu_is_visible(state.title_widget) then
            protected_call(
                "Launch panel connection failure callback",
                state.connection_failed
            )
            request_panel_render()
        end
    end)
    return true
end

local function handle_action(action)
    if type(action) ~= "table" then
        return
    end
    if state.editor_mode ~= nil
        and action.kind ~= "field"
        and action.kind ~= "editor_confirm"
        and action.kind ~= "editor_cancel"
    then
        return
    end
    if action.kind == "connect" then
        safe_log("Server row action received by the launch panel.")
        begin_connection_action(state.connect, action.index)
    elseif action.kind == "add_open" then
        open_editor("add")
    elseif action.kind == "modify_open" then
        open_editor("modify", action.index)
    elseif action.kind == "editor_cancel" then
        close_editor()
    elseif action.kind == "editor_confirm" then
        state.editor_draft = editor_values()
        if state.editor_mode == "modify" then
            local ok, accepted = protected_call(
                "Launch panel modify action",
                state.modify,
                state.editor_index,
                state.editor_draft
            )
            if ok and accepted ~= false then
                state.editor_mode = nil
                state.editor_index = nil
                state.editor_draft = nil
                rebuild_panel()
            end
        elseif state.editor_mode == "add" then
            begin_connection_action(state.add, state.editor_draft)
        end
    elseif action.kind == "refresh" then
        if not state.refreshing and state.editor_mode == nil then
            local force_sync = shift_is_down()
            state.refreshing = true
            state.refresh_feedback = "REFRESHING..."
            state.refresh_feedback_revision = state.refresh_feedback_revision + 1
            if type(update_refresh_controls) == "function" then
                update_refresh_controls()
            end
            local refresh_ok, accepted = protected_call(
                "Launch panel refresh action",
                state.refresh,
                force_sync
            )
            if not refresh_ok or accepted == false then
                state.refreshing = false
                state.refresh_feedback = "FAILED"
                state.refresh_feedback_revision = state.refresh_feedback_revision + 1
                if type(update_refresh_controls) == "function" then
                    update_refresh_controls()
                end
            end
        end
    elseif action.kind == "remove" and state.editor_mode == nil then
        protected_call("Launch panel remove action", state.remove, action.index)
    elseif action.kind == "field" then
        focus_at(state.focus_index or 1)
    end
end

local function arm_click_hook()
    if state.click_hook_armed then
        return true
    end
    state.click_hook_callback = state.click_hook_callback or function(context)
        local callback_ok, callback_error = pcall(function()
            local button_ok, button = pcall(function()
                return context:get()
            end)
            if not button_ok or not alive(button) then
                return
            end
            local key = object_address(button)
            local registration = key ~= nil and state.actions[key] or nil
            if registration == nil
                or registration.panel_revision ~= state.panel_revision
                or registration.identity ~= full_name(button)
                or registration.consumed == true
            then
                return
            end
            if registration.action.kind ~= "refresh"
                and registration.action.kind ~= "field"
            then
                -- Native delegates can occasionally report the same click more
                -- than once. One-shot actions are consumed before dispatch.
                registration.consumed = true
            end
            handle_action(registration.action)
        end)
        if not callback_ok then
            safe_log("Launch panel click hook failed safely: " .. tostring(callback_error))
        end
    end
    local ok, registration_result = pcall(
        RegisterHook,
        BUTTON_CLICK,
        state.click_hook_callback
    )
    if ok and registration_result ~= false then
        state.click_hook_armed = true
    else
        safe_log("Launch panel could not register its native row click hook.")
    end
    return state.click_hook_armed
end

local function gamepad_pressed(key_name)
    local down = input_key_down(key_name)
    local pressed = down and state.gamepad_down[key_name] ~= true
    state.gamepad_down[key_name] = down
    return pressed
end

local function sync_focus_index()
    for index, item in ipairs(state.focus_items) do
        if alive(item.ref) then
            local ok, focused = pcall(function()
                return item.ref:HasUserFocus(state.controller)
            end)
            if ok and focused == true then
                state.focus_index = index
                return
            end
        end
    end
end

local function poll_gamepad_input()
    if not alive(state.panel) or #state.focus_items == 0 then
        state.gamepad_down = {}
        return
    end
    sync_focus_index()
    local up = gamepad_pressed("Gamepad_DPad_Up")
    local left = gamepad_pressed("Gamepad_DPad_Left")
    local down = gamepad_pressed("Gamepad_DPad_Down")
    local right = gamepad_pressed("Gamepad_DPad_Right")
    local stick_up = gamepad_pressed("Gamepad_LeftStick_Up")
    local stick_left = gamepad_pressed("Gamepad_LeftStick_Left")
    local stick_down = gamepad_pressed("Gamepad_LeftStick_Down")
    local stick_right = gamepad_pressed("Gamepad_LeftStick_Right")
    local previous = up or left or stick_up or stick_left
    local next_item = down or right or stick_down or stick_right
    if previous then
        focus_at((state.focus_index or 2) - 1)
    elseif next_item then
        focus_at((state.focus_index or 0) + 1)
    end
    if gamepad_pressed("Gamepad_FaceButton_Right")
        and state.editor_mode ~= nil
    then
        handle_action({ kind = "editor_cancel" })
        return
    end
    if gamepad_pressed("Gamepad_FaceButton_Bottom") then
        local item = state.focus_items[state.focus_index or 0]
        if item ~= nil and item.action ~= nil
            and item.action.kind == "field"
        then
            focus_at(state.focus_index)
        end
    end
end

local function arm_title_tick_hook()
    if state.title_tick_hook_armed then
        return true
    end
    state.title_tick_callback = state.title_tick_callback or function(context)
        local callback_ok, callback_error = pcall(function()
            poll_gamepad_input()
            local title_ok, title_widget = pcall(function()
                return context:get()
            end)
            if not title_ok or not live_title_widget(title_widget) then
                return
            end
            local widget_key = object_address(title_widget)
            if widget_key == nil or widget_key ~= state.title_widget_key then
                return
            end
            local visible = main_menu_is_visible(title_widget)
            if state.title_menu_visible == visible then
                return
            end
            state.title_menu_visible = visible
            schedule_on_game_thread(1, "Title menu visibility transition", function()
                if widget_key ~= state.title_widget_key
                    or main_menu_is_visible(state.title_widget) ~= visible
                then
                    return
                end
                if visible then
                    state.connection_attempt_id = state.connection_attempt_id + 1
                    forget_panel()
                    state.dismissed_title_key = nil
                    state.recovery_title_key = nil
                    state.recovery_saw_hidden = false
                    state.build_failed_title_key = nil
                    request_panel_render()
                else
                    forget_panel()
                end
            end)
        end)
        if not callback_ok then
            safe_log("Title menu tick hook failed safely: " .. tostring(callback_error))
        end
    end
    local ok, registration_result = pcall(
        RegisterHook,
        TITLE_TICK,
        state.title_tick_callback
    )
    state.title_tick_hook_armed = ok and registration_result ~= false
    return state.title_tick_hook_armed
end

local function load_generated_class(package_name, asset_name, class_path)
    local existing_ok, existing = pcall(StaticFindObject, class_path)
    if existing_ok and alive(existing) then
        return existing
    end

    local ok, loaded = pcall(function()
        local helpers = StaticFindObject(
            "/Script/AssetRegistry.Default__AssetRegistryHelpers"
        )
        if not alive(helpers) then
            return nil
        end
        return helpers:GetAsset({
            PackageName = UEHelpers.FindOrAddFName(package_name),
            AssetName = UEHelpers.FindOrAddFName(asset_name),
        })
    end)
    return ok and alive(loaded) and loaded or nil
end

local function load_asset(package_name, asset_name, force_registry_load)
    local object_path = package_name .. "." .. asset_name
    if not force_registry_load then
        local existing_ok, existing = pcall(StaticFindObject, object_path)
        if existing_ok and alive(existing) then
            return existing
        end
    end
    local ok, loaded = pcall(function()
        local helpers = StaticFindObject(
            "/Script/AssetRegistry.Default__AssetRegistryHelpers"
        )
        if not alive(helpers) then
            return nil
        end
        return helpers:GetAsset({
            PackageName = UEHelpers.FindOrAddFName(package_name),
            AssetName = UEHelpers.FindOrAddFName(asset_name),
        })
    end)
    return ok and alive(loaded) and loaded or nil
end

local function ensure_assets_loaded()
    if not alive(state.panel_class) then
        state.panel_class = load_generated_class(
            PANEL_PACKAGE,
            PANEL_ASSET_NAME,
            PANEL_CLASS
        )
    end
    if not alive(state.button_class) then
        state.button_class = load_generated_class(
            BUTTON_PACKAGE,
            BUTTON_ASSET_NAME,
            BUTTON_CLASS
        )
    end
    if not alive(state.join_input_class) then
        state.join_input_class = load_generated_class(
            JOIN_INPUT_PACKAGE,
            JOIN_INPUT_ASSET_NAME,
            JOIN_INPUT_CLASS
        )
    end
    if not alive(state.password_input_class) then
        state.password_input_class = load_generated_class(
            PASSWORD_INPUT_PACKAGE,
            PASSWORD_INPUT_ASSET_NAME,
            PASSWORD_INPUT_CLASS
        )
    end
    local join_template_ok, join_template = pcall(
        StaticFindObject,
        JOIN_INPUT_TEMPLATE
    )
    state.join_input_template = join_template_ok and alive(join_template)
        and join_template
        or nil
    local password_template_ok, password_template = pcall(
        StaticFindObject,
        PASSWORD_INPUT_TEMPLATE
    )
    state.password_input_template = password_template_ok
        and alive(password_template)
        and password_template
        or nil
    -- Native texture wrappers can remain superficially valid after a title
    -- dialog/map transition while their brush resources have been released.
    -- Resolve them through the asset registry for every panel construction.
    state.refresh_texture = load_asset(
        REFRESH_TEXTURE_PACKAGE,
        REFRESH_TEXTURE_NAME,
        true
    )
    state.add_texture = load_asset(
        ADD_TEXTURE_PACKAGE,
        ADD_TEXTURE_NAME,
        true
    )
    state.edit_texture = load_asset(
        EDIT_TEXTURE_PACKAGE,
        EDIT_TEXTURE_NAME,
        true
    )
    state.remove_texture = load_asset(
        REMOVE_TEXTURE_PACKAGE,
        REMOVE_TEXTURE_NAME,
        true
    )
    state.lock_texture = load_asset(
        LOCK_TEXTURE_PACKAGE,
        LOCK_TEXTURE_NAME,
        true
    )
    return alive(state.panel_class) and alive(state.button_class)
end

local function status_for(entry)
    local ok, value = pcall(state.status, entry)
    if not ok or type(value) ~= "table" then
        return "—", "—"
    end
    local players = value.players ~= nil and tostring(value.players) or "—"
    local ping = value.ping ~= nil and tostring(value.ping) or "—"
    return players, ping
end

local function add_label(
    canvas,
    tree,
    template,
    value,
    x,
    y,
    width,
    height,
    font_size,
    alpha,
    justification,
    z
)
    local text = make_text(
        tree,
        template,
        value,
        font_size,
        alpha,
        justification
    )
    if alive(text) then
        canvas_add(canvas, text, x, y, width, height, z or 3)
    end
    return text
end

build_panel = function()
    if not state.ready
        or alive(state.panel)
        or not alive(state.controller)
        or not alive(state.title_widget)
        or not main_menu_is_visible(state.title_widget)
        or state.dismissed_title_key == state.title_key
        or state.build_failed_title_key == state.title_key
    then
        return
    end
    local build_title_key = state.title_key
    local build_title_widget = state.title_widget
    local build_context_revision = state.title_context_revision
    state.panel_revision = state.panel_revision + 1
    if not ensure_assets_loaded() then
        if state.asset_failure_logged_title_key ~= state.title_key then
            state.asset_failure_logged_title_key = state.title_key
            safe_log(
                "Cooked launch widget is temporarily unavailable after the "
                    .. "title transition; retrying its asset load."
            )
        end
        schedule_asset_retry()
        return
    end
    if not arm_click_hook() then
        return
    end

    local controller_ok, controller = pcall(function()
        return state.controller
    end)
    if not controller_ok or not alive(controller) then
        return
    end
    local panel_ok, panel = pcall(function()
        local library = StaticFindObject(WIDGET_LIBRARY)
        local class = state.panel_class
        if not alive(library) or not alive(class) then
            return nil
        end
        return library:Create(controller, class, controller)
    end)
    if not panel_ok or not alive(panel) then
        state.panel_class = nil
        if state.asset_failure_logged_title_key ~= state.title_key then
            state.asset_failure_logged_title_key = state.title_key
            safe_log(
                "Launch panel construction was deferred after the title "
                    .. "transition; reloading its cooked widget class."
            )
        end
        schedule_asset_retry()
        return
    end

    local tree_ok, tree = pcall(function()
        return panel.WidgetTree
    end)
    local slot_ok, named_slot = pcall(function()
        return panel.NamedSlot_91
    end)
    if not tree_ok or not slot_ok or not alive(tree) or not alive(named_slot) then
        discard_unattached_panel(panel)
        safe_log("Launch panel common-window content slot is unavailable.")
        schedule_asset_retry()
        return
    end

    local size_box = construct("/Script/UMG.SizeBox", tree)
    local canvas = construct("/Script/UMG.CanvasPanel", tree)
    if not alive(size_box) or not alive(canvas) then
        discard_unattached_panel(panel)
        safe_log("Launch panel could not construct its content canvas.")
        schedule_asset_retry()
        return
    end
    local panel_height = state.editor_mode ~= nil
        and EXPANDED_PANEL_HEIGHT
        or PANEL_HEIGHT
    local content_ok = pcall(function()
        size_box:SetWidthOverride(PANEL_WIDTH)
        size_box:SetHeightOverride(panel_height)
        size_box:AddChild(canvas)
        named_slot:SetContent(size_box)
    end)
    if not content_ok then
        discard_unattached_panel(panel)
        safe_log("Launch panel could not attach its content canvas.")
        schedule_asset_retry()
        return
    end

    state.actions = {}
    state.focus_items = {}
    state.focus_index = nil
    state.status_widgets = {}

    -- Copy typography from Palworld's native common-button text so every
    -- header and cell uses the same font, color, and shadow as the title UI.
    local style_probe, template = make_style_probe(panel)
    add_label(
        canvas,
        tree,
        template,
        "QUICK CONNECT",
        25,
        7,
        PANEL_WIDTH - 155,
        38,
        17,
        1.0,
        0,
        3
    )
    local add_button = make_native_button(panel, {
        kind = "add_open",
    })
    if alive(add_button) then
        canvas_add(canvas, add_button, PANEL_WIDTH - 126, 7, 44, 32, 2)
        set_native_button_interactive(add_button)
        add_inactive_button_background(
            canvas,
            tree,
            PANEL_WIDTH - 126,
            7,
            44,
            32,
            false
        )
        if state.editor_mode == nil then
            register_focus(add_button, { kind = "add_open" })
        end
        local add_icon = make_icon(tree, state.add_texture, 0.95)
        if alive(add_icon) then
            canvas_add(
                canvas,
                add_icon,
                PANEL_WIDTH - 126 + (44 - ADD_ICON_SIZE) / 2,
                7 + (32 - ADD_ICON_SIZE) / 2,
                ADD_ICON_SIZE,
                ADD_ICON_SIZE,
                4
            )
        end
    end
    local refresh_button = make_native_button(panel, {
        kind = "refresh",
    })
    if alive(refresh_button) then
        state.refresh_button = refresh_button
        canvas_add(
            canvas,
            refresh_button,
            PANEL_WIDTH - 74,
            7,
            52,
            32,
            2
        )
        set_native_button_interactive(refresh_button)
        add_inactive_button_background(
            canvas,
            tree,
            PANEL_WIDTH - 74,
            7,
            52,
            32,
            false
        )
        if state.editor_mode == nil then
            register_focus(refresh_button, { kind = "refresh" })
        end
        local refresh_icon = make_icon(
            tree,
            state.refresh_texture,
            state.refreshing and 0.45 or 1.0
        )
        if alive(refresh_icon) then
            state.refresh_icon = refresh_icon
            canvas_add(
                canvas,
                refresh_icon,
                PANEL_WIDTH - 74 + (52 - REFRESH_ICON_SIZE) / 2,
                7 + (32 - REFRESH_ICON_SIZE) / 2,
                REFRESH_ICON_SIZE,
                REFRESH_ICON_SIZE,
                4
            )
        else
            add_label(
                canvas,
                tree,
                template,
                "R",
                PANEL_WIDTH - 74,
                10,
                52,
                24,
                12,
                0.85,
                1,
                4
            )
        end
    end
    state.refresh_feedback_label = add_label(
        canvas,
        tree,
        template,
        state.refresh_feedback or "",
        PANEL_WIDTH - 242,
        11,
        108,
        22,
        10,
        0.68,
        1,
        4
    )
    local title_rule = make_rule(tree, 0.22)
    if alive(title_rule) then
        canvas_add(canvas, title_rule, 22, 44, PANEL_WIDTH - 44, 2, 2)
    end

    add_label(canvas, tree, template, "World Name", 60, 48, 190, 23, 12, 0.75, 0, 3)
    add_label(canvas, tree, template, "Players", 252, 48, 76, 23, 12, 0.75, 1, 3)
    add_label(canvas, tree, template, "Ping", 330, 48, 58, 23, 12, 0.75, 1, 3)
    local header_rule = make_rule(tree, 0.16)
    if alive(header_rule) then
        canvas_add(canvas, header_rule, 22, 72, PANEL_WIDTH - 44, 2, 2)
    end

    local row_canvas = canvas
    if #state.entries > 0 then
        local scroll_box = construct("/Script/UMG.ScrollBox", tree)
        local row_size_box = construct("/Script/UMG.SizeBox", tree)
        local scrolling_canvas = construct("/Script/UMG.CanvasPanel", tree)
        if not alive(scroll_box) or not alive(row_size_box) or not alive(scrolling_canvas) then
            discard_unattached_panel(panel)
            safe_log("Could not construct the server-list scroll container; will retry.")
            return
        end

        local content_height = #state.entries * ROW_HEIGHT + math.max(0, #state.entries - 1) * ROW_GAP
        local scroll_ok = pcall(function()
            row_size_box:SetWidthOverride(PANEL_WIDTH)
            row_size_box:SetHeightOverride(content_height)
            row_size_box:AddChild(scrolling_canvas)
            scroll_box:AddChild(row_size_box)
            scroll_box:SetClipping(1)
        end)
        pcall(function()
            scroll_box:SetAnimateWheelScrolling(true)
            scroll_box:SetWheelScrollMultiplier(ROW_HEIGHT + ROW_GAP)
            scroll_box:SetAlwaysShowScrollbar(#state.entries > MAX_ROWS)
        end)
        if not scroll_ok or not canvas_add(canvas, scroll_box, 0, ROW_START_Y, PANEL_WIDTH, ROW_VIEWPORT_HEIGHT, 2) then
            discard_unattached_panel(panel)
            safe_log("Could not attach the server-list scroll container; will retry.")
            return
        end
        row_canvas = scrolling_canvas
    end

    if #state.entries == 0 then
        add_label(
            canvas,
            tree,
            template,
            state.empty_message,
            30,
            112,
            PANEL_WIDTH - 60,
            34,
            15,
            0.8,
            1,
            3
        )
    else
        for index = 1, #state.entries do
            local entry = state.entries[index]
            local row_y = (index - 1) * (ROW_HEIGHT + ROW_GAP)
            local button = make_native_button(panel, {
                kind = "connect",
                index = index,
            })
            if alive(button) then
                canvas_add(
                    row_canvas,
                    button,
                    ROW_X,
                    row_y,
                    ROW_WIDTH,
                    ROW_HEIGHT,
                    2
                )
                set_native_button_interactive(button)
                add_inactive_button_background(
                    row_canvas,
                    tree,
                    ROW_X,
                    row_y,
                    ROW_WIDTH,
                    ROW_HEIGHT,
                    state.editor_mode == "modify"
                        and state.editor_index == index
                )
                if state.editor_mode == nil then
                    register_focus(button, { kind = "connect", index = index })
                end
            end

            local players, ping = status_for(entry)
            if entry.password_protected == true then
                local lock_icon = make_icon(tree, state.lock_texture, 0.92)
                if alive(lock_icon) then
                    canvas_add(
                        row_canvas,
                        lock_icon,
                        40 - LOCK_ICON_SIZE / 2,
                        row_y + (ROW_HEIGHT - LOCK_ICON_SIZE) / 2,
                        LOCK_ICON_SIZE,
                        LOCK_ICON_SIZE,
                        4
                    )
                else
                    add_label(
                        row_canvas,
                        tree,
                        template,
                        "P",
                        28,
                        row_y + 8,
                        24,
                        24,
                        11,
                        0.72,
                        1,
                        4
                    )
                end
            end
            local name_label = add_label(
                row_canvas,
                tree,
                template,
                entry.name,
                60,
                row_y + 7,
                178,
                28,
                15,
                1.0,
                0,
                4
            )
            if alive(name_label) then
                pcall(function()
                    name_label:SetClipping(1)
                end)
                pcall(function()
                    name_label:SetTextOverflowPolicy(1)
                end)
            end
            local players_label = add_label(
                row_canvas,
                tree,
                template,
                players,
                252,
                row_y + 7,
                76,
                28,
                15,
                1.0,
                1,
                4
            )
            local ping_label = add_label(
                row_canvas,
                tree,
                template,
                ping,
                330,
                row_y + 7,
                58,
                28,
                15,
                1.0,
                1,
                4
            )
            local ping_throbber = construct("/Script/UMG.CircularThrobber", tree)
            if alive(ping_throbber) then
                pcall(function()
                    ping_throbber:SetNumberOfPieces(8)
                    ping_throbber:SetPeriod(0.75)
                    ping_throbber:SetRadius(7)
                    ping_throbber:SetVisibility(state.refreshing and 4 or 1)
                end)
                canvas_add(
                    row_canvas,
                    ping_throbber,
                    348,
                    row_y + 10,
                    22,
                    22,
                    5
                )
            end
            if state.refreshing and alive(ping_label) then
                pcall(function()
                    ping_label:SetVisibility(1)
                end)
            end
            state.status_widgets[index] = {
                players = players_label,
                ping = ping_label,
                throbber = ping_throbber,
            }
            local edit_button = make_native_button(panel, {
                kind = "modify_open",
                index = index,
            })
            if alive(edit_button) then
                canvas_add(
                    row_canvas,
                    edit_button,
                    EDIT_X,
                    row_y,
                    EDIT_WIDTH,
                    ROW_HEIGHT,
                    2
                )
                set_native_button_interactive(edit_button)
                add_inactive_button_background(
                    row_canvas,
                    tree,
                    EDIT_X,
                    row_y,
                    EDIT_WIDTH,
                    ROW_HEIGHT,
                    false
                )
                if state.editor_mode == nil then
                    register_focus(edit_button, {
                        kind = "modify_open",
                        index = index,
                    })
                end
                local edit_icon = make_icon(tree, state.edit_texture, 0.92)
                if alive(edit_icon) then
                    canvas_add(
                        row_canvas,
                        edit_icon,
                        EDIT_X + (EDIT_WIDTH - EDIT_ICON_SIZE) / 2,
                        row_y + (ROW_HEIGHT - EDIT_ICON_SIZE) / 2,
                        EDIT_ICON_SIZE,
                        EDIT_ICON_SIZE,
                        6
                    )
                end
            end
            local remove_button = make_native_button(panel, {
                kind = "remove",
                index = index,
            })
            if alive(remove_button) then
                canvas_add(
                    row_canvas,
                    remove_button,
                    REMOVE_X,
                    row_y,
                    REMOVE_WIDTH,
                    ROW_HEIGHT,
                    2
                )
                set_native_button_interactive(remove_button)
                add_inactive_button_background(
                    row_canvas,
                    tree,
                    REMOVE_X,
                    row_y,
                    REMOVE_WIDTH,
                    ROW_HEIGHT,
                    false
                )
                if state.editor_mode == nil then
                    register_focus(remove_button, {
                        kind = "remove",
                        index = index,
                    })
                end
                local remove_icon = make_icon(tree, state.remove_texture, 0.92)
                if alive(remove_icon) then
                    canvas_add(
                        row_canvas,
                        remove_icon,
                        REMOVE_X + (REMOVE_WIDTH - REMOVE_ICON_SIZE) / 2,
                        row_y + (ROW_HEIGHT - REMOVE_ICON_SIZE) / 2,
                        REMOVE_ICON_SIZE,
                        REMOVE_ICON_SIZE,
                        6
                    )
                end
            end
        end
    end

    if state.editor_mode ~= nil then
        local draft = type(state.editor_draft) == "table"
            and state.editor_draft
            or {}
        local editor_y = ROW_START_Y + ROW_VIEWPORT_HEIGHT + 12
        local editor_rule = make_rule(tree, 0.2)
        if alive(editor_rule) then
            canvas_add(canvas, editor_rule, 22, editor_y, PANEL_WIDTH - 44, 2, 2)
        end
        add_label(
            canvas,
            tree,
            template,
            state.editor_mode == "add" and "ADD SERVER" or "MODIFY SERVER",
            22,
            editor_y + 7,
            PANEL_WIDTH - 44,
            24,
            13,
            0.9,
            0,
            3
        )
        local fields = {
            {
                key = "address",
                label = "ADDRESS",
                value = draft.address,
                hint = "IP address or hostname:port",
            },
            {
                key = "name",
                label = "SERVER NAME",
                value = draft.name,
                hint = "Server name",
            },
            {
                key = "password",
                label = "PASSWORD",
                value = draft.password,
                hint = "Optional",
                password = true,
            },
        }
        local first_field_index = nil
        local name_field_index = nil
        for field_index, field in ipairs(fields) do
            local label_y = editor_y + 36 + (field_index - 1) * 59
            add_label(
                canvas,
                tree,
                template,
                field.label,
                22,
                label_y,
                PANEL_WIDTH - 44,
                18,
                10,
                0.72,
                0,
                3
            )
            local field_width = PANEL_WIDTH - 44
            local field_height = 35
            local surface, input = make_input_surface(
                tree,
                field.value,
                field.hint,
                field.password == true,
                field_width,
                field_height
            )
            state.editor_inputs[field.key] = input
            if alive(surface) and alive(input) then
                canvas_add(
                    canvas,
                    surface,
                    22,
                    label_y + 17,
                    field_width,
                    field_height,
                    2
                )
                local focus_index = register_focus(input, {
                    kind = "field",
                    field = field.key,
                })
                first_field_index = first_field_index or focus_index
                if field.key == "name" then
                    name_field_index = focus_index
                end
            end
        end
        local primary = make_native_button(panel, {
            kind = "editor_confirm",
        })
        if alive(primary) then
            canvas_add(canvas, primary, 22, editor_y + 218, 220, 38, 2)
            register_focus(primary, { kind = "editor_confirm" })
            add_label(
                canvas,
                tree,
                template,
                state.editor_mode == "add" and "CONNECT" or "CONFIRM",
                22,
                editor_y + 224,
                220,
                26,
                14,
                1.0,
                1,
                4
            )
        end
        local cancel = make_native_button(panel, {
            kind = "editor_cancel",
        })
        if alive(cancel) then
            canvas_add(canvas, cancel, 258, editor_y + 218, 220, 38, 2)
            register_focus(cancel, { kind = "editor_cancel" })
            add_label(
                canvas,
                tree,
                template,
                "CANCEL",
                258,
                editor_y + 224,
                220,
                26,
                14,
                1.0,
                1,
                4
            )
        end
        state.focus_index = state.editor_mode == "modify"
            and name_field_index
            or first_field_index
    end

    local footer_y = panel_height - 66
    local footer_rule = make_rule(tree, 0.16)
    if alive(footer_rule) then
        canvas_add(canvas, footer_rule, 22, footer_y - 9, PANEL_WIDTH - 44, 2, 2)
    end
    add_label(
        canvas,
        tree,
        template,
        state.editor_mode ~= nil
            and "Use Confirm or Connect to continue."
            or "Successful joins are saved automatically.",
        25,
        footer_y,
        PANEL_WIDTH - 50,
        24,
        13,
        0.82,
        0,
        3
    )
    add_label(
        canvas,
        tree,
        template,
        state.editor_mode ~= nil
            and "Palworld handles connection and password errors."
            or "Use + to add, the pencil to edit, or trash to remove.",
        25,
        footer_y + 21,
        PANEL_WIDTH - 50,
        20,
        11,
        0.58,
        0,
        3
    )
    add_label(
        canvas,
        tree,
        template,
        state.editor_mode ~= nil
            and "Press controller Cancel to close this editor."
            or "Refresh updates status without renaming worlds.",
        25,
        footer_y + 38,
        PANEL_WIDTH - 50,
        20,
        11,
        0.58,
        0,
        3
    )

    if build_title_key ~= state.title_key
        or build_title_widget ~= state.title_widget
        or build_context_revision ~= state.title_context_revision
        or not live_title_widget(build_title_widget)
        or not main_menu_is_visible(build_title_widget)
    then
        discard_unattached_panel(panel)
        request_panel_render()
        return
    end

    local shown, show_error = pcall(function()
        local title_tree = build_title_widget.WidgetTree
        if not alive(title_tree) then
            error(
                "title widget tree is unavailable on "
                    .. full_name(build_title_widget)
            )
        end
        local title_canvas = title_tree.RootWidget
        if not alive(title_canvas) then
            error("title root canvas is unavailable")
        end
        local slot = title_canvas:AddChildToCanvas(panel)
        if not alive(slot) then
            error("title canvas refused the panel")
        end
        panel:SetVisibility(0)
        panel:SetRenderOpacity(1.0)
        panel:SetIsEnabled(true)
        slot:SetAnchors({
            Minimum = { X = 1, Y = 0.5 },
            Maximum = { X = 1, Y = 0.5 },
        })
        slot:SetAlignment({ X = 1, Y = 0.5 })
        slot:SetPosition({
            X = -55,
            Y = 25 + (panel_height - PANEL_HEIGHT) / 2,
        })
        slot:SetSize({ X = PANEL_WIDTH, Y = panel_height })
        slot:SetZOrder(25)
    end)
    if not shown then
        state.build_failed_title_key = state.title_key
        discard_unattached_panel(panel)
        safe_log(
            "Launch panel could not attach to the title menu canvas: "
                .. tostring(show_error)
        )
        return
    end
    state.panel = panel
    state.asset_failure_logged_title_key = nil
    state.last_disclaimer_visible = nil
    apply_disclaimer_visibility()
    if state.focus_index ~= nil
        and (state.editor_mode ~= nil or state.focus_requested)
    then
        schedule_on_game_thread(1, "Launch panel editor focus", function()
            focus_at(state.focus_index)
        end)
        state.focus_requested = false
    end
    -- Keep the style probe alive through construction. It is intentionally
    -- never attached to the widget tree and can be collected afterward.
    style_probe = nil
    if state.panel_logged_title_key ~= state.title_key then
        state.panel_logged_title_key = state.title_key
        safe_log("Quick Connect launch panel available.")
    end
end

local function adopt_title_world(world, controller, title_widget)
    if not alive(world) or not alive(controller) then
        return
    end
    local world_key = object_address(world)
    if world_key == nil then
        return
    end
    local widget_key = live_title_widget(title_widget)
        and object_address(title_widget)
        or nil
    local world_changed = state.title_key ~= world_key
    local widget_changed = widget_key ~= nil
        and state.title_widget_key ~= widget_key

    if world_changed or widget_changed then
        forget_panel()
        arm_title_tick_hook()
        state.title_context_revision = state.title_context_revision + 1
        local revision = state.title_context_revision
        state.title_stable = false
        state.controller = controller
        state.title_key = world_key
        if widget_key ~= nil then
            state.title_widget = title_widget
            state.title_widget_key = widget_key
        end
        state.dismissed_title_key = nil
        state.recovery_title_key = nil
        state.recovery_saw_hidden = false
        state.title_menu_visible = nil
        state.build_failed_title_key = nil
        state.asset_failure_logged_title_key = nil
        -- Palworld can replace its first title-menu instance roughly one second
        -- after map load. Debounce long enough to adopt only the final widget so
        -- startup cannot briefly build two Quick Connect panels.
        schedule_on_game_thread(1500, "Title world adoption", function()
            if alive(state.controller)
                and state.title_key == world_key
                and state.title_widget_key == widget_key
                and state.title_context_revision == revision
                and main_menu_is_visible(state.title_widget)
            then
                state.title_stable = true
                schedule_on_game_thread(5000, "Stable title metadata readiness", function()
                    if state.title_key == world_key
                        and state.title_widget_key == widget_key
                        and state.title_context_revision == revision
                        and main_menu_is_visible(state.title_widget)
                        and state.title_available_notified_key ~= world_key
                    then
                        state.title_available_notified_key = world_key
                        protected_call(
                            "Launch panel title available callback",
                            state.title_available
                        )
                    end
                end)
                request_panel_render()
            end
        end)
    else
        state.controller = controller
        if widget_key ~= nil then
            state.title_widget = title_widget
        end
    end
end

local function find_title_widget()
    if live_title_widget(state.title_widget) then
        return state.title_widget
    end
    local ok, widgets = pcall(FindAllOf, TITLE_SHORT_CLASS)
    if ok and type(widgets) == "table" then
        local fallback = nil
        for _, widget in ipairs(widgets) do
            if live_title_widget(widget) then
                fallback = fallback or widget
                local viewport_ok, in_viewport = pcall(function()
                    return widget:IsInViewport()
                end)
                if viewport_ok and in_viewport == true then
                    state.title_widget = widget
                    return widget
                end
            end
        end
        if alive(fallback) then
            state.title_widget = fallback
            return fallback
        end
    end
    return nil
end

local function find_title_context()
    local world_ok, world = pcall(UEHelpers.GetWorld)
    if not world_ok or not alive(world) then
        return nil, nil
    end
    local name_ok, name = pcall(function()
        return tostring(world:GetFullName())
    end)
    if not name_ok
        or name:find("/Game/Pal/Maps/Title/PL_Title", 1, true) == nil
    then
        return nil, nil
    end
    local controller_ok, controller = pcall(UEHelpers.GetPlayerController)
    if not controller_ok or not alive(controller) then
        return nil, nil
    end
    return world, controller, find_title_widget()
end

local function lifecycle_step()
    local world, controller, title_widget = find_title_context()
    if alive(world) and alive(controller) then
        state.in_title_context = true
        adopt_title_world(world, controller, title_widget)
        arm_title_tick_hook()
        local menu_visible = main_menu_is_visible(state.title_widget)
        if state.recovery_title_key == state.title_key
            and live_title_widget(state.title_widget)
        then
            if not menu_visible then
                state.recovery_saw_hidden = true
            elseif state.recovery_saw_hidden then
                state.dismissed_title_key = nil
                state.recovery_title_key = nil
                state.recovery_saw_hidden = false
                protected_call(
                    "Launch panel connection failure callback",
                    state.connection_failed
                )
            end
        end
        if menu_visible and state.ready and state.title_stable then
            if not alive(state.panel) then
                request_panel_render()
            else
                apply_disclaimer_visibility()
            end
        elseif alive(state.panel) then
            forget_panel()
        end
        return TITLE_POLL_MS
    end

    if state.in_title_context
        or state.controller ~= nil
        or state.title_widget ~= nil
        or state.title_key ~= nil
    then
        forget_panel()
        state.controller = nil
        state.title_widget = nil
        state.title_widget_key = nil
        state.title_menu_visible = nil
        state.title_context_revision = state.title_context_revision + 1
        state.title_stable = false
        state.title_key = nil
        state.dismissed_title_key = nil
        state.recovery_title_key = nil
        state.recovery_saw_hidden = false
        state.connection_attempt_id = state.connection_attempt_id + 1
        state.editor_mode = nil
        state.editor_index = nil
        state.editor_draft = nil
        state.restore_focus = nil
        state.focus_requested = false
    end
    state.in_title_context = false
    -- Title-widget creation notifications restart the lifecycle when Palworld
    -- returns to PL_Title. Keep no timer/callback chain alive during gameplay.
    return nil
end

local function lifecycle_poll()
    state.lifecycle_polling = true
    local generation = state.generation
    local queued, queue_error = pcall(ExecuteInGameThread, function()
        if not state.started or generation ~= state.generation then
            state.lifecycle_polling = false
            return
        end
        local step_ok, next_delay = pcall(lifecycle_step)
        if not step_ok then
            safe_log("Launch panel lifecycle poll failed safely: " .. tostring(next_delay))
            state.lifecycle_polling = false
            return
        end
        if tonumber(next_delay) ~= nil then
            if not schedule(next_delay, "Launch panel lifecycle poll", lifecycle_poll) then
                state.lifecycle_polling = false
            end
        else
            state.lifecycle_polling = false
        end
    end)
    if not queued then
        state.lifecycle_polling = false
        safe_log("Launch panel lifecycle poll could not enter the game thread: " .. tostring(queue_error))
    end
end

function LaunchUI.start(options)
    options = type(options) == "table" and options or {}
    if state.started then
        safe_log("Duplicate launch panel start request ignored.")
        request_panel_render()
        return false
    end

    state.entries = type(options.entries) == "table" and options.entries or {}
    state.connect = type(options.connect) == "function" and options.connect or function() end
    state.status = type(options.status) == "function" and options.status or function()
        return nil
    end
    state.refresh = type(options.refresh) == "function" and options.refresh or function() end
    state.remove = type(options.remove) == "function" and options.remove or function() end
    state.modify = type(options.modify) == "function" and options.modify or function() end
    state.add = type(options.add) == "function" and options.add or function() end
    state.connection_failed = type(options.connection_failed) == "function"
        and options.connection_failed
        or function() end
    state.title_available = type(options.title_available) == "function"
        and options.title_available
        or function() end
    state.log = type(options.log) == "function" and options.log or function() end
    state.empty_message = type(options.empty_message) == "string"
        and options.empty_message
        or "No dedicated servers configured"
    state.ready = options.ready ~= false

    state.generation = state.generation + 1
    state.started = true

    if not state.title_notification_armed then
        state.title_notification_callback = state.title_notification_callback
            or function(title)
                local callback_ok, callback_error = pcall(function()
                    local world, controller = find_title_context()
                    if alive(world) and alive(controller) then
                        adopt_title_world(world, controller, title)
                        if not state.lifecycle_polling then
                            lifecycle_poll()
                        end
                    end
                end)
                if not callback_ok then
                    safe_log(
                        "Launch panel title notification failed safely: "
                            .. tostring(callback_error)
                    )
                end
            end
        local title_ok, title_error = pcall(
            NotifyOnNewObject,
            TITLE_CLASS,
            state.title_notification_callback
        )
        state.title_notification_armed = title_ok
        if not title_ok then
            safe_log("Launch panel title notification failed: " .. tostring(title_error))
        end
    end

    if not state.disclaimer_notification_armed then
        state.disclaimer_notification_callback = state.disclaimer_notification_callback
            or function()
                local callback_ok, callback_error = pcall(
                    apply_disclaimer_visibility
                )
                if not callback_ok then
                    safe_log(
                        "Launch panel disclaimer notification failed safely: "
                            .. tostring(callback_error)
                    )
                end
            end
        local disclaimer_ok, disclaimer_error = pcall(
            NotifyOnNewObject,
            DISCLAIMER_CLASS,
            state.disclaimer_notification_callback
        )
        state.disclaimer_notification_armed = disclaimer_ok
        if not disclaimer_ok then
            safe_log(
                "Launch panel disclaimer notification failed: "
                    .. tostring(disclaimer_error)
            )
        end
    end

    lifecycle_poll()
    safe_log("Native non-modal launch panel armed.")
    return true
end

function LaunchUI.set_entries(new_entries, empty_message)
    run_on_game_thread("Launch panel entry update", function()
        state.entries = type(new_entries) == "table" and new_entries or {}
        state.ready = true
        state.refreshing = false
        if type(empty_message) == "string" then
            state.empty_message = empty_message
        end
        forget_panel()
        state.dismissed_title_key = nil
        state.build_failed_title_key = nil
        request_panel_render()
    end)
end

local function update_status_widgets()
    for index, widgets in pairs(state.status_widgets) do
        local entry = state.entries[index]
        if type(widgets) == "table" and type(entry) == "table" then
            local players, ping = status_for(entry)
            if alive(widgets.players) then
                pcall(function()
                    widgets.players:SetText(FText(players))
                end)
            end
            if alive(widgets.ping) then
                pcall(function()
                    widgets.ping:SetText(FText(ping))
                    widgets.ping:SetVisibility(state.refreshing and 1 or 4)
                end)
            end
            if alive(widgets.throbber) then
                pcall(function()
                    widgets.throbber:SetVisibility(state.refreshing and 4 or 1)
                end)
            end
        end
    end
end

function LaunchUI.set_statuses(new_entries)
    run_on_game_thread("Launch panel status update", function()
        state.entries = type(new_entries) == "table" and new_entries or {}
        update_status_widgets()
    end)
end

function LaunchUI.restore_after_failed_connect()
    run_on_game_thread("Failed connection panel restore", function()
        protected_call(
            "Launch panel connection failure callback",
            state.connection_failed
        )
        state.connection_attempt_id = state.connection_attempt_id + 1
        state.dismissed_title_key = nil
        state.recovery_title_key = nil
        state.recovery_saw_hidden = false
        state.build_failed_title_key = nil
        request_panel_render()
    end)
end

update_refresh_controls = function()
    update_status_widgets()
    if alive(state.refresh_icon) then
        pcall(function()
            state.refresh_icon:SetRenderOpacity(state.refreshing and 0.45 or 1.0)
        end)
    end
    if alive(state.refresh_feedback_label) then
        pcall(function()
            state.refresh_feedback_label:SetText(FText(state.refresh_feedback or ""))
        end)
    end
end

function LaunchUI.set_refreshing(refreshing)
    run_on_game_thread("Launch panel refresh state update", function()
        local value = refreshing == true
        if state.refreshing == value then
            update_refresh_controls()
            return
        end
        state.refreshing = value
        state.refresh_feedback = value and "REFRESHING..." or state.refresh_feedback
        state.refresh_feedback_revision = state.refresh_feedback_revision + 1
        update_refresh_controls()
    end)
end

function LaunchUI.show_refresh_result(succeeded, forced)
    run_on_game_thread("Launch panel refresh result", function()
        state.refreshing = false
        state.refresh_feedback = succeeded == true
            and (forced == true and "SYNCED" or "UPDATED")
            or "FAILED"
        local feedback = state.refresh_feedback
        state.refresh_feedback_revision = state.refresh_feedback_revision + 1
        local revision = state.refresh_feedback_revision
        update_refresh_controls()
        schedule_on_game_thread(2500, "Launch panel refresh feedback clear", function()
            if state.refresh_feedback_revision ~= revision
                or state.refresh_feedback ~= feedback
            then
                return
            end
            state.refresh_feedback = nil
            update_refresh_controls()
        end)
    end)
end

return LaunchUI
