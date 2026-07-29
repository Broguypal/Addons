# CastStill

Stops your spells/items/ranged attacks from getting interrupted right after you
stop moving.

## What it does

In FFXI there's a short delay between when you stop moving and when the server
realizes you've stopped. If you cast during that gap, the server thinks you're
still moving and interrupts your spell.

CastStill fixes this. If you cast too soon after moving, it quietly holds the
spell for a fraction of a second until the server knows you're standing still,
then casts it. No more "moved and interrupted" spam when you were clearly
standing still.

It works on magic, ninjutsu, songs, trusts, items, and ranged attacks. Job
abilities and weapon skills aren't affected (movement doesn't interrupt those
anyway).

## Installing

Open the Windower launcher, find CastStill in the addon list, and check it.
It'll be loaded the next time you start the game.

To load it manually instead, type in game:

```
//lua load caststill
```

Or add `lua load caststill` to your `init.txt`.

## How it works

CastStill watches the position updates your client sends to the server. When
you act too soon after moving, it holds the outgoing action packet and re-sends
it once the server has confirmed where you're standing — or after a short
timeout, whichever comes first. The hold is never longer than 0.35 seconds.

There's nothing to configure and no commands. The timings are tuned and fixed.

## Does it work with GearSwap?

Yes, and you don't need GearSwap for CastStill to work.

Windower calls addon event handlers in load order, so whichever addon loads
first sees your actions first — and CastStill has to see them before GearSwap
does. If GearSwap is already loaded when CastStill starts up, CastStill reloads
it once so it re-registers behind. You'll see a message in chat when this
happens.

If CastStill loads first, nothing gets reloaded.

One thing to know: reloading CastStill mid-session will reload GearSwap too,
which resets any modes you've set with `gs c`.

All your gear swaps (precast, midcast, aftercast) work exactly like they always
have.

## Good to know

- The hold is short — usually you won't even notice it.
- If you cast while you're still actively running, the spell gets sent after
  the hold expires and can still be interrupted. CastStill protects you from
  the lag after stopping; it can't make you cast while running.

## License

CastStill is free to use and share under the BSD 3-Clause License.

Copyright © 2026 Broguypal
