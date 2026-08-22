# Vanish

Hides other players from your FFXI client by suppressing their model at draw
time. Nothing is sent to the server, and no packets are read or altered.

## Install

Drop the folder in `Windower4/addons/`, then `//lua load vanish`.

## Modes

| Mode | Effect |
|---|---|
| Vanish | Everyone on the blacklist is hidden |
| Vanishga | Only the whitelist is drawn |

A keybind can be added after first load in the `data > settings folder` to cycle 
between modes:

| `<keybind>!space</keybind>` | Makes the keybind alt + spacebar  |


## Commands

`//vanish` or `//van`.

| Command | Effect |
|---|---|
| `vanish` | Switch to Vanish mode |
| `vanishga` | Switch to Vanishga mode |
| `cycle` | Swap modes |
| `add <name>` | Add to the active mode's list |
| `remove <name>` | Remove from the active mode's list |
| `blacklist add\|remove <name>` | Edit the blacklist from either mode |
| `whitelist add\|remove <name>` | Edit the whitelist from either mode |
| `list` | Show both lists |
| `clear` | Empty the active mode's list |

## Notes

- Mode, both lists and the keybind are saved to `data/settings.xml`, shared
  across all characters. Change `keybind` there to rebind.
- No chat filtering. Use `/blist`.

## License

BSD 3-Clause. Copyright (c) 2026 Broguypal.
