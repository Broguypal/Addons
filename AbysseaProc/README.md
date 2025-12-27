# AbysseaProc

This addon lets you press **F12** to cycle through weapons for Abyssea procs.

## Editing the Addon
To change the keybind or weapons, open **abysseaproc.lua** and edit the top section:

```lua
-- KEYBIND
windower.send_command('bind f12 input //aproc cycle')

-- WEAPONS
local weapon_groups = {
    ["Dagger"]       = { "Ceremonial Dagger" },
    ["Sword"]        = { "Twinned Blade" },
    ["Great Sword"]  = { "Irradiance Blade" },
    ["Scythe"]       = { "Hoe" },
    ["Polearm"]      = { "Iapetus" },
    ["Katana"]       = { "Yagyu Short. +1" },
    ["Great Katana"] = { "Ark Tachi" },
    ["Club"]         = { "Chac-chacs" },
    ["Staff"]        = { "Ram Staff" },
}
```

## Reloading After Edits
After saving changes:

```
///lua unload abysseaproc
///lua load abysseaproc
```

Done.
