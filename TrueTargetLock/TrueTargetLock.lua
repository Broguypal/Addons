_addon.name    = 'TrueTargetLock'
_addon.author  = 'Broguypal'
_addon.version = '1.1'
_addon.commands = {'truetargetlock'}

-- Throttle settings (edit here if desired)
local TURN_INTERVAL = 0.10     -- seconds between turn attempts
local MIN_DELTA     = 0.05     -- radians (~2.9°); must be off by this much to turn

local last_turn_t = 0

local config = require('config')

local defaults = {
    mode = 'normal', -- 'normal' or 'always'
}

local settings = config.load(defaults)
local MODE = settings.mode

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

windower.register_event('addon command', function(cmd)
    cmd = cmd and cmd:lower() or ''

    if cmd == 'always' then
        MODE = 'always'
        settings.mode = MODE
        config.save(settings)
        windower.add_to_chat(207, '[TrueTargetLock] Mode: ALWAYS. **You cannot turn away while engaged.**')
    elseif cmd == 'normal' then
        MODE = 'normal'
        settings.mode = MODE
        config.save(settings)
        windower.add_to_chat(207, '[TrueTargetLock] Mode: NORMAL (Default).')
    else
        windower.add_to_chat(207, '[TrueTargetLock] Commands: //truetargetlock always  |  //truetargetlock normal')
        windower.add_to_chat(207, '[TrueTargetLock] Current mode: '..MODE)
    end
end)

windower.register_event('prerender', function()
    local t = os.clock()
	
    if (t - last_turn_t) < TURN_INTERVAL then return end

    local pinfo = windower.ffxi.get_player()
    if not pinfo then return end

    if pinfo.status ~= 1 then return end

    if MODE == 'normal' and not pinfo.target_locked then return end

    if not pinfo.target_index or pinfo.target_index == 0 then return end

    local self_vector = windower.ffxi.get_mob_by_index(pinfo.index or 0)
    if not self_vector then return end

    local target = windower.ffxi.get_mob_by_index(pinfo.target_index)
    if not target or target.id == 0 then return end
    if target.hpp and target.hpp <= 0 then return end

    local desired = desired_facing_direction(self_vector, target)
    if not desired then return end

    local current = self_vector.facing or self_vector.heading or 0
    local delta = math.abs(norm_pi(desired - current))
    if delta < MIN_DELTA then return end

    windower.ffxi.turn(desired)
    last_turn_t = t
end)

