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

Porter retrieval packet logic adapted from PorterPacker by Ivaar (MIT License)
and informed by Porter by Thorny (MIT License).
]]

return function(res, util, config, slots, bags, scanmod, planner)
    local M = {}

    require('pack')
    local slips_lib = nil
    do
        local ok, s = pcall(require, 'slips')
        if ok then slips_lib = s end
    end

    -- ======================================================
    -- Constants
    -- ======================================================

    local NPC_NAME      = 'Porter Moogle'
    local INTERACT_RANGE = 6   -- yalms

    -- Zone ID -> retrieve menu ID.
    -- Store menu = value - 1.
    local ZONE_MENU = {
        [26]  = 621,   -- Tavnazian Safehold
        [50]  = 959,   -- Aht Urhgan Whitegate
        [53]  = 330,   -- Nashmau
        [80]  = 661,   -- Southern San d'Oria [S]
        [87]  = 603,   -- Bastok Markets [S]
        [94]  = 525,   -- Windurst Waters [S]
        [231] = 874,   -- Northern San d'Oria
        [235] = 547,   -- Bastok Markets
        [240] = 870,   -- Port Windurst
        [245] = 10106, -- Lower Jeuno
        [247] = 138,   -- Rabao
        [248] = 1139,  -- Selbina
        [249] = 338,   -- Mhaura
        [250] = 309,   -- Kazham
        [252] = 246,   -- Norg
        [256] = 43,    -- Western Adoulin
        [280] = 802,   -- Mog Garden
    }

    -- ======================================================
    -- State machine  
    --
    -- Flow per item:
    --   1. Trade slip to NPC              → STATE_TRADED
    --   2. 0x034 menu received            → select ONE item via 0x05B
    --                                     → STATE_SELECTING
    --   3. 0x05C update received          → item confirmed retrieved
    --                                     → STATE_CLOSING
    --   4. Press escape to close menu     (after short delay)
    --   5. Wait for menu to fully close   (after another delay)
    --   6. Trade next slip or finish      → STATE_IDLE / STATE_TRADED
    --
    -- ONE packet per trade. NO retries. NO repeated sends.
    -- ======================================================

    local STATE_IDLE      = 0
    local STATE_TRADED    = 1  -- 0x036 sent, waiting for 0x034
    local STATE_SELECTING = 2  -- 0x05B item-select sent, waiting for 0x05C
    local STATE_CLOSING   = 3  -- item retrieved, closing menu via escape

	local state        = STATE_IDLE
    local retrieve_ids = {}        -- { [item_id] = true }
    local on_complete  = nil       -- callback when retrieval finishes

    -- Track what we're currently retrieving so we can log it on 0x05C.
    local pending_item_name = nil

    -- ======================================================
    -- Trade timeout safety net
    -- ======================================================

    local TRADE_TIMEOUT = 8  -- seconds before giving up
    local timeout_gen   = 0  -- generation counter

    local function schedule_timeout(expected_state)
        -- Bump generation so any previous pending timeout becomes stale.
        timeout_gen = timeout_gen + 1
        local my_gen = timeout_gen

        coroutine.schedule(function()
            -- Only fire if no state transition has happened since we scheduled.
            if timeout_gen == my_gen and state == expected_state then
                util.warn('Porter trade timed out (no server response). Aborting.')
                -- Hard reset to idle.
                state = STATE_IDLE
                retrieve_ids = {}
                pending_item_name = nil
                if on_complete then
                    local cb = on_complete
                    on_complete = nil
                    pcall(cb, false)
                end
            end
        end, TRADE_TIMEOUT)
    end

    function M.is_busy()
        return state ~= STATE_IDLE
    end

    -- ======================================================
    -- NPC detection
    -- ======================================================

    function M.find_porter_npc()
        if not windower or not windower.ffxi then return nil end
        local ok, npc = pcall(windower.ffxi.get_mob_by_name, NPC_NAME)
        if not ok or not npc then return nil end

        local dist = npc.distance and math.sqrt(npc.distance) or 999
        if dist < INTERACT_RANGE and npc.valid_target and npc.is_npc then
            return npc
        end
        return nil
    end

    function M.is_in_porter_zone()
        local info = windower.ffxi.get_info()
        if not info or not info.zone then return false end
        return ZONE_MENU[info.zone] ~= nil
    end

    -- ======================================================
    -- Slip helpers
    -- ======================================================

    local function get_slip_data()
        if not slips_lib then return nil end
        local ok, data = pcall(slips_lib.get_player_items)
        if not ok or type(data) ~= 'table' then return nil end
        return data
    end

    local function find_slip_in_inventory(slip_item_id)
        local inv = windower.ffxi.get_items(0)
        if not inv or not inv.max then return nil end
        for slot = 1, inv.max do
            local entry = inv[slot]
            if entry and entry.id == slip_item_id and entry.status == 0 then
                return entry
            end
        end
        return nil
    end

    -- Search all bags for a slip item and return the bag name where it lives.
    local SEARCH_BAGS = {
        {id=0,  name='Inventory'},
        {id=1,  name='Safe'},
        {id=2,  name='Storage'},
        {id=4,  name='Locker'},
        {id=5,  name='Satchel'},
        {id=6,  name='Sack'},
        {id=7,  name='Case'},
        {id=8,  name='Wardrobe'},
        {id=10, name='Wardrobe 2'},
        {id=11, name='Wardrobe 3'},
        {id=12, name='Wardrobe 4'},
        {id=13, name='Wardrobe 5'},
        {id=14, name='Wardrobe 6'},
        {id=15, name='Wardrobe 7'},
        {id=16, name='Wardrobe 8'},
        {id=17, name='Safe 2'},
    }

    local function find_slip_location(slip_item_id)
        if not windower or not windower.ffxi or not windower.ffxi.get_items then
            return nil
        end
        for _, bag in ipairs(SEARCH_BAGS) do
            local ok, contents = pcall(windower.ffxi.get_items, bag.id)
            if ok and contents and contents.max then
                for slot = 1, contents.max do
                    local entry = contents[slot]
                    if entry and entry.id == slip_item_id then
                        return bag.name
                    end
                end
            end
        end
        return nil
    end

    local function inventory_free_space()
        local bi = windower.ffxi.get_bag_info(0)
        if not bi then return 0 end
        return math.max(0, (bi.max or 0) - (bi.count or 0))
    end

    -- ======================================================
    -- Identify: cross-reference lua needed items with slips
    -- ======================================================

    function M.identify_needed_on_slips(jobfiles)
        if not slips_lib then
            return nil, 'The slips library is not available. Ensure it is installed in Windower.'
        end

        if type(jobfiles) ~= 'table' or #jobfiles == 0 then
            return nil, 'No files selected.'
        end

        -- Merge all needed items from selected luas.
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

        -- Build name -> item_id(s) reverse index.
        local name_to_ids = {}
        for id, entry in pairs(res.items) do
            if entry and entry.en then
                local nm = util.trim(entry.en)
                if nm ~= '' then
                    name_to_ids[nm] = name_to_ids[nm] or {}
                    name_to_ids[nm][#name_to_ids[nm]+1] = id
                end
            end
        end

        -- Get items on slips.
        local slip_data = get_slip_data()
        if not slip_data then
            return nil, 'Could not read slip data. Ensure the slips library is loaded.'
        end

        -- Build item_id -> {slip_item_id, slip_num, slip_label} lookup.
        -- Verify each item is actually stored with player_has_item().
        local on_slip = {}   -- item_id -> { slip_item_id, slip_num, slip_label }
        local has_check = slips_lib.player_has_item
        for slip_item_id, item_list in pairs(slip_data) do
            if type(item_list) == 'table' then
                local slip_num = slips_lib.storages and slips_lib.storages.find
                    and slips_lib.storages:find(slip_item_id)
                local label = slip_num and ('Slip %02d'):format(slip_num) or 'Slip'
                for _, item_id in ipairs(item_list) do
                    if item_id and item_id ~= 0
                       and (not has_check or has_check(item_id)) then
                        on_slip[item_id] = {
                            slip_item_id = slip_item_id,
                            slip_num     = slip_num,
                            slip_label   = label,
                        }
                    end
                end
            end
        end

        -- Cross-reference needed items with slip contents.
        local results = {}   -- { {name, group, item_id, slip_label, slip_item_id, slip_num, in_inventory} }
        local slip_ids_needed = {}  -- { [slip_item_id] = true }

        for key, info in pairs(merged) do
            local ids = name_to_ids[info.name]
            if ids then
                for _, id in ipairs(ids) do
                    if on_slip[id] then
                        local s = on_slip[id]
                        local inv_slip = find_slip_in_inventory(s.slip_item_id)
                        local location = nil
                        if inv_slip then
                            location = 'Inventory'
                        else
                            location = find_slip_location(s.slip_item_id)
                        end
                        results[#results+1] = {
                            name          = info.name,
                            group         = info.group,
                            item_id       = id,
                            slip_label    = s.slip_label,
                            slip_item_id  = s.slip_item_id,
                            slip_num      = s.slip_num,
                            in_inventory  = inv_slip ~= nil,
                            slip_location = location,
                        }
                        slip_ids_needed[s.slip_item_id] = true
                        break
                    end
                end
            end
        end

        table.sort(results, function(a, b)
            if a.slip_label == b.slip_label then return a.name < b.name end
            return a.slip_label < b.slip_label
        end)

        -- Check which needed slips are in inventory.
        local slips_in_inv = {}
        local slips_not_in_inv = {}  -- { [slip_item_id] = bag_name or true }
        for slip_item_id in pairs(slip_ids_needed) do
            if find_slip_in_inventory(slip_item_id) then
                slips_in_inv[slip_item_id] = true
            else
                local loc = find_slip_location(slip_item_id)
                slips_not_in_inv[slip_item_id] = loc or true
            end
        end

        return {
            label            = table.concat(labels, ', '),
            items            = results,
            slips_in_inv     = slips_in_inv,
            slips_not_in_inv = slips_not_in_inv,
            free_space       = inventory_free_space(),
        }
    end

    -- ======================================================
    -- Packet helpers (adapted from PorterPacker by Ivaar)
    -- ======================================================

    local function trade_npc(npc, items)
        local str = 'I2':pack(0, npc.id)
        for x = 1, 8 do
            str = str .. 'I':pack(items[x] and items[x].count or 0)
        end
        str = str .. 'I2':pack(0, 0)
        for x = 1, 8 do
            str = str .. 'C':pack(items[x] and items[x].slot or 0)
        end
        str = str .. 'C2HI':pack(0, 0, npc.index, #items > 8 and 8 or #items)
        windower.packets.inject_outgoing(0x36, str)
        state = STATE_TRADED
		schedule_timeout(STATE_TRADED)  -- abort if 0x034 menu never arrives
    end

    local function inject_option(npc_id, npc_index, zone_id, menu_id, option_index, bool)
        windower.packets.inject_outgoing(0x5B,
            'I3H4':pack(0, npc_id, option_index, npc_index, bool, zone_id, menu_id))
        return true
    end

    -- ======================================================
    -- Escape key helper
    -- ======================================================

    local function send_escape()
        windower.send_command('setkey escape down')
        coroutine.schedule(function()
            windower.send_command('setkey escape up')
        end, 0.1)
    end

    -- Forward declaration (used by handle_update before definition).
    local porter_trade_next

    -- ======================================================
    -- Handle 0x034: menu opened after trade → select ONE item
    -- ======================================================

    -- Close the NPC menu via escape, wait for it to settle,
    -- then chain to porter_trade_next for the next item.
    local function close_menu_and_continue()
        state = STATE_CLOSING
        coroutine.schedule(function()
            send_escape()
            coroutine.schedule(function()
                state = STATE_IDLE
                porter_trade_next()
            end, 1.5)
        end, 0.5)
    end

    local function handle_menu(data)
        if #data < 0x2E then return false end

        local zone_id = data:unpack('H', 0x2A+1)
        local mid     = data:unpack('H', 0x2C+1)
        if not ZONE_MENU[zone_id] or ZONE_MENU[zone_id] ~= mid then
            return false
        end

        local npc_id    = data:unpack('I', 0x04+1)
        local npc_index = data:unpack('H', 0x28+1)

        if inventory_free_space() == 0 then
            util.warn('Inventory full. Closing menu.')
            close_menu_and_continue()
            return true
        end

        local stored_items = data:sub(0x08+1, 0x1F+1)
        local slip_number  = data:unpack('I', 0x24+1) + 1

        if not slips_lib or not slips_lib.items or not slips_lib.storages then
            close_menu_and_continue()
            return true
        end

        local slip_item_list = slips_lib.items[slips_lib.storages[slip_number]]
        if not slip_item_list then
            close_menu_and_continue()
            return true
        end

        -- Scan bitmask for the FIRST needed item. ONE item per trade cycle.
        local option_index = 0
        for bit_position = 0, 191 do
            if stored_items:unpack('b', math.floor(bit_position/8)+1, bit_position%8+1) == 1 then
                local item_id = slip_item_list[bit_position+1]
                if item_id and retrieve_ids[item_id] then
                    -- Found a needed item. Select it.
                    pending_item_name = res.items[item_id] and res.items[item_id].en or tostring(item_id)
                    retrieve_ids[item_id] = nil  -- Remove NOW so we don't pick it again
                    state = STATE_SELECTING
                    inject_option(npc_id, npc_index, zone_id, mid, option_index, 1)
                    schedule_timeout(STATE_SELECTING)  -- abort if 0x05C confirmation never arrives
                    return true
                end
                option_index = option_index + 1
            end
        end

        -- No matching item found on this slip — close and move on.
        close_menu_and_continue()
        return true
    end

    -- ======================================================
    -- Handle 0x05C: item retrieval confirmed
    -- ======================================================

    local function handle_update(data)
        -- Log the successful retrieval.
        local name = pending_item_name or 'item'
        pending_item_name = nil
        util.msg(('Retrieved: %s'):format(name))

        -- Close the menu via escape, then trade the next item after a delay.
        close_menu_and_continue()
    end

    -- ======================================================
    -- Finish / reset
    -- ======================================================

    local function finish(success)
        state = STATE_IDLE
        retrieve_ids = {}
        pending_item_name = nil
        if on_complete then
            local cb = on_complete
            on_complete = nil
            pcall(cb, success)
        end
    end

    -- ======================================================
    -- Trade loop: finds the next slip to trade
    -- ======================================================

    porter_trade_next = function()
        if state ~= STATE_IDLE then return end

        if next(retrieve_ids) == nil then
            finish(true)
            return
        end

        local npc = M.find_porter_npc()
        if not npc then
            util.err('Porter Moogle is no longer in range. Retrieval aborted.')
            finish(false)
            return
        end

        if inventory_free_space() == 0 then
            util.warn('Inventory is full. Retrieval stopped.')
            finish(false)
            return
        end

        -- Re-read slip data fresh each cycle (inventory changes after each retrieval).
        local slip_data = get_slip_data()
        if not slip_data then
            util.err('Could not read slip data.')
            finish(false)
            return
        end

        for slip_item_id, item_list in pairs(slip_data) do
            if type(item_list) == 'table' then
                for _, item_id in ipairs(item_list) do
                    if retrieve_ids[item_id] then
                        local slip_entry = find_slip_in_inventory(slip_item_id)
                        if slip_entry then
                            util.msg('Trading slip to Porter Moogle...')
                            trade_npc(npc, {slip_entry})
                            -- state is now STATE_TRADED (set by trade_npc)
                            return
                        else
                            local slip_num = slips_lib.storages and slips_lib.storages:find(slip_item_id)
                            local label = slip_num and ('Slip %02d'):format(slip_num) or 'Slip'
                            local loc = find_slip_location(slip_item_id)
                            if loc then
                                util.err(('%s is not in your inventory (found in %s).'):format(label, loc))
                            else
                                util.err(('%s is not in your inventory.'):format(label))
                            end
                            -- Remove all items on this slip from retrieve list
                            -- so we don't loop forever on an inaccessible slip.
                            for _, rid in ipairs(item_list) do
                                retrieve_ids[rid] = nil
                            end
                        end
                    end
                end
            end
        end

        -- If we get here, no matching slips found.
        if next(retrieve_ids) then
            util.warn('Some items could not be retrieved. Required slips are not in inventory.')
            finish(false)
        else
            finish(true)
        end
    end

    -- ======================================================
    -- Public: start retrieval
    -- ======================================================

    function M.retrieve(identified_result, callback)
        if state ~= STATE_IDLE then
            util.warn('Porter retrieval is already in progress.')
            return false
        end

        if not slips_lib then
            util.err('The slips library is not available.')
            return false
        end

        if not identified_result or not identified_result.items or #identified_result.items == 0 then
            util.warn('No items to retrieve. Press SCAN SLIPS first.')
            return false
        end

        local npc = M.find_porter_npc()
        if not npc then
            util.err('Porter Moogle is not in range.')
            return false
        end

        if inventory_free_space() == 0 then
            util.err('Inventory is full. Free up space before retrieving.')
            return false
        end

        -- Check ALL needed slips are in inventory before starting.
        local missing_slips = {}
        for slip_item_id, location in pairs(identified_result.slips_not_in_inv or {}) do
            local slip_num = slips_lib.storages and slips_lib.storages:find(slip_item_id)
            local label = slip_num and ('Slip %02d'):format(slip_num) or 'Slip'
            if type(location) == 'string' then
                label = label .. (' (in %s)'):format(location)
            end
            missing_slips[#missing_slips+1] = label
        end

        if #missing_slips > 0 then
            table.sort(missing_slips)
            util.err(('Cannot retrieve: slip(s) not in inventory: %s'):format(
                table.concat(missing_slips, ', ')))
            util.err('Move the required slip(s) to your inventory and try again.')
            return false
        end

        -- Build the retrieve set.
        retrieve_ids = {}
        local count = 0
        for _, item in ipairs(identified_result.items) do
            if not retrieve_ids[item.item_id] then
                retrieve_ids[item.item_id] = true
                count = count + 1
            end
        end

        if count == 0 then
            util.msg('No items to retrieve.')
            return false
        end

        on_complete = callback
        pending_item_name = nil
        util.msg(('Retrieving %d item(s) from Porter Moogle...'):format(count))
        porter_trade_next()
        return true
    end

    function M.abort()
        if state ~= STATE_IDLE then
            util.warn('Porter retrieval aborted.')
            state = STATE_IDLE
            retrieve_ids = {}
            on_complete = nil
            pending_item_name = nil
        end
    end

    -- ======================================================
    -- Packet event handlers
    -- ======================================================

    function M.on_incoming_chunk(id, data)
        if state == STATE_IDLE then return end

        -- 0x034: NPC menu opened after trade. Select one item.
        if id == 0x034 and state == STATE_TRADED then
            handle_menu(data)
            return
        end

        -- 0x05C: Server confirmed the item retrieval.
        if id == 0x05C and state == STATE_SELECTING then
            handle_update(data)
            return
        end
    end

    return M
end
