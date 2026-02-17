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


return function(ctx)
    local M = {}

    local state   = ctx.state
    local UI      = ctx.UI
    local PX      = ctx.PX
    local Rect    = ctx.Rect
    local util    = ctx.util
    local layout  = ctx.layout
    local row_h   = ctx.row_h
    local max_file_scroll          = ctx.max_file_scroll
    local max_log_scroll           = ctx.max_log_scroll
    local ensure_file_scroll_valid = ctx.ensure_file_scroll_valid
    local ensure_log_scroll_valid  = ctx.ensure_log_scroll_valid
    local ensure_selection_visible = ctx.ensure_selection_visible
    local do_scan  = ctx.do_scan
    local do_plan  = ctx.do_plan
    local do_exec  = ctx.do_exec
    local SB_HIT_PAD_X = ctx.SB_HIT_PAD_X
    local SB_HIT_PAD_Y = ctx.SB_HIT_PAD_Y

    -- ======================================================
    -- Hover
    -- ======================================================

    local function update_hover(mx, my)
        state.hover = nil
        local checks = {
            {'scan',         Rect.btn,            'scan'},
            {'plan',         Rect.btn,            'plan'},
            {'exec',         Rect.btn,            'exec'},
            {'file_sb_up',   Rect.file_sb_upbtn},
            {'file_sb_down', Rect.file_sb_downbtn},
            {'log_sb_up',    Rect.log_sb_upbtn},
            {'log_sb_down',  Rect.log_sb_downbtn},
        }
        for _, c in ipairs(checks) do
            local x, y, w, h
            if c[3] then
                x, y, w, h = c[2](c[3])
            else
                x, y, w, h = c[2]()
            end
            if Rect.point_in(mx, my, x, y, w, h) then
                state.hover = c[1]
                return
            end
        end
    end

    -- ======================================================
    -- Scrolling
    -- ======================================================

    local function scroll_file_by(rows)
        rows = tonumber(rows) or 0
        if rows == 0 then return false end
        state.file_scroll = (state.file_scroll or 0) + rows
        ensure_file_scroll_valid()
        layout()
        return true
    end

    local function scroll_log_by(rows)
        rows = tonumber(rows) or 0
        if rows == 0 then return false end
        state.log_scroll = (state.log_scroll or 0) + rows
        ensure_log_scroll_valid()
        layout()
        return true
    end

    -- ======================================================
    -- Button / file-list clicks
    -- ======================================================

    local function click_buttons(mx, my)
        local x, y, w, h = Rect.btn('scan')
        if Rect.point_in(mx, my, x, y, w, h) then do_scan(); return true end

        x, y, w, h = Rect.btn('plan')
        if Rect.point_in(mx, my, x, y, w, h) then do_plan(); return true end

        x, y, w, h = Rect.btn('exec')
        if Rect.point_in(mx, my, x, y, w, h) then do_exec(); return true end

        -- Scrollbar arrow buttons
        x, y, w, h = Rect.file_sb_upbtn()
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
        if abs >= 1 and abs <= #state.files then
            state.selected_index = abs
            ensure_selection_visible()
            state.status = ('Selected: %s'):format(state.files[abs].label)
            layout()
            return true
        end
        return false
    end

    -- ======================================================
    -- Header drag (panel move)
    -- ======================================================

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
        if state.dragging then
            state.dragging = false
            return true
        end
        return false
    end

    -- ======================================================
    -- File scrollbar drag
    -- ======================================================

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
                local rel = util.clamp((my - ty) - (thumb_h / 2), 0, maxy)
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

    local function end_file_sb_drag()
        state.file_sb_dragging = false
    end

    -- ======================================================
    -- Log scrollbar drag
    -- ======================================================

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
                local rel = util.clamp((my - ty) - (thumb_h / 2), 0, maxy)
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

    local function end_log_sb_drag()
        state.log_sb_dragging = false
    end

    -- ======================================================
    -- Main mouse dispatcher
    -- ======================================================

    function M.on_mouse(type, x, y, delta, blocked)
        if not UI.visible then return end

        update_hover(x, y)

        -- type 0: move
        if type == 0 then
            if state.dragging          then drag_move(x, y);          return true end
            if state.file_sb_dragging  then file_sb_drag_move(x, y);  return true end
            if state.log_sb_dragging   then log_sb_drag_move(x, y);   return true end
            layout()
            return
        end

        -- type 1: left down
        if type == 1 then
            if click_buttons(x, y)        then return true end
            if click_file_list(x, y)      then return true end
            if begin_drag(x, y)           then return true end
            if begin_file_sb_drag(x, y)   then return true end
            if begin_log_sb_drag(x, y)    then return true end
        end

        -- type 2: left up
        if type == 2 then
            if end_drag() then return true end
            end_file_sb_drag()
            end_log_sb_drag()
            layout()
            return
        end
    end

    return M
end
