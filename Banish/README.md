# Banish

Hides characters from your FFXI client completely: no model, no nameplate, no
bazaar, and they can't be targeted at all. Useful against bazaar scammers, who
stay clickable even after `/blist`. Client-side only, nothing is sent to the
server.

## Install

Drop the folder in `Windower4/addons/`, then `//lua load banish`.

## Commands

`//banish` or `//ban`.

| Command | Effect |
|---|---|
| `add <name>` | Hide a character |
| `remove <name>` | Unhide |
| `list` | Show the list |

## Notes

- Zone after `remove` before someone reappears.
- Party and alliance members are never hidden (and automatically become unhidden if they join mid-session).
- No chat filtering. Use `/blist`.
- List saved to `data/settings.xml`, shared across all characters.

## License

BSD 3-Clause. Copyright (c) 2026 Broguypal.
