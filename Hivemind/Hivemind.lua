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
_addon.version = '2.0'
_addon.command = 'hivemind'

local packets = require('packets')

----------------------------------------------------------------------
-- USER CONFIG — feel free to change these
----------------------------------------------------------------------
local REPLY_BIND  = '!r'         -- keybind for reply cycling (! = Alt, ^ = Ctrl, @ = Win)
local LS_BIND     = '!l'         -- keybind for linkshell cycling (! = Alt, ^ = Ctrl, @ = Win)
local MAX_REPLY   = 12            -- max unique targets to cycle through
local POLL_RATE   = 0.1          -- how often to check for new messages (in seconds)
local MAX_AGE     = 3600         -- purge messages older than 1 hour
local LS_ENABLED  = true         -- set to false to disable linkshell monitoring entirely

----------------------------------------------------------------------
-- INTERNALS
----------------------------------------------------------------------
local SHARED_DIR          = windower.windower_path .. 'addons/Hivemind/shared/'
local LOG_FILE            = SHARED_DIR .. 'messages.log'
local LOCK_SUFFIX         = '.lock'
local MY_NAME             = nil
local reply_list          = {}      -- unique {char, sender} for tells
local reply_index         = 0
local ls_target_list      = {}      -- unique {char, mode} for linkshells (activity-based priority)
local ls_reply_index      = 0
local recent_ls_msgs      = {}      -- deduplication {hash = timestamp}
local pending_ls_relays   = {}      -- queued LS relays awaiting dedup check {expire, sender, mode, other_player, message}
local last_poll           = os.clock()

-- Presence tracking — in-memory, driven by log entries
local HEARTBEAT_INTERVAL  = 120      -- seconds between heartbeat log entries
local PRESENCE_TIMEOUT    = 360     -- consider offline after 6 min without heartbeat
local last_heartbeat      = 0
local online_chars        = {}      -- { [char_name] = last_seen_timestamp }

local COLORS = { tell=4, ls1=6, ls2=213, info=167 }

----------------------------------------------------------------------
-- UTILS
----------------------------------------------------------------------
local function escape(s) return tostring(s):gsub('|', '<<PIPE>>') end
local function unescape(s) return tostring(s):gsub('<<PIPE>>', '|') end

local function with_lock(func)
    local lock_path = LOG_FILE .. LOCK_SUFFIX
    local attempts = 0
    while attempts < 30 do
        local lf = io.open(lock_path, 'r')
        if not lf then break end
        lf:close()
        attempts = attempts + 1
        coroutine.sleep(0.01)
    end
    local lf = io.open(lock_path, 'w')
    if lf then lf:write(tostring(os.clock())) lf:close() end
    local ok, err = pcall(func)
    os.remove(lock_path)
    if not ok then windower.add_to_chat(COLORS.info, '[Hivemind] Lock Error: ' .. tostring(err)) end
end

----------------------------------------------------------------------
-- PRESENCE TRACKING
----------------------------------------------------------------------
local function prune_presence()
    local now = os.time()
    for name, last_seen in pairs(online_chars) do
        if name ~= MY_NAME and (now - last_seen) >= PRESENCE_TIMEOUT then
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
    return (os.time() - last_seen) < PRESENCE_TIMEOUT
end

----------------------------------------------------------------------
-- TARGET MANAGEMENT
----------------------------------------------------------------------
local function push_reply_target(char_name, sender_name)
    for i = #reply_list, 1, -1 do
        if reply_list[i].sender == sender_name then table.remove(reply_list, i) end
    end
    table.insert(reply_list, 1, { char = char_name, sender = sender_name })
    while #reply_list > MAX_REPLY do table.remove(reply_list) end
    reply_index = 0
end

local function push_ls_target(char_name, mode)
    for i = #ls_target_list, 1, -1 do
        if ls_target_list[i].char == char_name and ls_target_list[i].mode == mode then
            table.remove(ls_target_list, i)
        end
    end
    table.insert(ls_target_list, 1, { char = char_name, mode = mode })
    while #ls_target_list > MAX_REPLY do table.remove(ls_target_list) end
    ls_reply_index = 0
end

----------------------------------------------------------------------
-- LOGGING
--
-- Log format: timestamp|sender_char|mode|other_player|message
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
local last_read_pos = 0

local function write_message(mode, other_player, message)
    if not MY_NAME or not mode or not other_player or not message or #message == 0 then return end
    with_lock(function()
        local f = io.open(LOG_FILE, 'a')
        if f then
            f:write(string.format('%d|%s|%s|%s|%s\n', os.time(), escape(MY_NAME), escape(mode), escape(other_player), escape(message)))
            f:close()
        end
    end)
