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

_addon.name    = 'Hivemind'
_addon.author  = 'Broguypal + Frodobald'
_addon.version = '1.0.4'
_addon.command = 'hivemind'

local packets = require('packets')
local config  = require('config')

----------------------------------------------------------------------
-- USER CONFIG
----------------------------------------------------------------------
local defaults = {
    reply_bind          = '!r',      -- keybind for reply cycling (! = Alt, ^ = Ctrl, @ = Win)
    ls_bind             = '!l',      -- keybind for linkshell cycling (! = Alt, ^ = Ctrl, @ = Win)
    max_reply           = 12,        -- max unique targets to cycle through
    heartbeat_interval  = 120,       -- seconds between heartbeat broadcasts
    presence_timeout    = 360,       -- consider offline after 6 min without heartbeat
    ls_enabled          = true,      -- toggle with: //hivemind linkshell [on|off]
}
local settings = config.load(defaults)

----------------------------------------------------------------------
-- INTERNALS
----------------------------------------------------------------------
local MY_NAME             = nil
local reply_list          = {}
local reply_index         = 0
local ls_target_list      = {}
local ls_reply_index      = 0
local seen_ls             = {}
local pending_ls          = {}
local last_heartbeat      = 0
local online_chars        = {}
local heartbeat_reply_pending = false
local active              = false
local input_text          = nil
local input_scheduled     = false

local RELAY_DELAY    = .75
local DEDUP_WINDOW   = 3
local SEEN_TTL       = 10
local PRUNE_INTERVAL = 15

local MODE_TELL = 3
local MODE_LS1  = 5
local MODE_LS2  = 27

local COLORS = { tell=4, ls1=6, ls2=213, info=167 }

----------------------------------------------------------------------
-- UTILS
----------------------------------------------------------------------
local function escape(s) return tostring(s):gsub('|', '<<PIPE>>') end
local function unescape(s) return tostring(s):gsub('<<PIPE>>', '|') end

----------------------------------------------------------------------
-- IPC
--
-- Message format: sender_char|mode|other_player|message
--
-- mode values:
--   tell_in    = incoming tell
--   tell_out   = outgoing tell
--   ls1        = linkshell 1 message
--   ls2        = linkshell 2 message
--   login      = character came online
--   heartbeat  = presence keepalive
--   logout     = character went offline
----------------------------------------------------------------------
local function broadcast(mode, other_player, message)
    if not MY_NAME or not mode or not other_player or not message or #message == 0 then return end
    local ipc_msg = string.format('%s|%s|%s|%s', escape(MY_NAME), escape(mode), escape(other_player), escape(message))
    windower.send_ipc_message(ipc_msg)
end

----------------------------------------------------------------------
-- PRESENCE TRACKING
----------------------------------------------------------------------
local function prune_presence()
    local now = os.time()
    local fresh = {}
    for name, last_seen in pairs(online_chars) do
        if name == MY_NAME or (now - last_seen) < settings.presence_timeout then
            fresh[name] = last_seen
        end
    end
    online_chars = fresh
end

local function get_online_ls_chars()
    local chars = {}
    local seen = {}

    table.insert(chars, { char = MY_NAME, mode = 'ls1' })
    table.insert(chars, { char = MY_NAME, mode = 'ls2' })
    seen[MY_NAME] = true

    for name, _ in pairs(online_chars) do
        if not seen[name] then
            seen[name] = true
            table.insert(chars, { char = name, mode = 'ls1' })
            table.insert(chars, { char = name, mode = 'ls2' })
        end
    end

    return chars
end

local function is_char_online(char_name)
    if char_name == MY_NAME then return true end
    local last_seen = online_chars[char_name]
    if not last_seen then return false end
    return (os.time() - last_seen) < settings.presence_timeout
end

----------------------------------------------------------------------
-- TARGET MANAGEMENT
----------------------------------------------------------------------
local function push_reply_target(char_name, sender_name)
    for i = #reply_list, 1, -1 do
        if reply_list[i].sender == sender_name then table.remove(reply_list, i) end
    end
    table.insert(reply_list, 1, { char = char_name, sender = sender_name })
    while #reply_list > settings.max_reply do table.remove(reply_list) end
    reply_index = 0
end

