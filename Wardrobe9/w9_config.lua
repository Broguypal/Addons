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
    -- If true, also print [W9] messages to the chatlog.
    -- Default false: notifications only show in the Wardrobe9 UI box.
    LOG_TO_CHAT = false,

    DEST_BAG_NAMES = {
        'Wardrobe','Wardrobe 2','Wardrobe 3','Wardrobe 4',
        'Wardrobe 5','Wardrobe 6','Wardrobe 7','Wardrobe 8',
    },

    RETURN_BAG_PREFER = {
        'Safe','Safe 2','Storage','Locker','Satchel','Sack','Case',
    },

    SLOT_GROUP = {
        head='head', body='body', hands='hands', legs='legs', feet='feet',
        neck='neck', waist='waist', back='back',
        left_ear='ear', right_ear='ear', ear1='ear', ear2='ear',
        left_ring='ring', right_ring='ring', ring1='ring', ring2='ring',
        ammo='ammo',
        main='weapon', sub='weapon', range='weapon', ranged='weapon',
    },

	-- These groups will not be moved.
    PROTECTED_SLOT_GROUPS = { weapon=true },

	-- These specific items will not be moved.
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

    -- Bags that Wardrobe9 will NEVER move FROM into wardrobes.
    -- Keys are normalized bag names (lowercase).
    SOURCE_BAG_EXCLUDE = {
        ["inventory"] = true,
    },
}
--[[ Available SOURCE_BAG_EXCLUDE bag names:
			"inventory"
			"safe"
			"safe 2"
			"storage"
			"locker"
			"satchel"
			"sack"
			"case"
			"wardrobe"
			"wardrobe 2"
			"wardrobe 3"
			"wardrobe 4"
			"wardrobe 5"
			"wardrobe 6"
			"wardrobe 7"
			"wardrobe 8"
			
]]