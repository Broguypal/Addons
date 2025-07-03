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
    windower.send_command('bind ' .. settings.keybind .. ' faceaway turn')
    log('faceaway loaded. Press [' .. settings.keybind .. '] to turn 180 degrees.')
end)

-- Unbinds key on unload
windower.register_event('unload', function()
    windower.send_command('unbind ' .. settings.keybind)
end)

-- Turn 180 degrees from current facing (simple version)
function turn_around()
    local player = windower.ffxi.get_mob_by_target('me')
    if not player or not player.facing then
        log('No valid player or facing info.')
        return
    end

    local current_facing = player.facing
    if current_facing < 0 then
        current_facing = current_facing + 2 * math.pi
    end

    local turn_angle = (current_facing + math.pi) % (2 * math.pi)

    windower.ffxi.run(false)
    windower.ffxi.turn(turn_angle)
end

-- Handle addon commands
windower.register_event('addon command', function(command)
    if command == 'turn' then
        turn_around()
    end
end)