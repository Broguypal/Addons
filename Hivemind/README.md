# Hivemind

A Windower 4 addon that relays incoming /tells across all your multiboxed characters. 
It also lets you quickly reply from any character to the last tell received when using the **Send** addon.

## What it does

When any of your characters receives a /tell, every other character running Hivemind will see it in their chat log. Messages appear as:

```
[CharacterName] SenderPlayer >> message
```

So you always know which character actually received the tell.

## Replying

Press **Alt+R** from any character window. The chat box opens with the reply pre-filled:

- If the tell was received on the current character: `/tell PlayerName `
- If received on a different character: `//send CharName /tell PlayerName `

Cross-character replies require the **Send** addon.

Repeated presses of **Alt+R** will cycle through the last 6 unique players who messaged you.

## Install

1. Copy the `Hivemind` folder into `Windower4/addons/`
2. Load on each character: `//lua load Hivemind`
3. Add `lua load Hivemind` to your init file to auto-load

## Licence
BSD 3-Clause License

Copyright (c) 2026 Broguypal
