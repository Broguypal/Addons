-- License: BSD 3-Clause (see bottom of file)
-- Copyright (c) 2026 Broguypal

_addon.name     = 'dbTracker'
_addon.author   = 'Broguypal'
_addon.version  = '1.5'

local texts   = require('texts')
local config  = require('config')
local packets = require('packets')
local res     = require('resources')

------------------------------------------------------------
-- State
------------------------------------------------------------
local zoning_bool = false
local LAST_CONFIRMED = {}      -- name -> {buff_id1, buff_id2, ...}
local MEMBER_JOB    = {}       -- name -> 'WAR', 'WHM', ... (short code)

------------------------------------------------------------
-- tracked_buffs (safe require)
-- Expect: return { TRACK = { [id]=label, ... }, SEVERE = { [label]=true, ... } }
------------------------------------------------------------
local ok_trk, tracked_mod = pcall(require, 'tracked_buffs')
local TRACK  = (ok_trk and type(tracked_mod.TRACK)  == 'table') and tracked_mod.TRACK  or {}
local SEVERE = (ok_trk and type(tracked_mod.SEVERE) == 'table') and tracked_mod.SEVERE or {}
local NA = (ok_trk and type(tracked_mod.NA) == 'table') and tracked_mod.NA or {}

------------------------------------------------------------
-- Member tracking helpers
------------------------------------------------------------
local member_table = { _names = {}, _ids = {} }
function member_table:contains(name)
    for i = 1, #self._names do
        if self._names[i] == name then return true end
    end
    return false
