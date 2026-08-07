#include <Windows.h>
#include <Xinput.h>

#include <array>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace
{
using XInputGetStateFn = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);
using GetRawInputDataFn = UINT(WINAPI*)(HRAWINPUT, UINT, LPVOID, PUINT, UINT);
using ExecuteLuaInModFn = const char* (*)(const char*, const char*, char*);

XInputGetStateFn g_original_get_state{};
GetRawInputDataFn g_original_get_raw_input_data{};
ExecuteLuaInModFn g_execute_lua{};
std::filesystem::path g_mode_path;
std::array<WORD, XUSER_MAX_COUNT> g_previous_buttons{};
std::array<bool, XUSER_MAX_COUNT> g_previous_left_trigger{};
std::array<DWORD, XUSER_MAX_COUNT> g_previous_packets{};
std::array<bool, XUSER_MAX_COUNT> g_packet_initialized{};

enum class InputMode : std::uint8_t
{
    Hidden,
    Unfrozen,
    Frozen,
};

std::array<InputMode, XUSER_MAX_COUNT> g_active_modes{};

enum class ActiveDevice : std::uint8_t
{
    Unknown,
    KeyboardMouse,
    Gamepad,
};

ActiveDevice g_active_device{ActiveDevice::Unknown};

InputMode read_mode()
{
    FILE* file{};
    if (_wfopen_s(&file, g_mode_path.c_str(), L"rb") != 0 || !file)
    {
        return InputMode::Hidden;
    }
    char value[16]{};
    const auto count = std::fread(value, 1, sizeof(value) - 1, file);
    std::fclose(file);
    const std::string_view mode{value, count};
    if (mode == "frozen") return InputMode::Frozen;
    if (mode == "unfrozen") return InputMode::Unfrozen;
    return InputMode::Hidden;
}

void dispatch_physical(int index)
{
    if (!g_execute_lua) return;
    char script[128]{};
    std::snprintf(script, sizeof(script),
                  "if PerfectPlacementNativeGamepadPhysical then "
                  "PerfectPlacementNativeGamepadPhysical(%d) end", index);
    char error[512]{};
    g_execute_lua("PerfectPlacement", script, error);
}

void notify_input_device(ActiveDevice device)
{
    if (!g_execute_lua || device == g_active_device) return;
    g_active_device = device;
    // Device changes outside an active construction preview are irrelevant to
    // PP and must not re-enter its Lua state during splash/title teardown.
    if (read_mode() == InputMode::Hidden) return;
    const char* script = device == ActiveDevice::Gamepad
        ? "if PerfectPlacementNativeInputDevice then "
          "PerfectPlacementNativeInputDevice(true) end"
        : "if PerfectPlacementNativeInputDevice then "
          "PerfectPlacementNativeInputDevice(false) end";
    char error[512]{};
    g_execute_lua("PerfectPlacement", script, error);
}

int frozen_dpad_up_index(const XINPUT_GAMEPAD& pad)
{
    constexpr BYTE trigger_threshold = 30;
    const bool left = pad.bLeftTrigger > trigger_threshold;
    const bool right = pad.bRightTrigger > trigger_threshold;
    if (left && right) return 14;
    if (left) return 6;
    if (right) return 10;
    return 2;
}

int dpad_direction_offset(WORD pressed)
{
    if (pressed & XINPUT_GAMEPAD_DPAD_UP) return 0;
    if (pressed & XINPUT_GAMEPAD_DPAD_DOWN) return 1;
    if (pressed & XINPUT_GAMEPAD_DPAD_LEFT) return 2;
    if (pressed & XINPUT_GAMEPAD_DPAD_RIGHT) return 3;
    return -1;
}

