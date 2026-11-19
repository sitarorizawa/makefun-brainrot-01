-- WorldBuilder: Step 1 — minimal scaffold.
-- Builds ONLY a flat green island, an ocean plane beneath it, and one straight
-- asphalt road down the center (north to south). Everything else returns empty.
--
-- Interface init.server.luau depends on:
--   build() -> { pads = array<Part>, bases = array<Model> }
--   setBaseSign(model, title, subtitle, color)
--   buildSpawnPad(index) -> Part

local WorldBuilder = {}

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local ISLAND_SIZE = 300
local OCEAN_SIZE = 700
local ROAD_WIDTH = 24
local ROAD_HALF = 150 -- road spans z = -150 .. +150

-- ---------------------------------------------------------------------------
-- Colour palette
-- ---------------------------------------------------------------------------

local GRASS = Color3.fromRGB(80, 180, 70)
local OCEAN = Color3.fromRGB(60, 160, 220)
local ASPHALT = Color3.fromRGB(55, 55, 65)
local PATH = Color3.fromRGB(100, 200, 80)
local YELLOW_LINE = Color3.fromRGB(255, 220, 40)

-- ---------------------------------------------------------------------------
-- Part helper
-- ---------------------------------------------------------------------------

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	for key, value in pairs(props) do
		p[key] = value
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Lighting: no custom setup.
-- ---------------------------------------------------------------------------

local function setupLighting()
	-- Intentionally empty — use Roblox defaults.
end

-- ---------------------------------------------------------------------------
-- Ground: 10x10 grid of 30x30 Plastic tiles, 300x300 total, centered at
-- origin, Y=0. Each tile is small enough to show visible studs.
-- ---------------------------------------------------------------------------

local function buildGround()
	local m = Instance.new("Model")
	m.Name = "Ground"

	for x = -150, 120, 30 do
		for z = -150, 120, 30 do
			local tile = part({
				Name = "Tile",
				Size = Vector3.new(30, 0.4, 30),
				Color = GRASS,
				Material = Enum.Material.Plastic,
			})
			tile.TopSurface = Enum.SurfaceType.Studs
			tile.CFrame = CFrame.new(x + 15, 0, z + 15)
			tile.Anchored = true
			tile.TopSurface = Enum.SurfaceType.Studs
			local tex = Instance.new("Texture")
			tex.Texture = "rbxassetid://617517142"
			tex.Face = Enum.NormalId.Top
			tex.StudsPerTileU = 4
			tex.StudsPerTileV = 4
			tex.Parent = tile
			tile.CanCollide = true
			tile.Parent = m
		end
	end

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Ocean: blue plane under the island at Y=-3.
-- ---------------------------------------------------------------------------

local function buildOcean()
	local water = part({
		Name = "Ocean",
		Size = Vector3.new(OCEAN_SIZE, 0.2, OCEAN_SIZE),
		Color = OCEAN,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.3,
	})
	water.CFrame = CFrame.new(0, -3, 0)
	water.Anchored = true
	water.CanCollide = false
	water.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Cliffs: reddish-brown brick walls at the horizon, varying heights, forming a
-- segmented enclosure around the island perimeter. 16 cliffs, evenly spaced
-- with jitter, seeded for determinism.
-- ---------------------------------------------------------------------------

local BRICK_COLOR = Color3.fromRGB(140, 80, 60)

-- size buckets: { wideMin, wideMax, tallMin, tallMax, deepMin, deepMax }
local CLIFF_BUCKETS = {
	{ 35, 55, 30, 50, 25, 50 }, -- BIG: dominate the horizon
	{ 20, 40, 20, 35, 15, 30 }, -- MEDIUM
	{ 10, 20, 12, 25, 10, 20 }, -- SMALL
}

