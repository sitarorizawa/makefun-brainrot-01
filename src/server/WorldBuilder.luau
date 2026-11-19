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
	-- Noon sun: bright overhead light, no shadows
	local sun = Instance.new("DirectionalLight")
	sun.Name = "NoonSun"
	sun.Brightness = 3
	sun.Color = Color3.fromRGB(255, 250, 240)
	sun.Shadows = false
	sun.Angle = 15
	-- Point straight down (noon): rotation looking down
	sun.CFrame = CFrame.new(0, 100, 0) * CFrame.Angles(math.rad(-80), math.rad(10), 0)
	sun.Parent = game:GetService("Lighting")

	-- Ambient: bright so no dark corners
	local light = game:GetService("Lighting")
	light.Ambient = Color3.fromRGB(140, 140, 140)
	light.OutdoorAmbient = Color3.fromRGB(160, 160, 160)
	light.Brightness = 3
	light.GlobalShadows = false
	light.EnvironmentDiffuseScale = 1
	light.EnvironmentSpecularScale = 1

	-- Time: noon (12:00)
	light.ClockTime = 12
	light.GeographicLatitude = 0
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
-- Decor: brainrot shop, statues, trees, lamps, billboard and props.
-- Purely visual scenery — no game systems.
-- ---------------------------------------------------------------------------

-- Anchored solid by default; flip CanCollide off for neon / trim pieces.
local function solid(props)
	local p = part(props)
	p.Anchored = true
	p.CanCollide = true
	return p
end

-- Shop at x=-50, west of the road. The road sits at x=0, so the shop's open
-- front is its +X face (mirrors the base at x=65, whose open front faces -X).
local function buildShop()
	local m = Instance.new("Model")
	m.Name = "Shop"

	local PURPLE = Color3.fromRGB(80, 60, 140)
	local DARK_PURPLE = Color3.fromRGB(60, 40, 110)
	local WOOD = Color3.fromRGB(160, 120, 80)
	local RED = Color3.fromRGB(255, 80, 80)
	local WHITE = Color3.fromRGB(255, 255, 255)
	local NEON_GREEN = Color3.fromRGB(0, 255, 100)

	local X, Z = -50, 0
	local W, H, D = 20, 15, 10 -- 20 wide (X), 15 tall, 10 deep (Z)

	-- Back wall, away from the road
	local back = solid({Name = "BackWall", Size = Vector3.new(1, H, D), Color = PURPLE, Material = Enum.Material.Plastic})
	back.CFrame = CFrame.new(X - W / 2 + 0.5, H / 2, Z)
	studAllFaces(back)
	back.Parent = m

	-- Side walls; the +X face is left open as the entrance
	for _, sz in ipairs({-1, 1}) do
		local wall = solid({Name = "SideWall", Size = Vector3.new(W, H, 1), Color = PURPLE, Material = Enum.Material.Plastic})
		wall.CFrame = CFrame.new(X, H / 2, Z + sz * (D / 2 - 0.5))
		studAllFaces(wall)
		wall.Parent = m
	end

	-- Flat overhanging roof
	local roof = solid({Name = "Roof", Size = Vector3.new(22, 1, 17), Color = DARK_PURPLE, Material = Enum.Material.Plastic})
	roof.CFrame = CFrame.new(X, H + 0.5, Z)
	studAllFaces(roof)
	roof.Parent = m

	-- Counter along the back wall
	local counter = solid({Name = "Counter", Size = Vector3.new(1, 4, 8), Color = WOOD, Material = Enum.Material.Plastic})
	counter.CFrame = CFrame.new(X - W / 2 + 2, 2, Z)
	studAllFaces(counter)
	counter.Parent = m

	-- Striped awning over the entrance: 8 alternating panels, tilted down/out
	for i = 0, 7 do
		local stripe = solid({
			Name = "Awning" .. (i + 1),
			Size = Vector3.new(6, 0.4, 1.25),
			Color = (i % 2 == 0) and RED or WHITE,
			Material = Enum.Material.Plastic,
		})
		stripe.CFrame = CFrame.new(X + W / 2 + 2.5, 12.5, Z - 4.375 + i * 1.25) * CFrame.Angles(0, 0, math.rad(-15))
		stripe.Parent = m
	end

	-- Neon sign above the entrance
	local sign = solid({Name = "Sign", Size = Vector3.new(0.5, 2, 12), Color = NEON_GREEN, Material = Enum.Material.SmoothPlastic})
	sign.CFrame = CFrame.new(X + W / 2 + 0.25, 15, Z)
	sign.CanCollide = false
	sign.Parent = m

	m.Parent = workspace
