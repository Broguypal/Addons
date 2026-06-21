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

--   return { files = { ["<full path lowercased>"] = "fav" | "low", ... } }

return function(util, ADDON_PATH, PREFS_FILE)
    local M = {}

    -- in-memory map: key -> 'fav' | 'low'
    local prefs = {}

    local function norm_key(path)
        if type(path) ~= 'string' or path == '' then return nil end
        return util.lkey(util.norm_slashes(path))
    end

    function M.load()
        prefs = {}
        local ok, t = pcall(dofile, PREFS_FILE)
        if ok and type(t) == 'table' and type(t.files) == 'table' then
            for path, st in pairs(t.files) do
                if type(path) == 'string' and (st == 'fav' or st == 'low') then
                    prefs[util.lkey(util.norm_slashes(path))] = st
                end
            end
        end
        return prefs
    end

    function M.save()
        util.ensure_dir(ADDON_PATH)

        local f, e = io.open(PREFS_FILE, 'w')
        if not f then
            util.warn(('Could not save priorities: %s'):format(tostring(e)))
            return false
        end

        f:write('return { files = {\n')

        local keys = {}
        for k in pairs(prefs) do keys[#keys+1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            f:write(('  ["%s"] = "%s",\n'):format(util.lua_quote(k), prefs[k]))
        end

        f:write('} }\n')
        f:close()
        return true
    end

    -- Returns 'fav' | 'low' | nil
    function M.get(path)
        local k = norm_key(path)
        if not k then return nil end
        return prefs[k]
    end

    function M.toggle(path, which)
        local k = norm_key(path)
        if not k then return nil end
        if which ~= 'fav' and which ~= 'low' then return prefs[k] end

        if prefs[k] == which then
            prefs[k] = nil
        else
            prefs[k] = which
        end

        M.save()
        return prefs[k]
    end

    M.load()

    return M
end
