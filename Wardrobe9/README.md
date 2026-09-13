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
    Tabbed into Retrieve Items, Deposit Items, and Validate Slips.

In your **Mog Garden** you have both at once: full Mog House storage
access *and* a Porter Moogle. Walk up to the Porter Moogle there and a
pair of switcher tabs — **WARDROBE9** and **PORTER** — appear in the
title bar of whichever panel is showing. Click either to swap between
them. Only one panel is on screen at a time, so they never overlap.

Approaching the Porter Moogle switches you to the PORTER panel
automatically; walking away returns you to WARDROBE9 and the switcher
tabs disappear. Everywhere else behaves exactly as before — one panel,
no tabs.

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

The panel is split into three tabs. Selecting a tab shows only that
tab's buttons and hides the others, so the steps for what you're doing
are always the only thing on screen.

The Lua file list at the bottom is shared by all three tabs.

### Tab 1 — Retrieve Items

The default tab. Pulls gear off your slips.

1.  **Select your Lua file(s)** — Same file list as the Mog House panel.

2.  **Scan Luas for Missing** — Identifies which gear from your selected
    Lua files is stored on Porter Mog Slips. Shows which slips are
    needed and whether they're in your inventory.

3.  **Choose how to retrieve:**

    -   **Retrieve Missing** — Pulls items from the Porter Moogle into
        your inventory.

    -   **RETR+FILL** — Retrieves items, then moves them into your
        wardrobes automatically.

    -   **RETR+STORE** — Retrieves items, then stores them in your Mog
        Satchel, Mog Case, or Mog Sack (the portable bags you can
        access outside your Mog House).

### Tab 2 — Deposit Items

Puts gear onto your slips.

1.  **Scan Inventory for Deposit** — Scans your inventory for items that
    a Porter Mog Slip will accept, and reports which slip takes each one.

2.  **Deposit** — Stores those items onto their slips.

### Tab 3 — Validate Slips

A report only. Nothing is moved.

-   **Validate All Slips** — Searches *every* container you own —
    inventory, all eight wardrobes, Safe, Safe 2, Storage, Locker,
    Satchel, Sack and Case — for gear that a Porter Mog Slip is able to
    hold. For each match it reports which slip takes the item, where the
    item currently is, and where that slip currently is.

    Items referenced by the Lua files you tick in the list below are
    **excluded**, so gear you actually use won't be suggested. Use the
    file list to select which Lua's items *not* to consider. With no
    Lua checked, every match is listed, including gear you use.
	
	Rows that the retrieve step won't be able to act on are marked

    -   `[SAFE - skipped]` — the item is in Safe or Safe 2.
    -   `[inaccessible - skipped]` — the item is in a bag you can't open
        from where you're currently standing.
    -   `^ slip inaccessible - skipped` — printed under a slip's header
        when the slip itself is somewhere you can't reach.

    A count of each appears in the summary line at the top of the
    report and again as an explanation at the bottom.

-   **Retrieve Unused Items and Slips** — Takes the report above and
    moves each unused item *and* its matching slip into your inventory,
    ready to deposit.

    Satchel, Sack, Case and Wardrobes 1 through 8 are reachable
    anywhere. Storage and Locker become reachable inside the Mog
    Garden.
	
	**Safe and Safe 2 are never pulled from**, even in the Mog Garden.
    Those bags hold your placed Mog House furniture, which reports
    itself as an ordinary item but cannot be moved and cannot be told
    apart from loose gear. Anything you genuinely want out of Safe or
    Safe 2 has to be moved by hand. Slips are the exception — a slip
    stored in Safe or Safe 2 is still fetched normally, because a slip
    is never placed furniture.

    If an item and its slip won't both fit in your inventory, that pair
    is skipped and the rest are still retrieved — it doesn't give up on
    the first problem. When a pair can't be done you're told why:

    -   The slip isn't in your possession — it names the slip so you can
        buy it from the Porter Moogle, then retry.
    -   The slip exists but sits in a bag you can't reach from where you
        are — it names that bag.
    -   The item itself is in an unreachable bag.
    -   Your inventory filled up partway through.

    When it finishes, switch to the **Deposit Items** tab and run its
    two steps to store everything automatically.

**Note:** Your Porter Mog Slips must be in your inventory before you can
retrieve or deposit items. The scan buttons will warn you if any slips
are stored elsewhere.

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

### Porter Ignore List

Items the Porter Moogle panel should leave alone.

This exists for gear you own and need but never reference in a Lua file,
which would otherwise look like a safe candidate for storing away.

All end stage Ambuscade weapons are enabled by default. Set any entry 
to `false`, or delete the line, to stop ignoring it.

```lua
PORTER_IGNORE_ITEMS = {
    ["Naegling"]    = true,
},
```

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
    head = {"WAR_AF_HELM"},
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
    inside your Mog House or your Mog Garden.

-   Porter Mog Slips must be in your inventory before retrieving or
    depositing.
	
-   Safe and Safe 2 are never used as a retrieve source for the porter
    moogle. They hold placed Mog House furniture, which can't be 
	distinguished from stored gear.

------------------------------------------------------------------------

## License

BSD 3-Clause License — Copyright (c) 2026 Broguypal