local function buildCliffs()
	local m = Instance.new("Model")
	m.Name = "Cliffs"

	local rng = Random.new(42)
	local CLUSTER_COUNT = 16

	-- 5 BIG, 6 MEDIUM, 5 SMALL = 16 cliffs.
	local bucketOrder = {}
	for _ = 1, 5 do table.insert(bucketOrder, 1) end
	for _ = 1, 6 do table.insert(bucketOrder, 2) end
	for _ = 1, 5 do table.insert(bucketOrder, 3) end

	-- 5 cliffs will be WedgeParts for shape variety
	local wedgeSet = { [2] = true, [5] = true, [8] = true, [11] = true, [14] = true }

	-- Evenly distributed base angles with jitter, skipping road zone.
	local baseAngle = math.pi * 2 / CLUSTER_COUNT -- ~22.5° spacing
	for i, bucketIndex in ipairs(bucketOrder) do
		local bucket = CLIFF_BUCKETS[bucketIndex]

		local angle
		for _ = 1, 50 do
			local a = (i - 1) * baseAngle + rng:NextNumber(-math.rad(5), math.rad(5))
			a = a % (math.pi * 2)
			local nearNorth = math.abs(a) < math.rad(15) or math.abs(a - math.pi * 2) < math.rad(15)
			local nearSouth = math.abs(a - math.pi) < math.rad(15)
			if not nearNorth and not nearSouth then
				angle = a
				break
			end
		end
		angle = angle or rng:NextNumber(math.rad(30), math.rad(60))

		local radius = rng:NextNumber(105, 135)
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius

		local wide = rng:NextNumber(bucket[1], bucket[2])
		local tall = rng:NextNumber(bucket[3], bucket[4])
		local deep = rng:NextNumber(bucket[5], bucket[6])

		local yRot = rng:NextNumber(0, math.pi * 2)

		local useWedge = wedgeSet[i] == true
		local cliff
		if useWedge then
			cliff = Instance.new("WedgePart")
		else
			cliff = Instance.new("Part")
		end
		cliff.Name = "Cliff" .. tostring(i)
		cliff.Size = Vector3.new(wide, tall, deep)
		cliff.Color = BRICK_COLOR
		cliff.Material = Enum.Material.Brick
		cliff.TopSurface = Enum.SurfaceType.Smooth
		cliff.BottomSurface = Enum.SurfaceType.Smooth
		cliff.Anchored = true
		cliff.CanCollide = true

		-- Bottom sits at Y=0, so center is at height/2.
		local pos = Vector3.new(x, tall / 2, z)
		local cf = CFrame.new(pos) * CFrame.Angles(0, yRot, 0)

		-- WedgeParts face inward toward the island center.
		if useWedge then
			local toCenter = CFrame.new(pos, Vector3.new(0, pos.Y, 0))
			cf = toCenter * CFrame.Angles(0, yRot, 0)
		end

		cliff.CFrame = cf
		cliff.Parent = m
	end

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Spawn: dark green Plastic baseplate, 30x30, 0.5 thick, at map center.
-- ---------------------------------------------------------------------------

local function buildSpawnArea()
	local m = Instance.new("Model")
	m.Name = "SpawnArea"

	local platform = part({
		Name = "SpawnPlatform",
		Size = Vector3.new(30, 0.5, 30),
		Color = Color3.fromRGB(50, 140, 50),
		Material = Enum.Material.Plastic,
	})
	platform.TopSurface = Enum.SurfaceType.Studs
	platform.CFrame = CFrame.new(0, 0.2, 0)
	platform.Anchored = true
	platform.TopSurface = Enum.SurfaceType.Studs
	local tex = Instance.new("Texture")
	tex.Texture = "rbxassetid://617517142"
	tex.Face = Enum.NormalId.Top
	tex.StudsPerTileU = 4
	tex.StudsPerTileV = 4
	tex.Parent = platform
	platform.CanCollide = true
	platform.Parent = m

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Road: one straight asphalt road at x=0, from z=-150 to z=+150.
-- ---------------------------------------------------------------------------

local function buildRoad()
	local m = Instance.new("Model")
	m.Name = "Road"

	-- Dark grey asphalt slab: width 24, length 300, thickness 0.3, Y=0.2.
	local road = part({
		Name = "Asphalt",
		Size = Vector3.new(ROAD_WIDTH, 0.3, ROAD_HALF * 2),
		Color = ASPHALT,
		Material = Enum.Material.Plastic,
	})
	road.CFrame = CFrame.new(0, 0.2, 0)
	road.Anchored = true
	road.CanCollide = true
	road.Parent = m

	-- White center line: 1 stud wide, Y=0.35.
	local line = part({
		Name = "CenterLine",
		Size = Vector3.new(1, 0.1, ROAD_HALF * 2),
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.SmoothPlastic,
	})
	line.CFrame = CFrame.new(0, 0.35, 0)
	line.Anchored = true
	line.CanCollide = false
	line.Parent = m

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- setBaseSign / buildSpawnPad: stubs returning empty for Step 1.
-- ---------------------------------------------------------------------------

function WorldBuilder.setBaseSign(_baseModel, _title, _subtitle, _color)
	-- No bases yet — no-op.
end

function WorldBuilder.buildSpawnPad(_index)
	return nil
end

-- ---------------------------------------------------------------------------
-- Build everything. Returns { pads = {}, bases = {} }.
-- ---------------------------------------------------------------------------

function WorldBuilder.build()
	local function safeStep(name, fn)
		local ok, err = pcall(fn)
		if not ok then
			warn("[WorldBuilder] step failed (" .. name .. "): " .. tostring(err))
		end
	end

	local template = workspace:FindFirstChild("Baseplate")
	if template then
		template:Destroy()
	end

	safeStep("setupLighting", setupLighting)
	safeStep("buildGround", buildGround)
	safeStep("buildOcean", buildOcean)
	safeStep("buildCliffs", buildCliffs)
	safeStep("buildSpawnArea", buildSpawnArea)
	safeStep("buildRoad", buildRoad)

	return { pads = {}, bases = {} }
end

return WorldBuilder