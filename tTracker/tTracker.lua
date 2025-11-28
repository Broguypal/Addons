_addon.name = 'tTracker'
_addon.author = 'Broguypal'
_addon.version = '2.0'
_addon.commands = {'ttracker', 'track'}

packets = require('packets')
res = require('resources')
texts = require('texts')
config = require('config')

local element_path = windower.addon_path .. 'Monster_Ability_Elements.lua'
local monster_elements = require('Monster_Ability_Elements')
local unique_elements = require('Unique_Elements')

local valid_elements = {
    fire = true, water = true, wind = true, ice = true,
    earth = true, thunder = true, light = true, dark = true
}

-- Custom Monster element colors
local monster_element_colors = {
    fire = {255, 64, 64},
    water = {64, 128, 255},
    wind = {64, 255, 128},
    ice = {160, 240, 255},
    earth = {150, 100, 50},
    thunder = {192, 64, 255},
    light = {255, 255, 255},
    dark = {80, 60, 100},
}

-- Spell color map
local element_colors = {
    [0] = {255, 64, 64},
    [1] = {160, 240, 255},
    [2] = {64, 255, 128},
    [3] = {150, 100, 50},
    [4] = {192, 64, 255},
    [5] = {64, 128, 255},
    [6] = {255, 255, 255},
    [7] = {80, 60, 100},
    default = {255, 192, 64}
}

-- Saving Elements
local function save_monster_elements()
    local file = io.open(element_path, 'w')
    if not file then
        error('[tTracker] Failed to write Monster_Ability_Elements.lua')
    end

    file:write('-- Monster_Ability_Elements.lua\n\nreturn {\n')
    for element, abilities in pairs(monster_elements) do
        file:write(string.format('    %s = {\n', element))
        for name, _ in pairs(abilities) do
            file:write(string.format('        [\"%s\"] = true,\n', name))
        end
        file:write('    },\n')
    end
    file:write('}\n')
    file:close()
    print('[tTracker] Monster_Ability_Elements.lua updated.')
end

local settings
local mode
local output_box
local last_pos
local initialized = false
local player_ready = false
local default_msg = '\\cs(100,100,100)tTracker ready...\\cr'

-- Timed line buffer
local lines = {}
local max_lines
local expire_seconds

-- Default settings
local defaults = {
    mode = 'always',
    pos = {x = 800, y = 300},
    max_lines = 5,
    timeout = 20
}

-- Save settings helper
local function save_settings()
    if not settings or not output_box then return end
    local x, y = output_box:pos()
    settings.pos.x = x
    settings.pos.y = y
    settings.mode = mode
    settings.max_lines = max_lines
    settings.timeout = expire_seconds
    config.save(settings)
end

local function purge_expired(buffer)
    local now = os.clock()
    for i = #buffer, 1, -1 do
        if now - buffer[i].time > expire_seconds then
            table.remove(buffer, i)
        end
    end
end

local function update_display()
    if not initialized or not windower.ffxi.get_player() then
        if output_box then output_box:hide() end
        return
    end

    purge_expired(lines)

    local player = windower.ffxi.get_player()
    local player_status = player and player.status or 0

    if mode == 'combat' and player_status ~= 1 then
        output_box:hide()
        return
    elseif mode == 'action' and #lines == 0 then
        output_box:hide()
        return
    end

    if #lines > 0 then
        local out = ''
        for i, entry in ipairs(lines) do
            out = out .. entry.text
            if i < #lines then
                out = out .. '\n'
            end
        end
        output_box:text(out)
        output_box:show()
    else
        output_box:text(default_msg)
        output_box:show()
    end
end

local function add_line(text)
    table.insert(lines, 1, {text = text, time = os.clock()})
    while #lines > max_lines do
        table.remove(lines)
    end
    update_display()
end

local function replace_casting_line(actor_name, spell_name, new_text)
    for i, entry in ipairs(lines) do
        if entry.text:find(actor_name .. ' is casting:') and entry.text:find(spell_name) then
            lines[i] = {text = new_text, time = os.clock()}
            update_display()
            return
        end
    end
    -- Fallback if no match found
    add_line(new_text)