end

local function write_heartbeat()
    local now = os.time()
    if now - last_heartbeat < HEARTBEAT_INTERVAL then return end
    last_heartbeat = now
    online_chars[MY_NAME] = now
    write_message('heartbeat', MY_NAME, 'alive')
end

local function read_new_messages()
    local results = {}
    local seen_ls_batch = {}
    with_lock(function()
        local f = io.open(LOG_FILE, 'r')
        if not f then return end
        -- If another instance pruned the file, it may be smaller than our last position.
        -- Reset to current EOF — we may miss a handful of messages from the tiny window
        -- between prune and detection, but this avoids replaying hours of old messages.
        local file_size = f:seek('end')
        if last_read_pos > file_size then
            last_read_pos = file_size
        end
        f:seek('set', last_read_pos)
        local new_data = f:read('*a')
        last_read_pos = f:seek()
        f:close()

        if not new_data or #new_data == 0 then return end

        local now = os.time()
        for line in new_data:gmatch('[^\n]+') do
            local ts, sender, mode, other_player, message = line:match('^(%d+)|([^|]*)|([^|]*)|([^|]*)|(.+)$')
            if ts then
                ts, sender, mode, other_player, message = tonumber(ts), unescape(sender), unescape(mode), unescape(other_player), unescape(message)

                -- Process presence entries from other characters
                if sender ~= MY_NAME then
                    if mode == 'login' or mode == 'heartbeat' then
                        online_chars[sender] = ts
                    elseif mode == 'logout' then
                        online_chars[sender] = nil
                    end
                end

                -- Only relay actual messages from other chars
                if sender ~= MY_NAME and (now - ts) < MAX_AGE then
                    if mode == 'tell_in' or mode == 'tell_out' then
                        table.insert(results, { sender=sender, mode=mode, other_player=other_player, message=message })
                    elseif mode == 'ls1' or mode == 'ls2' then
                        local ls_hash = mode .. '|' .. other_player .. '|' .. message
                        if not seen_ls_batch[ls_hash] then
                            seen_ls_batch[ls_hash] = true
                            table.insert(results, { sender=sender, mode=mode, other_player=other_player, message=message })
                        end
                    end
                end
            end
        end
    end)
    return results
end

