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

return function(res)
    local M = {}

    local bit = _G.bit
    if not bit then
        local ok, b = pcall(require, 'bit')
        if ok then bit = b end
    end
    if not bit then bit = _G.bit32 end

    local function band(a, m)
        if bit and bit.band then return bit.band(a, m) end
        return nil
    end

    local SLOT_MASK = nil
    if res and res.slots then
        SLOT_MASK = {}
        for k,v in pairs(res.slots) do
            if type(k) == 'string' and type(v) == 'number' then
                SLOT_MASK[k:lower()] = v
            end
        end
    end

    local FALLBACK_MASK = {
        main=0x0001, sub=0x0002, range=0x0004, ammo=0x0008,
        head=0x0010, body=0x0020, hands=0x0040, legs=0x0080, feet=0x0100,
        neck=0x0200, waist=0x0400,
        left_ear=0x0800, right_ear=0x1000,
        left_ring=0x2000, right_ring=0x4000,
        back=0x8000,
    }
    M.FALLBACK_MASK = FALLBACK_MASK

    local SLOT_ID_TO_GROUP = {
        [0]='weapon', [1]='weapon', [2]='weapon',
        [3]='ammo',
        [4]='head', [5]='body', [6]='hands', [7]='legs', [8]='feet',
        [9]='neck', [10]='waist', [15]='back',
        [11]='ear', [12]='ear',
        [13]='ring', [14]='ring',
    }

    local SLOT_ID_PRIORITY = { 4,5,6,7,8,9,10,15,11,12,13,14,3,0,1,2 }

    local function group_from_numeric_slots(slots_tbl)
        for _,sid in ipairs(SLOT_ID_PRIORITY) do
            if slots_tbl[sid] then
                return SLOT_ID_TO_GROUP[sid]
            end
        end
        for _,sid in ipairs(SLOT_ID_PRIORITY) do
            if slots_tbl[sid+1] then
                return SLOT_ID_TO_GROUP[sid]
            end
        end
        return nil
    end

    function M.infer_group_for_item_id(item_id)
        local it = res.items[item_id]
        if not it or it.slots == nil then return nil end
        local slots = it.slots

        if type(slots) == 'table' then
            local function has(k) return slots[k] == true end
            if has('head') then return 'head' end
            if has('body') then return 'body' end
            if has('hands') then return 'hands' end
            if has('legs') then return 'legs' end
            if has('feet') then return 'feet' end
            if has('neck') then return 'neck' end
            if has('waist') then return 'waist' end
            if has('back') then return 'back' end
            if has('ear1') or has('ear2') or has('left_ear') or has('right_ear') then return 'ear' end
            if has('ring1') or has('ring2') or has('left_ring') or has('right_ring') then return 'ring' end
            if has('ammo') then return 'ammo' end
            if has('main') or has('sub') or has('range') then return 'weapon' end

            return group_from_numeric_slots(slots)
        end

        if type(slots) ~= 'number' then return nil end
        local MM = SLOT_MASK or FALLBACK_MASK

        local function has(slotname)
            local m = MM[slotname]
            if not m then return false end
            local r = band(slots, m)
            if r == nil then return false end
            return r ~= 0
        end

        if has('head') then return 'head' end
        if has('body') then return 'body' end
        if has('hands') then return 'hands' end
        if has('legs') then return 'legs' end
        if has('feet') then return 'feet' end
        if has('neck') then return 'neck' end
        if has('waist') then return 'waist' end
        if has('back') then return 'back' end
        if has('left_ear') or has('right_ear') or has('ear1') or has('ear2') then return 'ear' end
        if has('left_ring') or has('right_ring') or has('ring1') or has('ring2') then return 'ring' end
        if has('ammo') then return 'ammo' end
        if has('main') or has('sub') or has('range') then return 'weapon' end

        return nil
    end

	function M.group_from_bitmask(mask)
		if type(mask) ~= 'number' then return nil end
		local function has(slotname)
			local m = FALLBACK_MASK[slotname]
			if not m then return false end
			local r = band(mask, m)
			return r ~= nil and r ~= 0
		end
		if has('head') then return 'head' end
		if has('body') then return 'body' end
		if has('hands') then return 'hands' end
		if has('legs') then return 'legs' end
		if has('feet') then return 'feet' end
		if has('neck') then return 'neck' end
		if has('waist') then return 'waist' end
		if has('back') then return 'back' end
		if has('left_ear') or has('right_ear') then return 'ear' end
		if has('left_ring') or has('right_ring') then return 'ring' end
		if has('ammo') then return 'ammo' end
		if has('main') or has('sub') or has('range') then return 'weapon' end
		return nil
	end

    function M.band(a, m) return band(a, m) end

    return M
end