end

local function replace_readying_line(actor_name, new_text)
    for i, entry in ipairs(lines) do
        if entry.text:find(actor_name .. ' readies:') then
            lines[i] = {text = new_text, time = os.clock()}
            update_display()
            return
        end
    end
    -- Fallback
    add_line(new_text)
end

-- Clear on zone change
windower.register_event('zone change', function()
    lines = {}
    if output_box then
        output_box:text('')
        output_box:hide()
    end
	player_ready = false
end)

-- Initialization and update every frame
windower.register_event('prerender', function()
    local player = windower.ffxi.get_player()

    if player and not player_ready then
        player_ready = true

        if not initialized then
            settings = config.load(defaults)
            mode = settings.mode
            max_lines = settings.max_lines or defaults.max_lines
            expire_seconds = settings.timeout or defaults.timeout

            output_box = texts.new('', {
                pos = {x = settings.pos.x, y = settings.pos.y},
                padding = 1,
                text = {font = 'Calibri', size = 12, alpha = 255, red = 255, green = 255, blue = 255, stroke = {width = 1, alpha = 255, red = 0, green = 0, blue = 0 }},
                bg = {red = 30, green = 30, blue = 40, alpha = 200, visible = true},
                flags = {bold = true, draggable = true}
            })

            last_pos = {x = settings.pos.x, y = settings.pos.y}
            initialized = true
        end
    elseif not player and player_ready then
        player_ready = false
    end

    if initialized and output_box then
        local x, y = output_box:pos()
        if x ~= last_pos.x or y ~= last_pos.y then
            save_settings()
        end
        update_display()
    end
end)