end

-- Statues: 4 positions along the road, both sides — 8 in total.
local function buildStatues()
	local m = Instance.new("Model")
	m.Name = "Statues"

	local STONE = Color3.fromRGB(120, 120, 130)
	local GOLD = Color3.fromRGB(255, 200, 50)
	local GOLD_LIGHT = Color3.fromRGB(255, 220, 80)

	for _, z in ipairs({-60, -20, 20, 60}) do
		for _, sx in ipairs({-1, 1}) do
			local x = sx * 15

			local pedestal = solid({Name = "Pedestal", Size = Vector3.new(4, 3, 4), Color = STONE, Material = Enum.Material.Plastic})
			pedestal.CFrame = CFrame.new(x, 1.5, z)
			studAllFaces(pedestal)
			pedestal.Parent = m

			local figure = solid({Name = "Figure", Size = Vector3.new(2, 4, 2), Color = GOLD, Material = Enum.Material.Plastic})
			figure.CFrame = CFrame.new(x, 5, z)
			studAllFaces(figure)
			figure.Parent = m

			local head = solid({Name = "Head", Size = Vector3.new(3, 1, 3), Color = GOLD_LIGHT, Material = Enum.Material.Plastic})
			head.CFrame = CFrame.new(x, 7.5, z)
			studAllFaces(head)
			head.Parent = m
		end
	end

	m.Parent = workspace
end

-- Trees: 16 blocky trees on a fixed ring around the island, clear of the road
-- (x=0) and of the base plot (x=65).
local function buildTrees()
	local m = Instance.new("Model")
	m.Name = "Trees"

	local TRUNK = Color3.fromRGB(120, 80, 40)
	local LEAF = Color3.fromRGB(50, 160, 50)

	local spots = {
		{-110, -110}, {-110, -40}, {-110, 40}, {-110, 110},
		{-70, -120}, {-30, -120}, {30, -120}, {90, -120},
		{-70, 120}, {-30, 120}, {30, 120}, {90, 120},
		{110, -80}, {110, -30}, {110, 30}, {110, 80},
	}

	for i, pos in ipairs(spots) do
		local x, z = pos[1], pos[2]

		local trunk = solid({Name = "Trunk" .. i, Size = Vector3.new(1, 6, 1), Color = TRUNK, Material = Enum.Material.Plastic})
		trunk.CFrame = CFrame.new(x, 3, z)
		studAllFaces(trunk)
		trunk.Parent = m

		local lower = solid({Name = "Canopy" .. i, Size = Vector3.new(5, 4, 5), Color = LEAF, Material = Enum.Material.Plastic})
		lower.CFrame = CFrame.new(x, 7, z)
		studAllFaces(lower)
		lower.Parent = m

		local top = solid({Name = "CanopyTop" .. i, Size = Vector3.new(3, 3, 3), Color = LEAF, Material = Enum.Material.Plastic})
		top.CFrame = CFrame.new(x, 10.5, z)
		studAllFaces(top)
		top.Parent = m
	end

	m.Parent = workspace
end

-- Street lamps: 5 positions along the road, both sides — 10 in total.
local function buildLamps()
	local m = Instance.new("Model")
	m.Name = "Lamps"

	local POLE = Color3.fromRGB(60, 60, 65)
	local GLOW = Color3.fromRGB(255, 240, 150)

	for _, z in ipairs({-100, -50, 0, 50, 100}) do
		for _, sx in ipairs({-1, 1}) do
			local x = sx * 16

			-- Roblox cylinders run along X, so rotate the pole upright.
			local pole = solid({Name = "Pole", Size = Vector3.new(10, 1, 1), Color = POLE, Material = Enum.Material.Plastic, Shape = Enum.PartType.Cylinder})
			pole.CFrame = CFrame.new(x, 5, z) * CFrame.Angles(0, 0, math.rad(90))
			pole.Parent = m

			local head = solid({Name = "LampHead", Size = Vector3.new(2, 2, 2), Color = GLOW, Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Ball})
			head.CFrame = CFrame.new(x, 11, z)
			head.CanCollide = false
			head.Parent = m

			-- LampLight disabled (noon lighting)
		end
	end

	m.Parent = workspace
