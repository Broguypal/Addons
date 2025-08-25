_addon.name     = 'dbTracker'
_addon.author   = 'Broguypal'
_addon.version  = '1.1'

local texts   = require('texts')
local config  = require('config')
local packets = require('packets')
local res     = require('resources')

local zoning_bool = false

local function member_same_zone(name)
  local party = windower.ffxi.get_party() or {}
  local zone = windower.ffxi.get_info().zone
  for i=0,5 do
    local m = party['p'..i]
    if m and m.name == name then
      return m.zone == zone
    end
  end
  return true -- default permissive if unknown
end

-- Safe tracked list require
local ok_trk, tracked_mod = pcall(require, 'tracked_buffs')
local TRACK  = (ok_trk and type(tracked_mod.TRACK)  == 'table') and tracked_mod.TRACK  or {}
local SEVERE = (ok_trk and type(tracked_mod.SEVERE) == 'table') and tracked_mod.SEVERE or {}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function name_from_id_index(id, idx)
  if id and id ~= 0 then
    local m = windower.ffxi.get_mob_by_id(id)
    if m and m.name then return m.name end
  end
  if idx and idx ~= 0 then
    local m = windower.ffxi.get_mob_by_index(idx)
    if m and m.name then return m.name end
  end
  return '<unknown>'
end

