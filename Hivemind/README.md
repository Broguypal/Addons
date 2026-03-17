# Hivemind

A Windower 4 addon that relays incoming /tells across all your multiboxed characters.

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

Press **Ctrl+Numpad0** from any character window. The chat line will pre-fill with:

```
//send CharName /tell PlayerName 
```

Where `CharName` is whichever of your characters received the tell. Just type your reply and hit enter — the reply goes out from the correct character.

Requires the **Send** addon.

## How it works

All instances share a log file at `addons/Hivemind/shared/messages.log`. When a tell arrives, the addon writes it to the log. Each instance polls the log for new entries and displays tells from other characters.

- No external dependencies
- Messages older than 5 minutes are automatically purged
- Does not inject packets.
