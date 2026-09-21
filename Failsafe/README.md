# Failsafe

Failsafe is a Windower addon for Final Fantasy XI that re-sends spells, weaponskills, 
items and job abilities that are refused because you pressed them while in the middle 
of another action.

# What is it?

Ever press a spell, weaponskill, job ability, or item a split second too early and the 
game refuses it? Failsafe presses it again for you.

## How it behaves

1. You use an ability (spell, job ability, weaponskill, or item).
2. It doesn't go off.
3. Failsafe retries it, up to 3 attempts total.

## Install

* Put `Failsafe.lua` in `Windower/addons/Failsafe/`
* Run `//lua load failsafe`
* Add it to your init script to load it automatically

## License

Failsafe is free to use and share under the BSD 3-Clause License.

Copyright © 2026 Broguypal
