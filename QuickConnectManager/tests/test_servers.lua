package.path = "QuickConnectManager/Scripts/?.lua;" .. package.path

local Servers = require("servers")
local failures = 0

local function expect(label, condition)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. "\n")
    end
end

expect("hostname and port", Servers.validate_address("play.example.com:8211") ~= nil)
expect("IPv4", Servers.validate_address("192.168.1.20:8211") ~= nil)
expect("trim address", Servers.validate_address("  localhost:8211  ") == "localhost:8211")
expect("reject command pipe", Servers.validate_address("host:8211|quit") == nil)
expect("reject URL options", Servers.validate_address("host:8211?Password=secret") == nil)
expect("reject invalid port", Servers.validate_address("host:70000") == nil)
expect("reject invalid IPv4 octet", Servers.validate_address("999.1.1.1:8211") == nil)
expect("reject leading label hyphen", Servers.validate_address("-bad.example:8211") == nil)
expect("reject trailing label hyphen", Servers.validate_address("bad-.example:8211") == nil)

local entries, warnings = Servers.load({
    { name = "Alpha", address = "alpha.example:8211" },
    { name = "Disabled", address = "disabled.example:8211", enabled = false },
    { name = "Bad", address = "bad host:8211" },
})
expect("load enabled valid entry", #entries == 1 and entries[1].name == "Alpha")
expect("warn for invalid enabled entry", #warnings == 1)

local normalized, normalization_warnings = Servers.load({
    {
        name = "  Alpha\n\tServer  ",
        address = "alpha.example:8211",
        players = math.huge,
        max_players = -1,
        ping = 42,
    },
    { name = "Duplicate", address = "ALPHA.EXAMPLE:8211" },
})
expect(
    "sanitize display name",
    #normalized == 1 and normalized[1].name == "Alpha Server"
)
expect(
    "drop non-finite or invalid status values",
    normalized[1].players == nil
        and normalized[1].max_players == nil
        and normalized[1].ping == 42
)
expect("warn for duplicate address", #normalization_warnings == 1)

local long_name = string.rep("A", 200)
local long_password = string.rep("p", 600) .. "\0"
local bounded = Servers.load({
    {
        name = long_name,
        address = "bounded.example:8211",
        password = long_password,
    },
})
expect("bound server name", #bounded[1].name == 128)
expect("bound password", #bounded[1].password == 512)
expect("strip password NUL", bounded[1].password:find("\0", 1, true) == nil)

local by_name, name_index = Servers.resolve(entries, "alpha")
expect("resolve case-insensitive name", by_name == entries[1] and name_index == 1)
local by_index = Servers.resolve(entries, "1")
expect("resolve numeric string", by_index == entries[1])

local discovered = Servers.load({
    {
        name = "History Result",
        address = "history.example:8211",
        players = 3,
        max_players = 32,
        ping = 42,
        world_guid = "fixture-world-guid",
        password = "fixture-password",
        password_protected = true,
        discovered = true,
    },
})
expect(
    "preserve native discovery status",
    discovered[1].players == 3
        and discovered[1].max_players == 32
        and discovered[1].ping == 42
        and discovered[1].world_guid == "fixture-world-guid"
        and discovered[1].password == "fixture-password"
        and discovered[1].password_protected == true
        and discovered[1].discovered == true
)

if failures > 0 then
    error(string.format("%d test(s) failed", failures))
end
print("Quick Connect Manager server tests passed")
