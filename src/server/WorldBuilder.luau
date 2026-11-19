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
	local light = game:GetService("Lighting")

	-- Modify existing DirectionalLight instead of creating new (avoids singleton error)
	local sun = light:FindFirstChildWhichIsA("DirectionalLight")
	if sun then
		sun.Brightness = 3
		sun.Color = Color3.fromRGB(255, 250, 240)
		sun.Shadows = false
		sun.Angle = 15
	else
		-- Only create if none exists
		local ok, err = pcall(function()
			local s = Instance.new("DirectionalLight")
			s.Name = "NoonSun"
			s.Brightness = 3
			s.Color = Color3.fromRGB(255, 250, 240)
			s.Shadows = false
			s.Angle = 15
			s.Parent = light
		end)
		if not ok then
			warn("Sun create failed: " .. tostring(err))
		end
	end

	-- Kill all shadows
	light.GlobalShadows = false
	light.Ambient = Color3.fromRGB(140, 140, 140)
	light.OutdoorAmbient = Color3.fromRGB(160, 160, 160)
	light.Brightness = 3
	light.EnvironmentDiffuseScale = 1
	light.EnvironmentSpecularScale = 1
	light.ShadowSoftness = 0

	-- Noon (12:00), sun straight overhead
	light.ClockTime = 12
	light.GeographicLatitude = 0

	-- Also disable shadows on every part in workspace
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CastShadow = false
		end
	end
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
	local function bp(props)
		local p = part(props)
		p.Anchored = true
		p.CanCollide = true
		return p
	end

	local TRUNK = Color3.fromRGB(100, 65, 35)
	local LEAF_DARK = Color3.fromRGB(35, 130, 40)
	local LEAF_MID = Color3.fromRGB(50, 160, 55)
	local LEAF_LIGHT = Color3.fromRGB(70, 190, 75)

	local spots = {
		{-130, -130}, {-130, -60}, {-130, 60}, {-130, 130},
		{-80, -140}, {-20, -140}, {40, -140}, {100, -140},
		{130, -130}, {130, -60}, {130, 60}, {130, 130},
		{-80, 140}, {-20, 140}, {40, 140}, {100, 140},
	}

	for i, pos in ipairs(spots) do
		local x, z = pos[1], pos[2]
		-- Slight random variation per tree
		local scale = 1 + ((i * 37) % 5) * 0.15  -- 1.0 to 1.6

		-- Trunk (thicker, taller)
		local trunkH = 10 * scale
		local trunk = bp({Name="Trunk" .. i, Size=Vector3.new(2.5 * scale, trunkH, 2.5 * scale), Color=TRUNK, Material=Enum.Material.Plastic})
		trunk.CFrame = CFrame.new(x, trunkH/2, z)
		studAllFaces(trunk)
		trunk.Parent = m

		-- Canopy layer 1 (big, wide - bottom)
		local c1w = 12 * scale
		local c1 = bp({Name="Canopy1_" .. i, Size=Vector3.new(c1w, 7 * scale, c1w), Color=LEAF_DARK, Material=Enum.Material.Plastic})
		c1.CFrame = CFrame.new(x, trunkH + 3 * scale, z) * CFrame.Angles(0, math.rad(i * 23 % 45), 0)
		studAllFaces(c1)
		c1.Parent = m

		-- Canopy layer 2 (medium - middle)
		local c2w = 9 * scale
		local c2 = bp({Name="Canopy2_" .. i, Size=Vector3.new(c2w, 6 * scale, c2w), Color=LEAF_MID, Material=Enum.Material.Plastic})
		c2.CFrame = CFrame.new(x + math.sin(i) * 1.5, trunkH + 8 * scale, z + math.cos(i) * 1.5) * CFrame.Angles(0, math.rad(i * 47 % 60), 0)
		studAllFaces(c2)
		c2.Parent = m

		-- Canopy layer 3 (small - top)
		local c3w = 6 * scale
		local c3 = bp({Name="Canopy3_" .. i, Size=Vector3.new(c3w, 5 * scale, c3w), Color=LEAF_LIGHT, Material=Enum.Material.Plastic})
		c3.CFrame = CFrame.new(x - math.cos(i) * 1, trunkH + 12.5 * scale, z + math.sin(i) * 1) * CFrame.Angles(0, math.rad(i * 31 % 40), 0)
		studAllFaces(c3)
		c3.Parent = m

		-- Bush at base (extra rindang)
		local bush = bp({Name="Bush" .. i, Size=Vector3.new(5 * scale, 3, 5 * scale), Color=LEAF_DARK, Material=Enum.Material.Plastic})
		bush.CFrame = CFrame.new(x + 4, 1.5, z + 4) * CFrame.Angles(0, math.rad(i * 67), 0)
		studAllFaces(bush)
		bush.Parent = m

		local bush2 = bp({Name="Bush2_" .. i, Size=Vector3.new(4 * scale, 2.5, 4 * scale), Color=LEAF_MID, Material=Enum.Material.Plastic})
		bush2.CFrame = CFrame.new(x - 4, 1.25, z - 3) * CFrame.Angles(0, math.rad(i * 89), 0)
		studAllFaces(bush2)
		bush2.Parent = m
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
local baseModel2 = nil
local baseModel3 = nil

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

		-- (shadow interior removed)
		local blackFloor = bp({Name="GateFloor", Size=Vector3.new(26, 0.5, 14), Color=Color3.fromRGB(25, 25, 28), Material=Enum.Material.SmoothPlastic})
		blackFloor.CFrame = CFrame.new(0, 0.25, z)
		blackFloor.Parent = m

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

