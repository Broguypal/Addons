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

_addon.name = 'Vanish'
_addon.author = 'Broguypal'
_addon.version = '2.0.0'
_addon.commands = {'vanish', 'van'}

require('logger')
require('strings')

local config = require('config')

local addon_path = windower.addon_path:gsub('\\', '/')
package.cpath = package.cpath .. ';' .. addon_path .. '/libs/?.dll'

local loaded, load_error = pcall(require, '_Vanish')

local settings = config.load({
    mode      = 'vanish',
    blacklist = '',
    whitelist = '',
    keybind   = '!space',
})

local MODE_ID = {vanish = 1, vanishga = 2}
local CYCLE = {vanish = 'vanishga', vanishga = 'vanish'}
local REFRESH_INTERVAL = 0.25

local blacklist = {}
local whitelist = {}
local mode = 'vanish'
local keybind = ''
local last_refresh = 0

local function available()
    return loaded and _Vanish ~= nil
end

local function titlecase(name)
    return (name:gsub('^%l', string.upper))
end

local function parse_list(raw)
    if type(raw) == 'table' then raw = table.concat(raw, ',') end
    if type(raw) ~= 'string' then raw = '' end

    local set = {}
    for entry in raw:gmatch('[^,]+') do
        local key = entry:trim():lower()
        if key ~= '' then set[key] = true end
    end

    return set
end

local function sorted(set)
    local list = {}
    for name in pairs(set) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local function list_for(which)
    if which == 'blacklist' then return blacklist, 'blacklist', 'vanish' end
    if which == 'whitelist' then return whitelist, 'whitelist', 'vanishga' end
    if mode == 'vanish' then return blacklist, 'blacklist', 'vanish' end
    return whitelist, 'whitelist', 'vanishga'
end

local function push_policy()
    if not available() then return end

    local set = mode == 'vanish' and blacklist or whitelist
    _Vanish.names(table.concat(sorted(set), ','))
    _Vanish.mode(MODE_ID[mode])
end

