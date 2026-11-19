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
-- Tunnels: one imported FBX mesh at each road end (z = ±120).
-- ---------------------------------------------------------------------------

local function buildTunnels()
	local m = Instance.new("Model")
	m.Name = "Tunnels"
	local assetId = 8738914511
	local SCALE = 0.5
	local success, err = pcall(function()
		local insertService = game:GetService("InsertService")
		for _, z in ipairs({0}) do
			local model = insertService:LoadAsset(assetId)
			model.Name = "Tunnel"
			-- Anchor + scale + remove black walls
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = true
					desc.Size = desc.Size * SCALE
					-- Remove black blocking walls (very dark parts in center)
					local brightness = (desc.Color.R + desc.Color.G + desc.Color.B) / 3
					if brightness < 0.15 and math.abs(desc.Position.X) < 5 then
						desc:Destroy()
					end
				end
			end
			-- Position: arch faces along Z axis (road direction)
			local pivot = CFrame.new(0, 2, z)
			model:PivotTo(pivot)
			model.Parent = m
		end
	end)
	if not success then
		warn("Tunnel load failed: " .. tostring(err))
	end
	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Base: creative open-front building at x=50, facing the road (x=0).
-- ---------------------------------------------------------------------------

local BASE_X = 65
local BASE_W = 50
local BASE_D = 40
local BASE_H = 18

local baseModel = nil

local function buildBase()
	local m = Instance.new("Model")
	m.Name = "Base1"

	local function bp(props)
		local p = part(props)
		p.Anchored = true
		p.CanCollide = true
		return p
	end

	-- Floor
	local floor = bp({Name="Floor", Size=Vector3.new(BASE_W, 1, BASE_D), Color=Color3.fromRGB(50,50,55), Material=Enum.Material.Plastic})
	floor.CFrame = CFrame.new(BASE_X, 0.5, 0)
	studAllFaces(floor)
	floor.Parent = m

	-- Checkerboard tiles (5x5) inside the base
	for tx = 0, 9 do
		for tz = 0, 7 do
			local c = ((tx + tz) % 2 == 0) and Color3.fromRGB(70,70,75) or Color3.fromRGB(50,50,55)
			local tile = bp({Name="Tile", Size=Vector3.new(5, 0.15, 5), Color=c, Material=Enum.Material.Plastic})
			tile.CFrame = CFrame.new(BASE_X - BASE_W/2 + 2.5 + tx*5, 1.07, -BASE_D/2 + 2.5 + tz*5)
			tile.CanCollide = false
			tile.Parent = m
		end
	end

	-- Back wall (positive X, away from road)
	local back = bp({Name="BackWall", Size=Vector3.new(1, BASE_H, BASE_D), Color=Color3.fromRGB(120,80,50), Material=Enum.Material.Plastic})
	back.CFrame = CFrame.new(BASE_X + BASE_W/2, BASE_H/2 + 1, 0)
	studAllFaces(back)
	back.Parent = m

	-- Side walls (Z sides)
	for _, sz in ipairs({-1, 1}) do
		local wall = bp({Name="SideWall", Size=Vector3.new(BASE_W, BASE_H, 0.5), Color=Color3.fromRGB(170,210,230), Material=Enum.Material.Glass})
		wall.CFrame = CFrame.new(BASE_X, BASE_H/2 + 1, sz * BASE_D/2)
		studAllFaces(wall)
		wall.Parent = m
	end

	-- Ceiling
	local ceil = bp({Name="Ceiling", Size=Vector3.new(BASE_W + 1, 1, BASE_D + 1), Color=Color3.fromRGB(100,65,40), Material=Enum.Material.Plastic})
	ceil.CFrame = CFrame.new(BASE_X, BASE_H + 1.5, 0)
	ceil.Parent = m

	-- Corner pillars (open front = negative X has NO wall)
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			local pil = bp({Name="Pillar", Size=Vector3.new(2, BASE_H, 2), Color=Color3.fromRGB(160,120,80), Material=Enum.Material.Plastic})
			pil.CFrame = CFrame.new(BASE_X + sx * BASE_W/2, BASE_H/2 + 1, sz * BASE_D/2)
			studAllFaces(pil)
			pil.Parent = m
		end
	end

	-- Display shelves on back wall (3 rows)
	for row = 1, 3 do
		local shelf = bp({Name="Shelf" .. row, Size=Vector3.new(3, 0.5, BASE_D - 6), Color=Color3.fromRGB(160,120,80), Material=Enum.Material.Plastic})
		shelf.CFrame = CFrame.new(BASE_X + BASE_W/2 - 3, row * 3 + 1, 0)
		shelf.Parent = m
	end

	-- Neon strip on top of open front
	local neon = bp({Name="NeonStrip", Size=Vector3.new(0.5, 0.5, BASE_D), Color=Color3.fromRGB(0,255,255), Material=Enum.Material.Neon})
	neon.CFrame = CFrame.new(BASE_X - BASE_W/2, BASE_H + 1, 0)
	neon.CanCollide = false
	neon.Parent = m

	-- Sign board above open front
	local sign = bp({Name="Sign", Size=Vector3.new(0.5, 3, 20), Color=Color3.fromRGB(30,30,35), Material=Enum.Material.Plastic})
	sign.CFrame = CFrame.new(BASE_X - BASE_W/2, BASE_H + 3.5, 0)
	sign.CanCollide = false
	sign.Parent = m

	m.Parent = workspace
	return m
end

function WorldBuilder.setBaseSign(model, title, _subtitle, _color)
	if not model then return end
	local sign = model:FindFirstChild("Sign")
	if not sign then return end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = title or "YOUR BASE"
	label.TextColor3 = Color3.fromRGB(255, 220, 50)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
end

function WorldBuilder.buildSpawnPad(index)
	local pad = part({Name="Pad" .. index, Size=Vector3.new(6, 1, 6), Color=Color3.fromRGB(50,200,50), Material=Enum.Material.Plastic})
	pad.CFrame = CFrame.new(BASE_X, 1.6, 0)
	pad.Anchored = true
	pad.CanCollide = true
	studAllFaces(pad)
	return pad
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
	safeStep("buildBase", function()
		baseModel = buildBase()
	end)

	return {
		pads = { WorldBuilder.buildSpawnPad(1) },
		bases = { baseModel },
	}
end

return WorldBuilder