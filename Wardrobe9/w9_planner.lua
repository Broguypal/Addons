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

return function(res, util, config, slots, bags, scanmod)
    local M = {}

    -- ======================================================
    -- Index scan cache
    -- ======================================================

    local function index_scan_items(scan)
        local by_name, by_exact = {}, {}
        local in_dest_name, in_dest_exact = {}, {}
        local dest_aug_by_name = {}

        local in_excl_name, in_excl_exact = {}, {}
        local excl_bag_for_name, excl_bag_for_exact = {}, {}

        local managed_dest_ids = {}
        do
            local dest = bags.build_dest_bags()
            for _,b in ipairs(dest) do managed_dest_ids[b.id] = true end
        end

        local ALL_WARDROBE_NAMES = {
            'Wardrobe','Wardrobe 2','Wardrobe 3','Wardrobe 4',
            'Wardrobe 5','Wardrobe 6','Wardrobe 7','Wardrobe 8',
        }

        local enabled_wardrobe_ids = {}
        local disabled_wardrobe_ids = {}
        local unmanaged_enabled_wardrobe_ids = {}

        for _,bn in ipairs(ALL_WARDROBE_NAMES) do
            local id = bags.bag_id_by_name(bn)
            if id then
                if bags.bag_enabled(id) then
                    enabled_wardrobe_ids[id] = true
                    if not managed_dest_ids[id] then
                        unmanaged_enabled_wardrobe_ids[id] = true
                    end
                else
                    disabled_wardrobe_ids[id] = bn
                end
            end
        end

        local excluded_ids = {}
        for bagname, enabled in pairs(config.SOURCE_BAG_EXCLUDE or {}) do
            if enabled then
                local id = bags.bag_id_by_name(bagname)
                if id then
                    excluded_ids[id] = bagname
                end
            end
        end

        for _,rec in ipairs(scan.items or {}) do
            local nm = rec.name
            if nm and nm ~= '' then
                local aug = util.normalize_aug_string(rec.aug or '')
                rec.aug = aug

                local exact = nm
                if aug ~= '' then exact = nm .. '|' .. aug end
                rec.key = rec.key or exact

                by_name[nm] = by_name[nm] or {}
                by_name[nm][#by_name[nm]+1] = rec

                by_exact[exact] = by_exact[exact] or {}
                by_exact[exact][#by_exact[exact]+1] = rec

                if enabled_wardrobe_ids[rec.bag_id] then
                    in_dest_name[nm] = (in_dest_name[nm] or 0) + 1
                    in_dest_exact[exact] = (in_dest_exact[exact] or 0) + 1

                    dest_aug_by_name[nm] = dest_aug_by_name[nm] or {}
                    dest_aug_by_name[nm][aug] = true

				elseif excluded_ids[rec.bag_id] then
					local bag_label = excluded_ids[rec.bag_id] or 'Excluded'

					in_excl_name[nm] = (in_excl_name[nm] or 0) + 1
					in_excl_exact[exact] = (in_excl_exact[exact] or 0) + 1

					excl_bag_for_name[nm] = excl_bag_for_name[nm] or {}
					excl_bag_for_name[nm][bag_label] = true

					excl_bag_for_exact[exact] = excl_bag_for_exact[exact] or {}
					excl_bag_for_exact[exact][bag_label] = true
				end
            end
        end

        return {
            by_name = by_name,
            by_exact = by_exact,

            -- NOTE: "dest" here means "available in any ENABLED wardrobe (1..8)", even if not managed.
            in_dest_name = in_dest_name,
            in_dest_exact = in_dest_exact,

            dest_aug_by_name = dest_aug_by_name,

            in_excl_name = in_excl_name,
            in_excl_exact = in_excl_exact,
            excl_bag_for_name = excl_bag_for_name,
            excl_bag_for_exact = excl_bag_for_exact,

            unmanaged_enabled_wardrobe_ids = unmanaged_enabled_wardrobe_ids,
            disabled_wardrobe_ids = disabled_wardrobe_ids,
            managed_dest_ids = managed_dest_ids,
        }
    end

    -- ======================================================
    -- Extract required items (TEXT SCAN superset, SLOT_GROUP keys only)
    -- ======================================================

    local function parse_augments_block(tbl_src)
        if type(tbl_src) ~= 'string' or tbl_src == '' then return nil end

        -- find augments= { ... } (balanced braces)
        local aug_block = tbl_src:match("augments%s*=%s*(%b{})")
                       or tbl_src:match("augment%s*=%s*(%b{})")
                       or tbl_src:match("aug%s*=%s*(%b{})")

        if not aug_block then return nil end

        local out = {}
        for _q, s in aug_block:gmatch("(['\"])(.-)%1") do
            if s and s ~= '' then out[#out+1] = s end
        end

        if #out == 0 then return nil end
        return out
    end

    -- TEXT-SCAN superset:
    -- Only capture values for slots where util.group_for_slot(slot) is true (i.e., keys in config.SLOT_GROUP).
    -- Captures:
    --   slot="Item"
    --   slot={name="Item", augments={...}}
    local function walk_text_collect(jobfile)
        local path = util.resolve_gearswap_jobfile_path(jobfile)
        if not path then
            return nil, ("cannot resolve job file path for %s (try full path or ensure it exists in GearSwap/data)"):format(tostring(jobfile))
        end

        local f = io.open(path, 'rb')
        if not f then
            return nil, ("cannot open %s"):format(tostring(path))
        end
        local src = f:read('*a') or ''
        f:close()

        local needed = {}

        local function add_needed(slot, val)
            local group = util.group_for_slot(slot)
            if not group or util.is_protected_group(group) then return end

            local key, name, aug = util.make_item_key(val)
            if key and name then
                needed[key] = needed[key] or { name = name, aug = aug, group = group }
            end
        end

        -- 1) slot = { ... } form (captures augments if present)
        -- This will also match non-gear tables, but this is filtered by SLOT_GROUP keys via util.group_for_slot(slot).
        for slot, tbl in src:gmatch("([%a_][%w_]*)%s*=%s*(%b{})") do
            if util.group_for_slot(slot) then
                local _q, nm = tbl:match("name%s*=%s*(['\"])(.-)%1")
                if nm and nm ~= '' then
                    local aug_list = parse_augments_block(tbl)
                    if aug_list then
                        add_needed(slot, { name = nm, augments = aug_list })
                    else
                        add_needed(slot, { name = nm })
                    end
                end
            end
        end

        -- 2) slot = "Item" or 'Item' form
        for slot, quote, item in src:gmatch("([%a_][%w_]*)%s*=%s*(['\"])(.-)%2") do
            if util.group_for_slot(slot) then
                -- ignore name="..." inside table values because slot must be a SLOT_GROUP key
                if item and item ~= '' then
                    add_needed(slot, item)
                end
            end
        end

        return needed, path
    end



    -- ======================================================
    -- Planning
    -- ======================================================

    function M.plan_for_file(jobfile, mode)
        mode = (mode == 'fill') and 'fill' or 'swap'
        local scan, se = scanmod.load_scan_cache()
        if not scan then
            return nil, 'No scan cache. In the Mog House UI, press SCAN.'
        end

        local needed, path_or_err = walk_text_collect(jobfile)
        if not needed then
            return nil, tostring(path_or_err)
        end
		local path = path_or_err

        local dest_bags, disabled_wardrobes = bags.build_dest_bags()
		if #dest_bags == 0 then
			return nil, 'No destination wardrobes enabled. In w9_config.lua, set DEST_BAGS for at least one of: Wardrobe, Wardrobe 2..Wardrobe 8 = true.'
		end
        local idx = index_scan_items(scan)
        local warn_aug_pre = {}
		
		local function bagset_to_string(set)
			if type(set) ~= 'table' then return nil end
			local t = {}
			for k,v in pairs(set) do
				if v then t[#t+1] = k end
			end
			table.sort(t)
			if #t == 0 then return nil end
			return table.concat(t, ', ')
		end

        local missing, present, excl_present, total_needed = {}, 0, 0, 0
        local mismatch = {}
        local in_excluded = {}

        for key,info in pairs(needed) do
            total_needed = total_needed + 1

            if info.aug and info.aug ~= '' then
                if (idx.in_dest_exact[key] or 0) > 0 then
                    present = present + 1

                elseif (idx.in_dest_name[info.name] or 0) > 0 then
                    mismatch[#mismatch+1] = { key=key, name=info.name, aug=info.aug, group=info.group }
                    missing[#missing+1]  = { key=key, name=info.name, aug=info.aug, group=info.group, reason='augment_mismatch' }

                else
                    local excl_exact = (idx.in_excl_exact[key] or 0) > 0
                    local excl_name  = (idx.in_excl_name[info.name] or 0) > 0

					if excl_exact or excl_name then
						local bag_set =
							idx.excl_bag_for_exact[key]
							or idx.excl_bag_for_name[info.name]

						local bag_label = bagset_to_string(bag_set) or 'Excluded'

						excl_present = excl_present + 1
						in_excluded[#in_excluded+1] = {
							name = info.name,
							aug = info.aug,
							group = info.group,
							bag = bag_label,
							exact = excl_exact,  -- true only if exact aug was found
						}
                    else
                        do
                        local found_disabled = false
                        local list = idx.by_exact[key] or idx.by_name[info.name]
                        if type(list) == 'table' then
                            for _,rec in ipairs(list) do
                                local bn = idx.disabled_wardrobe_ids and idx.disabled_wardrobe_ids[rec.bag_id]
                                if bn then
                                    found_disabled = true
                                    in_excluded[#in_excluded+1] = {
                                        name = info.name,
                                        aug = info.aug,
                                        group = info.group,
                                        bag = bn .. ' (disabled)',
                                        exact = true,
                                    }
                                    excl_present = excl_present + 1
                                    break
                                end
                            end
                        end
                        if not found_disabled then
                            missing[#missing+1] = { key=key, name=info.name, aug=info.aug, group=info.group }
                        end
                    end
                    end
                end
            else
                -- Non-aug items: name-only presence is fine
                if (idx.in_dest_name[info.name] or 0) > 0 then
                    present = present + 1
                else
                    local excl_name = (idx.in_excl_name[info.name] or 0) > 0
					
					if excl_name then
						local bag_set = idx.excl_bag_for_name[info.name]
						local bag_label = bagset_to_string(bag_set) or 'Excluded'

						excl_present = excl_present + 1
						in_excluded[#in_excluded+1] = {
							name = info.name,
							aug = '',
							group = info.group,
							bag = bag_label,
							exact = true,
						}
					else

                        do
                        local found_disabled = false
                        local list = idx.by_name[info.name]
                        if type(list) == 'table' then
                            for _,rec in ipairs(list) do
                                local bn = idx.disabled_wardrobe_ids and idx.disabled_wardrobe_ids[rec.bag_id]
                                if bn then
                                    found_disabled = true
                                    in_excluded[#in_excluded+1] = {
                                        name = info.name,
                                        aug = '',
                                        group = info.group,
                                        bag = bn .. ' (disabled)',
                                        exact = true,
                                    }
                                    excl_present = excl_present + 1
                                    break
                                end
                            end
                        end
                        if not found_disabled then
                            missing[#missing+1] = { key=key, name=info.name, aug='', group=info.group }
                        end
                    end
                    end
                end
            end
        end

        table.sort(missing, function(a,b)
            if a.group == b.group then return a.name < b.name end
            return a.group < b.group
        end)

        table.sort(mismatch, function(a,b)
            if a.group == b.group then return a.name < b.name end
            return a.group < b.group
        end)

        local plan = {
            file = jobfile,
            path = path,
            total_needed = total_needed,
            present = present,
            excl_present = excl_present,
            in_excluded = in_excluded,
            missing = missing,
            mismatch = mismatch,
            moves = {},
            notes = {},
            dest_bags = dest_bags,
            disabled_wardrobes = disabled_wardrobes,

            warn_aug_mismatch = warn_aug_pre,
            required_name_only = {},
            import_only = {},
            required_name_count = {},
            aug_mismatch_found = {},   -- [item_name] = {sorted list of aug strings actually present}
            mode = mode,
        }

        if #disabled_wardrobes > 0 then
            for _,b in ipairs(disabled_wardrobes) do
                plan.notes[#plan.notes+1] = ('%s is disabled; it will appear in scan, but we will not move into/out of it.'):format((type(b)=='table' and (b.name or b.en or b.id)) or tostring(b))
            end
        end

        if plan.in_excluded and #plan.in_excluded > 0 then
            table.sort(plan.in_excluded, function(a,b)
                if a.group == b.group then return a.name < b.name end
                return a.group < b.group
            end)
            for _,it in ipairs(plan.in_excluded) do
                local bag_label = it.bag or 'Excluded'
                if it.aug and it.aug ~= '' and not it.exact then
                    plan.notes[#plan.notes+1] =
                        ('Located in %s (augment differs): %s (%s). Will not be moved.'):format(bag_label, it.name, it.group)
                else
                    plan.notes[#plan.notes+1] =
                        ('Located in %s: %s (%s). Will not be moved.'):format(bag_label, it.name, it.group)
                end
            end
        end

        local return_id, return_name = bags.pick_return_bag_id()
        if not return_id then
            plan.notes[#plan.notes+1] = 'No enabled return bag found (Safe/Safe2/Storage/etc). EVICT moves will not be planned.'
        end

        local free_by_dest = {}
        for _,b in ipairs(dest_bags) do
            free_by_dest[b.id] = bags.bag_free(b.id)
        end

        local needed_name_only, needed_exact = {}, {}
        for k,info in pairs(needed) do
            needed_exact[k] = true
            needed_name_only[info.name] = true
            plan.required_name_count[info.name] = (plan.required_name_count[info.name] or 0) + 1

            if not info.aug or info.aug == '' then
                plan.required_name_only[info.name] = true
            end
        end

        local evict_candidates = {}
        do
            local dest_ids = {}
            for _,b in ipairs(dest_bags) do dest_ids[b.id] = true end

            for _,rec in ipairs(scan.items or {}) do
                if dest_ids[rec.bag_id] and rec.name and rec.name ~= '' then
                    if not config.LOCKED_ITEMS[rec.name] then
                        local g = rec.group

                        if g and g ~= '' and (not util.is_protected_group(g)) then
                            local exact = rec.name
                            if rec.aug and rec.aug ~= '' then exact = rec.name .. '|' .. rec.aug end

                            if (not needed_name_only[rec.name]) and (not needed_exact[exact]) then
                                evict_candidates[g] = evict_candidates[g] or {}
                                evict_candidates[g][#evict_candidates[g]+1] = rec
                            end
                        end
                    end
                end
            end

            for g,list in pairs(evict_candidates) do
                table.sort(list, function(a,b)
                    if a.bag_id == b.bag_id then return a.slot < b.slot end
                    return a.bag_id < b.bag_id
                end)
            end
        end

        local function pick_any_dest_with_space()
            for _,b in ipairs(dest_bags) do
                if (free_by_dest[b.id] or 0) > 0 then
                    return b.id
                end
            end
            return nil
        end

        local function pick_source_for_missing(m)
            -- Returns: rec, mode
            -- mode:
            --   'exact' = exact augmented match found
            --   'name1' = no exact aug match, but exactly 1 enabled candidate by name
            --   'multi' = multiple enabled candidates by name (ambiguous)
            --   'none'  = not found
            local list_exact = nil
            if m.aug and m.aug ~= '' then
                list_exact = idx.by_exact[m.key]

                if list_exact and #list_exact > 0 then
                    for _,rec in ipairs(list_exact) do
                        if bags.bag_enabled(rec.bag_id) and (not util.is_excluded_source_bag(rec.bag_name)) and (not idx.unmanaged_enabled_wardrobe_ids[rec.bag_id]) then
                            return rec, 'exact'
                        end
                    end
                end
                return nil, 'none'
            end

            local list_name = idx.by_name[m.name]
            if not list_name or #list_name == 0 then
                return nil, 'none'
            end

            local enabled = {}
            for _,rec in ipairs(list_name) do
                if bags.bag_enabled(rec.bag_id) and (not util.is_excluded_source_bag(rec.bag_name)) and (not idx.unmanaged_enabled_wardrobe_ids[rec.bag_id]) then
                    enabled[#enabled+1] = rec
                end
            end

            if #enabled == 1 then
                return enabled[1], 'name1'
            elseif #enabled > 1 then
                return enabled[1], 'multi'
            end

            return nil, 'none'
        end

		local any_missing = false

        for _,m in ipairs(mismatch) do
            local src, src_mode = pick_source_for_missing(m)
            if not src or src_mode ~= 'exact' then
                any_missing = true
                local have = idx.dest_aug_by_name[m.name]
                local havet = {}
                if type(have) == 'table' then
                    for a,_ in pairs(have) do
                        if a ~= '' then havet[#havet+1] = a end
                    end
                end
                table.sort(havet)
                if not plan.aug_mismatch_found[m.name] then
                    plan.aug_mismatch_found[m.name] = havet
                end
            else
                local dest_id = pick_any_dest_with_space()
                if not dest_id then
                    plan.notes[#plan.notes+1] = ('No free wardrobe slot to import exact aug for %s (%s).'):format(m.name, m.group)
                else
                    plan.moves[#plan.moves+1] = {
                        type='import',
                        from_bag_id=src.bag_id, from_bag_name=src.bag_name, from_slot=src.slot,
                        to_bag_id=dest_id, to_bag_name=(res.bags[dest_id] and res.bags[dest_id].en) or tostring(dest_id),
                        item_name=m.name, group=m.group,
                        item_key=m.key,
                    }
                    free_by_dest[dest_id] = math.max(0, (free_by_dest[dest_id] or 0) - 1)
                end
            end
        end

        for _,m in ipairs(missing) do
            local group = m.group
            local src, src_mode = pick_source_for_missing(m)

		if not src or not bags.bag_enabled(src.bag_id) then
			any_missing = true

            else

                if (m.aug and m.aug ~= '') and (src_mode == 'multi') then
                    plan.import_only[m.name] = true
                    plan.warn_aug_mismatch[m.name] = true

                    local dest_id = pick_any_dest_with_space()
                    if not dest_id then
                        plan.notes[#plan.notes+1] = ('Ambiguous augments for %s (%s): multiple copies exist; will not evict. No free wardrobe slots to import.'):format(m.name, group)
                    else
                        plan.moves[#plan.moves+1] = {
                            type='import',
                            from_bag_id=src.bag_id, from_bag_name=src.bag_name, from_slot=src.slot,
                            to_bag_id=dest_id, to_bag_name=(res.bags[dest_id] and res.bags[dest_id].en) or tostring(dest_id),
                            item_name=m.name, group=group,
                            warn_aug_mismatch=true,
                            item_key=m.key,
                        }
                        free_by_dest[dest_id] = math.max(0, (free_by_dest[dest_id] or 0) - 1)
                    end

                else
                    local dest_id = nil

                    local cands = evict_candidates[group]

                    if mode == 'fill' then
                        -- FILL mode: use free wardrobe slots first; evict only as last resort
                        dest_id = pick_any_dest_with_space()
                        if not dest_id and return_id and cands and #cands > 0 then
                            local ev = table.remove(cands, 1)

                            plan.moves[#plan.moves+1] = {
                                type='evict',
                                from_bag_id=ev.bag_id, from_bag_name=ev.bag_name, from_slot=ev.slot,
                                to_bag_id=return_id, to_bag_name=return_name,
                                item_name=ev.name, group=group,
                                item_key=ev.key or (ev.name .. ((ev.aug and ev.aug ~= '') and ('|'..ev.aug) or '')),
                            }

                            free_by_dest[ev.bag_id] = (free_by_dest[ev.bag_id] or 0) + 1
                            dest_id = ev.bag_id
                        end
                    else
                        -- SWAP mode: evict same-group item first; free slots as fallback
                        if return_id and cands and #cands > 0 then
                            local ev = table.remove(cands, 1)

                            plan.moves[#plan.moves+1] = {
                                type='evict',
                                from_bag_id=ev.bag_id, from_bag_name=ev.bag_name, from_slot=ev.slot,
                                to_bag_id=return_id, to_bag_name=return_name,
                                item_name=ev.name, group=group,
                                item_key=ev.key or (ev.name .. ((ev.aug and ev.aug ~= '') and ('|'..ev.aug) or '')),
                            }

                            free_by_dest[ev.bag_id] = (free_by_dest[ev.bag_id] or 0) + 1
                            dest_id = ev.bag_id
                        else
                            dest_id = pick_any_dest_with_space()
                        end
                    end

                    if not dest_id then
                        if return_id then
                            plan.notes[#plan.notes+1] = ('No space for %s (%s): no unused %s item to evict and no free slots.'):format(m.name, group, group)
                        else
                            plan.notes[#plan.notes+1] = ('No space for %s (%s): no return bag for eviction and no free slots.'):format(m.name, group)
                        end
                    else
                        local warn_aug = ((m.aug and m.aug ~= '') and (src_mode == 'name1'))
                        if warn_aug then
                            plan.warn_aug_mismatch[m.name] = true
                        end

                        plan.moves[#plan.moves+1] = {
                            type='import',
                            from_bag_id=src.bag_id, from_bag_name=src.bag_name, from_slot=src.slot,
                            to_bag_id=dest_id, to_bag_name=(res.bags[dest_id] and res.bags[dest_id].en) or tostring(dest_id),
                            item_name=m.name, group=group,
                            warn_aug_mismatch=warn_aug,
                            item_key=m.key,
                        }
                        free_by_dest[dest_id] = math.max(0, (free_by_dest[dest_id] or 0) - 1)
                    end
                end
            end
        end
        
        if any_missing then
            plan.notes[#plan.notes+1] =
                'This plan contains missing items. Please use /itemsearch "item name" or check your storage slips to see if the item exists. You may need to scan again if your inventory was not fully loaded during initial scan.'
        end

        do
            local dest_ids = {}
            for _,b in ipairs(dest_bags) do dest_ids[b.id] = true end

            local scheduled = {}
            for _,mv in ipairs(plan.moves) do
                if mv.from_bag_id and mv.from_slot then
                    scheduled[mv.from_bag_id .. ':' .. mv.from_slot] = true
                end
            end

            for name, req_count in pairs(plan.required_name_count or {}) do
                if req_count == 1 and plan.required_name_only[name] then
                    local list = idx.by_name[name] or {}
                    local enabled_total = 0
                    for _,rec in ipairs(list) do
                        if bags.bag_enabled(rec.bag_id) and (not util.is_excluded_source_bag(rec.bag_name)) and (not idx.unmanaged_enabled_wardrobe_ids[rec.bag_id]) then
                            enabled_total = enabled_total + 1
                        end
                    end
                    local in_wardrobes = idx.in_dest_name[name] or 0

                    local planned_into_wardrobes = 0
                    for _,mv in ipairs(plan.moves or {}) do
                        if mv.type == 'import' and mv.item_name == name and mv.to_bag_id and dest_ids[mv.to_bag_id] then
                            planned_into_wardrobes = planned_into_wardrobes + 1
                        end
                    end

                    local in_wardrobes_future = in_wardrobes + planned_into_wardrobes
                    local need_more = enabled_total - in_wardrobes_future

                    if need_more > 0 and enabled_total > req_count then
                        if not return_id then
                            plan.notes[#plan.notes+1] = ('Extra copies for %s: cannot import %d additional copy/copies because no enabled return bag exists for eviction.'):format(name, need_more)
                        else
                            plan.notes[#plan.notes+1] = ('Extra copies for %s: ensuring all %d enabled copies are in wardrobes (lua references %d).'):format(name, enabled_total, req_count)
                        end

                        for _,rec in ipairs(list) do
                            if need_more <= 0 then break end
                            if bags.bag_enabled(rec.bag_id) and (not dest_ids[rec.bag_id]) and (not util.is_excluded_source_bag(rec.bag_name)) then
                                local skey = rec.bag_id .. ':' .. rec.slot
                                if not scheduled[skey] then
                                    local g = rec.group

                        if g and g ~= '' and (not util.is_protected_group(g)) then
                                        local cands = evict_candidates[g]

                                        if return_id and cands and #cands > 0 then
                                            local ev = table.remove(cands, 1)

  
                                            plan.moves[#plan.moves+1] = {
                                                type='evict',
                                                from_bag_id=ev.bag_id, from_bag_name=ev.bag_name, from_slot=ev.slot,
                                                to_bag_id=return_id, to_bag_name=return_name,
                                                item_name=ev.name, group=g,
                                                item_key=ev.key or (ev.name .. ((ev.aug and ev.aug ~= '') and ('|'..ev.aug) or '')),
                                            }

                                            free_by_dest[ev.bag_id] = (free_by_dest[ev.bag_id] or 0) + 1

                                            plan.moves[#plan.moves+1] = {
                                                type='import',
                                                from_bag_id=rec.bag_id, from_bag_name=rec.bag_name, from_slot=rec.slot,
                                                to_bag_id=ev.bag_id, to_bag_name=(res.bags[ev.bag_id] and res.bags[ev.bag_id].en) or tostring(ev.bag_id),
                                                item_name=name, group=g,
                                                warn_aug_mismatch=true,
                                                item_key=name,
                                            }

                                            free_by_dest[ev.bag_id] = math.max(0, (free_by_dest[ev.bag_id] or 0) - 1)

                                            scheduled[skey] = true
                                            need_more = need_more - 1
                                            plan.warn_aug_mismatch[name] = true
                                        else
                                            plan.notes[#plan.notes+1] = ('Extra copies for %s: no unused %s item available to evict (or no return bag). Cannot pull additional copy into wardrobes.'):format(name, tostring(g))
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return plan, nil
    end

    -- Prints the shared header section (stats, mismatches, missing items, notes).
    function M.print_plan_header(plan)
        util.msg(('File: %s'):format(plan.path or plan.file))
        local miss_n = plan.missing and #plan.missing or 0
        local mm_n   = plan.mismatch and #plan.mismatch or 0
        util.msg(('Required (text-scan): %d | Present in wardrobes: %d | Located in excluded bags: %d | Missing: %d | Aug-mismatch: %d')
            :format(plan.total_needed or 0, plan.present or 0, plan.excl_present or 0, miss_n, mm_n))

        if plan.missing and #plan.missing > 0 then
            util.warn('Missing items (not currently in enabled wardrobes):')
            for i,m in ipairs(plan.missing) do
                if i > 30 then util.warn(('...and %d more'):format(#plan.missing-30)); break end
                local aug_suffix = (m.aug and m.aug ~= '') and (' (Aug: %s)'):format(m.aug) or ''
                util.warn(('  - Missing "%s"%s'):format(m.name, aug_suffix))
            end
        end

        if plan.mismatch and #plan.mismatch > 0 then
            util.warn('Augment mismatches (item in wardrobes but required augments not present):')
            local seen_keys = {}
            local shown = 0
            for _,m in ipairs(plan.mismatch) do
                local key = m.name .. '|' .. (m.aug or '')
                if not seen_keys[key] then
                    seen_keys[key] = true
                    shown = shown + 1
                    if shown > 30 then
                        util.warn('  ...and more (showing first 30)')
                        break
                    end
                    local req_label = (m.aug and m.aug ~= '') and m.aug or '(none)'
                    util.warn(('  "%s"'):format(m.name))
                    util.warn(('      Required: %s'):format(req_label))
                    local found = plan.aug_mismatch_found and plan.aug_mismatch_found[m.name]
                    if found and #found > 0 then
                        for _, fa in ipairs(found) do
                            util.warn(('      Found:    %s'):format(fa))
                        end
                    else
                        util.warn('      Found:    (unknown augments)')
                    end
                end
            end
        end

        if plan.notes and #plan.notes > 0 then
            local filtered = {}
            for _,n in ipairs(plan.notes) do
                if not n:match('^Augment mismatch: wardrobes contain') then
                    filtered[#filtered+1] = n
                end
            end
            if #filtered > 0 then
                util.warn('Notes:')
                for _,n in ipairs(filtered) do util.warn('  * '..n) end
            end
        end

        do
            local n = 0
            for _ in pairs(plan.warn_aug_mismatch or {}) do n = n + 1 end
            if n > 0 then
                util.warn(('Augment warnings (%d): some items matched/imported by name only; augments may not match exactly.'):format(n))
            end
        end
    end

    function M.print_plan_moves(plan, label)
        label = label or (plan.mode and plan.mode:upper()) or 'PLAN'
        local n = plan.moves and #plan.moves or 0
        if n == 0 then
            util.msg(('[%s] Planned moves: 0'):format(label))
            return
        end
        util.msg(('[%s] Planned moves: %d'):format(label, n))
        for i,mv in ipairs(plan.moves) do
            if i > 60 then util.warn(('...and %d more moves'):format(n - 60)); break end
            if mv.type == 'evict' then
                util.warn(('[%02d] EVICT  [%s] %s:slot%d -> %s   (%s)'):format(i, mv.group, mv.from_bag_name, mv.from_slot, mv.to_bag_name, mv.item_name))
            else
                local tag = mv.warn_aug_mismatch and ' [AUG?]' or ''
                util.warn(('[%02d] IMPORT [%s] %s%s   (%s:slot%d -> %s)'):format(i, mv.group, mv.item_name, tag, mv.from_bag_name, mv.from_slot, mv.to_bag_name))
            end
        end
    end

    -- Full single-plan output (used by exec path where only one mode is run).
    function M.print_plan(plan)
        M.print_plan_header(plan)
        M.print_plan_moves(plan, plan.mode and plan.mode:upper() or 'PLAN')
    end

    return M
end