local last_prune = os.time()
local function maybe_prune()
    if os.time() - last_prune < 60 then return end
    last_prune = os.time()
    local now = os.time()
    for hash, ts in pairs(recent_ls_msgs) do
        if (now - ts) > 10 then recent_ls_msgs[hash] = nil end
    end
    prune_presence()
    with_lock(function()
        local f = io.open(LOG_FILE, 'r')
        if not f then return end
        local content = f:read('*a')
        f:close()
        local kept = {}
        for line in content:gmatch('[^\n]+') do
            local ts = line:match('^(%d+)|')
            if ts and (now - tonumber(ts)) < MAX_AGE then table.insert(kept, line) end
        end
        f = io.open(LOG_FILE, 'w')
        if f then f:write(table.concat(kept, '\n') .. (#kept > 0 and '\n' or '')) f:close() end
    end)
    local f = io.open(LOG_FILE, 'r')
    if f then f:seek('end') last_read_pos = f:seek() f:close() end
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
    elseif LS_ENABLED and (mode == 'ls1' or mode == 'ls2') then
        -- Queue LS relays so the local incoming chunk has time to set the dedup hash
        table.insert(pending_ls_relays, {
            expire = os.clock() + 0.35,
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
        if now_clock >= p.expire then
            table.remove(pending_ls_relays, i)
            -- Re-check dedup after the delay
            if not (recent_ls_msgs[p.hash] and (now_time - recent_ls_msgs[p.hash]) < 3) then
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
            end
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
    if not LS_ENABLED then windower.add_to_chat(COLORS.info, '[Hivemind] Linkshell monitoring is disabled.') return end

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
-- PACKETS
----------------------------------------------------------------------
windower.register_event('outgoing chunk', function(id, data)
    if not MY_NAME then return end
    if id == 0x0B6 then -- Outgoing Tell
        local p = packets.parse('outgoing', data)
        local target = (p['Target Name'] or p['target_name'] or 'Unknown'):gsub('%z', ''):trim()
        local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()
        reply_index = 0
        write_message('tell_out', target, msg)
    elseif id == 0x0B5 and LS_ENABLED then -- Outgoing Speech (LS1/LS2/etc)
        local p = packets.parse('outgoing', data)
        local mode = p['Mode'] or p['mode']
        local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()
        if #msg > 0 then
            local ls_mode = (mode == 5 and 'ls1') or (mode == 27 and 'ls2') or nil
            if ls_mode then
                local hash = ls_mode .. '|' .. MY_NAME .. '|' .. msg
                push_ls_target(MY_NAME, ls_mode)
                recent_ls_msgs[hash] = os.time()
                write_message(ls_mode, MY_NAME, msg)
            end
        end
    end
end)

----------------------------------------------------------------------
-- 0x017 Incoming Chat — OTHER PLAYERS' LS messages + dedup for own echo
--   • Other players: sets dedup hash + writes to log for relay
--   • Own echo: sets dedup hash only (0x0B5 already wrote to log);
--     if 0x0B5 somehow didn't fire, falls back to writing
----------------------------------------------------------------------
windower.register_event('incoming chunk', function(id, data)
    if id == 0x017 and MY_NAME then
        local p = packets.parse('incoming', data)
        local mode = p['Mode'] or p['mode']
        local sender = (p['Sender Name'] or p['sender_name'] or ''):gsub('%z', ''):trim()
        local msg = (p['Message'] or p['message'] or ''):gsub('%z', ''):trim()

        if mode == 3 then -- Tell Incoming
            push_reply_target(MY_NAME, sender)
            write_message('tell_in', sender, msg)
        elseif LS_ENABLED and (mode == 5 or mode == 27) then
            local ls_mode = (mode == 5) and 'ls1' or 'ls2'
            if sender == '' or sender == 'Unknown' then sender = MY_NAME end
            local hash = ls_mode .. '|' .. sender .. '|' .. msg

            push_ls_target(MY_NAME, ls_mode)

            if sender ~= MY_NAME then
                recent_ls_msgs[hash] = os.time()
                write_message(ls_mode, sender, msg)
            else
                if not recent_ls_msgs[hash] then
                    recent_ls_msgs[hash] = os.time()
                    write_message(ls_mode, MY_NAME, msg)
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
    end
end)

----------------------------------------------------------------------
-- LOOP & INIT
----------------------------------------------------------------------
windower.register_event('prerender', function()
    local now = os.clock()
    flush_pending_ls()
    if not MY_NAME or (now - last_poll < POLL_RATE) then return end
    last_poll = now
    local msgs = read_new_messages()
    if msgs then for _, m in ipairs(msgs) do show_relayed_message(m.sender, m.mode, m.other_player, m.message) end end
    maybe_prune()
    write_heartbeat()
end)

local function setup(name)
    MY_NAME = name
    windower.send_command('bind ' .. REPLY_BIND .. ' hivemind reply')
    windower.send_command('bind ' .. LS_BIND .. ' hivemind lsreply')

    -- Register self in the roster
    online_chars[MY_NAME] = os.time()
    last_heartbeat = os.time()

    -- Log the login so other characters see it
    write_message('login', MY_NAME, 'online')

    -- Seed from existing log
    local f = io.open(LOG_FILE, 'r')
    if f then
        local content = f:read('*a')
        f:seek('end') last_read_pos = f:seek() f:close()
        if content then
            local now = os.time()
            for line in content:gmatch('[^\n]+') do
                local ts, sender, mode, other_player = line:match('^(%d+)|([^|]*)|([^|]*)|([^|]*)|')
                if ts then
                    ts = tonumber(ts)
                    sender = unescape(sender)
                    other_player = unescape(other_player)
                    if (now - ts) < MAX_AGE then
                        -- Rebuild presence roster
                        if sender ~= MY_NAME then
                            if mode == 'login' or mode == 'heartbeat' then
                                online_chars[sender] = ts
                            elseif mode == 'logout' then
                                online_chars[sender] = nil
                            end
                        end
                        -- Rebuild activity lists
                        if mode == 'tell_in' then push_reply_target(sender, other_player)
                        elseif mode == 'ls1' then push_ls_target(sender, 'ls1')
                        elseif mode == 'ls2' then push_ls_target(sender, 'ls2') end
                    end
                end
            end
            prune_presence()
        end
    end
end

windower.register_event('load', function() windower.create_dir(SHARED_DIR) local p = windower.ffxi.get_player() if p then setup(p.name) end end)
windower.register_event('login', function(name) setup(name) end)
windower.register_event('logout', function()
    if MY_NAME then
        write_message('logout', MY_NAME, 'offline')
        online_chars[MY_NAME] = nil
    end
end)
windower.register_event('unload', function()
    if MY_NAME then
        write_message('logout', MY_NAME, 'offline')
        online_chars[MY_NAME] = nil
    end
    windower.send_command('unbind ' .. REPLY_BIND)
    windower.send_command('unbind ' .. LS_BIND)
end)