DWORD WINAPI intercepted_get_state(DWORD user_index, XINPUT_STATE* state)
{
    const DWORD result = g_original_get_state(user_index, state);
    if (result != ERROR_SUCCESS || !state || user_index >= XUSER_MAX_COUNT)
    {
        return result;
    }

    auto& pad = state->Gamepad;
    if (g_packet_initialized[user_index])
    {
        if (state->dwPacketNumber != g_previous_packets[user_index])
            notify_input_device(ActiveDevice::Gamepad);
    }
    else
    {
        g_packet_initialized[user_index] = true;
    }
    g_previous_packets[user_index] = state->dwPacketNumber;
    const WORD physical = pad.wButtons;
    const WORD previous = g_previous_buttons[user_index];
    g_previous_buttons[user_index] = physical;
    const WORD pressed = static_cast<WORD>(physical & ~previous);
    constexpr BYTE trigger_threshold = 30;
    const bool left_trigger = pad.bLeftTrigger > trigger_threshold;
    const bool left_trigger_pressed = left_trigger &&
        !g_previous_left_trigger[user_index];
    g_previous_left_trigger[user_index] = left_trigger;
    constexpr WORD dpad = XINPUT_GAMEPAD_DPAD_UP |
        XINPUT_GAMEPAD_DPAD_DOWN |
        XINPUT_GAMEPAD_DPAD_LEFT |
        XINPUT_GAMEPAD_DPAD_RIGHT;
    constexpr WORD intercepted = dpad |
        XINPUT_GAMEPAD_LEFT_SHOULDER |
        XINPUT_GAMEPAD_RIGHT_SHOULDER;
    if ((pressed & intercepted) || left_trigger_pressed)
    {
        // Mode changes are written by Lua. Read once on a relevant physical
        // edge; held buttons use the cached value, so no input-loop or disk
        // polling is introduced.
        g_active_modes[user_index] = read_mode();
    }
    else if ((physical & intercepted) == 0 && !left_trigger)
    {
        g_active_modes[user_index] = InputMode::Hidden;
    }
    const InputMode mode = g_active_modes[user_index];

    if (mode == InputMode::Frozen)
    {
        const int direction = dpad_direction_offset(pressed);
        if (direction >= 0 && left_trigger)
        {
            const bool right_trigger = pad.bRightTrigger > trigger_threshold;
            dispatch_physical((right_trigger ? 14 : 6) + direction);
        }
        else if (pressed & XINPUT_GAMEPAD_DPAD_UP)
        {
            dispatch_physical(frozen_dpad_up_index(pad));
        }
        if (pressed & XINPUT_GAMEPAD_LEFT_SHOULDER)
            dispatch_physical(18);
        if (pressed & XINPUT_GAMEPAD_RIGHT_SHOULDER)
            dispatch_physical(19);
        WORD buttons_to_mask = XINPUT_GAMEPAD_DPAD_UP |
            XINPUT_GAMEPAD_LEFT_SHOULDER |
            XINPUT_GAMEPAD_RIGHT_SHOULDER;
        if (left_trigger) buttons_to_mask |= dpad;
        pad.wButtons = static_cast<WORD>(pad.wButtons & ~buttons_to_mask);
        // Preserve LT for chord detection above, but hide it from Palworld's
        // camera zoom while Perfect Placement owns the frozen preview.
        pad.bLeftTrigger = 0;
    }
    else if (mode == InputMode::Unfrozen &&
             (physical & XINPUT_GAMEPAD_LEFT_THUMB))
    {
        if (pressed & XINPUT_GAMEPAD_DPAD_UP)
            dispatch_physical(22);
        pad.wButtons = static_cast<WORD>(pad.wButtons & ~XINPUT_GAMEPAD_DPAD_UP);
    }

    return result;
}

UINT WINAPI intercepted_get_raw_input_data(
    HRAWINPUT raw_input,
    UINT command,
    LPVOID data,
    PUINT size,
    UINT header_size)
{
    const UINT result = g_original_get_raw_input_data(
        raw_input, command, data, size, header_size);
    if (result != static_cast<UINT>(-1) && command == RID_INPUT && data &&
        result >= sizeof(RAWINPUTHEADER))
    {
        const auto* input = static_cast<const RAWINPUT*>(data);
        if (input->header.dwType == RIM_TYPEKEYBOARD ||
            input->header.dwType == RIM_TYPEMOUSE)
        {
            notify_input_device(ActiveDevice::KeyboardMouse);
        }
    }
    return result;
}

