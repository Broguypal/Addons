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
-- Using a fixed path so every character resolves the same folder.
-- Adjust this if your Windower lives somewhere else.
local SHARED_DIR  = windower.windower_path .. 'addons/Hivemind/shared/'
local LOG_FILE    = SHARED_DIR .. 'messages.log'
local LOCK_SUFFIX = '.lock'
local POLL_RATE   = 0.1          -- seconds between polls
local MAX_AGE     = 300          -- purgw messages older than 5 min
local MY_NAME     = nil          -- filled on load

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
-- Make sure the shared directory exists
local function ensure_dir(path)
    windower.create_dir(path)
end

-- create a .lock file, yield if it exists
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
-- MESSAGE LOG  (format: timestamp|sender_char|from_player|message\n)
----------------------------------------------------------------------
local last_read_pos = 0  -- byte offset we've read up to

local function write_message(from_player, message)
    with_lock(function()
        local f = io.open(LOG_FILE, 'a')
        if f then
            local line = string.format('%d|%s|%s|%s\n',
                os.time(),
                escape(MY_NAME),
                escape(from_player),
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
            local ts, sender, from_player, message = line:match('^(%d+)|([^|]*)|([^|]*)|(.+)$')
            if ts then
                ts = tonumber(ts)
                sender     = unescape(sender)
                from_player = unescape(from_player)
                message     = unescape(message)

                if sender ~= MY_NAME and (now - ts) < MAX_AGE then
                    table.insert(results, {
                        sender      = sender,
                        from_player = from_player,
                        message     = message,
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

local function show_relayed_tell(sender_char, from_player, message)
    -- Show which of your characters received it
    local display = string.format('[%s] %s >> %s', sender_char, from_player, message)
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

            write_message(from_player, message)
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
            show_relayed_tell(m.sender, m.from_player, m.message)
        end
    end

    maybe_prune()
end)

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------
windower.register_event('load', function()
    ensure_dir(SHARED_DIR)

    -- Seek to end of existing log so we don't replay old messages
    local f = io.open(LOG_FILE, 'r')
    if f then
        f:seek('end')
        last_read_pos = f:seek()
        f:close()
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
