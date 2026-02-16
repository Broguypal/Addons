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

return function(res, util, scanmod, planner, execmod, mousemod)
    local ui = {}

    local texts = require('texts')

    local PX = {
        -- Panel outer width (fixed)
        PANEL_W     = 480,

        -- Padding inside the panel edge
        PAD         = 8,

        -- Header / title bar (drag target)
        HEADER_H    = 24,

        -- Buttons
        BTN_W       = 72,
        BTN_H       = 18,
        BTN_GAP     = 8,
        BTN_Y       = 30,          -- px below panel top

        -- Status line
        STATUS_Y    = 54,

        -- File list
        FILE_Y      = 72,          -- px below panel top
        FILE_ROWS   = 5,

        -- Gap between file list bottom and log label
        SECTION_GAP = 20,

        -- Log
        LOG_ROWS    = 17,
        LOG_LABEL_H = 16,          -- "Notifications" label height

        -- Scrollbar (flush right inside panel)
        SB_W        = 12,
        SB_BTN_H    = 16,          -- up/down arrow button height

        -- Row height fallback (overridden by measurement)
        ROW_H       = 16,

        -- Bottom padding
        BOTTOM_PAD  = 8,
    }

    -- ==========================================================================
    -- Font metrics (measured at runtime)
    -- ==========================================================================

    local FONT_NAME = 'Consolas'
    local FONT_SIZE = 10

    local _measured_char_w = nil
    local _measured_row_h  = nil

    local function char_w()
        return _measured_char_w or 7.5
    end

    local function row_h()
        return _measured_row_h or PX.ROW_H
    end

    -- How many characters fit in a pixel width.
    local function chars_in(px_width)
        local cw = char_w()
        if cw <= 0 then return 60 end
        return math.floor(px_width / cw)
    end

    -- ==========================================================================
    -- Derived geometry helpers
    -- ==========================================================================

    local function content_w()
        return PX.PANEL_W - PX.PAD * 2 - PX.SB_W
    end

    local function file_list_h()
        return PX.FILE_ROWS * row_h()
    end

    local function log_y_off()
        return PX.FILE_Y + file_list_h() + PX.SECTION_GAP + PX.LOG_LABEL_H
    end

    local function log_list_h()
        return PX.LOG_ROWS * row_h()
    end

    local function panel_h()
        return log_y_off() + log_list_h() + PX.BOTTOM_PAD
    end

    -- ==========================================================================
    -- Mutable position (draggable)
    -- ==========================================================================

    local UI = {
        x = 420,
        y = 220,
        visible = false,
    }

    -- ==========================================================================
    -- Colors
    -- ==========================================================================

    local C = {
        text    = {255, 235, 235, 235},
        subtle  = {255, 190, 190, 190},

        panel_bg = {220,  20,  20,  20},
        btn_bg   = {255,  45,  45,  45},
        btn_hov  = {255,  70,  70,  70},
        btn_txt  = {255, 245, 245, 245},

        sel_bg   = {255,  60,  60,  90},

        sb_track = {120,  60,  60,  60},
        sb_thumb = {255, 160, 160, 220},

        log_msg     = {255, 200, 220, 255},
        log_warn    = {255, 255, 220, 140},
        log_err     = {255, 255, 160, 160},

        log_missing = {255, 255,  80,  80},
        log_note    = {255, 255,  80,  80},
        log_evict   = {255, 255, 190, 120},
        log_import  = {255, 160, 220, 255},
    }

    -- ==========================================================================
    -- State
    -- ==========================================================================

    local state = {
        files          = {},
        selected_index = nil,
        last_plan      = nil,
        status         = 'Ready.',
        hover          = nil,

        file_scroll = 0,

        log_lines     = {},
        log_scroll    = 0,
        log_max_lines = 300,

        dragging       = false,
        drag_dx        = 0,
        drag_dy        = 0,

        file_sb_dragging    = false,
        file_sb_drag_offset = 0,

        log_sb_dragging     = false,
        log_sb_drag_offset  = 0,
    }

    -- ==========================================================================
    -- Text objects
    -- ==========================================================================

    local t_panel   = texts.new('')
    local t_title   = texts.new('')
    local t_status  = texts.new('')

    local t_btn_scan = texts.new('')
    local t_btn_plan = texts.new('')
    local t_btn_exec = texts.new('')

    local t_file_rows     = {}
    local t_file_sb_track = texts.new('')
    local t_file_sb_thumb = texts.new('')
    local t_file_sb_up    = texts.new('')
    local t_file_sb_down  = texts.new('')

    local t_log_title    = texts.new('')
    local t_log_rows     = {}
    local t_log_sb_track = texts.new('')
    local t_log_sb_thumb = texts.new('')
    local t_log_sb_up    = texts.new('')
    local t_log_sb_down  = texts.new('')

    -- ---- Shared text-object helpers ----

    local function apply_text_defaults(t)
        t:font(FONT_NAME)
        t:size(FONT_SIZE)
        t:bg_alpha(0)
        t:visible(UI.visible)
    end

    local function set_color(t, rgba)
        t:color(rgba[1], rgba[2], rgba[3], rgba[4])
    end

    local function set_bg(t, rgba)
        t:bg_color(rgba[2], rgba[3], rgba[4])
        t:bg_alpha(rgba[1])
    end

    local function pad_right(s, w)
        s = s or ''
        if #s >= w then return s:sub(1, w) end
        return s .. string.rep(' ', w - #s)
    end

    -- ==========================================================================
    -- Scrolling helpers
    -- ==========================================================================

    local function max_file_scroll()
        local n = #state.files
        if n <= PX.FILE_ROWS then return 0 end
        return n - PX.FILE_ROWS
    end

    local function ensure_file_scroll_valid()
        state.file_scroll = util.clamp(state.file_scroll or 0, 0, max_file_scroll())
    end

    local function ensure_selection_visible()
        if not state.selected_index then return end
        local idx = state.selected_index
        local top = state.file_scroll + 1
        local bot = state.file_scroll + PX.FILE_ROWS

        if idx < top then
            state.file_scroll = idx - 1
        elseif idx > bot then
            state.file_scroll = idx - PX.FILE_ROWS
        end
        ensure_file_scroll_valid()
    end

    local function max_log_scroll()
        local n = #state.log_lines
        if n <= PX.LOG_ROWS then return 0 end
        return n - PX.LOG_ROWS
    end

    local function ensure_log_scroll_valid()
        state.log_scroll = util.clamp(state.log_scroll or 0, 0, max_log_scroll())
    end

    -- ==========================================================================
    -- Mog house detection
    -- ==========================================================================

    local function is_mog_house()
        local info = windower.ffxi.get_info()
        if info and info.mog_house ~= nil then
            return info.mog_house == true
        end
        if info and info.zone and res and res.zones
           and res.zones[info.zone] and res.zones[info.zone].en then
            local zn = (res.zones[info.zone].en or ''):lower()
            if zn:find('mog') then return true end
        end
        return false
    end

    -- ==========================================================================
    -- File listing
    -- ==========================================================================

    local function list_lua_files_in_dir(dirpath)
        local out = {}
        if not dirpath or dirpath == '' then return out end

        if windower.get_dir then
            local ok, files = pcall(windower.get_dir, dirpath)
            if ok and type(files) == 'table' then
                for _, fn in ipairs(files) do
                    if type(fn) == 'string' and fn:lower():match('%.lua$') then
                        out[#out + 1] = fn
                    end
                end
            end
        end

        table.sort(out, function(a, b) return a:lower() < b:lower() end)
        return out
    end

    local function refresh_file_list()
        state.files = {}
        state.selected_index = nil
        state.file_scroll = 0

        local root, char, pname = util.get_gearswap_data_paths()

        for _, fn in ipairs(list_lua_files_in_dir(root)) do
            state.files[#state.files + 1] = {
                label    = fn,
                rel      = fn,
                scope    = 'root',
                fullpath = util.safe_join(root, fn),
            }
        end

        for _, fn in ipairs(list_lua_files_in_dir(char)) do
            state.files[#state.files + 1] = {
                label    = (pname and (pname .. '/' .. fn)) or ('CHAR/' .. fn),
                rel      = fn,
                scope    = 'char',
                fullpath = util.safe_join(char, fn),
            }
        end

        ensure_file_scroll_valid()
        state.status = ('Found %d GearSwap lua(s).'):format(#state.files)
    end

    local function selected_file_rel()
        if not state.selected_index then return nil end
        local rec = state.files[state.selected_index]
        return rec and rec.rel or nil
    end

    -- ==========================================================================
    -- Hit-test rectangles 
    -- ==========================================================================

    local Rect = {}

    function Rect.header()
        return UI.x, UI.y, PX.PANEL_W, PX.HEADER_H
    end

    function Rect.btn(which)
        local bx = UI.x + PX.PAD
        local by = UI.y + PX.BTN_Y
        if which == 'scan' then
            return bx, by, PX.BTN_W, PX.BTN_H
        elseif which == 'plan' then
            return bx + PX.BTN_W + PX.BTN_GAP, by, PX.BTN_W, PX.BTN_H
        else
            return bx + (PX.BTN_W + PX.BTN_GAP) * 2, by, PX.BTN_W, PX.BTN_H
        end
    end

    function Rect.file_list()
        local lx = UI.x + PX.PAD
        local ly = UI.y + PX.FILE_Y
        return lx, ly, content_w(), PX.FILE_ROWS * row_h()
    end

    function Rect.log()
        local lx = UI.x + PX.PAD
        local ly = UI.y + log_y_off()
        return lx, ly, content_w(), PX.LOG_ROWS * row_h()
    end

    -- ---- File scrollbar  ----

    local function file_sb_x() return UI.x + PX.PANEL_W - PX.SB_W end
    local function file_sb_y() return UI.y + PX.FILE_Y end
    local function file_sb_h() return PX.FILE_ROWS * row_h() end

    function Rect.file_sb_upbtn()
        return file_sb_x(), file_sb_y(), PX.SB_W, PX.SB_BTN_H
    end

    function Rect.file_sb_downbtn()
        return file_sb_x(), file_sb_y() + file_sb_h() - PX.SB_BTN_H, PX.SB_W, PX.SB_BTN_H
    end

    function Rect.file_scrollbar()
        local ty = file_sb_y() + PX.SB_BTN_H
        local th = math.max(PX.SB_BTN_H, file_sb_h() - PX.SB_BTN_H * 2)
        return file_sb_x(), ty, PX.SB_W, th
    end

    function Rect.file_thumb()
        local tx, ty, tw, th = Rect.file_scrollbar()
        local total   = #state.files
        local visible = PX.FILE_ROWS
        if total <= visible then return tx, ty, tw, th end

        local thumb_h = math.max(row_h(), math.floor(th * (visible / total)))
        local ms = max_file_scroll()
        local yoff = 0
        if ms > 0 then yoff = math.floor((state.file_scroll / ms) * (th - thumb_h)) end
        return tx, ty + yoff, tw, thumb_h
    end

    -- ---- Log scrollbar ----

    local function log_sb_x() return UI.x + PX.PANEL_W - PX.SB_W end
    local function log_sb_y() return UI.y + log_y_off() end
    local function log_sb_h() return PX.LOG_ROWS * row_h() end

    function Rect.log_sb_upbtn()
        return log_sb_x(), log_sb_y(), PX.SB_W, PX.SB_BTN_H
    end

    function Rect.log_sb_downbtn()
        return log_sb_x(), log_sb_y() + log_sb_h() - PX.SB_BTN_H, PX.SB_W, PX.SB_BTN_H
    end

    function Rect.log_scrollbar()
        local ty = log_sb_y() + PX.SB_BTN_H
        local th = math.max(PX.SB_BTN_H, log_sb_h() - PX.SB_BTN_H * 2)
        return log_sb_x(), ty, PX.SB_W, th
    end

    function Rect.log_thumb()
        local tx, ty, tw, th = Rect.log_scrollbar()
        local total   = #state.log_lines
        local visible = PX.LOG_ROWS
        if total <= visible then return tx, ty, tw, th end

        local thumb_h = math.max(row_h(), math.floor(th * (visible / total)))
        local ms = max_log_scroll()
        local yoff = 0
        if ms > 0 then yoff = math.floor((state.log_scroll / ms) * (th - thumb_h)) end
        return tx, ty + yoff, tw, thumb_h
    end

    -- ---- Generic hit-test ----

    function Rect.point_in(mx, my, x, y, w, h)
        return mx >= x and mx <= (x + w) and my >= y and my <= (y + h)
    end

    local SB_HIT_PAD_X = 6
    local SB_HIT_PAD_Y = 4

    function Rect.point_in_pad(mx, my, x, y, w, h, pad_x, pad_y)
        pad_x = pad_x or 0
        pad_y = pad_y or 0
        return Rect.point_in(mx, my, x - pad_x, y - pad_y, w + pad_x * 2, h + pad_y * 2)
    end

    -- ==========================================================================
    -- Render helpers
    -- ==========================================================================

    local Render = {}

    function Render.ensure_rows(tbl, n)
        for i = 1, n do
            if not tbl[i] then
                tbl[i] = texts.new('')
                apply_text_defaults(tbl[i])
            end
        end
    end

    function Render.make_block(rows, cols)
        local line = string.rep(' ', math.max(1, cols))
        local lines = {}
        for _ = 1, math.max(1, rows) do lines[#lines + 1] = line end
        return table.concat(lines, '\n')
    end

    function Render.set_block(t, x, y, rows, cols, bg)
        if x and y then t:pos(x, y) end
        t:text(Render.make_block(rows, cols))
        set_bg(t, bg)
        t:visible(true)
    end

    function Render.scrollbar(track_obj, thumb_obj, track_fn, thumb_fn)
        local sx, sy, sw, sh = track_fn()
        local tc = math.max(1, chars_in(sw))
        local tr = math.max(1, math.floor(sh / row_h()))
        track_obj:pos(sx, sy)
        track_obj:text(Render.make_block(tr, tc))
        set_bg(track_obj, C.sb_track)
        track_obj:visible(true)

        local tx, ty, tw, th = thumb_fn()
        local thc = math.max(1, chars_in(tw))
        local thr = math.max(1, math.floor(th / row_h()))
        thumb_obj:pos(tx, ty)
        thumb_obj:text(Render.make_block(thr, thc))
        set_bg(thumb_obj, C.sb_thumb)
        thumb_obj:visible(true)
    end

    function Render.sb_btn(t, which, label)
        local c = math.max(1, chars_in(PX.SB_W))
        t:text(pad_right(label, c))
        set_color(t, C.btn_txt)
        set_bg(t, state.hover == which and C.btn_hov or C.sb_track)
        t:visible(true)
    end

    -- ==========================================================================
    -- Visibility toggle
    -- ==========================================================================

    local function set_all_visible(v)
        local objs = {
            t_panel, t_title, t_status,
            t_btn_scan, t_btn_plan, t_btn_exec,
            t_file_sb_track, t_file_sb_thumb, t_file_sb_up, t_file_sb_down,
            t_log_title,
            t_log_sb_track, t_log_sb_thumb, t_log_sb_up, t_log_sb_down,
        }
        for _, t in ipairs(objs) do if t then t:visible(v) end end
        for _, t in pairs(t_file_rows) do if t then t:visible(v) end end
        for _, t in pairs(t_log_rows)  do if t then t:visible(v) end end
    end

    -- ==========================================================================
    -- Reposition — pure pixel offsets from (UI.x, UI.y)
    -- ==========================================================================

    local function reposition_all()
        t_panel:pos(UI.x, UI.y)
        t_title:pos(UI.x + PX.PAD, UI.y + 4)
        t_status:pos(UI.x + PX.PAD, UI.y + PX.STATUS_Y)

        -- Buttons
        do
            local bx, by = Rect.btn('scan');  t_btn_scan:pos(bx, by)
            bx, by = Rect.btn('plan');        t_btn_plan:pos(bx, by)
            bx, by = Rect.btn('exec');        t_btn_exec:pos(bx, by)
        end

        -- File rows
        do
            local lx = UI.x + PX.PAD
            local ly = UI.y + PX.FILE_Y
            Render.ensure_rows(t_file_rows, PX.FILE_ROWS)
            for i = 1, PX.FILE_ROWS do
                t_file_rows[i]:pos(lx, ly + (i - 1) * row_h())
            end
            local ux, uy = Rect.file_sb_upbtn();    t_file_sb_up:pos(ux, uy)
            local dx, dy = Rect.file_sb_downbtn();   t_file_sb_down:pos(dx, dy)
            local sx, sy = Rect.file_scrollbar();    t_file_sb_track:pos(sx, sy)
            local tx, ty = Rect.file_thumb();        t_file_sb_thumb:pos(tx, ty)
        end

        -- Log rows
        do
            local lx = UI.x + PX.PAD
            t_log_title:pos(lx, UI.y + log_y_off() - PX.LOG_LABEL_H)

            local ly = UI.y + log_y_off()
            Render.ensure_rows(t_log_rows, PX.LOG_ROWS)
            for i = 1, PX.LOG_ROWS do
                t_log_rows[i]:pos(lx, ly + (i - 1) * row_h())
            end
            local ux, uy = Rect.log_sb_upbtn();     t_log_sb_up:pos(ux, uy)
            local dx, dy = Rect.log_sb_downbtn();    t_log_sb_down:pos(dx, dy)
            local sx, sy = Rect.log_scrollbar();     t_log_sb_track:pos(sx, sy)
            local tx, ty = Rect.log_thumb();         t_log_sb_thumb:pos(tx, ty)
        end
    end

    -- ==========================================================================
    -- Main layout / render
    -- ==========================================================================

    local function layout()
        local all_fixed = {
            t_panel, t_title, t_status,
            t_btn_scan, t_btn_plan, t_btn_exec,
            t_file_sb_track, t_file_sb_thumb, t_file_sb_up, t_file_sb_down,
            t_log_title,
            t_log_sb_track, t_log_sb_thumb, t_log_sb_up, t_log_sb_down,
        }
        for _, t in ipairs(all_fixed) do apply_text_defaults(t) end

        if not UI.visible then
            Render.ensure_rows(t_file_rows, PX.FILE_ROWS)
            Render.ensure_rows(t_log_rows, PX.LOG_ROWS)
            set_all_visible(false)
            return
        end

        -- Panel background
        local pcols = chars_in(PX.PANEL_W)
        local prows = math.max(1, math.floor(panel_h() / row_h()))
        Render.set_block(t_panel, UI.x, UI.y, prows, pcols, C.panel_bg)

        -- Title
        t_title:text('Wardrobe9 — Mog House')
        set_color(t_title, C.text)
        t_title:visible(true)

        -- Status
        t_status:text(state.status or '')
        set_color(t_status, C.subtle)
        t_status:visible(true)

        -- Buttons
        do
            local bc = chars_in(PX.BTN_W)
            local function rbtn(t, label, which)
                t:text(pad_right(label, bc))
                set_color(t, C.btn_txt)
                set_bg(t, state.hover == which and C.btn_hov or C.btn_bg)
                t:visible(true)
            end
            rbtn(t_btn_scan, '[ SCAN ]', 'scan')
            rbtn(t_btn_plan, '[ PLAN ]', 'plan')
            rbtn(t_btn_exec, '[ EXEC ]', 'exec')
        end

        -- File rows
        local rc = chars_in(content_w())
        Render.ensure_rows(t_file_rows, PX.FILE_ROWS)
        ensure_file_scroll_valid()
        for vis = 1, PX.FILE_ROWS do
            local abs = state.file_scroll + vis
            local t   = t_file_rows[vis]
            local rec = state.files[abs]
            if rec then
                local sel    = (state.selected_index == abs)
                local prefix = sel and '> ' or '  '
                t:text(pad_right(prefix .. rec.label, rc))
                if sel then set_bg(t, C.sel_bg) else t:bg_alpha(0) end
                set_color(t, C.text)
            else
                t:text(pad_right('', rc))
                t:bg_alpha(0)
            end
            t:visible(true)
        end

        -- File scrollbar
        Render.scrollbar(t_file_sb_track, t_file_sb_thumb, Rect.file_scrollbar, Rect.file_thumb)
        Render.sb_btn(t_file_sb_up,   'file_sb_up',   '^')
        Render.sb_btn(t_file_sb_down, 'file_sb_down', 'v')

        -- Log label
        t_log_title:text('Notifications')
        set_color(t_log_title, C.subtle)
        t_log_title:visible(true)

        -- Log rows
        Render.ensure_rows(t_log_rows, PX.LOG_ROWS)
        ensure_log_scroll_valid()
        for vis = 1, PX.LOG_ROWS do
            local abs = state.log_scroll + vis
            local t   = t_log_rows[vis]
            local rec = state.log_lines[abs]
            if rec then
                t:text(rec.text)
                set_color(t, rec.color or C.text)
            else
                t:text('')
            end
            t:bg_alpha(0)
            t:visible(true)
        end

        -- Log scrollbar
        Render.scrollbar(t_log_sb_track, t_log_sb_thumb, Rect.log_scrollbar, Rect.log_thumb)
        Render.sb_btn(t_log_sb_up,   'log_sb_up',   '^')
        Render.sb_btn(t_log_sb_down, 'log_sb_down', 'v')

        reposition_all()
    end

    -- ==========================================================================
    -- Notifications / log
    -- ==========================================================================

    local function wrap_text(s, width, cont_indent)
        s = tostring(s or '')
        width = math.max(8, tonumber(width) or 60)
        cont_indent = cont_indent or ''
        local out = {}

        local function rtrim(x) return (x:gsub('%s+$', '')) end

        local first = true
        while #s > 0 do
            local w = width
            if not first then w = math.max(8, width - #cont_indent) end

            if #s <= w then
                local line = rtrim(s)
                if not first and cont_indent ~= '' then line = cont_indent .. line end
                out[#out + 1] = line
                break
            end

            local cut = w
            local sub = s:sub(1, w)
            local sp  = sub:match('^.*()%s')
            if sp and sp > 8 then cut = sp end

            local chunk = rtrim(s:sub(1, cut))
            s = s:sub(cut + 1):gsub('^%s+', '')
            if not first and cont_indent ~= '' then chunk = cont_indent .. chunk end
            out[#out + 1] = chunk
            first = false
        end
        return out
    end

    local function pick_log_color(level, raw)
        local s = tostring(raw or '')
        local color = C.log_msg
        if level == 'warn' then color = C.log_warn
        elseif level == 'err' then color = C.log_err end

        if s:find('EVICT', 1, true) then
            color = C.log_evict
        elseif s:find('IMPORT', 1, true) then
            color = C.log_import
        elseif s:find('Missing items', 1, true)
            or s:match('^%s*%*%s*Missing')
            or s:find('This plan contains missing items', 1, true)
            or s:match('^%s*%-')
            or s:match('^%s*%-%s*%[') then
            color = C.log_missing
        elseif s:find('Notes:', 1, true) or s:match('^%s*%*') then
            color = C.log_note
        end
        return color
    end

    local function clear_log()
        state.log_lines = {}
        state.log_scroll = 0
        ensure_log_scroll_valid()
        if UI.visible then layout() end
    end

    ui.clear_log = clear_log

    local function push_log(level, s)
        s = tostring(s or '')
        if s == '' then return end

        local color      = pick_log_color(level, s)
        local wrap_width = chars_in(content_w()) - 1
        local prefix     = '[W9] '
        local wrapped    = wrap_text(prefix .. s, wrap_width, string.rep(' ', #prefix))

        for _, line in ipairs(wrapped) do
            state.log_lines[#state.log_lines + 1] = { text = line, color = color }
        end
        while #state.log_lines > state.log_max_lines do
            table.remove(state.log_lines, 1)
        end

        state.log_scroll = max_log_scroll()
        ensure_log_scroll_valid()
        if UI.visible then layout() end
    end

    ui.push_log = push_log

    -- ==========================================================================
    -- Actions
    -- ==========================================================================

    local function do_scan()
        local ok, e = scanmod.scan_all_bags_to_cache()
        if not ok then
            state.status = tostring(e)
            util.err(tostring(e))
            layout()
            return
        end
        clear_log()
        util.msg('Scan complete. Please select a lua and press PLAN.')
        state.status = 'Scan complete. Select a lua and press PLAN.'
        refresh_file_list()
        layout()
    end

    local function do_plan()
        local rel = selected_file_rel()
        if not rel then
            state.status = 'Select a lua file first.'
            layout()
            return
        end
        clear_log()

        local plan, e = planner.plan_for_file(rel)
        if not plan then
            state.status = tostring(e)
            util.err(tostring(e))
            layout()
            return
        end

        state.last_plan = plan
        state.status = ('Planned %d moves for %s.'):format(plan.moves and #plan.moves or 0, rel)
        planner.print_plan(plan)
        util.msg('Please press EXEC to execute the plan.')
        layout()
    end

    local function do_exec()
        if not state.last_plan then
            state.status = 'No stored plan. Press PLAN first.'
            layout()
            return
        end
        state.status = 'Executing...'
        layout()
        execmod.exec_plan(state.last_plan)
    end

    -- ==========================================================================
    -- Mouse handler (w9_mouse.lua)
    -- ==========================================================================

    local mouse = mousemod({
        state   = state,
        UI      = UI,
        PX      = PX,
        Rect    = Rect,
        util    = util,
        layout  = function() layout() end,
        row_h   = row_h,
        max_file_scroll          = max_file_scroll,
        max_log_scroll           = max_log_scroll,
        ensure_file_scroll_valid = ensure_file_scroll_valid,
        ensure_log_scroll_valid  = ensure_log_scroll_valid,
        ensure_selection_visible = ensure_selection_visible,
        do_scan  = do_scan,
        do_plan  = do_plan,
        do_exec  = do_exec,
        SB_HIT_PAD_X = SB_HIT_PAD_X,
        SB_HIT_PAD_Y = SB_HIT_PAD_Y,
    })

    -- ==========================================================================
    -- Show / hide
    -- ==========================================================================

    function ui.show()
        UI.visible = true
        state.dragging         = false
        state.file_sb_dragging = false
        state.log_sb_dragging  = false
        state.hover            = nil
        clear_log()
        refresh_file_list()
        layout()
    end

    function ui.hide()
        UI.visible = false
        state.dragging         = false
        state.file_sb_dragging = false
        state.log_sb_dragging  = false
        state.hover            = nil
        clear_log()
        refresh_file_list()
        layout()
    end

    function ui.on_zone_or_login_refresh()
        local mh = is_mog_house()
        if mh and not UI.visible then
            ui.show()
        elseif (not mh) and UI.visible then
            ui.hide()
        end
    end

    -- ==========================================================================
    -- Events
    -- ==========================================================================

    windower.register_event('zone change', function()
        coroutine.schedule(function() ui.on_zone_or_login_refresh() end, 1.0)
    end)

    windower.register_event('login', function()
        coroutine.schedule(function() ui.on_zone_or_login_refresh() end, 2.0)
    end)

    windower.register_event('logout', function()
        ui.hide()
    end)

    windower.register_event('mouse', function(type, x, y, delta, blocked)
        return mouse.on_mouse(type, x, y, delta, blocked)
    end)

    -- ==========================================================================
    -- Init
    -- ==========================================================================

    function ui.init()
        util.set_ui_logger(function(level, s) push_log(level, s) end)

        -- Measure font metrics so text content fits pixel regions correctly.
        do
            local sample = string.rep('M', 20)
            local t = texts.new(sample)
            apply_text_defaults(t)
            t:bg_alpha(0)
            t:alpha(0)
            t:pos(0, 0)
            t:show()

            local ok, w, h = pcall(function()
                local ew, eh = t:extents()
                return ew, eh
            end)

            if ok and type(w) == 'number' and w > 0 then
                _measured_char_w = w / #sample
            end
            if ok and type(h) == 'number' and h > 0 then
                _measured_row_h = math.max(PX.ROW_H, math.floor(h + 6))
            end

            t:hide()
        end

        ui.on_zone_or_login_refresh()
        layout()
    end

    ui.init()

    return ui
end
