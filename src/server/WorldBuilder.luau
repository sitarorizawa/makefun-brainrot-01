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
local YELLOW_LINE = Color3.fromRGB(255, 220, 40)

-- ---------------------------------------------------------------------------
-- Part helper
-- ---------------------------------------------------------------------------

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
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
-- Ground: flat green plane, 300x300, centered at origin, Y=0.
-- ---------------------------------------------------------------------------

local function buildGround()
	local grass = part({
		Name = "Island",
		Size = Vector3.new(ISLAND_SIZE, 0.4, ISLAND_SIZE),
		Color = GRASS,
		Material = Enum.Material.Grass,
	})
	grass.CFrame = CFrame.new(0, 0, 0)

	grass.Anchored = true
	grass.CanCollide = true
	grass.Parent = workspace
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
-- Cliffs: random earth/rock formations around the island perimeter to fill
-- the empty horizon. 18 cliffs of mixed sizes, seeded for determinism.
-- ---------------------------------------------------------------------------

local CLIFF_COLORS = {
	Color3.fromRGB(120, 85, 50),
	Color3.fromRGB(100, 70, 40),
	Color3.fromRGB(140, 100, 65),
	Color3.fromRGB(90, 65, 35),
}

-- size buckets: { wideMin, wideMax, tallMin, tallMax, deepMin, deepMax }
local CLIFF_BUCKETS = {
	{ 30, 50, 20, 35, 20, 40 }, -- BIG
	{ 15, 25, 12, 20, 12, 25 }, -- MEDIUM
	{ 8, 15, 6, 12, 8, 15 },   -- SMALL
}

local function buildCliffs()
	local m = Instance.new("Model")
	m.Name = "Cliffs"

	local rng = Random.new(42)

	-- 5 BIG, 7 MEDIUM, 6 SMALL = 18 cliffs.
	local bucketOrder = {}
	for _ = 1, 5 do table.insert(bucketOrder, 1) end
	for _ = 1, 7 do table.insert(bucketOrder, 2) end
	for _ = 1, 6 do table.insert(bucketOrder, 3) end

	-- indices that should be sloped WedgeParts (4-5 of them)
	local wedgeSet = { [3] = true, [8] = true, [11] = true, [15] = true, [17] = true }

	for i, bucketIndex in ipairs(bucketOrder) do
		local bucket = CLIFF_BUCKETS[bucketIndex]

		-- Pick an angle around all 360 degrees, skipping within 15 deg of the
		-- road (north/south, i.e. angle near 0 or 180 degrees).
		local angle
		for _ = 1, 50 do
			local a = rng:NextNumber(0, math.pi * 2)
			local nearNorth = math.abs(a) < math.rad(15) or math.abs(a - math.pi * 2) < math.rad(15)
			local nearSouth = math.abs(a - math.pi) < math.rad(15)
			if not nearNorth and not nearSouth then
				angle = a
				break
			end
		end
		angle = angle or rng:NextNumber(math.rad(30), math.rad(60))

		local radius = rng:NextNumber(100, 140)
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius

		local wide = rng:NextNumber(bucket[1], bucket[2])
		local tall = rng:NextNumber(bucket[3], bucket[4])
		local deep = rng:NextNumber(bucket[5], bucket[6])

		local yRot = rng:NextNumber(0, math.pi * 2)
		local color = CLIFF_COLORS[rng:NextInteger(1, #CLIFF_COLORS)]
		local material = rng:NextNumber() < 0.5 and Enum.Material.Slate or Enum.Material.Dirt

		local useWedge = wedgeSet[i] == true
		local cliff
		if useWedge then
			cliff = Instance.new("WedgePart")
		else
			cliff = Instance.new("Part")
		end
		cliff.Name = "Cliff" .. tostring(i)
		cliff.Size = Vector3.new(wide, tall, deep)
		cliff.Color = color
		cliff.Material = material
		cliff.TopSurface = Enum.SurfaceType.Smooth
		cliff.BottomSurface = Enum.SurfaceType.Smooth
		cliff.Anchored = true
		cliff.CanCollide = true

		-- Bottom sits at Y=0, so center is at height/2.
		local pos = Vector3.new(x, tall / 2, z)
		local cf = CFrame.new(pos) * CFrame.Angles(0, yRot, 0)

		-- Sloped wedges: face inward toward the island center.
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
-- Road: one straight asphalt road at x=0, from z=-150 to z=+150.
-- ---------------------------------------------------------------------------

local function buildRoad()
	local m = Instance.new("Model")
	m.Name = "Road"

	-- Asphalt slab: width 14, length 300, thickness 0.3, Y=0.2.
	local road = part({
		Name = "Asphalt",
		Size = Vector3.new(ROAD_WIDTH, 0.3, ROAD_HALF * 2),
		Color = ASPHALT,
		Material = Enum.Material.SmoothPlastic,
	})
	road.CFrame = CFrame.new(0, 0.2, 0)
	road.Anchored = true
	road.CanCollide = true
	road.Parent = m

	-- Yellow center line: 1 stud wide, Y=0.35.
	local line = part({
		Name = "CenterLine",
		Size = Vector3.new(1, 0.1, ROAD_HALF * 2),
		Color = YELLOW_LINE,
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
	safeStep("buildRoad", buildRoad)

	return { pads = {}, bases = {} }
end

return WorldBuilder