bool hook_xinput_import()
{
    auto* base = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr));
    if (!base) return false;
    const auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    const auto& directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    auto* descriptor = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + directory.VirtualAddress);

    for (; descriptor->Name; ++descriptor)
    {
        const char* module_name = reinterpret_cast<const char*>(base + descriptor->Name);
        if (_stricmp(module_name, "XINPUT1_3.dll") != 0) continue;
        auto* thunk = reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->FirstThunk);
        auto* original = descriptor->OriginalFirstThunk
            ? reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->OriginalFirstThunk)
            : thunk;
        for (; original->u1.AddressOfData; ++original, ++thunk)
        {
            // Palworld imports XInputGetState from XInput 1.3 by ordinal 2.
            if (!IMAGE_SNAP_BY_ORDINAL(original->u1.Ordinal) ||
                IMAGE_ORDINAL(original->u1.Ordinal) != 2) continue;
            DWORD old_protect{};
            if (!VirtualProtect(&thunk->u1.Function, sizeof(void*),
                                PAGE_READWRITE, &old_protect)) return false;
            g_original_get_state = reinterpret_cast<XInputGetStateFn>(thunk->u1.Function);
            thunk->u1.Function = reinterpret_cast<ULONGLONG>(&intercepted_get_state);
            DWORD ignored{};
            VirtualProtect(&thunk->u1.Function, sizeof(void*), old_protect, &ignored);
            FlushInstructionCache(GetCurrentProcess(), &thunk->u1.Function, sizeof(void*));
            return true;
        }
    }
    return false;
}

bool hook_raw_input_import()
{
    auto* base = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr));
    if (!base) return false;
    const auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    const auto& directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    auto* descriptor = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + directory.VirtualAddress);
    for (; descriptor->Name; ++descriptor)
    {
        const char* module_name = reinterpret_cast<const char*>(base + descriptor->Name);
        if (_stricmp(module_name, "USER32.dll") != 0) continue;
        auto* thunk = reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->FirstThunk);
        auto* original = descriptor->OriginalFirstThunk
            ? reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->OriginalFirstThunk)
            : thunk;
        for (; original->u1.AddressOfData; ++original, ++thunk)
        {
            if (IMAGE_SNAP_BY_ORDINAL(original->u1.Ordinal)) continue;
            const auto* import = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
                base + original->u1.AddressOfData);
            if (std::strcmp(reinterpret_cast<const char*>(import->Name),
                            "GetRawInputData") != 0) continue;
            DWORD old_protect{};
            if (!VirtualProtect(&thunk->u1.Function, sizeof(void*),
                                PAGE_READWRITE, &old_protect)) return false;
            g_original_get_raw_input_data =
                reinterpret_cast<GetRawInputDataFn>(thunk->u1.Function);
            thunk->u1.Function =
                reinterpret_cast<ULONGLONG>(&intercepted_get_raw_input_data);
            DWORD ignored{};
            VirtualProtect(&thunk->u1.Function, sizeof(void*), old_protect, &ignored);
            FlushInstructionCache(GetCurrentProcess(), &thunk->u1.Function, sizeof(void*));
            return true;
        }
    }
    return false;
}

void unhook_xinput_import()
{
    if (!g_original_get_state) return;
    auto* base = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr));
    const auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    const auto& directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    auto* descriptor = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + directory.VirtualAddress);
    for (; descriptor->Name; ++descriptor)
    {
        const char* module_name = reinterpret_cast<const char*>(base + descriptor->Name);
        if (_stricmp(module_name, "XINPUT1_3.dll") != 0) continue;
        auto* thunk = reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->FirstThunk);
        auto* original = descriptor->OriginalFirstThunk
            ? reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->OriginalFirstThunk)
            : thunk;
        for (; original->u1.AddressOfData; ++original, ++thunk)
        {
            if (!IMAGE_SNAP_BY_ORDINAL(original->u1.Ordinal) ||
                IMAGE_ORDINAL(original->u1.Ordinal) != 2) continue;
            DWORD old_protect{};
            if (VirtualProtect(&thunk->u1.Function, sizeof(void*), PAGE_READWRITE, &old_protect))
            {
                thunk->u1.Function = reinterpret_cast<ULONGLONG>(g_original_get_state);
                DWORD ignored{};
                VirtualProtect(&thunk->u1.Function, sizeof(void*), old_protect, &ignored);
            }
            return;
        }
    }
}

