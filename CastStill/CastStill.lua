--[[
Copyright © 2026 Broguypal

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

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

-- CastStill - holds movement-interruptible actions until the client reports the
-- same position twice (two matching 0x015 packets), or until a short timeout
-- expires, whichever comes first. Nothing is synthesized, only delayed.

_addon.name     = 'CastStill'
_addon.author   = 'Broguypal'
_addon.version  = '1.2.1'

require('pack')
local res = require('resources')

local recent_window  = 1.25
local stop_window    = 0.35
local bypass_window  = 1.50
local st_window      = 30.00
local probe_interval = 10.00
local probe_timeout  = 1.50
local auto_order     = true

local cs = {
    last_reported   = nil,
    last_move_time  = -999,
    is_settled      = true,

    pending         = nil,
    pending_time    = 0,
    bypass_until    = 0,
    st_until        = 0,

    gs_present      = false,
    gs_probe_until  = nil,
    gs_probe_reload = false,
    gs_next_probe   = 0,
}

local function get_pos()
    local info = windower.ffxi.get_info()
    if not info or not info.logged_in or info.loading then return nil end
    local p = windower.ffxi.get_player()
    if not p or not p.index then return nil end
    local me = windower.ffxi.get_mob_by_index(p.index)
    if me and me.x and me.y then
        return { x = me.x, y = me.y }
    end
    return nil
end

local function same_pos(p1, p2)
    if not p1 or not p2 then return false end
    return p1.x == p2.x and p1.y == p2.y
end

local function recently_moving()
    return (os.clock() - cs.last_move_time) <= recent_window
end

local function server_knows_pos()
    if not cs.last_reported then return false end
    return same_pos(get_pos(), cs.last_reported)
end

local function should_gate()
    if os.clock() < cs.bypass_until then return false end
    if not recently_moving() or cs.is_settled then return false end
    return true
end

local function token_for_id(id)
    local player = windower.ffxi.get_player()
    if player and player.id == id then
        return '<me>'
    end

    local t = windower.ffxi.get_mob_by_target('t')
    if t and t.id == id then
        return '<t>'
    end

    local mob = windower.ffxi.get_mob_by_id(id)
    if mob and not mob.is_npc and mob.name and mob.name ~= '' then
        return mob.name
    end

    return nil
end

local function command_from_packet(id, data)
    if id == 0x01A then
        local target   = data:unpack('I', 5)
        local category = data:unpack('H', 11)
        local param    = data:unpack('H', 13)

        local token = token_for_id(target)
        if not token then return nil end

        if category == 3 then
            local spell = res.spells[param]
            if not spell or not spell.name then return nil end
            return (spell.prefix or '/ma') .. ' "' .. spell.name .. '" ' .. token
        end

        if category == 16 then
            return '/ra ' .. token
        end

        return nil
    end

    if id == 0x037 then
        local target = data:unpack('I', 5)
        local slot   = data:unpack('B', 15)
        local bag    = data:unpack('B', 17)

        local token = token_for_id(target)
        if not token then return nil end

        local item = windower.ffxi.get_items(bag, slot)
        if not item or not item.id or item.id == 0 then return nil end

        local info = res.items[item.id]
        if not info or not info.name then return nil end

        return '/item "' .. info.name .. '" ' .. token
    end

    return nil
end

local function fire_pending()
    local p = cs.pending
    cs.pending = nil

    local info = windower.ffxi.get_info()
    if not info or not info.logged_in or info.loading then return end

    local cmd = p.cmd
    if cmd and p.target and cmd:find('<t>', 1, true) then
        local t = windower.ffxi.get_mob_by_target('t')
        if not t or t.id ~= p.target then
            cmd = nil
        end
    end

    cs.bypass_until = os.clock() + bypass_window

    if cmd then
        windower.send_command('input ' .. cmd)
    elseif p.data then
        windower.packets.inject_outgoing(p.id, p.data)
    end
end

local function track_position(data)
    local now = os.clock()
    local new_pos = { x = data:unpack('f', 5), y = data:unpack('f', 13) }

    if cs.last_reported then
        if same_pos(cs.last_reported, new_pos) then
            cs.is_settled = true
        else
            cs.last_move_time = now
            cs.is_settled = false
        end
    end

    cs.last_reported = new_pos
end

local gated_text_prefixes = {
    ['/ma']           = true,
    ['/magic']        = true,
    ['/nin']          = true,
    ['/ninjutsu']     = true,
    ['/so']           = true,
    ['/song']         = true,
    ['/item']         = true,
    ['/ra']           = true,
    ['/range']        = true,
    ['/rangedattack'] = true,
    ['/throw']        = true,
    ['/shoot']        = true,
}

-- '' rather than true: a line blocked with true still reaches addons that don't
-- check the flag
windower.register_event('outgoing text', function(original, modified, blocked)
    if blocked == true then return end

    local line = modified
    if type(line) ~= 'string' or line:sub(1, 1) ~= '/' then return end

    local cmd = line:match('^(%S+)')
    if not cmd or not gated_text_prefixes[cmd:lower()] then return end

    if line:find('<st') then
        cs.st_until = os.clock() + st_window
        return
    end

    if os.clock() < cs.st_until then
        cs.st_until = 0
        return
    end

    -- these lines often carry a numeric target id. gearswap parses those, the
    -- client doesn't, so with no gearswap to replay to we gate the packet
    if not cs.gs_present then return end
    if not should_gate() then return end

    if cs.pending then
        return ''
    end

    cs.pending = { cmd = line }
    cs.pending_time = os.clock()
    return ''
end)

local function packet_is_gated(id, data)
    if id == 0x037 then return true end
    if id == 0x01A then
        local category = data:unpack('H', 11)
        return category == 3 or category == 16
    end
    return false
end

windower.register_event('outgoing chunk', function(id, original, modified, injected, blocked)
    if id == 0x015 then
        track_position(original)
        return
    end

    if blocked then return end
    if not packet_is_gated(id, modified) then return end

    if os.clock() < cs.bypass_until then
        cs.bypass_until = 0
        return
    end

    if not should_gate() then return end

    if cs.pending then
        return true
    end

    -- injected means precast already ran
    local cmd
    if not injected and cs.gs_present then
        cmd = command_from_packet(id, modified)
    end

    cs.pending = {
        cmd    = cmd,
        id     = id,
        data   = modified,
        target = modified:unpack('I', 5),
    }
    cs.pending_time = os.clock()
    return true
end)

-- polled, not one-shot: gearswap can come and go mid-session and it picks the
-- replay path. a bare 'gearswap' is a no-op for a loaded gearswap
windower.register_event('unhandled command', function(cmd)
    if cs.gs_probe_until and cmd and cmd:lower() == 'gearswap' then
        cs.gs_probe_until = nil
        cs.gs_probe_reload = false
        cs.gs_present = false
        return true
    end
end)

windower.register_event('prerender', function()
    if cs.gs_probe_until then
        if os.clock() >= cs.gs_probe_until then
            cs.gs_probe_until = nil
            cs.gs_present = true
            -- windower dispatches in load order and gearswap eats the line, so
            -- it has to sit behind us
            if cs.gs_probe_reload then
                cs.gs_probe_reload = false
                windower.add_to_chat(8, 'CastStill: GearSwap is loaded, reloading it so CastStill intercepts first.')
                windower.send_command('lua reload gearswap')
            end
        end
    elseif os.clock() >= cs.gs_next_probe then
        local info = windower.ffxi.get_info()
        if info and not info.loading then
            cs.gs_next_probe  = os.clock() + probe_interval
            cs.gs_probe_until = os.clock() + probe_timeout
            windower.send_command('gearswap')
        end
    end

    if not cs.pending then return end

    if (os.clock() - cs.pending_time) >= stop_window then
        fire_pending()
        return
    end

    if cs.is_settled and server_knows_pos() then
        fire_pending()
    end
end)

windower.register_event('zone change', function()
    cs.pending        = nil
    cs.last_reported  = nil
    cs.last_move_time = -999
    cs.is_settled     = true
    cs.st_until       = 0
end)

windower.register_event('load', function()
    windower.add_to_chat(8, 'CastStill v' .. _addon.version .. ' loaded.')
    cs.gs_probe_reload = auto_order
        and windower.file_exists(windower.addon_path .. '../GearSwap/GearSwap.lua')
    cs.gs_next_probe = os.clock() + 0.5
end)