# Hivemind

A Windower 4 addon that relays /tells and linkshell chat across all your multiboxed characters.
It also lets you quickly reply from any character using the **Send** addon.

# What it does

## Tells
When any of your characters receives a /tell, every other character running Hivemind will see it in their chat log:

```
[CharacterName] SenderPlayer >> message
```

Outgoing tells are also shared:

```
[CharacterName] >> TargetPlayer : message
```

### Replying to tells

Press **Alt+R** from any character window. The chat box opens with the reply pre-filled:

- If the tell was received on the current character: `/tell PlayerName `
- If received on a different character: `//send CharName /tell PlayerName `

Repeated presses of **Alt+R** cycle through the last 12 unique players who messaged you. Only characters that are currently online are included in the cycle.

Cross-character replies require the **Send** addon.

## Linkshell chat
Linkshell 1 and Linkshell 2 messages are shared across all characters, including messages you send yourself. They appear as:

```
[CharacterName][LS1] SenderPlayer: message
[CharacterName][LS2] SenderPlayer: message
```

If multiple characters are in the same linkshell, built-in deduplication prevents the same message from appearing more than once.

Linkshell monitoring can be toggled per character with `//hivemind linkshell off` (see [Commands](#commands) below).

### Replying to linkshells

Press **Alt+L** from any character window. The chat box opens with the linkshell command pre-filled:

- If the character is the current one: `/l ` or `/l2 `
- If it's a different character: `//send CharName /l ` or `//send CharName /l2 `

Repeated presses of **Alt+L** cycle through all online characters, with `/l` and `/l2` as separate entries for each.

## Commands

| Command | Description |
|---|---|
| `//hivemind linkshell on` | Enable linkshell monitoring (saved per character) |
| `//hivemind linkshell off` | Disable linkshell monitoring (saved per character) |
| `//hivemind linkshell` | Show current linkshell monitoring status |

## Configuration

Settings are managed by Windower's config library and saved per character. Default values can be changed by editing the `defaults` table near the top of `Hivemind.lua`:

```lua
local defaults = {
    reply_bind          = '!r',      -- keybind for reply cycling (! = Alt, ^ = Ctrl, @ = Win)
    ls_bind             = '!l',      -- keybind for linkshell cycling (! = Alt, ^ = Ctrl, @ = Win)
    max_reply           = 12,        -- max unique targets to cycle through
    poll_rate           = 0.1,       -- how often to check for new messages (in seconds)
    max_age             = 3600,      -- purge messages older than 1 hour
    heartbeat_interval  = 120,       -- seconds between heartbeat log entries
    presence_timeout    = 360,       -- consider offline after 6 min without heartbeat
    ls_enabled          = true,      -- toggle with: //hivemind linkshell [on|off]
}
```

## Install

1. Copy the `Hivemind` folder into `Windower4/addons/`
2. Load on each character: `//lua load Hivemind`
3. Add `lua load Hivemind` to your init file to auto-load

## Licence
BSD 3-Clause License

Copyright (c) 2026 Broguypal