void unhook_raw_input_import()
{
    if (!g_original_get_raw_input_data) return;
    auto* base = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr));
    const auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    const auto& directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    auto* descriptor = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + directory.VirtualAddress);
    for (; descriptor->Name; ++descriptor)
    {
        const char* module_name = reinterpret_cast<const char*>(base + descriptor->Name);
        if (_stricmp(module_name, "USER32.dll") != 0) continue;
        auto* thunk = reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->FirstThunk);
        auto* original = descriptor->OriginalFirstThunk
            ? reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->OriginalFirstThunk)
            : thunk;
        for (; original->u1.AddressOfData; ++original, ++thunk)
        {
            if (IMAGE_SNAP_BY_ORDINAL(original->u1.Ordinal)) continue;
            const auto* import = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
                base + original->u1.AddressOfData);
            if (std::strcmp(reinterpret_cast<const char*>(import->Name),
                            "GetRawInputData") != 0) continue;
            DWORD old_protect{};
            if (VirtualProtect(&thunk->u1.Function, sizeof(void*),
                               PAGE_READWRITE, &old_protect))
            {
                thunk->u1.Function = reinterpret_cast<ULONGLONG>(
                    g_original_get_raw_input_data);
                DWORD ignored{};
                VirtualProtect(&thunk->u1.Function, sizeof(void*),
                               old_protect, &ignored);
            }
            return;
        }
    }
}

// UE4SS only requires a lifecycle-compatible vtable from C++ mods. This small
// adapter deliberately uses no private UE4SS SDK types or allocations.
struct UserModAdapter
{
    virtual ~UserModAdapter() = default;
    virtual void on_update() {}
    virtual void on_unreal_init() {}
    virtual void on_ui_init() {}
    virtual void on_program_start() {}
    virtual void on_lua_start(std::wstring_view, void*, void*, void*, std::vector<void*>&) {}
    virtual void on_lua_start(void*, void*, void*, std::vector<void*>&) {}
    virtual void on_lua_stop(std::wstring_view, void*, void*, void*, std::vector<void*>&) {}
    virtual void on_lua_stop(void*, void*, void*, std::vector<void*>&) {}
    virtual void on_dll_load(std::wstring_view) {}
    virtual void render_tab() {}
    virtual void on_lua_start(std::wstring_view, void*, void*, void*, void*) {}
    virtual void on_lua_start(void*, void*, void*, void*) {}
    virtual void on_lua_stop(std::wstring_view, void*, void*, void*, void*) {}
    virtual void on_lua_stop(void*, void*, void*, void*) {}
    virtual void on_cpp_mods_loaded() {}
};
}

extern "C" __declspec(dllexport) UserModAdapter* start_mod()
{
    HMODULE self{};
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                       GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&start_mod), &self);
    wchar_t path[MAX_PATH]{};
    GetModuleFileNameW(self, path, MAX_PATH);
    g_mode_path = std::filesystem::path(path).parent_path().parent_path()
        .parent_path() / L"PerfectPlacement" / L"native_gamepad_mode.txt";
    if (HMODULE ue4ss = GetModuleHandleW(L"UE4SS.dll"))
    {
        g_execute_lua = reinterpret_cast<ExecuteLuaInModFn>(
            GetProcAddress(ue4ss, "execute_lua_in_mod"));
    }
    if (!g_execute_lua || !hook_xinput_import()) return nullptr;
    if (!hook_raw_input_import())
    {
        unhook_xinput_import();
        return nullptr;
    }
    return new UserModAdapter{};
}

extern "C" __declspec(dllexport) void uninstall_mod(UserModAdapter* mod)
{
    unhook_xinput_import();
    unhook_raw_input_import();
    delete mod;
}
