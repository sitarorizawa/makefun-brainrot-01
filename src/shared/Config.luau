-- Config: the brainrot catalog, rarity table, mutations and every economy number.
-- Shared by the server (which owns the state) and the client HUD (which shows it),
-- so both sides always agree on names, rates and prices.

local Config = {}

-- Rarity ladder, weakest first. Colors drive capsule glow, unit labels and the HUD.
Config.Rarities = {
	{ name = "Common", weight = 40, color = Color3.fromRGB(170, 170, 175) },
	{ name = "Uncommon", weight = 26, color = Color3.fromRGB(90, 200, 120) },
	{ name = "Rare", weight = 16, color = Color3.fromRGB(80, 140, 255) },
	{ name = "Epic", weight = 9, color = Color3.fromRGB(170, 90, 255) },
	{ name = "Legendary", weight = 6, color = Color3.fromRGB(255, 170, 40) },
	{ name = "Mythic", weight = 3, color = Color3.fromRGB(255, 70, 120) },
}

-- The twelve collectible brainrots: each earns its cash rate per second while it
-- sits on a pedestal of the player's base. `shape` and `hat` pick the 3D build.
Config.Brainrots = {
	{ id = "gunko", name = "Gunko", rarity = "Common", rate = 1, color = Color3.fromRGB(240, 220, 120), shape = "round", hat = "none" },
	{ id = "blorbo", name = "Blorbo", rarity = "Common", rate = 2, color = Color3.fromRGB(120, 200, 240), shape = "box", hat = "none" },
	{ id = "schnorp", name = "Schnorp", rarity = "Common", rate = 3, color = Color3.fromRGB(240, 140, 170), shape = "tall", hat = "none" },
	{ id = "wumbino", name = "Wumbino", rarity = "Uncommon", rate = 6, color = Color3.fromRGB(150, 230, 110), shape = "round", hat = "antenna" },
	{ id = "flibberjack", name = "Flibberjack", rarity = "Uncommon", rate = 10, color = Color3.fromRGB(255, 190, 80), shape = "box", hat = "cap" },
	{ id = "grumbo", name = "Grumbo", rarity = "Rare", rate = 22, color = Color3.fromRGB(140, 110, 220), shape = "tall", hat = "horns" },
	{ id = "zonko", name = "Zonko the Zesty", rarity = "Rare", rate = 35, color = Color3.fromRGB(90, 220, 200), shape = "round", hat = "crown" },
	{ id = "binglebop", name = "Binglebop", rarity = "Epic", rate = 75, color = Color3.fromRGB(255, 120, 90), shape = "box", hat = "antenna" },
	{ id = "crungus", name = "Crungus", rarity = "Epic", rate = 110, color = Color3.fromRGB(110, 240, 160), shape = "tall", hat = "cap" },
	{ id = "fartbox", name = "Lord Fartbox", rarity = "Legendary", rate = 250, color = Color3.fromRGB(200, 200, 60), shape = "box", hat = "crown" },
	{ id = "schnoz", name = "Quantum Schnoz", rarity = "Legendary", rate = 400, color = Color3.fromRGB(90, 160, 255), shape = "round", hat = "horns" },
	{ id = "finalblorbo", name = "The Final Blorbo", rarity = "Mythic", rate = 900, color = Color3.fromRGB(255, 80, 200), shape = "tall", hat = "crown" },
}

-- Mutations roll independently of rarity when a capsule is caught and multiply
-- the unit's rate. A rainbow Blorbo is still worth little; a rainbow Final Blorbo is a fortune.
Config.Mutations = {
	{ id = "none", name = "", multiplier = 1, weight = 68 },
	{ id = "golden", name = "Golden", multiplier = 2, weight = 18, color = Color3.fromRGB(255, 215, 60), material = Enum.Material.Metal },
	{ id = "toxic", name = "Toxic", multiplier = 3, weight = 10, color = Color3.fromRGB(90, 255, 90), material = Enum.Material.Neon },
	{ id = "rainbow", name = "Rainbow", multiplier = 5, weight = 4, material = Enum.Material.Neon },
}

Config.Economy = {
	startCash = 0,
	startSlots = 4, -- pedestals that accept a unit from the start
	maxSlots = 10,
	slotBaseCost = 500, -- next slot costs slotBaseCost * 2^(slots owned - startSlots)
	startMultiplierLevel = 0,
	maxMultiplierLevel = 6,
	multiplierBaseCost = 800, -- each level costs multiplierBaseCost * 3^level and adds +0.5x income
	multiplierPerLevel = 0.5,
	startSpeedLevel = 0,
	maxSpeedLevel = 3,
	speedBaseCost = 250, -- each level costs speedBaseCost * 2^level and adds walk speed
	speedPerLevel = 6,
	baseWalkSpeed = 16,
	rebirthBaseRequirement = 25000, -- lifetime cash needed for the first rebirth, x4 each after
	rebirthMultiplierBonus = 1.0, -- permanent income multiplier added per rebirth
}

Config.Wave = {
	firstDelay = 55, -- seconds of calm before the first tsunami
	interval = 80, -- seconds of calm between tsunamis
	warning = 15, -- seconds of red-alert countdown before the water moves
	sweep = 14, -- seconds for the wave to cross the whole arena
	waterHeight = 14, -- anything below this height off a base is swept (island tops sit at 16)
}

Config.Capsule = {
	respawnTime = 6, -- seconds until a caught capsule's pad spawns another
	padCount = 8,
	carryHeight = 5.2, -- how far above the character's head a carried unit floats
}

-- Rarity lookup by name, for rolls and labels.
function Config.rarity(name)
	for _, entry in ipairs(Config.Rarities) do
		if entry.name == name then
			return entry
		end
	end
	return Config.Rarities[1]
end

-- Weighted pick of a rarity entry, used when a capsule is caught.
function Config.rollRarity(rng)
	local total = 0
	for _, entry in ipairs(Config.Rarities) do
		total += entry.weight
	end
	local pick = rng:NextNumber() * total
	for _, entry in ipairs(Config.Rarities) do
		pick -= entry.weight
		if pick <= 0 then
			return entry
		end
	end
	return Config.Rarities[1]
end

-- Weighted pick of a mutation entry (may be "none").
function Config.rollMutation(rng)
	local total = 0
	for _, entry in ipairs(Config.Mutations) do
		total += entry.weight
	end
	local pick = rng:NextNumber() * total
	for _, entry in ipairs(Config.Mutations) do
		pick -= entry.weight
		if pick <= 0 then
			return entry
		end
	end
	return Config.Mutations[1]
end

-- Prices, so the server charges and the HUD labels the same number.
function Config.slotCost(currentSlots)
	return Config.Economy.slotBaseCost * 2 ^ (currentSlots - Config.Economy.startSlots)
end

function Config.multiplierCost(currentLevel)
	return Config.Economy.multiplierBaseCost * 3 ^ currentLevel
end

function Config.speedCost(currentLevel)
	return Config.Economy.speedBaseCost * 2 ^ currentLevel
end

function Config.rebirthRequirement(currentRebirths)
	return Config.Economy.rebirthBaseRequirement * 4 ^ currentRebirths
end

-- Total income multiplier: shop levels, then rebirths on top.
function Config.incomeMultiplier(multiplierLevel, rebirths)
	return 1 + multiplierLevel * Config.Economy.multiplierPerLevel + rebirths * Config.Economy.rebirthMultiplierBonus
end

return Config
