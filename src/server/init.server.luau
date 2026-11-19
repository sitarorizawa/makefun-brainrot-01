-- Brainrot Vault Tycoon — server entry point.
-- Owns all game state (one table per player), builds the world, runs the
-- capsule spawner, the catch/place loop, the cash economy, the shop and the
-- tsunami wiring. The client only ever reads attributes and fires ShopAction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldBuilder = require(script.WorldBuilder)
local BrainrotModels = require(script.BrainrotModels)
local Wave = require(script.Wave)

local rng = Random.new()
local ok, worldOrErr = pcall(function() return WorldBuilder.build() end)
local world = ok and worldOrErr or { pads = {}, bases = {} }
if not ok then warn("WorldBuilder.build failed: " .. tostring(worldOrErr)) end

-- One RemoteEvent for every shop button; the client sends an action string.
local shopRemote = Instance.new("RemoteEvent")
shopRemote.Name = "ShopAction"
shopRemote.Parent = ReplicatedStorage

-- ---------------------------------------------------------------------------
-- Player state
-- ---------------------------------------------------------------------------

-- states[player] is the single source of truth for everything a player owns.
local states = {}

local function fmt(n)
	n = math.floor(n + 0.5)
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

local function playerFromHit(hit)
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if player then
		return player
	end
	if hit.Parent and hit.Parent.Parent then
		return Players:GetPlayerFromCharacter(hit.Parent.Parent)
	end
	return nil
end

local function showToast(player, text)
	player:SetAttribute("Toast", text)
	player:SetAttribute("ToastAt", os.clock())
end

local function setHint(player, text)
	player:SetAttribute("Hint", text)
end

local function rarityIndex(name)
	for index, entry in ipairs(Config.Rarities) do
		if entry.name == name then
			return index
		end
	end
	return 1
end