local function buildBaseAt(bx, mirror)
	local m = Instance.new("Model")
	m.Name = mirror and "Base2" or "Base1"

	local function bp(props)
		local p = part(props)
		p.Anchored = true
		p.CanCollide = true
		return p
	end

	-- Mirror: flip X offset for left-side base
	local MX = mirror and -1 or 1

	-- Palette
	local WALL = Color3.fromRGB(45, 45, 52)
	local ACCENT = Color3.fromRGB(255, 90, 60)
	local FLOOR_DARK = Color3.fromRGB(55, 55, 60)
	local FLOOR_LIGHT = Color3.fromRGB(75, 75, 82)
	local SHELF = Color3.fromRGB(90, 65, 45)
	local CEIL = Color3.fromRGB(35, 35, 40)
	local FOUNDATION = Color3.fromRGB(95, 95, 102)
	local GLASS_C = Color3.fromRGB(190, 220, 245)

	-- === THICK FOUNDATION ===
	local foundation = bp({Name="Foundation", Size=Vector3.new(BASE_W + 6, 8, BASE_D + 6), Color=FOUNDATION, Material=Enum.Material.Plastic})
	foundation.CFrame = CFrame.new(bx, -3, 0)
	studAllFaces(foundation)
	foundation.Parent = m

	local trim = bp({Name="FoundationTrim", Size=Vector3.new(BASE_W + 8, 1.5, BASE_D + 8), Color=Color3.fromRGB(70, 70, 76), Material=Enum.Material.Plastic})
	trim.CFrame = CFrame.new(bx, 1.75, 0)
	studAllFaces(trim)
	trim.Parent = m

	-- === FLOOR (checkerboard) ===
	local floorBase = bp({Name="Floor", Size=Vector3.new(BASE_W, 1, BASE_D), Color=FLOOR_DARK, Material=Enum.Material.Plastic})
	floorBase.CFrame = CFrame.new(bx, 3, 0)
	studAllFaces(floorBase)
	floorBase.Parent = m

	for tx = 0, 9 do
		for tz = 0, 7 do
			if (tx + tz) % 2 == 0 then
				local tile = bp({Name="FloorTile", Size=Vector3.new(5, 0.1, 5), Color=FLOOR_LIGHT, Material=Enum.Material.Plastic})
				tile.CFrame = CFrame.new(bx - BASE_W/2 + 2.5 + tx*5, 3.55, -BASE_D/2 + 2.5 + tz*5)
				tile.CanCollide = false
				tile.Parent = m
			end
		end
	end

	-- === WALLS ===
	local wallY = BASE_H/2 + 3.5
	-- Back wall: away from road (positive X for right base, negative X for left base)
	local backX = bx + MX * BASE_W/2
	local back = bp({Name="BackWall", Size=Vector3.new(1, BASE_H, BASE_D), Color=WALL, Material=Enum.Material.Plastic})
	back.CFrame = CFrame.new(backX, wallY, 0)
	studAllFaces(back)
	back.Parent = m

	for _, sz in ipairs({-1, 1}) do
		local wall = bp({Name="SideWall", Size=Vector3.new(BASE_W, BASE_H, 0.4), Color=GLASS_C, Material=Enum.Material.Glass})
		wall.Transparency = 0.65
		wall.CFrame = CFrame.new(bx, wallY, sz * BASE_D/2)
		wall.Parent = m

		local frame = bp({Name="WallFrame", Size=Vector3.new(BASE_W + 1, 1, 1), Color=WALL, Material=Enum.Material.Plastic})
		frame.CFrame = CFrame.new(bx, BASE_H + 4, sz * BASE_D/2)
		studAllFaces(frame)
		frame.Parent = m
	end

	local ceil = bp({Name="Ceiling", Size=Vector3.new(BASE_W + 1, 1, BASE_D + 1), Color=CEIL, Material=Enum.Material.Plastic})
	ceil.CFrame = CFrame.new(bx, BASE_H + 4.5, 0)
	studAllFaces(ceil)
	ceil.Parent = m

	-- === FRONT FRAME (open toward road) ===
	local frontX = bx - MX * BASE_W/2
	local topBeam = bp({Name="FrontBeam", Size=Vector3.new(1.5, 3, BASE_D), Color=ACCENT, Material=Enum.Material.Plastic})
	topBeam.CFrame = CFrame.new(frontX, BASE_H + 5.5, 0)
	studAllFaces(topBeam)
	topBeam.Parent = m

	for _, sz in ipairs({-1, 1}) do
		local pil = bp({Name="FrontPillar", Size=Vector3.new(2.5, BASE_H + 5, 2.5), Color=WALL, Material=Enum.Material.Plastic})
		pil.CFrame = CFrame.new(frontX, (BASE_H + 5)/2 + 3, sz * BASE_D/2)
		studAllFaces(pil)
		pil.Parent = m
	end

	-- === DISPLAY SHELVES on back wall ===
	for row = 1, 3 do
		local shelf = bp({Name="DisplayShelf", Size=Vector3.new(4, 0.6, BASE_D - 8), Color=SHELF, Material=Enum.Material.Plastic})
		shelf.CFrame = CFrame.new(backX - MX * 4, row * 4 + 5, 0)
		studAllFaces(shelf)
		shelf.Parent = m

		local panel = bp({Name="ShelfPanel", Size=Vector3.new(0.3, 3.5, BASE_D - 8), Color=Color3.fromRGB(70, 50, 35), Material=Enum.Material.Plastic})
		panel.CFrame = CFrame.new(backX - MX * 1, row * 4 + 7, 0)
		panel.Parent = m
	end

	-- === DISPLAY STEPS (4 spots) ===
	local pedColors = {
		Color3.fromRGB(220, 70, 50),
		Color3.fromRGB(50, 180, 100),
		Color3.fromRGB(60, 120, 220),
		Color3.fromRGB(230, 180, 40),
	}
	local pedPositions = {{-8, -12}, {-8, 12}, {8, -12}, {8, 12}}
	for i, pos in ipairs(pedPositions) do
		local px = bx + pos[1]
		local step1 = bp({Name="DisplayStep", Size=Vector3.new(7, 1, 7), Color=pedColors[i], Material=Enum.Material.Plastic})
		step1.CFrame = CFrame.new(px, 4, pos[2])
		studAllFaces(step1)
		step1.Parent = m

		local step2 = bp({Name="DisplayStepTop", Size=Vector3.new(5, 0.5, 5), Color=Color3.fromRGB(30,30,35), Material=Enum.Material.Plastic})
		step2.CFrame = CFrame.new(px, 4.75, pos[2])
		studAllFaces(step2)
		step2.Parent = m
	end

	-- === FRONT STEPS (toward road) ===
	for i = 1, 3 do
		local step = bp({Name="Step", Size=Vector3.new(3, 1, BASE_D - 4), Color=FOUNDATION, Material=Enum.Material.Plastic})
		step.CFrame = CFrame.new(frontX - MX * i * 2.5, 3.5 - i, 0)
		studAllFaces(step)
		step.Parent = m
	end

	-- === SIGN ===
	local sign = bp({Name="Sign", Size=Vector3.new(0.5, 4, 22), Color=Color3.fromRGB(25,25,30), Material=Enum.Material.Plastic})
	sign.CFrame = CFrame.new(frontX, BASE_H + 8, 0)
	studAllFaces(sign)
	sign.CanCollide = false
	sign.Parent = m

	local stripe = bp({Name="SignStripe", Size=Vector3.new(0.3, 0.8, 22), Color=ACCENT, Material=Enum.Material.Plastic})
	stripe.CFrame = CFrame.new(frontX - MX * 0.2, BASE_H + 6.5, 0)
	stripe.CanCollide = false
	stripe.Parent = m

	m.Parent = workspace
	return m
