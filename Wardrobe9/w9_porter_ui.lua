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

return function(res, util, config, planner, portermod, scanmod, execmod, bags, prefs, dock)
    local pui = {}

    local texts  = require('texts')
    local images = require('images')

    -- ==========================================================================
    -- Assets 
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

        fav_on         = ASSETS_DIR .. 'fav_on.png',
        fav_off        = ASSETS_DIR .. 'fav_off.png',
        low_on         = ASSETS_DIR .. 'low_on.png',
        low_off        = ASSETS_DIR .. 'low_off.png',

        btn_full       = ASSETS_DIR .. 'btn_full.png',
        btn_full_hover = ASSETS_DIR .. 'btn_full_hover.png',
        btn_half       = ASSETS_DIR .. 'btn_half.png',
        btn_half_hover = ASSETS_DIR .. 'btn_half_hover.png',
        btn_third      = ASSETS_DIR .. 'btn_third.png',
        btn_third_hover= ASSETS_DIR .. 'btn_third_hover.png',
        tab_on         = ASSETS_DIR .. 'tab_on.png',
        tab_off        = ASSETS_DIR .. 'tab_off.png',
        tab_hot        = ASSETS_DIR .. 'tab_hot.png',
        divider        = ASSETS_DIR .. 'divider.png',
        sw_on          = ASSETS_DIR .. 'sw_on.png',
        sw_off         = ASSETS_DIR .. 'sw_off.png',
        sw_hot         = ASSETS_DIR .. 'sw_hot.png',
    }

    -- ==========================================================================
    -- Layout constants
    -- ==========================================================================

    local PX = {
        PANEL_W     = 480,
        PAD         = 8,
        HEADER_H    = 24,

        TAB_Y       = 26,
        TAB_H       = 22,
        TAB_GAP     = 3,
        TAB_COUNT   = 3,

        BTN_H       = 18,
        BTN_GAP     = 8,

        SEC1_LBL_Y  = 54,
        SEC1_BTN_Y  = 70,
        SEC2_LBL_Y  = 92,
        SEC2_BTN_Y  = 108,

        DIV_Y       = 132,
        STATUS_Y    = 140,
        FILE_Y      = 160,
        FILE_ROWS   = 5,

        SECTION_GAP = 16,
        LOG_ROWS    = 12,
        LOG_LABEL_H = 16,

        SW_W        = 96,
        SW_H        = 16,
        SW_GAP      = 4,

        SB_W        = 12,
        SB_BTN_H    = 16,
        CHK_SIZE    = 14,
        CHK_GAP     = 4,
        PRIO_SIZE   = 14,
        PRIO_GAP    = 4,
        PRIO_LPAD   = 6,
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
        tab_on   = {255, 255, 255, 255},
        tab_off  = {255, 150, 190, 255}, 
        step     = {255, 150, 190, 255},
        fav      = { 95, 220, 115, 255},
        low      = {235,  95,  95, 255}, 
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
        tab            = 1,
        files          = {},
        selected_set   = {},
        selected_index = nil,
        status         = 'Ready. Select lua(s) and press SCAN LUAS FOR MISSING.',
        hover          = nil,
        hover_tab      = nil,

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
        last_validate  = nil,
    }

    local ALWAYS_ACCESSIBLE_BAGS = {
        [0]=true, [5]=true, [6]=true, [7]=true,
        [8]=true, [10]=true, [11]=true, [12]=true,
        [13]=true, [14]=true, [15]=true, [16]=true,
    }

    local FULL_ACCESS_BAGS = { [1]=true, [2]=true, [4]=true, [9]=true }

    -- Safe (1) and Safe 2 (9) are reachable from the Mog Garden, but they are
    -- also where placed Mog House furniture lives. Placed furniture reports as
    -- an ordinary item, cannot be moved, and cannot be told apart from loose
    -- gear, so RETRIEVE UNUSED ITEMS AND SLIPS never pulls items out of them.
    -- Slips themselves are still allowed to come from Safe / Safe 2 
    local SAFE_BAGS = { [1]=true, [9]=true }

    local function is_safe_bag(bag_id)
        return SAFE_BAGS[bag_id] == true
    end

    local function bag_accessible(bag_id)
        if ALWAYS_ACCESSIBLE_BAGS[bag_id] then
            return bag_id == 0 or bags.bag_enabled(bag_id)
        end
        if FULL_ACCESS_BAGS[bag_id] and dock.is_mog_garden() then
            return bags.bag_enabled(bag_id)
        end
        return false
    end

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
    local img_fav     = {}
    local img_low     = {}
    for i = 1, PX.FILE_ROWS do
        img_row_sel[i] = make_img(ASSET.row_selected)
        img_chk[i]     = make_img(ASSET.chk_off)
        img_fav[i]     = make_img(ASSET.fav_off)
        img_low[i]     = make_img(ASSET.low_off)
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
    local t_sec1      = texts.new('')
    local t_sec2      = texts.new('')

    local img_divider = make_img(ASSET.divider)

    local SW_DEFS = {}
    for i, id in ipairs(dock.PANELS) do
        SW_DEFS[i] = { id = id, label = dock.LABELS[id], img = make_img(ASSET.sw_off), text = texts.new('') }
        apply_text_defaults(SW_DEFS[i].text)
    end

    local TAB_DEFS = {
        { id=1, label='RETRIEVE ITEMS' },
        { id=2, label='DEPOSIT ITEMS'  },
        { id=3, label='VALIDATE SLIPS' },
    }

    for _, tab in ipairs(TAB_DEFS) do
        tab.img  = make_img(ASSET.tab_off)
        tab.text = texts.new('')
        apply_text_defaults(tab.text)
    end

    local TAB_TITLES = {
        [1] = { 'STEP 1  -  Scan Luas for Missing',
                'STEP 2  -  Retrieve Missing  /  RETR+FILL  /  RETR+STORE' },
        [2] = { 'STEP 1  -  Scan Inventory for Deposit',
                'STEP 2  -  Deposit' },
        [3] = { 'STEP 1  -  Validate All Slips  (tick lua\'s NOT to consider)',
                'STEP 2  -  Retrieve Unused Items and Slips' },
    }

    -- ==========================================================================
    -- Buttons
    -- ==========================================================================

    local BTN_DEFS = {
        { id='identify',       label='SCAN LUAS FOR MISSING',      tab=1, row=1, slot='full'   },
        { id='retrieve',       label='RETRIEVE MISSING',           tab=1, row=2, slot='third1' },
        { id='retrieve_fill',  label='RETR+FILL',                  tab=1, row=2, slot='third2' },
        { id='retrieve_store', label='RETR+STORE',                 tab=1, row=2, slot='third3' },
        { id='check_compat',   label='SCAN INVENTORY FOR DEPOSIT', tab=2, row=1, slot='full'   },
        { id='deposit_slips',  label='DEPOSIT',                    tab=2, row=2, slot='full'   },
        { id='validate_slips', label='VALIDATE ALL SLIPS',         tab=3, row=1, slot='full'   },
        { id='retrieve_unused',label='RETRIEVE UNUSED ITEMS AND SLIPS', tab=3, row=2, slot='full'   },
        { id='toggle',         label='+',                          toggle=true },
    }

    local BTN_ART = {
        full   = { ASSET.btn_full,  ASSET.btn_full_hover  },
        half1  = { ASSET.btn_half,  ASSET.btn_half_hover  },
        half2  = { ASSET.btn_half,  ASSET.btn_half_hover  },
        third1 = { ASSET.btn_third, ASSET.btn_third_hover },
        third2 = { ASSET.btn_third, ASSET.btn_third_hover },
        third3 = { ASSET.btn_third, ASSET.btn_third_hover },
    }

    for _, def in ipairs(BTN_DEFS) do
        if def.toggle then
            def.img  = img_toggle
            def.text = t_toggle
        else
            def.art  = BTN_ART[def.slot] or BTN_ART.full
            def.img  = make_img(def.art[1])
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

    function Rect.dock_tab(i)
        local n = #SW_DEFS
        local right = UI.x + PX.PANEL_W - PX.PAD - PX.CHK_SIZE - 8
        local x = right - (n - i + 1) * PX.SW_W - (n - i) * PX.SW_GAP
        local y = UI.y + math.floor((PX.HEADER_H - PX.SW_H) / 2)
        return x, y, PX.SW_W, PX.SW_H
    end

    local function inner_w() return PX.PANEL_W - PX.PAD * 2 end

    function Rect.tab(i)
        local total = inner_w()
        local tw = math.floor((total - PX.TAB_GAP * (PX.TAB_COUNT - 1)) / PX.TAB_COUNT)
        local tx = UI.x + PX.PAD + (i - 1) * (tw + PX.TAB_GAP)
        if i == PX.TAB_COUNT then
            tw = (UI.x + PX.PAD + total) - tx
        end
        return tx, UI.y + PX.TAB_Y, tw, PX.TAB_H
    end

    local function slot_geom(slot)
        local total = inner_w()
        local base  = UI.x + PX.PAD
        if slot == 'half1' or slot == 'half2' then
            local w = math.floor((total - PX.BTN_GAP) / 2)
            local i = (slot == 'half1') and 0 or 1
            return base + i * (w + PX.BTN_GAP), w
        end
        if slot == 'third1' or slot == 'third2' or slot == 'third3' then
            local w = math.floor((total - PX.BTN_GAP * 2) / 3)
            local i = (slot == 'third1') and 0 or ((slot == 'third2') and 1 or 2)
            return base + i * (w + PX.BTN_GAP), w
        end
        return base, total
    end

    function Rect.button(def)
        if def.toggle then return Rect.toggle_btn() end
        local row_y = (def.row == 2) and PX.SEC2_BTN_Y or PX.SEC1_BTN_Y
        local bx, bw = slot_geom(def.slot)
        return bx, UI.y + row_y, bw, PX.BTN_H
    end

    local function btn_active(def)
        if def.toggle then return true end
        return def.tab == state.tab
    end

    function Rect.file_list()
        return UI.x + PX.PAD, UI.y + PX.FILE_Y, content_w(), PX.FILE_ROWS * row_h()
    end

    -- Per-row priority button geometry
    function Rect.file_prio_btn(vis, which)
        local flx = UI.x + PX.PAD
        local fly = UI.y + PX.FILE_Y
        local ry  = fly + (vis-1) * row_h()
        local by  = ry + math.floor((row_h() - PX.PRIO_SIZE) / 2)
        local low_x = flx + content_w() - PX.PRIO_SIZE
        local fav_x = low_x - PX.PRIO_GAP - PX.PRIO_SIZE
        if which == 'fav' then return fav_x, by, PX.PRIO_SIZE, PX.PRIO_SIZE end
        return low_x, by, PX.PRIO_SIZE, PX.PRIO_SIZE
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
            img_panel, img_header, img_divider,
            img_file_sb_track, img_file_sb_thumb, img_file_sb_up, img_file_sb_down,
            img_log_sb_track,  img_log_sb_thumb,  img_log_sb_up,  img_log_sb_down,
        }
        for _, tab in ipairs(TAB_DEFS) do
            if v then tab.img:show() else tab.img:hide() end
            tab.text:visible(v)
        end
        if not v then
            for _, sw in ipairs(SW_DEFS) do
                sw.img:hide()
                sw.text:visible(false)
            end
        end
        for _, img in ipairs(all_imgs) do
            if v then img:show() else img:hide() end
        end
        for i = 1, PX.FILE_ROWS do
            if v then img_row_sel[i]:show() else img_row_sel[i]:hide() end
            if v then img_chk[i]:show()     else img_chk[i]:hide()     end
            if v then img_fav[i]:show()     else img_fav[i]:hide()     end
            if v then img_low[i]:show()     else img_low[i]:hide()     end
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
        local txts = { t_title, t_status, t_log_title, t_sec1, t_sec2 }
        for _, t in ipairs(txts) do if t then t:visible(v) end end
        for _, t in pairs(t_file_rows) do if t then t:visible(v) end end
        for _, t in pairs(t_log_rows)  do if t then t:visible(v) end end
    end

    -- ==========================================================================
    -- Layout / render
    -- ==========================================================================

    local function layout()
        local fixed = { t_title, t_status, t_log_title, t_sec1, t_sec2 }
        for _, t in ipairs(fixed) do apply_text_defaults(t) end
        for _, def in ipairs(BTN_DEFS) do apply_text_defaults(def.text) end
        for _, tab in ipairs(TAB_DEFS) do apply_text_defaults(tab.text) end

        if not UI.visible or dock.hidden_by_dock('porter') then
            ensure_rows(t_file_rows, PX.FILE_ROWS)
            ensure_rows(t_log_rows, PX.LOG_ROWS)
            set_all_visible(false)
            return
        end

        local function render_dock_tabs()
            if not dock.dual() then
                for _, sw in ipairs(SW_DEFS) do
                    sw.img:hide()
                    sw.text:visible(false)
                end
                return
            end
            for i, sw in ipairs(SW_DEFS) do
                local sx, sy, sw_w, sw_h = Rect.dock_tab(i)
                local on = (dock.active_panel() == sw.id)
                local art = ASSET.sw_off
                if on then art = ASSET.sw_on
                elseif state.hover_sw == sw.id then art = ASSET.sw_hot end
                sw.img:path(art)
                place_img(sw.img, sx, sy, sw_w, sw_h)
                local lw = #sw.label * char_w()
                sw.text:pos(sx + math.floor((sw_w - lw) / 2), sy + 1)
                sw.text:text(sw.label)
                set_color(sw.text, on and C.tab_on or C.tab_off)
                sw.text:bg_alpha(0)
                sw.text:visible(true)
            end
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
            render_dock_tabs()
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

        render_dock_tabs()

        for i, tab in ipairs(TAB_DEFS) do
            local tx, ty, tw, th = Rect.tab(i)
            local active = (state.tab == i)
            local art = ASSET.tab_off
            if active then art = ASSET.tab_on
            elseif state.hover_tab == i then art = ASSET.tab_hot end
            tab.img:path(art)
            place_img(tab.img, tx, ty, tw, th)

            local label = tab.label
            local maxc = chars_in(tw - 8)
            if #label > maxc then label = label:sub(1, maxc) end
            local lw = #label * char_w()
            tab.text:pos(tx + math.floor((tw - lw) / 2), ty + 4)
            tab.text:text(label)
            set_color(tab.text, active and C.tab_on or C.tab_off)
            tab.text:bg_alpha(0)
            tab.text:visible(true)
        end

        local titles = TAB_TITLES[state.tab] or {}
        local lblmax = chars_in(inner_w())

        t_sec1:pos(UI.x + PX.PAD, UI.y + PX.SEC1_LBL_Y)
        t_sec1:text((titles[1] or ''):sub(1, lblmax))
        set_color(t_sec1, C.step)
        t_sec1:visible(true)

        t_sec2:pos(UI.x + PX.PAD, UI.y + PX.SEC2_LBL_Y)
        t_sec2:text((titles[2] or ''):sub(1, lblmax))
        set_color(t_sec2, C.step)
        t_sec2:visible(true)

        place_img(img_divider, UI.x + PX.PAD, UI.y + PX.DIV_Y, inner_w(), 2)

        local smax = chars_in(PX.PANEL_W - PX.PAD*2)
        t_status:pos(UI.x + PX.PAD, UI.y + PX.STATUS_Y)
        t_status:text((state.status or ''):sub(1, smax))
        set_color(t_status, C.subtle)
        t_status:visible(true)

        for _, def in ipairs(BTN_DEFS) do
            if not def.toggle then
                if btn_active(def) then
                    local bx, by, bw, bh = Rect.button(def)
                    local is_hover = (state.hover == def.id)
                    def.img:path(is_hover and def.art[2] or def.art[1])
                    place_img(def.img, bx, by, bw, bh)
                    local label = def.label
                    local maxc = chars_in(bw - 6)
                    if #label > maxc then label = label:sub(1, maxc) end
                    local lw = #label * char_w()
                    def.text:pos(bx + math.floor((bw - lw)/2), by + 1)
                    def.text:text(label)
                    set_color(def.text, C.btn_txt)
                    def.text:bg_alpha(0)
                    def.text:visible(true)
                else
                    def.img:hide()
                    def.text:visible(false)
                end
            end
        end

        -- File rows
        local chk_total = PX.CHK_SIZE + PX.CHK_GAP
        local prio_total = PX.PRIO_LPAD + PX.PRIO_SIZE + PX.PRIO_GAP + PX.PRIO_SIZE
        local tw = content_w() - chk_total - prio_total
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

                local pr = rec.priority
                if pr == 'fav' then
                    set_color(t, C.fav)
                elseif pr == 'low' then
                    set_color(t, C.low)
                else
                    set_color(t, C.text)
                end

                local fx, fy = Rect.file_prio_btn(vis, 'fav')
                local lx2, ly2 = Rect.file_prio_btn(vis, 'low')
                img_fav[vis]:path(pr == 'fav' and ASSET.fav_on or ASSET.fav_off)
                img_low[vis]:path(pr == 'low' and ASSET.low_on or ASSET.low_off)
                place_img(img_fav[vis], fx,  fy,  PX.PRIO_SIZE, PX.PRIO_SIZE)
                place_img(img_low[vis], lx2, ly2, PX.PRIO_SIZE, PX.PRIO_SIZE)

                if checked then
                    place_img(img_row_sel[vis], flx, ry, content_w(), row_h())
                else
                    img_row_sel[vis]:hide()
                end
            else
                t:text(pad_right('', rc))
                img_chk[vis]:hide()
                img_row_sel[vis]:hide()
                img_fav[vis]:hide()
                img_low[vis]:hide()
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
                out[#out+1] = line
                break
            end
            local cut = w
            local sub = s:sub(1, w)
            local sp  = sub:match('^.*()%s')
            if sp and sp > 8 then cut = sp end
            local chunk = rtrim(s:sub(1, cut))
            s = s:sub(cut + 1):gsub('^%s+', '')
            if not first and cont_indent ~= '' then chunk = cont_indent .. chunk end
            out[#out+1] = chunk
            first = false
        end
        return out
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
        local wrapped = wrap_text(prefix .. s, wrap_w, string.rep(' ', #prefix))
        for _, line in ipairs(wrapped) do
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

    -- Priority ordering
    local function file_priority_rank(p)
        if p == 'fav' then return 0 end
        if p == 'low' then return 2 end
        return 1
    end

    local function sort_files()
        table.sort(state.files, function(a, b)
            local ra, rb = file_priority_rank(a.priority), file_priority_rank(b.priority)
            if ra ~= rb then return ra < rb end
            return (a.label or ''):lower() < (b.label or ''):lower()
        end)
    end

    local function apply_priorities()
        for _, rec in ipairs(state.files) do
            rec.priority = prefs and prefs.get(rec.fullpath or rec.label) or nil
        end
        sort_files()
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

        apply_priorities()

        ensure_file_scroll_valid()
        state.status = ('Found %d GearSwap lua(s). Select file(s), then use the tabs above.'):format(#state.files)
    end

    local function toggle_file_priority(abs, which)
        local rec = state.files[abs]
        if not rec or not prefs then return end

        rec.priority = prefs.toggle(rec.fullpath or rec.label, which)

        local checked_keys = {}
        for i, v in pairs(state.selected_set) do
            if v and state.files[i] then
                checked_keys[state.files[i].fullpath or state.files[i].label] = true
            end
        end

        sort_files()

        state.selected_set = {}
        for i, r in ipairs(state.files) do
            if checked_keys[r.fullpath or r.label] then
                state.selected_set[i] = true
            end
        end
        state.selected_index = nil

        ensure_file_scroll_valid()
        layout()
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

    local function report_ignored(n)
        if not n or n <= 0 then return end
        push_log('msg', ('Ignoring %d item(s) via PORTER_IGNORE_ITEMS.'):format(n))
    end

    local _ignore_warned = false
    local function report_ignore_problems()
        if _ignore_warned then return end
        _ignore_warned = true
        if not portermod.ignore_unknown_names then return end
        local unknown = portermod.ignore_unknown_names()
        if not unknown or #unknown == 0 then return end
        push_log('warn', ('%d name(s) in PORTER_IGNORE_ITEMS match no known item:'):format(#unknown))
        for i, nm in ipairs(unknown) do
            if i > 10 then
                push_log('warn', ('  ...and %d more'):format(#unknown - 10))
                break
            end
            push_log('warn', ('  %s'):format(nm))
        end
        push_log('warn', 'Check the spelling in w9_config.lua.')
    end

    local function do_identify()
        local files = selected_files_list()
        if #files == 0 then
            state.status = 'Check at least one lua file first.'
            push_log('warn', 'Select lua file(s) before pressing SCAN LUAS FOR MISSING.')
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
        report_ignored(result.ignored_count)

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
            push_log('warn', ('Note: %d slip(s) are NOT in your inventory. Move them to inventory before pressing RETRIEVE MISSING.'):format(missing_count))
        else
            push_log('ok', 'All required slips are in your inventory. Press RETRIEVE MISSING to continue.')
        end

        layout()
    end

    local function do_retrieve_common(post_action_fn)
        if portermod.is_busy() then
            push_log('warn', 'Retrieval already in progress.')
            return
        end

        if not state.last_identify then
            state.status = 'Press SCAN LUAS FOR MISSING first.'
            push_log('warn', 'Step 1 first: press SCAN LUAS FOR MISSING before RETRIEVE MISSING.')
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
            else
                push_log('warn', 'Retrieval finished with warnings. Check log above.')
                state.status = 'Retrieval finished. Check log.'
            end
            layout()
            -- Run post-action even on partial success (e.g. inventory filled up)
            -- so that RETR+FILL can move items to wardrobes and loop back.
            if post_action_fn then
                coroutine.schedule(function()
                    post_action_fn(retrieved_item_ids, success)
                end, 1.5)
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
    -- Loops automatically: retrieve batch → fill wardrobes →
    -- retrieve more, until all items are done or wardrobes
    -- are full.
    -- ======================================================

    local MAX_FILL_CYCLES = 20  -- safety limit to prevent infinite loops

    local function do_retrieve_fill()
        local cycle = 0

        local function fill_cycle(item_ids, retrieval_complete)
            cycle = cycle + 1

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
                    push_log('ok', ('Wardrobe fill complete (cycle %d).'):format(cycle))
                    layout()

                    -- If retrieval stopped early (inventory was full) and we
                    -- haven't hit the safety limit, re-scan and retrieve more.
                    if not retrieval_complete and cycle < MAX_FILL_CYCLES then
                        coroutine.schedule(function()
                            -- Re-scan to see if items remain on slips.
                            local files = selected_files_list()
                            if #files == 0 then
                                state.status = 'Items moved to wardrobes.'
                                layout()
                                return
                            end

                            local result, err = portermod.identify_needed_on_slips(files)
                            if not result or #result.items == 0 then
                                push_log('ok', 'All needed items retrieved and stored.')
                                state.status = 'All items moved to wardrobes.'
                                layout()
                                return
                            end

                            state.last_identify = result
                            push_log('msg', ('%d item(s) still on slips. Retrieving next batch...'):format(#result.items))
                            layout()

                            -- Kick off another retrieve cycle.
                            do_retrieve_common(function(ids2, success2)
                                fill_cycle(ids2, success2)
                            end)
                        end, 1.5)
                    else
                        state.status = 'Items moved to wardrobes.'
                        layout()
                    end
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
        end

        do_retrieve_common(function(item_ids, success)
            fill_cycle(item_ids, success)
        end)
    end

    -- ======================================================
    -- RETR+STORE: retrieve from porter, then store in
    -- Satchel / Case / Sack (portable storage bags).
    -- Loops automatically: retrieve batch → store to bags →
    -- retrieve more, until all items are done or bags are full.
    -- ======================================================

    local MAX_STORE_CYCLES = 20  -- safety limit

    local function do_retrieve_store()
        local cycle = 0

        local STORAGE_BAGS = {
            {id=5, name='Satchel'},
            {id=7, name='Case'},
            {id=6, name='Sack'},
        }

        local function store_cycle(item_ids, retrieval_complete)
            cycle = cycle + 1

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
                    push_log('ok', ('Storage complete (cycle %d).'):format(cycle))
                    layout()

                    -- If retrieval stopped early (inventory was full) and we
                    -- haven't hit the safety limit, re-scan and retrieve more.
                    if not retrieval_complete and cycle < MAX_STORE_CYCLES then
                        coroutine.schedule(function()
                            local files = selected_files_list()
                            if #files == 0 then
                                state.status = 'Items stored in portable storage.'
                                layout()
                                return
                            end

                            local result, err = portermod.identify_needed_on_slips(files)
                            if not result or #result.items == 0 then
                                push_log('ok', 'All needed items retrieved and stored.')
                                state.status = 'All items stored in portable storage.'
                                layout()
                                return
                            end

                            state.last_identify = result
                            push_log('msg', ('%d item(s) still on slips. Retrieving next batch...'):format(#result.items))
                            layout()

                            do_retrieve_common(function(ids2, success2)
                                store_cycle(ids2, success2)
                            end)
                        end, 1.5)
                    else
                        state.status = 'Items stored in portable storage.'
                        layout()
                    end
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
        end

        do_retrieve_common(function(item_ids, success)
            store_cycle(item_ids, success)
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
        report_ignored(result.ignored_count)

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
            push_log('warn', ('%d slip(s) are NOT in your inventory. Those items will be skipped. Move slips to inventory to deposit all.'):format(missing_count))
        else
            push_log('ok', 'All required slips are in your inventory. Press DEPOSIT to store items.')
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
            state.status = 'Press SCAN INVENTORY FOR DEPOSIT first.'
            push_log('warn', 'Step 1 first: press SCAN INVENTORY FOR DEPOSIT before DEPOSIT.')
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

    local function do_validate_slips()
        if portermod.is_busy() then
            push_log('warn', 'Porter operation in progress.')
            return
        end

        clear_log()

        local files = selected_files_list()
        local result, err = portermod.validate_all_slips(files)
        if not result then
            state.status = tostring(err)
            push_log('err', tostring(err))
            layout()
            return
        end

        local excl_count = #files

        push_log('msg', 'Validate All Slips')
        push_log('msg', ('Searched %d container(s) for slip-storable gear.'):format(result.bags_scanned))
        report_ignored(result.ignored_count)
        report_ignore_problems()
        if excl_count == 0 then
            push_log('warn', 'No lua(s) checked - listing every match, including gear you use.')
            push_log('warn', 'Tick lua(s) below to leave their items out of this report.')
        else
            push_log('msg', ('Excluding items from: %s'):format(result.label))
            push_log('msg', ('Ignored %d item(s) from %d gear name(s).')
                :format(result.excluded_items, result.excluded_name_count))
        end

        if #result.items == 0 then
            state.status = 'Validate: nothing left that can be stored on a slip.'
            push_log('ok', 'No storable items found outside those lua(s).')
            layout()
            return
        end

        local function item_state(item)
            if is_safe_bag(item.bag_id) then return 'safe' end
            if not bag_accessible(item.bag_id) then return 'far' end
            return ''
        end

        local safe_total, far_total = 0, 0
        for _, item in ipairs(result.items) do
            local st = item_state(item)
            if st == 'safe' then safe_total = safe_total + 1
            elseif st == 'far' then far_total = far_total + 1 end
        end

        state.last_validate = result
        state.status = ('Validate: %d item(s) across %d slip(s). Excluded: %d lua(s)')
            :format(#result.items, result.slip_count, excl_count)

        push_log('ok', ('%d item(s) can be moved onto %d slip(s):')
            :format(#result.items, result.slip_count))
        if safe_total > 0 then
            push_log('warn', ('%d of those sit in Safe / Safe 2 and will not be retrieved.')
                :format(safe_total))
        end
        if far_total > 0 then
            push_log('warn', ('%d of those sit in a bag you cannot reach from here.')
                :format(far_total))
        end

        local by_slip = {}
        local order = {}
        for _, item in ipairs(result.items) do
            if not by_slip[item.slip_label] then
                by_slip[item.slip_label] = {}
                order[#order+1] = item.slip_label
            end
            local list = by_slip[item.slip_label]
            list[#list+1] = item
        end
        table.sort(order)

        for _, label in ipairs(order) do
            local items = by_slip[label]
            local sid   = items[1].slip_item_id
            local loc   = result.slips_not_in_inv[sid]
            local tag
            local slip_far = false
            if result.slips_in_inv[sid] then
                tag = ' (in Inventory)'
            elseif type(loc) == 'string' then
                tag = (' (in %s)'):format(loc)
                local loc_id = bags.bag_id_by_name(loc)
                slip_far = (loc_id ~= nil) and not bag_accessible(loc_id)
            else
                tag = ' (not owned - buy it)'
            end
            push_log('msg', ('--- %s%s | %d item(s) ---'):format(label, tag, #items))
            if slip_far then
                push_log('warn', '  ^ slip inaccessible - skipped')
            end
            for i, item in ipairs(items) do
                if i > 60 then
                    push_log('msg', ('  ...and %d more'):format(#items - 60))
                    break
                end
                local qty = (item.count and item.count > 1) and (' x%d'):format(item.count) or ''
                local st  = item_state(item)
                if st == 'safe' then
                    push_log('warn', ('  %s%s - %s  [SAFE - skipped]')
                        :format(item.name, qty, item.bag_name))
                elseif st == 'far' then
                    push_log('warn', ('  %s%s - %s  [inaccessible - skipped]')
                        :format(item.name, qty, item.bag_name))
                else
                    push_log('msg', ('  %s%s - %s'):format(item.name, qty, item.bag_name))
                end
            end
        end

        push_log('msg', '')
        if safe_total > 0 then
            push_log('warn', ('%d row(s) marked [SAFE - skipped] live in Safe / Safe 2. RETRIEVE UNUSED ITEMS AND SLIPS leaves those alone, because those bags also hold placed furniture that cannot be moved. Move any you do want out of Safe / Safe 2 by hand first.'):format(safe_total))
        end
        if far_total > 0 then
            push_log('warn', ('%d row(s) marked [inaccessible - skipped] are in a bag you cannot open from here. Only Mog Satchel, Mog Sack, Mog Case and Wardrobes 1-8 work anywhere; the rest need you to be in your Mog Garden.'):format(far_total))
        end
        if safe_total > 0 or far_total > 0 then
            push_log('msg', '')
        end
        push_log('warn', 'Nothing was moved. This is a report only.')
        push_log('warn', 'Press RETRIEVE UNUSED ITEMS AND SLIPS to pull the unmarked rows and their slips into your inventory.')

        layout()
    end

    local function inventory_free()
        local ok, bi = pcall(windower.ffxi.get_bag_info, 0)
        if not ok or not bi then return 0 end
        return math.max(0, (bi.max or 0) - (bi.count or 0))
    end

    local function do_retrieve_unused()
        if portermod.is_busy() then
            push_log('warn', 'Porter operation in progress.')
            return
        end

        if not state.last_validate then
            state.status = 'Press VALIDATE ALL SLIPS first.'
            push_log('warn', 'Step 1 first: press VALIDATE ALL SLIPS.')
            layout()
            return
        end

        local files = selected_files_list()
        local result, err = portermod.validate_all_slips(files)
        if not result then
            state.status = tostring(err)
            push_log('err', tostring(err))
            layout()
            return
        end
        state.last_validate = result

        clear_log()

        if #result.items == 0 then
            state.status = 'Retrieve Unused - nothing to move.'
            push_log('ok', 'No unused slip-storable items were found.')
            layout()
            return
        end

        -- Drop anything sitting in Safe / Safe 2 before we group. Those bags
        -- hold placed Mog House furniture, which looks like a normal item but
        -- cannot be moved, so attempting it just stalls the run.
        local retrievable   = {}
        local safe_skipped  = 0
        for _, item in ipairs(result.items) do
            if is_safe_bag(item.bag_id) then
                safe_skipped = safe_skipped + 1
            else
                retrievable[#retrievable+1] = item
            end
        end

        if safe_skipped > 0 then
            push_log('warn', ('Ignoring %d item(s) in Safe / Safe 2.'):format(safe_skipped))
            push_log('warn', '  Those bags hold placed furniture, which cannot be moved.')
            push_log('warn', '  Move anything you do want from there by hand, then retry.')
        end

        if #retrievable == 0 then
            state.status = 'Retrieve Unused - nothing to move.'
            push_log('ok', 'No unused slip-storable items outside Safe / Safe 2.')
            layout()
            return
        end

        local groups, order = {}, {}
        for _, item in ipairs(retrievable) do
            local sid = item.slip_item_id
            if not groups[sid] then
                groups[sid] = { label = item.slip_label, items = {} }
                order[#order+1] = sid
            end
            local g = groups[sid].items
            g[#g+1] = item
        end
        table.sort(order, function(a, b) return groups[a].label < groups[b].label end)

        local free = inventory_free()
        local moves = {}
        local out_of_space = false

        local function plan_group(sid)
            local g = groups[sid]
            local eligible, blocked, in_inv = {}, {}, 0

            for _, item in ipairs(g.items) do
                if item.bag_id == 0 then
                    in_inv = in_inv + 1
                elseif bag_accessible(item.bag_id) then
                    eligible[#eligible+1] = item
                else
                    blocked[#blocked+1] = item
                end
            end

            if #eligible == 0 and in_inv == 0 then
                for _, item in ipairs(blocked) do
                    push_log('warn', ('Skipped %s'):format(item.name))
                    push_log('warn', ('  %s is not reachable from here.'):format(item.bag_name))
                end
                return false
            end

            local slip_move = nil
            if not result.slips_in_inv[sid] then
                local found = portermod.find_slip_slot(sid)
                if not found then
                    push_log('err', ('%s is not in your possession.'):format(g.label))
                    push_log('err', '  Buy it from the Porter Moogle, then retry.')
                    return false
                elseif not bag_accessible(found.bag_id) then
                    push_log('warn', ('%s is in your %s, which you cannot')
                        :format(g.label, found.bag_name))
                    push_log('warn', '  reach from here. Move it, then retry.')
                    return false
                end
                slip_move = found
            end

            local slip_cost = slip_move and 1 or 0
            local need = slip_cost + ((#eligible > 0) and 1 or 0)
            if free < need then
                push_log('warn', ('Not enough inventory room for %s right now.'):format(g.label))
                return false
            end

            if slip_move then
                moves[#moves+1] = {
                    kind = 'slip', name = g.label, item_id = sid,
                    bag_id = slip_move.bag_id, bag_name = slip_move.bag_name,
                    slot = slip_move.slot,
                }
                free = free - 1
            end

            for _, item in ipairs(eligible) do
                if free <= 0 then
                    out_of_space = true
                    break
                end
                moves[#moves+1] = {
                    kind = 'item', name = item.name, item_id = item.item_id,
                    bag_id = item.bag_id, bag_name = item.bag_name,
                    slot = item.slot,
                }
                free = free - 1
            end

            for _, item in ipairs(blocked) do
                push_log('warn', ('Skipped %s'):format(item.name))
                push_log('warn', ('  %s is not reachable from here.'):format(item.bag_name))
            end

            return out_of_space
        end

        for _, sid in ipairs(order) do
            if free <= 0 then
                out_of_space = true
                break
            end
            if plan_group(sid) then break end
        end

        if out_of_space then
            push_log('warn', 'Inventory filled up. Deposit these, then run this again.')
        end

        if #moves == 0 then
            state.status = 'Retrieve Unused - nothing could be moved.'
            push_log('warn', 'Nothing was moved. See the notes above.')
            layout()
            return
        end

        push_log('msg', ('Moving %d thing(s) into inventory...'):format(#moves))
        state.status = 'Retrieving unused items...'
        layout()

        local idx = 1
        local moved_items, moved_slips, skipped_locked = 0, 0, 0

        local function step()
            if idx > #moves then
                push_log('ok', ('Moved %d item(s) and %d slip(s) to inventory.')
                    :format(moved_items, moved_slips))
                if skipped_locked > 0 then
                    push_log('warn', ('%d thing(s) were in use and left alone.'):format(skipped_locked))
                end
                push_log('msg', '')
                push_log('msg', 'Now switch to the DEPOSIT ITEMS tab and press')
                push_log('msg', 'SCAN INVENTORY FOR DEPOSIT, then DEPOSIT.')
                state.status = ('Retrieved %d item(s). Use the DEPOSIT ITEMS tab.')
                    :format(moved_items)
                state.last_validate = nil
                layout()
                return
            end

            local mv = moves[idx]
            idx = idx + 1

            local movable, why = portermod.slot_movable(mv.bag_id, mv.slot, mv.item_id)
            if not movable then
                skipped_locked = skipped_locked + 1
                if why == 'inuse' then
                    push_log('warn', ('Skipped %s'):format(mv.name))
                    push_log('warn', '  In use right now, so it cannot be moved.')
                    push_log('warn', '  Placed furniture must be removed first.')
                else
                    push_log('warn', ('Skipped %s (no longer in %s).'):format(mv.name, mv.bag_name))
                end
                coroutine.schedule(step, 0.2)
                return
            end

            local move_ok, move_err = pcall(windower.ffxi.move_item, mv.bag_id, 0, mv.slot, 1)
            if move_ok then
                if mv.kind == 'slip' then
                    moved_slips = moved_slips + 1
                else
                    moved_items = moved_items + 1
                end
                push_log('msg', ('Moved: %s (from %s)'):format(mv.name, mv.bag_name))
            else
                push_log('err', ('Failed to move %s: %s'):format(mv.name, tostring(move_err)))
            end

            coroutine.schedule(step, 0.6)
        end

        step()
    end

    -- Attach actions
    local action_map = {
        identify       = do_identify,
        retrieve       = do_retrieve,
        retrieve_fill  = do_retrieve_fill,
        retrieve_store = do_retrieve_store,
        check_compat   = do_check_compat,
        deposit_slips  = do_deposit_slips,
        validate_slips = do_validate_slips,
        retrieve_unused= do_retrieve_unused,
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
        state.hover_tab = nil
        state.hover_sw = nil
        if dock.dual() then
            for i, sw in ipairs(SW_DEFS) do
                local x, y, w, h = Rect.dock_tab(i)
                if Rect.point_in(mx, my, x, y, w, h) then
                    state.hover_sw = sw.id
                    return
                end
            end
        end
        if state.collapsed then return end
        for _, def in ipairs(BTN_DEFS) do
            if btn_active(def) then
                local x, y, w, h = Rect.button(def)
                if Rect.point_in(mx, my, x, y, w, h) then
                    state.hover = def.id
                    return
                end
            end
        end
        for i = 1, #TAB_DEFS do
            local x, y, w, h = Rect.tab(i)
            if Rect.point_in(mx, my, x, y, w, h) then
                state.hover_tab = i
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

    local function select_tab(i)
        if state.tab == i then return true end
        state.tab = i
        state.hover = nil
        layout()
        return true
    end

    local function click_dock(mx, my)
        if not dock.dual() then return false end
        for i, sw in ipairs(SW_DEFS) do
            local x, y, w, h = Rect.dock_tab(i)
            if Rect.point_in(mx, my, x, y, w, h) then
                dock.set_active(sw.id)
                return true
            end
        end
        return false
    end

    local function click_buttons(mx, my)
        for _, def in ipairs(BTN_DEFS) do
            if def.toggle or (not state.collapsed and btn_active(def)) then
                local x, y, w, h = Rect.button(def)
                if Rect.point_in(mx, my, x, y, w, h) then
                    if def.action then def.action() end
                    return true
                end
            end
        end

        if state.collapsed then return false end

        for i = 1, #TAB_DEFS do
            local x, y, w, h = Rect.tab(i)
            if Rect.point_in(mx, my, x, y, w, h) then
                return select_tab(i)
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

    -- Per-row priority buttons
    local function click_file_prio(mx, my)
        local lx, ly, lw, lh = Rect.file_list()
        if not Rect.point_in(mx, my, lx, ly, lw, lh) then return false end
        local vis = math.floor((my - ly) / row_h()) + 1
        if vis < 1 or vis > PX.FILE_ROWS then return false end
        local abs = (state.file_scroll or 0) + vis
        if abs < 1 or abs > #state.files then return false end

        local fx, fy, fw, fh = Rect.file_prio_btn(vis, 'fav')
        if Rect.point_in(mx, my, fx, fy, fw, fh) then
            toggle_file_priority(abs, 'fav'); return true
        end
        local rx, ry, rw, rh = Rect.file_prio_btn(vis, 'low')
        if Rect.point_in(mx, my, rx, ry, rw, rh) then
            toggle_file_priority(abs, 'low'); return true
        end
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
        state.last_validate = nil
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
            if click_dock(x, y)         then return true end
            if click_buttons(x, y)      then return true end
            if state.collapsed then
                if begin_drag(x, y) then return true end
                return
            end
            if click_file_prio(x, y)    then return true end
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
        state.last_validate    = nil

        -- Redirect util messages to this panel's log while porter UI is active.
        _saved_ui_logger = util._get_ui_logger and util._get_ui_logger() or nil
        util.set_ui_logger(function(level, s) push_log(level, s) end)

        state.tab = 1
        clear_log()
        push_log('msg', 'Porter Moogle detected nearby.')
        push_log('msg', '')
        push_log('msg', 'Pick a tab above. Each tab has its own steps.')
        push_log('msg', '')
        push_log('ok',  'RETRIEVE ITEMS  (tab 1)')
        push_log('msg', '  Step 1 - Scan Luas for Missing')
        push_log('msg', '    Lists gear your ticked lua(s) need that is')
        push_log('msg', '    currently sitting on a Porter Mog Slip.')
        push_log('msg', '  Step 2 - Pick how to bring it back:')
        push_log('msg', '    Retrieve Missing - to inventory only.')
        push_log('msg', '    RETR+FILL - then into free wardrobe slots.')
        push_log('msg', '    RETR+STORE - then into Satchel/Case/Sack.')
        push_log('msg', '')
        push_log('ok',  'DEPOSIT ITEMS  (tab 2)')
        push_log('msg', '  Step 1 - Scan Inventory for Deposit')
        push_log('msg', '    Lists items a slip will accept.')
        push_log('msg', '  Step 2 - Deposit')
        push_log('msg', '    Stores those items onto their slips.')
        push_log('msg', '')
        push_log('ok',  'VALIDATE SLIPS  (tab 3)')
        push_log('msg', '  Validate All Slips')
        push_log('msg', '    Searches every bag, wardrobe and container you')
        push_log('msg', '    own for gear a slip can hold, then reports')
        push_log('msg', '    which slip takes it and where it is now.')
        push_log('msg', '    Select which lua\'s items not to consider')
        push_log('msg', '    using the list below.')
            push_log('msg', '    Step 1 is a report only; nothing is moved.')
        push_log('msg', '  Step 2 - Retrieve Unused Items and Slips')
        push_log('msg', '    Moves each unused item AND its slip into your')
        push_log('msg', '    inventory, so you can deposit them right away.')
        push_log('msg', '    Satchel, Sack, Case and Wardrobes 1-8 are always')
        push_log('msg', '    reachable; in the Mog Garden every bag is. Step 1')
        push_log('msg', '    marks anything out of reach right now with')
        push_log('msg', '    [inaccessible - skipped].')
        push_log('msg', '    Safe and Safe 2 are never pulled from - they hold')
        push_log('msg', '    placed furniture that cannot be moved. Step 1')
        push_log('msg', '    marks those items [SAFE - skipped]. Slips stored')
        push_log('msg', '    in Safe / Safe 2 are still fetched normally.')
        push_log('msg', '    If an item and its slip will not both fit, it')
        push_log('msg', '    skips that pair and carries on with the rest.')
        push_log('msg', '    Missing slips are named so you can buy them from')
        push_log('msg', '    the Porter Moogle, then retry.')
        push_log('msg', '    Then use the DEPOSIT ITEMS tab to store them.')
        refresh_file_list()
        layout()
    end

    function pui.hide()
        UI.visible = false
        dock.set_available('porter', false)
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

    function pui.is_active() return UI.visible and dock.is_active('porter') end

    dock.register('porter', function() layout() end)

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
        if is_mog_house() and not dock.is_mog_garden() then
            if UI.visible then pui.hide() end
            return
        end

        local npc = portermod.find_porter_npc()
        if npc and not UI.visible then
            pui.show()
        elseif not npc and UI.visible and not portermod.is_busy() then
            pui.hide()
        end
        dock.set_available('porter', UI.visible)
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
