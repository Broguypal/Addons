# CastStill

Stops your spells/items/ranged attacks from getting interrupted right after you stop moving.

## What it does

In FFXI there's a short delay between when you stop moving and when the
server realizes you've stopped. If you cast during that gap, the server
thinks you're still moving and interrupts your spell.

CastStill fixes this. If you cast too soon after moving, it quietly holds
the spell for a fraction of a second until the server knows you're standing
still, then casts it. No more "moved and interrupted" spam when you were
clearly standing still.

It works on magic, ninjutsu, songs, trusts, items, and ranged attacks.
Job abilities and weapon skills aren't affected (movement doesn't
interrupt those anyway).

## Installing

1. Copy the `CastStill` folder into your `Windower/addons/` folder.
   You should end up with `Windower/addons/CastStill/CastStill.lua`.
2. In game, type:

   ```
   //lua load caststill
   ```

3. To have it load automatically, add it to your addon list in the
   Windower launcher, or add `lua load caststill` to your init.txt.

That's it. There's nothing to configure.

## Does it work with GearSwap?

Yes. You don't need GearSwap for CastStill to work, but if you use it,
they work together automatically. When CastStill loads and finds GearSwap
running, it reloads GearSwap once (you'll see a message about this). That's
normal - it just makes sure the two addons cooperate in the right order.

All your gear swaps (precast, midcast, aftercast) work exactly like they
always have.

## Commands

You'll probably never need these, but they exist:

- `//cst` - shows current settings
- `//cst stop 0.5` - changes how long a spell can be held before it's
  sent anyway (default is 0.35 seconds)
- `//cst recent 1.5` - changes how recently you must have moved for a
  spell to be held at all (default is 1.25 seconds)

## Good to know

- The hold is short - usually you won't even notice it.
- If you cast while you're still actively running, the spell gets sent
  after the hold expires and can still be interrupted. CastStill protects
  you from the lag after stopping; it can't make you cast while running.

## License

CastStill is free to use and share under the BSD 3-Clause License.

Copyright (c) 2026 Broguypal
