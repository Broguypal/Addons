-- AbysseaProc - Element / Weapon / WS cycler with HUD

_addon.name     = 'AbysseaProc'
_addon.author   = 'Broguypal'
_addon.version  = '2.0'
_addon.commands = { 'aproc' }

local texts = require('texts')

-------------------------------------------------------------
--  KEYBINDS (CHANGE THESE IF YOU WANT)
-------------------------------------------------------------
local key_element = 'f10'  -- cycle element
local key_weapon  = 'f11'  -- cycle weapon for current element
local key_ws      = 'f12'  -- use weaponskill for current weapon/element

-------------------------------------------------------------
--  WEAPONS YOU OWN (EDIT THIS PART)
-------------------------------------------------------------
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
--  ELEMENT → (WEAPON TYPE, WEAPONSKILL) MAPPING
--  From the Abyssea red proc table.
-------------------------------------------------------------
local element_order = {
    "Fire",
	"Ice",
	"Wind",
	"Earth",
	"Thunder",
	"Light",
    "Dark",
}

local element_map = {
    Wind = {
        {weapon_type = "Dagger",       ws = "Cyclone"},
        {weapon_type = "Great Katana", ws = "Tachi: Jinpu"},
    },
    Dark = {
        {weapon_type = "Dagger",  ws = "Energy Drain"},
        {weapon_type = "Scythe",  ws = "Shadow of Death"},
        {weapon_type = "Katana",  ws = "Blade: Ei"},
    },
    Fire = {
        {weapon_type = "Sword", ws = "Red Lotus Blade"},
    },
    Light = {
        {weapon_type = "Sword",        ws = "Seraph Blade"},
        {weapon_type = "Great Katana", ws = "Tachi: Koki"},
        {weapon_type = "Club",         ws = "Seraph Strike"},
        {weapon_type = "Staff",        ws = "Sunburst"},
    },
    Ice = {
        {weapon_type = "Great Sword", ws = "Freezebite"},
    },
    Thunder = {
        {weapon_type = "Polearm", ws = "Raiden Thrust"},
    },
    Earth = {
        {weapon_type = "Staff", ws = "Earth Crusher"},
    },
}

-------------------------------------------------------------
--  ELEMENT COLORS (RGB) 
-------------------------------------------------------------
local element_colors = {
    Light   = {255, 255, 255}, -- LGT
    Fire    = {255,  64,  64}, -- FIR
    Wind    = {  0, 255,   0}, -- WND
    Thunder = {180,   0, 255}, -- THD
    Dark    = { 80,  60, 100}, -- DRK
    Ice     = {128, 255, 255}, -- ICE
    Earth   = {165, 100,  40}, -- STN
    Water   = { 64, 128, 255}, -- WTR (unused)
}

-------------------------------------------------------------
--  INTERNAL STATE
-------------------------------------------------------------
local current_element_index = 1
local current_element       = element_order[current_element_index]

local weapons_for_element   = {} 
local current_weapon_index  = 0

-------------------------------------------------------------
--  TEXT BOX (HUD)
-------------------------------------------------------------
local info_box = texts.new()
info_box:pos(800, 400)  -- change position if you want
info_box:size(12)
info_box:bold(true)
info_box:show()
info_box:bg_alpha(180)  
info_box:bg_color(30, 30, 30) 

local function colorize_element(name)
    local c = element_colors[name] or {255, 255, 255}
    return string.format('\\cs(%d,%d,%d)%s\\cr', c[1], c[2], c[3], name or 'None')
end

local function update_display()
    local elem_str = colorize_element(current_element or 'None')

    local weapon_type = 'None'
    local wsname      = 'None'

    local entry = weapons_for_element[current_weapon_index]
    if entry then
        weapon_type = entry.weapon_type or 'None'
        wsname      = entry.ws or 'None'
    end

    local text = string.format(
[[\cs(200,200,200)[AbysseaProc]\cr
\cs(160,160,160)Element:\cr   %s
\cs(160,160,160)Weapon:\cr    %s
\cs(160,160,160)WS:\cr        %s]],
        elem_str,
        weapon_type,
        wsname
    )

    info_box:text(text)
    info_box:show()
end


