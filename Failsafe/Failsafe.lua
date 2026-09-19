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

_addon.name    = 'Failsafe'
_addon.author  = 'Broguypal'
_addon.version = '1.0.0'

require('pack')
local res = require('resources')

local max_attempts = 3
local retry_delay  = 1.10
local echo_timeout = 1.00

local wait_messages = {[17] = true, [87] = true, [90] = true}

local reject_lines = {
    'Unable to cast spells at this time%.',
    'Unable to use job ability%.',
    'Unable to use weapon skill%.',
    'Unable to use ranged attack%.',
    'Unable to use item%.',
    'You must wait longer to perform that action%.',
}

local kind_by_prefix = {
    ['/ma'] = 'spell',  ['/magic'] = 'spell',
    ['/nin'] = 'spell', ['/ninjutsu'] = 'spell',
    ['/so'] = 'spell',  ['/song'] = 'spell',
    ['/ws'] = 'ws',     ['/weaponskill'] = 'ws',
    ['/ja'] = 'ja',     ['/jobability'] = 'ja',  ['/pet'] = 'ja',
    ['/item'] = 'item',
    ['/ra'] = 'ranged', ['/range'] = 'ranged',   ['/rangedattack'] = 'ranged',
    ['/throw'] = 'ranged', ['/shoot'] = 'ranged',
}

local resource_by_kind = {spell = 'spells', ws = 'weapon_skills', ja = 'job_abilities'}

local resource_by_category = {
    [4]  = 'spells',        [8]  = 'spells',
    [6]  = 'job_abilities', [13] = 'job_abilities',
    [14] = 'job_abilities', [15] = 'job_abilities',
    [3]  = 'weapon_skills', [7]  = 'weapon_skills',
    [5]  = 'items',         [9]  = 'items',
}
local id_lives_in_target = {[7] = true, [8] = true, [9] = true}
local kind_by_resource = {spells = 'spell', job_abilities = 'ja',
                          weapon_skills = 'ws', items = 'item'}

local job  = nil
local echo = nil

local lookups = {}
local function ability_id(kind, name)
    local resource = resource_by_kind[kind]
    if not resource or not name then return nil end

    if not lookups[resource] then
        local tbl = {}
        for _, entry in pairs(res[resource]) do
            if type(entry) == 'table' and entry.en then tbl[entry.en:lower()] = entry.id end
        end
        lookups[resource] = tbl
    end
    return lookups[resource][name:lower()]
end

local function identify(line)
    local prefix = line:match('^(%S+)')
    if not prefix then return nil end

    local kind = kind_by_prefix[prefix:lower()]
    if not kind then return nil end

    local rest = line:match('^%S+%s+(.+)$')
    if not rest then return kind, nil end

    local name = rest:match('^"([^"]+)"')
    if not name then
        name = rest:gsub('%s*<%S+>%s*$', ''):gsub('%s+%d+%s*$', ''):gsub('%s+$', '')
    end

    return kind, ability_id(kind, name)
end

local function on_refused()
    if not job or job.fire_at then return end

    if job.attempts >= max_attempts then
        job = nil
        return
    end

    job.fire_at = os.clock() + retry_delay
end

windower.register_event('outgoing text', function(original, modified, blocked)
    local line = type(modified) == 'string' and modified or original
    if type(line) ~= 'string' or line:sub(1, 1) ~= '/' then return end

    local prefix = line:match('^(%S+)')
    if not prefix or not kind_by_prefix[prefix:lower()] then return end

    if echo and line == echo.cmd and os.clock() < echo.deadline then
        echo = nil
        return
    end

    if line:find('<st') then return end

    local kind, id = identify(line)
    if not kind then return end

    job = {cmd = line, kind = kind, id = id, attempts = 1}
end)

windower.register_event('incoming chunk', function(id, original, modified, injected, blocked)
    if id ~= 0x029 or type(original) ~= 'string' or #original < 26 then return end
    if not job then return end

    local p = windower.ffxi.get_player()
    if not p then return end

    local actor   = original:unpack('I', 0x05)
    local target  = original:unpack('I', 0x09)
    local message = original:unpack('H', 0x19) % 32768
    if actor ~= p.id and target ~= p.id then return end

    if wait_messages[message] then on_refused() end
end)

windower.register_event('incoming text', function(original, modified, mode, modified_mode, blocked)
    if blocked or not job then return end

    local line = type(modified) == 'string' and modified or original
    if type(line) ~= 'string' then return end

    for _, pattern in ipairs(reject_lines) do
        if line:find(pattern) then
            on_refused()
            return
        end
    end
end)

windower.register_event('action', function(act)
    if not job then return end

    local p = windower.ffxi.get_player()
    if not p or act.actor_id ~= p.id then return end

    if job.kind == 'ranged' and (act.category == 2 or act.category == 12) then
        job = nil
        return
    end

    local resource = resource_by_category[act.category]
    if not resource or kind_by_resource[resource] ~= job.kind then return end

    local id
    if id_lives_in_target[act.category] then
        local t = act.targets and act.targets[1]
        local a = t and t.actions and t.actions[1]
        id = a and a.param
    else
        id = act.param
    end

    if id and job.id and id == job.id then job = nil end
end)

windower.register_event('prerender', function()
    local now = os.clock()

    if echo and now > echo.deadline then echo = nil end

    if not job or not job.fire_at or now < job.fire_at then return end

    job.fire_at = nil
    job.attempts = job.attempts + 1
    echo = {cmd = job.cmd, deadline = now + echo_timeout}

    windower.send_command('input ' .. job.cmd)
end)

windower.register_event('zone change', function() job = nil; echo = nil end)
windower.register_event('logout', function() job = nil; echo = nil end)
