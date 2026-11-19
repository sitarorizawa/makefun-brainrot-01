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
-- Perimeter wall: three concentric lines of segmented wall around the island
-- edge (12 segments of 25 studs per side — studs vanish on a single 300-long
-- part, same culling issue as the ground). Heights vary per segment so the
-- skyline reads as ruined rather than extruded; the outer line caps each
-- segment with a grass strip. One seeded Random keeps the layout identical
-- every run.
-- ---------------------------------------------------------------------------

local WALL_COLOR = Color3.fromRGB(120, 80, 50)  -- dark brown

local function buildPerimeterWall()
	local rng = Random.new(42)

	local m = Instance.new("Model")
	m.Name = "PerimeterWall"

	local half = ISLAND_SIZE / 2 -- 150
	local SEGMENT_COUNT = 12
	local SEGMENT_LENGTH = 25
	local SEGMENT_START = -half + SEGMENT_LENGTH / 2 -- -137.5; + i*25 covers -150..+150

	local function addSegment(name, size, pos)
		local w = part({
			Name = name,
			Size = size,
			Color = WALL_COLOR,
			Material = Enum.Material.Plastic,
		})
		w.CFrame = CFrame.new(pos)
		studAllFaces(w)
		w.Anchored = true
		w.CanCollide = true
		w.Parent = m
	end

	local function addGrassCap(name, size, pos)
		local g = part({
			Name = name,
			Size = size,
			Color = GRASS,
			Material = Enum.Material.Plastic,
		})
		g.CFrame = CFrame.new(pos)
		studAllFaces(g)
		g.Anchored = true
		g.CanCollide = false
		g.Parent = m
	end

	-- One line: north/south run along X at z=±distance, east/west along Z at
	-- x=±distance. Bottom sits at Y=0, so the center is at Y=height/2.
	local function addWallLine(prefix, distance, thickness, minH, maxH, capWithGrass)
		for i = 0, SEGMENT_COUNT - 1 do
			local offset = SEGMENT_START + i * SEGMENT_LENGTH
			local height = rng:NextNumber(minH, maxH)
			local y = height / 2

			local sizeAlongX = Vector3.new(SEGMENT_LENGTH, height, thickness)
			local sizeAlongZ = Vector3.new(thickness, height, SEGMENT_LENGTH)
			addSegment(prefix .. "North", sizeAlongX, Vector3.new(offset, y, -distance))
			addSegment(prefix .. "South", sizeAlongX, Vector3.new(offset, y, distance))
			addSegment(prefix .. "East", sizeAlongZ, Vector3.new(distance, y, offset))
			addSegment(prefix .. "West", sizeAlongZ, Vector3.new(-distance, y, offset))

			if capWithGrass then
				-- 1-stud slab a hair wider than the wall, sitting on its top.
				local capX = Vector3.new(SEGMENT_LENGTH, 1, thickness + 2)
				local capZ = Vector3.new(thickness + 2, 1, SEGMENT_LENGTH)
				local capY = height + 0.5
				addGrassCap(prefix .. "GrassNorth", capX, Vector3.new(offset, capY, -distance))
				addGrassCap(prefix .. "GrassSouth", capX, Vector3.new(offset, capY, distance))
				addGrassCap(prefix .. "GrassEast", capZ, Vector3.new(distance, capY, offset))
				addGrassCap(prefix .. "GrassWest", capZ, Vector3.new(-distance, capY, offset))
			end
		end
	end

	-- Outermost (thick, tall, grass-capped) → innermost (thin, short).
	addWallLine("Wall1", half, 20, 12, 35, true) -- half = 150
	addWallLine("Wall2", half - 10, 12, 8, 22, true) -- 138
	addWallLine("Wall3", half - 20, 10, 5, 14, true) -- 126

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

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Tunnels: one arch over each road end (z = ±150). Side walls stand at
-- x = ±15 just outside the road edges, a 36-wide arch top spans them at
-- Y = 12 (level with the wall tops), and a lighter keystone caps the crown.
-- The gap between the walls is left open so the road passes through.
-- ---------------------------------------------------------------------------

local KEYSTONE = Color3.fromRGB(150, 100, 65) -- slightly lighter brown

local function buildTunnels()
	local m = Instance.new("Model")
	m.Name = "Tunnels"

	local function addBox(name, size, pos, color)
		local p = part({
			Name = name,
			Size = size,
			Color = color,
			Material = Enum.Material.Plastic,
		})
		p.CFrame = CFrame.new(pos)
		studAllFaces(p)
		p.Anchored = true
		p.CanCollide = true
		p.Parent = m
	end

	-- Walls sit on the ground (center Y = height / 2). The arch top's center
	-- is at Y = 12; the keystone rests on its crown (12 + 3/2 + 4/2).
	local function addArch(prefix, z)
		addBox(prefix .. "WallWest", Vector3.new(6, 12, 8), Vector3.new(-15, 6, z), WALL_COLOR)
		addBox(prefix .. "WallEast", Vector3.new(6, 12, 8), Vector3.new(15, 6, z), WALL_COLOR)
		addBox(prefix .. "ArchTop", Vector3.new(36, 3, 8), Vector3.new(0, 12, z), WALL_COLOR)
		addBox(prefix .. "Keystone", Vector3.new(6, 4, 8.5), Vector3.new(0, 15.5, z), KEYSTONE)
	end

	addArch("North", -120) -- z = -100
	addArch("South", 120) -- z = +100

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
	safeStep("buildTunnels", buildTunnels)

	return { pads = {}, bases = {} }
end

return WorldBuilder