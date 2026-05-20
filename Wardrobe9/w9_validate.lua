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

return function(res, util, config, bags, scanmod, planner)
    local M = {}

    local ALL_WARDROBE_NAMES = {
        'Wardrobe','Wardrobe 2','Wardrobe 3','Wardrobe 4',
        'Wardrobe 5','Wardrobe 6','Wardrobe 7','Wardrobe 8',
    }

    local function wardrobe_id_set(enabled_only)
        local ids = {}
        for _, bn in ipairs(ALL_WARDROBE_NAMES) do
            local id = bags.bag_id_by_name(bn)
            if id then
                if enabled_only then
                    if bags.bag_enabled(id) then ids[id] = true end
                else
                    ids[id] = true
                end
            end
        end
        return ids
    end

    local function merge_needed_from_files(jobfiles)
        local merged = {}
        local labels = {}
        for _, f in ipairs(jobfiles) do
            local needed, err = planner.extract_needed(f.rel)
            if not needed then
                return nil, ('Error reading %s: %s'):format(tostring(f.rel), tostring(err))
            end
            labels[#labels+1] = f.label or f.rel
            for key, info in pairs(needed) do
                if not merged[key] then merged[key] = info end
            end
        end
        return merged, table.concat(labels, ', ')
    end

    -- ======================================================
    -- VAL: List all missing
    -- ======================================================

    function M.validate_missing(jobfiles)
        if type(jobfiles) ~= 'table' or #jobfiles == 0 then
            return nil, 'No files selected.'
        end

        local scan, err = scanmod.load_scan_cache()
        if not scan then return nil, 'No scan cache. Press SCAN first.' end

        local merged, label = merge_needed_from_files(jobfiles)
        if not merged then return nil, label end

        local idx    = planner.index_scan_items(scan)
        local wd_ids = wardrobe_id_set(false)

        local missing_entirely      = {}
        local in_bags_not_wardrobes = {}
        local in_wardrobes_count    = 0
        local total                 = 0

        for key, info in pairs(merged) do
            total = total + 1
            local found_in_wd = false
            local ln = util.lkey(info.name)

            -- Augment-strict: augmented items require exact key match.
            if info.aug and info.aug ~= '' then
                found_in_wd = (idx.in_dest_exact[key] or 0) > 0
            else
                found_in_wd = (idx.in_dest_name[ln] or 0) > 0
            end

            if found_in_wd then
                in_wardrobes_count = in_wardrobes_count + 1
            else
                -- Not in any wardrobe — check all bags.
                local recs_exact = (info.aug and info.aug ~= '') and idx.by_exact[key] or nil
                local recs_name  = idx.by_name[ln]

                local non_wd_bags = {}

                if recs_exact then
                    for _, rec in ipairs(recs_exact) do
                        if not wd_ids[rec.bag_id] then
                            non_wd_bags[rec.bag_name or ('Bag '..rec.bag_id)] = true
                        end
                    end
                end

                if recs_name then
                    for _, rec in ipairs(recs_name) do
                        if not wd_ids[rec.bag_id] then
                            non_wd_bags[rec.bag_name or ('Bag '..rec.bag_id)] = true
                        end
                    end
                end

                local bag_list = {}
                for b in pairs(non_wd_bags) do bag_list[#bag_list+1] = b end
                table.sort(bag_list)

                if #bag_list > 0 then
                    in_bags_not_wardrobes[#in_bags_not_wardrobes+1] = {
                        name  = info.name,
                        aug   = info.aug or '',
                        group = info.group,
                        bags  = table.concat(bag_list, ', '),
                    }
                else
                    missing_entirely[#missing_entirely+1] = {
                        name  = info.name,
                        aug   = info.aug or '',
                        group = info.group,
                    }
                end
            end
        end

        local function sort_fn(a, b)
            if a.group == b.group then return a.name < b.name end
            return a.group < b.group
        end
        table.sort(missing_entirely, sort_fn)
        table.sort(in_bags_not_wardrobes, sort_fn)

        -- Check storage slips for items that are missing entirely.
        local on_slips = {}
        do
            local slip_map = util.read_slip_items()
            if next(slip_map) then
                local name_to_ids = {}
                for id, entry in pairs(res.items) do
                    if entry and entry.en then
                        local nm = util.lkey(util.trim(entry.en))
                        if nm ~= '' then
                            name_to_ids[nm] = name_to_ids[nm] or {}
                            name_to_ids[nm][#name_to_ids[nm]+1] = id
                        end
                        if entry.enl then
                            local long = util.lkey(util.trim(entry.enl))
                            if long ~= '' and long ~= nm then
                                name_to_ids[long] = name_to_ids[long] or {}
                                name_to_ids[long][#name_to_ids[long]+1] = id
                            end
                        end
                    end
                end

                local still_missing = {}
                for _, m in ipairs(missing_entirely) do
                    local ids = name_to_ids[util.lkey(m.name)]
                    local slip_label = nil
                    if ids then
                        for _, id in ipairs(ids) do
                            if slip_map[id] then
                                slip_label = slip_map[id]
                                break
                            end
                        end
                    end
                    if slip_label then
                        on_slips[#on_slips+1] = {
                            name  = m.name,
                            aug   = m.aug or '',
                            group = m.group,
                            slip  = slip_label,
                        }
                    else
                        still_missing[#still_missing+1] = m
                    end
                end
                missing_entirely = still_missing
            end
        end

        table.sort(on_slips, sort_fn)

        return {
            label                 = label,
            total                 = total,
            in_wardrobes          = in_wardrobes_count,
            missing_entirely      = missing_entirely,
            in_bags_not_wardrobes = in_bags_not_wardrobes,
            on_slips              = on_slips,
        }
    end

    -- ======================================================
    -- VAL: List all unused
    -- ======================================================

function M.validate_unused(jobfiles)
        if type(jobfiles) ~= 'table' or #jobfiles == 0 then
            return nil, 'No files selected.'
        end

        local scan, err = scanmod.load_scan_cache()
        if not scan then return nil, 'No scan cache. Press SCAN first.' end

        local merged, label = merge_needed_from_files(jobfiles)
        if not merged then return nil, label end

        local idx = planner.index_scan_items(scan)

        local needed_exact     = {}
        local needed_name_only = {}

        for key, info in pairs(merged) do
            needed_exact[key] = true
            needed_name_only[util.lkey(info.name)] = true
        end

        local wd_ids = wardrobe_id_set(true)

        local unused = {}
        local seen   = {}

        for _, rec in ipairs(scan.items or {}) do
            if wd_ids[rec.bag_id] and rec.name and rec.name ~= '' then
                local group = rec.group or ''
                if group ~= '' and not util.is_protected_group(group) then
                    -- rec.key was set by index_scan_items — lowercased, same format as needed keys
                    local key = rec.key

                    local is_used = needed_exact[key] or needed_name_only[util.lkey(rec.name)]

                    -- Also check the long name (enl) — GearSwap files may
                    -- reference items by their full name rather than the
                    -- abbreviated form stored in the scan cache.
                    if not is_used and rec.item_id and res.items[rec.item_id] then
                        local r = res.items[rec.item_id]
                        if r.enl then
                            local long = util.lkey(util.trim(r.enl))
                            if long ~= '' and long ~= util.lkey(rec.name) then
                                is_used = needed_name_only[long]
                                if not is_used then
                                    local long_key = long
                                    if rec.aug and rec.aug ~= '' then long_key = (long .. '|' .. rec.aug):lower() end
                                    is_used = needed_exact[long_key]
                                end
                            end
                        end
                    end

                    if not is_used and not seen[key] then
                        seen[key] = true
                        unused[#unused+1] = {
                            name     = rec.name,
                            aug      = rec.aug or '',
                            group    = group,
                            bag_name = rec.bag_name,
                        }
                    end
                end
            end
        end

        table.sort(unused, function(a, b)
            if (a.group or '') == (b.group or '') then return a.name < b.name end
            return (a.group or '') < (b.group or '')
        end)

        local has_custom_vars = false
        if type(config.CUSTOM_GEAR_VARIABLES) == 'table' then
            for _, vars in pairs(config.CUSTOM_GEAR_VARIABLES) do
                if type(vars) == 'table' and #vars > 0 then
                    has_custom_vars = true
                    break
                end
            end
        end

        return {
            label           = label,
            unused          = unused,
            has_custom_vars = has_custom_vars,
        }
    end
	
    return M
end