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

return function(res, util, config, planner, portermod, scanmod, execmod, bags)
    local pui = {}

    local texts  = require('texts')
    local images = require('images')

    -- ==========================================================================
    -- Assets (shared with main UI)
    -- ==========================================================================

    local ADDON_PATH = windower.addon_path or (_addon and _addon.path) or 'addons/wardrobe9/'
    local ASSETS_DIR = ADDON_PATH .. 'assets/'

    local ASSET = {
        panel_bg       = ASSETS_DIR .. 'panel_bg.png',
        header_bg      = ASSETS_DIR .. 'header_bg.png',
        btn_wide       = ASSETS_DIR .. 'btn_wide.png',
        btn_wide_hover = ASSETS_DIR .. 'btn_wide_hover.png',
        btn_porter       = ASSETS_DIR .. 'btn_porter.png',
        btn_porter_hover = ASSETS_DIR .. 'btn_porter_hover.png',
        row_selected   = ASSETS_DIR .. 'row_selected.png',
        sb_track       = ASSETS_DIR .. 'sb_track.png',
        sb_thumb       = ASSETS_DIR .. 'sb_thumb.png',
        sb_arrow_up    = ASSETS_DIR .. 'sb_arrow_up.png',
        sb_arrow_down  = ASSETS_DIR .. 'sb_arrow_down.png',
        chk_on         = ASSETS_DIR .. 'chk_on.png',
        chk_off        = ASSETS_DIR .. 'chk_off.png',
    }

    -- ==========================================================================
    -- Layout constants
    -- ==========================================================================

    local PX = {
        PANEL_W     = 480,
        PAD         = 8,
        HEADER_H    = 24,

        BTN_W       = 228,
        BTN_H       = 18,
        BTN_GAP     = 8,
        BTN_Y       = 30,
        BTN_ROW2_Y  = 52,
        BTN_ROW3_Y  = 74,

        STATUS_Y    = 98,
        FILE_Y      = 116,
        FILE_ROWS   = 5,

        SECTION_GAP = 16,
        LOG_ROWS    = 12,
        LOG_LABEL_H = 16,

        SB_W        = 12,
        SB_BTN_H    = 16,
        CHK_SIZE    = 14,
        CHK_GAP     = 4,
        ROW_H       = 16,
        BOTTOM_PAD  = 8,
    }

    -- ==========================================================================
    -- Font metrics
    -- ==========================================================================

    local FONT_NAME = 'Consolas'
    local FONT_SIZE = 10
    local _cw = nil
    local _rh = nil

    local function char_w() return _cw or 7.5 end
    local function row_h()  return _rh or PX.ROW_H end

    local function chars_in(px)
        local c = char_w()
        if c <= 0 then return 60 end
        return math.floor(px / c)
    end

    -- ==========================================================================
    -- Derived geometry
    -- ==========================================================================

    local function content_w()   return PX.PANEL_W - PX.PAD*2 - PX.SB_W end
    local function file_list_h() return PX.FILE_ROWS * row_h() end
    local function log_y_off()   return PX.FILE_Y + file_list_h() + PX.SECTION_GAP + PX.LOG_LABEL_H end
    local function log_list_h()  return PX.LOG_ROWS * row_h() end
    local function panel_h()     return log_y_off() + log_list_h() + PX.BOTTOM_PAD end

    -- ==========================================================================
    -- Position
    -- ==========================================================================

    local UI = {
        x = (config and config.UI_START_X or 420) + 20,
        y = (config and config.UI_START_Y or 220) + 20,
        visible = false,
    }

    -- ==========================================================================
    -- Colors
    -- ==========================================================================

    local C = {
        text     = {255, 235, 235, 235},
        subtle   = {255, 190, 190, 190},
        btn_txt  = {255, 245, 245, 245},
        log_msg  = {255, 200, 220, 255},
        log_warn = {255, 255, 220, 140},
        log_err  = {255, 255, 160, 160},
        log_ok   = {255, 140, 255, 140},
    }

    -- ==========================================================================
    -- State
    -- ==========================================================================

    local state = {
        collapsed      = true,
        files          = {},
        selected_set   = {},
        selected_index = nil,
        status         = 'Ready. Select lua(s) and press RETRIEVAL SCAN.',
        hover          = nil,

        file_scroll = 0,

        log_lines      = {},
        log_scroll     = 0,
        log_max_lines  = 200,

        dragging       = false,
        drag_dx = 0, drag_dy = 0,

        file_sb_dragging = false, file_sb_drag_offset = 0,
        log_sb_dragging  = false, log_sb_drag_offset  = 0,

        last_identify  = nil,
        last_compat    = nil,
    }

    -- ==========================================================================
    -- Image / text helpers
    -- ==========================================================================

    local function make_img(p)
        local img = images.new()
        img:path(p)
        img:hide()
        return img
    end

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
    -- Image objects
    -- ==========================================================================

    local img_panel  = make_img(ASSET.panel_bg)
    local img_header = make_img(ASSET.header_bg)
    local img_toggle = make_img(ASSET.chk_off)
    local t_toggle   = texts.new('')

    local img_row_sel = {}
    local img_chk     = {}
    for i = 1, PX.FILE_ROWS do
        img_row_sel[i] = make_img(ASSET.row_selected)
        img_chk[i]     = make_img(ASSET.chk_off)
    end

    local img_file_sb_track = make_img(ASSET.sb_track)
    local img_file_sb_thumb = make_img(ASSET.sb_thumb)
    local img_file_sb_up    = make_img(ASSET.sb_arrow_up)
    local img_file_sb_down  = make_img(ASSET.sb_arrow_down)

    local img_log_sb_track = make_img(ASSET.sb_track)
    local img_log_sb_thumb = make_img(ASSET.sb_thumb)
    local img_log_sb_up    = make_img(ASSET.sb_arrow_up)
    local img_log_sb_down  = make_img(ASSET.sb_arrow_down)

    -- ==========================================================================
    -- Text objects
    -- ==========================================================================

    local t_title     = texts.new('')
    local t_status    = texts.new('')
    local t_file_rows = {}
    local t_log_title = texts.new('')
    local t_log_rows  = {}

    -- ==========================================================================
    -- Buttons
    -- ==========================================================================

    local BTN_DEFS = {
        { id='identify',       label='RETRIEVAL SCAN',    row=1 },
        { id='retrieve',       label='RETRIEVE',      row=1 },
        { id='retrieve_fill',  label='RETR+FILL',     row=2 },
        { id='retrieve_store', label='RETR+STORE',    row=2 },
        { id='check_compat',   label='DEPOSIT SCAN',   row=3 },
        { id='deposit_slips',  label='DEPOSIT', row=3 },
        { id='toggle',         label='+',             toggle=true },
    }

    for _, def in ipairs(BTN_DEFS) do
        if def.toggle then
            def.img  = img_toggle
            def.text = t_toggle
        else
            def.img  = make_img(ASSET.btn_porter)
            def.text = texts.new('')
        end
        apply_text_defaults(def.text)
    end

    -- ==========================================================================
    -- Scroll helpers
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
        if idx < state.file_scroll + 1 then
            state.file_scroll = idx - 1
        elseif idx > state.file_scroll + PX.FILE_ROWS then
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
    -- Hit-test rectangles
    -- ==========================================================================

    local Rect = {}

    function Rect.header() return UI.x, UI.y, PX.PANEL_W, PX.HEADER_H end

    function Rect.toggle_btn()
        local tx = UI.x + PX.PANEL_W - PX.PAD - PX.CHK_SIZE
        local ty = UI.y + math.floor((PX.HEADER_H - PX.CHK_SIZE) / 2)
        return tx, ty, PX.CHK_SIZE, PX.CHK_SIZE
    end

    function Rect.button(def)
        if def.toggle then return Rect.toggle_btn() end
        local bx = UI.x + PX.PAD
        local row_y
        if def.row == 3 then row_y = PX.BTN_ROW3_Y
        elseif def.row == 2 then row_y = PX.BTN_ROW2_Y
        else row_y = PX.BTN_Y end
        local by = UI.y + row_y
        -- Left or right in the row
        if def.id == 'identify' or def.id == 'retrieve_fill' or def.id == 'check_compat' then
            return bx, by, PX.BTN_W, PX.BTN_H
        else
            return bx + PX.BTN_W + PX.BTN_GAP, by, PX.BTN_W, PX.BTN_H
        end
    end

    function Rect.file_list()
        return UI.x + PX.PAD, UI.y + PX.FILE_Y, content_w(), PX.FILE_ROWS * row_h()
    end

    function Rect.point_in(mx, my, x, y, w, h)
        return mx >= x and mx <= (x+w) and my >= y and my <= (y+h)
    end

    local SB_HIT_PAD_X = 6
    local SB_HIT_PAD_Y = 4

    function Rect.point_in_pad(mx, my, x, y, w, h, px, py)
        px = px or 0; py = py or 0
        return Rect.point_in(mx, my, x-px, y-py, w+px*2, h+py*2)
    end

    -- File scrollbar rects
    local function fsb_x() return UI.x + PX.PANEL_W - PX.SB_W end
    local function fsb_y() return UI.y + PX.FILE_Y end
    local function fsb_h() return PX.FILE_ROWS * row_h() end

    function Rect.file_sb_upbtn()   return fsb_x(), fsb_y(), PX.SB_W, PX.SB_BTN_H end
    function Rect.file_sb_downbtn() return fsb_x(), fsb_y() + fsb_h() - PX.SB_BTN_H, PX.SB_W, PX.SB_BTN_H end

    function Rect.file_scrollbar()
        local ty = fsb_y() + PX.SB_BTN_H
        local th = math.max(PX.SB_BTN_H, fsb_h() - PX.SB_BTN_H*2)
        return fsb_x(), ty, PX.SB_W, th
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

    -- Log scrollbar rects
    local function lsb_x() return UI.x + PX.PANEL_W - PX.SB_W end
    local function lsb_y() return UI.y + log_y_off() end
    local function lsb_h() return PX.LOG_ROWS * row_h() end

    function Rect.log_sb_upbtn()   return lsb_x(), lsb_y(), PX.SB_W, PX.SB_BTN_H end
    function Rect.log_sb_downbtn() return lsb_x(), lsb_y() + lsb_h() - PX.SB_BTN_H, PX.SB_W, PX.SB_BTN_H end

    function Rect.log_scrollbar()
        local ty = lsb_y() + PX.SB_BTN_H
        local th = math.max(PX.SB_BTN_H, lsb_h() - PX.SB_BTN_H*2)
        return lsb_x(), ty, PX.SB_W, th
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

    -- ==========================================================================
    -- Render helpers
    -- ==========================================================================

    local function ensure_rows(tbl, n)
        for i = 1, n do
            if not tbl[i] then
                tbl[i] = texts.new('')
                apply_text_defaults(tbl[i])
            end
        end
    end

    local function place_img(img, x, y, w, h)
        img:pos(x, y)
        img:size(w, h)
        img:show()
    end

    local function scrollbar_imgs(track, thumb, up, down, up_fn, down_fn, track_fn, thumb_fn)
        local ax, ay, aw, ah = up_fn();    place_img(up,    ax, ay, aw, ah)
        ax, ay, aw, ah       = down_fn();  place_img(down,  ax, ay, aw, ah)
        ax, ay, aw, ah       = track_fn(); place_img(track, ax, ay, aw, ah)
        ax, ay, aw, ah       = thumb_fn(); place_img(thumb, ax, ay, aw, ah)
    end

    -- ==========================================================================
    -- Visibility
    -- ==========================================================================

    local function set_all_visible(v)
        local all_imgs = {
            img_panel, img_header,
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
        for _, def in ipairs(BTN_DEFS) do
            if not def.toggle then
                if v then def.img:show() else def.img:hide() end
                def.text:visible(v)
            end
        end
        -- Toggle handled separately for collapsed mode
        if not v then
            img_toggle:hide()
            t_toggle:visible(false)
        end
        local txts = { t_title, t_status, t_log_title }
        for _, t in ipairs(txts) do if t then t:visible(v) end end
        for _, t in pairs(t_file_rows) do if t then t:visible(v) end end
        for _, t in pairs(t_log_rows)  do if t then t:visible(v) end end
    end

    -- ==========================================================================
    -- Layout / render
    -- ==========================================================================

    local function layout()
        local fixed = { t_title, t_status, t_log_title }
        for _, t in ipairs(fixed) do apply_text_defaults(t) end
        for _, def in ipairs(BTN_DEFS) do apply_text_defaults(def.text) end

        if not UI.visible then
            ensure_rows(t_file_rows, PX.FILE_ROWS)
            ensure_rows(t_log_rows, PX.LOG_ROWS)
            set_all_visible(false)
            return
        end

        -- ---- Collapsed mode: header bar + toggle only ----
        if state.collapsed then
            ensure_rows(t_file_rows, PX.FILE_ROWS)
            ensure_rows(t_log_rows, PX.LOG_ROWS)
            set_all_visible(false)

            place_img(img_header, UI.x, UI.y, PX.PANEL_W, PX.HEADER_H)

            t_title:pos(UI.x + PX.PAD, UI.y + 4)
            t_title:text('Wardrobe9 — Porter Moogle')
            set_color(t_title, C.text)
            t_title:visible(true)

            local tx, ty, tw, th = Rect.toggle_btn()
            place_img(img_toggle, tx, ty, tw, th)
            t_toggle:pos(tx + 3, ty - 1)
            t_toggle:text('+')
            set_color(t_toggle, C.btn_txt)
            t_toggle:bg_alpha(0)
            t_toggle:visible(true)
            return
        end

        -- Panel + header
        place_img(img_panel,  UI.x, UI.y, PX.PANEL_W, math.floor(panel_h()))
        place_img(img_header, UI.x, UI.y, PX.PANEL_W, PX.HEADER_H)

        t_title:pos(UI.x + PX.PAD, UI.y + 4)
        t_title:text('Wardrobe9 — Porter Moogle')
        set_color(t_title, C.text)
        t_title:visible(true)

        -- ---- Collapse/expand toggle ----
        do
            local tx, ty, tw, th = Rect.toggle_btn()
            place_img(img_toggle, tx, ty, tw, th)
            t_toggle:pos(tx + 3, ty - 1)
            t_toggle:text('-')
            set_color(t_toggle, C.btn_txt)
            t_toggle:bg_alpha(0)
            t_toggle:visible(true)
        end

        -- Status
        local smax = chars_in(PX.PANEL_W - PX.PAD*2)
        t_status:pos(UI.x + PX.PAD, UI.y + PX.STATUS_Y)
        t_status:text((state.status or ''):sub(1, smax))
        set_color(t_status, C.subtle)
        t_status:visible(true)

        -- Buttons
        for _, def in ipairs(BTN_DEFS) do
            if not def.toggle then
            local bx, by, bw, bh = Rect.button(def)
            local is_hover = (state.hover == def.id)
            def.img:path(is_hover and ASSET.btn_porter_hover or ASSET.btn_porter)
            place_img(def.img, bx, by, bw, bh)
            local lw = #def.label * char_w()
            def.text:pos(bx + math.floor((bw - lw)/2), by + 1)
            def.text:text(def.label)
            set_color(def.text, C.btn_txt)
            def.text:bg_alpha(0)
            def.text:visible(true)
            end -- if not def.toggle
        end

        -- File rows
        local chk_total = PX.CHK_SIZE + PX.CHK_GAP
        local tw = content_w() - chk_total
        local rc = chars_in(tw)
        ensure_rows(t_file_rows, PX.FILE_ROWS)
        ensure_file_scroll_valid()

        local flx = UI.x + PX.PAD
        local fly = UI.y + PX.FILE_Y

        for vis = 1, PX.FILE_ROWS do
            local abs = state.file_scroll + vis
            local t   = t_file_rows[vis]
            local rec = state.files[abs]
            local ry  = fly + (vis-1) * row_h()
            local chk_y = ry + math.floor((row_h() - PX.CHK_SIZE)/2)
            local tx = flx + chk_total

            t:pos(tx, ry)
            if rec then
                local checked = state.selected_set[abs] == true
                img_chk[vis]:path(checked and ASSET.chk_on or ASSET.chk_off)
                place_img(img_chk[vis], flx, chk_y, PX.CHK_SIZE, PX.CHK_SIZE)
                t:text(pad_right(rec.label, rc))
                set_color(t, C.text)
                if checked then
                    place_img(img_row_sel[vis], flx, ry, content_w(), row_h())
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

        -- File scrollbar
        scrollbar_imgs(img_file_sb_track, img_file_sb_thumb, img_file_sb_up, img_file_sb_down,
            Rect.file_sb_upbtn, Rect.file_sb_downbtn, Rect.file_scrollbar, Rect.file_thumb)

        -- Log label
        t_log_title:pos(UI.x + PX.PAD, UI.y + log_y_off() - PX.LOG_LABEL_H)
        t_log_title:text('Porter Log')
        set_color(t_log_title, C.subtle)
        t_log_title:visible(true)

        -- Log rows
        ensure_rows(t_log_rows, PX.LOG_ROWS)
        ensure_log_scroll_valid()
        local llx = UI.x + PX.PAD
        local lly = UI.y + log_y_off()

        for vis = 1, PX.LOG_ROWS do
            local abs = state.log_scroll + vis
            local t   = t_log_rows[vis]
            local rec = state.log_lines[abs]
            t:pos(llx, lly + (vis-1) * row_h())
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
        scrollbar_imgs(img_log_sb_track, img_log_sb_thumb, img_log_sb_up, img_log_sb_down,
            Rect.log_sb_upbtn, Rect.log_sb_downbtn, Rect.log_scrollbar, Rect.log_thumb)
    end

    -- ==========================================================================
    -- Log
    -- ==========================================================================

    local function clear_log()
        state.log_lines = {}
        state.log_scroll = 0
        ensure_log_scroll_valid()
        if UI.visible then layout() end
    end

    local function push_log(level, s)
        s = tostring(s or '')
        if s == '' then return end
        local color = C.log_msg
        if level == 'warn' then color = C.log_warn
        elseif level == 'err' then color = C.log_err
        elseif level == 'ok'  then color = C.log_ok end

        local wrap_w = chars_in(content_w()) - 1
        local prefix = '[Porter] '
        -- simple wrap
        local full = prefix .. s
        while #full > 0 do
            local line = full:sub(1, wrap_w)
            full = full:sub(wrap_w + 1)
            state.log_lines[#state.log_lines+1] = { text = line, color = color }
        end
        while #state.log_lines > state.log_max_lines do
            table.remove(state.log_lines, 1)
        end
        state.log_scroll = max_log_scroll()
        ensure_log_scroll_valid()
        if UI.visible then layout() end
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
                        out[#out+1] = fn
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a:lower() < b:lower() end)
        return out
    end

    local function refresh_file_list()
        state.files        = {}
        state.selected_set = {}
        state.selected_index = nil
        state.file_scroll  = 0
        state.last_identify = nil

        local root, char, pname = util.get_gearswap_data_paths()

        for _, fn in ipairs(list_lua_files_in_dir(root)) do
            state.files[#state.files+1] = {
                label    = fn,
                rel      = fn,
                scope    = 'root',
                fullpath = util.safe_join(root, fn),
            }
        end
        for _, fn in ipairs(list_lua_files_in_dir(char)) do
            state.files[#state.files+1] = {
                label    = (pname and (pname..'/'..fn)) or ('CHAR/'..fn),
                rel      = fn,
                scope    = 'char',
                fullpath = util.safe_join(char, fn),
            }
        end
        ensure_file_scroll_valid()
        state.status = ('Found %d GearSwap lua(s). Select file(s) and press RETRIEVAL SCAN.'):format(#state.files)
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

    -- ==========================================================================
    -- Actions
    -- ==========================================================================

    local function do_identify()
        local files = selected_files_list()
        if #files == 0 then
            state.status = 'Check at least one lua file first.'
            push_log('warn', 'Select lua file(s) before pressing RETRIEVAL SCAN.')
            layout()
            return
        end
        clear_log()

        local result, err = portermod.identify_needed_on_slips(files)
        if not result then
            state.status = tostring(err)
            push_log('err', tostring(err))
            layout()
            return
        end

        state.last_identify = result

        if #result.items == 0 then
            state.status = 'No required items found on storage slips.'
            push_log('msg', ('File(s): %s'):format(result.label))
            push_log('msg', 'None of the required gear is stored on a Porter Mog Slip.')
            layout()
            return
        end

        state.status = ('%d item(s) on slips | %d free inv slots  [%s]'):format(
            #result.items, result.free_space, result.label)

        push_log('msg', ('File(s): %s'):format(result.label))
        push_log('msg', ('Items on slips: %d | Free inventory: %d'):format(
            #result.items, result.free_space))

        -- Group by slip
        local by_slip = {}
        for _, item in ipairs(result.items) do
            by_slip[item.slip_label] = by_slip[item.slip_label] or {}
            by_slip[item.slip_label][#by_slip[item.slip_label]+1] = item
        end

        local slip_labels = {}
        for k in pairs(by_slip) do slip_labels[#slip_labels+1] = k end
        table.sort(slip_labels)

        for _, label in ipairs(slip_labels) do
            local items = by_slip[label]
            local in_inv = items[1].in_inventory
            local loc    = items[1].slip_location
            local inv_tag
            if in_inv then
                inv_tag = ' (in inventory)'
            elseif loc then
                inv_tag = (' (in %s)'):format(loc)
            else
                inv_tag = ' (location unknown)'
            end
            push_log('msg', ('--- %s%s ---'):format(label, inv_tag))
            if not in_inv then
                if loc then
                    push_log('err', ('  WARNING: %s is in your %s. Move it to inventory to retrieve items.'):format(label, loc))
                else
                    push_log('err', ('  WARNING: %s is not in your inventory and could not be located.'):format(label))
                end
            end
            for _, item in ipairs(items) do
                push_log('msg', ('  [%s] %s'):format(item.group, item.name))
            end
        end

        -- Check for slips not in inventory
        local missing_count = 0
        for _ in pairs(result.slips_not_in_inv or {}) do missing_count = missing_count + 1 end
        if missing_count > 0 then
            push_log('warn', ('Note: %d slip(s) are NOT in your inventory. Move them to inventory before pressing RETRIEVE.'):format(missing_count))
        else
            push_log('ok', 'All required slips are in your inventory. Press RETRIEVE to continue.')
        end

        layout()
    end

    local function do_retrieve_common(post_action_fn)
        if portermod.is_busy() then
            push_log('warn', 'Retrieval already in progress.')
            return
        end

        if not state.last_identify then
            state.status = 'Press RETRIEVAL SCAN first.'
            push_log('warn', 'You must press RETRIEVAL SCAN before RETRIEVE.')
            layout()
            return
        end

        if #state.last_identify.items == 0 then
            push_log('msg', 'Nothing to retrieve.')
            layout()
            return
        end

        -- Re-check slip inventory status
        local result, err = portermod.identify_needed_on_slips(selected_files_list())
        if not result then
            push_log('err', tostring(err))
            layout()
            return
        end

        state.last_identify = result

        -- Save item IDs for post-action
        local retrieved_item_ids = {}
        for _, item in ipairs(result.items) do
            retrieved_item_ids[item.item_id] = true
        end

        -- Re-check NPC proximity
        if not portermod.find_porter_npc() then
            push_log('err', 'Porter Moogle is not in range. Move closer and try again.')
            layout()
            return
        end

        clear_log()
        push_log('msg', ('Attempting to retrieve %d item(s)...'):format(#result.items))
        state.status = 'Retrieving items from Porter Moogle...'
        layout()

        local ok = portermod.retrieve(result, function(success)
            state.last_identify = nil
            if success then
                push_log('ok', 'Retrieval complete.')
                state.status = 'Retrieval complete.'
                layout()
                if post_action_fn then
                    coroutine.schedule(function()
                        post_action_fn(retrieved_item_ids)
                    end, 1.5)
                end
            else
                push_log('warn', 'Retrieval finished with warnings. Check log above.')
                state.status = 'Retrieval finished. Check log.'
                layout()
            end
        end)

        if not ok then
            state.status = 'Retrieval failed. Check log.'
            layout()
        end
    end

    local function do_retrieve()
        do_retrieve_common(nil)
    end

    -- ======================================================
    -- RETR+FILL: retrieve from porter, then move directly
    -- from inventory into wardrobe slots with free space.
    -- ======================================================

    local function do_retrieve_fill()
        do_retrieve_common(function(item_ids)
            -- Get enabled destination wardrobes with free space.
            local dest_bags, _ = bags.build_dest_bags()

            if #dest_bags == 0 then
                push_log('warn', 'No destination wardrobes are enabled/available.')
                state.status = 'No wardrobes available.'
                layout()
                return
            end

            -- Find retrieved items in inventory
            local moves = {}
            local inv_ok, inv = pcall(windower.ffxi.get_items, 0)
            if inv_ok and inv and inv.max then
                for slot = 1, inv.max do
                    local entry = inv[slot]
                    if entry and entry.id and entry.id ~= 0
                       and entry.status == 0 and item_ids[entry.id] then
                        local r = res.items[entry.id]
                        local name = r and r.en or 'item'
                        moves[#moves+1] = {slot=slot, item_id=entry.id, name=name}
                        -- Remove from set so we don't double-move duplicates
                        item_ids[entry.id] = nil
                    end
                end
            end

            if #moves == 0 then
                push_log('msg', 'No items to move (not found in inventory).')
                layout()
                return
            end

            push_log('msg', ('Moving %d item(s) to wardrobes...'):format(#moves))
            state.status = 'Moving items to wardrobes...'
            layout()

            local idx = 1
            local function step()
                if idx > #moves then
                    push_log('ok', 'Wardrobe fill complete.')
                    state.status = 'Items moved to wardrobes.'
                    layout()
                    return
                end

                local mv = moves[idx]
                idx = idx + 1

                -- Find a destination wardrobe with free space
                local dest = nil
                for _, bag in ipairs(dest_bags) do
                    if bags.bag_free(bag.id) > 0 then
                        dest = bag
                        break
                    end
                end

                if not dest then
                    push_log('warn', 'All wardrobes are full. Remaining items left in inventory.')
                    state.status = 'Wardrobes full. Some items remain in inventory.'
                    layout()
                    return
                end

                local move_ok, move_err = pcall(windower.ffxi.move_item, 0, dest.id, mv.slot, 1)
                if move_ok then
                    push_log('msg', ('Moved: %s -> %s'):format(mv.name, dest.name))
                else
                    push_log('err', ('Failed to move %s: %s'):format(mv.name, tostring(move_err)))
                end

                coroutine.schedule(step, 0.6)
            end

            step()
        end)
    end

    -- ======================================================
    -- RETR+STORE: retrieve from porter, then store in
    -- Satchel / Case / Sack (portable storage bags)
    -- ======================================================

    local function do_retrieve_store()
        do_retrieve_common(function(item_ids)
            local STORAGE_BAGS = {
                {id=5, name='Satchel'},
                {id=7, name='Case'},
                {id=6, name='Sack'},
            }

            -- Find retrieved items in inventory
            local moves = {}
            local inv_ok, inv = pcall(windower.ffxi.get_items, 0)
            if inv_ok and inv and inv.max then
                for slot = 1, inv.max do
                    local entry = inv[slot]
                    if entry and entry.id and entry.id ~= 0
                       and entry.status == 0 and item_ids[entry.id] then
                        local r = res.items[entry.id]
                        local name = r and r.en or 'item'
                        moves[#moves+1] = {slot=slot, item_id=entry.id, name=name}
                        -- Remove from set so we don't double-move duplicates
                        item_ids[entry.id] = nil
                    end
                end
            end

            if #moves == 0 then
                push_log('msg', 'No items to store (already moved or not found in inventory).')
                layout()
                return
            end

            push_log('msg', ('Storing %d item(s) to portable storage...'):format(#moves))
            state.status = 'Moving items to storage...'
            layout()

            local idx = 1
            local function step()
                if idx > #moves then
                    push_log('ok', 'Storage complete.')
                    state.status = 'Items stored in portable storage.'
                    layout()
                    return
                end

                local mv = moves[idx]
                idx = idx + 1

                -- Find a destination bag with free space
                local dest = nil
                for _, bag in ipairs(STORAGE_BAGS) do
                    if bags.bag_enabled(bag.id) and bags.bag_free(bag.id) > 0 then
                        dest = bag
                        break
                    end
                end

                if not dest then
                    push_log('warn', 'No storage space in Satchel/Case/Sack. Remaining items left in inventory.')
                    state.status = 'Storage full. Some items remain in inventory.'
                    layout()
                    return
                end

                local move_ok, move_err = pcall(windower.ffxi.move_item, 0, dest.id, mv.slot, 1)
                if move_ok then
                    push_log('msg', ('Stored: %s -> %s'):format(mv.name, dest.name))
                else
                    push_log('err', ('Failed to store %s: %s'):format(mv.name, tostring(move_err)))
                end

                coroutine.schedule(step, 0.6)
            end

            step()
        end)
    end

    -- ======================================================
    -- CHECK SLIPS: scan inventory for slip-compatible items
    -- ======================================================

    local function do_check_compat()
        if portermod.is_busy() then
            push_log('warn', 'Porter operation in progress.')
            return
        end

        clear_log()
        state.last_compat = nil

        local result, err = portermod.check_slip_compatible()
        if not result then
            state.status = tostring(err)
            push_log('err', tostring(err))
            layout()
            return
        end

        state.last_compat = result

        if #result.items == 0 then
            state.status = 'No slip-compatible items found in inventory.'
            push_log('msg', 'Scanned inventory: no items can be deposited into slips.')
            layout()
            return
        end

        state.status = ('%d item(s) in inventory can be stored on slips.'):format(#result.items)

        push_log('msg', ('Found %d item(s) that can be deposited into slips:'):format(#result.items))

        -- Group by slip
        local by_slip = {}
        for _, item in ipairs(result.items) do
            by_slip[item.slip_label] = by_slip[item.slip_label] or {}
            by_slip[item.slip_label][#by_slip[item.slip_label]+1] = item
        end

        local slip_labels = {}
        for k in pairs(by_slip) do slip_labels[#slip_labels+1] = k end
        table.sort(slip_labels)

        for _, label in ipairs(slip_labels) do
            local items = by_slip[label]
            local slip_item_id = items[1].slip_item_id
            local in_inv = result.slips_in_inv[slip_item_id]
            local loc_info = result.slips_not_in_inv[slip_item_id]
            local inv_tag
            if in_inv then
                inv_tag = ' (in inventory)'
            elseif type(loc_info) == 'string' then
                inv_tag = (' (in %s)'):format(loc_info)
            else
                inv_tag = ' (location unknown)'
            end
            push_log('msg', ('--- %s%s ---'):format(label, inv_tag))
            if not in_inv then
                if type(loc_info) == 'string' then
                    push_log('err', ('  WARNING: %s is in your %s. Move it to inventory to deposit items.'):format(label, loc_info))
                else
                    push_log('err', ('  WARNING: %s is not in your inventory and could not be located.'):format(label))
                end
            end
            for _, item in ipairs(items) do
                push_log('msg', ('  %s'):format(item.name))
            end
        end

        -- Summary
        local missing_count = 0
        for _ in pairs(result.slips_not_in_inv or {}) do missing_count = missing_count + 1 end
        if missing_count > 0 then
            push_log('warn', ('Note: %d slip(s) are NOT in your inventory. Move them to inventory before pressing DEPOSIT SLIPS.'):format(missing_count))
        else
            push_log('ok', 'All required slips are in your inventory. Press DEPOSIT SLIPS to store items.')
        end

        layout()
    end

    -- ======================================================
    -- DEPOSIT SLIPS: store inventory items into slips
    -- ======================================================

    local function do_deposit_slips()
        if portermod.is_busy() then
            push_log('warn', 'Porter operation in progress.')
            return
        end

        if not state.last_compat then
            state.status = 'Press DEPOSIT SCAN first.'
            push_log('warn', 'You must press DEPOSIT SCAN before DEPOSIT.')
            layout()
            return
        end

        if #state.last_compat.items == 0 then
            push_log('msg', 'Nothing to deposit.')
            layout()
            return
        end

        -- Re-check NPC proximity
        if not portermod.find_porter_npc() then
            push_log('err', 'Porter Moogle is not in range. Move closer and try again.')
            layout()
            return
        end

        -- Re-scan for fresh data
        local result, err = portermod.check_slip_compatible()
        if not result then
            push_log('err', tostring(err))
            layout()
            return
        end

        state.last_compat = result

        if #result.items == 0 then
            push_log('msg', 'No items to deposit (inventory changed).')
            layout()
            return
        end

        clear_log()
        push_log('msg', ('Attempting to deposit %d item(s) into slips...'):format(#result.items))
        state.status = 'Depositing items into slips...'
        layout()

        local ok = portermod.deposit_into_slips(result, function(success)
            state.last_compat = nil
            if success then
                push_log('ok', 'Deposit complete. All items stored on slips.')
                state.status = 'Deposit complete.'
            else
                push_log('warn', 'Deposit finished with warnings. Check log above.')
                state.status = 'Deposit finished. Check log.'
            end
            layout()
        end)

        if not ok then
            state.status = 'Deposit failed. Check log.'
            layout()
        end
    end

    -- Attach actions
    local action_map = {
        identify       = do_identify,
        retrieve       = do_retrieve,
        retrieve_fill  = do_retrieve_fill,
        retrieve_store = do_retrieve_store,
        check_compat   = do_check_compat,
        deposit_slips  = do_deposit_slips,
        toggle         = function()
            state.collapsed = not state.collapsed
            layout()
        end,
    }
    for _, def in ipairs(BTN_DEFS) do
        def.action = action_map[def.id]
    end

    -- ==========================================================================
    -- Mouse handling (self-contained)
    -- ==========================================================================

    local function update_hover(mx, my)
        state.hover = nil
        for _, def in ipairs(BTN_DEFS) do
            local x, y, w, h = Rect.button(def)
            if Rect.point_in(mx, my, x, y, w, h) then
                state.hover = def.id
                return
            end
        end
    end

    local function scroll_file_by(n)
        state.file_scroll = (state.file_scroll or 0) + n
        ensure_file_scroll_valid()
        layout()
        return true
    end

    local function scroll_log_by(n)
        state.log_scroll = (state.log_scroll or 0) + n
        ensure_log_scroll_valid()
        layout()
        return true
    end

    local function click_buttons(mx, my)
        for _, def in ipairs(BTN_DEFS) do
            local x, y, w, h = Rect.button(def)
            if Rect.point_in(mx, my, x, y, w, h) then
                if def.action then def.action() end
                return true
            end
        end
        -- Scrollbar arrows
        local x, y, w, h = Rect.file_sb_upbtn()
        if Rect.point_in(mx, my, x, y, w, h) then return scroll_file_by(-1) end
        x, y, w, h = Rect.file_sb_downbtn()
        if Rect.point_in(mx, my, x, y, w, h) then return scroll_file_by(1) end
        x, y, w, h = Rect.log_sb_upbtn()
        if Rect.point_in(mx, my, x, y, w, h) then return scroll_log_by(-3) end
        x, y, w, h = Rect.log_sb_downbtn()
        if Rect.point_in(mx, my, x, y, w, h) then return scroll_log_by(3) end
        return false
    end

    local function click_file_list(mx, my)
        local lx, ly, lw, lh = Rect.file_list()
        if not Rect.point_in(mx, my, lx, ly, lw, lh) then return false end
        local vis = math.floor((my - ly) / row_h()) + 1
        if vis < 1 or vis > PX.FILE_ROWS then return false end
        local abs = state.file_scroll + vis
        if abs < 1 or abs > #state.files then return false end

        state.selected_set[abs] = not state.selected_set[abs] or nil
        state.last_identify = nil
        state.selected_index = abs
        ensure_selection_visible()
        layout()
        return true
    end

    local function begin_drag(mx, my)
        local hx, hy, hw, hh = Rect.header()
        if Rect.point_in(mx, my, hx, hy, hw, hh) then
            state.dragging = true
            state.drag_dx  = mx - UI.x
            state.drag_dy  = my - UI.y
            return true
        end
        return false
    end

    local function drag_move(mx, my)
        if not state.dragging then return false end
        UI.x = util.clamp(mx - state.drag_dx, 0, 2000)
        UI.y = util.clamp(my - state.drag_dy, 0, 2000)
        layout()
        return true
    end

    local function end_drag()
        if state.dragging then state.dragging = false; return true end
        return false
    end

    -- Scrollbar drag helpers (file)
    local function begin_file_sb_drag(mx, my)
        local sx, sy, sw, sh = Rect.file_thumb()
        if Rect.point_in_pad(mx, my, sx, sy, sw, sh, SB_HIT_PAD_X, SB_HIT_PAD_Y) then
            state.file_sb_dragging    = true
            state.file_sb_drag_offset = my - sy
            return true
        end
        local tx, ty, tw, th = Rect.file_scrollbar()
        if Rect.point_in_pad(mx, my, tx, ty, tw, th, SB_HIT_PAD_X, SB_HIT_PAD_Y) then
            local _, _, _, thumb_h = Rect.file_thumb()
            local maxy = th - thumb_h
            if maxy > 0 then
                local rel = util.clamp((my - ty) - (thumb_h/2), 0, maxy)
                local ms = max_file_scroll()
                if ms > 0 then
                    state.file_scroll = math.floor((rel / maxy) * ms + 0.5)
                    ensure_file_scroll_valid()
                end
                state.file_sb_dragging    = true
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
        local rel  = my - ty - state.file_sb_drag_offset
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

    -- Scrollbar drag helpers (log)
    local function begin_log_sb_drag(mx, my)
        local sx, sy, sw, sh = Rect.log_thumb()
        if Rect.point_in_pad(mx, my, sx, sy, sw, sh, SB_HIT_PAD_X, SB_HIT_PAD_Y) then
            state.log_sb_dragging    = true
            state.log_sb_drag_offset = my - sy
            return true
        end
        local tx, ty, tw, th = Rect.log_scrollbar()
        if Rect.point_in_pad(mx, my, tx, ty, tw, th, SB_HIT_PAD_X, SB_HIT_PAD_Y) then
            local _, _, _, thumb_h = Rect.log_thumb()
            local maxy = th - thumb_h
            if maxy > 0 then
                local rel = util.clamp((my - ty) - (thumb_h/2), 0, maxy)
                local ms = max_log_scroll()
                if ms > 0 then
                    state.log_scroll = math.floor((rel / maxy) * ms + 0.5)
                    ensure_log_scroll_valid()
                end
                state.log_sb_dragging    = true
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
        local rel  = my - ty - state.log_sb_drag_offset
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

    -- Main mouse dispatcher
    local function on_mouse(type, x, y, delta, blocked)
        if not UI.visible then return end

        update_hover(x, y)

        if type == 0 then -- move
            if state.dragging         then drag_move(x, y);          return true end
            if state.file_sb_dragging then file_sb_drag_move(x, y);  return true end
            if state.log_sb_dragging  then log_sb_drag_move(x, y);   return true end
            layout()
            return
        end

        if type == 1 then -- left down
            if click_buttons(x, y)      then return true end
            if click_file_list(x, y)    then return true end
            if begin_drag(x, y)         then return true end
            if begin_file_sb_drag(x, y) then return true end
            if begin_log_sb_drag(x, y)  then return true end
        end

        if type == 2 then -- left up
            if end_drag() then return true end
            state.file_sb_dragging = false
            state.log_sb_dragging  = false
            layout()
            return
        end
    end

    -- ==========================================================================
    -- Show / hide
    -- ==========================================================================

    local _saved_ui_logger = nil

    function pui.show()
        UI.visible = true
        state.dragging         = false
        state.file_sb_dragging = false
        state.log_sb_dragging  = false
        state.hover            = nil
        state.last_identify    = nil
        state.last_compat      = nil

        -- Redirect util messages to this panel's log while porter UI is active.
        _saved_ui_logger = util._get_ui_logger and util._get_ui_logger() or nil
        util.set_ui_logger(function(level, s) push_log(level, s) end)

        clear_log()
        push_log('msg', 'Porter Moogle detected nearby.')
        push_log('msg', '')
        push_log('msg', 'How to use:')
        push_log('msg', '  1. Check one or more GearSwap lua files below.')
        push_log('msg', '  2. Press RETRIEVAL to identify gear stored on slips.')
        push_log('msg', '  3. Choose a retrieve action:')
        push_log('msg', '')
        push_log('msg', '  RETRIEVE    — Withdraw items to inventory only.')
        push_log('msg', '  RETR+FILL   — Retrieve, then move into free wardrobe slots.')
        push_log('msg', '  RETR+STORE  — Retrieve, then store in Satchel/Case/Sack.')
        push_log('msg', '')
        push_log('msg', '  Or deposit items INTO slips:')
        push_log('msg', '  DEPOSIT SCAN   — Scan inventory for slip-compatible items.')
        push_log('msg', '  DEPOSIT  — Store those items into their slips.')
        refresh_file_list()
        layout()
    end

    function pui.hide()
        UI.visible = false
        state.dragging         = false
        state.file_sb_dragging = false
        state.log_sb_dragging  = false
        state.hover            = nil
        state.last_identify    = nil
        state.last_compat      = nil
        if portermod.is_busy() then
            portermod.abort()
        end

        -- Restore the original logger.
        if _saved_ui_logger then
            util.set_ui_logger(_saved_ui_logger)
        end
        _saved_ui_logger = nil
        clear_log()
        ensure_rows(t_file_rows, PX.FILE_ROWS)
        ensure_rows(t_log_rows, PX.LOG_ROWS)
        set_all_visible(false)
        layout()
    end

    function pui.is_visible() return UI.visible end

    -- ==========================================================================
    -- Mog House detection (to avoid overlap with main UI)
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
    -- Proximity check (called from prerender)
    -- ==========================================================================

    local _last_check = 0
    local CHECK_INTERVAL = 2  -- seconds

    function pui.proximity_check()
        local now = os.clock()
        if now - _last_check < CHECK_INTERVAL then return end
        _last_check = now

        -- Never show while in Mog House (main UI handles that).
        if is_mog_house() then
            if UI.visible then pui.hide() end
            return
        end

        local npc = portermod.find_porter_npc()
        if npc and not UI.visible then
            pui.show()
        elseif not npc and UI.visible and not portermod.is_busy() then
            pui.hide()
        end
    end

    -- ==========================================================================
    -- Events (registered by Wardrobe9.lua)
    -- ==========================================================================

    function pui.on_mouse(type, x, y, delta, blocked)
        return on_mouse(type, x, y, delta, blocked)
    end

    -- ==========================================================================
    -- Init
    -- ==========================================================================

    function pui.init()
        -- Measure font
        do
            local sample = string.rep('M', 20)
            local t = texts.new(sample)
            apply_text_defaults(t)
            t:bg_alpha(0); t:alpha(0); t:pos(0, 0); t:show()
            local ok, w, h = pcall(function()
                local ew, eh = t:extents()
                return ew, eh
            end)
            if ok and type(w) == 'number' and w > 0 then
                _cw = w / #sample
            end
            if ok and type(h) == 'number' and h > 0 then
                _rh = math.max(PX.ROW_H, math.floor(h + 6))
            end
            t:hide()
        end
        layout()
    end

    pui.init()

    return pui
end
