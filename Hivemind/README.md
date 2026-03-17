# Hivemind

A Windower 4 addon that relays incoming /tells across all your multiboxed characters. 
It also lets you quickly reply from any character to the last tell received when using the **send** addon.

## What it does

When any of your characters receives a /tell, every other character running Hivemind will see it in their chat log. Messages appear as:

```
[CharacterName] SenderPlayer >> message
```

So you always know which character actually received the tell.

## Install

1. Copy the `Hivemind` folder into `Windower4/addons/`
2. Load on each character: `//lua load Hivemind`
3. (Optional) Add `lua load Hivemind` to your init file to auto-load

## Replying

Press **Ctrl+C** from any character window. The chat box opens with the reply pre-filled:

- If the tell was received on the current character: `/tell PlayerName `
- If received on a different character: `//send CharName /tell PlayerName `

Just type your message and hit enter. The reply always goes out from the character who received the tell.

Ctrl+C is intercepted via Windower's keyboard event. If no tell has been received yet, the keypress is ignored.

Cross-character replies require the **Send** addon.

## How it works

All instances share a log file at `addons/Hivemind/shared/messages.log`. When a tell arrives, the addon writes it to the log. Each instance polls the log for new entries and displays tells from other characters.

## Licence
BSD 3-Clause License

Copyright (c) 2026 Broguypal