end

-- Build 3 bases on the RIGHT side (x=65), spaced apart along Z
local function buildBase()
	local base1 = buildBaseAt(65, false)
	base1.Name = "Base1"
	-- Shift base1 to z=0 is default; add two more at z=±100
	local base2 = buildBaseAt(65, false)
	base2.Name = "Base2"
	-- Move base2 to z=100
	for _, p in ipairs(base2:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CFrame = p.CFrame + Vector3.new(0, 0, 95)
		end
	end
	local base3 = buildBaseAt(65, false)
	base3.Name = "Base3"
	-- Move base3 to z=-100
	for _, p in ipairs(base3:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CFrame = p.CFrame + Vector3.new(0, 0, -95)
		end
	end
	return base1, base2, base3
end

-- ---------------------------------------------------------------------------
-- Build everything.
-- ---------------------------------------------------------------------------

local baseModel = nil
local baseModel2 = nil
local baseModel3 = nil

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
	safeStep("buildShop", buildShop)
	safeStep("buildStatues", buildStatues)
	safeStep("buildTrees", buildTrees)
	safeStep("buildLamps", buildLamps)
	safeStep("buildBillboard", buildBillboard)
	safeStep("buildProps", buildProps)
	safeStep("buildGates", buildGates)
	safeStep("buildBase", function()
		local b1, b2, b3 = buildBase()
		baseModel = b1
		baseModel2 = b2
		baseModel3 = b3
	end)

	return {
		pads = { WorldBuilder.buildSpawnPad(1), WorldBuilder.buildSpawnPad(2), WorldBuilder.buildSpawnPad(3) },
		bases = { baseModel, baseModel2, baseModel3 },
	}
end

return WorldBuilder