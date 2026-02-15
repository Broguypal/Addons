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

return function(res, util, scanmod, planner, execmod)
    local ui = {}

    local texts = require('texts')

    -- ======================================================
    -- Layout
    -- ======================================================

    local UI = {
        x = 420,
        y = 220,

        w_chars = 62,

        max_rows = 22,

        file_rows = 11,
        log_rows  = 11,

        row_h_px = 16,
        font = 'Consolas',
        size = 10,

        visible = false,
    }

    local C = {
        text   = {255, 235, 235, 235},
        subtle = {255, 190, 190, 190},

        panel_bg = {220, 20, 20, 20},
        btn_bg   = {255, 45, 45, 45},
        btn_hov  = {255, 70, 70, 70},
        btn_txt  = {255, 245, 245, 245},

        sel_bg   = {255, 60, 60, 90},

        sb_track = {120, 60, 60, 60},
        sb_thumb = {255, 160, 160, 220},

        log_bg   = {220, 20, 20, 20},
        log_msg  = {255, 200, 220, 255},
        log_warn = {255, 255, 220, 140},
        log_err  = {255, 255, 160, 160},

        log_missing = {255, 255,  80,  80},
        log_note    = {255, 255,  80,  80},
        log_evict   = {255, 255, 190, 120},
        log_import  = {255, 160, 220, 255},
    }

    local CHAR_W = 7.47

    local function panel_total_lines()
        return 2 + 2 + UI.max_rows + 2
    end

    local function panel_width_px()
        return UI.w_chars * CHAR_W
    end

    -- ======================================================
    -- State
    -- ======================================================

    local state = {
        files = {},
        selected_index = nil,
        last_plan = nil,
        status = 'Ready.',
        hover = nil,

        file_scroll = 0,

        log_lines = {},
        log_scroll = 0,
        log_max_lines = 300,

        dragging = false,
        drag_dx = 0,
        drag_dy = 0,

        file_sb_dragging = false,
        file_sb_drag_offset = 0,

        log_sb_dragging = false,
        log_sb_drag_offset = 0,
    }

    -- ======================================================
    -- Text objects
    -- ======================================================

    local t_panel  = texts.new('')
    local t_title  = texts.new('')
    local t_status = texts.new('')

    local t_btn_scan = texts.new('')
    local t_btn_plan = texts.new('')
    local t_btn_exec = texts.new('')

    local t_file_rows = {}
    local t_file_sb_track = texts.new('')
    local t_file_sb_thumb = texts.new('')

    local t_log_title = texts.new('')
    local t_log_panel = texts.new('')
    local t_log_rows = {}
    local t_log_sb_track = texts.new('')
    local t_log_sb_thumb = texts.new('')

    local function apply_text_defaults(t)
        t:font(UI.font)
        t:size(UI.size)
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
        if #s >= w then return s end
        return s .. string.rep(' ', w - #s)
    end

    -- ======================================================
    -- File list scrolling
    -- ======================================================

    local function max_file_scroll()
        local n = #state.files
        if n <= UI.file_rows then return 0 end
        return n - UI.file_rows
    end

    local function ensure_file_scroll_valid()
        state.file_scroll = util.clamp(state.file_scroll or 0, 0, max_file_scroll())
    end

    local function ensure_selection_visible()
        if not state.selected_index then return end
        local idx = state.selected_index
        local top = state.file_scroll + 1
        local bot = state.file_scroll + UI.file_rows

        if idx < top then
            state.file_scroll = idx - 1
        elseif idx > bot then
            state.file_scroll = idx - UI.file_rows
        end
        ensure_file_scroll_valid()
    end

    -- ======================================================
    -- Log scrolling
    -- ======================================================

    local function max_log_scroll()
        local n = #state.log_lines
        if n <= UI.log_rows then return 0 end
        return n - UI.log_rows
    end

    local function ensure_log_scroll_valid()
        state.log_scroll = util.clamp(state.log_scroll or 0, 0, max_log_scroll())
    end

    -- ======================================================
    -- Mog house detection
    -- ======================================================

    local function is_mog_house()
        local info = windower.ffxi.get_info()
        if info and info.mog_house ~= nil then
            return info.mog_house == true
        end
        if info and info.zone and res and res.zones and res.zones[info.zone] and res.zones[info.zone].en then
            local zn = (res.zones[info.zone].en or ''):lower()
            if zn:find('mog') then return true end
        end
        return false
    end

    -- ======================================================
    -- File listing
    -- ======================================================

    local function list_lua_files_in_dir(dirpath)
        local out = {}
        if not dirpath or dirpath == '' then return out end

        if windower.get_dir then
            local ok, files = pcall(windower.get_dir, dirpath)
            if ok and type(files) == 'table' then
                for _,fn in ipairs(files) do
                    if type(fn) == 'string' and fn:lower():match('%.lua$') then
                        out[#out+1] = fn
                    end
                end
            end
        end

        table.sort(out, function(a,b) return a:lower() < b:lower() end)
        return out
    end

    local function refresh_file_list()
        state.files = {}
        state.selected_index = nil
        state.file_scroll = 0

        local root, char, pname = util.get_gearswap_data_paths()

        local root_files = list_lua_files_in_dir(root)
        for _,fn in ipairs(root_files) do
            state.files[#state.files+1] = {
                label = fn,
                rel = fn,
                scope = 'root',
                fullpath = util.safe_join(root, fn),
            }
        end

        local char_files = list_lua_files_in_dir(char)
        for _,fn in ipairs(char_files) do
            state.files[#state.files+1] = {
                label = (pname and (pname .. '/' .. fn)) or ('CHAR/'..fn),
                rel = fn,
                scope = 'char',
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

    -- ======================================================
    -- Hitboxes
    -- ======================================================


    local Rect = {}

    function Rect.btn(which)
        local bx = UI.x + 12
        local by = UI.y + 36

        local spacing = 14
        local bw_chars = 10
        local bw = bw_chars * CHAR_W
        local bh = UI.row_h_px

        if which == 'scan' then
            return bx, by, bw, bh
        elseif which == 'plan' then
            return bx + bw + spacing, by, bw, bh
        else
            return bx + (bw + spacing)*2, by, bw, bh
        end
    end

    function Rect.file_list()
        local lx = UI.x + 12
        local ly = UI.y + 80
        local lw = panel_width_px() - 24 - CHAR_W
        local lh = UI.file_rows * UI.row_h_px
        return lx, ly, lw, lh
    end

    function Rect.log()
        local lx, ly, lw, lh = Rect.file_list()
        local gap = 16
        local log_y = ly + lh + gap
        local log_h = UI.log_rows * UI.row_h_px
        return lx, log_y, lw, log_h
    end

    function Rect.header()
        local hx = UI.x
        local hy = UI.y
        local hw = panel_width_px()
        local hh = 30
        return hx, hy, hw, hh
    end

    function Rect.file_scrollbar()
        local _, ly, _, lh = Rect.file_list()
        local px = UI.x
        local pw = panel_width_px()
        local sx = px + pw + 6
        return sx, ly, CHAR_W, lh
    end

    function Rect.log_scrollbar()
        local _, ly, _, lh = Rect.log()
        local px = UI.x
        local pw = panel_width_px()
        local sx = px + pw + 6
        return sx, ly, CHAR_W, lh
    end

    function Rect.file_thumb()
        local tx, ty, tw, th = Rect.file_scrollbar()

        local total = #state.files
        local visible = UI.file_rows

        if total <= visible then
            return tx, ty, tw, th
        end

        local ratio = visible / total
        local thumb_h = math.max(UI.row_h_px, math.floor(th * ratio))

        local ms = max_file_scroll()
        local yoff = 0
        if ms > 0 then
            yoff = math.floor((state.file_scroll / ms) * (th - thumb_h))
        end

        return tx, ty + yoff, tw, thumb_h
    end

    function Rect.log_thumb()
        local tx, ty, tw, th = Rect.log_scrollbar()

        local total = #state.log_lines
        local visible = UI.log_rows

        if total <= visible then
            return tx, ty, tw, th
        end

        local ratio = visible / total
        local thumb_h = math.max(UI.row_h_px, math.floor(th * ratio))

        local ms = max_log_scroll()
        local yoff = 0
        if ms > 0 then
            yoff = math.floor((state.log_scroll / ms) * (th - thumb_h))
        end

        return tx, ty + yoff, tw, thumb_h
    end

    function Rect.point_in(mx, my, x, y, w, h)
        return mx >= x and mx <= (x + w) and my >= y and my <= (y + h)
    end

    local SB_HIT_PAD_X = 18  -- vertical forgiveness for grabbing the scrollbar/thumb
    local SB_HIT_PAD_Y = 18  -- vertical forgiveness for grabbing the scrollbar/thumb

    function Rect.point_in_xpad(mx, my, x, y, w, h, pad_x)
        pad_x = pad_x or 0
        return Rect.point_in(mx, my, x - pad_x, y, w + pad_x*2, h)
    end

    function Rect.point_in_pad(mx, my, x, y, w, h, pad_x, pad_y)
        pad_x = pad_x or 0
        pad_y = pad_y or 0
        return Rect.point_in(mx, my, x - pad_x, y - pad_y, w + pad_x*2, h + pad_y*2)
    end


    -- ======================================================
    -- Render helpers
    -- ======================================================

    local Render = {}

    function Render.ensure_rows(tbl, n)
        for i=1,n do
            if not tbl[i] then
                tbl[i] = texts.new('')
                apply_text_defaults(tbl[i])
            end
        end
    end

    function Render.make_block_lines(rows, cols_chars)
        local lines = {}
        local line = pad_right('', cols_chars)
        for _=1,rows do
            lines[#lines+1] = line
        end
        return table.concat(lines, "\n")
    end

    function Render.set_block(t, x, y, rows, cols_chars, bg)
        if x and y then t:pos(x, y) end
        t:text(Render.make_block_lines(rows, cols_chars))
        set_bg(t, bg)
        t:visible(true)
    end

    function Render.scrollbar(track_obj, thumb_obj, track_rect_fn, thumb_rect_fn, visible_rows)
        local sx, sy = track_rect_fn()
        track_obj:pos(sx, sy)
        track_obj:text(Render.make_block_lines(visible_rows, 1))
        set_bg(track_obj, C.sb_track)
        track_obj:visible(true)

        local tx, ty, tw, th = thumb_rect_fn()
        local rows = math.max(1, math.floor(th / UI.row_h_px))
        thumb_obj:pos(tx, ty)
        thumb_obj:text(Render.make_block_lines(rows, 1))
        set_bg(thumb_obj, C.sb_thumb)
        thumb_obj:visible(true)
    end


    local function set_all_visible(v)
        local objs = {
            t_panel, t_title, t_status,
            t_btn_scan, t_btn_plan, t_btn_exec,
            t_file_sb_track, t_file_sb_thumb,
            t_log_title, t_log_panel,
            t_log_sb_track, t_log_sb_thumb,
        }
        for _,t in ipairs(objs) do
            if t then t:visible(v) end
        end
        for _,t in pairs(t_file_rows) do if t then t:visible(v) end end
        for _,t in pairs(t_log_rows) do if t then t:visible(v) end end
    end


    local function reposition_all()
        t_panel:pos(UI.x, UI.y)
        t_title:pos(UI.x + 12, UI.y + 8)
        t_status:pos(UI.x + 12, UI.y + 58)

        local bx, by = Rect.btn('scan')
        t_btn_scan:pos(bx, by)
        bx, by = Rect.btn('plan')
        t_btn_plan:pos(bx, by)
        bx, by = Rect.btn('exec')
        t_btn_exec:pos(bx, by)

        -- File list rows
        do
            local lx, ly = UI.x + 12, UI.y + 80
            Render.ensure_rows(t_file_rows, UI.file_rows)
            for i=1,UI.file_rows do
                t_file_rows[i]:pos(lx, ly + (i-1)*UI.row_h_px)
            end

            local sx, sy = Rect.file_scrollbar()
            t_file_sb_track:pos(sx, sy)

            local tx, ty = Rect.file_thumb()
            t_file_sb_thumb:pos(tx, ty)
        end

        -- Log panel
        do
            local lx, ly, lw, lh = Rect.log()
            t_log_panel:pos(lx, ly)
            t_log_title:pos(lx, ly - 16)

            Render.ensure_rows(t_log_rows, UI.log_rows)
            for i=1,UI.log_rows do
                t_log_rows[i]:pos(lx + 4, ly + (i-1)*UI.row_h_px)
            end

            local sx, sy = Rect.log_scrollbar()
            t_log_sb_track:pos(sx, sy)

            local tx, ty = Rect.log_thumb()
            t_log_sb_thumb:pos(tx, ty)
        end
    end

    local function layout()
        apply_text_defaults(t_panel)
        apply_text_defaults(t_title)
        apply_text_defaults(t_status)
        apply_text_defaults(t_btn_scan)
        apply_text_defaults(t_btn_plan)
        apply_text_defaults(t_btn_exec)
        apply_text_defaults(t_file_sb_track)
        apply_text_defaults(t_file_sb_thumb)
        apply_text_defaults(t_log_title)
        apply_text_defaults(t_log_panel)
        apply_text_defaults(t_log_sb_track)
        apply_text_defaults(t_log_sb_thumb)
        if not UI.visible then
            Render.ensure_rows(t_file_rows, UI.file_rows)
            Render.ensure_rows(t_log_rows, UI.log_rows)
            set_all_visible(false)
            return
        end

        -- Background block
        do
            local total_lines = panel_total_lines()
            Render.set_block(t_panel, UI.x, UI.y, total_lines, UI.w_chars, C.panel_bg)
        end

        -- Title
        t_title:text('Wardrobe9 — Mog House Panel (drag header)')
        set_color(t_title, C.text)
        t_title:visible(true)

        -- Status
        t_status:text(state.status or '')
        set_color(t_status, C.subtle)
        t_status:visible(true)

        -- Buttons
        do
            local function render_btn(t, label, which)
                t:text(label)
                set_color(t, C.btn_txt)
                if state.hover == which then set_bg(t, C.btn_hov) else set_bg(t, C.btn_bg) end
                t:visible(true)
            end
            render_btn(t_btn_scan, '[ SCAN ]', 'scan')
            render_btn(t_btn_plan, '[ PLAN ]', 'plan')
            render_btn(t_btn_exec, '[ EXEC ]', 'exec')
        end

        -- File rows
        Render.ensure_rows(t_file_rows, UI.file_rows)
        ensure_file_scroll_valid()
        for vis=1,UI.file_rows do
            local abs = state.file_scroll + vis
            local t = t_file_rows[vis]
            local rec = state.files[abs]

            if rec then
                local selected = (state.selected_index == abs)
                local prefix = selected and '> ' or '  '
                t:text(prefix .. rec.label)
                if selected then set_bg(t, C.sel_bg) else t:bg_alpha(0) end
                set_color(t, C.text)
                t:visible(true)
            else
                t:text('')
                t:bg_alpha(0)
                t:visible(true)
            end
        end

        -- File scrollbar
        Render.scrollbar(t_file_sb_track, t_file_sb_thumb, Rect.file_scrollbar, Rect.file_thumb, UI.file_rows)

        -- Log title + panel background
        do
            local lx, ly, lw, lh = Rect.log()
            t_log_title:text('Notifications')
            set_color(t_log_title, C.subtle)
            t_log_title:visible(true)

			-- Keep the log panel object, but make it fully transparent so it doesn't darken.
			t_log_panel:pos(lx, ly)
			t_log_panel:text('')      -- no block text
			t_log_panel:bg_alpha(0)   -- fully transparent background
			t_log_panel:visible(true)
        end

        -- Log rows
        Render.ensure_rows(t_log_rows, UI.log_rows)
        ensure_log_scroll_valid()
        for vis=1,UI.log_rows do
            local abs = state.log_scroll + vis
            local t = t_log_rows[vis]
            local rec = state.log_lines[abs]
            if rec then
                t:text(rec.text)
                set_color(t, rec.color or C.text)
                t:bg_alpha(0)
                t:visible(true)
            else
                t:text('')
                t:bg_alpha(0)
                t:visible(true)
            end
        end

        -- Log scrollbar
        Render.scrollbar(t_log_sb_track, t_log_sb_thumb, Rect.log_scrollbar, Rect.log_thumb, UI.log_rows)

        reposition_all()
    end

    -- ======================================================
    -- Notifications API (called by util via set_ui_logger)
    -- ======================================================

    local function wrap_text(s, width, cont_indent)
        s = tostring(s or '')
        width = math.max(8, tonumber(width) or 60)
        cont_indent = cont_indent or ''
        local out = {}

        local function rtrim(x)
            return (x:gsub('%s+$',''))
        end

        local first = true
        while #s > 0 do
            local w = width
            if not first then
                w = math.max(8, width - #cont_indent)
            end

            if #s <= w then
                local line = rtrim(s)
                if not first and cont_indent ~= '' then line = cont_indent .. line end
                out[#out+1] = line
                break
            end

            local cut = w
            local sub = s:sub(1, w)
            local sp = sub:match('^.*()%s')
            if sp and sp > 8 then
                cut = sp
            end

            local chunk = rtrim(s:sub(1, cut))
            s = s:sub(cut + 1):gsub('^%s+','')
            if not first and cont_indent ~= '' then chunk = cont_indent .. chunk end
            out[#out+1] = chunk
            first = false
        end
        return out
    end

    local function pick_log_color(level, raw)
        local s = tostring(raw or '')

        -- Base by level
        local color = C.log_msg
        if level == 'warn' then color = C.log_warn
        elseif level == 'err' then color = C.log_err
        end

        -- Overrides for specific content
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

        local color = pick_log_color(level, s)

        local prefix = '[W9] '
        local wrapped = wrap_text(prefix .. s, UI.w_chars - 1, string.rep(' ', #prefix))
        for _,line in ipairs(wrapped) do
            state.log_lines[#state.log_lines+1] = { text = line, color = color }
        end
        while #state.log_lines > state.log_max_lines do
            table.remove(state.log_lines, 1)
        end

        state.log_scroll = max_log_scroll()
        ensure_log_scroll_valid()

        if UI.visible then
            layout()
        end
    end

    ui.push_log = push_log

    -- ======================================================
    -- Actions
    -- ======================================================

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
        util.msg("Please press EXEC to execute the plan.")
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

    -- ======================================================
    -- Mouse handling
    -- ======================================================

    local function update_hover(mx, my)
        state.hover = nil
        do
            local x,y,w,h = Rect.btn('scan')
            if Rect.point_in(mx,my,x,y,w,h) then state.hover = 'scan' end
        end
        do
            local x,y,w,h = Rect.btn('plan')
            if Rect.point_in(mx,my,x,y,w,h) then state.hover = 'plan' end
        end
        do
            local x,y,w,h = Rect.btn('exec')
            if Rect.point_in(mx,my,x,y,w,h) then state.hover = 'exec' end
        end
    end

    local function click_buttons(mx, my)
        local x,y,w,h = Rect.btn('scan')
        if Rect.point_in(mx,my,x,y,w,h) then do_scan(); return true end

        x,y,w,h = Rect.btn('plan')
        if Rect.point_in(mx,my,x,y,w,h) then do_plan(); return true end

        x,y,w,h = Rect.btn('exec')
        if Rect.point_in(mx,my,x,y,w,h) then do_exec(); return true end

        return false
    end

    local function click_file_list(mx, my)
        local lx, ly, lw, lh = Rect.file_list()
        if not Rect.point_in(mx,my,lx,ly,lw,lh) then return false end

        local vis = math.floor((my - ly) / UI.row_h_px) + 1
        if vis < 1 or vis > UI.file_rows then return false end

        local abs = state.file_scroll + vis
        if abs >= 1 and abs <= #state.files then
            state.selected_index = abs
            ensure_selection_visible()
            state.status = ('Selected: %s'):format(state.files[abs].label)
            layout()
            return true
        end
        return false
    end

    local function scroll_file_list(delta)
        if delta == 0 then return false end
        local step = (delta > 0) and -3 or 3
        state.file_scroll = (state.file_scroll or 0) + step
        ensure_file_scroll_valid()
        layout()
        return true
    end

    local function scroll_log(delta)
        if delta == 0 then return false end
        local step = (delta > 0) and -3 or 3
        state.log_scroll = (state.log_scroll or 0) + step
        ensure_log_scroll_valid()
        layout()
        return true
    end

    local function begin_drag(mx, my)
        local hx, hy, hw, hh = Rect.header()
        if Rect.point_in(mx,my,hx,hy,hw,hh) then
            state.dragging = true
            state.drag_dx = mx - UI.x
            state.drag_dy = my - UI.y
            return true
        end
        return false
    end

    local function drag_move(mx, my)
        if not state.dragging then return false end
        UI.x = mx - state.drag_dx
        UI.y = my - state.drag_dy
        UI.x = util.clamp(UI.x, 0, 2000)
        UI.y = util.clamp(UI.y, 0, 2000)
        layout()
        return true
    end

    local function end_drag()
        if state.dragging then
            state.dragging = false
            return true
        end
        return false
    end

    local function begin_file_sb_drag(mx, my)
        local sx, sy, sw, sh = Rect.file_thumb()
        if Rect.point_in_pad(mx, my, sx, sy, sw, sh, SB_HIT_PAD_X, SB_HIT_PAD_Y) then
            state.file_sb_dragging = true
            state.file_sb_drag_offset = my - sy
            return true
        end

        local tx, ty, tw, th = Rect.file_scrollbar()
        if Rect.point_in_pad(mx, my, tx, ty, tw, th, SB_HIT_PAD_X, SB_HIT_PAD_Y) then
            local _, _, _, thumb_h = Rect.file_thumb()
            local maxy = th - thumb_h
            if maxy > 0 then

                local rel = util.clamp((my - ty) - (thumb_h / 2), 0, maxy)
                local ms = max_file_scroll()
                if ms > 0 then
                    state.file_scroll = math.floor((rel / maxy) * ms + 0.5)
                    ensure_file_scroll_valid()
                end
				
                state.file_sb_dragging = true
                state.file_sb_drag_offset = thumb_h / 2
                layout()
                return true
            end
        end

        return false
    end

    local function file_sb_drag_move(mx, my)
        if not state.file_sb_dragging then return false end

        local tx, ty, tw, th = Rect.file_scrollbar()
        local _, _, _, thumb_h = Rect.file_thumb()

        local rel = my - ty - state.file_sb_drag_offset
        local maxy = th - thumb_h
        if maxy <= 0 then return true end

        rel = util.clamp(rel, 0, maxy)

        local ms = max_file_scroll()
        if ms > 0 then
            state.file_scroll = math.floor((rel / maxy) * ms + 0.5)
            ensure_file_scroll_valid()
            layout()
        end
        return true
    end

    local function end_file_sb_drag()
        state.file_sb_dragging = false
    end

    local function begin_log_sb_drag(mx, my)
        local sx, sy, sw, sh = Rect.log_thumb()
        if Rect.point_in_pad(mx, my, sx, sy, sw, sh, SB_HIT_PAD_X, SB_HIT_PAD_Y) then
            state.log_sb_dragging = true
            state.log_sb_drag_offset = my - sy
            return true
        end

        local tx, ty, tw, th = Rect.log_scrollbar()
        if Rect.point_in_pad(mx, my, tx, ty, tw, th, SB_HIT_PAD_X, SB_HIT_PAD_Y) then
            local _, _, _, thumb_h = Rect.log_thumb()
            local maxy = th - thumb_h
            if maxy > 0 then
                local rel = util.clamp((my - ty) - (thumb_h / 2), 0, maxy)
                local ms = max_log_scroll()
                if ms > 0 then
                    state.log_scroll = math.floor((rel / maxy) * ms + 0.5)
                    ensure_log_scroll_valid()
                end
                state.log_sb_dragging = true
                state.log_sb_drag_offset = thumb_h / 2
                layout()
                return true
            end
        end

        return false
    end

    local function log_sb_drag_move(mx, my)
        if not state.log_sb_dragging then return false end

        local tx, ty, tw, th = Rect.log_scrollbar()
        local _, _, _, thumb_h = Rect.log_thumb()

        local rel = my - ty - state.log_sb_drag_offset
        local maxy = th - thumb_h
        if maxy <= 0 then return true end

        rel = util.clamp(rel, 0, maxy)

        local ms = max_log_scroll()
        if ms > 0 then
            state.log_scroll = math.floor((rel / maxy) * ms + 0.5)
            ensure_log_scroll_valid()
            layout()
        end
        return true
    end

    local function end_log_sb_drag()
        state.log_sb_dragging = false
    end

    -- ======================================================
    -- Show / hide based on mog house
    -- ======================================================

	function ui.show()
		UI.visible = true

		state.dragging = false
		state.file_sb_dragging = false
		state.log_sb_dragging = false
		state.hover = nil

		clear_log()

		refresh_file_list()
		layout()
	end

    function ui.hide()
        UI.visible = false
        state.dragging = false
        state.file_sb_dragging = false
        state.log_sb_dragging = false
		state.hover = nil
		
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

    -- ======================================================
    -- Events
    -- ======================================================

    windower.register_event('zone change', function()
        coroutine.schedule(function()
            ui.on_zone_or_login_refresh()
        end, 1.0)
    end)

    windower.register_event('login', function()
        coroutine.schedule(function()
            ui.on_zone_or_login_refresh()
        end, 2.0)
    end)

    windower.register_event('logout', function()
        ui.hide()
    end)

    windower.register_event('mouse', function(type, x, y, delta, blocked)
        if not UI.visible then return end

        update_hover(x, y)

        if type == 0 then
            if state.dragging then
                drag_move(x, y)
                return true
            end
            if state.file_sb_dragging then
                file_sb_drag_move(x, y)
                return true
            end
            if state.log_sb_dragging then
                log_sb_drag_move(x, y)
                return true
            end

            layout()
            return
        end

        if type == 1 then
            if click_buttons(x, y) then return true end
            if click_file_list(x, y) then return true end
            if begin_drag(x, y) then return true end
            if begin_file_sb_drag(x, y) then return true end
            if begin_log_sb_drag(x, y) then return true end
        end

        if type == 2 then
            if end_drag() then return true end
            end_file_sb_drag()
            end_log_sb_drag()
            layout()
            return
        end

        if type == 3 then
            if delta and delta ~= 0 then
                local flx, fly, flw, flh = Rect.file_list()
                local lgx, lgy, lgw, lgh = Rect.log()

                if Rect.point_in(x, y, flx, fly, flw, flh) then
                    return scroll_file_list(delta)
                elseif Rect.point_in(x, y, lgx, lgy, lgw, lgh) then
                    return scroll_log(delta)
                else
                    -- Default to file list scroll
                    return scroll_file_list(delta)
                end
            end
        end
    end)

    -- ======================================================
    -- Public init
    -- ======================================================

    function ui.init()
        -- Route util.msg/warn/err into the notification panel.
        util.set_ui_logger(function(level, s)
            push_log(level, s)
        end)

        ui.on_zone_or_login_refresh()
        layout()
    end

    ui.init()

    return ui
end
