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

return function(res, util, config)
    local M = {}

    function M.bag_id_by_name(target_name)
        target_name = util.normalize_bag_name(target_name):lower()
        for id, bag in pairs(res.bags) do
            if bag and bag.en and util.normalize_bag_name(bag.en):lower() == target_name then
                return id
            end
        end
        return nil
    end

    local function bag_info(id)
        if not id then return nil end
        return windower.ffxi.get_bag_info(id)
    end

    function M.bag_enabled(id)
        local bi = bag_info(id)
        return bi and bi.enabled == true
    end

    local function bag_capacity(id)
        local bi = bag_info(id)
        if not bi then return 0 end
        return bi.max or 0
    end

    local function bag_count(id)
        local bi = bag_info(id)
        if not bi then return 0 end
        return bi.count or 0
    end

    function M.bag_free(id)
        return math.max(0, bag_capacity(id) - bag_count(id))
    end

    function M.pick_return_bag_id()
        local order = config.RETURN_BAG_ORDER or {}
        for _, bn in ipairs(order) do
            local id = M.bag_id_by_name(bn)
            if id and M.bag_enabled(id) then
                return id, (res.bags[id] and res.bags[id].en) or bn
            end
        end
        return nil, nil
    end

    function M.build_dest_bags()
        local dest = {}
        local disabled = {}

        -- Prefer the normalized boolean-map config if present.
        -- Preserve a consistent, user-friendly order for Wardrobe 1..8.
        if type(config.DEST_BAGS) == 'table' then
            local ordered = {
                'Wardrobe','Wardrobe 2','Wardrobe 3','Wardrobe 4',
                'Wardrobe 5','Wardrobe 6','Wardrobe 7','Wardrobe 8',
            }
            for _, bn in ipairs(ordered) do
                if config.DEST_BAGS[bn] then
                    local id = M.bag_id_by_name(bn)
                    if id then
                        if M.bag_enabled(id) then
                            dest[#dest+1] = { id=id, name=(res.bags[id] and res.bags[id].en) or bn }
                        else
                            disabled[#disabled+1] = bn
                        end
                    end
                end
            end
        end

        return dest, disabled
    end

    return M
end
