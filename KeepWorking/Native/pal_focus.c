#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

typedef struct lua_State lua_State;

enum
{
    RECENT_FOCUS_LOSS_WINDOW_MS = 1500,
    RECENT_FOCUS_GAIN_WINDOW_MS = 250,
    MAX_SAMPLE_GAP_MS = 500
};

typedef struct FocusTracker
{
    SRWLOCK lock;
    BOOL initialized;
    BOOL wasForeground;
    ULONGLONG lastSampleTick;
    ULONGLONG lastFocusLossTick;
    BOOL lastFocusLossWasNoForegroundWindow;
    BOOL lastRecentQueryWasNoForegroundWindow;
    ULONGLONG lastFocusGainTick;
    BOOL focusGainTokenValid;
    BOOL lastFocusGainHadAltDown;
    BOOL lastFocusGainHadTabDown;
    BOOL lastRecentGainQueryHadAltDown;
    BOOL lastRecentGainQueryHadTabDown;
} FocusTracker;

typedef struct FocusSample
{
    BOOL known;
    BOOL foreground;
    BOOL recentFocusLoss;
    BOOL noForegroundWindow;
    BOOL recentFocusLossFromNoForegroundWindow;
    BOOL recentFocusGain;
    BOOL recentFocusGainHadAltDown;
    BOOL recentFocusGainHadTabDown;
} FocusSample;

static FocusTracker g_focusTracker = {
    SRWLOCK_INIT,
    FALSE,
    0,
    FALSE,
    0,
    FALSE,
    FALSE,
    FALSE,
    0,
    FALSE,
    FALSE,
    FALSE,
    FALSE,
};

static BOOL query_current_process_foreground(BOOL* known, BOOL* noForegroundWindow)
{
    HWND foregroundWindow = GetForegroundWindow();
    DWORD foregroundProcessId = 0;
    DWORD foregroundThreadId;

    *known = FALSE;
    *noForegroundWindow = FALSE;

    if (foregroundWindow == NULL)
    {
        /* No foreground window means this process is definitively not foreground. */
        *known = TRUE;
        *noForegroundWindow = TRUE;
        return FALSE;
    }

    foregroundThreadId = GetWindowThreadProcessId(foregroundWindow, &foregroundProcessId);
    if (foregroundThreadId == 0)
    {
        return FALSE;
    }

    *known = TRUE;
    return foregroundProcessId == GetCurrentProcessId();
}