end
function member_table:append(name)
    self._names[#self._names+1] = name
end
setmetatable(member_table, {
    __index = function(t, k) return rawget(t._ids, k) end,
    __newindex = function(t, k, v) rawset(t._ids, k, v) end,
})

local _id_to_name = {}
local function _name_from_id(id)
    if id and id ~= 0 then
        local nm = _id_to_name[id]
        if nm then return nm end
        local m = windower.ffxi.get_mob_by_id(id)
        if m and m.name then
            _id_to_name[id] = m.name
            return m.name
        end
    end
    return nil
end

local function is_player_ready()
  local info = windower.ffxi.get_info()
  if not (info and info.logged_in) then return false end
  local p = windower.ffxi.get_player()
  return (p and p.name and p.id) ~= nil
end

------------------------------------------------------------
-- Parsing
------------------------------------------------------------
local function parse_buffs(data)
    local party = windower.ffxi.get_party() or {}
    for k = 0, 4 do
        local base = k*48 + 5
        local pid  = data:unpack('I', base)
        if pid ~= 0 then
            local m = party['p'..(k+1)]
            local name = (m and m.name) or _name_from_id(pid) or ('<'..tostring(pid)..'>')
            if name and name ~= '' then
                local ids = {}
                for i = 1, 32 do
                    local low = data:byte(base + 16 + (i-1)) or 0
                    local hix = data:byte(base + 8  + math.floor((i-1)/4)) or 0
                    local hi2 = math.floor(hix / 4^((i-1)%4)) % 4
                    local idv = low + 256*hi2
                    ids[#ids+1] = idv
                end
                LAST_CONFIRMED[name] = ids
            end
        end
    end
	buff_sort()
end

------------------------------------------------------------
-- Role colors + jobs
------------------------------------------------------------
local ROLE_COLORS = {
    tank       = {r=100, g=160, b=255},  -- blue
    healer     = {r=60,  g=220, b=120},  -- green
    pure_dd    = {r=170, g=120, b=70 },  -- brown
    hybrid     = {r=255, g=165, b=0  },  -- orange
    mag_dps    = {r=120, g=80,  b=160},  -- purple
    support    = {r=255, g=255, b=100},  -- yellow
    default    = {r=200, g=200, b=200},  -- fallback grey
}

local JOB_ROLE = {
    RUN='tank', PLD='tank',
    WHM='healer',
    WAR='pure_dd', MNK='pure_dd', DRG='pure_dd', RNG='pure_dd', SAM='pure_dd', DRK='pure_dd', THF='pure_dd', DNC='pure_dd',
    BST='hybrid', PUP='hybrid', RDM='hybrid', BLU='hybrid', NIN='hybrid',
    BLM='mag_dps', SCH='mag_dps', SMN='mag_dps',
    GEO='support', COR='support', BRD='support',
}

local function job_to_role(job)
  return JOB_ROLE[job or ''] or 'default'
end

local function name_color(name)
  local job = MEMBER_JOB[name]
  local role = job_to_role(job)
  return ROLE_COLORS[role] or ROLE_COLORS.default
end

------------------------------------------------------------
-- UI
------------------------------------------------------------
local settings = config.load({
  pos   = {x=920, y=360},
  font  = 'Consolas',
  size  = 10,
  p0_on_top = true,
})

local ROW_H  = settings.size + 6
local PAD_X  = 10
local COL_NAME_PX = 140

local STROKE = { w=1.7, a=180, r=0,g=0,b=0 }
local GREY   = {r=200, g=200, b=200}
local RED    = {r=230, g=90,  b=90}
local YELLOW = {r=255, g=230, b=90}


local ui = { header=nil, rows={} }
local drag_state = { x = settings.pos.x, y = settings.pos.y }
local __last_header_x, __last_header_y = drag_state.x, drag_state.y
local __last_move_at = 0
local __drag_settle_time = 0.25

local function make_text(x, y, size, color, bold)
  color = color or ROLE_COLORS.default
  local t = texts.new('', {
    pos  = {x = x, y = y},
    text = {
      font  = settings.font,
      size  = size,
      alpha = 255,
      red   = color.r, green = color.g, blue = color.b,
      stroke = { width = STROKE.w, alpha = STROKE.a, red=STROKE.r, green=STROKE.g, blue=STROKE.b }
    },
    bg   = {visible=false},
    flags= {draggable=false, bold=bold or false},
  })
  return t
end

-- Safe color apply (prevents nil alpha errors)
local function set_text_rgb(t, rgb)
  if not t or not rgb then return end
  local r = tonumber(rgb.r) or 255
  local g = tonumber(rgb.g) or 255
  local b = tonumber(rgb.b) or 255
  t:color(r, g, b, 255)
end

local function colorize_labels(labels, severe_rgb)
  severe_rgb = severe_rgb or RED
  local out = {}
  for _, lbl in ipairs(labels) do
    if SEVERE[lbl] then
      out[#out+1] = ('\\cs(%d,%d,%d)%s\\cr'):format(severe_rgb.r, severe_rgb.g, severe_rgb.b, lbl)
    else
      out[#out+1] = lbl
    end
  end
  return table.concat(out, ' ')
end

local function wrap_color(lbl, rgb)
  return ('\\cs(%d,%d,%d)%s\\cr'):format(rgb.r, rgb.g, rgb.b, lbl)
end

local function split_labels_by_priority(labels)
  local severe, na, normal = {}, {}, {}

  for _, lbl in ipairs(labels) do
    if SEVERE[lbl] then
      severe[#severe+1] = lbl
    elseif NA[lbl] then
      na[#na+1] = lbl
    else
      normal[#normal+1] = lbl
    end
  end

  table.sort(severe)
  table.sort(na)
  table.sort(normal)

  return severe, na, normal
end


-- Formats the debuff line so NA debuffs are displayed separately in yellow
local function format_debuff_line(labels)
  local severe, na, normal = split_labels_by_priority(labels)

  local parts = {}

  -- SEVERE first (red)
  if #severe > 0 then
    parts[#parts+1] = colorize_labels(severe)
  end

-- NA second (yellow, no prefix)
  if #na > 0 then
    local na_colored = {}
    for _, lbl in ipairs(na) do
      na_colored[#na_colored+1] = wrap_color(lbl, YELLOW)
    end
    parts[#parts+1] = table.concat(na_colored, ' ')
  end


  -- Normal last
  if #normal > 0 then
    parts[#parts+1] = table.concat(normal, ' ')
  end

  return table.concat(parts, '  |  ')
end


-- Whitelist: only render labels for buff IDs present in TRACK
local function labels_for_name(name)
  local ids = LAST_CONFIRMED[name]
  if not ids then return {} end
  local out = {}
  for _, id in ipairs(ids) do
    if id and id ~= 0 and id ~= 255 then
      local label = TRACK[id]
      if label then
        out[#out+1] = label
      end
    end
  end
  table.sort(out)
  return out
end

-- P0 uses API (0x076 does not include self)
local function p0_labels_from_api()
  local labels = {}
  local player = windower.ffxi.get_player()
  if not (player and player.buffs) then return labels end
  for _, id in ipairs(player.buffs) do
    if id and id ~= 0 and id ~= 255 then
      local lbl = TRACK[id]
      if lbl then labels[#labels+1] = lbl end
    end
  end
  table.sort(labels)
  return labels
end

-- compute rows
local function compute_rows()
  local names = {}
  local party = windower.ffxi.get_party() or {}
  local player = windower.ffxi.get_player()

  if player and player.name and settings.p0_on_top then
    names[#names+1] = player.name
  end
  for i=1,5 do
    local m = party['p'..i]
    if m and m.name then
      names[#names+1] = m.name
      -- keep job cache fresh
      if type(m.main_job) == 'string' then
        MEMBER_JOB[m.name] = m.main_job:upper()
      elseif type(m.main_job_id) == 'number' and res.jobs[m.main_job_id] then
        local short = res.jobs[m.main_job_id].ens or res.jobs[m.main_job_id].english_short or res.jobs[m.main_job_id].name
        if type(short) == 'string' then MEMBER_JOB[m.name] = short:upper() end
      end
    end
  end
  if player and player.name and not settings.p0_on_top then
    table.insert(names, 1, player.name)
  end

  -- also keep player's job fresh
  if player and player.name then
    if type(player.main_job) == 'string' then
      MEMBER_JOB[player.name] = player.main_job:upper()
    elseif type(player.main_job_id) == 'number' and res.jobs[player.main_job_id] then
      local short = res.jobs[player.main_job_id].ens or res.jobs[player.main_job_id].english_short or res.jobs[player.main_job_id].name
      if type(short) == 'string' then MEMBER_JOB[player.name] = short:upper() end
    end
  end

  local rows = {}
  for _, name in ipairs(names) do
    local labels = (player and player.name == name) and p0_labels_from_api() or labels_for_name(name)
    rows[#rows+1] = { name = name, labels = labels }
  end
  return rows
end

-- Job refresh helper + timer
local __job_refresh_last = 0
local function refresh_jobs()
  local changed = false
  local player = windower.ffxi.get_player()
  if player and player.name then
    local before = MEMBER_JOB[player.name]
    if type(player.main_job) == 'string' then
      MEMBER_JOB[player.name] = player.main_job:upper()
    elseif type(player.main_job_id) == 'number' and res.jobs[player.main_job_id] then
      local short = res.jobs[player.main_job_id].ens or res.jobs[player.main_job_id].english_short or res.jobs[player.main_job_id].name
      if type(short) == 'string' then MEMBER_JOB[player.name] = short:upper() end
    end
    changed = changed or (before ~= MEMBER_JOB[player.name])
  end
  local party = windower.ffxi.get_party() or {}
  for i=1,5 do
    local m = party['p'..i]
    if m and m.name then
      local before = MEMBER_JOB[m.name]
      if type(m.main_job) == 'string' then
        MEMBER_JOB[m.name] = m.main_job:upper()
      elseif type(m.main_job_id) == 'number' and res.jobs[m.main_job_id] then
        local short = res.jobs[m.main_job_id].ens or res.jobs[m.main_job_id].english_short or res.jobs[m.main_job_id].name
        if type(short) == 'string' then MEMBER_JOB[m.name] = short:upper() end
      end
      if before ~= MEMBER_JOB[m.name] then changed = true end
    end
  end
  if changed then
    update_ui()
  end
end

-- UI update
function update_ui()
  if not is_player_ready() then return end
  if not ui.header then
    ui.header = make_text(drag_state.x, drag_state.y, settings.size+1, GREY, true)
    ui.header:text('dbTracker')
    ui.header:draggable(true)
    ui.header:visible(true)
  end

  local rows = compute_rows()

  -- ensure we have text objects for rows
  for i=1, math.max(#rows, #ui.rows) do
    if rows[i] and not ui.rows[i] then
      local y = drag_state.y + i*ROW_H
      local t_name = make_text(drag_state.x + PAD_X, y, settings.size, GREY, true)
      local t_buffs= make_text(drag_state.x + PAD_X + COL_NAME_PX, y, settings.size, GREY, false)
      t_name:visible(true); t_buffs:visible(true)
      ui.rows[i] = { name=t_name, buffs=t_buffs }
    elseif ui.rows[i] and not rows[i] then
      ui.rows[i].name:visible(false); ui.rows[i].buffs:visible(false)
      ui.rows[i] = nil
    end
  end

  -- update content/colors
	for i,r in ipairs(rows) do
		local label = ("%d. %s"):format(i, r.name)
		ui.rows[i].name:text(label)
		set_text_rgb(ui.rows[i].name, name_color(r.name))
		ui.rows[i].buffs:text(format_debuff_line(r.labels))
	end
end

-- Pull a short job code (e.g. "WAR") from a 0x0DD packet
local function set_member_job_from_dd(packet)
    if not packet or type(packet) ~= 'table' then return end
    local name = packet['Name']
    if not name or name == '' then return end

    -- Try all common keys the Windower packet may use
    local num = packet['Job'] or packet['Main job'] or packet['Main Job']
                 or packet['Main Job ID'] or packet['MJob'] or packet['MainJob']
    local str = packet['main_job'] or packet['mjob'] or packet['job'] or packet['Job Abbr']

    if type(num) == 'number' and num > 0 and res.jobs[num] then
        local short = res.jobs[num].ens or res.jobs[num].english_short or res.jobs[num].name
        if type(short) == 'string' and #short > 0 then
            MEMBER_JOB[name] = short:upper()
            return
        end
    end

    if type(str) == 'string' and #str > 0 then
        MEMBER_JOB[name] = str:upper()
    end
end

------------------------------------------------------------
-- Incoming chunk handling 
------------------------------------------------------------
windower.register_event('incoming chunk', function(id, data)
  if id == 0x0DD then
    local packet = packets.parse('incoming', data)
    if packet and packet['Name'] then
      if not member_table:contains(packet['Name']) then
        member_table:append(packet['Name'])
        member_table[packet['Name']] = packet['ID']
      else
        member_table[packet['Name']] = packet['ID']
      end
      if packet['ID'] and packet['ID'] ~= 0 then
        _id_to_name[packet['ID']] = packet['Name']
      end
	   set_member_job_from_dd(packet)
    end
    coroutine.schedule(buff_sort, 0.5)
  end

  if id == 0x076 then
    parse_buffs(data)
  end

  if id == 0x0B then
    zoning_bool = true
    buff_sort()
  elseif id == 0x0A and zoning_bool then
    zoning_bool = false
    coroutine.schedule(buff_sort, 10)
  end
end)

------------------------------------------------------------
-- Events for P0 buffs and job changes / heartbeat for party job changes
------------------------------------------------------------
windower.register_event('gain buff', function()
  buff_sort()
end)

windower.register_event('lose buff', function()
  buff_sort()
end)

windower.register_event('job change', function()
  refresh_jobs()
end)

windower.register_event('prerender', function()
  local now = os.clock()
  if now - __job_refresh_last > 0.1 then
    __job_refresh_last = now
    refresh_jobs()
  end

  -- NEW: keep rows anchored to the header while dragging, and persist after it settles
  if ui.header then
    local hx, hy = ui.header:pos()
    if hx ~= __last_header_x or hy ~= __last_header_y then
      -- header moved: follow it
      __last_header_x, __last_header_y = hx, hy
      __last_move_at = now
      drag_state.x, drag_state.y = hx, hy

      for i, row in ipairs(ui.rows) do
        if row and row.name and row.buffs then
          local yy = hy + i * ROW_H
          row.name:pos(hx + PAD_X, yy)
          row.buffs:pos(hx + PAD_X + COL_NAME_PX, yy)
        end
      end
    elseif __last_move_at > 0 and (now - __last_move_at) >= __drag_settle_time then
      -- save once after movement stops
      __last_move_at = 0
      if settings.pos.x ~= drag_state.x or settings.pos.y ~= drag_state.y then
        settings.pos.x, settings.pos.y = drag_state.x, drag_state.y
        config.save(settings)
      end
    end
  end
end)


------------------------------------------------------------
-- buff_sort
------------------------------------------------------------
function buff_sort()
  refresh_jobs()
  update_ui()
end

------------------------------------------------------------
-- Load / zone events
------------------------------------------------------------
windower.register_event('load', function() -- Create member table if addon loads while already in PT
	if not windower.ffxi.get_info().logged_in then return end
	drag_state.x, drag_state.y = settings.pos.x, settings.pos.y
	
	if not is_player_ready() then
    -- try again when ready: hydrate buffs if cached; otherwise just paint
    coroutine.schedule(function()
      if is_player_ready() then
        local data = windower.packets.last_incoming(0x076)
        if data then parse_buffs(data) else buff_sort() end
      end
    end, 0.15)
    coroutine.schedule(function()
      if is_player_ready() then buff_sort() end
    end, 0.50)
    return
  end
	
    local party  = windower.ffxi.get_party() or {}
    -- Seed member_table and jobs for p1..p5
    for i = 1, 5 do
        local m = party['p'..i]
        if m and m.mob and not m.mob.is_npc and m.name then
            if not member_table:contains(m.name) then
                member_table:append(m.name)
            end
            member_table[m.name] = m.mob.id
            -- seed job from whatever the party API has now
            if type(m.main_job) == 'string' then
                MEMBER_JOB[m.name] = m.main_job:upper()
            elseif type(m.main_job_id) == 'number' and res.jobs[m.main_job_id] then
                local short = res.jobs[m.main_job_id].ens or res.jobs[m.main_job_id].english_short or res.jobs[m.main_job_id].name
                if type(short) == 'string' then
                    MEMBER_JOB[m.name] = short:upper()
                end
            end
        end
    end

    -- Seed your own job too
    local player = windower.ffxi.get_player()
    if player and player.name then
        if type(player.main_job) == 'string' then
            MEMBER_JOB[player.name] = player.main_job:upper()
        elseif type(player.main_job_id) == 'number' and res.jobs[player.main_job_id] then
            local short = res.jobs[player.main_job_id].ens or res.jobs[player.main_job_id].english_short or res.jobs[player.main_job_id].name
            if type(short) == 'string' then
                MEMBER_JOB[player.name] = short:upper()
            end
        end
    end

    -- Hydrate buffs from the most recent 0x076 if Windower has one cached
    local data = windower.packets.last_incoming(0x076)
    if data then
        parse_buffs(data)      
    else
        buff_sort()            
    end

    -- Tiny follow-up repaint so colors catch late job fields
    coroutine.schedule(buff_sort, 0.5)
end)

windower.register_event('login', function()
  drag_state.x, drag_state.y = settings.pos.x, settings.pos.y
  coroutine.schedule(buff_sort, 0.10)
  coroutine.schedule(buff_sort, 0.50)
end)

windower.register_event('zone change', function()
  LAST_CONFIRMED = {}
end)

--[[
BSD 3-Clause License

Copyright (c) 2026 Broguypal
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of Broguypal nor the names of its contributors may be used
   to endorse or promote products derived from this software without specific
   prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]