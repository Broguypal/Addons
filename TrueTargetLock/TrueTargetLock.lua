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

_addon.name    = 'TrueTargetLock'
_addon.author  = 'Broguypal'
_addon.version = '1.2'
_addon.commands = {'truetargetlock'}

-- Throttle settings (edit here if desired)
local TURN_INTERVAL = 0.10     -- seconds between turn attempts
local MIN_DELTA     = 0.05     -- radians (~2.9°); must be off by this much to turn

local last_turn_t = 0

local config = require('config')

local defaults = {
    combat = true,
    locked = true,
}

local settings = config.load(defaults)

if settings.mode ~= nil then
    if settings.mode == 'always' then
        settings.locked = false
    end
    settings.mode = nil
    config.save(settings)
end

local function norm_pi(a)
    while a > math.pi do a = a - 2*math.pi end
    while a < -math.pi do a = a + 2*math.pi end
    return a
end

local function desired_facing_direction(self_vector, target)
    local dx = (target.x - self_vector.x)
    local dy = (target.y - self_vector.y)

    if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then
        return nil
    end

    local angle_deg = (math.atan2(dy, dx) * 180 / math.pi) * -1
    return angle_deg * (math.pi / 180)
end

local function on_off(v)
    return v and 'ON' or 'OFF'
end

local function parse_toggle(arg, current)
    if arg == 'on' then return true end
    if arg == 'off' then return false end
    if arg == nil or arg == '' or arg == 'toggle' then return not current end
    return nil
end

local function show_status()
    windower.add_to_chat(207, '[TrueTargetLock] Combat: '..on_off(settings.combat)..'  |  Locked: '..on_off(settings.locked))
end

local function show_help()
    windower.add_to_chat(207, '[TrueTargetLock] Commands:')
    windower.add_to_chat(207, '  //truetargetlock combat on|off  - Require being engaged (default ON)')
    windower.add_to_chat(207, '  //truetargetlock locked on|off  - Require native target lock (default ON)')
    windower.add_to_chat(207, '  //truetargetlock status         - Show current settings')
end

windower.register_event('addon command', function(cmd, arg)
    cmd = cmd and cmd:lower() or ''
    arg = arg and arg:lower() or nil

    if cmd == 'combat' or cmd == 'locked' then
        local value = parse_toggle(arg, settings[cmd])
        if value == nil then
            windower.add_to_chat(207, '[TrueTargetLock] Usage: //truetargetlock '..cmd..' on|off')
            return
        end

        settings[cmd] = value
        config.save(settings)
        show_status()

        if not settings.combat and not settings.locked then
            windower.add_to_chat(207, '[TrueTargetLock] **You will always face your current target, in or out of combat.**')
        elseif not settings.locked then
            windower.add_to_chat(207, '[TrueTargetLock] **You cannot turn away while engaged.**')
        end
    elseif cmd == 'status' then
        show_status()
    else
        show_help()
        show_status()
    end
end)

windower.register_event('prerender', function()
    local t = os.clock()

    if (t - last_turn_t) < TURN_INTERVAL then return end

    local pinfo = windower.ffxi.get_player()
    if not pinfo then return end

    if settings.combat and pinfo.status ~= 1 then return end

    if settings.locked and not pinfo.target_locked then return end

    if not pinfo.target_index or pinfo.target_index == 0 then return end

    local self_vector = windower.ffxi.get_mob_by_index(pinfo.index or 0)
    if not self_vector then return end

    local target = windower.ffxi.get_mob_by_index(pinfo.target_index)
    if not target or target.id == 0 then return end
    if target.spawn_type == 16 and target.hpp and target.hpp <= 0 then return end

    local desired = desired_facing_direction(self_vector, target)
    if not desired then return end

    local current = self_vector.facing or self_vector.heading or 0
    local delta = math.abs(norm_pi(desired - current))
    if delta < MIN_DELTA then return end

    windower.ffxi.turn(desired)
    last_turn_t = t
end)