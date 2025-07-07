-- CondensedDamage
-- Author: Broguypal

-- WARNING:
-- This addon injects condensed damage messages using specific chat modes:
-- - Mode 151: Used for player, trust, and NPC auto/ranged attacks.
--   • This is the same mode used by NPC dialogue (e.g., key item messages, shop text).
--   • You MUST keep "NPC dialogue" enabled in your log to see these messages.
--
-- - Mode 122: Used for Enspell damage only.
--   • This is part of the game's "Battle messages" filter.
--   • You MUST have "Battle Messages" enabled in your log
--     to see Enspell damage lines.

_addon.name     = 'CondensedDamage'
_addon.author   = 'Broguypal'
_addon.version  = '2.5-clean'
_addon.commands = {'cdd', 'condenseddamage'}

local condensed_categories = {
    [1]  = true, -- Melee
    [2]  = true, -- Ranged
    [11] = true, -- Enspell
}

local last_output = {}

local function get_name(id)
    local mob = windower.ffxi.get_mob_by_id(id)
    return mob and mob.name or ('Unknown(' .. tostring(id) .. ')')
end

local function inject_message(text, actor_id)
    local actor = windower.ffxi.get_mob_by_id(actor_id)

    -- Enspell lines get chat mode 122 (light blue)
    if text:find("Enspell") then
        windower.add_to_chat(122, text)
        return
    end

    windower.add_to_chat(151, text)
end

local function parse_action(act)
    local results = {}
    local actor = get_name(act.actor_id)

    for _, target in ipairs(act.targets) do
        local target_name = get_name(target.id)
        local total, count, crits = 0, 0, 0
        local enspell_total, enspell_hits = 0, 0

        for _, action in ipairs(target.actions) do
            local msg = action.message
            local dmg = action.param or 0

            if msg == 1 or msg == 67 or msg == 2 or msg == 68 then
                total = total + dmg
                count = count + 1
                if msg == 67 or msg == 68 then
                    crits = crits + 1
                end
            end

            if action.has_add_effect and action.add_effect_message == 229 then
                local admg = action.add_effect_param or 0
                if admg > 0 then
                    enspell_total = enspell_total + admg
                    enspell_hits = enspell_hits + 1
                end
            end
        end

        if count > 0 then
            local line = string.format('%s dealt %d to %s (%d hit%s%s)',
                actor, total, target_name, count,
                count > 1 and 's' or '',
                crits > 0 and string.format(', %d crit%s', crits, crits > 1 and 's' or '') or '')
            table.insert(results, { actor = actor, text = line })
        end

        if enspell_hits > 0 then
            local es = string.format("%s's Enspell hits %s for %d (%d hit%s)",
                actor, target_name, enspell_total, enspell_hits,
                enspell_hits > 1 and 's' or '')
            table.insert(results, { actor = actor, text = es })
        end
    end

    return results
end

-- Condense only if the actor is not a monster
windower.register_event('action', function(act)
    if not condensed_categories[act.category] then return end

    local actor = windower.ffxi.get_mob_by_id(act.actor_id)
    if actor and actor.is_npc and not actor.is_player then
        return -- Monster attack: skip condensing
    end

    local results = parse_action(act)
    for _, entry in ipairs(results) do
        if last_output[entry.actor] ~= entry.text then
            inject_message(entry.text, act.actor_id)
            last_output[entry.actor] = entry.text
        end
    end
end)

-- Suppress only messages where the attacker is not a monster
windower.register_event('incoming text', function(original)
    local player_name = windower.ffxi.get_player().name

    -- Suppress messages caused by player/NPC/trust attacks only
    local suppress = false

    -- Match your own actions
    if original:match('^' .. player_name .. ' hits [%w%s]+ for %d+') or
       original:match('^Additional effect:') or
       original:match('^' .. player_name .. ' scores a critical hit!') then
        suppress = true
    end

    -- Match other players/trusts/NPCs but not monsters
    if original:match('^[^%s]+ hits [^%s]+ for %d+') then
        local actor = original:match('^([^%s]+) hits')
        local mob = actor and windower.ffxi.get_mob_by_name(actor)
        if mob and mob.is_npc and not mob.is_player then
            suppress = false
        else
            suppress = true
        end
    end

    if suppress then return true end
end)

windower.register_event('load', function()
    windower.add_to_chat(151, '[CondensedDamage] Loaded. Monster damage is native. Only player/trust/NPC attacker damage is condensed/suppressed.')
end)