-- Handle incoming casting/readies
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x28 then return end

    local p = packets.parse('incoming', data)
    local actor = windower.ffxi.get_mob_by_id(p.Actor)
    local target = windower.ffxi.get_mob_by_target('t')

    if not actor or not target then return end
    if actor.id ~= target.id then return end

    local actor_name = actor.name
    local param = p["Target 1 Action 1 Param"]
    local message_id = p["Target 1 Action 1 Message"]

    -- === SPELLS (Category 8) ===
    if p.Category == 8 then
        local spell = res.spells[param]
        local spell_name = spell and spell.name or ("Unknown Spell")
        local element_id
        if spell then
            for element_name, spell_table in pairs(unique_elements) do
                if spell_table[spell.name] then
                    element_id = ({
                        fire = 0, ice = 1, wind = 2, earth = 3,
                        thunder = 4, water = 5, light = 6, dark = 7
                    })[element_name]
                    break
                end
            end
            element_id = element_id or spell.element
        end
        local r, g, b = unpack(element_colors.default)
        if element_id and element_colors[element_id] then
            r, g, b = unpack(element_colors[element_id])
        end

        if message_id == 0 then
            local interrupt_line = ("\\cs(100,100,100)%s's %s was interrupted.\\cr"):format(actor_name, spell_name)
            replace_casting_line(actor_name, spell_name, interrupt_line)
        elseif message_id == 3 or message_id == 327 then
            add_line(("\\cs(180,180,255)%s is casting:\\cr \\cs(%d,%d,%d)%s\\cr"):
                format(actor_name, r, g, b, spell_name))
        end

    -- === TP/Ready moves (Category 7) ===
    elseif p.Category == 7 then
        if actor.spawn_type == 2 or actor.spawn_type == 16 then -- (2 = pets/npcs, 16 = Monsters)
            local mob_ability = res.monster_abilities[param]
            local ws          = mob_ability and nil or res.weapon_skills[param]  -- only check WS if no mob ability
            local ability_name = (mob_ability and mob_ability.name) or (ws and ws.name) or "Unknown TP Move"

            if message_id == 0 then
                local interrupt_line = ("\\cs(100,100,100)%s's TP move was interrupted.\\cr"):
                    format(actor_name)
                replace_readying_line(actor_name, interrupt_line)
            else
                local r, g, b = 255, 192, 64 -- default

                if mob_ability then
                    for element, ability_table in pairs(monster_elements) do
                        if ability_table[ability_name] then
                            local color = monster_element_colors[element]
                            if color then r, g, b = unpack(color) end
                            break
                        end
                    end
                elseif ws then
                    local element_id = ws.element
                    if element_id == 6 and not (unique_elements.light_weaponskills or {})[ability_name] then
                        element_id = nil
                    end
                    if element_id and element_colors[element_id] then
                        r, g, b = unpack(element_colors[element_id])
                    end
                end

                add_line(("\\cs(255,255,64)%s readies:\\cr \\cs(%d,%d,%d)%s\\cr"):
                    format(actor_name, r, g, b, ability_name))
            end

        elseif actor.spawn_type == 1 or actor.spawn_type == 14 or actor.spawn_type == 13 then -- (1 = other players, 14 = trusts, 13 = self)
            local ws = res.weapon_skills[param]
            local ws_name = ws and ws.name or ("Unknown Weaponskill")
            local element_id = ws and ws.element
            if element_id == 6 and not (unique_elements.light_weaponskills or {})[ws_name] then
                element_id = nil
            end

            local r, g, b = unpack(element_colors.default)
            if element_id and element_colors[element_id] then
                r, g, b = unpack(element_colors[element_id])
            end

            add_line(("\\cs(255,255,64)%s uses:\\cr \\cs(%d,%d,%d)%s\\cr"):
                format(actor_name, r, g, b, ws_name))
        end

    -- === TP MOVE FINISH (Category 11) ===
    elseif p.Category == 11 then
        local mob_ability = res.monster_abilities[p.Param]
        local ability_name = mob_ability and mob_ability.name or "Unknown TP Move"

        local r, g, b = 255, 192, 64
        if mob_ability then
            for element, ability_table in pairs(monster_elements) do
                if ability_table[ability_name] then
                    local color = monster_element_colors[element]
                    if color then r, g, b = unpack(color) end
                    break
                end
            end
        end

        local complete_line =
            ("\\cs(200,200,40)%s completes:\\cr \\cs(%d,%d,%d)%s\\cr"):
            format(actor_name, r, g, b, ability_name)

        replace_readying_line(actor_name, complete_line)

    -- === WEAPONSKILL FINISH (Category 3) ===
    elseif p.Category == 3 then
        local ws = res.weapon_skills[p.Param]
        local ws_name = ws and ws.name or "Unknown Weaponskill"
        local element_id = ws and ws.element

        if element_id == 6 and not (unique_elements.light_weaponskills or {})[ws_name] then
            element_id = nil
        end

        local r, g, b = unpack(element_colors.default)
        if element_id and element_colors[element_id] then
            r, g, b = unpack(element_colors[element_id])
        end

        local complete_line =
            ("\\cs(200,200,40)%s completes:\\cr \\cs(%d,%d,%d)%s\\cr"):
            format(actor_name, r, g, b, ws_name)

        replace_readying_line(actor_name, complete_line)

    -- === SPELL FINISH (Category 4) ===
    elseif p.Category == 4 then
        local spell = res.spells[p.Param]
        local spell_name = spell and spell.name or ("Unknown Spell")

        local element_id
        if spell then
            for element_name, spell_table in pairs(unique_elements) do
                if spell_table[spell_name] then
                    element_id = ({
                        fire = 0, ice = 1, wind = 2, earth = 3,
                        thunder = 4, water = 5, light = 6, dark = 7
                    })[element_name]
                    break
                end
            end
            element_id = element_id or spell.element
        end

        local r, g, b = unpack(element_colors.default)
        if element_id and element_colors[element_id] then
            r, g, b = unpack(element_colors[element_id])
        end

        local complete_line =
            ("\\cs(120,120,220)%s completed:\\cr \\cs(%d,%d,%d)%s\\cr"):
                format(actor_name, r, g, b, spell_name)

        replace_casting_line(actor_name, spell_name, complete_line)
    end