local function push_ls_target(char_name, mode)
    for i = #ls_target_list, 1, -1 do
        if ls_target_list[i].char == char_name and ls_target_list[i].mode == mode then
            table.remove(ls_target_list, i)
        end
    end
    table.insert(ls_target_list, 1, { char = char_name, mode = mode })
    while #ls_target_list > settings.max_reply do table.remove(ls_target_list) end
    ls_reply_index = 0
end

----------------------------------------------------------------------
-- DEDUPLICATION
----------------------------------------------------------------------
local function ls_hash(mode, other_player, message)
    return mode .. '|' .. other_player .. '|' .. message
end

local function ls_seen_recently(hash)
    local ts = seen_ls[hash]
    return ts and (os.clock() - ts) < DEDUP_WINDOW
end

local function mark_ls_seen(hash)
    seen_ls[hash] = os.clock()
end

----------------------------------------------------------------------
-- DISPLAY & REPLIES
----------------------------------------------------------------------
local function relay_ls(entry)
    pending_ls[entry.hash] = nil
    if not active or not MY_NAME then return end
    if ls_seen_recently(entry.hash) then return end
    mark_ls_seen(entry.hash)

    local display, color
    if entry.mode == 'ls1' then
        display = string.format('[%s][LS1] %s: %s', entry.sender, entry.other_player, entry.message)
        color = COLORS.ls1
        push_ls_target(entry.sender, 'ls1')
    else
        display = string.format('[%s][LS2] %s: %s', entry.sender, entry.other_player, entry.message)
        color = COLORS.ls2
        push_ls_target(entry.sender, 'ls2')
    end

    windower.add_to_chat(color, display)
end

local function show_relayed_message(sender_char, mode, other_player, message)
    if mode == 'tell_out' then
        windower.add_to_chat(COLORS.tell, string.format('[%s] >> %s : %s', sender_char, other_player, message))
        return
    end

    if mode == 'tell_in' then
        windower.add_to_chat(COLORS.tell, string.format('[%s] %s >> %s', sender_char, other_player, message))
        push_reply_target(sender_char, other_player)
        return
    end

    if not settings.ls_enabled then return end
    if mode ~= 'ls1' and mode ~= 'ls2' then return end

    local hash = ls_hash(mode, other_player, message)
    if pending_ls[hash] then return end
    if ls_seen_recently(hash) then return end

    pending_ls[hash] = true
    local entry = {
        hash = hash,
        sender = sender_char,
        mode = mode,
        other_player = other_player,
        message = message,
    }
    coroutine.schedule(function() relay_ls(entry) end, RELAY_DELAY)
end

local function open_input(text)
    input_text = text
    if input_scheduled then return end
    input_scheduled = true
    windower.send_command('keyboard_type / ')
    coroutine.schedule(function()
        local text_to_set = input_text
        input_text = nil
        input_scheduled = false
        if text_to_set then windower.chat.set_input(text_to_set) end
    end, 0.1)
end

