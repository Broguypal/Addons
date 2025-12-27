
_addon.name     = 'AbysseaProc'
_addon.author   = 'Broguypal'
_addon.version  = '1.0'
_addon.commands = { 'aproc' }

-------------------------------------------------------------
--	KEYBIND AND WEAPONS
-------------------------------------------------------------
windower.send_command('bind f12 input //aproc cycle')

local weapon_groups = {
    ["Dagger"]       = { "Ceremonial Dagger" },
    ["Sword"]        = { "Twinned Blade" },
    ["Great Sword"]  = { "Irradiance Blade" },
    ["Scythe"]       = { "Hoe" },
    ["Polearm"]      = { "Iapetus" },
    ["Katana"]       = { "Yagyu Short. +1" },
    ["Great Katana"] = { "Ark Tachi" },
    ["Club"]         = { "Chac-chacs" },
    ["Staff"]        = { "Ram Staff" },
}

-------------------------------------------------------------
--	LOGIC
-------------------------------------------------------------
local weapons = {}
local weapon_type_lookup = {}

for wtype, list in pairs(weapon_groups) do
    for _, weapon in ipairs(list) do
        table.insert(weapons, weapon)
        weapon_type_lookup[weapon] = wtype
    end
end

local current_index = 0

-------------------------------------------------------------
-- CYCLE FUNCTION
-------------------------------------------------------------
local function cycle_weapon()
    if #weapons == 0 then
        windower.add_to_chat(123, "[AbysseaProc] No weapons defined.")
        return
    end

    current_index = current_index + 1
    if current_index > #weapons then
        current_index = 1
    end

    local wpn   = weapons[current_index]
    local wtype = weapon_type_lookup[wpn] or "Unknown"

    windower.send_command('input /equip main "' .. wpn .. '"')
    windower.add_to_chat(207, ("[AbysseaProc] Equipped: %s [%s]"):format(wpn, wtype))
end

-------------------------------------------------------------
-- COMMAND HANDLER
-------------------------------------------------------------
windower.register_event('addon command', function(cmd, ...)
    cmd = cmd and cmd:lower() or ''

    if cmd == '' or cmd == 'cycle' then
        cycle_weapon()
    elseif cmd == 'reset' then
        current_index = 0
        windower.add_to_chat(207, "[AbysseaProc] Index reset.")
    end
end)

-------------------------------------------------------------
-- LOAD / UNLOAD
-------------------------------------------------------------
windower.register_event('load', function()
    windower.add_to_chat(207, "[AbysseaProc] Loaded. Press F12 to cycle proc weapons.")
end)

windower.register_event('unload', function()
    windower.send_command('unbind f12')
end)
