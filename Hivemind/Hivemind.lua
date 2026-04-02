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
_addon.version = '1.0'
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
local reply_list          = {}      -- unique {char, sender} for tells
local reply_index         = 0
local ls_target_list      = {}      -- unique {char, mode} for linkshells (activity-based priority)
local ls_reply_index      = 0
local recent_ls_msgs      = {}      -- deduplication {hash = timestamp}
local pending_ls_relays   = {}      -- queued LS relays awaiting dedup check
local last_heartbeat      = 0
local online_chars        = {}      -- { [char_name] = last_seen_timestamp }

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
    for name, last_seen in pairs(online_chars) do
        if name ~= MY_NAME and (now - last_seen) >= settings.presence_timeout then
            online_chars[name] = nil
        end
    end
end

local function get_online_ls_chars()
    local chars = {}
    local seen = {}

    -- Current character first
    table.insert(chars, { char = MY_NAME, mode = 'ls1' })
    table.insert(chars, { char = MY_NAME, mode = 'ls2' })
    seen[MY_NAME] = true

    -- Other online characters
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
-- DISPLAY & REPLIES
----------------------------------------------------------------------
local function show_relayed_message(sender_char, mode, other_player, message)
    local display, color
    local hash = mode .. '|' .. other_player .. '|' .. message
    local now = os.time()

    if recent_ls_msgs[hash] and (now - recent_ls_msgs[hash]) < 3 then return end

    if mode == 'tell_out' then
        recent_ls_msgs[hash] = now
        display, color = string.format('[%s] >> %s : %s', sender_char, other_player, message), COLORS.tell
    elseif mode == 'tell_in' then
        recent_ls_msgs[hash] = now
        display, color = string.format('[%s] %s >> %s', sender_char, other_player, message), COLORS.tell
        push_reply_target(sender_char, other_player)
    elseif settings.ls_enabled and (mode == 'ls1' or mode == 'ls2') then
        -- Queue LS relays; hold until either the local 0x017 sets the dedup
        -- hash (suppress) or the deadline passes with no match (show)
        table.insert(pending_ls_relays, {
            deadline = os.clock() + .75,
            sender = sender_char, mode = mode,
            other_player = other_player, message = message,
            hash = hash
        })
        return
    end

    if display then windower.add_to_chat(color, display) end
end

local function flush_pending_ls()
    local now_clock = os.clock()
    local now_time = os.time()
    local i = 1
    while i <= #pending_ls_relays do
        local p = pending_ls_relays[i]
        local dominated = recent_ls_msgs[p.hash] and (now_time - recent_ls_msgs[p.hash]) < 3

        if dominated then
            -- Local 0x017 already displayed this message; suppress the relay
            table.remove(pending_ls_relays, i)
        elseif now_clock >= p.deadline then
            -- Deadline reached with no local hash — safe to relay
            table.remove(pending_ls_relays, i)
            recent_ls_msgs[p.hash] = now_time
            local display, color
            if p.mode == 'ls1' then
                display = string.format('[%s][LS1] %s: %s', p.sender, p.other_player, p.message)
                color = COLORS.ls1
                push_ls_target(p.sender, 'ls1')
            elseif p.mode == 'ls2' then
                display = string.format('[%s][LS2] %s: %s', p.sender, p.other_player, p.message)
                color = COLORS.ls2
                push_ls_target(p.sender, 'ls2')
            end
            if display then windower.add_to_chat(color, display) end
        else
            i = i + 1
        end
    end
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
    windower.send_command('keyboard_type / ')
    coroutine.schedule(function() windower.chat.set_input(text) end, 0.1)
end

