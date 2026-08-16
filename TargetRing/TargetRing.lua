_addon.name = 'TargetRing'
_addon.author = 'Broguypal'
_addon.version = '1.0.0'
_addon.commands = {'tring', 'targetring'}

local plugin_name = 'TargetRing'
local plugin_file = plugin_name .. '.dll'

local state_dir = windower.windower_path .. 'plugins/settings/TargetRing'
windower.create_dir(state_dir)

local state_file = state_dir .. '/target.json'
local marker_file = state_dir .. '/plugin.active'
local stamp_file = state_dir .. '/installed_version'
local plugin_dir = windower.windower_path .. 'plugins/'
local installed_dll = plugin_dir .. plugin_file

local subtarget_modes = {'st', 'stpc', 'stnpc', 'stpt', 'stal'}

local previous = ''
local checked = false
local check_at = 0
local copy_at = 0

local function chat(color, message)
    windower.add_to_chat(color, 'TargetRing: ' .. message)
end

local function addon_dir()
    local base = windower.addon_path
    if not base or base == '' then
        base = windower.windower_path .. 'addons/' .. _addon.name .. '/'
    end

    local last = base:sub(-1)
    if last ~= '/' and last ~= '\\' then
        base = base .. '/'
    end

    return base
end

local bundled_dll = addon_dir() .. 'plugins/' .. plugin_file

local function file_exists(path)
    local handle = io.open(path, 'rb')
    if not handle then
        return false
    end

    handle:close()
    return true
end

local function read_stamp()
    local handle = io.open(stamp_file, 'r')
    if not handle then
        return nil
    end

    local value = handle:read('*l')
    handle:close()
    return value
end

local function write_stamp(value)
    local handle = io.open(stamp_file, 'w')
    if handle then
        handle:write(value)
        handle:close()
    end
end

local function copy_plugin()
    local input = io.open(bundled_dll, 'rb')
    if not input then
        return false, 'the bundled DLL is missing from the addon folder'
    end

    local data = input:read('*a')
    input:close()

    if not data or #data == 0 then
        return false, 'the bundled DLL could not be read'
    end

    local output = io.open(installed_dll, 'wb')
    if not output then
        return false, 'plugins\\' .. plugin_file .. ' could not be written (in use, or no permission)'
    end

    output:write(data)
    output:close()

    write_stamp(_addon.version)
    return true
end

local function manual_install_help(reason)
    chat(167, 'Could not install the plugin: ' .. reason .. '.')
    chat(167, 'Copy  addons\\TargetRing\\plugins\\' .. plugin_file .. '  to  plugins\\' .. plugin_file .. '  by hand,')
    chat(167, 'then type  //lua reload TargetRing')
end

local function ensure_plugin()
    local present = file_exists(installed_dll)
    local bundled = file_exists(bundled_dll)

    if not bundled then
        windower.send_command('wait 1; load ' .. plugin_name)
        return
    end

    if present and read_stamp() == _addon.version then
        windower.send_command('wait 1; load ' .. plugin_name)
        return
    end

    if not present then
        local ok, reason = copy_plugin()
        if ok then
            chat(207, 'Installed ' .. plugin_file .. ' into your plugins folder.')
            windower.send_command('wait 1; load ' .. plugin_name)
        else
            manual_install_help(reason)
        end
        return
    end

    chat(207, 'Updating ' .. plugin_file .. ' to ' .. _addon.version .. '...')
    windower.send_command('unload ' .. plugin_name)
    copy_at = os.clock() + 2
end

local function finish_update()
    local ok, reason = copy_plugin()
    if ok then
        chat(207, 'Plugin updated.')
        windower.send_command('wait 1; load ' .. plugin_name)
    else
        manual_install_help(reason)
    end
end

local function plugin_running()
    local handle = io.open(marker_file, 'r')
    if not handle then
        return false
    end

    handle:close()
    return true
end

local function lookup(kind)
    local ok, mob = pcall(windower.ffxi.get_mob_by_target, kind)
    if not ok or not mob or not mob.index or not mob.id or mob.id == 0 then
        return nil
    end

    return mob
end

local function is_hostile(mob)
    if not mob or not mob.is_npc then
        return false
    end

    if mob.in_party or mob.in_alliance or mob.charmed then
        return false
    end

    if (tonumber(mob.spawn_type) or 0) == 16 then
        return true
    end

    return mob.claim_id ~= nil and mob.claim_id ~= 0
end

local function describe(mob)
    if not mob then
        return 'null'
    end

    return ('{"index":%u,"npc":%s,"hostile":%s,"model_size":%.3f,"model_scale":%.3f}'):format(
        mob.index,
        mob.is_npc and 'true' or 'false',
        is_hostile(mob) and 'true' or 'false',
        tonumber(mob.model_size) or 0,
        tonumber(mob.model_scale) or 1)
end

local function first_subtarget()
    for _, kind in ipairs(subtarget_modes) do
        local mob = lookup(kind)
        if mob then
            return mob
        end
    end

    return nil
end

local function report_status()
    if plugin_running() then
        chat(207, 'Plugin is running.')
    else
        chat(167, 'Plugin is NOT running. The addon cannot draw rings on its own.')
        chat(167, 'Type  //load TargetRing  to start it.')
    end

    if file_exists(installed_dll) then
        chat(207, 'Installed plugin version: ' .. (read_stamp() or 'unknown'))
    else
        chat(167, 'plugins\\' .. plugin_file .. ' is not installed.')
    end

    local target = lookup('t')
    if target then
        chat(207, ('Target: %s (%s)'):format(target.name or '?',
            is_hostile(target) and 'enemy' or 'friendly'))
    else
        chat(207, 'No target selected.')
    end
end

windower.register_event('load', function()
    ensure_plugin()
    check_at = os.clock() + 5
end)

windower.register_event('addon command', function(command)
    command = command and command:lower() or 'status'

    if command == 'status' or command == 'help' then
        report_status()
    elseif command == 'install' then
        local ok, reason = copy_plugin()
        if ok then
            chat(207, 'Copied ' .. plugin_file .. ' into your plugins folder.')
            windower.send_command('wait 1; load ' .. plugin_name)
        else
            manual_install_help(reason)
        end
    else
        chat(207, 'Commands: //tring status | //tring install')
    end
end)

windower.register_event('prerender', function()
    if copy_at > 0 and os.clock() >= copy_at then
        copy_at = 0
        finish_update()
    end

    if not checked and check_at > 0 and os.clock() >= check_at then
        checked = true
        if not plugin_running() then
            report_status()
        end
    end

    local player = windower.ffxi.get_player()
    if player and player.status == 4 then
        local idle = '{"target":null,"subtarget":null}\n'
        if idle ~= previous then
            previous = idle
            local blank = io.open(state_file, 'w')
            if blank then
                blank:write(idle)
                blank:close()
            end
        end
        return
    end

    local target = lookup('t')
    local subtarget = first_subtarget()

    if target and subtarget and target.index == subtarget.index then
        subtarget = nil
    end

    local payload = ('{"target":%s,"subtarget":%s}\n'):format(describe(target), describe(subtarget))

    if payload == previous then
        return
    end

    previous = payload
    local handle = io.open(state_file, 'w')
    if handle then
        handle:write(payload)
        handle:close()
    end
end)
