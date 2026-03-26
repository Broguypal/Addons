# Hivemind

A Windower 4 addon that relays /tells and linkshell chat across all your multiboxed characters.
It also lets you quickly reply from any character using the **Send** addon.

## What it does

### Tells
When any of your characters receives a /tell, every other character running Hivemind will see it in their chat log:

```
[CharacterName] SenderPlayer >> message
```

Outgoing tells are also shared:

```
[CharacterName] >> TargetPlayer : message
```

### Linkshell chat
Linkshell 1 and Linkshell 2 messages are shared across all characters, including messages you send yourself. They appear as:

```
[CharacterName][LS1] SenderPlayer: message
[CharacterName][LS2] SenderPlayer: message
```

If multiple characters are in the same linkshell, built-in deduplication prevents the same message from appearing more than once.

Linkshell monitoring can be disabled entirely by setting `LS_ENABLED = false` in the config section.

## Replying to tells

Press **Alt+R** from any character window. The chat box opens with the reply pre-filled:

- If the tell was received on the current character: `/tell PlayerName `
- If received on a different character: `//send CharName /tell PlayerName `

Repeated presses of **Alt+R** cycle through the last 12 unique players who messaged you. Only characters that are currently online are included in the cycle.

## Replying to linkshells

Press **Alt+L** from any character window. The chat box opens with the linkshell command pre-filled:

- If the character is the current one: `/l ` or `/l2 `
- If it's a different character: `//send CharName /l ` or `//send CharName /l2 `

Repeated presses of **Alt+L** cycle through all online characters, with `/l` and `/l2` as separate entries for each.

### Cycling order

The cycle prioritises the linkshell where someone last spoke. For example, if someone talks in CharC's LS2, the first press of Alt+L gives you `//send CharC /l2`. Subsequent presses cycle through the remaining characters, starting with the one you're currently on.

If nobody has spoken yet, the default order is your current character first (`/l`, `/l2`), then other online characters in the order they logged in.

Cross-character replies require the **Send** addon.

## Configuration

To change keybinds or other settings, open `Hivemind.lua` and edit the variables near the top of the file:

```lua
local REPLY_BIND  = '!r'         -- keybind for tell reply (! = Alt, ^ = Ctrl, @ = Win)
local LS_BIND     = '!l'         -- keybind for linkshell reply
local MAX_REPLY   = 12           -- max unique targets to cycle through
local POLL_RATE   = 0.1          -- how often to check for new messages (in seconds)
local MAX_AGE     = 3600         -- purge messages older than 1 hour
local LS_ENABLED  = true         -- set to false to disable linkshell monitoring
```

## Install

1. Copy the `Hivemind` folder into `Windower4/addons/`
2. Load on each character: `//lua load Hivemind`
3. Add `lua load Hivemind` to your init file to auto-load

## Licence
BSD 3-Clause License

Copyright (c) 2026 Broguypal
