# CastStill

A Windower 4 addon for Final Fantasy XI that stops your spells, items, and
ranged attacks from getting interrupted right after you stop moving.

## What it does

In FFXI there's a short delay between when you stop moving and when the server
realizes you've stopped. If you cast during that gap, the server thinks you're
still moving and interrupts your spell.

CastStill fixes this. If you cast too soon after moving, it quietly holds the
spell for a fraction of a second until the server knows you're standing still,
then casts it. No more "moved and interrupted" spam when you were clearly
standing still.

It works on magic, ninjutsu, songs, trusts, items, and ranged attacks.

Note: If you cast while you're still actively running, the spell gets sent after
the hold expires and can still be interrupted. CastStill protects you from
the lag after stopping; it can't make you cast while running.

## How it works

CastStill watches the position updates your client sends to the server. When
you act too soon after moving, it holds the outgoing action packet and re-sends
it once the server has confirmed where you're standing or after a short timeout,
whichever comes first. The hold is never longer than 1 second.

There's nothing to configure and no commands. The timings are tuned and fixed.

## Does it work with GearSwap?

Yes.

Windower calls addon event handlers in load order, so whichever addon loads
first sees your actions first, and CastStill has to see them before GearSwap
does. GearSwap is usually already running by the time CastStill starts, so
CastStill reloads it once to put it back in line. If you load CastStill from
your `init.txt`, that reload happens at the character select screen, before the
game is drawing chat, so you won't see it.

Where you will notice: reloading CastStill mid-session reloads GearSwap with it,
which resets any modes you may have set.

All your gear swaps (precast, midcast, aftercast) work exactly like they always
have.

## License

CastStill is free to use and share under the BSD 3-Clause License.

Copyright © 2026 Broguypal