end

-- Billboard behind the shop at x=-65, text facing the road.
local function buildBillboard()
	local m = Instance.new("Model")
	m.Name = "Billboard"

	local GREY = Color3.fromRGB(110, 110, 115)
	local PANEL = Color3.fromRGB(240, 240, 240)

	local X, Z = -65, 0

	for _, sz in ipairs({-1, 1}) do
		local pillar = solid({Name = "Pillar", Size = Vector3.new(1, 15, 1), Color = GREY, Material = Enum.Material.Plastic})
		pillar.CFrame = CFrame.new(X, 7.5, Z + sz * 8)
		studAllFaces(pillar)
		pillar.Parent = m
	end

	local panel = solid({Name = "Panel", Size = Vector3.new(0.5, 8, 20), Color = PANEL, Material = Enum.Material.Plastic})
	panel.CFrame = CFrame.new(X, 12, Z)
	panel.CanCollide = false
	panel.Parent = m

	-- NormalId.Right points at +X, i.e. toward the road.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "BRAINROT MARKET"
	label.TextColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui

	m.Parent = workspace
end

-- Scattered props: crates, benches and road-end fountains.
local function buildProps()
	local m = Instance.new("Model")
	m.Name = "Props"

	local WOOD = Color3.fromRGB(150, 110, 70)
	local STONE = Color3.fromRGB(120, 120, 130)
	local WATER = Color3.fromRGB(80, 160, 255)

	-- 6 crates: three by the base plot, three by the shop front
	for i, pos in ipairs({{44, -24}, {48, -26}, {82, 20}, {-36, -8}, {-36, 8}, {-62, 12}}) do
		local crate = solid({Name = "Crate" .. i, Size = Vector3.new(3, 3, 3), Color = WOOD, Material = Enum.Material.Plastic})
		crate.CFrame = CFrame.new(pos[1], 1.5, pos[2])
		studAllFaces(crate)
		crate.Parent = m
	end

	-- 4 benches, one per z, alternating side of the road
	for i, pos in ipairs({{-20, -40}, {20, -10}, {-20, 10}, {20, 40}}) do
		local x, z = pos[1], pos[2]

		local seat = solid({Name = "BenchSeat" .. i, Size = Vector3.new(6, 0.5, 2), Color = WOOD, Material = Enum.Material.Plastic})
		seat.CFrame = CFrame.new(x, 2.25, z)
		studAllFaces(seat)
		seat.Parent = m

		for _, sx in ipairs({-1, 1}) do
			local leg = solid({Name = "BenchLeg" .. i, Size = Vector3.new(0.5, 2, 2), Color = WOOD, Material = Enum.Material.Plastic})
			leg.CFrame = CFrame.new(x + sx * 2.75, 1, z)
			studAllFaces(leg)
			leg.Parent = m
		end
	end

	-- 2 fountains on the road ends
	for _, z in ipairs({-120, 120}) do
		local base = solid({Name = "FountainBase", Size = Vector3.new(2, 12, 12), Color = STONE, Material = Enum.Material.Plastic, Shape = Enum.PartType.Cylinder})
		base.CFrame = CFrame.new(0, 1, z) * CFrame.Angles(0, 0, math.rad(90))
		base.Parent = m

		local water = solid({Name = "FountainWater", Size = Vector3.new(1.5, 8, 8), Color = WATER, Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Cylinder})
		water.CFrame = CFrame.new(0, 2.75, z) * CFrame.Angles(0, 0, math.rad(90))
		water.CanCollide = false
		water.Parent = m
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

-- ---------------------------------------------------------------------------
-- Gates: stone arch tunnels at both road ends (z=±150).
-- ---------------------------------------------------------------------------

