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
	{ name = "Secret", weight = 2, color = Color3.fromRGB(255, 50, 50) },
	{ name = "God", weight = 1, color = Color3.fromRGB(255, 100, 255) },
}

-- The twelve collectible brainrots: each earns its cash rate per second while it
-- sits on a pedestal of the player's base. `shape` and `hat` pick the 3D build.
Config.Brainrots = {
	{ id = "satoshi-nekotto", name = "Satoshi Nekotto", rarity = "Common", rate = 1, color = Color3.fromRGB(255, 165, 0), shape = "round", hat = "none" },
	{ id = "vitalik-froghini", name = "Vitalik Froghini", rarity = "Common", rate = 2, color = Color3.fromRGB(120, 200, 240), shape = "box", hat = "none" },
	{ id = "schnorpellino", name = "Schnorpellino", rarity = "Common", rate = 3, color = Color3.fromRGB(240, 140, 170), shape = "tall", hat = "none" },
	{ id = "wumbino-antennini", name = "Wumbino Antennini", rarity = "Uncommon", rate = 6, color = Color3.fromRGB(150, 230, 110), shape = "round", hat = "antenna" },
	{ id = "flibberino-pizza", name = "Flibberino Pizzarolo", rarity = "Uncommon", rate = 10, color = Color3.fromRGB(255, 190, 80), shape = "box", hat = "cap" },
	{ id = "grumbolo-melon", name = "Grumbolo Melonotto", rarity = "Rare", rate = 22, color = Color3.fromRGB(140, 110, 220), shape = "tall", hat = "horns" },
	{ id = "zonketto-limone", name = "Zonketto Limonele", rarity = "Rare", rate = 35, color = Color3.fromRGB(90, 220, 200), shape = "round", hat = "crown" },
	{ id = "binglebop-arcade", name = "Binglebop Macchinino", rarity = "Epic", rate = 75, color = Color3.fromRGB(255, 120, 90), shape = "box", hat = "antenna" },
	{ id = "crungus-funghetto", name = "Crungus Funghetto", rarity = "Epic", rate = 110, color = Color3.fromRGB(110, 240, 160), shape = "tall", hat = "cap" },
	{ id = "fartellone-bomb", name = "Fartellone Bombetta", rarity = "Legendary", rate = 250, color = Color3.fromRGB(200, 200, 60), shape = "box", hat = "crown" },
	{ id = "schnozzolo-fridge", name = "Schnozzolo Gelatone", rarity = "Legendary", rate = 400, color = Color3.fromRGB(90, 160, 255), shape = "round", hat = "horns" },
	{ id = "finale-drago", name = "Finale Dragoespresso", rarity = "Mythic", rate = 900, color = Color3.fromRGB(255, 80, 200), shape = "tall", hat = "crown" },
-- The43 parade brainrots (catchable from the road parade).
	{ id = "satoshino-crocodilo", name = "Satoshino Crocodilo", rarity = "Mythic", rate = 120, color = Color3.fromRGB(255, 70, 120), shape = "round", hat = "none" },
	{ id = "bananita-whalebit", name = "Bananita Whalebit", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "box", hat = "antenna" },
	{ id = "patapim-node", name = "Patapim Node", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "tall", hat = "cap" },
	{ id = "tralalero-rugpull", name = "Tralalero Rugpull", rarity = "God", rate = 1000, color = Color3.fromRGB(255, 100, 255), shape = "round", hat = "horns" },
	{ id = "bombombini-gasfee", name = "Bombombini Gasfee", rarity = "Mythic", rate = 120, color = Color3.fromRGB(255, 70, 120), shape = "box", hat = "crown" },
	{ id = "bombardiro-airdrop", name = "Bombardiro Airdrop", rarity = "Legendary", rate = 50, color = Color3.fromRGB(255, 170, 40), shape = "tall", hat = "none" },
	{ id = "banditore-arbitrage", name = "Banditore Arbitrage", rarity = "Legendary", rate = 50, color = Color3.fromRGB(255, 170, 40), shape = "round", hat = "antenna" },
	{ id = "brr-brr-nodek", name = "Brr Brr Nodek", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "box", hat = "cap" },
	{ id = "frigo-camelo-whale", name = "Frigo Camelo Whale", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "tall", hat = "horns" },
	{ id = "tung-tung-sahur", name = "Tung Tung Sahur", rarity = "Secret", rate = 300, color = Color3.fromRGB(255, 50, 50), shape = "round", hat = "crown" },
	{ id = "capuccina-mining", name = "Capuccina Mining", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "box", hat = "none" },
	{ id = "pipi-potato-stake", name = "Pipi Potato Stake", rarity = "Uncommon", rate = 3, color = Color3.fromRGB(90, 200, 120), shape = "tall", hat = "antenna" },
	{ id = "chimpanzini-solana", name = "Chimpanzini Solana", rarity = "Common", rate = 1, color = Color3.fromRGB(170, 170, 175), shape = "round", hat = "cap" },
	{ id = "hamstero-wheel", name = "Hamstero Wheel", rarity = "Common", rate = 1, color = Color3.fromRGB(170, 170, 175), shape = "box", hat = "horns" },
	{ id = "lameno-tungsten", name = "Lameno Tungsten", rarity = "Uncommon", rate = 3, color = Color3.fromRGB(90, 200, 120), shape = "tall", hat = "crown" },
	{ id = "gorillah-memecoin", name = "Gorillah Memecoin", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "round", hat = "none" },
	{ id = "penguino-stable", name = "Penguino Stable", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "box", hat = "antenna" },
	{ id = "froggo-maker", name = "Froggo Maker", rarity = "Mythic", rate = 120, color = Color3.fromRGB(255, 70, 120), shape = "tall", hat = "cap" },
	{ id = "serpentino-dex", name = "Serpentino Dex", rarity = "Legendary", rate = 50, color = Color3.fromRGB(255, 170, 40), shape = "round", hat = "horns" },
	{ id = "owlcorn-oracle", name = "Owlcorn Oracle", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "box", hat = "crown" },
	{ id = "elephante-bridge", name = "Elephante Bridge", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "tall", hat = "none" },
	{ id = "crabetto-cex", name = "Crabetto CEX", rarity = "Legendary", rate = 50, color = Color3.fromRGB(255, 170, 40), shape = "round", hat = "antenna" },
	{ id = "pandano-vault", name = "Pandano Vault", rarity = "Mythic", rate = 120, color = Color3.fromRGB(255, 70, 120), shape = "box", hat = "cap" },
	{ id = "tortuga-ledger", name = "Tortuga Ledger", rarity = "Common", rate = 1, color = Color3.fromRGB(170, 170, 175), shape = "tall", hat = "horns" },
	{ id = "viperino-node", name = "Viperino Node", rarity = "Uncommon", rate = 3, color = Color3.fromRGB(90, 200, 120), shape = "round", hat = "crown" },
	{ id = "aquilino-stake", name = "Aquilino Stake", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "box", hat = "none" },
	{ id = "cucumbro-chain", name = "Cucumbro Chain", rarity = "Uncommon", rate = 3, color = Color3.fromRGB(90, 200, 120), shape = "tall", hat = "antenna" },
	{ id = "gelatino-mint", name = "Gelatino Mint", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "round", hat = "cap" },
	{ id = "piccione-bridge", name = "Piccione Bridge", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "box", hat = "horns" },
	{ id = "gattino-swap", name = "Gattino Swap", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "tall", hat = "crown" },
	{ id = "bruschetta-block", name = "Bruschetta Block", rarity = "Uncommon", rate = 3, color = Color3.fromRGB(90, 200, 120), shape = "round", hat = "none" },
	{ id = "volpe-oracle", name = "Volpe Oracle", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "box", hat = "antenna" },
	{ id = "zucchino-vault", name = "Zucchino Vault", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "tall", hat = "cap" },
	{ id = "moscato-whale", name = "Moscato Whale", rarity = "Mythic", rate = 120, color = Color3.fromRGB(255, 70, 120), shape = "round", hat = "horns" },
	{ id = "cannoli-blaster", name = "Cannoli Blaster", rarity = "Legendary", rate = 50, color = Color3.fromRGB(255, 170, 40), shape = "box", hat = "crown" },
	{ id = "gnocchi-golem", name = "Gnocchi Golem", rarity = "Secret", rate = 300, color = Color3.fromRGB(255, 50, 50), shape = "tall", hat = "none" },
	{ id = "focaccia-node", name = "Focaccia Node", rarity = "Uncommon", rate = 3, color = Color3.fromRGB(90, 200, 120), shape = "round", hat = "antenna" },
	{ id = "pesto-pirate", name = "Pesto Pirate", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "box", hat = "cap" },
	{ id = "tiramisu-tower", name = "Tiramisu Tower", rarity = "Epic", rate = 20, color = Color3.fromRGB(170, 90, 255), shape = "tall", hat = "horns" },
	{ id = "arancino-bomb", name = "Arancino Bomb", rarity = "Legendary", rate = 50, color = Color3.fromRGB(255, 170, 40), shape = "round", hat = "crown" },
	{ id = "limone-frost", name = "Limone Frost", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "box", hat = "none" },
	{ id = "prosciutto-smoke", name = "Prosciutto Smoke", rarity = "Rare", rate = 8, color = Color3.fromRGB(80, 140, 255), shape = "tall", hat = "antenna" },
	{ id = "polenta-pillar", name = "Polenta Pillar", rarity = "Common", rate = 1, color = Color3.fromRGB(170, 170, 175), shape = "round", hat = "cap" },
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
	startCash = 100, -- enough for a few Common catches to get the loop going
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
-- Every walker moves at one convoy speed and keeps a fixed laneSpacing gap, so
-- the lane reads as an even convoy instead of fast walkers pile-driving slow ones.
Config.CARPET_HALF = 72 -- exported so init.server can use it without hardcoding
Config.Walkers = {
	minAlive = 0,
	maxAlive = 0,
	respawnDelay = 4, -- seconds before a replacement spawns after a catch
	labelVOffset = 3.8, -- higher than capsule/carried/placed labels so they never overlap
	spawnY = 3.5, -- studs above the carpet
	laneSpacing = 9, -- fixed convoy gap kept between walkers (studs)
	convoySpeed = 7, -- every walker moves at this speed (no per-rarity speed)
}

-- Rarity lookup by name, for rolls and labels.
-- Catch price when buying a brainrot off the parade.
function Config.catchPrice(rarityName)
	local prices = {
		Common = 10, Uncommon = 50, Rare = 250, Epic = 1000,
		Legendary = 2500, Mythic = 5000, Secret = 8000, God = 10000,
	}
	return prices[rarityName] or 10
end

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
