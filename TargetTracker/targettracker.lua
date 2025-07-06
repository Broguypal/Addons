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

local settings
local display_mode
local player_status = 'Idle'

local cast_box
local tp_box

local max_entries = 3
local expire_seconds = 30
local default_cast_msg = 'CastTracker ready...'
local default_tp_msg = 'TPTracker ready...'

-- === STATE ===
local cast_log = {}
local tp_log = {}
local player_ready = false
local initialized = false

-- === UTILITY ===
local function now()
    return os.time()
end

local function sanitize_text(text)
    return (text:gsub("[^\32-\126]", "?"))
end

local function format_line(line)
    local time_str = os.date('%M:%S', line.timestamp)
    return ('%s \\cs(100,100,100)[%s]\\cr'):format(line.text, time_str)
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
    if not windower.ffxi.get_player() then
        box:hide()
        return
    end

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

-- === SETTINGS SAVE HELPER ===
local function save_settings()
    if settings and cast_box and tp_box then
        local c_x, c_y = cast_box:pos()
        local t_x, t_y = tp_box:pos()
        settings.cast_box_pos = { x = c_x, y = c_y }
        settings.tp_box_pos   = { x = t_x, y = t_y }
        settings.display_mode = display_mode or settings.display_mode
        config.save(settings)
    end
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
				local spell_name, target_part = spell:match('^(.-)( on .*)$')
				if not spell_name then
					spell_name = spell
					target_part = ''
				end
				local colored_spell = '\\cs(100,255,255)' .. spell_name .. '\\cr' .. target_part
				local text = caster .. ' starts casting ' .. colored_spell
				table.insert(cast_log, 1, { text = text, timestamp = now() })
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
			local move_name, target_part = move:match('^(.-)( on .*)$')
			if not move_name then
				move_name = move
				target_part = ''
			end
			local colored_move = '\\cs(255,215,0)' .. move_name .. '\\cr' .. target_part
			local text = caster .. ' readies ' .. colored_move
			table.insert(tp_log, 1, { text = text, timestamp = now() })
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

-- === LOAD AND PLAYER LOGIN DETECTION ===
windower.register_event('prerender', function()
    local player = windower.ffxi.get_player()

    if player and not player_ready then
        player_ready = true

        if not initialized then
            settings = config.load(defaults)
            display_mode = settings.display_mode or 'always'

            local cast_box_config = {
                pos = settings.cast_box_pos,
                padding = 4,
                text = {font = 'Calibri', size = 10, stroke = { width = 1, alpha = 255 }, color = { r = 255, g = 255, b = 255 },},
                bg = { red = 30, green = 50, blue = 100, alpha = 180 },
                flags = { draggable = true },
            }
            cast_box = texts.new('', cast_box_config)
            cast_box:show()

            local tp_box_config = {
                pos = settings.tp_box_pos,
                padding = 4,
                text = {font = 'Calibri', size = 10, stroke = { width = 1, alpha = 255 }, color = { r = 255, g = 255, b = 255 },},
                bg = { red = 100, green = 90, blue = 40, alpha = 180 },
                flags = { draggable = true },
            }
            tp_box = texts.new('', tp_box_config)
            tp_box:show()

            update_box(cast_box, cast_log, default_cast_msg)
            update_box(tp_box, tp_log, default_tp_msg)

            initialized = true
        end
    elseif not player and player_ready then
        player_ready = false
    end

    if initialized then
        update_box(cast_box, cast_log, default_cast_msg)
        update_box(tp_box, tp_log, default_tp_msg)
    end
end)

-- === SAVE ON UNLOAD / LOGOUT ===
windower.register_event('unload', save_settings)
windower.register_event('logout', save_settings)

-- === CUSTOM COMMAND HANDLER ===
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
