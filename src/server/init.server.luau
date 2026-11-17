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
local world = WorldBuilder.build()

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

-- Total placed income per second, before the shop/rebirth multiplier.
local function placedIncome(state)
	local total = 0
	for _, unit in pairs(state.pedestals) do
		total += math.floor(unit.entry.rate * unit.mutation.multiplier + 0.5)
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
		local rate = math.floor(carried.entry.rate * carried.mutation.multiplier + 0.5)
		player:SetAttribute("CarryInfo", string.format(
			"%s%s · %s · $%d/s",
			carried.mutation.name ~= "" and (carried.mutation.name .. " ") or "",
			carried.entry.name,
			carried.entry.rarity,
			rate
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
	return entry, mutation
end

local spawnCapsule -- forward declaration so the catch handler can respawn later

local function catchCapsule(player, record)
	local state = states[player]
	if state == nil or state.carried ~= nil then
		return
	end

	state.carried = { entry = record.entry, mutation = record.mutation }
	local model = BrainrotModels.buildCarried(record.entry, record.mutation)
	model.Name = "Carried"
	state.carriedModel = model
	model.Parent = workspace

	-- Retire the pad and schedule the next capsule.
	BrainrotModels.retire(record.model)
	record.model:Destroy()
	capsules[record.padIndex] = nil
	task.delay(Config.Capsule.respawnTime, function()
		if capsules[record.padIndex] == nil then
			spawnCapsule(record.padIndex)
		end
	end)

	showToast(player, string.format(
		"Caught %s! %s",
		record.entry.name,
		state.baseIndex and "Bring it to your base!" or "Claim an open base first!"
	))
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
	local entry, mutation = rollUnit()
	local model = BrainrotModels.buildCapsule(entry, mutation, pad.Position + Vector3.new(0, 0.2, 0))
	model.Parent = workspace

	local record = { model = model, entry = entry, mutation = mutation, padIndex = padIndex, dead = false }
	capsules[padIndex] = record

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

	-- Put a fresh capsule on a free pad so nothing is lost.
	task.delay(3, function()
		for index = 1, Config.Capsule.padCount do
			if capsules[index] == nil then
				spawnCapsule(index)
				break
			end
		end
	end)

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
		pedestal.Color = Color3.fromRGB(70, 70, 80)
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
	local model = BrainrotModels.buildPlaced(carried.entry, carried.mutation)
	-- Pedestal top sits 0.9 above its center; lift the unit so its feet land there.
	model:PivotTo(CFrame.new(pedestal.Position + Vector3.new(0, 3.0, 0)))
	model.Parent = workspace
	BrainrotModels.startSway(model)

	state.pedestals[slot] = { entry = carried.entry, mutation = carried.mutation, model = model }
	BrainrotModels.retire(state.carriedModel)
	state.carriedModel:Destroy()
	state.carried = nil

	updateStats(player)
	local rate = math.floor(carried.entry.rate * carried.mutation.multiplier + 0.5)
	showToast(player, string.format("Placed %s — earning $%d/s", carried.entry.name, rate))
	setHint(player, "Catch another capsule, or open the shop with your cash")
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
	WorldBuilder.setBaseSign(base, player.DisplayName .. "'s VAULT", "place your brainrots here", Color3.fromRGB(120, 200, 255))
	showToast(player, "Base claimed! Now catch a capsule")
	setHint(player, state.carried and "Step onto your island to place your catch" or "Touch a glowing capsule to catch a brainrot")
	updateStats(player)
end

local function onBaseTouched(base, hit)
	local player = playerFromHit(hit)
	if player == nil or states[player] == nil then
		return
	end
	local state = states[player]
	local index = base:GetAttribute("Index")
	local owner = base:GetAttribute("OwnerUserId")

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

	if action == "slots" then
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
		if state.lifetime < requirement then
			showToast(player, string.format("Need $%s lifetime cash to rebirth", fmt(requirement)))
			return
		end
		-- Rebirth: wipe placed units and cash, keep upgrades, gain a permanent boost.
		for _, unit in pairs(state.pedestals) do
			BrainrotModels.retire(unit.model)
			unit.model:Destroy()
		end
		state.pedestals = {}
		state.cash = 0
		state.rebirths += 1
		showToast(player, string.format("REBIRTH %d! Income permanently boosted", state.rebirths))
		setHint(player, "Your vault reset — rebuild it stronger!")
	end

	updateStats(player)
end

shopRemote.OnServerEvent:Connect(onShopAction)

-- ---------------------------------------------------------------------------
-- Tsunami wiring
-- ---------------------------------------------------------------------------

Wave.start({
	-- Anyone at or above the water line (on an island, or a lucky jump) is safe.
	isSafe = function(character)
		local root = character:FindFirstChild("HumanoidRootPart")
		return root ~= nil and root.Position.Y >= Config.Wave.waterHeight
	end,

	onSwept = function(player, root)
		local state = states[player]
		dropCarried(player, "swept")

		-- Sweep them home: onto their island if they have one, else spawn.
		local target
		if state and state.baseModel then
			local center = baseCenter(state.baseModel)
			target = CFrame.new(center + Vector3.new(0, state.baseModel:GetAttribute("TopY") + 4, 0))
				* CFrame.Angles(0, math.rad(180), 0)
		else
			target = CFrame.new(0, 6, 0)
		end
		root.CFrame = target
		if state then
			setHint(player, "The wave swept you home — your catch got away")
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
		carried = nil,
		carriedModel = nil,
		pedestals = {},
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
	player:SetAttribute("UnitsPlaced", 0)
	player:SetAttribute("UnitList", "")
	player:SetAttribute("CarryInfo", "")
	setHint(player, "1) Claim an open base  2) Catch a capsule  3) Bring it home")

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
		for _, unit in pairs(state.pedestals) do
			BrainrotModels.retire(unit.model)
			unit.model:Destroy()
		end
		if state.baseModel then
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
-- Kick it off: capsules on every pad, bases listening for claims
-- ---------------------------------------------------------------------------

for index = 1, Config.Capsule.padCount do
	spawnCapsule(index)
end

for _, base in ipairs(world.bases) do
	local island = base:FindFirstChild("Island")
	island.Touched:Connect(function(hit)
		onBaseTouched(base, hit)
	end)
end

print("Brainrot Vault Tycoon server online")
