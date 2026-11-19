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

local GRASS = Color3.fromRGB(40, 100, 30)  -- dark green
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

local function studAllFaces(p)
	p.TopSurface = Enum.SurfaceType.Studs
	p.BottomSurface = Enum.SurfaceType.Studs
	p.FrontSurface = Enum.SurfaceType.Studs
	p.BackSurface = Enum.SurfaceType.Studs
	p.LeftSurface = Enum.SurfaceType.Studs
	p.RightSurface = Enum.SurfaceType.Studs
	return p
end

-- ---------------------------------------------------------------------------
-- Lighting: no custom setup.
-- ---------------------------------------------------------------------------

local function setupLighting()
	-- Intentionally empty — use Roblox defaults.
end

-- ---------------------------------------------------------------------------
-- Ground: 6x6 grid of 50x50 Plastic tiles with TopSurface.Studs — studs stay
-- visible at gameplay distance (a single 300x300 part culls them out).
-- ---------------------------------------------------------------------------

local function buildGround()
	local m = Instance.new("Model")
	m.Name = "Ground"
	for x = -150, 100, 50 do
		for z = -150, 100, 50 do
			local tile = part({
				Name = "Tile",
				Size = Vector3.new(50, 0.5, 50),
				Color = GRASS,
				Material = Enum.Material.Plastic,
			})
			tile.CFrame = CFrame.new(x + 25, 0, z + 25)
			studAllFaces(tile)
			tile.Anchored = true
			tile.CanCollide = true
			tile.Parent = m
		end
	end

	-- Third wall line, thinnest and shortest
	local half3 = half - 24  -- 126
	for i = 0, SEGMENT_COUNT - 1 do
		local offset = SEGMENT_START + i * SEGMENT_LENGTH
		local h3 = rng:NextNumber(6, 18)  -- shortest wall
		addSegment("Wall3North", Vector3.new(SEGMENT_LENGTH, h3, 5), Vector3.new(offset, h3/2, -half3))
		addSegment("Wall3South", Vector3.new(SEGMENT_LENGTH, h3, 5), Vector3.new(offset, h3/2, half3))
		addSegment("Wall3East", Vector3.new(5, h3, SEGMENT_LENGTH), Vector3.new(half3, h3/2, offset))
		addSegment("Wall3West", Vector3.new(5, h3, SEGMENT_LENGTH), Vector3.new(-half3, h3/2, offset))
	end
, thinnest and shortest
	local half3 = half - 24  -- 126
	for i = 0, SEGMENT_COUNT - 1 do
		local offset = SEGMENT_START + i * SEGMENT_LENGTH
		local h3 = rng:NextNumber(6, 18)  -- shortest wall
		addSegment("Wall3North", Vector3.new(SEGMENT_LENGTH, h3, 5), Vector3.new(offset, h3/2, -half3))
		addSegment("Wall3South", Vector3.new(SEGMENT_LENGTH, h3, 5), Vector3.new(offset, h3/2, half3))
		addSegment("Wall3East", Vector3.new(5, h3, SEGMENT_LENGTH), Vector3.new(half3, h3/2, offset))
		addSegment("Wall3West", Vector3.new(5, h3, SEGMENT_LENGTH), Vector3.new(-half3, h3/2, offset))
	end
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
	studAllFaces(road)
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
	line.TopSurface = Enum.SurfaceType.Smooth
	line.CanCollide = false
	line.Parent = m


	, thinnest and shortest
	local half3 = half - 24  -- 126
	for i = 0, SEGMENT_COUNT - 1 do
		local offset = SEGMENT_START + i * SEGMENT_LENGTH
		local h3 = rng:NextNumber(6, 18)  -- shortest wall
		addSegment("Wall3North", Vector3.new(SEGMENT_LENGTH, h3, 5), Vector3.new(offset, h3/2, -half3))
		addSegment("Wall3South", Vector3.new(SEGMENT_LENGTH, h3, 5), Vector3.new(offset, h3/2, half3))
		addSegment("Wall3East", Vector3.new(5, h3, SEGMENT_LENGTH), Vector3.new(half3, h3/2, offset))
		addSegment("Wall3West", Vector3.new(5, h3, SEGMENT_LENGTH), Vector3.new(-half3, h3/2, offset))
	end
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
	safeStep("buildPerimeterWall", buildPerimeterWall)
	safeStep("buildRoad", buildRoad)

	return { pads = {}, bases = {} }
end

return WorldBuilder