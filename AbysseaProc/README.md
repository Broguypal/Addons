# AbysseaProc (Element → Weapon → WS)

This addon lets you select an Abyssea proc element, pick a matching weapon, and auto‑use the correct WS.

## Default Controls
| Key | Action |
|-----|--------|
| **F10** | Cycle element |
| **F11** | Cycle weapon associated with the element selected|
| **F12** | Use appropriate weaponskill |

## Change Keybinds
Open **abysseaproc.lua** and change:

```lua
local key_element = 'f10'
local key_weapon  = 'f11'
local key_ws      = 'f12'
```

## Edit Weapons
Open **abysseaproc.lua** and change:

```lua
local weapon_groups = {
    ["Dagger"] = { "Ceremonial Dagger" },
    ["Sword"]  = { "Twinned Blade" },
}
```

## Reloading After Edits
After saving changes:

```
///lua unload abysseaproc
///lua load abysseaproc
```

Done.
