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

_addon.name = 'Banish'
_addon.author = 'Broguypal'
_addon.version = '1.1.0'
_addon.commands = {'banish', 'ban'}

require('logger')
require('strings')

local config  = require('config')
local packets = require('packets')

local settings = config.load({names = ''})

local INDEX_TTL = 5

local ignored = {}
local ignored_ids = {}
local ignored_indices = {}
local index_seen = {}
local suppressed_name = {}
local roster = {}
local last_warn = {}
local last_scan = 0

local function rebuild_set()
    ignored = {}

    local raw = settings.names
    if type(raw) == 'table' then raw = table.concat(raw, ',') end
    if type(raw) ~= 'string' then raw = '' end

    for name in raw:gmatch('[^,]+') do
        name = name:trim():lower()
        if name ~= '' then ignored[name] = true end
    end
end

local function persist()
    local list = {}
    for name in pairs(ignored) do list[#list + 1] = name end
    table.sort(list)
    settings.names = table.concat(list, ',')
    config.save(settings, 'all')
end

rebuild_set()

local function is_ignored(name)
    return name ~= nil and name ~= '' and ignored[name:lower()] == true
end

local function titlecase(name)
    local shown = name:gsub('^%l', string.upper)
    return shown
end

local function safe_parse(dir, data)
    local ok, parsed = pcall(packets.parse, dir, data)
    if ok then return parsed end
    return nil
end

local function touch_index(index, id)
    if not index then return end
    ignored_indices[index] = id
    index_seen[index] = os.clock()
end

local function index_is_fresh(index)
    local seen = index_seen[index]
    return seen ~= nil and (os.clock() - seen) < INDEX_TTL
end

local function remember(id, index, lname)
    ignored_ids[id] = true
    suppressed_name[id] = lname
    touch_index(index, id)
end

local function forget(id)
    if not id then return end
    ignored_ids[id] = nil
    suppressed_name[id] = nil
    for index, eid in pairs(ignored_indices) do
        if eid == id then
            ignored_indices[index] = nil
            index_seen[index] = nil
        end
    end
end

local function despawn(id, index)
    local ok, p = pcall(packets.new, 'incoming', 0x00D, {
        ['Player']  = id,
        ['Index']   = index,
        ['Despawn'] = true,
    })
    if not ok or not p then return false end

    local built, data = pcall(packets.build, p)
    if not built or not data then return false end

    windower.packets.inject_incoming(0x00D, data)
    return true
end

local warn_line = _G.warning or error

local function warn_trade(pid, idx)
    local key = pid or idx
    if key then
        local now = os.clock()
        if last_warn[key] and now - last_warn[key] < 5 then return end
        last_warn[key] = now
    end

    local lname = pid and suppressed_name[pid]
    if not lname and idx and ignored_indices[idx] then
        lname = suppressed_name[ignored_indices[idx]]
    end

    warn_line((lname and titlecase(lname) or 'Someone on your Banish list')
        .. ' is trying to trade with you. Decline unless you are certain.')
end

local function refresh_roster()
    local new = {}

    local me = windower.ffxi.get_player()
    if me and me.name then new[me.name:lower()] = true end

    local party = windower.ffxi.get_party()
    if party then
        for _, member in pairs(party) do
            if type(member) == 'table' and member.name and member.name ~= '' then
                new[member.name:lower()] = true
            end
        end
    end

    roster = new

    for eid in pairs(ignored_ids) do
        local lname = suppressed_name[eid]
        if lname and roster[lname] then
            log(titlecase(lname) .. ' joined your party or alliance. Visible until they leave.')
            forget(eid)
        end
    end
end

local function exempt(name)
    return name ~= nil and roster[name:lower()] == true
end

local function find_mob(lname)
    local arr = windower.ffxi.get_mob_array()
    if not arr then return nil end
    for _, mob in pairs(arr) do
        if type(mob) == 'table' and mob.name and mob.is_npc == false
           and mob.name:lower() == lname then
            return mob
        end
    end
    return nil
end

windower.register_event('incoming chunk', function(id, original, _, injected, blocked)
    if blocked or injected then return end

    if id == 0x00A then
        ignored_ids = {}
        ignored_indices = {}
        index_seen = {}
        suppressed_name = {}
        last_warn = {}

    elseif id == 0x021 then
        local p = safe_parse('incoming', original)
        if p then
            local pid, idx = p['Player'], p['Index']
            if (pid and ignored_ids[pid]) or (idx and ignored_indices[idx]) then
                warn_trade(pid, idx)
            end
        end

    elseif id == 0x00D then
        local p = safe_parse('incoming', original)
        if not p then return end

        local pid, idx = p['Player'], p['Index']
        if not pid then return end

        if p['Despawn'] then
            forget(pid)
            return
        end

        if idx and ignored_indices[idx] and ignored_indices[idx] ~= pid then
            ignored_indices[idx] = nil
            index_seen[idx] = nil
        end

        if ignored_ids[pid] then
            local lname = suppressed_name[pid]
            if lname and roster[lname] then
                forget(pid)
                return
            end
            touch_index(idx, pid)
            return true
        end

        if p['Update Name'] then
            local name = p['Character Name']
            name = type(name) == 'string' and name:gsub('%z.*$', ''):trim() or nil
            if is_ignored(name) and not exempt(name) then
                remember(pid, idx, name:lower())
                return true
            end
        end
    end
end)

windower.register_event('prerender', function()
    local now = os.clock()
    if now - last_scan < 0.25 then return end
    last_scan = now

    refresh_roster()

    if next(ignored) == nil then return end

    local arr = windower.ffxi.get_mob_array()
    if not arr then return end

    for _, mob in pairs(arr) do
        if type(mob) == 'table' and mob.is_npc == false and mob.name
           and is_ignored(mob.name) and not exempt(mob.name) then
            if despawn(mob.id, mob.index) then
                remember(mob.id, mob.index, mob.name:lower())
            end
        end
    end
end)

windower.register_event('outgoing chunk', function(id, original, _, injected, blocked)
    if blocked or injected then return end
    if id ~= 0x016 then return end

    local p = safe_parse('outgoing', original)
    if not p then return end

    local idx = p['Target Index']
    if not idx or idx == 0 then return end

    local eid = ignored_indices[idx]
    if not eid or not ignored_ids[eid] then return end

    if not index_is_fresh(idx) then return end

    return true
end)

windower.register_event('addon command', function(cmd, ...)
    cmd = (cmd or ''):lower()
    local name = table.concat({...}, ' ')
    local lname = name:lower()

    if cmd == 'add' then
        local me = windower.ffxi.get_player()

        if name == '' then
            error('Usage: //banish add <name>')

        elseif me and me.name:lower() == lname then
            error('Refusing to ignore yourself.')

        elseif ignored[lname] then
            log(titlecase(name) .. ' is already on the list.')

        elseif roster[lname] then
            ignored[lname] = true
            persist()
            log('Added ' .. titlecase(name)
                .. '. In your party or alliance, so visible until they leave.')

        else
            ignored[lname] = true
            persist()

            local mob = find_mob(lname)
            if mob then
                if despawn(mob.id, mob.index) then
                    remember(mob.id, mob.index, lname)
                end
            end

            log('Now hiding ' .. titlecase(name)
                .. '. Consider /blist add ' .. titlecase(name) .. ' too.')
        end

    elseif cmd == 'remove' then
        if name == '' then
            error('Usage: //banish remove <name>')

        elseif not ignored[lname] then
            log(titlecase(name) .. ' is not on the list.')

        else
            ignored[lname] = nil
            for eid in pairs(ignored_ids) do
                if suppressed_name[eid] == lname then forget(eid) end
            end
            persist()

            log('Removed ' .. titlecase(name) .. '. Zone to make them visible again.')
        end

    elseif cmd == 'list' then
        local list = {}
        for entry in pairs(ignored) do
            list[#list + 1] = titlecase(entry) .. (roster[entry] and ' (in party)' or '')
        end
        table.sort(list)

        if #list == 0 then
            log('List is empty.')
        else
            log('Hiding ' .. #list .. ':')
            for _, entry in ipairs(list) do log('  ' .. entry) end
        end

    else
        log('//banish add <name> | remove <name> | list')
    end
end)

log('Banish v' .. _addon.version .. ' loaded.')