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

_addon.name = 'wardrobe9'
_addon.author = 'Broguypal'
_addon.version = '1.1'

local res = require('resources')
local extdata = require('extdata')

-- Addon path + scan cache file
local ADDON_PATH = windower.addon_path or (_addon and _addon.path) or 'addons/wardrobe9/'
local SCAN_FILE  = ADDON_PATH .. 'scan_cache.lua'

local function load_local(modfile)
    return dofile(ADDON_PATH .. modfile)
end

local config   = load_local('w9_config.lua')
local util     = load_local('w9_util.lua')(config)
local slots    = load_local('w9_slots.lua')(res)
local bags     = load_local('w9_bags.lua')(res, util, config)
local scan     = load_local('w9_scan.lua')(res, extdata, util, slots, ADDON_PATH, SCAN_FILE)
local planner  = load_local('w9_planner.lua')(res, util, config, slots, bags, scan)
local execmod  = load_local('w9_executor.lua')(res, extdata, util)
local mousemod = load_local('w9_mouse.lua')
local ui       = load_local('w9_ui.lua')(res, util, config, scan, planner, execmod, mousemod)
