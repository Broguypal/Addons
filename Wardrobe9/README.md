# Wardrobe9

**Wardrobe9** is a Windower 4 addon for *Final Fantasy XI* that
reads your GearSwap Lua files, checks your wardrobes for the gear
they reference, and moves everything into place automatically.

> Make sure the gear in your Lua files is actually in your wardrobes —
> and fix it when it isn't.

------------------------------------------------------------------------

## How It Works

Wardrobe9 has two interfaces that appear automatically:

-   **Mog House panel** — Opens when you enter your Mog House. This is
    where you scan your bags, plan wardrobe moves, and execute them.

-   **Porter Moogle panel** — Opens when you walk near a Porter Moogle.
    This lets you retrieve gear stored on Porter Mog Slips.

Both panels start collapsed (just a title bar) to stay out of your way.
Click the **[+]** button on the right side to expand, or **[-]** to
collapse again. You can drag the title bar to reposition either panel.

------------------------------------------------------------------------

## Mog House

### Step-by-Step

1.  **SCAN** — Reads all of your bags and builds a list of everything
    you own. Always do this first.

2.  **Select your Lua file(s)** — Check one or more GearSwap files from
    the list. Wardrobe9 finds all `.lua` files in your GearSwap `data`
    folder automatically.

3.  **PLAN** — Compares the gear in your Lua files against what's in
    your wardrobes and shows you what needs to move.

4.  **SWAP** or **FILL** — Executes the plan.

### SWAP vs FILL

-   **SWAP** — Makes room by swapping out unused gear of the same type
    (ring for ring, body for body, etc.). Uses free slots as a fallback.

-   **FILL** — Uses free wardrobe slots first. Only swaps something out
    if there's no empty space left.

### Validation

-   **VAL:MISS** — Shows gear referenced in your Lua files that isn't in
    your wardrobes. Tells you if it's missing entirely, stored on a
    Porter Mog Slip, or sitting in another bag.

-   **VAL:UNUSED** — Shows gear sitting in your wardrobes that isn't
    referenced by your selected Lua files. Helpful for freeing up space.

------------------------------------------------------------------------

## Porter Moogle

The Porter Moogle panel appears when you're near a Porter Moogle and
disappears when you walk away.

### Step-by-Step

1.  **Select your Lua file(s)** — Same file list as the Mog House panel.

2.  **SCAN SLIPS** — Identifies which gear from your Lua files is stored
    on Porter Mog Slips. Shows you which slips are needed and whether
    they're in your inventory.

3.  **Choose how to retrieve:**

    -   **RETRIEVE** — Pulls items from the Porter Moogle into your
        inventory.

    -   **RETR+FILL** — Retrieves items, then moves them into your
        wardrobes automatically.

    -   **RETR+STORE** — Retrieves items, then stores them in your Mog
        Satchel, Mog Case, or Mog Sack (the portable bags you can
        access outside your Mog House).

**Note:** Your Porter Mog Slips must be in your inventory before you can
retrieve items. SCAN SLIPS will warn you if any slips are stored
elsewhere.

------------------------------------------------------------------------

## Automatic Lua Parsing

The planner reads your GearSwap Lua files and automatically picks up
gear from:

-   Direct assignments like `head = "Pummeler's Mask +3"`.
-   Table assignments with augments like `head = { name = "...", augments = {...} }`.
-   Variable references like `head = EMPY.Head` or `head = my_var` —
    resolved automatically by scanning the file for variable definitions.

No setup is needed for any of this. If you use unconventional variable
patterns that the parser can't resolve on its own, you can add them to
`CUSTOM_GEAR_VARIABLES` in the config file (see below).

------------------------------------------------------------------------

## Configuration (w9_config.lua)

You can adjust Wardrobe9's behavior by editing `w9_config.lua`. Most
users won't need to change anything beyond locked items.

### Locked Items

Items you never want moved. Useful for convenience gear like Warp Ring.

```lua
LOCKED_ITEMS = {
    ["Warp Ring"]         = true,
    ["Dim. Ring (Holla)"] = true,
    ["Echad Ring"]        = true,
},
```

### Protected Slot Groups

Entire equipment categories you never want moved. Weapons are protected
by default.

```lua
PROTECTED_SLOT_GROUPS = {
    weapon = true,
},
```

Available groups: `weapon`, `head`, `body`, `hands`, `legs`, `feet`,
`neck`, `waist`, `back`, `ear`, `ring`, `ammo`.

### Destination Wardrobes

Which wardrobes Wardrobe9 is allowed to move items into. All eight are
enabled by default. Set any to `false` to exclude it.

```lua
DEST_BAGS = {
    ["Wardrobe"]   = true,
    ["Wardrobe 2"] = true,
    -- through Wardrobe 8
},
```

**Note:** If a Wardrobe is not activated you do not need to change this 
to false as Wardrobe9 ignores these automatically.

### Return Bag Priority

When Wardrobe9 evicts an unused item from a wardrobe, it sends it to the
first available bag in this list.

```lua
RETURN_BAG_ORDER = {
    "Safe", "Safe 2", "Storage",
    "Locker", "Satchel", "Sack", "Case",
},
```

### Source Bag Exclusions

Bags that Wardrobe9 will never pull items *from*. Inventory is excluded
by default so Wardrobe9 won't grab things out of your active inventory.

```lua
SOURCE_BAG_EXCLUDE = {
    ["inventory"] = true,
},
```

### Chat Logging

Set to `true` to also print messages to the FFXI chat log. Default is
`false` (messages only appear in the Wardrobe9 panel).

```lua
LOG_TO_CHAT = false,
```

### UI Position

Where the panel appears when it first opens. You can drag it after that.

```lua
UI_START_X = 420,
UI_START_Y = 220,
```

### Custom Gear Variables (Advanced)

Only needed if you use variable names in your Lua that the automatic
parser can't resolve — for example, a variable that is defined but never
directly assigned to a gear slot. Add the variable name under the
appropriate slot group so the planner knows to look for it.

```lua
CUSTOM_GEAR_VARIABLES = {
    head = {"WAR_AF_HEAD"},
    body = {},
    -- ...
},
```

------------------------------------------------------------------------

## Installation

1.  Place the `wardrobe9` folder in your Windower `addons` directory.
2.  In-game, load with `//lua load wardrobe9`.
3.  Enter your Mog House or walk near a Porter Moogle.

------------------------------------------------------------------------

## Notes

-   In windowed mode, button positions may appear slightly offset from
    their click targets. This is a Windower 4 limitation. Borderless
    Windowed or Fullscreen mode is recommended.

-   If your cursor appears behind the addon interface, enable Hardware
    Mouse in the Windower launcher (Edit → Game tab → Hardware Mouse).

-   Full wardrobe management (SCAN, PLAN, SWAP, FILL) requires being
    inside your Mog House.

-   Porter Mog Slips must be in your inventory before retrieval.

------------------------------------------------------------------------

## License

BSD 3-Clause License — Copyright (c) 2026 Broguypal