-- Decode uint16 buff array; strip flagged high bytes (0xFF, 0x28)
local function decode_buff_array(raw_or_table)
  if type(raw_or_table) == 'table' then
    return raw_or_table
  elseif type(raw_or_table) == 'string' then
    local ids, seen = {}, {}
    local n = #raw_or_table
    for i = 1, n-1, 2 do
      local lo = raw_or_table:byte(i)
      local hi = raw_or_table:byte(i+1)
      if not (lo == 0 and hi == 0) and not (lo == 0xFF and hi == 0xFF) then
        local id = (hi == 0xFF or hi == 0x28) and lo or (lo + 256*hi)
        if id and id > 0 and not seen[id] then
          seen[id] = true
          ids[#ids+1] = id
        end
      end
    end
    return ids
  end
  return nil
end

-- Caches:
local LAST_CONFIRMED, MEMBER_LAST_SNAPSHOT = {}, {}
_G.MEMBER_JOB = _G.MEMBER_JOB or {}
local MEMBER_JOB = _G.MEMBER_JOB

local function only_tracked_ids(ids)
  if not ids then return {} end
  local out, seen = {}, {}
  for _,id in ipairs(ids) do
    if TRACK[id] and not seen[id] then
      seen[id] = true
      out[#out+1] = id
    end
  end
  return out
end

local function diff_and_commit(name, now_ids)
  local now = {}
  for _,id in ipairs(only_tracked_ids(now_ids or {})) do now[id] = true end
  LAST_CONFIRMED[name] = now
  MEMBER_LAST_SNAPSHOT[name] = os.clock()
end

----------------------------------------------------------------
-- Incoming packets: PartyBuffs logic (snapshots only)
----------------------------------------------------------------
windower.register_event('incoming chunk', function(id, data)
  if id == 0x076 then
    local p = packets.parse('incoming', data); if not p then return end
    local party = windower.ffxi.get_party() or {}
    for slot = 0, 5 do
      local m = party['p'..slot]
      local name
      if m and m.name then
        name = m.name
      else
        local pid  = p[('ID %u'):format(slot)]
        local pidx = p[('Index %u'):format(slot)]
        name = name_from_id_index(pid, pidx)
      end
      local field = ('Buffs %u'):format(slot)
      local raw   = p[field]
      if raw ~= nil and name then
        local ids = decode_buff_array(raw) or {}
        diff_and_commit(name, ids)
      end
    end
    return
  end

  if id == 0x0DD or id == 0x0DF then
    local p = packets.parse('incoming', data); if not p then return end
    local mj_id = p['Main job'] or p['Main Job'] or p['Job'] or p['Main Job ID']
    local name_for_job = p.Name or name_from_id_index(p.ID or p['ID'], p.Index or p['Index'])
    if name_for_job and type(mj_id) == 'number' and res.jobs[mj_id] and res.jobs[mj_id].ens then
      MEMBER_JOB[name_for_job] = res.jobs[mj_id].ens
    end
    local buffs_field = p.Buffs or p.buffs
    if buffs_field ~= nil then
      local ids  = decode_buff_array(buffs_field) or {}
      local name = p.Name or name_from_id_index(p.ID or p['ID'], p.Index or p['Index'])
      if name then diff_and_commit(name, ids) end
    end
    return
  end

  if id == 0x00B then
    zoning_bool = true
    return
  elseif id == 0x00A and zoning_bool then
    zoning_bool = false
    return
  end
end)

windower.register_event('zone change', function()
  LAST_CONFIRMED, MEMBER_LAST_SNAPSHOT = {}, {}
  for k in pairs(MEMBER_JOB) do MEMBER_JOB[k] = nil end
end)

----------------------------------------------------------------
-- Labels
----------------------------------------------------------------
local function labels_for_member(name)
  local labels = {}
  if zoning_bool then return labels end
  if not member_same_zone(name) then return labels end
  local confirmed = LAST_CONFIRMED[name] or {}
  for id,_ in pairs(confirmed) do
    local lbl = TRACK[id]
    if lbl then labels[#labels+1] = lbl end
  end
  table.sort(labels)
  return labels
end

local function p0_labels_from_api()
  local labels = {}
  local player = windower.ffxi.get_player()
  if not player or not player.buffs then return labels end
  for _, id in ipairs(player.buffs) do
    if id and id ~= 0 and id ~= 255 then
      local lbl = TRACK[id]
      if lbl then labels[#labels+1] = lbl end
    end
  end
  table.sort(labels)
  return labels
end

-- === Role colors and job mapping ===
local ROLE_COLORS = {
    tank       = {r=100, g=160, b=255},  -- blue
    healer     = {r=60,  g=220, b=120},  -- green
    pure_dd    = {r=170, g=120, b=70 },  -- brown
    hybrid     = {r=255, g=165, b=0  },  -- orange
    mag_dps    = {r=120, g=80,  b=160},  -- darkish purple
    support    = {r=255, g=255, b=100},  -- yellow
}

local JOB_ROLE = {
    -- Tanks
    RUN='tank', PLD='tank',

    -- Healers
    WHM='healer',

    -- Pure DD
    WAR='pure_dd', MNK='pure_dd', DRG='pure_dd', RNG='pure_dd',
    SAM='pure_dd', DRK='pure_dd', THF='pure_dd', DNC='pure_dd',

    -- Hybrid
    BST='hybrid', PUP='hybrid', RDM='hybrid', BLU='hybrid', NIN='hybrid',

    -- Magic DPS
    BLM='mag_dps', SCH='mag_dps', SMN='mag_dps',

    -- Support
    GEO='support', COR='support', BRD='support',
}

local function resolve_job_tag(name)
  if not name then return nil end
  if MEMBER_JOB[name] then return MEMBER_JOB[name] end
  local pt = windower.ffxi.get_party() or {}
  for i=0,5 do
    local m = pt['p'..i]
    if m and m.name == name then
      if m.main_job and res.jobs[m.main_job] then
        MEMBER_JOB[name] = res.jobs[m.main_job].ens
        return MEMBER_JOB[name]
      end
    end
  end
  local player = windower.ffxi.get_player()
  if player and player.name == name and player.main_job and res.jobs[player.main_job] then
    MEMBER_JOB[name] = res.jobs[player.main_job].ens
    return MEMBER_JOB[name]
  end
  return nil
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local defaults = {
  pos = {x=100, y=200},
  locked = false,
  font = 'Arial',
  size = 10,
  line_height = 18,
  header_height = 22,
  width = 520,
}
local settings = config.load(defaults)

local GREY   = {r=120, g=120, b=120}
local WHITE  = {r=255, g=255, b=255}
local ORANGE = {r=255, g=160, b=60}
local RED 	 = {r=255, g=80, b=80} 
local STROKE = {r=0, g=0, b=0, a=220, w=2}

local COL_P_PX    = 26
local NAME_XPAD   = 1
local COL_NAME_PX = 110

local ui = { header=nil, rows={}, }
local last_rows = nil
local last_sig = ''
local drag_state = { x = settings.pos.x, y = settings.pos.y }

local function make_text(x, y, size, color, bold)
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

local function colorize_labels(labels, severe_rgb)
  severe_rgb = severe_rgb or RED 
  local parts = {}
  for _, lbl in ipairs(labels) do
    if SEVERE[lbl] then
      -- Inline color for just this label; reset with \cr
      parts[#parts+1] = ('\\cs(%d,%d,%d)%s\\cr'):format(severe_rgb.r, severe_rgb.g, severe_rgb.b, lbl)
    else
      parts[#parts+1] = lbl
    end
  end
  return table.concat(parts, ', ')
end

local function collect_rows()
  local rows = {}
  local pt = windower.ffxi.get_party() or {}
  local player = windower.ffxi.get_player()
  local self_name = player and player.name or nil

  for slot=0,5 do
    local m = pt['p'..slot]
    if m and m.name then
      local debuffs = (self_name and m.name == self_name) and p0_labels_from_api() or labels_for_member(m.name)
      local job_tag = resolve_job_tag(m.name)
      rows[#rows+1] = { slot=slot, name=m.name, debuffs=debuffs, job=job_tag }
    end
  end

  if #rows == 0 and self_name then
    local solo_job = resolve_job_tag(self_name)
    rows[#rows+1] = { slot=0, name=self_name, debuffs=p0_labels_from_api(), job=solo_job }
  end

  table.sort(rows, function(a,b) return a.slot < b.slot end)
  return rows
end

local function render_rows(rows)
  local x, y     = settings.pos.x, settings.pos.y
  local header_h = settings.header_height
  local line_h   = settings.line_height

  ui.header:pos(x, y)
  ui.header:text('dbTracker')
  ui.header:visible(true)

  for i=1,6 do
    local row = rows[i]
    local base_y = y + header_h + (i-1)*line_h
    local widgets = ui.rows[i]

    if not widgets then
      widgets = {
        p    = make_text(x, base_y, settings.size, GREY,   false),
        name = make_text(x+COL_P_PX+NAME_XPAD, base_y, settings.size, WHITE,  false),
        debs = make_text(x+COL_P_PX+COL_NAME_PX, base_y, settings.size, WHITE, false),
      }
      ui.rows[i] = widgets
    end

    if row then
		widgets.p:pos(x, base_y); widgets.p:text(('P%d'):format(row.slot)); widgets.p:visible(true)
		widgets.name:pos(x+COL_P_PX+NAME_XPAD, base_y); widgets.name:text(row.name)
		local role = row.job and JOB_ROLE[row.job] or nil
		local col = (role and ROLE_COLORS[role]) or WHITE
		widgets.name:color(col.r, col.g, col.b)
		widgets.name:visible(true)

		local s = colorize_labels(row.debuffs, RED)  -- or ORANGE
		widgets.debs:pos(x+COL_P_PX+COL_NAME_PX, base_y)
		widgets.debs:text(s)
		widgets.debs:color(WHITE.r, WHITE.g, WHITE.b)  -- base color stays neutral
		widgets.debs:visible(true)
    else
      widgets.p:visible(false); widgets.name:visible(false); widgets.debs:visible(false)
    end
  end
end

local function sig(rows)
  local parts = {}
  for _,r in ipairs(rows) do parts[#parts+1] = r.slot..'|'..r.name..'|'..(r.job or '')..'|'..table.concat(r.debuffs,';') end
  return table.concat(parts,'||')
end

local function update_ui()
  local rows = collect_rows()
  local s = sig(rows)
  if s ~= last_sig or not last_rows then
    render_rows(rows)
    last_sig = s
    last_rows = rows
  end
end

windower.register_event('prerender', function()
  update_ui()
  if ui and ui.header then
    local hx = ui.header:pos_x()
    local hy = ui.header:pos_y()
    if hx ~= drag_state.x or hy ~= drag_state.y then
      settings.pos.x, settings.pos.y = hx, hy
      drag_state.x, drag_state.y = hx, hy
      if last_rows then render_rows(last_rows) end
      config.save(settings)
    end
  end
end)

windower.register_event('load', function()
    if ui.header then return end -- prevent double init if load fires twice
    ui.header = make_text(settings.pos.x, settings.pos.y, settings.size+1, GREY, true)
    ui.header:draggable(true)
    ui.header:visible(true)
    update_ui()

    -- Seed your own job into MEMBER_JOB so color shows right away
    local player = windower.ffxi.get_player()
    if player and player.name then
        local mj = player.main_job_id or player.main_job or player.job_id or player.Job
        if type(mj) == 'number' and res.jobs[mj] and res.jobs[mj].ens then
            MEMBER_JOB[player.name] = res.jobs[mj].ens
        elseif type(mj) == 'string' then
            MEMBER_JOB[player.name] = mj
        end
    end
end)