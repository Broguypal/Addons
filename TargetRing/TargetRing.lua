_addon.name = 'TargetRing'
_addon.author = 'Broguypal'
_addon.version = '3.0.0'
_addon.commands = {'tring', 'targetring'}

local addon_path = windower.addon_path:gsub('\\', '/')
package.cpath = package.cpath .. ';' .. addon_path .. '/libs/?.dll'

local loaded, load_error = pcall(require, '_TargetRing')

local HOSTILE_COLOR = 0xE6FF6A3C
local FRIENDLY_COLOR = 0xE64CC4FF
local PLAYER_FOOTPRINT = 0.64
local HUMANOID_EXTENT = 1.15

local subtarget_modes = {'st', 'stpc', 'stnpc', 'stpt', 'stal'}

local function chat(color, message)
    windower.add_to_chat(color, 'TargetRing: ' .. message)
end

local function available()
    return loaded and _TargetRing ~= nil
end

local function lookup(kind)
    local ok, mob = pcall(windower.ffxi.get_mob_by_target, kind)
    if not ok or not mob or not mob.index or not mob.id or mob.id == 0 then
        return nil
    end

    return mob
end

local function first_subtarget()
    for _, kind in ipairs(subtarget_modes) do
        local mob = lookup(kind)
        if mob then
            return mob
        end
    end

    return nil
end

local function is_hostile(mob)
    if not mob or not mob.is_npc then
        return false
    end

    if mob.in_party or mob.in_alliance or mob.charmed then
        return false
    end

    if (tonumber(mob.spawn_type) or 0) == 16 then
        return true
    end

    return mob.claim_id ~= nil and mob.claim_id ~= 0
end

-- model_size reads 0 for most green NPCs and has done for years, so fall back to
-- inverting model_scale: larger models tend to carry a smaller scale.
local function ring_radius(mob)
    if not mob or not mob.is_npc then
        return PLAYER_FOOTPRINT
    end

    local size = tonumber(mob.model_size) or 0
    local scale = tonumber(mob.model_scale) or 1
    if scale <= 0 then
        scale = 1
    end

    local extent
    if size > 0.05 then
        extent = size * scale
        if extent > HUMANOID_EXTENT then
            extent = HUMANOID_EXTENT + math.sqrt(extent - HUMANOID_EXTENT) * 0.62
        end
    else
        extent = HUMANOID_EXTENT * (0.5 / math.max(scale, 0.18))
        if extent > 3.0 then
            extent = 3.0 + math.sqrt(extent - 3.0) * 0.5
        end
    end

    local footprint = extent * 0.5
    if footprint < 0.45 then
        return 0.45
    elseif footprint > 8 then
        return 8
    end

    return footprint
end

-- The index is what lets the plugin read the live render position; the
-- coordinates are only a fallback for entities it cannot resolve.
local function submit(mob)
    if not mob then
        return
    end

    _TargetRing.add(
        tonumber(mob.index) or 0,
        tonumber(mob.x) or 0,
        tonumber(mob.y) or 0,
        tonumber(mob.z) or 0,
        ring_radius(mob),
        is_hostile(mob) and HOSTILE_COLOR or FRIENDLY_COLOR)
end

windower.register_event('load', function()
    if available() then
        _TargetRing.start()
    end
end)

windower.register_event('unload', function()
    if available() then
        _TargetRing.clear()
        _TargetRing.stop()
    end
end)

windower.register_event('addon command', function(command)
    if not available() then
        chat(167, 'the plugin module failed to load: ' .. tostring(load_error))
        return
    end

    command = command and command:lower() or 'status'

    if command == 'objects' then
        chat(207, _TargetRing.objects())
    elseif command == 'on' then
        _TargetRing.start()
        chat(207, 'enabled')
    elseif command == 'off' then
        _TargetRing.clear()
        _TargetRing.stop()
        chat(207, 'disabled')
    else
        chat(207, _TargetRing.status())
    end
end)

windower.register_event('prerender', function()
    if not available() then
        return
    end

    _TargetRing.clear()

    local target = lookup('t')
    local subtarget = first_subtarget()

    if not target and not subtarget then
        return
    end

    local player = windower.ffxi.get_player()
    if player and player.status == 4 then
        return
    end

    if target and subtarget and target.index == subtarget.index then
        subtarget = nil
    end

    submit(subtarget)
    submit(target)
end)