local function buildGates()
	local m = Instance.new("Model")
	m.Name = "Gates"

	local function bp(props)
		local p = part(props)
		p.Anchored = true
		p.CanCollide = true
		return p
	end

	local STONE = Color3.fromRGB(110, 110, 118)
	local STONE_DARK = Color3.fromRGB(85, 85, 92)
	local STONE_LIGHT = Color3.fromRGB(140, 140, 148)

	local function buildGate(z)
		local MOSS = Color3.fromRGB(70, 130, 50)
		local MOSS_DARK = Color3.fromRGB(50, 100, 35)
		local ROOT = Color3.fromRGB(100, 70, 40)
		local VINE = Color3.fromRGB(45, 140, 40)
		local FLOWER1 = Color3.fromRGB(255, 100, 150)
		local FLOWER2 = Color3.fromRGB(255, 220, 80)

		-- Big boulder pillars (irregular rock shapes using stacked boxes with rotation)
		for _, sx in ipairs({-1, 1}) do
			-- Base boulder (wide, irregular)
			local b1 = bp({Name="Boulder", Size=Vector3.new(8, 5, 9), Color=Color3.fromRGB(105, 100, 95), Material=Enum.Material.Slate})
			b1.CFrame = CFrame.new(sx * 14, 2.5, z) * CFrame.Angles(0, math.rad(sx * 8), math.rad(sx * 3))
			studAllFaces(b1)
			b1.Parent = m

			-- Mid boulder
			local b2 = bp({Name="Boulder", Size=Vector3.new(7, 5, 8), Color=Color3.fromRGB(115, 110, 105), Material=Enum.Material.Slate})
			b2.CFrame = CFrame.new(sx * 14.5, 7, z) * CFrame.Angles(math.rad(2), math.rad(-sx * 5), math.rad(-sx * 2))
			studAllFaces(b2)
			b2.Parent = m

			-- Upper boulder
			local b3 = bp({Name="Boulder", Size=Vector3.new(6, 5, 7), Color=Color3.fromRGB(100, 95, 90), Material=Enum.Material.Slate})
			b3.CFrame = CFrame.new(sx * 13.5, 11.5, z) * CFrame.Angles(math.rad(-1), math.rad(sx * 6), math.rad(sx * 4))
			studAllFaces(b3)
			b3.Parent = m

			-- Top boulder
			local b4 = bp({Name="Boulder", Size=Vector3.new(5, 4, 6), Color=Color3.fromRGB(110, 105, 100), Material=Enum.Material.Slate})
			b4.CFrame = CFrame.new(sx * 14, 15.5, z) * CFrame.Angles(math.rad(3), math.rad(-sx * 4), 0)
			studAllFaces(b4)
			b4.Parent = m

			-- Moss patches on boulders (green flat boxes)
			for i = 0, 3 do
				local moss = bp({Name="Moss", Size=Vector3.new(3 + i, 0.3, 3 + i), Color=MOSS, Material=Enum.Material.Grass})
				moss.CFrame = CFrame.new(sx * (13 + i * 0.5), 4 + i * 4, z + (i % 2 == 0 and 2 or -2))
				moss.CanCollide = false
				moss.Parent = m
			end

			-- Vine climbing the pillar (stacked small green boxes)
			for i = 0, 7 do
				local vine = bp({Name="Vine", Size=Vector3.new(1.5, 2, 1.5), Color=VINE, Material=Enum.Material.Grass})
				local vx = sx * (14 + math.sin(i * 1.2) * 3)
				vine.CFrame = CFrame.new(vx, 2 + i * 2, z + math.cos(i * 1.5) * 3)
				vine.CanCollide = false
				vine.Parent = m
			end

			-- Tree root wrapping base
			for r = 0, 2 do
				local root = bp({Name="Root", Size=Vector3.new(6 - r, 1.5, 3), Color=ROOT, Material=Enum.Material.Wood})
				root.CFrame = CFrame.new(sx * (14 + r * 2), 0.75, z + r * 3 - 3) * CFrame.Angles(0, math.rad(sx * 20 * r), 0)
				root.Parent = m
			end

			-- Small flowers on top
			for f = 0, 2 do
				local stem = bp({Name="Stem", Size=Vector3.new(0.4, 2, 0.4), Color=MOSS_DARK, Material=Enum.Material.Grass})
				stem.CFrame = CFrame.new(sx * (13 + f), 18.5, z + f * 2 - 2)
				stem.CanCollide = false
				stem.Parent = m

				local flower = bp({Name="Flower", Size=Vector3.new(1.2, 1.2, 1.2), Color=(f % 2 == 0) and FLOWER1 or FLOWER2, Material=Enum.Material.SmoothPlastic, Shape=Enum.PartType.Ball})
				flower.CFrame = CFrame.new(sx * (13 + f), 20, z + f * 2 - 2)
				flower.CanCollide = false
				flower.Parent = m
			end
		end

		-- Arch: natural stone rocks in a curve
		local archY = 17
		local R = 14
		for i = 0, 10 do
			local t = math.pi * i / 10
			local wx = math.cos(t) * R
			local wy = archY + math.sin(t) * 5
			local sz = 5 + (i % 3)
			local block = bp({Name="ArchRock", Size=Vector3.new(sz, sz - 1, 7), Color=Color3.fromRGB(105 + (i % 3) * 8, 100 + (i % 3) * 8, 95 + (i % 3) * 8), Material=Enum.Material.Slate})
			block.CFrame = CFrame.new(wx, wy, z) * CFrame.Angles(math.rad(i * 7 % 10), math.rad(i * 13 % 15), t - math.pi/2)
			studAllFaces(block)
			block.Parent = m

			-- Moss on arch rocks (alternating)
			if i % 2 == 0 then
				local moss = bp({Name="ArchMoss", Size=Vector3.new(sz - 1, 1, 4), Color=MOSS, Material=Enum.Material.Grass})
				moss.CFrame = CFrame.new(wx, wy + sz/2, z) * CFrame.Angles(0, 0, t - math.pi/2)
				moss.CanCollide = false
				moss.Parent = m
			end
		end

		-- Keystone: big round boulder
		local key = bp({Name="Keystone", Size=Vector3.new(7, 6, 8), Color=Color3.fromRGB(120, 115, 108), Material=Enum.Material.Slate, Shape=Enum.PartType.Ball})
		key.CFrame = CFrame.new(0, archY + 8, z)
		studAllFaces(key)
		key.Parent = m

		-- Moss on keystone
		local keyMoss = bp({Name="KeyMoss", Size=Vector3.new(5, 1.5, 5), Color=MOSS, Material=Enum.Material.Grass})
		keyMoss.CFrame = CFrame.new(0, archY + 11, z)
		keyMoss.CanCollide = false
		keyMoss.Parent = m

		-- Vines hanging from arch
		for v = 0, 4 do
			local hang = bp({Name="HangingVine", Size=Vector3.new(1, 4 + v, 1), Color=VINE, Material=Enum.Material.Grass})
			local t = math.pi * (v + 1) / 6
			hang.CFrame = CFrame.new(math.cos(t) * R, archY + math.sin(t) * 5 - 3, z + math.sin(v * 2) * 2)
			hang.CanCollide = false
			hang.Parent = m
		end

		-- Ground vegetation around base (bushes)
		for _, bx in ipairs({-18, -10, 10, 18}) do
			local bush = bp({Name="Bush", Size=Vector3.new(4, 3, 4), Color=MOSS_DARK, Material=Enum.Material.Grass})
			bush.CFrame = CFrame.new(bx, 1.5, z + (bx > 0 and 5 or -5)) * CFrame.Angles(0, math.rad(bx * 7), 0)
			bush.CanCollide = false
			bush.Parent = m
		end

		-- Small rocks scattered at base
		for _, rx in ipairs({-20, -7, 7, 20}) do
			local rock = bp({Name="SmallRock", Size=Vector3.new(2, 1.5, 2), Color=Color3.fromRGB(130, 125, 120), Material=Enum.Material.Slate, Shape=Enum.PartType.Ball})
			rock.CFrame = CFrame.new(rx, 0.75, z + (rx % 2 == 0 and 4 or -4))
			rock.Parent = m
		end
	end

	buildGate(-125)
	buildGate(125)

	m.Parent = workspace
