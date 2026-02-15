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

return function(config)
    local M = {}

    local ui_logger = nil

    -- level: 'msg' | 'warn' | 'err'
    function M.set_ui_logger(fn)
        ui_logger = fn
    end

    local function push_ui(level, s)
        if ui_logger then
            pcall(ui_logger, level, s)
        end
    end

    function M.msg(s)
        if config and config.LOG_TO_CHAT then
            windower.add_to_chat(207, ('[W9] %s'):format(s))
        end
        push_ui('msg', s)
    end

    function M.warn(s)
        if config and config.LOG_TO_CHAT then
            windower.add_to_chat(167, ('[W9] %s'):format(s))
        end
        push_ui('warn', s)
    end

    function M.err(s)
        if config and config.LOG_TO_CHAT then
            windower.add_to_chat(123, ('[W9] %s'):format(s))
        end
        push_ui('err', s)
    end

    function M.trim(s)
        if type(s) ~= 'string' then return s end
        return (s:gsub('^%s+',''):gsub('%s+$',''))
    end

    function M.normalize_bag_name(name)
        return M.trim((name or ''):gsub('%s+',' '))
    end

    function M.group_for_slot(slot)
        if not slot then return nil end
        slot = slot:lower()
        return config.SLOT_GROUP[slot]
    end

    function M.is_protected_group(group)
        return group and config.PROTECTED_SLOT_GROUPS[group] == true
    end

    function M.is_excluded_source_bag(bag_name)
        if not bag_name then return false end
        local bn = M.normalize_bag_name(bag_name):lower()
        local ex = config and config.SOURCE_BAG_EXCLUDE
        if type(ex) ~= 'table' then return false end
        return ex[bn] == true
    end


    -- ======================================================
    -- Small helpers
    -- ======================================================

    function M.clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    function M.norm_slashes(p)
        return (p or ''):gsub('\\','/'):gsub('/+','/')
    end

    function M.safe_join(a, b)
        a = M.norm_slashes(a):gsub('/+$','')
        b = M.norm_slashes(b):gsub('^/+','')
        if a == '' then return b end
        if b == '' then return a end
        return a .. '/' .. b
    end

    function M.ensure_dir(path)
        path = M.norm_slashes(path):gsub('/+$','')
        if path == '' then return true end

        if windower and windower.dir_exists and windower.create_dir then
            if not windower.dir_exists(path) then
                windower.create_dir(path)
            end
            return true
        end

        local is_windows = (package.config:sub(1,1) == '\\')
        if is_windows then
            os.execute(('mkdir "%s"'):format(path))
        else
            os.execute(('mkdir -p "%s"'):format(path))
        end
        return true
    end


    -- ======================================================
    -- Augment normalization + item keying
    --
    -- These helpers produce strings compatible with the scan cache format:
    --   "Aug1;Aug2;Aug3" (sorted, ';' separated)
    -- and item keys:
    --   "Item Name" or "Item Name|Aug1;Aug2"
    -- ======================================================

    function M.canon_text(s)
        if type(s) ~= 'string' then return '' end

        s = s:gsub('\194\160', ' ')
        s = s:gsub('%s+', ' ')

        s = s:gsub('“', '"'):gsub('”', '"')
        s = s:gsub('‘', "'"):gsub('’', "'")

        return (s:gsub('^%s+',''):gsub('%s+$',''))
    end

    function M.normalize_aug_list(aug)
        if type(aug) ~= 'table' then return '' end
        local t = {}
        for _,a in ipairs(aug) do
            if type(a) == 'string' and a ~= '' then
                a = M.canon_text(a)
                if a ~= '' and a:lower() ~= 'none' then
                    t[#t+1] = a
                end
            end
        end
        table.sort(t)
        return table.concat(t, ';')
    end

    function M.normalize_aug_string(s)
        s = M.canon_text(s)
        if s == '' then return '' end

        local parts = {}
        for part in s:gmatch('[^,;]+') do
            part = M.canon_text(part)
            if part ~= '' and part:lower() ~= 'none' then
                parts[#parts+1] = part
            end
        end

        if #parts == 0 then return '' end
        table.sort(parts)
        return table.concat(parts, ';')
    end

    function M.make_item_key(val)
        if not val then return nil end

        if type(val) == 'string' then
            local name = M.trim(val)
            if name == '' then return nil end
            return name, name, ''
        end

        if type(val) == 'table' then
            local name = val.name or val.en or val.english or val[1]
            if type(name) ~= 'string' then return nil end
            name = M.trim(name)
            if name == '' then return nil end

            local aug = ''
            if type(val.augments) == 'table' then
                aug = M.normalize_aug_list(val.augments)
            elseif type(val.augment) == 'table' then
                aug = M.normalize_aug_list(val.augment)
            elseif type(val.aug) == 'string' then
                aug = M.normalize_aug_string(val.aug)
            end

            if aug ~= '' then
                return name .. '|' .. aug, name, aug
            end
            return name, name, ''
        end

        return nil
    end

    -- ======================================================
    -- Filesystem helpers (shared)
    -- ======================================================

    function M.file_exists(path)
        local f = io.open(path, 'rb')
        if f then f:close(); return true end
        return false
    end

    function M.lua_quote(s)
        s = tostring(s or '')
        return s:gsub('\\','\\\\'):gsub('"','\\"')
    end

    -- ======================================================
    -- GearSwap path resolution (shared by UI + planner)
    -- ======================================================

    local function windower_root()
        local ww = windower and windower.windower_path
        if type(ww) ~= 'string' or ww == '' then return nil end
        ww = M.norm_slashes(ww):gsub('/+$','')
        return ww
    end

    function M.get_gearswap_data_paths()
        local ww = windower_root()
        local base
        if ww then
            base = M.safe_join(ww, 'addons/GearSwap/data')
        else
            base = 'addons/GearSwap/data'
        end

        local player = windower and windower.ffxi and windower.ffxi.get_player and windower.ffxi.get_player() or nil
        local pname = player and player.name or nil

        local root = base
        local char = pname and M.safe_join(base, pname) or nil
        return root, char, pname
    end

    function M.resolve_gearswap_jobfile_path(filename)
        if type(filename) ~= 'string' or filename == '' then return nil end

        if M.file_exists(filename) then return filename end

        local name = filename
        if not name:lower():match('%.lua$') then name = name .. '.lua' end
        name = M.norm_slashes(name):gsub('^/','')

        local root = windower_root()
        local _root, _char, pname = M.get_gearswap_data_paths()

        local addons_cases = { 'addons', 'Addons' }
        local gs_cases = { 'GearSwap', 'gearswap' }

        local candidates = {}

        candidates[#candidates+1] = name

        if root then
            for _,a in ipairs(addons_cases) do
                for _,g in ipairs(gs_cases) do
                    local base = M.safe_join(root, a .. '/' .. g .. '/data')
                    candidates[#candidates+1] = M.safe_join(base, name)
                    candidates[#candidates+1] = M.safe_join(base, name:lower())
                    if pname then
                        candidates[#candidates+1] = M.safe_join(base, pname .. '/' .. name)
                        candidates[#candidates+1] = M.safe_join(base, pname .. '/' .. name:lower())
                    end
                end
            end
        end

        for _,a in ipairs(addons_cases) do
            for _,g in ipairs(gs_cases) do
                local base = a .. '/' .. g .. '/data'
                candidates[#candidates+1] = base .. '/' .. name
                candidates[#candidates+1] = base .. '/' .. name:lower()
                if pname then
                    candidates[#candidates+1] = base .. '/' .. pname .. '/' .. name
                    candidates[#candidates+1] = base .. '/' .. pname .. '/' .. name:lower()
                end
            end
        end

        for _,p in ipairs(candidates) do
            if M.file_exists(p) then return p end
        end

        return nil
    end

    return M
end