static BOOL is_key_down(int virtualKey)
{
    return (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
}

static FocusSample sample_focus_locked(void)
{
    FocusSample sample = {FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE};
    ULONGLONG now;

    now = GetTickCount64();

    sample.foreground = query_current_process_foreground(
        &sample.known,
        &sample.noForegroundWindow);

    if (!sample.known)
    {
        g_focusTracker.lastFocusGainTick = 0;
        g_focusTracker.focusGainTokenValid = FALSE;
        g_focusTracker.lastFocusGainHadAltDown = FALSE;
        g_focusTracker.lastFocusGainHadTabDown = FALSE;
        return sample;
    }

    if (g_focusTracker.initialized &&
        g_focusTracker.wasForeground &&
        !sample.foreground)
    {
        ULONGLONG sampleGap = now - g_focusTracker.lastSampleTick;
        if (sampleGap <= MAX_SAMPLE_GAP_MS)
        {
            g_focusTracker.lastFocusLossTick = now;
            g_focusTracker.lastFocusLossWasNoForegroundWindow =
                sample.noForegroundWindow;
        }
        else
        {
            g_focusTracker.lastFocusLossTick = 0;
            g_focusTracker.lastFocusLossWasNoForegroundWindow = FALSE;
        }

        g_focusTracker.lastFocusGainTick = 0;
        g_focusTracker.focusGainTokenValid = FALSE;
        g_focusTracker.lastFocusGainHadAltDown = FALSE;
        g_focusTracker.lastFocusGainHadTabDown = FALSE;
    }

    if (g_focusTracker.initialized &&
        !g_focusTracker.wasForeground &&
        sample.foreground)
    {
        ULONGLONG sampleGap = now - g_focusTracker.lastSampleTick;
        if (sampleGap <= MAX_SAMPLE_GAP_MS)
        {
            g_focusTracker.lastFocusGainTick = now;
            g_focusTracker.focusGainTokenValid = TRUE;
            g_focusTracker.lastFocusGainHadAltDown = is_key_down(VK_MENU);
            g_focusTracker.lastFocusGainHadTabDown = is_key_down(VK_TAB);
        }
        else
        {
            g_focusTracker.lastFocusGainTick = 0;
            g_focusTracker.focusGainTokenValid = FALSE;
            g_focusTracker.lastFocusGainHadAltDown = FALSE;
            g_focusTracker.lastFocusGainHadTabDown = FALSE;
        }
    }

    g_focusTracker.initialized = TRUE;
    g_focusTracker.wasForeground = sample.foreground;
    g_focusTracker.lastSampleTick = now;

    sample.recentFocusLoss =
        !sample.foreground &&
        g_focusTracker.lastFocusLossTick != 0 &&
        (now - g_focusTracker.lastFocusLossTick) <= RECENT_FOCUS_LOSS_WINDOW_MS;
    sample.recentFocusLossFromNoForegroundWindow =
        sample.recentFocusLoss &&
        g_focusTracker.lastFocusLossWasNoForegroundWindow;
    sample.recentFocusGain =
        sample.foreground &&
        g_focusTracker.focusGainTokenValid &&
        (now - g_focusTracker.lastFocusGainTick) <= RECENT_FOCUS_GAIN_WINDOW_MS;
    sample.recentFocusGainHadAltDown =
        sample.recentFocusGain &&
        g_focusTracker.lastFocusGainHadAltDown;
    sample.recentFocusGainHadTabDown =
        sample.recentFocusGain &&
        g_focusTracker.lastFocusGainHadTabDown;

    return sample;
}

static FocusSample sample_focus(void)
{
    FocusSample sample;

    AcquireSRWLockExclusive(&g_focusTracker.lock);
    sample = sample_focus_locked();
    ReleaseSRWLockExclusive(&g_focusTracker.lock);

    return sample;
}

/*
 * These functions deliberately do not call the Lua C API. Lua invokes each
 * function with one private marker argument. Returning 1 leaves that existing
 * top argument as the result; returning 0 produces no result (nil to the caller).
 */
__declspec(dllexport) int __cdecl pal_focus_is_foreground(lua_State* state)
{
    FocusSample sample;
    (void)state;

    sample = sample_focus();
    return sample.known && sample.foreground ? 1 : 0;
}

__declspec(dllexport) int __cdecl pal_focus_is_f_down(lua_State* state)
{
    (void)state;
    return is_key_down('F') ? 1 : 0;
}

__declspec(dllexport) int __cdecl pal_focus_is_recent_loss(lua_State* state)
{
    FocusSample sample;
    (void)state;

    sample = sample_focus();

    AcquireSRWLockExclusive(&g_focusTracker.lock);
    g_focusTracker.lastRecentQueryWasNoForegroundWindow =
        sample.known && sample.recentFocusLossFromNoForegroundWindow;
    ReleaseSRWLockExclusive(&g_focusTracker.lock);

    return sample.known && sample.recentFocusLoss ? 1 : 0;
}

__declspec(dllexport) int __cdecl pal_focus_last_recent_loss_from_no_foreground(lua_State* state)
{
    BOOL result;
    (void)state;

    AcquireSRWLockShared(&g_focusTracker.lock);
    result = g_focusTracker.lastRecentQueryWasNoForegroundWindow;
    ReleaseSRWLockShared(&g_focusTracker.lock);

    return result ? 1 : 0;
}

__declspec(dllexport) int __cdecl pal_focus_is_recent_gain(lua_State* state)
{
    FocusSample sample;
    (void)state;

    sample = sample_focus();

    AcquireSRWLockExclusive(&g_focusTracker.lock);
    g_focusTracker.lastRecentGainQueryHadAltDown =
        sample.known && sample.recentFocusGainHadAltDown;
    g_focusTracker.lastRecentGainQueryHadTabDown =
        sample.known && sample.recentFocusGainHadTabDown;
    ReleaseSRWLockExclusive(&g_focusTracker.lock);

    return sample.known && sample.recentFocusGain ? 1 : 0;
}

__declspec(dllexport) int __cdecl pal_focus_last_recent_gain_had_alt(lua_State* state)
{
    BOOL result;
    (void)state;

    AcquireSRWLockShared(&g_focusTracker.lock);
    result = g_focusTracker.lastRecentGainQueryHadAltDown;
    ReleaseSRWLockShared(&g_focusTracker.lock);

    return result ? 1 : 0;
}

__declspec(dllexport) int __cdecl pal_focus_last_recent_gain_had_tab(lua_State* state)
{
    BOOL result;
    (void)state;

    AcquireSRWLockShared(&g_focusTracker.lock);
    result = g_focusTracker.lastRecentGainQueryHadTabDown;
    ReleaseSRWLockShared(&g_focusTracker.lock);

    return result ? 1 : 0;
}

__declspec(dllexport) int __cdecl pal_focus_consume_recent_gain(lua_State* state)
{
    FocusSample sample;
    BOOL matched;
    (void)state;

    AcquireSRWLockExclusive(&g_focusTracker.lock);
    sample = sample_focus_locked();
    matched = sample.known && sample.recentFocusGain;

    g_focusTracker.lastFocusGainTick = 0;
    g_focusTracker.focusGainTokenValid = FALSE;
    g_focusTracker.lastFocusGainHadAltDown = FALSE;
    g_focusTracker.lastFocusGainHadTabDown = FALSE;
    g_focusTracker.lastRecentGainQueryHadAltDown = FALSE;
    g_focusTracker.lastRecentGainQueryHadTabDown = FALSE;
    ReleaseSRWLockExclusive(&g_focusTracker.lock);

    return matched ? 1 : 0;
}
