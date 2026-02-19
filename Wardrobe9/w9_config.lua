--[[
Wardrobe9 - Windower addon for Final Fantasy XI
BSD 3-Clause License

Copyright (c) 2026 Broguypal
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain this notice.
2. Redistributions in binary form must reproduce this notice in documentation.
3. Neither the name of the author nor contributors may be used to endorse or
   promote products derived from this software without prior written permission.

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
]]

return {

    ---------------------------------------------------------------------------
    -- CHAT LOG
		-- If true, also print [W9] messages to the chatlog.
		-- Default false: notifications only show in the Wardrobe9 UI box.
    ---------------------------------------------------------------------------
	
    LOG_TO_CHAT = false,

    ---------------------------------------------------------------------------
    -- USER INTERFACE POSITION
		-- Where the Wardrobe9 panel appears when it first opens.
		-- You can still drag it around once it's visible.
    ---------------------------------------------------------------------------

    UI_START_X = 420,
    UI_START_Y = 220,

    ---------------------------------------------------------------------------
    -- DESTINATION WARDROBES (true = eligible destination)
    --
    -- Note: If a wardrobe is not currently active/available, Wardrobe9 ignores
    -- it automatically (you don't need to change this list).
    ---------------------------------------------------------------------------

    DEST_BAGS = {
        ["Wardrobe"]   = true,
        ["Wardrobe 2"] = true,
        ["Wardrobe 3"] = true,
        ["Wardrobe 4"] = true,
        ["Wardrobe 5"] = true,
        ["Wardrobe 6"] = true,
        ["Wardrobe 7"] = true,
        ["Wardrobe 8"] = true,
    },

    ---------------------------------------------------------------------------
    -- RETURN BAG PRIORITY (top-to-bottom = priority)
    --
    -- When Wardrobe9 swaps an unused wardrobe item out, it tries these bags in
    -- order and returns it to the first enabled bag it finds.
    ---------------------------------------------------------------------------

    RETURN_BAG_ORDER = {
        "Safe",
        "Safe 2",
        "Storage",
        "Locker",
        "Satchel",
        "Sack",
        "Case",
    },

    ---------------------------------------------------------------------------
    -- SLOT GROUPS (reference only)
    -- Used by Wardrobe9 to treat "left/right ring" as the same slot group, etc.
    -- DO NOT edit unless you know exactly what you're doing.
    ---------------------------------------------------------------------------

    SLOT_GROUP = {
        head='head', body='body', hands='hands', legs='legs', feet='feet',
        neck='neck', waist='waist', back='back',
        left_ear='ear', right_ear='ear', ear1='ear', ear2='ear',
        left_ring='ring', right_ring='ring', ring1='ring', ring2='ring',
        ammo='ammo',
        main='weapon', sub='weapon', range='weapon', ranged='weapon',
    },

    ---------------------------------------------------------------------------
    -- PROTECTED SLOT GROUPS (true = never moved)
    ---------------------------------------------------------------------------
	
    PROTECTED_SLOT_GROUPS = {
        weapon = true,
        ring   = false,
        ear    = false,
        head   = false,
        body   = false,
        hands  = false,
        legs   = false,
        feet   = false,
        neck   = false,
        waist  = false,
        back   = false,
        ammo   = false,
    },

    ---------------------------------------------------------------------------
    -- LOCKED ITEMS (true = never moved)
    ---------------------------------------------------------------------------

    LOCKED_ITEMS = {
        ["Warp Ring"] = true,
        ["Dim. Ring (Holla)"] = true,
        ["Dim. Ring (Dem)"] = true,
        ["Dim. Ring (Mea)"] = true,
        ["Trizek Ring"] = true,
        ["Echad Ring"] = true,
        ["Facility Ring"] = true,
        ["Capacity Ring"] = true,
        ["Reraise Gorget"] = true,
        ["Airmid's Gorget"] = true,
        ["Nexus Cape"] = true,
        ["Shobuhouou Kabuto"] = true,
    },

    ---------------------------------------------------------------------------
    -- SOURCE BAG EXCLUSIONS
    -- true  = Wardrobe9 will NEVER move items FROM this bag into wardrobes
    ---------------------------------------------------------------------------

    SOURCE_BAG_EXCLUDE = {
        ["inventory"] = true,
        ["safe"]    = false,
        ["safe 2"]  = false,
        ["storage"] = false,
        ["locker"]  = false,
        ["satchel"] = false,
        ["sack"]    = false,
        ["case"]    = false,
    },

    ---------------------------------------------------------------------------
    -- CUSTOM GEARSWAP VARIABLES (ADVANCED USERS)
    -- Add custom gearswap variables to this list so gear isn't missed during plan
	-- This looks for assignments like: VAR_NAME = "Item Name"
	-- format: head = {"VAR_NAME","WAR_HEAD","AF_HEAD",...},
			-- Note: weapon includes MAIN / SUB / RANGED gear
    ---------------------------------------------------------------------------

	CUSTOM_GEAR_VARIABLES = {
		weapon	= {},
		head  	= {},
		body  	= {},
		hands 	= {},
		legs  	= {},
		feet  	= {},
		neck  	= {},
		waist 	= {},
		back  	= {},
		ear   	= {},
		ring  	= {},
		ammo  	= {},
	},
	
}
