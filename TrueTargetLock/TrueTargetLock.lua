_addon.name    = 'TrueTargetLock'
_addon.author  = 'Broguypal'
_addon.version = '1.0'

-- Throttle settings (edit here if desired)
local TURN_INTERVAL = 0.10     -- seconds between turn attempts
local MIN_DELTA     = 0.05     -- radians (~2.9°); must be off by this much to turn

local last_turn_t = 0

-- This function checks if the addon "react" is loaded as this already handles facing and can cause conflicts.
local function react_is_loaded()
    return _G.facemob ~= nil
end


local function norm_pi(a)
    while a > math.pi do a = a - 2*math.pi end
    while a < -math.pi do a = a + 2*math.pi end
    return a
end

local function desired_facing_react_style(self_vector, target)
    local dx = (target.x - self_vector.x)
    local dy = (target.y - self_vector.y)

    if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then
        return nil
    end

    local angle_deg = (math.atan2(dy, dx) * 180 / math.pi) * -1
    return angle_deg * (math.pi / 180)
end

windower.register_event('prerender', function()
    local t = os.clock()
	
    if react_is_loaded() then return end
	
    if (t - last_turn_t) < TURN_INTERVAL then return end

    local pinfo = windower.ffxi.get_player()
    if not pinfo then return end

    if pinfo.status ~= 1 then return end

    if not pinfo.target_locked then return end

    if not pinfo.target_index or pinfo.target_index == 0 then return end

    local self_vector = windower.ffxi.get_mob_by_index(pinfo.index or 0)
    if not self_vector then return end

    local target = windower.ffxi.get_mob_by_index(pinfo.target_index)
    if not target or target.id == 0 then return end
    if target.hpp and target.hpp <= 0 then return end

    local desired = desired_facing_react_style(self_vector, target)
    if not desired then return end

    local current = self_vector.facing or self_vector.heading or 0
    local delta = math.abs(norm_pi(desired - current))
    if delta < MIN_DELTA then return end

    windower.ffxi.turn(desired)
    last_turn_t = t
end)