-- Publish collection progress: unique brainrots found and a per-rarity row
-- (rich text so each count wears its rarity colour in the HUD).
local function publishCollection(player, state)
	local count = 0
	for _ in pairs(state.collectedIds) do
		count += 1
	end
	player:SetAttribute("CollectionCount", count)
	player:SetAttribute("CollectionMax", #Config.Brainrots)

	local parts = {}
	for _, rarity in ipairs(Config.Rarities) do
		local n = state.rarityCounts[rarity.name] or 0
		table.insert(parts, string.format(
			'<font color="#%02X%02X%02X">%s %d</font>',
			math.floor(rarity.color.R * 255 + 0.5),
			math.floor(rarity.color.G * 255 + 0.5),
			math.floor(rarity.color.B * 255 + 0.5),
			string.upper(string.sub(rarity.name, 1, 1)),
			n
		))
	end
	player:SetAttribute("RarityProgress", table.concat(parts, "  "))
end

-- Total placed income per second, before the shop/rebirth multiplier.
-- Per unit: TotalIncome = BaseIncome * (MutationModifier + sum(TraitModifiers)).
local function placedIncome(state)
	local total = 0
	for _, unit in pairs(state.pedestals) do
		total += Config.unitIncome(unit.entry, unit.mutation, unit.traits)
	end
	return total
end

-- Publish every number the HUD shows. Called whenever state changes.
local function updateStats(player)
	local state = states[player]
	if state == nil then
		return
	end
	local income = math.floor(placedIncome(state) * Config.incomeMultiplier(state.multiplierLevel, state.rebirths) + 0.5)
	state.cashPerSecond = income
	player:SetAttribute("Cash", math.floor(state.cash))
	player:SetAttribute("CashPerSecond", income)
	player:SetAttribute("Slots", state.slots)
	-- Shop costs for the HUD (−1 = maxed out).
	player:SetAttribute("SlotCost", state.slots < Config.Economy.maxSlots and Config.slotCost(state.slots) or -1)
	player:SetAttribute("MultiplierCost", state.multiplierLevel < Config.Economy.maxMultiplierLevel and Config.multiplierCost(state.multiplierLevel) or -1)
	player:SetAttribute("SpeedCost", state.speedLevel < Config.Economy.maxSpeedLevel and Config.speedCost(state.speedLevel) or -1)
	player:SetAttribute("RebirthNeed", Config.rebirthRequirement(state.rebirths))
	player:SetAttribute("MultiplierLevel", state.multiplierLevel)
	player:SetAttribute("SpeedLevel", state.speedLevel)
	player:SetAttribute("Rebirths", state.rebirths)
	player:SetAttribute("Lifetime", math.floor(state.lifetime))

	local names = {}
	for slot = 1, Config.Economy.maxSlots do
		local unit = state.pedestals[slot]
		if unit then
			table.insert(names, unit.entry.name)
		end
	end
	player:SetAttribute("UnitsPlaced", #names)
	player:SetAttribute("UnitList", table.concat(names, ", "))

	if state.carried then
		local carried = state.carried
		player:SetAttribute("CarryInfo", string.format(
			"%s · %s · $%d/s",
			Config.unitTitle(carried.entry, carried.mutation, carried.traits),
			carried.entry.rarity,
			Config.unitIncome(carried.entry, carried.mutation, carried.traits)
		))
		player:SetAttribute("CarryColor", Config.rarity(carried.entry.rarity).color)
	else
		player:SetAttribute("CarryInfo", "")
	end

	local stats = player:FindFirstChild("leaderstats")
	if stats and stats:FindFirstChild("Cash") then
		stats.Cash.Value = math.floor(state.cash)
	end
end

-- ---------------------------------------------------------------------------
-- Walkers: brainrot characters walking the red carpet, catchable like capsules
-- ---------------------------------------------------------------------------

local walkers = {} -- [walkerIndex] = walker record, 12-16 alive at once

local function walkerCount()
	local n = 0
	for _ in pairs(walkers) do
		n += 1
	end
	return n
end

-- Pick a catalog entry with a controlled rarity mix — weighted toward Common
-- but every rarity can appear so a Mythic on the carpet is a chase-worthy moment.
local function rollWalkerUnit()
	local rarity = Config.rollRarity(rng)
	local pool = {}
	for _, entry in ipairs(Config.Brainrots) do
		if entry.rarity == rarity.name then
			table.insert(pool, entry)
		end
	end
	local entry = pool[rng:NextInteger(1, #pool)]
	local mutation = Config.rollMutation(rng)
	local traits = Config.rollTraits(rng)
	return entry, mutation, traits
end

local function spawnWalker(startZ)
	return nil, nil
end

local function catchWalker(player, record)
	local state = states[player]
	if state == nil or state.carried ~= nil then
		return
	end

	state.carried = { entry = record.entry, mutation = record.mutation, traits = record.traits }
	local model = BrainrotModels.buildCarried(record.entry, record.mutation, record.traits)
	model.Name = "Carried"
	state.carriedModel = model
	model.Parent = workspace

	-- Sparkle on catch, big for Rare+.
	local rarityColor = Config.rarity(record.entry.rarity).color
	if rarityIndex(record.entry.rarity) >= 3 then
		BrainrotModels.sparkleAt(record.model.PrimaryPart.Position, rarityColor, true)
	end

	-- Collection tracking.
	local isNew = state.collectedIds[record.entry.id] == nil
	if isNew then
		state.collectedIds[record.entry.id] = true
		state.rarityCounts[record.entry.rarity] = (state.rarityCounts[record.entry.rarity] or 0) + 1
		publishCollection(player, state)
	end

	-- Retire the walker model and schedule a replacement.
	BrainrotModels.stopWalker(record.model)
	BrainrotModels.retire(record.model)
	record.model:Destroy()
	walkers[record.walkerIndex] = nil
	record.dead = true

	local wi = record.walkerIndex
	task.delay(Config.Walkers.respawnDelay, function()
		if walkers[wi] == nil then
			-- Replacement joins the BACK of the convoy queue.
			spawnWalker()
		end
	end)

	if isNew then
		local found = 0
		for _ in pairs(state.collectedIds) do
			found += 1
		end
		showToast(player, string.format("NEW DISCOVERY! %s (%d/%d)",
			Config.unitTitle(record.entry, record.mutation, record.traits), found, #Config.Brainrots))
	else
		showToast(player, string.format(
			"Caught %s from the carpet! %s",
			Config.unitTitle(record.entry, record.mutation, record.traits),
			state.baseIndex and "Bring it to your base!" or "Claim an open base first!"
		))
	end
	setHint(player, state.baseIndex and "Carry it onto YOUR island to place it" or "Stand on an open base to claim it")
end

spawnWalker = function(startZ)
	if walkerCount() >= Config.Walkers.maxAlive then
		return
	end
	local entry, mutation, traits = rollWalkerUnit()
	local model, hitbox = BrainrotModels.buildWalker(entry, mutation, traits)

	-- Find a free walker index.
	local wi = 1
	while walkers[wi] ~= nil do
		wi += 1
	end

	-- All walkers share the centre lane (x = 0), moving +z at a fixed convoy speed.
	local laneX = 0

	-- If no explicit start Z, position at the BACK of the convoy: lowest z among
	-- active walkers minus one laneSpacing. On an empty lane start at -CARPET_HALF.
	-- Reads each walker's LIVE z (the animation item's current position) so the
	-- gap stays exact even after others have advanced/wrapped.
	local z: number
	if startZ ~= nil then
		z = startZ
	else
		local lowest = -Config.CARPET_HALF
		for _, rec in pairs(walkers) do
			local lz = rec.item and rec.item.z or rec.z
			if lz < lowest then
				lowest = lz
			end
		end
		z = lowest - Config.Walkers.laneSpacing
	end
	local animItem = BrainrotModels.startWalker(model, laneX, z, Config.Walkers.convoySpeed, Config.CARPET_HALF)

	-- Position the model at its starting spot so it does not flash at origin.
	model:PivotTo(CFrame.new(laneX, Config.Walkers.spawnY, z))
	model.Parent = workspace

	local record = {
		model = model,
		entry = entry,
		mutation = mutation,
		traits = traits,
		walkerIndex = wi,
		dead = false,
		z = z,
		item = animItem,
	}
	walkers[wi] = record

	hitbox.Touched:Connect(function(hit)
		if record.dead or walkers[wi] ~= record then
			return
		end
		local player = playerFromHit(hit)
		if player == nil then
			return
		end
		local state = states[player]
		if state == nil or state.carried ~= nil then
			if state and state.carried ~= nil then
				showToast(player, "Hands full — place your catch first!")
			end
			return
		end
		record.dead = true
		catchWalker(player, record)
	end)
end

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Parade catch: buy a brainrot straight off the road parade.
-- ---------------------------------------------------------------------------

local function paradeNameToId(name)
	-- "SatoshinoCrocodilo" -> "satoshino-crocodilo"
	local out = name:sub(1, 1):lower() .. name:sub(2)
	out = out:gsub("(%u)", "-%1"):lower()
	return out
end

local function catchParade(player, model)
	local state = states[player]
	if state == nil or state.carried ~= nil then
		return
	end

	local id = paradeNameToId(model.Name)
	local entry
	for _, e in ipairs(Config.Brainrots) do
		if e.id == id then
			entry = e
			break
		end
	end
	if entry == nil then
		return
	end

	-- Already caught recently (waiting to rejoin the parade)?
	local now = os.time()
	if (model:GetAttribute("CaughtUntil") or 0) > now then
		return
	end

	-- Charge the catch price.
	local price = Config.catchPrice(entry.rarity)
	if state.cash < price then
		showToast(player, string.format("Need $%s to catch %s", fmt(price), entry.name))
		return
	end
	state.cash = state.cash - price

	local mutation = Config.rollMutation(rng)
	local traits = Config.rollTraits(rng)

	state.carried = { entry = entry, mutation = mutation, traits = traits }
	local carriedModel = BrainrotModels.buildCarried(entry, mutation, traits)
	carriedModel.Name = "Carried"
	state.carriedModel = carriedModel
	carriedModel.Parent = workspace

	local rarityColor = Config.rarity(entry.rarity).color
	if rarityIndex(entry.rarity) >= 3 then
		BrainrotModels.sparkleAt(model:GetPivot().Position, rarityColor, true)
	end

	-- Collection tracking + INDEX BONUS ($1,000 the first time a rarity tier lands).
	local isNew = state.collectedIds[entry.id] == nil
	if isNew then
		state.collectedIds[entry.id] = true
		local firstOfRarity = state.rarityCounts[entry.rarity] == nil
		state.rarityCounts[entry.rarity] = (state.rarityCounts[entry.rarity] or 0) + 1
		if firstOfRarity then
			state.cash = state.cash + 1000
			showToast(player, string.format("INDEX BONUS - first %s! +$1,000", entry.rarity))
		end
		publishCollection(player, state)
	end

	-- Hide the parade copy for a while, then it rejoins the parade.
	model:SetAttribute("CaughtUntil", now + 30)

	updateStats(player)
	showToast(player, string.format("Caught %s for $%s - bring it to your base!",
		Config.unitTitle(entry, mutation, traits), fmt(price)))
	setHint(player, "Walk onto your base to place it on a pedestal")
end

-- Wire parade ClickDetectors: visible models now, hidden ones when they rejoin.
local function wireParadeModel(obj)
	if not obj:IsA("Model") then
		return
	end
	local clicker = obj:FindFirstChildWhichIsA("ClickDetector", true)
	if clicker and not clicker:GetAttribute("Wired") then
		clicker:SetAttribute("Wired", true)
		clicker.MouseClick:Connect(function(player)
			catchParade(player, obj)
		end)
	end
end

for _, obj in ipairs(workspace:GetChildren()) do
	wireParadeModel(obj)
end
workspace.DescendantAdded:Connect(wireParadeModel)

-- Paint the catch price + income onto every parade billboard label.
local function paintParadeLabel(obj)
	if not obj:IsA("Model") then
		return
	end
	local bb = obj:FindFirstChildWhichIsA("BillboardGui", true)
	local label = bb and bb:FindFirstChildWhichIsA("TextLabel")
	if label == nil or label:GetAttribute("Priced") then
		return
	end
	local id = paradeNameToId(obj.Name)
	for _, e in ipairs(Config.Brainrots) do
		if e.id == id then
			label:SetAttribute("Priced", true)
			label.TextWrapped = true
			bb.Size = UDim2.new(0, 360, 0, 92)
			label.Text = string.format(
				"%s\n[%s]  $%s to catch  ·  $%d/s",
				e.name, e.rarity, fmt(Config.catchPrice(e.rarity)), e.rate
			)
			break
		end
	end
end

for _, obj in ipairs(workspace:GetChildren()) do
	paintParadeLabel(obj)
end
workspace.DescendantAdded:Connect(paintParadeLabel)

-- Capsules: spawn, catch, respawn
-- ---------------------------------------------------------------------------

local capsules = {} -- [padIndex] = capsule record, while one is on the pad

local function rollUnit()
	local rarity = Config.rollRarity(rng)
	local pool = {}
	for _, entry in ipairs(Config.Brainrots) do
		if entry.rarity == rarity.name then
			table.insert(pool, entry)
		end
	end
	local entry = pool[rng:NextInteger(1, #pool)]
	local mutation = Config.rollMutation(rng)
	local traits = Config.rollTraits(rng)
	return entry, mutation, traits
end

-- ---------------------------------------------------------------------------
-- Rare spawn announcements: Roblox chat + a server-wide HUD banner
-- ---------------------------------------------------------------------------

local lastRareAnnounce = 0

-- System chat line: TextChatService on a modern place, the legacy ChatService
-- otherwise. A failure here is harmless — the HUD banner still fires.
local function announceChat(text)
	local ok = pcall(function()
		local channels = game:GetService("TextChatService").TextChannels
		local system = channels and channels:FindFirstChild("RBXSystem")
		if system == nil then
			error("no system chat channel")
		end
		system:SendAsync(text)
	end)
	if ok then
		return
	end
	pcall(function()
		local chatService = game:GetService("Chat"):LoadLibrary("ChatService")
		local speaker = chatService:GetSpeaker("VaultSystem")
		if speaker == nil then
			speaker = chatService:AddSpeaker("VaultSystem")
			speaker:JoinChannel("All")
		end
		speaker:Say(text)
	end)
end

-- Rare and above announce themselves the moment they spawn. Announcements are
-- rate-limited so a busy plaza cannot flood chat; a Mythic always gets through.
local function announceRareSpawn(entry, mutation, traits)
	if rarityIndex(entry.rarity) < 3 then
		return
	end
	local now = tick()
	if entry.rarity ~= "Mythic" and now - lastRareAnnounce < Config.RareAnnounce.minInterval then
		return
	end
	lastRareAnnounce = now

	local title = Config.unitTitle(entry, mutation, traits)
	local text = string.format("★ %s SPAWN! %s has appeared in the plaza! ★",
		string.upper(entry.rarity), title)
	announceChat(text)
	ReplicatedStorage:SetAttribute("RareBanner", text)
	ReplicatedStorage:SetAttribute("RareBannerRarity", entry.rarity)
	ReplicatedStorage:SetAttribute("RareBannerAt", os.clock())
end

local spawnCapsule -- forward declaration so the catch handler can respawn later

local function catchCapsule(player, record)
	local state = states[player]
	if state == nil or state.carried ~= nil then
		return
	end

	state.carried = { entry = record.entry, mutation = record.mutation, traits = record.traits }
	local model = BrainrotModels.buildCarried(record.entry, record.mutation, record.traits)
	model.Name = "Carried"
	state.carriedModel = model
	model.Parent = workspace

	-- Sparkle burst on the pickup — small for Common/Uncommon, big and glowing
	-- for Rare and above so a good pull is impossible to miss.
	local rarityColor = Config.rarity(record.entry.rarity).color
	local bigSparkle = rarityIndex(record.entry.rarity) >= 3
	if record.model.PrimaryPart then
		BrainrotModels.sparkleAt(record.model.PrimaryPart.Position, rarityColor, bigSparkle)
	end

	-- New-discovery bookkeeping for the HUD collection panel.
	local isNew = state.collectedIds[record.entry.id] == nil
	if isNew then
		state.collectedIds[record.entry.id] = true
		state.rarityCounts[record.entry.rarity] = (state.rarityCounts[record.entry.rarity] or 0) + 1
		publishCollection(player, state)
	end

	-- Retire the pad and schedule the next capsule.
	BrainrotModels.retire(record.model)
	record.model:Destroy()
	capsules[record.padIndex] = nil
	-- Capsule spawning disabled — no respawn after a catch.
	-- task.delay(Config.Capsule.respawnTime, function()
	-- 	if capsules[record.padIndex] == nil then
	-- 		spawnCapsule(record.padIndex)
	-- 	end
	-- end)

	if isNew then
		local found = 0
		for _ in pairs(state.collectedIds) do
			found += 1
		end
		showToast(player, string.format("NEW DISCOVERY! %s (%d/%d)",
			Config.unitTitle(record.entry, record.mutation, record.traits), found, #Config.Brainrots))
	else
		showToast(player, string.format(
			"Caught %s! %s",
			Config.unitTitle(record.entry, record.mutation, record.traits),
			state.baseIndex and "Bring it to your base!" or "Claim an open base first!"
		))
	end
	setHint(player, state.baseIndex and "Carry it onto YOUR island to place it" or "Stand on an open base to claim it")
end

spawnCapsule = function(padIndex)
	local pad = world.pads[padIndex]
	if pad == nil then
		return
	end
	if capsules[padIndex] ~= nil then
		return -- a capsule is already on this pad
	end
	local entry, mutation, traits = rollUnit()
	local model = BrainrotModels.buildCapsule(entry, mutation, pad.Position + Vector3.new(0, 0.2, 0), traits)
	model.Parent = workspace

	local record = { model = model, entry = entry, mutation = mutation, traits = traits, padIndex = padIndex, dead = false }
	capsules[padIndex] = record
	announceRareSpawn(entry, mutation, traits)

	local orb = model.PrimaryPart
	orb.Touched:Connect(function(hit)
		if record.dead or capsules[padIndex] ~= record then
			return
		end
		local player = playerFromHit(hit)
		if player == nil then
			return
		end
		local state = states[player]
		if state == nil or state.carried ~= nil then
			if state and state.carried ~= nil then
				showToast(player, "Hands full — place your catch first!")
			end
			return
		end
		record.dead = true
		catchCapsule(player, record)
	end)
end

-- Return a carried unit to a pad after a sweep or a death (any pad, at random).
local function dropCarried(player, reason)
	local state = states[player]
	if state == nil or state.carried == nil then
		return
	end
	BrainrotModels.retire(state.carriedModel)
	state.carriedModel:Destroy()
	state.carriedModel = nil
	state.carried = nil
	updateStats(player)

	-- Capsule spawning disabled — no capsule seeded after a drop.
	-- task.delay(3, function()
	-- 	for index = 1, Config.Capsule.padCount do
	-- 		if capsules[index] == nil then
	-- 			spawnCapsule(index)
	-- 			break
	-- 		end
	-- 	end
	-- end)

	if reason == "swept" then
		showToast(player, "SWEPT AWAY! You dropped your catch!")
	elseif reason == "died" then
		showToast(player, "You went down — your catch got away!")
	end
end

-- ---------------------------------------------------------------------------
-- Bases: claim, place, upgrade visuals
-- ---------------------------------------------------------------------------

local function baseCenter(base)
	return Vector3.new(base:GetAttribute("CenterX"), 0, base:GetAttribute("CenterZ"))
end

local function unlockPedestalVisual(base, slot)
	local pedestal = base:FindFirstChild("Pedestal" .. slot)
	if pedestal then
		pedestal.Color = Color3.fromRGB(115, 120, 135)
		pedestal.Material = Enum.Material.Slate
	end
end

local function resetPedestalVisual(base, slot, slotsUnlocked)
	local pedestal = base:FindFirstChild("Pedestal" .. slot)
	if pedestal then
		local unlocked = slot <= (slotsUnlocked or Config.Economy.startSlots)
		pedestal.Color = unlocked and Color3.fromRGB(115, 120, 135) or Color3.fromRGB(58, 60, 70)
		pedestal.Material = Enum.Material.Slate
	end
end

local function placeUnit(player, base)
	local state = states[player]
	if state.carried == nil then
		return
	end

	-- First free pedestal within the bought slot count.
	local slot
	for index = 1, state.slots do
		if state.pedestals[index] == nil then
			slot = index
			break
		end
	end
	if slot == nil then
		showToast(player, "BASE FULL — buy more slots in the shop!")
		return
	end

	local pedestal = base:FindFirstChild("Pedestal" .. slot)
	if pedestal == nil then
		return
	end

	local carried = state.carried
	local model = BrainrotModels.buildPlaced(carried.entry, carried.mutation, carried.traits)
	-- Pedestal top sits 0.9 above its center; lift the unit so its feet land there.
	model:PivotTo(CFrame.new(pedestal.Position + Vector3.new(0, 3.0, 0)))
	model.Parent = workspace
	BrainrotModels.startSway(model)

	-- Tint the pedestal with the unit's rarity and sparkle rare placements.
	local rarityColor = Config.rarity(carried.entry.rarity).color
	pedestal.Color = rarityColor
	pedestal.Material = Enum.Material.SmoothPlastic
	if rarityIndex(carried.entry.rarity) >= 3 then
		BrainrotModels.sparkleAt(pedestal.Position + Vector3.new(0, 2, 0), rarityColor, true)
	end

	state.pedestals[slot] = { entry = carried.entry, mutation = carried.mutation, traits = carried.traits, model = model }
	BrainrotModels.retire(state.carriedModel)
	state.carriedModel:Destroy()
	state.carried = nil

	updateStats(player)
	local rate = Config.unitIncome(carried.entry, carried.mutation, carried.traits)
	showToast(player, string.format("Placed %s — earning $%d/s",
		Config.unitTitle(carried.entry, carried.mutation, carried.traits), rate))
	setHint(player, "Catch another brainrot, or open the shop with your cash")
end

local function claimBase(player, base)
	local state = states[player]
	local index = base:GetAttribute("Index")
	local owner = base:GetAttribute("OwnerUserId")

	if owner ~= nil and owner ~= player.UserId then
		showToast(player, "That base is taken!")
		return
	end
	if state.baseIndex ~= nil and state.baseIndex ~= index then
		showToast(player, "You already claimed a base")
		return
	end

	base:SetAttribute("OwnerUserId", player.UserId)
	state.baseIndex = index
	state.baseModel = base
	WorldBuilder.setBaseSign(base, player.DisplayName .. "'s VAULT", "SAFE ZONE · place your brainrots here", Color3.fromRGB(120, 210, 255))
	showToast(player, "Base claimed! Now click a brainrot on the road!")
	setHint(player, state.carried and "Step onto your island to place your catch" or "Click a brainrot walking on the road to catch it!")
	updateStats(player)
end

-- ---------------------------------------------------------------------------
-- Base lock: the robbery alarm
-- ---------------------------------------------------------------------------

local LOCK_RED = Color3.fromRGB(255, 82, 82)
local SAFE_BLUE = Color3.fromRGB(120, 210, 255)

-- The lock runs Config.Lock.duration, +10 s for every rebirth already earned.
local function lockSeconds(state)
	return Config.Lock.duration + state.rebirths * Config.Lock.perRebirth
end

-- Sound the alarm on the owner's base: red locked sign with a live countdown,
-- plus the HUD attributes the client draws "YOUR BASE IS BEING ROBBED" from.
local function startLock(owner, state, robber)
	if state.baseIndex == nil or state.baseModel == nil then
		return
	end
	if state.lockEndsAt then
		-- Already sounding: never stretch the timer, but remember a real
		-- thief if the lock was started by the wave and nobody is named yet.
		if state.lockRobber == nil and robber ~= nil then
			state.lockRobber = robber
		end
		return
	end
	local seconds = lockSeconds(state)
	state.lockEndsAt = tick() + seconds
	state.lockRobber = robber
	WorldBuilder.setBaseSign(state.baseModel, "BASE LOCKED!", string.format("ROBBERY IN %ds", seconds), LOCK_RED)
	owner:SetAttribute("Robbed", true)
	owner:SetAttribute("RobbedSeconds", seconds)
	showToast(owner, robber and (robber.DisplayName .. " is on your base!") or "Your vault is exposed — lock engaged!")
	setHint(owner, "Get back to your base — defend your brainrots!")
end

-- Countdown tick: repaint the locked sign, and when time runs out resolve the
-- robbery — the thief takes a character, or a cut of cash if their hands are full.
local function finishLock(owner, state)
	local robber = state.lockRobber
	state.lockEndsAt = nil
	state.lockRobber = nil
	WorldBuilder.setBaseSign(state.baseModel, owner.DisplayName .. "'s VAULT", "SAFE ZONE · place your brainrots here", SAFE_BLUE)
	owner:SetAttribute("Robbed", false)
	owner:SetAttribute("RobbedSeconds", 0)

	local thiefState = robber and states[robber]
	if thiefState == nil then
		showToast(owner, "Lock held — nobody got into your vault")
		return
	end

	local occupied = {}
	for slot in pairs(state.pedestals) do
		table.insert(occupied, slot)
	end
	if #occupied > 0 and thiefState.carried == nil and robber.Character then
		-- Hands free: the thief carries one of the owner's characters away.
		local slot = occupied[rng:NextInteger(1, #occupied)]
		local unit = state.pedestals[slot]
		state.pedestals[slot] = nil
		BrainrotModels.retire(unit.model)
		unit.model:Destroy()
		resetPedestalVisual(state.baseModel, slot, state.slots)

		thiefState.carried = { entry = unit.entry, mutation = unit.mutation, traits = unit.traits }
		local stolen = BrainrotModels.buildCarried(unit.entry, unit.mutation, unit.traits)
		stolen.Name = "Carried"
		stolen.Parent = workspace
		thiefState.carriedModel = stolen

		showToast(owner, string.format("ROBBED! %s stole your %s", robber.DisplayName, unit.entry.name))
		showToast(robber, string.format("You stole %s from %s!",
			Config.unitTitle(unit.entry, unit.mutation, unit.traits), owner.DisplayName))
		setHint(robber, "Bring it to YOUR base to keep it")
	else
		-- Hands full (or nothing placed): a cash cut instead of a character.
		local taken = math.floor(state.cash * Config.Lock.stealCashFraction + 0.5)
		if taken > 0 then
			state.cash -= taken
			thiefState.cash += taken
			showToast(owner, string.format("ROBBED! %s got away with $%s", robber.DisplayName, fmt(taken)))
			showToast(robber, string.format("You got $%s from %s!", fmt(taken), owner.DisplayName))
		else
			showToast(owner, "Lock held — nobody got into your vault")
		end
	end
	updateStats(owner)
	updateStats(robber)
end

local function onBaseTouched(base, hit)
	local player = playerFromHit(hit)
	if player == nil or states[player] == nil then
		return
	end
	local state = states[player]
	local index = base:GetAttribute("Index")
	local owner = base:GetAttribute("OwnerUserId")

	-- Someone else steps on a claimed island: their base is being robbed now.
	if owner ~= nil and owner ~= player.UserId then
		local ownerPlayer = Players:GetPlayerByUserId(owner)
		local ownerState = ownerPlayer and states[ownerPlayer]
		if ownerState and ownerState.baseIndex == index then
			startLock(ownerPlayer, ownerState, player)
		end
		return
	end

	if state.baseIndex == nil and (owner == nil or owner == player.UserId) then
		claimBase(player, base)
		return
	end
	if state.baseIndex == index and state.carried ~= nil then
		placeUnit(player, base)
	end
end

-- ---------------------------------------------------------------------------
-- Shop actions
-- ---------------------------------------------------------------------------

local function onShopAction(player, action)
	local state = states[player]
	if state == nil or type(action) ~= "string" then
		return
	end

	-- The HUD's UPGRADE button sends "upgrade"; it buys the income boost.
	if action == "upgrade" then
		action = "multiplier"
	end

	if action == "collect" then
		-- The HUD COLLECT button: place the carried catch from anywhere on
		-- your own base's economy (server still validates slots and ownership).
		if state.carried == nil then
			showToast(player, "Nothing to catch — click a brainrot on the road!")
			return
		end
		if state.baseIndex == nil or state.baseModel == nil then
			showToast(player, "Claim an open base first!")
			return
		end
		placeUnit(player, state.baseModel)

	elseif action == "slots" then
		if state.slots >= Config.Economy.maxSlots then
			showToast(player, "All pedestal slots unlocked!")
			return
		end
		local cost = Config.slotCost(state.slots)
		if state.cash < cost then
			showToast(player, "Not enough cash for another slot")
			return
		end
		state.cash -= cost
		state.slots += 1
		if state.baseModel then
			unlockPedestalVisual(state.baseModel, state.slots)
		end
		showToast(player, string.format("Slot %d unlocked! ($%s)", state.slots, fmt(cost)))

	elseif action == "multiplier" then
		if state.multiplierLevel >= Config.Economy.maxMultiplierLevel then
			showToast(player, "Multiplier maxed out!")
			return
		end
		local cost = Config.multiplierCost(state.multiplierLevel)
		if state.cash < cost then
			showToast(player, "Not enough cash for the multiplier")
			return
		end
		state.cash -= cost
		state.multiplierLevel += 1
		showToast(player, string.format("Income x%.1f! ($%s)", Config.incomeMultiplier(state.multiplierLevel, state.rebirths), fmt(cost)))

	elseif action == "speed" then
		if state.speedLevel >= Config.Economy.maxSpeedLevel then
			showToast(player, "Speed maxed out!")
			return
		end
		local cost = Config.speedCost(state.speedLevel)
		if state.cash < cost then
			showToast(player, "Not enough cash for speed")
			return
		end
		state.cash -= cost
		state.speedLevel += 1
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Config.Economy.baseWalkSpeed + state.speedLevel * Config.Economy.speedPerLevel
		end
		showToast(player, string.format("Speed boost! ($%s)", fmt(cost)))

	elseif action == "rebirth" then
		local requirement = Config.rebirthRequirement(state.rebirths)
		local unitNeed = Config.rebirthUnitRequirement(state.rebirths)
		local placed = 0
		for _ in pairs(state.pedestals) do
			placed += 1
		end
		if state.lifetime < requirement then
			showToast(player, string.format("Need $%s lifetime cash to rebirth", fmt(requirement)))
			return
		end
		if placed < unitNeed then
			showToast(player, string.format("Rebirth needs %d characters placed — you have %d", unitNeed, placed))
			return
		end
		-- Rebirth: wipe placed units and cash, keep upgrades, gain a permanent
		-- boost plus extra base slots (the new pedestals light up right away).
		for slot, unit in pairs(state.pedestals) do
			BrainrotModels.retire(unit.model)
			unit.model:Destroy()
			if state.baseModel then
				resetPedestalVisual(state.baseModel, slot, state.slots)
			end
		end
		state.pedestals = {}
		state.cash = 0
		state.rebirths += 1
		local slotsBefore = state.slots
		state.slots = math.min(Config.Economy.maxSlots, state.slots + Config.Economy.rebirthSlotsBonus)
		if state.baseModel then
			for slot = slotsBefore + 1, state.slots do
				unlockPedestalVisual(state.baseModel, slot)
			end
		end
		local gained = state.slots - slotsBefore
		showToast(player, gained > 0
			and string.format("REBIRTH %d! Income boosted · +%d base slots", state.rebirths, gained)
			or string.format("REBIRTH %d! Income permanently boosted", state.rebirths))
		setHint(player, "Your vault reset — rebuild it stronger!")
	end

	updateStats(player)
end

shopRemote.OnServerEvent:Connect(onShopAction)

-- ---------------------------------------------------------------------------
-- Tsunami wiring
-- ---------------------------------------------------------------------------

Wave.start({
	-- Bases are at ground level so safety is a region check.
	isSafe = function(character)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root == nil then
			return false
		end
		local px, pz = root.Position.X, root.Position.Z
		for _, base in ipairs(world.bases) do
			local cx, cz = base:GetAttribute("CenterX"), base:GetAttribute("CenterZ")
			if cx and cz and math.abs(px - cx) < 9 and math.abs(pz - cz) < 9 then
				return true
			end
		end
		return false
	end,

	onSwept = function(player, root)
		local state = states[player]
		dropCarried(player, "swept")

		-- Sweep them home: onto their base if they have one, else spawn.
		local target
		if state and state.baseModel then
			local center = baseCenter(state.baseModel)
			target = CFrame.new(center + Vector3.new(0, 5, 0))
				* CFrame.Angles(0, math.rad(180), 0)
		else
			target = CFrame.new(0, 6, 0)
		end
		root.CFrame = target
		if state then
			setHint(player, "The wave swept you home — your catch got away")
			startLock(player, state, nil)
		end
	end,

	onWarning = function(_secondsLeft)
		-- The HUD reads WaveState/WaveCountdown itself; nothing to send here.
	end,
})

-- ---------------------------------------------------------------------------
-- Players: join, spawn, leave
-- ---------------------------------------------------------------------------

local function onCharacterAdded(player, character)
	local state = states[player]
	if state == nil then
		return
	end
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = Config.Economy.baseWalkSpeed + state.speedLevel * Config.Economy.speedPerLevel
	humanoid.Died:Connect(function()
		dropCarried(player, "died")
	end)
end

local function onPlayerAdded(player)
	if states[player] then
		return -- already set up (PlayerAdded and the startup loop can both fire)
	end
	local state = {
		cash = Config.Economy.startCash,
		cashPerSecond = 0,
		lifetime = 0,
		slots = Config.Economy.startSlots,
		multiplierLevel = Config.Economy.startMultiplierLevel,
		speedLevel = Config.Economy.startSpeedLevel,
		rebirths = 0,
		baseIndex = nil,
		baseModel = nil,
		lockEndsAt = nil,
		lockRobber = nil,
		carried = nil,
		carriedModel = nil,
		pedestals = {},
		collectedIds = {},
		rarityCounts = {},
	}
	states[player] = state

	-- The player list shows cash; the HUD reads the richer attributes.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Value = 0
	cashValue.Parent = leaderstats
	leaderstats.Parent = player

	player:SetAttribute("Cash", 0)
	player:SetAttribute("CashPerSecond", 0)
	player:SetAttribute("Slots", state.slots)
	player:SetAttribute("MultiplierLevel", 0)
	player:SetAttribute("SpeedLevel", 0)
	player:SetAttribute("Rebirths", 0)
	player:SetAttribute("Lifetime", 0)
	player:SetAttribute("Robbed", false)
	player:SetAttribute("RobbedSeconds", 0)
	player:SetAttribute("UnitsPlaced", 0)
	player:SetAttribute("UnitList", "")
	player:SetAttribute("CarryInfo", "")
	player:SetAttribute("CollectionCount", 0)
	player:SetAttribute("CollectionMax", #Config.Brainrots)
	player:SetAttribute("RarityProgress", "")
	publishCollection(player, state)
	setHint(player, "1) Claim an open base  2) Click a brainrot on the road  3) Bring it home")

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function onPlayerRemoving(player)
	local state = states[player]
	if state then
		if state.carriedModel then
			BrainrotModels.retire(state.carriedModel)
			state.carriedModel:Destroy()
		end
		for slot, unit in pairs(state.pedestals) do
			BrainrotModels.retire(unit.model)
			unit.model:Destroy()
			if state.baseModel then
				resetPedestalVisual(state.baseModel, slot, state.slots)
			end
		end
		if state.baseModel and state.baseIndex then
			state.baseModel:SetAttribute("OwnerUserId", nil)
			WorldBuilder.setBaseSign(state.baseModel, "BASE " .. state.baseIndex .. " — OPEN", "stand on it to claim", Color3.fromRGB(120, 230, 140))
		end
	end
	states[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

-- ---------------------------------------------------------------------------
-- Economy tick: one credit per second for every placed unit
-- ---------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)
		for player, state in pairs(states) do
			local income = state.cashPerSecond
			if income > 0 then
				state.cash += income
				state.lifetime += income
				updateStats(player)
			end

			-- Robbery lock countdown: repaint the sign every second, resolve
			-- the robbery when it hits zero.
			if state.lockEndsAt then
				local remaining = math.ceil(state.lockEndsAt - tick())
				if remaining <= 0 then
					finishLock(player, state)
				else
					player:SetAttribute("RobbedSeconds", remaining)
					WorldBuilder.setBaseSign(state.baseModel, "BASE LOCKED!",
						string.format("ROBBERY IN %ds", remaining), LOCK_RED)
				end
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Carried-unit follow: one loop keeps every catch floating over its holder
-- ---------------------------------------------------------------------------

RunService.Heartbeat:Connect(function()
	local now = tick()
	for player, state in pairs(states) do
		local model = state.carriedModel
		if model and model.Parent then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local bob = math.sin(now * 5) * 0.2
				model:PivotTo(
					CFrame.new(root.Position + Vector3.new(0, Config.Capsule.carryHeight + bob, 0))
						* CFrame.Angles(0, math.sin(now * 1.4) * 0.35, 0)
				)
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Kick it off: walkers on the carpet, capsules on every pad, bases listening
-- ---------------------------------------------------------------------------

-- Seed the carpet with walkers so the lane is busy from the first frame.
-- Populate minAlive right away, each one laneSpacing studs behind the previous,
-- so the convoy starts evenly staggered instead of a random pile-up.
for i = 1, Config.Walkers.minAlive do
	local z = -Config.CARPET_HALF - (i - 1) * Config.Walkers.laneSpacing
	spawnWalker(z)
end

-- Capsule spawning disabled — no characters appear on the map.
-- for index = 1, Config.Capsule.padCount do
-- 	spawnCapsule(index)
-- end

if world and world.bases then
	for _, base in ipairs(world.bases) do
		if base then
			local island = base:FindFirstChild("Island") or base:FindFirstChild("Floor")
			if island then
				island.Touched:Connect(function(hit)
					onBaseTouched(base, hit)
				end)
			end
		end
	end
end

print("Brainrot Vault Tycoon server online")