end

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
		local wall = bp({Name="SideWall", Size=Vector3.new(BASE_W, BASE_H, 0.5), Color=Color3.fromRGB(200,230,255), Material=Enum.Material.Glass})
		wall.Transparency = 0.7
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


	-- Sign board above open front
	local sign = bp({Name="Sign", Size=Vector3.new(0.5, 3, 20), Color=Color3.fromRGB(30,30,35), Material=Enum.Material.Plastic})
	sign.CFrame = CFrame.new(BASE_X - BASE_W/2, BASE_H + 3.5, 0)
	sign.CanCollide = false
	sign.Parent = m

	-- === DECORATIONS ===

	-- 1. Front porch + steps
	local porch = bp({Name="Porch", Size=Vector3.new(8, 1, BASE_W), Color=Color3.fromRGB(140,140,145), Material=Enum.Material.Concrete})
	porch.CFrame = CFrame.new(BASE_X - BASE_W/2 - 4, 0.5, 0)
	porch.Parent = m

	for i, sx in ipairs({-2, -4}) do
		local step = bp({Name="Step", Size=Vector3.new(2, 0.5, BASE_W), Color=Color3.fromRGB(130,130,135), Material=Enum.Material.Concrete})
		step.CFrame = CFrame.new(BASE_X - BASE_W/2 + sx - 1, 0.25, 0)
		step.Parent = m
	end

	-- Porch railing
	for _, sz in ipairs({-1, 1}) do
		for _, px in ipairs({BASE_X - BASE_W/2 - 7, BASE_X - BASE_W/2 - 1}) do
			local post = bp({Name="RailingPost", Size=Vector3.new(0.5, 3, 0.5), Color=Color3.fromRGB(70,70,75), Material=Enum.Material.Metal})
			post.CFrame = CFrame.new(px, 2.5, sz * (BASE_W/2 - 1))
			post.Parent = m
		end
		local bar = bp({Name="RailingBar", Size=Vector3.new(6, 0.3, 0.3), Color=Color3.fromRGB(70,70,75), Material=Enum.Material.Metal})
		bar.CFrame = CFrame.new(BASE_X - BASE_W/2 - 4, 3.8, sz * (BASE_W/2 - 1))
		bar.Parent = m
	end

	-- 2. Ceiling light fixtures (NO PointLight)
	for _, lx in ipairs({-10, 0, 10}) do
		for _, lz in ipairs({-10, 10}) do
		end
	end

	-- 3. Display cases (4 glass cases for brainrots)
	for _, pos in ipairs({{-15, -12}, {-15, 12}, {15, -12}, {15, 12}}) do
		local caseBase = bp({Name="CaseBase", Size=Vector3.new(6, 1, 6), Color=Color3.fromRGB(130,95,60), Material=Enum.Material.Wood})
		caseBase.CFrame = CFrame.new(BASE_X + pos[1], 1.5, pos[2])
		caseBase.Parent = m

		local glass = bp({Name="CaseGlass", Size=Vector3.new(5, 5, 5), Color=Color3.fromRGB(200,230,255), Material=Enum.Material.Glass})
		glass.Transparency = 0.7
		glass.CFrame = CFrame.new(BASE_X + pos[1], 4.5, pos[2])
		glass.CanCollide = false
		glass.Parent = m

		local caseTop = bp({Name="CaseTop", Size=Vector3.new(6, 0.3, 6), Color=Color3.fromRGB(130,95,60), Material=Enum.Material.Wood})
		caseTop.CFrame = CFrame.new(BASE_X + pos[1], 7.1, pos[2])
		caseTop.Parent = m
	end

	-- 4. Front desk + monitor
	local deskTop = bp({Name="DeskTop", Size=Vector3.new(1, 0.3, 10), Color=Color3.fromRGB(160,120,80), Material=Enum.Material.Wood})
	deskTop.CFrame = CFrame.new(BASE_X - 15, 4.3, 0)
	deskTop.Parent = m

	local deskBase = bp({Name="DeskBase", Size=Vector3.new(1, 4, 10), Color=Color3.fromRGB(120,85,55), Material=Enum.Material.Wood})
	deskBase.CFrame = CFrame.new(BASE_X - 15, 2, 0)
	deskBase.Parent = m

	local monitor = bp({Name="Monitor", Size=Vector3.new(0.2, 1.5, 2), Color=Color3.fromRGB(30,30,35), Material=Enum.Material.SmoothPlastic})
	monitor.CFrame = CFrame.new(BASE_X - 15.5, 5.3, 0)
	monitor.CanCollide = false
	monitor.Parent = m

	local screen = bp({Name="MonitorScreen", Size=Vector3.new(0.1, 1.2, 1.8), Color=Color3.fromRGB(40,40,45), Material=Enum.Material.SmoothPlastic})
	screen.CFrame = CFrame.new(BASE_X - 15.7, 5.3, 0)
	screen.CanCollide = false
	screen.Parent = m

	-- 5. Windows on side walls (frames + glass)
	for _, sz in ipairs({-1, 1}) do
		for _, wz in ipairs({-15, -5, 5, 15}) do
			local frame = bp({Name="WindowFrame", Size=Vector3.new(1.2, 5, 4), Color=Color3.fromRGB(140,105,70), Material=Enum.Material.Wood})
			frame.CFrame = CFrame.new(BASE_X, 11, sz * (BASE_D/2))
			-- Offset along Z
			frame.CFrame = CFrame.new(BASE_X + wz, 11, sz * (BASE_D/2))
			frame.Parent = m

			local wglass = bp({Name="WindowGlass", Size=Vector3.new(0.6, 4, 3), Color=Color3.fromRGB(180,220,255), Material=Enum.Material.Glass})
			wglass.Transparency = 0.5
			wglass.CFrame = CFrame.new(BASE_X + wz, 11, sz * (BASE_D/2))
			wglass.CanCollide = false
			wglass.Parent = m
		end
	end

	-- 6. Trophy shelves + posters on back wall
	for _, tz in ipairs({-10, 0, 10}) do
		local tshelf = bp({Name="TrophyShelf", Size=Vector3.new(0.5, 0.3, 8), Color=Color3.fromRGB(160,120,80), Material=Enum.Material.Wood})
		tshelf.CFrame = CFrame.new(BASE_X + BASE_W/2 - 2, 9, tz)
		tshelf.Parent = m

		for _, ox in ipairs({-2, 2}) do
			local trophy = bp({Name="Trophy", Size=Vector3.new(1, 1.5, 1), Color=Color3.fromRGB(255,200,50), Material=Enum.Material.Metal})
			trophy.CFrame = CFrame.new(BASE_X + BASE_W/2 - 2, 10, tz + ox)
			trophy.Parent = m
		end
	end


	-- 7. Roof details
	-- Roof railing
	for _, sz in ipairs({-1, 1}) do
		local rail = bp({Name="RoofRail", Size=Vector3.new(BASE_W, 0.3, 0.3), Color=Color3.fromRGB(70,70,75), Material=Enum.Material.Metal})
		rail.CFrame = CFrame.new(BASE_X, BASE_H + 3.5, sz * BASE_D/2)
		rail.Parent = m
	end
	for _, sx in ipairs({-1, 1}) do
		local rail = bp({Name="RoofRail", Size=Vector3.new(0.3, 0.3, BASE_D), Color=Color3.fromRGB(70,70,75), Material=Enum.Material.Metal})
		rail.CFrame = CFrame.new(BASE_X + sx * BASE_W/2, BASE_H + 3.5, 0)
		rail.Parent = m
	end
	-- Railing posts
	for _, sx in ipairs({-1, 0, 1}) do
		for _, sz in ipairs({-1, 1}) do
			local rp = bp({Name="RoofPost", Size=Vector3.new(0.3, 2, 0.3), Color=Color3.fromRGB(70,70,75), Material=Enum.Material.Metal})
			rp.CFrame = CFrame.new(BASE_X + sx * BASE_W/2, BASE_H + 2.5, sz * BASE_D/2)
			rp.Parent = m
		end
	end

	-- AC unit
	local ac = bp({Name="ACUnit", Size=Vector3.new(4, 2, 3), Color=Color3.fromRGB(150,150,155), Material=Enum.Material.Metal})
	ac.CFrame = CFrame.new(BASE_X + 10, BASE_H + 3, -10)
	ac.Parent = m

	-- Vent pipe
	local vent = bp({Name="VentPipe", Size=Vector3.new(2, 4, 2), Color=Color3.fromRGB(100,100,105), Material=Enum.Material.Metal})
	vent.CFrame = CFrame.new(BASE_X - 10, BASE_H + 3, 10)
	vent.Parent = m

	-- 8. Potted plants (4 corners inside)
	for _, cx in ipairs({-1, 1}) do
		for _, cz in ipairs({-1, 1}) do
			local pot = bp({Name="PlantPot", Size=Vector3.new(3, 2, 3), Color=Color3.fromRGB(180,100,60), Material=Enum.Material.Slate, Shape=Enum.PartType.Cylinder})
			pot.CFrame = CFrame.new(BASE_X + cx * (BASE_W/2 - 4), 2, cz * (BASE_D/2 - 4)) * CFrame.Angles(0, 0, math.rad(90))
			pot.Parent = m

			local plant = bp({Name="Plant", Size=Vector3.new(2, 3, 2), Color=Color3.fromRGB(40,160,50), Material=Enum.Material.Grass})
			plant.CFrame = CFrame.new(BASE_X + cx * (BASE_W/2 - 4), 4.5, cz * (BASE_D/2 - 4))
			plant.Parent = m
		end
	end

	-- 9. Welcome mat
	local mat = bp({Name="WelcomeMat", Size=Vector3.new(4, 0.1, 8), Color=Color3.fromRGB(120,30,30), Material=Enum.Material.Fabric})
	mat.CFrame = CFrame.new(BASE_X - BASE_W/2 + 2, 1.15, 0)
	mat.CanCollide = false
	mat.Parent = m

	-- === BRAINROT THEME DECORATIONS ===

	-- 10. Brainrot character pedestals (4 display spots for caught brainrots)
	local pedestalColors = {
		Color3.fromRGB(255, 80, 80),   -- red
		Color3.fromRGB(80, 255, 120),  -- green
		Color3.fromRGB(80, 150, 255),  -- blue
		Color3.fromRGB(255, 220, 50),  -- yellow
	}
	for i, pos in ipairs({{-10, -15}, {-10, 15}, {10, -15}, {10, 15}}) do
		-- Pedestal base (rotating display feel)
		local ped = bp({Name="BrainrotPedestal", Size=Vector3.new(5, 2, 5), Color=pedestalColors[i], Material=Enum.Material.SmoothPlastic})
		ped.CFrame = CFrame.new(BASE_X + pos[1], 2, pos[2])
		studAllFaces(ped)
		ped.Parent = m

		-- Neon ring on pedestal
		local ring = bp({Name="PedestalRing", Size=Vector3.new(5.5, 0.3, 5.5), Color=pedestalColors[i], Material=Enum.Material.SmoothPlastic})
		ring.CFrame = CFrame.new(BASE_X + pos[1], 3.1, pos[2])
		ring.CanCollide = false
		ring.Parent = m

		-- Question mark placeholder (where brainrot will stand)
		local placeholder = bp({Name="Placeholder", Size=Vector3.new(2, 3, 2), Color=Color3.fromRGB(60,60,65), Material=Enum.Material.SmoothPlastic})
		placeholder.CFrame = CFrame.new(BASE_X + pos[1], 4.5, pos[2])
		placeholder.CanCollide = false
		placeholder.Parent = m
	end

	-- 11. Neon brain icon on back wall (big, centered)




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
	safeStep("buildShop", buildShop)
	safeStep("buildStatues", buildStatues)
	safeStep("buildTrees", buildTrees)
	safeStep("buildLamps", buildLamps)
	safeStep("buildBillboard", buildBillboard)
	safeStep("buildProps", buildProps)
	safeStep("buildGates", buildGates)
	safeStep("buildBase", function()
		baseModel = buildBase()
	end)

	return {
		pads = { WorldBuilder.buildSpawnPad(1) },
		bases = { baseModel },
	}
end

return WorldBuilder