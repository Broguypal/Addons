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
_addon.author  = 'Broguypal'
_addon.version = '1.0'

local packets = require('packets')

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
-- Shared directory: all instances read/write here.
local SHARED_DIR  = windower.windower_path .. 'addons/Hivemind/shared/'
local LOG_FILE    = SHARED_DIR .. 'messages.log'
local LOCK_SUFFIX = '.lock'
local POLL_RATE   = 0.1          -- seconds between polls
local MAX_AGE     = 1800         -- prune messages older than 30 min
local MY_NAME     = nil          -- filled on load
local MAX_REPLY   = 5            -- max unique senders to cycle through

local reply_list   = {}          -- ordered most-recent-first, up to MAX_REPLY
local reply_index  = 0           -- 0 = not cycling yet, 1..#reply_list = current position
local ctrl_held    = false       -- track ctrl key state (DIK 29)

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
-- Simple file lock: create a .lock file, yield if it exists
local function with_lock(func)
    local lock_path = LOG_FILE .. LOCK_SUFFIX
    local attempts = 0
    while attempts < 20 do
        local lf = io.open(lock_path, 'r')
        if not lf then break end
        lf:close()
        attempts = attempts + 1
        coroutine.sleep(0.01)
    end
    -- Grab lock
    local lf = io.open(lock_path, 'w')
    if lf then
        lf:write(tostring(os.clock()))
        lf:close()
    end
    -- Do work
    local ok, err = pcall(func)
    -- Release lock
    os.remove(lock_path)
    if not ok then
        windower.add_to_chat(167, '[Hivemind] Error: ' .. tostring(err))
    end
end

-- Escape pipe characters so they don't break our delimiter
local function escape(s)
    return s:gsub('|', '<<PIPE>>')
end

local function unescape(s)
    return s:gsub('<<PIPE>>', '|')
end

----------------------------------------------------------------------
-- REPLY LIST MANAGEMENT
----------------------------------------------------------------------
-- Cap at MAX_REPLY entries.
local function push_reply(char_name, sender_name)
    -- Remove existing entry for this sender (if any)
    for i = #reply_list, 1, -1 do
        if reply_list[i].sender == sender_name then
            table.remove(reply_list, i)
        end
    end

    -- Insert at front (most recent)
    table.insert(reply_list, 1, { char = char_name, sender = sender_name })

    -- Trim to cap
    while #reply_list > MAX_REPLY do
        table.remove(reply_list)
    end

    -- Reset cycle position so next Ctrl+C starts from the newest
    reply_index = 0
end

-- Called when an outgoing tell is sent — reset cycle back to most recent
local function reset_reply_cycle()
    reply_index = 0
end

----------------------------------------------------------------------
-- MESSAGE LOG  (format: timestamp|sender_char|direction|other_player|message\n)
----------------------------------------------------------------------
local last_read_pos = 0  -- byte offset we've read up to

local function write_message(direction, other_player, message)
    with_lock(function()
        local f = io.open(LOG_FILE, 'a')
        if f then
            local line = string.format('%d|%s|%s|%s|%s\n',
                os.time(),
                escape(MY_NAME),
                direction,
                escape(other_player),
                escape(message))
            f:write(line)
            f:close()
        end
    end)
end

local function read_new_messages()
    local results = {}
    with_lock(function()
        local f = io.open(LOG_FILE, 'r')
        if not f then return end

        f:seek('set', last_read_pos)
        local new_data = f:read('*a')
        last_read_pos = f:seek()
        f:close()

        if not new_data or #new_data == 0 then return end

        local now = os.time()
        for line in new_data:gmatch('[^\n]+') do
            local ts, sender, direction, other_player, message = line:match('^(%d+)|([^|]*)|([^|]*)|([^|]*)|(.+)$')
            if ts then
                ts = tonumber(ts)
                sender       = unescape(sender)
                other_player = unescape(other_player)
                message      = unescape(message)

                if sender ~= MY_NAME and (now - ts) < MAX_AGE then
                    table.insert(results, {
                        sender       = sender,
                        direction    = direction,
                        other_player = other_player,
                        message      = message,
                    })
                end
            end
        end
    end)
    return results
end

-- Periodically purge the log so it doesn't grow forever
local last_prune = os.time()
local PRUNE_INTERVAL = 60

local function maybe_prune()
    if os.time() - last_prune < PRUNE_INTERVAL then return end
    last_prune = os.time()

    with_lock(function()
        local f = io.open(LOG_FILE, 'r')
        if not f then return end
        local content = f:read('*a')
        f:close()

        local now = os.time()
        local kept = {}
        for line in content:gmatch('[^\n]+') do
            local ts = line:match('^(%d+)|')
            if ts and (now - tonumber(ts)) < MAX_AGE then
                table.insert(kept, line)
            end
        end

        f = io.open(LOG_FILE, 'w')
        if f then
            f:write(table.concat(kept, '\n'))
            if #kept > 0 then f:write('\n') end
            f:close()
        end
    end)

    -- After purging, reset read position to end of new file
    local f = io.open(LOG_FILE, 'r')
    if f then
        f:seek('end')
        last_read_pos = f:seek()
        f:close()
    end
