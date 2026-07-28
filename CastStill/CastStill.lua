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

-- CastStill - holds movement-interruptible actions until the server
-- confirms you've stopped moving (two matching 0x15 position packets).

_addon.name     = 'CastStill'
_addon.author   = 'Broguypal'
_addon.version  = '1.0'
_addon.commands = {'caststill', 'cst'}

require('pack')

caststill = caststill or {}
caststill.recent_window = caststill.recent_window or 1.25
caststill.stop_window   = caststill.stop_window   or 0.35
if caststill.auto_order == nil then caststill.auto_order = true end

local cs = {
    last_reported    = nil,
    last_move_time   = -999,
    is_settled       = true,

    pending          = nil,
    pending_time     = 0,
    bypass_until     = 0,

    gs_probe_deadline = nil,
}

local function get_pos()
    local info = windower.ffxi.get_info()
    if not info or not info.logged_in or info.loading then return nil end
    local p = windower.ffxi.get_player()
    if not p then return nil end
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
    return (os.clock() - cs.last_move_time) <= caststill.recent_window
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

-- trailing numeric target ids are gearswap-only syntax
local function normalize_target(cmd)
    local base, id = cmd:match('^(.+%S)%s+(%d+)%s*$')
    if not base then return cmd end
    id = tonumber(id)

    local player = windower.ffxi.get_player()
    if player and player.id == id then
        return base .. ' <me>'
    end

    local t = windower.ffxi.get_mob_by_target('t')
    if t and t.id == id then
        return base .. ' <t>'
    end

    local mob = windower.ffxi.get_mob_by_id(id)
    if mob and mob.name and mob.name ~= '' and not mob.name:find(' ') then
        return base .. ' ' .. mob.name
    end

    return base .. ' <t>'
end

local function fire_pending()
    cs.bypass_until = os.clock() + 0.50
    local p = cs.pending
    cs.pending = nil
    if p.kind == 'text' then
        windower.send_command('input ' .. p.cmd)
    else
        windower.packets.inject_outgoing(p.id, p.data)
        for _, eq in ipairs(p.equips) do
            windower.packets.inject_outgoing(eq.id, eq.data)
        end
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

-- suppress with '' not true; blocked lines still reach addons that ignore the flag
windower.register_event('outgoing text', function(original, modified, blocked)
    if blocked == true then return end

    local line = modified
    if type(line) ~= 'string' or line:sub(1, 1) ~= '/' then return end

    local cmd = line:match('^(%S+)')
    if not cmd or not gated_text_prefixes[cmd:lower()] then return end

    if line:find('<st') then return end
    if not should_gate() then return end

    if cs.pending then
        return ''
    end

    cs.pending = { kind = 'text', cmd = normalize_target(line) }
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

    -- hold equip packets behind a held action so midcast gear can't beat it
    if (id == 0x050 or id == 0x051) and cs.pending and cs.pending.kind == 'packet' then
        table.insert(cs.pending.equips, { id = id, data = modified })
        return true
    end

    if not packet_is_gated(id, modified) then return end
    if not should_gate() then return end

    if cs.pending then
        -- upstream addon consumed the held command; hold its packet instead
        if injected and cs.pending.kind == 'text' then
            cs.pending = { kind = 'packet', id = id, data = modified, equips = {} }
            cs.pending_time = os.clock()
        end
        return true
    end

    cs.pending = { kind = 'packet', id = id, data = modified, equips = {} }
    cs.pending_time = os.clock()
    return true
end)

-- a loaded gearswap eats a bare 'gearswap' silently; unloaded, it echoes back here
windower.register_event('unhandled command', function(cmd)
    if cs.gs_probe_deadline and cmd and cmd:lower() == 'gearswap' then
        cs.gs_probe_deadline = nil
    end
end)

windower.register_event('prerender', function()
    if cs.gs_probe_deadline and os.clock() >= cs.gs_probe_deadline then
        cs.gs_probe_deadline = nil
        windower.add_to_chat(8, 'CastStill: GearSwap is loaded, reloading it so CastStill intercepts first.')
        windower.send_command('lua reload gearswap')
    end

    if not cs.pending then return end

    if not get_pos() then
        cs.pending = nil
        return
    end

    if cs.is_settled and server_knows_pos() then
        fire_pending()
        return
    end

    if (os.clock() - cs.pending_time) >= caststill.stop_window then
        fire_pending()
    end
end)

windower.register_event('addon command', function(cmd, arg)
    cmd = cmd and cmd:lower() or 'status'
    if cmd == 'recent' and tonumber(arg) then
        caststill.recent_window = tonumber(arg)
        windower.add_to_chat(8, ('CastStill: recent_window = %.2f'):format(caststill.recent_window))
    elseif cmd == 'stop' and tonumber(arg) then
        caststill.stop_window = tonumber(arg)
        windower.add_to_chat(8, ('CastStill: stop_window = %.2f'):format(caststill.stop_window))
    else
        windower.add_to_chat(8, ('CastStill v%s | recent_window=%.2f stop_window=%.2f | settled=%s pending=%s'):format(
            _addon.version, caststill.recent_window, caststill.stop_window,
            tostring(cs.is_settled), cs.pending and cs.pending.kind or 'none'))
        windower.add_to_chat(8, 'Commands: //cst recent <sec> | //cst stop <sec> | //cst status')
    end
end)

windower.register_event('load', function()
    windower.add_to_chat(8, 'CastStill v' .. _addon.version .. ' loaded.')
    if caststill.auto_order and windower.file_exists(windower.addon_path .. '../GearSwap/GearSwap.lua') then
        windower.send_command('@wait 0.5;gearswap')
        cs.gs_probe_deadline = os.clock() + 1.5
    end
end)
