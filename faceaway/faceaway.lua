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

--[[
BSD 3-Clause License

Copyright (c) 2026 Broguypal
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of Broguypal nor the names of its contributors may be used
   to endorse or promote products derived from this software without specific
   prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]