end

----------------------------------------------------------------------
-- DISPLAY
----------------------------------------------------------------------
-- Color 4 = tell color in default FFXI chat
local TELL_COLOR = 4

local function show_relayed_tell(sender_char, direction, other_player, message)
    local display
    if direction == 'out' then
        -- Outgoing: show that your other character sent a tell
        display = string.format('[%s] >> %s : %s', sender_char, other_player, message)
    else
        -- Incoming: show that your other character received a tell
        display = string.format('[%s] %s >> %s', sender_char, other_player, message)
    end
    windower.add_to_chat(TELL_COLOR, display)
end

----------------------------------------------------------------------
-- PACKET HOOK — capture incoming tells
----------------------------------------------------------------------
windower.register_event('incoming chunk', function(id, data)
    if not MY_NAME then return end

    if id == 0x017 then
        local parsed = packets.parse('incoming', data)
        -- Mode 3 = /tell
        if parsed and parsed['Mode'] == 3 then
            local from_player = parsed['Sender Name'] or parsed['sender_name'] or 'Unknown'
            local message     = parsed['Message']     or parsed['message']     or ''

            -- Clean up any auto-translate brackets or trailing bytes
            message = message:gsub('%z', '')

            -- Track for reply cycling
            push_reply(MY_NAME, from_player)

            write_message('in', from_player, message)
        end
    end
end)

----------------------------------------------------------------------
-- PACKET HOOK — capture outgoing tells (sent by this character)
----------------------------------------------------------------------
windower.register_event('outgoing chunk', function(id, data)
    if not MY_NAME then return end

    if id == 0xB6 then
        local parsed = packets.parse('outgoing', data)
        if parsed then
            local target  = parsed['Target Name'] or parsed['target_name'] or 'Unknown'
            local message = parsed['Message']     or parsed['message']     or ''

            message = message:gsub('%z', '')

            -- Reset cycle so next Ctrl+C starts from most recent sender
            reset_reply_cycle()

            write_message('out', target, message)
        end
    end
end)

----------------------------------------------------------------------
-- POLLING LOOP — check for messages from other instances
----------------------------------------------------------------------
local last_poll = os.clock()

windower.register_event('prerender', function()
    if not MY_NAME then return end

    local now = os.clock()
    if now - last_poll < POLL_RATE then return end
    last_poll = now

    local msgs = read_new_messages()
    if msgs then
        for _, m in ipairs(msgs) do
            show_relayed_tell(m.sender, m.direction, m.other_player, m.message)
            -- Track for reply cycling — only incoming tells
            if m.direction == 'in' then
                push_reply(m.sender, m.other_player)
            end
        end
    end

    maybe_prune()
end)

----------------------------------------------------------------------
-- REPLY — Ctrl+C cycles through the last N unique incoming senders
----------------------------------------------------------------------
windower.register_event('keyboard', function(dik, key_up, blocked)
    -- Track ctrl state (DIK 29)
    -- Note: key_up=true means pressed, key_up=false means released
    if dik == 29 then
        ctrl_held = key_up
        return
    end

    -- Ctrl+C (DIK 46) on key press
    if dik == 46 and key_up and ctrl_held then
        if #reply_list == 0 then return end

        -- Advance the cycle index (1-based, wraps around)
        reply_index = reply_index + 1
        if reply_index > #reply_list then
            reply_index = 1
        end

        local entry = reply_list[reply_index]
        local text
        if entry.char == MY_NAME then
            text = '/tell ' .. entry.sender .. ' '
        else
            text = '//send ' .. entry.char .. ' /tell ' .. entry.sender .. ' '
        end

        -- keyboard_type opens chat, then set_input replaces with full text
        windower.send_command('keyboard_type /tell ')
        coroutine.schedule(function()
            windower.chat.set_input(text)
        end, 0.1)
    end
end)

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------
windower.register_event('load', function()
    windower.create_dir(SHARED_DIR)

    -- Seed reply list from existing log (incoming tells only, within MAX_AGE)
    local f = io.open(LOG_FILE, 'r')
    if f then
        local content = f:read('*a')
        f:seek('end')
        last_read_pos = f:seek()
        f:close()

        if content and #content > 0 then
            local now = os.time()
            -- Parse all incoming tells to build the reply list in chronological order
            for line in content:gmatch('[^\n]+') do
                local ts, sender, direction, other_player = line:match('^(%d+)|([^|]*)|([^|]*)|([^|]*)|')
                if ts and direction == 'in' then
                    ts = tonumber(ts)
                    sender       = unescape(sender)
                    other_player = unescape(other_player)
                    if (now - ts) < MAX_AGE then
                        push_reply(sender, other_player)
                    end
                end
            end
        end
    end
end)

windower.register_event('login', function(name)
    MY_NAME = name
    windower.add_to_chat(207, '[Hivemind] Active for: ' .. MY_NAME)
end)

-- Handle if already logged in when addon loads
local player = windower.ffxi.get_player()
if player then
    MY_NAME = player.name
    windower.add_to_chat(207, '[Hivemind] Active for: ' .. MY_NAME)
end