local function cycle_ls_reply()
    if not settings.ls_enabled then windower.add_to_chat(COLORS.info, '[Hivemind] Linkshell monitoring is disabled.') return end

    local all_online = get_online_ls_chars()
    if #all_online == 0 then windower.add_to_chat(COLORS.info, '[Hivemind] No online characters with linkshell access.') return end

    local ordered = {}
    local added = {}

    -- Priority: specific char+LS combos where someone spoke, most recent first
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

    -- Default: current character first, then remaining online chars
    local default_order = {}

    -- Current character's remaining entries
    for _, entry in ipairs(all_online) do
        if entry.char == MY_NAME then
            local key = entry.char .. '|' .. entry.mode
            if not added[key] then
                table.insert(default_order, entry)
                added[key] = true
            end
        end
    end

    -- Other online characters' remaining entries
    for _, entry in ipairs(all_online) do
        local key = entry.char .. '|' .. entry.mode
        if not added[key] then
            table.insert(default_order, entry)
            added[key] = true
        end
    end

    -- Append defaults after the activity-priority entries
    for _, entry in ipairs(default_order) do
        table.insert(ordered, entry)
    end

    if #ordered == 0 then windower.add_to_chat(COLORS.info, '[Hivemind] No online characters with linkshell access.') return end

    ls_reply_index = (ls_reply_index % #ordered) + 1
    local target = ordered[ls_reply_index]
    local slash = (target.mode == 'ls1') and '/l ' or '/l2 '
    local text = (target.char == MY_NAME) and slash or ('//send ' .. target.char .. ' ' .. slash)
    windower.send_command('keyboard_type / ')
    coroutine.schedule(function() windower.chat.set_input(text) end, 0.1)
end

----------------------------------------------------------------------
-- IPC MESSAGE HANDLER
----------------------------------------------------------------------
windower.register_event('ipc message', function(raw)
    if not MY_NAME then return end

    local sender, mode, other_player, message = raw:match('^([^|]*)|([^|]*)|([^|]*)|(.+)$')
    if not sender then return end
    sender, mode, other_player, message = unescape(sender), unescape(mode), unescape(other_player), unescape(message)

    -- Ignore our own broadcasts
    if sender == MY_NAME then return end

    -- Process presence
    if mode == 'login' or mode == 'heartbeat' then
        online_chars[sender] = os.time()
        -- If they just logged in, respond so they learn about us immediately
        if mode == 'login' then
            broadcast('heartbeat', MY_NAME, 'alive')
        end
        return
    elseif mode == 'logout' then
        online_chars[sender] = nil
        return
    end

    -- Relay actual messages
    if mode == 'tell_in' or mode == 'tell_out' or mode == 'ls1' or mode == 'ls2' then
        show_relayed_message(sender, mode, other_player, message)
    end
end)

----------------------------------------------------------------------
-- 0x0B6 Outgoing Chat
----------------------------------------------------------------------
windower.register_event('outgoing chunk', function(id, data)
    if not MY_NAME then return end
    if id == 0x0B6 then -- Outgoing Tell
        local p = packets.parse('outgoing', data)
        local target = (p['Target Name'] or p['target_name'] or 'Unknown'):gsub('%z', ''):trim()
        local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()
        reply_index = 0
        broadcast('tell_out', target, msg)
    elseif id == 0x0B5 and settings.ls_enabled then -- Outgoing Speech (LS1/LS2/etc)
        local p = packets.parse('outgoing', data)
        local mode = p['Mode'] or p['mode']
        local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()
        if #msg > 0 then
            local ls_mode = (mode == 5 and 'ls1') or (mode == 27 and 'ls2') or nil
            if ls_mode then
                local hash = ls_mode .. '|' .. MY_NAME .. '|' .. msg
                push_ls_target(MY_NAME, ls_mode)
                recent_ls_msgs[hash] = os.time()
                broadcast(ls_mode, MY_NAME, msg)
            end
        end
    end
end)

----------------------------------------------------------------------
-- 0x017 Incoming Chat
----------------------------------------------------------------------
windower.register_event('incoming chunk', function(id, data)
    if id == 0x017 and MY_NAME then
        local p = packets.parse('incoming', data)
        local mode = p['Mode'] or p['mode']
        local sender = (p['Sender Name'] or p['sender_name'] or ''):gsub('%z', ''):trim()
        local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()

        if mode == 3 then -- Tell Incoming
            push_reply_target(MY_NAME, sender)
            broadcast('tell_in', sender, msg)
        elseif settings.ls_enabled and (mode == 5 or mode == 27) then
            local ls_mode = (mode == 5) and 'ls1' or 'ls2'
            if sender == '' or sender == 'Unknown' then sender = MY_NAME end
            local hash = ls_mode .. '|' .. sender .. '|' .. msg

            push_ls_target(MY_NAME, ls_mode)

            if sender ~= MY_NAME then
                recent_ls_msgs[hash] = os.time()
                broadcast(ls_mode, sender, msg)
            else
                if not recent_ls_msgs[hash] then
                    recent_ls_msgs[hash] = os.time()
                    broadcast(ls_mode, MY_NAME, msg)
                else
                    recent_ls_msgs[hash] = os.time()
                end
            end
        end
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
-- LOOP & INIT
----------------------------------------------------------------------
local last_prune = os.time()

windower.register_event('prerender', function()
    flush_pending_ls()

    if not MY_NAME then return end

    -- Periodic maintenance
    local now = os.time()
    if now - last_prune >= 60 then
        last_prune = now
        -- Prune stale dedup entries
        for hash, ts in pairs(recent_ls_msgs) do
            if (now - ts) > 10 then recent_ls_msgs[hash] = nil end
        end
        prune_presence()
    end

    -- Heartbeat
    if now - last_heartbeat >= settings.heartbeat_interval then
        last_heartbeat = now
        online_chars[MY_NAME] = now
        broadcast('heartbeat', MY_NAME, 'alive')
    end
end)

local function setup(name)
    MY_NAME = name

    -- Clear stale state from any previous character session
    reply_list          = {}
    reply_index         = 0
    ls_target_list      = {}
    ls_reply_index      = 0
    recent_ls_msgs      = {}
    pending_ls_relays   = {}

    windower.send_command('bind ' .. settings.reply_bind .. ' hivemind reply')
    windower.send_command('bind ' .. settings.ls_bind .. ' hivemind lsreply')

    -- Register self in the roster
    online_chars[MY_NAME] = os.time()
    last_heartbeat = os.time()

    -- Broadcast login so other characters discover us
    broadcast('login', MY_NAME, 'online')
end

windower.register_event('load', function()
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
end)

windower.register_event('unload', function()
    if MY_NAME then
        broadcast('logout', MY_NAME, 'offline')
        online_chars[MY_NAME] = nil
    end
    windower.send_command('unbind ' .. settings.reply_bind)
    windower.send_command('unbind ' .. settings.ls_bind)
end)
