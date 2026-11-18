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

-- Traits stack on top of a mutation: 0-2 per character, each one visible on
-- the model (colour shift, sparkles, glow) and each one adding to that
-- character's income. Income rule, shared by server and HUD:
-- TotalIncome = BaseIncome * (MutationModifier + sum(TraitModifiers)).
Config.Traits = {
	{ id = "golden", name = "Golden", modifier = 0.5, weight = 34, color = Color3.fromRGB(255, 215, 60) },
	{ id = "glitched", name = "Glitched", modifier = 1.0, weight = 28, color = Color3.fromRGB(175, 95, 255) },
	{ id = "rainbow", name = "Rainbow", modifier = 1.5, weight = 22, color = Color3.fromRGB(120, 255, 245) },
	{ id = "halo", name = "Halo", modifier = 2.5, weight = 16, color = Color3.fromRGB(255, 245, 160) },
}

-- How many traits a fresh roll carries — most characters carry none, so a
-- traited pull stays a screenshot moment.
Config.TraitRoll = {
	{ count = 0, weight = 70 },
	{ count = 1, weight = 22 },
	{ count = 2, weight = 8 },
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
	rebirthBaseUnits = 4, -- placed brainrots the first rebirth demands
	rebirthUnitsPerRebirth = 2, -- +2 characters required per rebirth, capped at maxSlots
	rebirthSlotsBonus = 2, -- extra pedestal slots every rebirth unlocks, capped at maxSlots
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

-- Base lock: the robbery alarm. It starts when another player steps on your
-- island (or the tsunami finds your base unattended) and runs a countdown with
-- a locked state on the base and a HUD alert on the owner. The lock starts at
-- 60 s and grows +10 s per rebirth; if it reaches zero the thief takes a
-- character (or cash, if their hands are full).
Config.Lock = {
	duration = 60,
	perRebirth = 10,
	stealCashFraction = 0.15, -- cash fallback when no character can be taken
}

-- Rare spawns (Rare and above) are announced in Roblox chat and with a HUD
-- banner. Announcements are rate-limited so a busy plaza does not spam chat;
-- a Mythic always announces.
Config.RareAnnounce = {
	minInterval = 12, -- seconds between announcements
}

-- Walking brainrot characters on the red carpet: 12-16 walkers always alive,
-- single lane at x=0, z from -CARPET_HALF to +CARPET_HALF then wrap.
-- Speed scales with rarity so rarer characters are harder to catch.
Config.CARPET_HALF = 72 -- exported so init.server can use it without hardcoding
Config.Walkers = {
	minAlive = 12,
	maxAlive = 16,
	respawnDelay = 4, -- seconds before a replacement spawns after a catch
	labelVOffset = 3.8, -- higher than capsule/carried/placed labels so they never overlap
	spawnY = 2.0, -- studs above the carpet
	speeds = {
		Common = 4,
		Uncommon = 6,
		Rare = 8,
		Epic = 10,
		Legendary = 13,
		Mythic = 17,
	},
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

-- Roll 0-2 distinct traits for a fresh character.
function Config.rollTraits(rng)
	local total = 0
	for _, entry in ipairs(Config.TraitRoll) do
		total += entry.weight
	end
	local pick = rng:NextNumber() * total
	local count = 0
	for _, entry in ipairs(Config.TraitRoll) do
		pick -= entry.weight
		if pick <= 0 then
			count = entry.count
			break
		end
	end

	local pool = {}
	for _, trait in ipairs(Config.Traits) do
		table.insert(pool, trait)
	end
	local traits = {}
	for _ = 1, count do
		if #pool == 0 then
			break
		end
		local weightTotal = 0
		for _, trait in ipairs(pool) do
			weightTotal += trait.weight
		end
		local traitPick = rng:NextNumber() * weightTotal
		for index, trait in ipairs(pool) do
			traitPick -= trait.weight
			if traitPick <= 0 then
				table.insert(traits, trait)
				table.remove(pool, index)
				break
			end
		end
	end
	return traits
end

-- Sum of every trait's income modifier.
function Config.traitSum(traits)
	local sum = 0
	if traits then
		for _, trait in ipairs(traits) do
			sum += trait.modifier
		end
	end
	return sum
end

-- "Golden · Halo", or "" when the character carries no traits.
function Config.traitLabel(traits)
	local names = {}
	if traits then
		for _, trait in ipairs(traits) do
			table.insert(names, trait.name)
		end
	end
	return table.concat(names, " · ")
end

-- TotalIncome = BaseIncome * (MutationModifier + sum(TraitModifiers)).
function Config.unitIncome(entry, mutation, traits)
	local mutationModifier = mutation and mutation.multiplier or 1
	return math.floor(entry.rate * (mutationModifier + Config.traitSum(traits)) + 0.5)
end

-- The name shown on the 3D label and in the carry pill:
-- "Golden · Halo · Zonko the Zesty" (mutation first, then traits, then name).
function Config.unitTitle(entry, mutation, traits)
	local parts = {}
	if mutation and mutation.name ~= "" then
		table.insert(parts, mutation.name)
	end
	local traitText = Config.traitLabel(traits)
	if traitText ~= "" then
		table.insert(parts, traitText)
	end
	table.insert(parts, entry.name)
	return table.concat(parts, " · ")
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

-- Characters that must stand on your pedestals before the rebirth unlocks.
-- Placed units are wiped by every rebirth, so this is a fresh goal each time.
function Config.rebirthUnitRequirement(currentRebirths)
	return math.min(
		Config.Economy.maxSlots,
		Config.Economy.rebirthBaseUnits + currentRebirths * Config.Economy.rebirthUnitsPerRebirth
	)
end

-- Total income multiplier: shop levels, then rebirths on top.
function Config.incomeMultiplier(multiplierLevel, rebirths)
	return 1 + multiplierLevel * Config.Economy.multiplierPerLevel + rebirths * Config.Economy.rebirthMultiplierBonus
end

return Config
