-- Wave: the tsunami threat. On a timer it raises a red-alert countdown, then
-- sweeps a wall of water straight across the arena. Anyone caught off a base
-- island is swept home (and loses whatever they were carrying), so a player
-- with a fresh catch has to dash back to their base before the water arrives.
-- Wave state is published as attributes on ReplicatedStorage for the HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)

local Wave = {}

local ARENA_HALF = 112
local TRAVEL = ARENA_HALF * 2 + 18

local directions = {
	{ axis = "X", sign = 1 },
	{ axis = "X", sign = -1 },
	{ axis = "Z", sign = 1 },
	{ axis = "Z", sign = -1 },
}

local function setState(state, countdown)
	ReplicatedStorage:SetAttribute("WaveState", state)
	ReplicatedStorage:SetAttribute("WaveCountdown", countdown or 0)
end

local function buildWall(direction)
	local wall = Instance.new("Model")
	wall.Name = "Tsunami"

	local water = Instance.new("Part")
	water.Name = "Water"
	water.Anchored = true
	water.CanCollide = false
	water.CanQuery = false
	water.Size = direction.axis == "X"
		and Vector3.new(8, Config.Wave.waterHeight, TRAVEL)
		or Vector3.new(TRAVEL, Config.Wave.waterHeight, 8)
	water.Color = Color3.fromRGB(60, 165, 255)
	water.Material = Enum.Material.Neon
	water.Transparency = 0.5
	water.Parent = wall

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.Size = direction.axis == "X"
		and Vector3.new(3, Config.Wave.waterHeight, TRAVEL)
		or Vector3.new(TRAVEL, Config.Wave.waterHeight, 3)
	core.Color = Color3.fromRGB(30, 90, 200)
	core.Material = Enum.Material.Glass
	core.Transparency = 0.35
	core.Parent = wall

	local foam = Instance.new("Part")
	foam.Name = "Foam"
	foam.Anchored = true
	foam.CanCollide = false
	foam.CanQuery = false
	foam.Size = direction.axis == "X"
		and Vector3.new(9, 1.6, TRAVEL)
		or Vector3.new(TRAVEL, 1.6, 9)
	foam.Color = Color3.fromRGB(240, 250, 255)
	foam.Material = Enum.Material.Neon
	foam.Transparency = 0.1
	foam.Parent = wall

	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(210, 235, 255))
	spray.Lifetime = NumberRange.new(0.6, 1.2)
	spray.Rate = 140
	spray.Speed = NumberRange.new(5, 12)
	spray.SpreadAngle = Vector2.new(30, 30)
	spray.Size = NumberSequence.new(1.8)
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.Parent = foam

	wall.Parent = workspace
	return wall, water
end

-- Is this character standing somewhere the water cannot reach (a base island)?
-- `deps.isSafe` is supplied by the game script, which knows the islands.
local function sweepCharacter(character, deps)
	local player = Players:GetPlayerFromCharacter(character)
	if player == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	if deps.isSafe(character) then
		return
	end
	deps.onSwept(player, root)
end

-- The warning countdown, published a few times a second for the HUD.
local function runWarning(deps)
	for remaining = Config.Wave.warning, 0, -1 do
		setState("warning", remaining)
		deps.onWarning(remaining)
		task.wait(1)
	end
end

-- Move the wall from one side of the arena to the other, sweeping anyone it meets.
local function runSweep(direction, deps)
	local wall, water = buildWall(direction)
	local startTime = tick()
	local swept = {}
	local alongSign = direction.sign

	while true do
		local progress = (tick() - startTime) / Config.Wave.sweep
		if progress >= 1 then
			break
		end
		local travel = -TRAVEL / 2 + progress * TRAVEL
		travel *= alongSign
		if direction.axis == "X" then
			wall:PivotTo(CFrame.new(travel, Config.Wave.waterHeight / 2, 0))
		else
			wall:PivotTo(CFrame.new(0, Config.Wave.waterHeight / 2, travel))
		end
		setState("sweep", Config.Wave.sweep - (tick() - startTime))

		-- Who is in the water this frame?
		local wallPos = water.Position
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character and swept[player] == nil then
				local root = character:FindFirstChild("HumanoidRootPart")
				if root then
					local pos = root.Position
					local belowSurface = pos.Y < Config.Wave.waterHeight
					local inSpan
					local inTravel
					if direction.axis == "X" then
						inSpan = math.abs(pos.Z) < TRAVEL / 2
						inTravel = math.abs(pos.X - wallPos.X) < 5
					else
						inSpan = math.abs(pos.X) < TRAVEL / 2
						inTravel = math.abs(pos.Z - wallPos.Z) < 5
					end
					if belowSurface and inSpan and inTravel then
						swept[player] = true
						sweepCharacter(character, deps)
					end
				end
			end
		end

		RunService.Heartbeat:Wait()
	end

	wall:Destroy()
end

-- Start the endless calm/warning/sweep cycle. Call once at server start.
-- deps = { isSafe(character), onSwept(player, root), onWarning(secondsLeft) }
function Wave.start(deps)
	setState("calm", Config.Wave.firstDelay)

	task.spawn(function()
		task.wait(Config.Wave.firstDelay)
		while true do
			runWarning(deps)
			local direction = directions[math.random(#directions)]
			runSweep(direction, deps)
			setState("calm", Config.Wave.interval)
			for remaining = Config.Wave.interval, 0, -1 do
				setState("calm", remaining)
				task.wait(1)
			end
		end
	end)
end

return Wave
