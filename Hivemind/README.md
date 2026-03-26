# Hivemind

A Windower 4 addon that relays incoming /tells and Linkshell messages across all your multiboxed characters. 
It also lets you quickly reply from any character to the last message received when using the **Send** addon.

## Features

- **Tells:** Incoming and outgoing tells are relayed to all active characters.
- **Linkshells:** Messages from Linkshell 1 and Linkshell 2 are relayed to all characters.
- **Self-Relay:** Messages you send on one character appear as relays on your others, ensuring a complete conversation history everywhere.
- **Deduplication:** Automatically suppresses duplicate messages if multiple characters are in the same linkshell.

## Keybinds

### /tells (Alt+R)
Press **Alt+R** to cycle through the last 6 unique people who sent you a tell. 
- If the tell was on the current character: `/tell Player `
- If on another character: `//send CharName /tell Player `

### Linkshells (Alt+L)
Press **Alt+L** to cycle through your active linkshell bridges across all characters.
- The cycle is sorted by **recency** (the linkshell that most recently saw a message is always first).
- Automatically routes via `//send` if the linkshell is on a different character.

## Configuration

To change the default keybinds or settings, open `Hivemind.lua` and edit the variables near the top:

```lua
local REPLY_BIND  = '!r'         -- keybind for reply cycling (! = Alt, ^ = Ctrl, @ = Win)
local LS_BIND     = '!l'         -- keybind for linkshell cycling
local MAX_REPLY   = 6            -- max unique targets to cycle through
```

## Troubleshooting

If you are having trouble with specific messages not relaying, you can use:
- `//hivemind debug`: Toggles a debug mode that prints raw chat packet info to your chat box.

## Install

1. Copy the `Hivemind` folder into `Windower4/addons/`
2. Load on each character: `//lua load Hivemind`
3. Add `lua load Hivemind` to your init file to auto-load

## Licence
BSD 3-Clause License

Copyright (c) 2026 Broguypal
