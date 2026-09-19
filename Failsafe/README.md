# Failsafe

Failsafe is a Windower addon for Final Fantasy XI that re-sends spells, weaponskills 
and job abilities that are refused because you pressed them while in the middle of 
another action.

# What is it?

Ever press a spell, weaponskill or job ability a split second too early and the game 
refuses it? Failsafe presses it again for you.

## How it behaves

1. You use an ability (spell, job ability or weaponskill).
2. It doesn't go off.
3. Failsafe retries it, up to 3 attempts total, about a second apart.
4. It resets completely if:
   * you use another ability. That one becomes the one being watched, and the
     old one is forgotten.
   * all 4 attempts are used. Done, it stops.
   * the ability goes off. Done, it stops.

Only ever the last thing you tried. There is no queue, and nothing you've
moved on from is retried.

Runs silently. No commands, no messages, no settings file.

## Install

* Put `Failsafe.lua` in `Windower/addons/Failsafe/`
* Run `//lua load failsafe`
* Add it to your init script to load it automatically

## License

CastStill is free to use and share under the BSD 3-Clause License.

Copyright © 2026 Broguypal
