_addon.name = 'RoastMeDaddy'
_addon.author = 'Broguypal'
_addon.version = '1.0'
_addon.commands = {'rmd','roastmedaddy'}  -- use //rmd or //roastmedaddy

local config = require('config')

-- Phrase lists
local insults = require('insults')
local flirty  = require('flirty')

----------------------------------------------------------------
-- Persistent settings (auto-saved to data/settings.xml)
----------------------------------------------------------------
local defaults = {
    mode = 'random',       -- 'flirty' | 'roast' | 'random'
    trigger_chance = 0.15, -- 0.0 .. 1.0
    cooldown_seconds = 8,  -- seconds between triggers
    inject_delay = 1.1,    -- seconds after NPC line appears
}
local settings = config.load(defaults)

-- Bind locals to current settings
local mode = settings.mode
local trigger_chance = settings.trigger_chance
local cooldown_seconds = settings.cooldown_seconds
local inject_delay = settings.inject_delay

-- NPC dialogue modes 
local NPC_MODES = {
    [150] = true,
    [144] = true,
}

----------------------------------------------------------------
-- RNG seed (once on load)
----------------------------------------------------------------
math.randomseed(os.time())
for i = 1, 5 do math.random() end 

windower.add_to_chat(200, ("[RoastMeDaddy] Loaded. Current mode: %s"):format(tostring(mode)))

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
-- Normalize UTF-8 punctuation to ASCII to avoid mojibake in FFXI chat
local function sanitize_text(s)
    if not s then return "" end
    s = s
        :gsub("’", "'"):gsub("‘", "'"):gsub("‛", "'")
        :gsub("“", '"'):gsub("”", '"'):gsub("„", '"')
        :gsub("–", "-"):gsub("—", "-"):gsub("‒", "-")
        :gsub("…", "...")
        :gsub("\u00A0", " "):gsub("\u202F", " ")
        :gsub("•", "*")
        :gsub("™", "(TM)")
    -- Strip any remaining non-ASCII bytes
    s = s:gsub("[^\032-\126]", "")
    return s
end

local function get_line()
    if mode == 'flirty' then
        return flirty[math.random(#flirty)]
    elseif mode == 'roast' then
        return insults[math.random(#insults)]
    else -- 'random'
        if math.random(2) == 1 then
            return flirty[math.random(#flirty)]
        else
            return insults[math.random(#insults)]
        end
    end
end

----------------------------------------------------------------
-- Internals
----------------------------------------------------------------
local pending_injection = nil
local inject_time = 0
local squelch_until = 0
local last_injected = nil

----------------------------------------------------------------
-- Commands (use //rmd or //roastmedaddy)
----------------------------------------------------------------
windower.register_event('addon command', function(cmd, arg)
    cmd = cmd and cmd:lower() or ""
    arg = arg and arg:lower() or ""

    if cmd == 'mode' then
        if arg == 'flirty' or arg == 'roast' or arg == 'random' then
            mode = arg
            settings.mode = mode
            settings:save()
            windower.add_to_chat(200, ("[RoastMeDaddy] Mode set to: %s"):format(mode))
        else
            windower.add_to_chat(200, "[RoastMeDaddy] Usage: //rmd mode [flirty|roast|random]")
        end

    elseif cmd == 'chance' then
        local n = tonumber(arg)
        if n and n >= 0 and n <= 1 then
            trigger_chance = n
            settings.trigger_chance = trigger_chance
            settings:save()
            windower.add_to_chat(200, ("[RoastMeDaddy] Trigger chance set to %.2f"):format(trigger_chance))
        else
            windower.add_to_chat(200, "[RoastMeDaddy] Usage: //rmd chance 0.0..1.0")
        end

    elseif cmd == 'cooldown' then
        local n = tonumber(arg)
        if n and n >= 0 then
            cooldown_seconds = n
            settings.cooldown_seconds = cooldown_seconds
            settings:save()
            windower.add_to_chat(200, ("[RoastMeDaddy] Cooldown set to %.1f seconds"):format(cooldown_seconds))
        else
            windower.add_to_chat(200, "[RoastMeDaddy] Usage: //rmd cooldown <seconds>")
        end

    elseif cmd == 'delay' then
        local n = tonumber(arg)
        if n and n >= 0 then
            inject_delay = n
            settings.inject_delay = inject_delay
            settings:save()
            windower.add_to_chat(200, ("[RoastMeDaddy] Inject delay set to %.1f seconds"):format(inject_delay))
        else
            windower.add_to_chat(200, "[RoastMeDaddy] Usage: //rmd delay <seconds>")
        end

    elseif cmd == 'test' then
        pending_injection = sanitize_text(get_line())
        inject_time = os.clock() + 0.1
        windower.add_to_chat(200, "[RoastMeDaddy] Forced test injection queued")

    else
        windower.add_to_chat(200, "[RoastMeDaddy] Commands:")
        windower.add_to_chat(200, "//rmd mode [flirty|roast|random]")
        windower.add_to_chat(200, "//rmd chance 0.0..1.0")
        windower.add_to_chat(200, "//rmd cooldown <seconds>")
        windower.add_to_chat(200, "//rmd delay <seconds>")
        windower.add_to_chat(200, "//rmd test")
        windower.add_to_chat(200, "Alias: //roastmedaddy (same commands)")
    end
end)

----------------------------------------------------------------
-- Delay/inject handler 
----------------------------------------------------------------
windower.register_event('prerender', function()
    if pending_injection and os.clock() >= inject_time then
        last_injected = pending_injection
        windower.add_to_chat(151, "  " .. pending_injection)
        pending_injection = nil
        squelch_until = os.clock() + cooldown_seconds
    end
end)

----------------------------------------------------------------
-- NPC dialogue trigger (incoming text only) 
----------------------------------------------------------------
windower.register_event('incoming text', function(original, modified, mode_id)
    if not NPC_MODES[mode_id] then return end

    local now = os.clock()
    if now < squelch_until then return end

    if last_injected and original and original == last_injected then return end

    if math.random() >= trigger_chance then return end

    pending_injection = sanitize_text(get_line())
    inject_time = now + inject_delay
end)
