-- Tracked Buff IDs & severity list for DebuffMonitor
-- Edit this file to change what the addon tracks/highlights.

local M = {}

-- Map exact Buff ID => Display Label
M.TRACK = {
    -- Base ailments
    [0] = "KO",
    [1] = "Weakness",
    [2] = "Sleep",
    [3] = "Poison",
    [4] = "Paralysis",
    [5] = "Blindness",
    [6] = "Silence",
    [7] = "Petrification",
    [8] = "Disease",
    [9] = "Curse",
    [10] = "Stun",
    [11] = "Bind",
    [12] = "Weight",
    [13] = "Slow",
    [14] = "Charm",
    [15] = "Doom",
    [16] = "Amnesia",
    [17] = "Charm",                  -- duplicate effect, different ID
    [18] = "Gradual Petrification",
    [19] = "Sleep",                  -- duplicate effect, different ID
    [20] = "Curse",                  -- duplicate effect, different ID
    [21] = "Addle",
    [22] = "Intimidate",
    [23] = "Kaustra",
    [28] = "Terror",
    [29] = "Mute",
    [30] = "Bane",
    [31] = "Plague",

    -- Elemental DoTs / Core downs / Dia-Bio
    [128] = "Burn",
    [129] = "Frost",
    [130] = "Choke",
    [131] = "Rasp",
    [132] = "Shock",
    [133] = "Drown",
    [134] = "Dia",
    [135] = "Bio",
    [136] = "STR Down",
    [137] = "DEX Down",
    [138] = "VIT Down",
    [139] = "AGI Down",
    [140] = "INT Down",
    [141] = "MND Down",
    [142] = "CHR Down",
    [144] = "Max HP Down",
    [145] = "Max MP Down",
    [146] = "Accuracy Down",
    [147] = "Attack Down",
    [148] = "Evasion Down",
    [149] = "Defense Down",

    [156] = "Flash",
    [167] = "Magic Def. Down",
    [168] = "Inhibit TP",
    [174] = "Magic Acc. Down",
    [175] = "Magic Atk. Down",
    [177] = "Encumbrance",

    -- BRD debuffs
    [192] = "Requiem",
    [193] = "Lullaby",
    [194] = "Elegy",
    [223] = "Nocturne",

    -- Additional “Down” IDs
    [557] = "Attack Down",
    [558] = "Defense Down",
    [559] = "Magic Atk. Down",
    [560] = "Magic Def. Down",
    [561] = "Accuracy Down",
    [562] = "Evasion Down",
    [563] = "Magic Acc. Down",
    [564] = "Magic Evasion Down",
    [565] = "Slow",
    [566] = "Paralysis",
    [567] = "Weight",
}


-- Labels to highlight in warm color (optional)
M.SEVERE = {
    ["Doom"]=true,
	["Curse"]=true, 
	["Bane"]=true, 
	["Plague"]=true,
    ["Amnesia"]=true, 
	["Petrification"]=true, 
	["Gradual Petrification"]=true,
    ["Terror"]=true, 
	["Charm"]=true, 
	["Mute"]=true, 
	["Silence"]=true,
}

return M