-------------------------------------------------------------
--  BUILD LIST OF ACTUAL WEAPONS FOR CURRENT ELEMENT
-------------------------------------------------------------
local function rebuild_weapons_for_element()
    weapons_for_element = {}
    current_weapon_index = 0

    local elem = current_element
    local elem_data = element_map[elem]
    if not elem_data then
        update_display()
        return
    end

    for _, entry in ipairs(elem_data) do
        local wtype  = entry.weapon_type
        local wsname = entry.ws
        local list   = weapon_groups[wtype]

        if list then
            for _, weapon_name in ipairs(list) do
                table.insert(weapons_for_element, {
                    weapon_type = wtype,
                    weapon_name = weapon_name,
                    ws          = wsname,
                })
            end
        end
    end

    update_display()
end

-------------------------------------------------------------
--  CYCLE ELEMENT
-------------------------------------------------------------
local function cycle_element()
    current_element_index = current_element_index + 1
    if current_element_index > #element_order then
        current_element_index = 1
    end

    current_element = element_order[current_element_index]
    rebuild_weapons_for_element()

    windower.add_to_chat(207,
        string.format("[AbysseaProc] Element: %s", current_element)
    )
end

-------------------------------------------------------------
--  CYCLE WEAPON FOR CURRENT ELEMENT
-------------------------------------------------------------
local function cycle_weapon_for_element()
    if #weapons_for_element == 0 then
        windower.add_to_chat(123,
            string.format("[AbysseaProc] No weapons configured for element: %s", current_element)
        )
        update_display()
        return
    end

    current_weapon_index = current_weapon_index + 1
    if current_weapon_index > #weapons_for_element then
        current_weapon_index = 1
    end

    local entry = weapons_for_element[current_weapon_index]

    windower.send_command('input /equip main "' .. entry.weapon_name .. '"')
	windower.add_to_chat(207,
		string.format("[AbysseaProc] [%s] %s - WS: %s",
			current_element, entry.weapon_name, entry.ws)
	)

    update_display()
end

-------------------------------------------------------------
--  USE WEAPONSKILL FOR CURRENT ELEMENT + WEAPON
-------------------------------------------------------------
local function use_current_ws()
    local entry = weapons_for_element[current_weapon_index]
    if not entry then
        windower.add_to_chat(123,
            "[AbysseaProc] No weapon selected for current element."
        )
        return
    end

    windower.send_command('input /ws "' .. entry.ws .. '" <t>')
	windower.add_to_chat(207,
		string.format("[AbysseaProc] Using %s with %s (%s)",
			entry.ws, entry.weapon_name, current_element)
	)

    update_display()
end

-------------------------------------------------------------
--  COMMAND HANDLER
-------------------------------------------------------------
--  //aproc element  – cycle element
--  //aproc weapon   – cycle weapon for current element
--  //aproc ws       – use weaponskill
--  //aproc reset    – reset element + weapon indices
-------------------------------------------------------------
windower.register_event('addon command', function(cmd, ...)
    cmd = cmd and cmd:lower() or ''

    if cmd == 'element' then
        cycle_element()
    elseif cmd == 'weapon' then
        cycle_weapon_for_element()
    elseif cmd == 'ws' then
        use_current_ws()
    elseif cmd == 'reset' then
        current_element_index = 1
        current_element       = element_order[current_element_index]
        rebuild_weapons_for_element()
        current_weapon_index  = 0
        windower.add_to_chat(207, "[AbysseaProc] Reset to first element and weapon.")
    else
        -- default: treat //aproc as "cycle weapon"
        cycle_weapon_for_element()
    end
end)

-------------------------------------------------------------
--  LOAD / UNLOAD
-------------------------------------------------------------
windower.register_event('load', function()
    rebuild_weapons_for_element()

    windower.send_command(string.format('bind %s input //aproc element', key_element))
    windower.send_command(string.format('bind %s input //aproc weapon',  key_weapon))
    windower.send_command(string.format('bind %s input //aproc ws',      key_ws))

    windower.add_to_chat(207,
        string.format("[AbysseaProc] Loaded. %s: element, %s: weapon, %s: WS.",
            key_element:upper(), key_weapon:upper(), key_ws:upper())
    )

    update_display()
end)

windower.register_event('unload', function()
    windower.send_command(string.format('unbind %s', key_element))
    windower.send_command(string.format('unbind %s', key_weapon))
    windower.send_command(string.format('unbind %s', key_ws))
    if info_box then
        info_box:hide()
    end
end)

--[[
MIT License

Copyright (c) 2026 Broguypal

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]
