_addon.name = 'CastTracker'
_addon.author = 'Broguypal'
_addon.version = '1.0'

local texts = require('texts')
local config = require('config')

-- === CONFIGURATION ===
local defaults = {
    cast_box_pos = { x = 200, y = 200 },
    tp_box_pos   = { x = 200, y = 350 },
}

local settings = config.load(defaults)

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

-- Strip non-ASCII characters
local function sanitize_text(text)
    return (text:gsub("[^\32-\126]", "?"))
end

-- Format line
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

-- === UNLOAD EVENT: Save current positions ===
windower.register_event('unload', function()
    local c_x, c_y = cast_box:pos()
    local t_x, t_y = tp_box:pos()

    settings.cast_box_pos.x = c_x
    settings.cast_box_pos.y = c_y
    settings.tp_box_pos.x = t_x
    settings.tp_box_pos.y = t_y

    config.save(settings)
end)
