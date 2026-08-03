return {
    -- Addresses may be hostnames or IPv4 addresses with an optional port.
    -- Palworld's default game port is 8211.
    -- An optional password is stored as plain text in this local file.
    -- QUICKCONNECT_SERVERS_BEGIN
    servers = {
        {
            name = "My Server",
            address = "127.0.0.1:8211",
            password = "",
            enabled = false,
        },
    },
    -- QUICKCONNECT_SERVERS_END

    -- Direct shortcuts use Ctrl+Shift+F1 through Ctrl+Shift+F8.
    hotkeys = {
        enabled = true,
        max_slots = 8,
    },

    selected_slot = 1,
    connect_cooldown_ms = 2000,
    ui = {
        show_on_launch = true,
    },
    diagnostics = {
        verbose = false,
    },
}
