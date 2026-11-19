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
			tile.TopSurface = Enum.SurfaceType.Studs
			tile.Anchored = true
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
	water.TopSurface = Enum.SurfaceType.Smooth
	water.BottomSurface = Enum.SurfaceType.Smooth
	water.CanCollide = false
	water.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Perimeter wall: clean rectangular enclosure around the island edge. Four
-- 300x15x2 brick walls at x=±150 / z=±150, plus 4x4x20 corner pillars.
-- ---------------------------------------------------------------------------

local WALL_COLOR = Color3.fromRGB(140, 80, 60)

local function buildPerimeterWall()
	local m = Instance.new("Model")
	m.Name = "PerimeterWall"

	local half = ISLAND_SIZE / 2 -- 150

	-- Four walls: north/south run along X, east/west run along Z.
	-- Bottom sits at Y=0, so center is at Y=7.5.
	local walls = {
		{ Name = "WallNorth", Size = Vector3.new(ISLAND_SIZE, 15, 2), Pos = Vector3.new(0, 7.5, -half) },
		{ Name = "WallSouth", Size = Vector3.new(ISLAND_SIZE, 15, 2), Pos = Vector3.new(0, 7.5, half) },
		{ Name = "WallEast", Size = Vector3.new(2, 15, ISLAND_SIZE), Pos = Vector3.new(half, 7.5, 0) },
		{ Name = "WallWest", Size = Vector3.new(2, 15, ISLAND_SIZE), Pos = Vector3.new(-half, 7.5, 0) },
	}
	for _, def in ipairs(walls) do
		local w = part({
			Name = def.Name,
			Size = def.Size,
			Color = WALL_COLOR,
			Material = Enum.Material.Plastic,
		})
		w.CFrame = CFrame.new(def.Pos)
		w.TopSurface = Enum.SurfaceType.Studs
		w.BottomSurface = Enum.SurfaceType.Studs
		w.Anchored = true
		w.CanCollide = true
		w.Parent = m
	end

	-- Corner pillars: 4x4x20, straddling each corner to joint the walls.
	for _, sx in ipairs({ -half, half }) do
		for _, sz in ipairs({ -half, half }) do
			local pillar = part({
				Name = "CornerPillar",
				Size = Vector3.new(4, 20, 4),
				Color = WALL_COLOR,
				Material = Enum.Material.Plastic,
			})
			pillar.CFrame = CFrame.new(sx, 10, sz)
			pillar.TopSurface = Enum.SurfaceType.Studs
			pillar.BottomSurface = Enum.SurfaceType.Studs
			pillar.Anchored = true
			pillar.CanCollide = true
			pillar.Parent = m
		end
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
	road.TopSurface = Enum.SurfaceType.Studs
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