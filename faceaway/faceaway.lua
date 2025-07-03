_addon.name     = 'faceaway'
_addon.author   = 'Broguypal'
_addon.version  = '1.0'
_addon.commands = {'faceaway'}

require('logger')
config = require('config')

-- Default config settings
defaults = {
    keybind = 'numpad0'  -- Change this in data/settings.xml
}

settings = config.load(defaults)

-- Binds key on load
windower.register_event('load', function()
    windower.send_command('bind ' .. settings.keybind .. ' faceaway toggle')
    log('faceaway loaded. Press [' .. settings.keybind .. '] to toggle facing.')
end)

-- Unbinds key on unload
windower.register_event('unload', function()
    windower.send_command('unbind ' .. settings.keybind)
end)

-- Toggle facing toward/away from target
function toggle_facing()
    local player = windower.ffxi.get_mob_by_target('me')
    local target = windower.ffxi.get_mob_by_target('t')

    if not player or not target then
        log('No valid target.')
        return
    end

    local dx = target.x - player.x
    local dy = target.y - player.y
    local angle_to_target = math.atan2(dy, dx)
    local current_facing = player.facing

    local angle_diff = math.abs((angle_to_target - current_facing + math.pi) % (2 * math.pi) - math.pi)
    local turn_angle

    if angle_diff < (math.pi / 6) then
        turn_angle = (angle_to_target + math.pi) % (2 * math.pi)
    else
        turn_angle = angle_to_target
    end

    windower.ffxi.run(false)
    windower.ffxi.turn(turn_angle)
end

-- Handle addon commands
windower.register_event('addon command', function(command)
    if command == 'toggle' then
        toggle_facing()
    end
end)