local function cycle_reply()
    local online = {}
    for _, entry in ipairs(reply_list) do
        if entry.char == MY_NAME or is_char_online(entry.char) then
            table.insert(online, entry)
        end
    end
    if #online == 0 then windower.add_to_chat(COLORS.info, '[Hivemind] No tells in memory.') return end
    reply_index = (reply_index % #online) + 1
    local entry = online[reply_index]
    local text = (entry.char == MY_NAME) and ('/tell ' .. entry.sender .. ' ') or ('//send ' .. entry.char .. ' /tell ' .. entry.sender .. ' ')
    open_input(text)
end

local function cycle_ls_reply()
    if not settings.ls_enabled then windower.add_to_chat(COLORS.info, '[Hivemind] Linkshell monitoring is disabled.') return end

    local all_online = get_online_ls_chars()
    if #all_online == 0 then windower.add_to_chat(COLORS.info, '[Hivemind] No online characters with linkshell access.') return end

    local ordered = {}
    local added = {}

    for _, target in ipairs(ls_target_list) do
        local key = target.char .. '|' .. target.mode
        if not added[key] then
            for _, online in ipairs(all_online) do
                if online.char == target.char and online.mode == target.mode then
                    table.insert(ordered, target)
                    added[key] = true
                    break
                end
            end
        end
    end

    local default_order = {}

    for _, entry in ipairs(all_online) do
        if entry.char == MY_NAME then
            local key = entry.char .. '|' .. entry.mode
            if not added[key] then
                table.insert(default_order, entry)
                added[key] = true
            end
        end
    end

    for _, entry in ipairs(all_online) do
        local key = entry.char .. '|' .. entry.mode
        if not added[key] then
            table.insert(default_order, entry)
            added[key] = true
        end
    end

    for _, entry in ipairs(default_order) do
        table.insert(ordered, entry)
    end

    if #ordered == 0 then windower.add_to_chat(COLORS.info, '[Hivemind] No online characters with linkshell access.') return end

    ls_reply_index = (ls_reply_index % #ordered) + 1
    local target = ordered[ls_reply_index]
    local slash = (target.mode == 'ls1') and '/l ' or '/l2 '
    local text = (target.char == MY_NAME) and slash or ('//send ' .. target.char .. ' ' .. slash)
    open_input(text)
end

----------------------------------------------------------------------
-- IPC MESSAGE HANDLER
----------------------------------------------------------------------
windower.register_event('ipc message', function(raw)
    if not MY_NAME then return end

    local sender, mode, other_player, message = raw:match('^([^|]*)|([^|]*)|([^|]*)|(.+)$')
    if not sender then return end
    sender, mode, other_player, message = unescape(sender), unescape(mode), unescape(other_player), unescape(message)

    if sender == MY_NAME then return end

    if mode == 'login' or mode == 'heartbeat' then
        online_chars[sender] = os.time()
        if mode == 'login' and not heartbeat_reply_pending then
            heartbeat_reply_pending = true
            coroutine.schedule(function()
                broadcast('heartbeat', MY_NAME, 'alive')
                heartbeat_reply_pending = false
            end, 0.5)
        end
        return
    elseif mode == 'logout' then
        online_chars[sender] = nil
        return
    end

    if mode == 'tell_in' or mode == 'tell_out' or mode == 'ls1' or mode == 'ls2' then
        show_relayed_message(sender, mode, other_player, message)
    end
end)

----------------------------------------------------------------------
-- 0x0B6 Outgoing Chat
----------------------------------------------------------------------
windower.register_event('outgoing chunk', function(id, data)
    if not MY_NAME then return end

    if id == 0x0B6 then
        local p = packets.parse('outgoing', data)
        local target = (p['Target Name'] or p['target_name'] or 'Unknown'):gsub('%z', ''):trim()
        local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()
        reply_index = 0
        broadcast('tell_out', target, msg)

    elseif id == 0x0B5 then
        if not settings.ls_enabled then return end
        local mode = data:byte(5)
        if mode ~= MODE_LS1 and mode ~= MODE_LS2 then return end

        local p = packets.parse('outgoing', data)
        local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()
        if #msg == 0 then return end

        local ls_mode = (mode == MODE_LS1) and 'ls1' or 'ls2'
        push_ls_target(MY_NAME, ls_mode)
        mark_ls_seen(ls_hash(ls_mode, MY_NAME, msg))
        broadcast(ls_mode, MY_NAME, msg)
    end
end)

----------------------------------------------------------------------
-- 0x017 Incoming Chat
----------------------------------------------------------------------
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x017 or not MY_NAME then return end

    local mode = data:byte(5)
    if mode ~= MODE_TELL and mode ~= MODE_LS1 and mode ~= MODE_LS2 then return end
    if mode ~= MODE_TELL and not settings.ls_enabled then return end

    local p = packets.parse('incoming', data)
    local sender = (p['Sender Name'] or p['sender_name'] or ''):gsub('%z', ''):trim()
    local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()

    if mode == MODE_TELL then
        push_reply_target(MY_NAME, sender)
        broadcast('tell_in', sender, msg)
        return
    end

    local ls_mode = (mode == MODE_LS1) and 'ls1' or 'ls2'
    if sender == '' or sender == 'Unknown' then sender = MY_NAME end
    local hash = ls_hash(ls_mode, sender, msg)

    push_ls_target(MY_NAME, ls_mode)

    if sender ~= MY_NAME then
        mark_ls_seen(hash)
        broadcast(ls_mode, sender, msg)
    else
        local known = seen_ls[hash] ~= nil
        mark_ls_seen(hash)
        if not known then broadcast(ls_mode, MY_NAME, msg) end
    end
end)

----------------------------------------------------------------------
-- COMMANDS
----------------------------------------------------------------------
windower.register_event('addon command', function(...)
    local args = {...}
    if not args[1] then return end
    local cmd = args[1]:lower()
    if cmd == 'reply' then cycle_reply()
    elseif cmd == 'lsreply' then cycle_ls_reply()
    elseif cmd == 'linkshell' or cmd == 'ls' then
        local arg = args[2] and args[2]:lower() or nil
        if arg == 'on' then
            settings.ls_enabled = true
            settings:save()
            windower.add_to_chat(COLORS.info, '[Hivemind] Linkshell monitoring enabled.')
        elseif arg == 'off' then
            settings.ls_enabled = false
            settings:save()
            seen_ls = {}
            pending_ls = {}
            windower.add_to_chat(COLORS.info, '[Hivemind] Linkshell monitoring disabled.')
        else
            local status = settings.ls_enabled and 'enabled' or 'disabled'
            windower.add_to_chat(COLORS.info, '[Hivemind] Linkshell monitoring is currently ' .. status .. '. Usage: //hivemind linkshell [on|off]')
        end
    elseif cmd == 'help' then
        windower.add_to_chat(COLORS.info, '[Hivemind] Commands:')
        windower.add_to_chat(COLORS.info, '  //hivemind reply         - Cycle tell reply targets')
        windower.add_to_chat(COLORS.info, '  //hivemind lsreply       - Cycle linkshell reply targets')
        windower.add_to_chat(COLORS.info, '  //hivemind linkshell [on|off] - Toggle linkshell monitoring (saved per character)')
        windower.add_to_chat(COLORS.info, '  //hivemind help          - Show this help')
    end
end)

----------------------------------------------------------------------
-- MAINTENANCE & INIT
----------------------------------------------------------------------
local maintenance
maintenance = function()
    if not active then return end

    coroutine.schedule(maintenance, PRUNE_INTERVAL)

    local ok, err = pcall(function()
        local now_clock = os.clock()
        local fresh = {}
        for hash, ts in pairs(seen_ls) do
            if (now_clock - ts) <= SEEN_TTL then fresh[hash] = ts end
        end
        seen_ls = fresh

        if MY_NAME then
            prune_presence()
            local now = os.time()
            if now - last_heartbeat >= settings.heartbeat_interval then
                last_heartbeat = now
                online_chars[MY_NAME] = now
                broadcast('heartbeat', MY_NAME, 'alive')
            end
        end
    end)

    if not ok then
        windower.add_to_chat(COLORS.info, '[Hivemind] maintenance error: ' .. tostring(err))
    end
end

local function setup(name)
    MY_NAME = name

    reply_list          = {}
    reply_index         = 0
    ls_target_list      = {}
    ls_reply_index      = 0
    seen_ls             = {}
    pending_ls          = {}
    input_text          = nil
    input_scheduled     = false

    windower.send_command('bind ' .. settings.reply_bind .. ' hivemind reply')
    windower.send_command('bind ' .. settings.ls_bind .. ' hivemind lsreply')

    online_chars[MY_NAME] = os.time()
    last_heartbeat = os.time()

    broadcast('login', MY_NAME, 'online')
end

windower.register_event('load', function()
    active = true
    coroutine.schedule(maintenance, PRUNE_INTERVAL)
    local p = windower.ffxi.get_player()
    if p then setup(p.name) end
end)

windower.register_event('login', function(name) setup(name) end)

windower.register_event('logout', function()
    if MY_NAME then
        broadcast('logout', MY_NAME, 'offline')
        online_chars[MY_NAME] = nil
        MY_NAME = nil
    end
    seen_ls    = {}
    pending_ls = {}
end)

windower.register_event('unload', function()
    active = false
    if MY_NAME then
        broadcast('logout', MY_NAME, 'offline')
        online_chars[MY_NAME] = nil
    end
    windower.send_command('unbind ' .. settings.reply_bind)
    windower.send_command('unbind ' .. settings.ls_bind)
end)
