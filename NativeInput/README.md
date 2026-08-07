# Perfect Placement native gamepad input

This separately distributed optional UE4SS add-on contains the C++ companion for the controller mapping logic bundled with Perfect Placement Core. The native component intercepts Palworld's existing `XInputGetState` import, forwards only the reserved controller edges owned by the current preview mode, and removes those inputs from the state returned to Palworld.

It introduces no recurring Lua controller polling. Core resolves physical inputs into placement actions in the same Lua environment as the rest of Perfect Placement; this add-on supplies only the optional native interception layer.
