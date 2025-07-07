-- CondensedDamage
-- Author: Broguypal

_addon.name     = 'CondensedDamage'
_addon.author   = 'Broguypal'
_addon.version  = '3.0-filters'
_addon.commands = {'cdd', 'condenseddamage'}

local config = require('config')
local default_settings = {
    filters = {
        show_self = true,
        show_party = true,
        show_alliance = true,
        show_trusts = true,
        show_other_players = false,
    }
}
local settings = config.load(default_settings)

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

local function should_show(actor)
    if not actor then return false end
    local me = windower.ffxi.get_player()
    if not me then return false end

    if actor.id == me.id then
        return settings.filters.show_self
    elseif actor.in_party then
        return settings.filters.show_party
    elseif actor.in_alliance then
        return settings.filters.show_alliance
    elseif actor.is_npc and not actor.is_monster then
        return settings.filters.show_trusts
    elseif actor.is_player then
        return settings.filters.show_other_players
    end

    return false
end

local function inject_message(text, actor_id)
    local actor = windower.ffxi.get_mob_by_id(actor_id)
    if not should_show(actor) then return end

    if text:find("Enspell") then
        windower.add_to_chat(122, text)
    else
        windower.add_to_chat(151, text)
    end
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

windower.register_event('action', function(act)
    if not condensed_categories[act.category] then return end

    local actor = windower.ffxi.get_mob_by_id(act.actor_id)
    if not should_show(actor) then return end

    local results = parse_action(act)
    for _, entry in ipairs(results) do
        if last_output[entry.actor] ~= entry.text then
            inject_message(entry.text, act.actor_id)
            last_output[entry.actor] = entry.text
        end
    end
end)

windower.register_event('incoming text', function(original)
    local me = windower.ffxi.get_player()
    if not me then return end

    local suppress = false

    if original:match('^' .. me.name .. ' hits [%w%s]+ for %d+') or
       original:match('^Additional effect:') or
       original:match('^' .. me.name .. ' scores a critical hit!') then
        suppress = true
    end

    if original:match('^[^%s]+ hits [^%s]+ for %d+') then
        local actor = original:match('^([^%s]+) hits')
        local mob = actor and windower.ffxi.get_mob_by_name(actor)
        if mob and should_show(mob) then
            suppress = true
        end
    end

    if suppress then return true end
end)

windower.register_event('unload', function() config.save(settings) end)
windower.register_event('logout', function() config.save(settings) end)

windower.register_event('load', function()
    windower.add_to_chat(151, '[CondensedDamage] Loaded with filters. Edit settings.xml to control visible sources.')
end)



windower.register_event('addon command', function(cmd, arg)
    if cmd == 'help' then

    windower.add_to_chat(151, '[CondensedDamage Commands]')
    windower.add_to_chat(151, '  //cdd toggle self       - Show/hide your own damage')
    windower.add_to_chat(151, '  //cdd toggle party      - Show/hide party members')
    windower.add_to_chat(151, '  //cdd toggle alliance   - Show/hide alliance members')
    windower.add_to_chat(151, '  //cdd toggle trusts     - Show/hide trusts/NPCs')
    windower.add_to_chat(151, '  //cdd toggle others     - Show/hide other players')
    windower.add_to_chat(151, '  //cdd status            - Show current filter settings')
    windower.add_to_chat(151, '  //cdd help              - Show this help message')

        return
    end
    cmd = cmd and cmd:lower()
    arg = arg and arg:lower()

    if cmd == 'toggle' and arg then
        if arg == 'self' then
            settings.filters.show_self = not settings.filters.show_self
            windower.add_to_chat(151, 'Show Self Damage: ' .. tostring(settings.filters.show_self))
        elseif arg == 'party' then
            settings.filters.show_party = not settings.filters.show_party
            windower.add_to_chat(151, 'Show Party Damage: ' .. tostring(settings.filters.show_party))
        elseif arg == 'alliance' then
            settings.filters.show_alliance = not settings.filters.show_alliance
            windower.add_to_chat(151, 'Show Alliance Damage: ' .. tostring(settings.filters.show_alliance))
        elseif arg == 'trusts' then
            settings.filters.show_trusts = not settings.filters.show_trusts
            windower.add_to_chat(151, 'Show Trust/NPC Damage: ' .. tostring(settings.filters.show_trusts))
        elseif arg == 'others' then
            settings.filters.show_other_players = not settings.filters.show_other_players
            windower.add_to_chat(151, 'Show Other Players Damage: ' .. tostring(settings.filters.show_other_players))
        else
            windower.add_to_chat(123, 'Usage: //cdd toggle [self | party | alliance | trusts | others]')
        end
        config.save(settings)
    elseif cmd == 'status' then
        windower.add_to_chat(151, '[CondensedDamage Filter Status]')
        windower.add_to_chat(151, '  Self:     ' .. tostring(settings.filters.show_self))
        windower.add_to_chat(151, '  Party:    ' .. tostring(settings.filters.show_party))
        windower.add_to_chat(151, '  Alliance: ' .. tostring(settings.filters.show_alliance))
        windower.add_to_chat(151, '  Trusts:   ' .. tostring(settings.filters.show_trusts))
        windower.add_to_chat(151, '  Others:   ' .. tostring(settings.filters.show_other_players))
    else
        windower.add_to_chat(123, 'Invalid command.')

    windower.add_to_chat(151, '[CondensedDamage Commands]')
    windower.add_to_chat(151, '  //cdd toggle self       - Show/hide your own damage')
    windower.add_to_chat(151, '  //cdd toggle party      - Show/hide party members')
    windower.add_to_chat(151, '  //cdd toggle alliance   - Show/hide alliance members')
    windower.add_to_chat(151, '  //cdd toggle trusts     - Show/hide trusts/NPCs')
    windower.add_to_chat(151, '  //cdd toggle others     - Show/hide other players')
    windower.add_to_chat(151, '  //cdd status            - Show current filter settings')
    windower.add_to_chat(151, '  //cdd help              - Show this help message')

        windower.add_to_chat(123, '  //cdd toggle [self | party | alliance | trusts | others]')
        windower.add_to_chat(123, '  //cdd status')
    end
end)
