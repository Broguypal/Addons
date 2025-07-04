_addon.name     = 'TargetTracker'
_addon.author   = 'Broguypal'
_addon.version  = '1.0'
_addon.commands = {'tart', 'targettracker'}

local texts = require('texts')
local config = require('config')

-- === CONFIGURATION ===
local defaults = {
    cast_box_pos = { x = 200, y = 200 },
    tp_box_pos   = { x = 200, y = 350 },
    display_mode = 'always',
}

local settings = config.load(defaults)
local display_mode = settings.display_mode
local player_status = 'Idle'

local max_entries = 3
local expire_seconds = 30
local default_cast_msg = 'CastTracker ready...'
local default_tp_msg = 'TPTracker ready...'

-- === STATE ===
local cast_log = {}
local tp_log = {}

-- === SPELL CASTING BOX ===
local cast_box_config = {
    pos = settings.cast_box_pos,
    padding = 4,
    text = {font = 'Consolas', size = 10, stroke = { width = 1, alpha = 255 }, color = { r = 255, g = 255, b = 255 },},
    bg = { red = 30, green = 50, blue = 100, alpha = 180 },  
    flags = { draggable = true },
}

local cast_box = texts.new('', cast_box_config)
cast_box:show()

-- === TP MOVE BOX ===
local tp_box_config = {
    pos = settings.tp_box_pos,
    padding = 4,
    text = {font = 'Consolas', size = 10, stroke = { width = 1, alpha = 255 }, color = { r = 255, g = 255, b = 255 },},
    bg = { red = 100, green = 90, blue = 40, alpha = 180 },  
    flags = { draggable = true },
}

local tp_box = texts.new('', tp_box_config)
tp_box:show()

-- === UTILITY ===
local function now()
    return os.time()
end

local function sanitize_text(text)
    return (text:gsub("[^\32-\126]", "?"))
end

local function format_line(line)
    local time_str = os.date('%M:%S', line.timestamp)
    return ('\\cs(255,255,0)%s \\cs(100,100,100)[%s]\\cr'):format(line.text, time_str)
end

local function purge_expired(buffer)
    local current = now()
    for i = #buffer, 1, -1 do
        if (current - buffer[i].timestamp) > expire_seconds then
            table.remove(buffer, i)
        end
    end
end

local function update_box(box, buffer, default_text)
    purge_expired(buffer)

    if display_mode == 'combat' and player_status ~= 'Engaged' then
        box:hide()
        return
    elseif display_mode == 'action' and #buffer == 0 then
        box:hide()
        return
    end

    if #buffer > 0 then
        local out = ''
        for i, entry in ipairs(buffer) do
            out = out .. format_line(entry)
            if i < #buffer then
                out = out .. '\n'
            end
        end
        box:text(out)
        box:show()
    else
        box:text('\\cs(100,100,100)' .. default_text .. '\\cr')
        box:show()
    end
end

function string:trim()
    return self:match('^%s*(.-)%s*$')
end

-- === MAIN LOGIC ===
windower.register_event('incoming text', function(original, modified, mode)
    if not original or mode == 123 then return end

    local decoded = windower.from_shift_jis(original)
    local clean = decoded:gsub('\30%a', ''):gsub('\31%a', ''):trim()

    local target = windower.ffxi.get_mob_by_target('t')
    if not target or not target.name then return end
    local target_name = sanitize_text(target.name:lower())

    -- SPELL CASTING
    if mode == 52 then
        local caster, spell = clean:match('^(.-) starts casting (.-)%.?$')
        if caster and spell then
            caster = sanitize_text(caster)
            spell = sanitize_text(spell):gsub('%s*%p?%d+$', '')
            if caster:lower():gsub('^the ', '') == target_name then
                table.insert(cast_log, 1, { text = caster .. ' starts casting ' .. spell, timestamp = now() })
                while #cast_log > max_entries do table.remove(cast_log) end
                update_box(cast_box, cast_log, default_cast_msg)
            end
        end
    end

    -- TP MOVE
    local caster, move = clean:match('^(.-) readies (.-)%.?$')
    if caster and move then
        caster = sanitize_text(caster)
        move = sanitize_text(move):gsub('%s*%p?%d+$', '')
        if caster:lower():gsub('^the ', '') == target_name then
            table.insert(tp_log, 1, { text = caster .. ' readies ' .. move, timestamp = now() })
            while #tp_log > max_entries do table.remove(tp_log) end
            update_box(tp_box, tp_log, default_tp_msg)
        end
    end
end)

-- === ZONE CHANGE: Clear logs ===
windower.register_event('zone change', function()
    cast_log = {}
    tp_log = {}
    update_box(cast_box, cast_log, default_cast_msg)
    update_box(tp_box, tp_log, default_tp_msg)
end)

-- === STATUS TRACKING ===
windower.register_event('status change', function(new, old)
    if new == 1 then
        player_status = 'Engaged'
    else
        player_status = 'Idle'
    end
end)

-- === PERIODIC CLEANUP ===
windower.register_event('prerender', function()
    update_box(cast_box, cast_log, default_cast_msg)
    update_box(tp_box, tp_log, default_tp_msg)
end)

-- === LOAD EVENT ===
windower.register_event('load', function()
    cast_log = {}
    tp_log = {}
    update_box(cast_box, cast_log, default_cast_msg)
    update_box(tp_box, tp_log, default_tp_msg)
end)

-- === UNLOAD EVENT: Save current positions and mode ===
windower.register_event('unload', function()
    local c_x, c_y = cast_box:pos()
    local t_x, t_y = tp_box:pos()

    settings.cast_box_pos.x = c_x
    settings.cast_box_pos.y = c_y
    settings.tp_box_pos.x = t_x
    settings.tp_box_pos.y = t_y
    settings.display_mode = display_mode

    config.save(settings)
end)

-- === CUSTOM COMMAND HANDLER (fixed with full fallback) ===
windower.register_event('addon command', function(...)
    local args = {...}
    local cmd = args[1] and args[1]:lower()
    local arg = args[2] and args[2]:lower()

    if cmd == 'box' then
        if arg == 'always' or arg == 'combat' or arg == 'action' then
            display_mode = arg
            settings.display_mode = arg
            config.save(settings)
            windower.add_to_chat(207, '[TargetTracker] Display mode set to: ' .. arg:gsub("^%l", string.upper))
        else
            windower.add_to_chat(123, '[TargetTracker] Invalid subcommand.')
            windower.add_to_chat(123, 'Usage: //tart box [always | combat | action]')
            windower.add_to_chat(123, '  always  - Always show the boxes (default)')
            windower.add_to_chat(123, '  combat  - Only show boxes while you are in combat')
            windower.add_to_chat(123, '  action  - Only show boxes when an action is detected')
        end
    else
        windower.add_to_chat(123, '[TargetTracker] Unknown command: "' .. tostring(cmd) .. '"')
        windower.add_to_chat(123, 'Usage: //tart box [always | combat | action]')
		windower.add_to_chat(123, '  always  - Always show the boxes (default)')
        windower.add_to_chat(123, '  combat  - Only show boxes while you are in combat')
        windower.add_to_chat(123, '  action  - Only show boxes when an action is detected')
    end
end)