end)


-- Command handler: //track mode [always|combat|action]
windower.register_event('addon command', function(cmd, ...)
    local function print_commands()
        print('[tTracker] Available commands:')
        print('    //track mode [always|combat|action]')
        print('    //track lines <1–50>')
        print('    //track timeout <1–120>')
        print('    //track status')
        print('    //track add "Ability Name" <element>')
        print('    //track remove "Ability Name"')
    end

    if not cmd then
        print_commands()
        return
    end

    cmd = cmd:lower()
    local args = {...}

    if cmd == 'mode' then
        local arg = args[1] and args[1]:lower()
        if arg == 'always' or arg == 'combat' or arg == 'action' then
            mode = arg
            print('[tTracker] Mode set to: ' .. mode)
            update_display()
        else
            print('[tTracker] Invalid mode. Usage: //track mode [always|combat|action]')
        end

    elseif cmd == 'lines' then
        local n = tonumber(args[1])
        if n and n > 0 and n <= 50 then
            max_lines = n
            print('[tTracker] Max lines set to: ' .. n)
            update_display()
        else
            print('[tTracker] Invalid line count. Must be 1–50.')
        end

    elseif cmd == 'timeout' then
        local n = tonumber(args[1])
        if n and n >= 1 and n <= 120 then
            expire_seconds = n
            print('[tTracker] Timeout set to: ' .. n .. ' seconds')
            update_display()
        else
            print('[tTracker] Invalid timeout. Must be 1–120 seconds.')
        end

    elseif cmd == 'status' then
        print('[tTracker] Current settings:')
        print('    Mode: ' .. tostring(mode))
        print('    Max lines: ' .. tostring(max_lines))
        print('    Timeout: ' .. tostring(expire_seconds) .. ' seconds')
        print('    Position: ' .. tostring(settings.pos.x) .. ', ' .. tostring(settings.pos.y))

    elseif cmd == 'add' then
        local ability_input = args[1]
        local element = args[2] and args[2]:lower()

        if not ability_input or not element then
            print('[tTracker] Usage: //track add "Ability Name" <element>')
            return
        end

        if not valid_elements[element] then
            print('[tTracker] Invalid element. Must be one of: fire, water, wind, ice, earth, thunder, light, dark')
            return
        end

        local ability_lc = ability_input:lower()

        -- Prevent duplicates (case-insensitive)
        for elem, list in pairs(monster_elements) do
            for stored_name, _ in pairs(list) do
                if stored_name:lower() == ability_lc then
                    print(('[tTracker] "%s" already exists in element "%s". Remove it first before re-adding.'):format(stored_name, elem))
                    return
                end
            end
        end

        -- Match casing to official monster ability name if available
        local canonical_name = nil
        for id, ability in pairs(res.monster_abilities) do
            if ability.name:lower() == ability_lc then
                canonical_name = ability.name
                break
            end
        end

        local name_to_store = canonical_name or ability_input
        monster_elements[element][name_to_store] = true
        print(('[tTracker] Added "%s" to element "%s".'):format(name_to_store, element))
        save_monster_elements()

    elseif cmd == 'remove' then
        local ability_input = args[1]
        if not ability_input then
            print('[tTracker] Usage: //track remove "Ability Name"')
            return
        end

        local ability_lc = ability_input:lower()
        local found = false

        for element, list in pairs(monster_elements) do
            for stored_name, _ in pairs(list) do
                if stored_name:lower() == ability_lc then
                    list[stored_name] = nil
                    found = true
                    print(('[tTracker] Removed "%s" from element "%s".'):format(stored_name, element))
                    break
                end
            end
            if found then break end
        end

        if not found then
            print(('[tTracker] Ability "%s" not found in any element table.'):format(ability_input))
        else
            save_monster_elements()
        end

    else
        print('[tTracker] Unknown command: ' .. cmd)
        print_commands()
    end

    save_settings()
end)


-- Save position/mode on unload
windower.register_event('unload', save_settings)

-- Also save on logout
windower.register_event('logout', save_settings)