--[[
Wardrobe9 - Windower addon for Final Fantasy XI
BSD 3-Clause License

Copyright (c) 2026 Broguypal
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain this notice.
2. Redistributions in binary form must reproduce this notice in documentation.
3. Neither the name of the author nor contributors may be used to endorse or
   promote products derived from this software without prior written permission.

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
]]

return function(res, extdata, util)
    local M = {}

    local executing = false

    local function have_native_move()
        return windower and windower.ffxi and type(windower.ffxi.move_item) == 'function'
    end

    local function native_move(mv)
        -- windower.ffxi.move_item(source_bag_id, dest_bag_id, slot, count)
        local ok, r = pcall(windower.ffxi.move_item, mv.from_bag_id, mv.to_bag_id, mv.from_slot, 1)
        if not ok then
            return false, tostring(r)
        end
        return true, nil
    end

    local function slot_item_key(bag_id, slot)
        local contents = windower.ffxi.get_items(bag_id)
        if not contents or not contents.max or not contents[slot] then return nil end
        local entry = contents[slot]
        if not entry or not entry.id or entry.id == 0 then return nil end

        local r = res.items[entry.id]
        local name = r and r.en or nil
        if not name or name == '' then return nil end
        name = util.trim(name)

        local aug = ''
        if entry.extdata then
            local ok, decoded = pcall(extdata.decode, entry)
            if ok and decoded then
                local a = nil
                if type(decoded.augments) == 'table' then a = decoded.augments
                elseif type(decoded.augment) == 'table' then a = decoded.augment end
                if type(a) == 'table' then
                    aug = util.normalize_aug_list(a)
                end
            end
        end

        if aug ~= '' then
            return name .. '|' .. aug
        end
        return name
    end

    function M.exec_plan(plan)
        if executing then util.warn('Already executing.'); return end
        if not plan or not plan.moves then util.err('No stored plan. In the Mog House UI, press PLAN first.'); return end
        if #plan.moves == 0 then util.msg('Nothing to do.'); return end

        if not have_native_move() then
            util.err('Exec cannot run: your Windower build does not expose windower.ffxi.move_item(). Update Windower or add a fallback executor.')
            return
        end

        executing = true
        util.msg(('Executing %d moves...'):format(#plan.moves))

        local i = 1
        local function step()
            if not executing then return end

            if i > #plan.moves then
                executing = false
                util.msg('Execution complete.')
                return
            end

            local mv = plan.moves[i]
            i = i + 1

            -- Safety: verify the planned source slot still contains the expected item.
            if mv.item_key and mv.from_bag_id and mv.from_slot then
                local cur = slot_item_key(mv.from_bag_id, mv.from_slot)
                if cur and cur ~= mv.item_key then
                    executing = false
                    util.err(('ABORT: source slot changed before move %d. Expected "%s" but found "%s" at %s:slot%d')
                        :format(i-1, tostring(mv.item_key), tostring(cur), tostring(mv.from_bag_name), tonumber(mv.from_slot) or -1))
                    util.err('Re-run SCAN, then PLAN in the Mog House UI, then try EXEC again.')
                    return
                elseif not cur then
                    executing = false
                    util.err(('ABORT: source slot is empty/unknown before move %d. Expected "%s" at %s:slot%d')
                        :format(i-1, tostring(mv.item_key), tostring(mv.from_bag_name), tonumber(mv.from_slot) or -1))
                    util.err('Re-run SCAN, then PLAN in the Mog House UI, then try EXEC again.')
                    return
                end
            end

            local ok, e = native_move(mv)
            if not ok then
                util.err(('Move failed (%s): %s:slot%d -> %s (%s) | %s')
                    :format(
                        tostring(mv.type),
                        tostring(mv.from_bag_name),
                        tonumber(mv.from_slot) or -1,
                        tostring(mv.to_bag_name),
                        tostring(mv.item_name),
                        tostring(e)
                    ))
            end

            -- Slight delay between moves to stay safe with server processing.
            coroutine.schedule(step, 0.6)
        end

        step()
    end

    return M
end