local function push_exempt()
    if not available() then return end

    local indices = {}
    local self_index = 0

    local me = windower.ffxi.get_player()
    if me and me.index then
        self_index = me.index
        indices[#indices + 1] = tostring(me.index)
    end

    local party = windower.ffxi.get_party()
    if party then
        for key, member in pairs(party) do
            if type(member) == 'table' and type(key) == 'string'
               and (key:match('^p%d$') or key:match('^a%d%d$')) then
                local index = member.mob and member.mob.index
                if index and index > 0 then
                    indices[#indices + 1] = tostring(index)
                end
            end
        end
    end

    _Vanish.exempt(table.concat(indices, ','), self_index)
end

local function persist()
    settings.mode = mode
    settings.blacklist = table.concat(sorted(blacklist), ',')
    settings.whitelist = table.concat(sorted(whitelist), ',')
    config.save(settings, 'all')
end

local function describe_mode()
    if mode == 'vanish' then
        return 'Vanish mode: the blacklist is hidden.'
    end

    return 'Vanishga mode: only the whitelist, your party and your alliance are drawn.'
end

local function set_mode(next_mode)
    mode = next_mode
    push_policy()
    push_exempt()
    persist()
    log(describe_mode())
end

local function add_name(which, name)
    if name == '' then
        error('Usage: //vanish add <name>')
        return
    end

    local set, label, owner = list_for(which)
    local key = name:lower()
    local me = windower.ffxi.get_player()

    if me and me.name and me.name:lower() == key then
        error('Refusing to blacklist yourself.')
        return
    end

    if set[key] then
        log(titlecase(name) .. ' is already on the ' .. label .. '.')
        return
    end

    set[key] = true
    push_policy()
    persist()

    if mode == owner then
        log('Added ' .. titlecase(name) .. ' to the ' .. label
            .. (owner == 'vanish' and '. Hidden now.' or '. Visible now.'))
    else
        log('Added ' .. titlecase(name) .. ' to the ' .. label
            .. '. Takes effect in ' .. owner .. ' mode.')
    end
end

local function remove_name(which, name)
    if name == '' then
        error('Usage: //vanish remove <name>')
        return
    end

    local set, label = list_for(which)
    local key = name:lower()

    if not set[key] then
        log(titlecase(name) .. ' is not on the ' .. label .. '.')
        return
    end

    set[key] = nil
    push_policy()
    persist()
    log('Removed ' .. titlecase(name) .. ' from the ' .. label .. '.')
end

local function show_lists()
    log(describe_mode())

    local black = sorted(blacklist)
    local white = sorted(whitelist)

    log('Blacklist (' .. #black .. ')' .. (mode == 'vanish' and ' <- active' or '') .. ':')
    if #black == 0 then
        log('  empty')
    else
        for _, name in ipairs(black) do log('  ' .. titlecase(name)) end
    end

    log('Whitelist (' .. #white .. ')' .. (mode == 'vanishga' and ' <- active' or '') .. ':')
    if #white == 0 then
        log('  empty')
    else
        for _, name in ipairs(white) do log('  ' .. titlecase(name)) end
    end
end

local function initialise()
    if not available() then
        log('The native module failed to load: ' .. tostring(load_error))
        log('Check that libs/_Vanish.dll sits beside Vanish.lua.')
        return
    end

    blacklist = parse_list(settings.blacklist)
    whitelist = parse_list(settings.whitelist)

    mode = tostring(settings.mode or 'vanish'):lower()
    if not MODE_ID[mode] then mode = 'vanish' end

    log(_Vanish.start())

    push_policy()
    push_exempt()

    if type(settings.keybind) == 'string' and settings.keybind ~= '' then
        keybind = settings.keybind
        windower.send_command('bind ' .. keybind .. ' vanish cycle')
    end

    log('Vanish v' .. _addon.version .. ' loaded. ' .. describe_mode())
end

windower.register_event('unload', function()
    if keybind ~= '' then
        windower.send_command('unbind ' .. keybind)
    end

    if available() then
        _Vanish.stop()
    end
end)

windower.register_event('prerender', function()
    if not available() then return end

    local now = os.clock()
    if now - last_refresh < REFRESH_INTERVAL then return end
    last_refresh = now

    push_exempt()
end)

windower.register_event('zone change', function()
    if available() then
        push_exempt()
    end
end)

windower.register_event('addon command', function(cmd, ...)
    if not available() then
        error('The native module is not loaded: ' .. tostring(load_error))
        return
    end

    cmd = (cmd or 'list'):lower()
    local args = {...}
    local rest = table.concat(args, ' '):trim()

    if MODE_ID[cmd] then
        set_mode(cmd)

    elseif cmd == 'cycle' then
        set_mode(CYCLE[mode])

    elseif cmd == 'add' then
        add_name(nil, rest)

    elseif cmd == 'remove' then
        remove_name(nil, rest)

    elseif cmd == 'blacklist' or cmd == 'whitelist' then
        local action = (args[1] or ''):lower()
        local name = table.concat(args, ' ', 2):trim()

        if action == 'add' then
            add_name(cmd, name)
        elseif action == 'remove' then
            remove_name(cmd, name)
        else
            error('Usage: //vanish ' .. cmd .. ' add|remove <name>')
        end

    elseif cmd == 'clear' then
        local set, label = list_for(nil)
        for key in pairs(set) do set[key] = nil end
        push_policy()
        persist()
        log('Cleared the ' .. label .. '.')

    elseif cmd == 'list' then
        show_lists()

    else
        log('//vanish vanish | vanishga | cycle')
        log('//vanish add <name> | remove <name>')
        log('//vanish blacklist add|remove <name>')
        log('//vanish whitelist add|remove <name>')
        log('//vanish list | clear')
    end
end)

initialise()
