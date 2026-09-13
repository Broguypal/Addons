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
    local D = {}

    local MOG_GARDEN_ZONE = 280

    local avail    = { mog = false, porter = false }
    local relayout = {}
    local active   = 'mog'

    D.PANELS = { 'mog', 'porter' }
    D.LABELS = { mog = 'WARDROBE9', porter = 'PORTER' }

    function D.is_mog_garden()
        local info = windower.ffxi.get_info()
        if not info or not info.zone then return false end
        if info.zone == MOG_GARDEN_ZONE then return true end
        local z = res and res.zones and res.zones[info.zone]
        local zn = (z and z.en or ''):lower()
        return zn == 'mog garden'
    end

    function D.dual()
        return avail.mog and avail.porter
    end

    function D.available(which)
        return avail[which] == true
    end

    function D.active_panel()
        return active
    end

    function D.is_active(which)
        if not D.dual() then return true end
        return active == which
    end

    function D.hidden_by_dock(which)
        return D.dual() and active ~= which
    end

    function D.register(which, fn)
        relayout[which] = fn
    end

    local function refresh_all()
        for _, fn in pairs(relayout) do
            local ok = pcall(fn)
            if not ok then end
        end
    end

    function D.set_active(which)
        if active == which then return false end
        if not avail[which] then return false end
        active = which
        refresh_all()
        return true
    end

    function D.set_available(which, value)
        value = value and true or false
        if avail[which] == value then return false end

        local was_dual = D.dual()
        avail[which] = value

        if which == 'porter' and value and avail.mog then
            active = 'porter'
        elseif not avail[active] then
            if avail.mog then active = 'mog'
            elseif avail.porter then active = 'porter'
            else active = 'mog' end
        end

        if was_dual ~= D.dual() or value == false then
            refresh_all()
        end
        return true
    end

    return D
end
