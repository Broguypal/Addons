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

return function(res, util, config, scanmod, planner, execmod, mousemod, validate)
    local ui = {}

    local texts  = require('texts')
    local images = require('images')

    -- ==========================================================================
    -- Asset paths
    -- ==========================================================================

    local ADDON_PATH = windower.addon_path or (_addon and _addon.path) or 'addons/wardrobe9/'
    local ASSETS_DIR = ADDON_PATH .. 'assets/'

    local ASSET = {
        panel_bg       = ASSETS_DIR .. 'panel_bg.png',
        header_bg      = ASSETS_DIR .. 'header_bg.png',
        btn            = ASSETS_DIR .. 'btn.png',
        btn_hover      = ASSETS_DIR .. 'btn_hover.png',
        btn_wide       = ASSETS_DIR .. 'btn_wide.png',
        btn_wide_hover = ASSETS_DIR .. 'btn_wide_hover.png',
        row_selected   = ASSETS_DIR .. 'row_selected.png',
        sb_track       = ASSETS_DIR .. 'sb_track.png',
        sb_thumb       = ASSETS_DIR .. 'sb_thumb.png',
        sb_arrow_up    = ASSETS_DIR .. 'sb_arrow_up.png',
        sb_arrow_down  = ASSETS_DIR .. 'sb_arrow_down.png',
        chk_on         = ASSETS_DIR .. 'chk_on.png',
        chk_off        = ASSETS_DIR .. 'chk_off.png',
    }

    -- ==========================================================================
    -- Pixel constants
    -- ==========================================================================

    local PX = {
        PANEL_W     = 480,
        PAD         = 8,
        HEADER_H    = 24,

        BTN_W       = 72,
        BTN_H       = 18,
        BTN_GAP     = 8,
        BTN_Y       = 30,

        VAL_BTN_W   = 108,
        VAL_BTN_H   = 18,
        VAL_BTN_Y   = 56,

        STATUS_Y    = 82,

        FILE_Y      = 100,
        FILE_ROWS   = 5,

        SECTION_GAP = 20,

        LOG_ROWS    = 17,
        LOG_LABEL_H = 16,

        SB_W        = 12,
        SB_BTN_H    = 16,

        CHK_SIZE    = 14,
        CHK_GAP     = 4,

        ROW_H       = 16,

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
        x = (config and config.UI_START_X) or 420,
        y = (config and config.UI_START_Y) or 220,
        visible = false,
    }

    -- ==========================================================================
    -- Colors (text-only — visual chrome comes from images)
    -- ==========================================================================

    local C = {
        text    = {255, 235, 235, 235},
        subtle  = {255, 190, 190, 190},

        btn_txt  = {255, 245, 245, 245},

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
        collapsed      = true,
        files          = {},
        selected_set   = {},
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
    -- Image helper
    -- ==========================================================================

    local function make_img(asset_path)
        local img = images.new()
        img:path(asset_path)
        img:hide()
        return img
    end

    -- ==========================================================================
    -- Image objects — visual chrome
    -- ==========================================================================

    local img_panel  = make_img(ASSET.panel_bg)
    local img_header = make_img(ASSET.header_bg)

    -- Row-selection highlight images (one per visible file row)
    local img_row_sel = {}
    for i = 1, PX.FILE_ROWS do
        img_row_sel[i] = make_img(ASSET.row_selected)
    end

    -- Checkbox images (one per visible file row)
    local img_chk = {}
    for i = 1, PX.FILE_ROWS do
        img_chk[i] = make_img(ASSET.chk_off)
    end

    -- Scrollbar images: file list
    local img_file_sb_track = make_img(ASSET.sb_track)
    local img_file_sb_thumb = make_img(ASSET.sb_thumb)
    local img_file_sb_up    = make_img(ASSET.sb_arrow_up)
    local img_file_sb_down  = make_img(ASSET.sb_arrow_down)

    -- Scrollbar images: log
    local img_log_sb_track = make_img(ASSET.sb_track)
    local img_log_sb_thumb = make_img(ASSET.sb_thumb)
    local img_log_sb_up    = make_img(ASSET.sb_arrow_up)
    local img_log_sb_down  = make_img(ASSET.sb_arrow_down)

    -- Collapse/expand toggle button (in header bar)
    local img_toggle = make_img(ASSET.chk_off)
    local t_toggle   = texts.new('')

    -- ==========================================================================
    -- Text objects (content only — transparent backgrounds)
    -- ==========================================================================

    local t_title  = texts.new('')
    local t_status = texts.new('')

    local t_file_rows = {}
    local t_log_title = texts.new('')
    local t_log_rows  = {}

    local function apply_text_defaults(t)
        t:font(FONT_NAME)
        t:size(FONT_SIZE)
        t:pad(0)
        t:bg_alpha(0)
        t:visible(UI.visible)
    end

    local function set_color(t, rgba)
        t:color(rgba[1], rgba[2], rgba[3], rgba[4])
    end

    local function pad_right(s, w)
        s = s or ''
        if #s >= w then return s:sub(1, w) end
        return s .. string.rep(' ', w - #s)
    end

    -- ==========================================================================
    -- Data-driven button table
    --
    -- Each entry owns one image and one text object.  Actions are attached
    -- later (after the action functions are defined) via attach_button_actions().
    -- ==========================================================================

    local BTN_DEFS = {
        { id='scan',       label='SCAN',       wide=false },
        { id='plan',       label='PLAN',       wide=false },
        { id='swap',       label='SWAP',       wide=false },
        { id='fill',       label='FILL',       wide=false },
        { id='val_miss',   label='VAL:MISS',   wide=true  },
        { id='val_unused', label='VAL:UNUSED', wide=true  },
        { id='toggle',     label='+',          toggle=true },
    }

    local BTN_BY_ID = {}

    for _, def in ipairs(BTN_DEFS) do
        if def.toggle then
            def.img  = img_toggle
            def.text = t_toggle
        else
            def.img  = make_img(def.wide and ASSET.btn_wide or ASSET.btn)
            def.text = texts.new('')
        end
        apply_text_defaults(def.text)
        BTN_BY_ID[def.id] = def
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
        state.files          = {}
        state.selected_set   = {}
        state.selected_index = nil
        state.file_scroll    = 0

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
        state.status = ('Found %d GearSwap lua(s). Click rows to check/uncheck.'):format(#state.files)
    end

    local function selected_files_list()
        local out = {}
        for abs, checked in pairs(state.selected_set) do
            if checked and state.files[abs] then
                out[#out+1] = state.files[abs]
            end
        end
        table.sort(out, function(a, b) return (a.label or '') < (b.label or '') end)
        return out
    end

    local function selected_count()
        local n = 0
        for _, v in pairs(state.selected_set) do
            if v then n = n + 1 end
        end
        return n
    end

    -- ==========================================================================
    -- Hit-test rectangles
    -- ==========================================================================

    local Rect = {}

    function Rect.header()
        return UI.x, UI.y, PX.PANEL_W, PX.HEADER_H
    end

    -- Generic button rect
    function Rect.btn(which)
        local bx = UI.x + PX.PAD
        local by = UI.y + PX.BTN_Y
        if which == 'scan' then
            return bx, by, PX.BTN_W, PX.BTN_H
        elseif which == 'plan' then
            return bx + PX.BTN_W + PX.BTN_GAP, by, PX.BTN_W, PX.BTN_H
        elseif which == 'swap' then
            return bx + (PX.BTN_W + PX.BTN_GAP) * 2, by, PX.BTN_W, PX.BTN_H
        else -- 'fill'
            return bx + (PX.BTN_W + PX.BTN_GAP) * 3, by, PX.BTN_W, PX.BTN_H
        end
    end

    function Rect.val_btn(which)
        local bx = UI.x + PX.PAD
        local by = UI.y + PX.VAL_BTN_Y
        if which == 'val_miss' then
            return bx, by, PX.VAL_BTN_W, PX.VAL_BTN_H
        else -- 'val_unused'
            return bx + PX.VAL_BTN_W + PX.BTN_GAP, by, PX.VAL_BTN_W, PX.VAL_BTN_H
        end
    end

    -- Toggle button (far right of header)
    function Rect.toggle_btn()
        local tx = UI.x + PX.PANEL_W - PX.PAD - PX.CHK_SIZE
        local ty = UI.y + math.floor((PX.HEADER_H - PX.CHK_SIZE) / 2)
        return tx, ty, PX.CHK_SIZE, PX.CHK_SIZE
    end

    -- Unified rect lookup used by the data-driven button table.
    function Rect.button(def)
        if def.toggle then return Rect.toggle_btn() end
        if def.wide then return Rect.val_btn(def.id)
        else             return Rect.btn(def.id) end
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

    -- ---- File scrollbar ----

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

    -- Position and stretch an image, then show it.
    function Render.place_img(img, x, y, w, h)
        img:pos(x, y)
        img:size(w, h)
        img:show()
    end

    -- Position a scrollbar image set (track, thumb, arrows).
    function Render.scrollbar_imgs(track_img, thumb_img, up_img, down_img,
                                   sb_upbtn_fn, sb_downbtn_fn, track_fn, thumb_fn)
        do -- up arrow
            local x, y, w, h = sb_upbtn_fn()
            Render.place_img(up_img, x, y, w, h)
        end
        do -- down arrow
            local x, y, w, h = sb_downbtn_fn()
            Render.place_img(down_img, x, y, w, h)
        end
        do -- track
            local x, y, w, h = track_fn()
            Render.place_img(track_img, x, y, w, h)
        end
        do -- thumb
            local x, y, w, h = thumb_fn()
            Render.place_img(thumb_img, x, y, w, h)
        end
    end

    -- ==========================================================================
    -- Visibility toggle
    -- ==========================================================================

    local function set_all_visible(v)
        -- Images
        local all_imgs = {
            img_panel, img_header, img_toggle,
            img_file_sb_track, img_file_sb_thumb, img_file_sb_up, img_file_sb_down,
            img_log_sb_track,  img_log_sb_thumb,  img_log_sb_up,  img_log_sb_down,
        }
        for _, img in ipairs(all_imgs) do
            if v then img:show() else img:hide() end
        end

        for i = 1, PX.FILE_ROWS do
            if v then img_row_sel[i]:show() else img_row_sel[i]:hide() end
            if v then img_chk[i]:show()     else img_chk[i]:hide()     end
        end

        -- Button images + text
        for _, def in ipairs(BTN_DEFS) do
            if not def.toggle then
                if v then def.img:show() else def.img:hide() end
                def.text:visible(v)
            end
        end

        -- Toggle (handled separately so collapsed mode can show it)
        if not v then
            img_toggle:hide()
            t_toggle:visible(false)
        end

        -- Text objects
        local txt_objs = { t_title, t_status, t_log_title }
        for _, t in ipairs(txt_objs) do if t then t:visible(v) end end
        for _, t in pairs(t_file_rows) do if t then t:visible(v) end end
        for _, t in pairs(t_log_rows)  do if t then t:visible(v) end end
    end

    -- ==========================================================================
    -- Main layout / render
    -- ==========================================================================

    local function layout()
        -- Ensure text defaults on fixed text objects.
        local fixed_txt = { t_title, t_status, t_log_title }
        for _, t in ipairs(fixed_txt) do apply_text_defaults(t) end
        for _, def in ipairs(BTN_DEFS) do apply_text_defaults(def.text) end

        if not UI.visible then
            Render.ensure_rows(t_file_rows, PX.FILE_ROWS)
            Render.ensure_rows(t_log_rows, PX.LOG_ROWS)
            set_all_visible(false)
            return
        end

        -- ---- Collapsed mode: header bar + toggle only ----
        if state.collapsed then
            Render.ensure_rows(t_file_rows, PX.FILE_ROWS)
            Render.ensure_rows(t_log_rows, PX.LOG_ROWS)
            set_all_visible(false)

            Render.place_img(img_header, UI.x, UI.y, PX.PANEL_W, PX.HEADER_H)

            t_title:pos(UI.x + PX.PAD, UI.y + 4)
            t_title:text('Wardrobe9 — Mog House')
            set_color(t_title, C.text)
            t_title:visible(true)

            local tx, ty, tw, th = Rect.toggle_btn()
            Render.place_img(img_toggle, tx, ty, tw, th)
            t_toggle:pos(tx + 3, ty - 1)
            t_toggle:text('+')
            set_color(t_toggle, C.btn_txt)
            t_toggle:bg_alpha(0)
            t_toggle:visible(true)
            return
        end

        -- ---- Panel background ----
        Render.place_img(img_panel, UI.x, UI.y, PX.PANEL_W, math.floor(panel_h()))

        -- ---- Header background ----
        Render.place_img(img_header, UI.x, UI.y, PX.PANEL_W, PX.HEADER_H)

        -- ---- Title text ----
        t_title:pos(UI.x + PX.PAD, UI.y + 4)
        t_title:text('Wardrobe9 — Mog House')
        set_color(t_title, C.text)
        t_title:visible(true)

        -- ---- Collapse/expand toggle ----
        do
            local tx, ty, tw, th = Rect.toggle_btn()
            Render.place_img(img_toggle, tx, ty, tw, th)
            t_toggle:pos(tx + 3, ty - 1)
            t_toggle:text('-')
            set_color(t_toggle, C.btn_txt)
            t_toggle:bg_alpha(0)
            t_toggle:visible(true)
        end

        -- ---- Status text (truncated to panel width) ----
        local status_max = chars_in(PX.PANEL_W - PX.PAD * 2)
        local status_str = (state.status or ''):sub(1, status_max)
        t_status:pos(UI.x + PX.PAD, UI.y + PX.STATUS_Y)
        t_status:text(status_str)
        set_color(t_status, C.subtle)
        t_status:visible(true)

        -- ---- Buttons (data-driven) ----
        for _, def in ipairs(BTN_DEFS) do
            if not def.toggle then
            local bx, by, bw, bh = Rect.button(def)
            local is_hover = (state.hover == def.id)

            -- Swap image path for hover state.
            if is_hover then
                def.img:path(def.wide and ASSET.btn_wide_hover or ASSET.btn_hover)
            else
                def.img:path(def.wide and ASSET.btn_wide or ASSET.btn)
            end
            Render.place_img(def.img, bx, by, bw, bh)

            -- Center label text on button.
            local label_px_w = #def.label * char_w()
            local tx = bx + math.floor((bw - label_px_w) / 2)
            local ty = by + 1
            def.text:pos(tx, ty)
            def.text:text(def.label)
            set_color(def.text, C.btn_txt)
            def.text:bg_alpha(0)
            def.text:visible(true)
            end -- if not def.toggle
        end

        -- ---- File rows ----
        local chk_total = PX.CHK_SIZE + PX.CHK_GAP
        local text_w    = content_w() - chk_total
        local rc = chars_in(text_w)
        Render.ensure_rows(t_file_rows, PX.FILE_ROWS)
        ensure_file_scroll_valid()

        local file_lx = UI.x + PX.PAD
        local file_ly = UI.y + PX.FILE_Y

        for vis = 1, PX.FILE_ROWS do
            local abs = state.file_scroll + vis
            local t   = t_file_rows[vis]
            local rec = state.files[abs]
            local ry  = file_ly + (vis - 1) * row_h()

            -- Checkbox image (vertically centered in row).
            local chk_y = ry + math.floor((row_h() - PX.CHK_SIZE) / 2)
            -- Text starts after checkbox + gap.
            local tx = file_lx + chk_total

            t:pos(tx, ry)

            if rec then
                local checked = state.selected_set[abs] == true

                -- Show correct checkbox image.
                img_chk[vis]:path(checked and ASSET.chk_on or ASSET.chk_off)
                Render.place_img(img_chk[vis], file_lx, chk_y, PX.CHK_SIZE, PX.CHK_SIZE)

                t:text(pad_right(rec.label, rc))
                set_color(t, C.text)

                -- Row selection highlight image.
                if checked then
                    Render.place_img(img_row_sel[vis], file_lx, ry, content_w(), row_h())
                else
                    img_row_sel[vis]:hide()
                end
            else
                t:text(pad_right('', rc))
                img_chk[vis]:hide()
                img_row_sel[vis]:hide()
            end

            t:bg_alpha(0)
            t:visible(true)
        end

        -- ---- File scrollbar ----
        Render.scrollbar_imgs(
            img_file_sb_track, img_file_sb_thumb, img_file_sb_up, img_file_sb_down,
            Rect.file_sb_upbtn, Rect.file_sb_downbtn, Rect.file_scrollbar, Rect.file_thumb)

        -- ---- Log label ----
        t_log_title:pos(UI.x + PX.PAD, UI.y + log_y_off() - PX.LOG_LABEL_H)
        t_log_title:text('Notifications')
        set_color(t_log_title, C.subtle)
        t_log_title:visible(true)

        -- ---- Log rows ----
        Render.ensure_rows(t_log_rows, PX.LOG_ROWS)
        ensure_log_scroll_valid()

        local log_lx = UI.x + PX.PAD
        local log_ly = UI.y + log_y_off()

        for vis = 1, PX.LOG_ROWS do
            local abs = state.log_scroll + vis
            local t   = t_log_rows[vis]
            local rec = state.log_lines[abs]

            t:pos(log_lx, log_ly + (vis - 1) * row_h())

            if rec then
                t:text(rec.text)
                set_color(t, rec.color or C.text)
            else
                t:text('')
            end
            t:bg_alpha(0)
            t:visible(true)
        end

        -- ---- Log scrollbar ----
        Render.scrollbar_imgs(
            img_log_sb_track, img_log_sb_thumb, img_log_sb_up, img_log_sb_down,
            Rect.log_sb_upbtn, Rect.log_sb_downbtn, Rect.log_scrollbar, Rect.log_thumb)
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
        util.msg('Scan complete. Check one or more luas, then:')
        util.msg('  PLAN → Preview wardrobe moves, then SWAP or FILL to execute.')
        util.msg('  VAL:MISS → List gear in your luas that is missing from wardrobes.')
        util.msg('  VAL:UNUSED → List wardrobe items not referenced by your luas.')
        state.status = 'Scan complete. Check lua(s) and press PLAN or VAL.'
        refresh_file_list()
        layout()
    end

    local function do_plan()
        local files = selected_files_list()
        local n = #files
        if n == 0 then
            state.status = 'Check at least one lua file first.'
            util.warn('Check at least one lua file in the list before pressing PLAN.')
            layout()
            return
        end
        clear_log()

        local label = (n == 1) and files[1].label or (('%d files'):format(n))

        local swap_plan, e1 = planner.plan_for_files(files, 'swap')
        if not swap_plan then
            state.status = tostring(e1)
            util.err(tostring(e1))
            layout()
            return
        end

        local fill_plan, e2 = planner.plan_for_files(files, 'fill')
        if not fill_plan then
            state.status = tostring(e2)
            util.err(tostring(e2))
            layout()
            return
        end

        state.last_plan = swap_plan
        state.status = ('Plans ready: SWAP=%d moves  FILL=%d moves  [%s]'):format(
            swap_plan.moves and #swap_plan.moves or 0,
            fill_plan.moves and #fill_plan.moves or 0,
            label)

        planner.print_plan_header(swap_plan)
        planner.print_plan_moves(swap_plan, 'SWAP')
        planner.print_plan_moves(fill_plan, 'FILL')
        util.msg('Press [ SWAP ] or [ FILL ] to execute:')
        util.msg('  SWAP → Evict unused same-type gear to make room, free slots as fallback.')
        util.msg('  FILL → Use free wardrobe slots first, evict only as last resort.')
        layout()
    end

    local function do_exec_with_mode(mode)
        if not state.last_plan then
            state.status = 'No plan. Press PLAN first, then SWAP or FILL.'
            util.warn('You must press PLAN before using SWAP or FILL.')
            layout()
            return
        end

        local files = selected_files_list()
        local n = #files
        if n == 0 then
            state.status = 'No lua files checked. Check file(s) first.'
            util.warn('Check at least one lua file before executing.')
            layout()
            return
        end
        clear_log()

        local plan, e = planner.plan_for_files(files, mode)
        if not plan then
            clear_log()
            state.status = tostring(e)
            util.err(tostring(e))
            layout()
            return
        end

        local label = (n == 1) and files[1].label or (('%d files'):format(n))
        state.last_plan = nil
        state.status = ('Executing %d moves [%s] [%s]...'):format(
            plan.moves and #plan.moves or 0, mode, label)
        planner.print_plan(plan)
        layout()
        execmod.exec_plan(plan)
    end

    local function do_exec_swap()
        do_exec_with_mode('swap')
    end

    local function do_exec_fill()
        do_exec_with_mode('fill')
    end

    -- ==========================================================================
    -- Validate actions
    -- ==========================================================================

    local function do_val_miss()
        local files = selected_files_list()
        if #files == 0 then
            state.status = 'Check at least one lua file first.'
            util.warn('Check at least one lua file before pressing VAL:MISS.')
            layout()
            return
        end
        clear_log()

        local result, err = validate.validate_missing(files)
        if not result then
            state.status = tostring(err)
            util.err(tostring(err))
            layout()
            return
        end

        state.status = ('VAL:MISS — %d required | %d in wardrobes | %d missing | %d in other bags | %d on slips  [%s]')
            :format(result.total, result.in_wardrobes,
                    #result.missing_entirely, #result.in_bags_not_wardrobes,
                    result.on_slips and #result.on_slips or 0,
                    result.label)

        util.msg(('Validate Missing — File(s): %s'):format(result.label))
        util.msg(('Required items: %d | In wardrobes: %d'):format(result.total, result.in_wardrobes))

        if #result.missing_entirely == 0 and #result.in_bags_not_wardrobes == 0
            and (not result.on_slips or #result.on_slips == 0) then
            util.msg('All referenced gear is present in your wardrobes.')
        end

        if #result.missing_entirely > 0 then
            util.warn(('--- Missing from ALL bags/wardrobes: %d ---'):format(#result.missing_entirely))
            for i, m in ipairs(result.missing_entirely) do
                if i > 80 then util.warn(('  ...and %d more'):format(#result.missing_entirely - 80)); break end
                local aug_suffix = (m.aug ~= '') and (' (Aug: %s)'):format(m.aug) or ''
                util.warn(('  [%s] %s%s'):format(m.group, m.name, aug_suffix))
            end
        end

        if result.on_slips and #result.on_slips > 0 then
            util.warn(('--- Stored on Porter Mog Slips: %d ---'):format(#result.on_slips))
            for i, s in ipairs(result.on_slips) do
                if i > 80 then util.warn(('  ...and %d more'):format(#result.on_slips - 80)); break end
                local aug_suffix = (s.aug ~= '') and (' (Aug: %s)'):format(s.aug) or ''
                util.warn(('  [%s] %s%s  —  %s'):format(s.group, s.name, aug_suffix, s.slip))
            end
        end

        if #result.in_bags_not_wardrobes > 0 then
            util.warn(('--- Missing from wardrobes but present in other bags: %d ---'):format(#result.in_bags_not_wardrobes))
            for i, m in ipairs(result.in_bags_not_wardrobes) do
                if i > 80 then util.warn(('  ...and %d more'):format(#result.in_bags_not_wardrobes - 80)); break end
                local aug_suffix = (m.aug ~= '') and (' (Aug: %s)'):format(m.aug) or ''
                util.warn(('  [%s] %s%s  —  Found in: %s'):format(m.group, m.name, aug_suffix, m.bags))
            end
        end

        layout()
    end

    local function do_val_unused()
        local files = selected_files_list()
        if #files == 0 then
            state.status = 'Check at least one lua file first.'
            util.warn('Check at least one lua file before pressing VAL:UNUSED.')
            layout()
            return
        end
        clear_log()

        local result, err = validate.validate_unused(files)
        if not result then
            state.status = tostring(err)
            util.err(tostring(err))
            layout()
            return
        end

        local n = #result.unused
        state.status = ('VAL:UNUSED — %d wardrobe item(s) not referenced by selected lua(s)  [%s]')
            :format(n, result.label)

        util.msg(('Validate Unused — File(s): %s'):format(result.label))

        if n == 0 then
            util.msg('Every item in your wardrobes is referenced by the selected lua(s).')
        else
            util.warn(('--- Unused wardrobe items: %d ---'):format(n))
            for i, u in ipairs(result.unused) do
                if i > 120 then util.warn(('  ...and %d more'):format(n - 120)); break end
                local aug_suffix = (u.aug ~= '') and (' (Aug: %s)'):format(u.aug) or ''
                util.warn(('  [%s] %s%s  —  %s'):format(u.group, u.name, aug_suffix, u.bag_name))
            end
        end

        util.warn('')
        if result.has_custom_vars then
            util.warn('Note: Items referenced via CUSTOM_GEAR_VARIABLES in w9_config.lua were included in matching.')
            util.warn('However, any custom gearswap variables NOT defined in the config may cause items to appear unused here.')
        else
            util.warn('Warning: No CUSTOM_GEAR_VARIABLES are defined in w9_config.lua.')
            util.warn('If your lua files use custom variable names for gear (e.g. WAR_HEAD = "Item Name"),')
            util.warn('those items will NOT be detected as "used" and may appear in this list incorrectly.')
            util.warn('Add them to CUSTOM_GEAR_VARIABLES in w9_config.lua to fix this.')
        end

        layout()
    end

    -- ==========================================================================
    -- Attach actions to button defs (now that functions exist)
    -- ==========================================================================

    do
        local actions = {
            scan       = do_scan,
            plan       = do_plan,
            swap       = do_exec_swap,
            fill       = do_exec_fill,
            val_miss   = do_val_miss,
            val_unused = do_val_unused,
            toggle     = function()
                state.collapsed = not state.collapsed
                layout()
            end,
        }
        for _, def in ipairs(BTN_DEFS) do
            def.action = actions[def.id]
        end
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
        BTN_DEFS = BTN_DEFS,
        max_file_scroll          = max_file_scroll,
        max_log_scroll           = max_log_scroll,
        ensure_file_scroll_valid = ensure_file_scroll_valid,
        ensure_log_scroll_valid  = ensure_log_scroll_valid,
        ensure_selection_visible = ensure_selection_visible,
        clear_log    = clear_log,
        push_log     = push_log,
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
        push_log('msg', 'Welcome to Wardrobe9! Press SCAN to begin.')
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
