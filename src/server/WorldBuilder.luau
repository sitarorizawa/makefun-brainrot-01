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
	local function bp(props)
		local p = part(props)
		p.Anchored = true
		p.CanCollide = true
		return p
	end

	local WALL = Color3.fromRGB(80, 60, 140)     -- purple
	local WALL_DARK = Color3.fromRGB(55, 40, 100) -- darker purple
	local ROOF = Color3.fromRGB(45, 30, 80)
	local WOOD = Color3.fromRGB(150, 110, 70)
	local WOOD_DARK = Color3.fromRGB(110, 80, 50)
	local FOUND = Color3.fromRGB(100, 100, 108)
	local SIGN_C = Color3.fromRGB(0, 220, 90)

	local SX = -50  -- center X
	local SW = 30   -- width (bigger from 20)
	local SD = 26   -- depth (bigger from 20)
	local SH = 20   -- height (bigger from 15)

	-- === THICK FOUNDATION ===
	local foundation = bp({Name="Foundation", Size=Vector3.new(SW + 6, 6, SD + 6), Color=FOUND, Material=Enum.Material.Plastic})
	foundation.CFrame = CFrame.new(SX, -2, 0)
	studAllFaces(foundation)
	foundation.Parent = m

	-- === FLOOR ===
	local floor = bp({Name="Floor", Size=Vector3.new(SW, 1, SD), Color=Color3.fromRGB(65, 50, 110), Material=Enum.Material.Plastic})
	floor.CFrame = CFrame.new(SX, 1.5, 0)
	studAllFaces(floor)
	floor.Parent = m

	-- === WALLS (thick, 2 studs) ===
	-- Back wall (away from road, negative X)
	local back = bp({Name="BackWall", Size=Vector3.new(2, SH, SD), Color=WALL, Material=Enum.Material.Plastic})
	back.CFrame = CFrame.new(SX - SW/2, SH/2 + 2, 0)
	studAllFaces(back)
	back.Parent = m

	-- Side walls (thick)
	for _, sz in ipairs({-1, 1}) do
		local wall = bp({Name="SideWall", Size=Vector3.new(SW, SH, 2), Color=WALL, Material=Enum.Material.Plastic})
		wall.CFrame = CFrame.new(SX, SH/2 + 2, sz * SD/2)
		studAllFaces(wall)
		wall.Parent = m

		-- Wall pillar accents (darker, structural)
		for _, px in ipairs({-SW/2 + 2, 0, SW/2 - 2}) do
			local pillar = bp({Name="WallPillar", Size=Vector3.new(3, SH, 3), Color=WALL_DARK, Material=Enum.Material.Plastic})
			pillar.CFrame = CFrame.new(SX + px, SH/2 + 2, sz * SD/2)
			studAllFaces(pillar)
			pillar.Parent = m
		end
	end

	-- Front wall pillars (open front at positive X)
	for _, sz in ipairs({-1, 1}) do
		local fp = bp({Name="FrontPillar", Size=Vector3.new(3, SH + 2, 3), Color=WALL_DARK, Material=Enum.Material.Plastic})
		fp.CFrame = CFrame.new(SX + SW/2, (SH + 2)/2 + 2, sz * SD/2)
		studAllFaces(fp)
		fp.Parent = m
	end

	-- === ROOF (thick, overhanging) ===
	local roof = bp({Name="Roof", Size=Vector3.new(SW + 4, 2, SD + 4), Color=ROOF, Material=Enum.Material.Plastic})
	roof.CFrame = CFrame.new(SX, SH + 3.5, 0)
	studAllFaces(roof)
	roof.Parent = m

	-- Roof trim
	local roofTrim = bp({Name="RoofTrim", Size=Vector3.new(SW + 6, 1, SD + 6), Color=WALL_DARK, Material=Enum.Material.Plastic})
	roofTrim.CFrame = CFrame.new(SX, SH + 5, 0)
	studAllFaces(roofTrim)
	roofTrim.Parent = m

	-- === AWNING (striped, over entrance) ===
	for i = 0, 9 do
		local c = (i % 2 == 0) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
		local stripe = bp({Name="Awning", Size=Vector3.new(5, 0.5, SD/5), Color=c, Material=Enum.Material.Plastic})
		stripe.CFrame = CFrame.new(SX + SW/2 + 3, SH - 2, -SD/2 + (i + 0.5) * SD/10) * CFrame.Angles(0, 0, math.rad(-25))
		studAllFaces(stripe)
		stripe.Parent = m
	end

	-- === COUNTER (bigger) ===
	local counterTop = bp({Name="CounterTop", Size=Vector3.new(2, 0.5, 14), Color=WOOD, Material=Enum.Material.Plastic})
	counterTop.CFrame = CFrame.new(SX - 8, 6, 0)
	studAllFaces(counterTop)
	counterTop.Parent = m

	local counterBody = bp({Name="CounterBody", Size=Vector3.new(2, 5, 14), Color=WOOD_DARK, Material=Enum.Material.Plastic})
	counterBody.CFrame = CFrame.new(SX - 8, 3.5, 0)
	studAllFaces(counterBody)
	counterBody.Parent = m

	-- === SHELVES inside (back wall, 3 rows) ===
	for row = 1, 3 do
		local shelf = bp({Name="Shelf", Size=Vector3.new(3, 0.5, SD - 6), Color=WOOD, Material=Enum.Material.Plastic})
		shelf.CFrame = CFrame.new(SX - SW/2 + 4, row * 4 + 4, 0)
		studAllFaces(shelf)
		shelf.Parent = m
	end

	-- === SIGN above entrance ===
	local sign = bp({Name="Sign", Size=Vector3.new(1, 4, 18), Color=Color3.fromRGB(25, 25, 30), Material=Enum.Material.Plastic})
	sign.CFrame = CFrame.new(SX + SW/2, SH + 7, 0)
	studAllFaces(sign)
	sign.CanCollide = false
	sign.Parent = m

	-- Neon green stripe on sign
	local stripe2 = bp({Name="SignStripe", Size=Vector3.new(0.5, 1, 18), Color=SIGN_C, Material=Enum.Material.Plastic})
	stripe2.CFrame = CFrame.new(SX + SW/2 + 0.5, SH + 5.5, 0)
	stripe2.CanCollide = false
	stripe2.Parent = m

	-- === FRONT STEPS ===
	for i = 1, 2 do
		local step = bp({Name="Step", Size=Vector3.new(3, 1, SD - 4), Color=FOUND, Material=Enum.Material.Plastic})
		step.CFrame = CFrame.new(SX + SW/2 + i * 2.5, 1.5 - (i-1), 0)
		studAllFaces(step)
		step.Parent = m
	end

	-- === SHOPKEEPER (green, facing road) ===
	local nx, nz = SX - 2, 0
	local skin = Color3.fromRGB(255, 225, 190)
	local shirt = Color3.fromRGB(50, 170, 95)
	local pants = Color3.fromRGB(55, 55, 60)
	local hairC = Color3.fromRGB(30, 30, 30)
	local FY = 2
	-- Face road (positive X direction)
	local cf = CFrame.new(nx, 0, nz) * CFrame.Angles(0, math.rad(-90), 0)

	-- Legs
	for _, lx in ipairs({-0.55, 0.55}) do
		local leg = bp({Name="Leg", Size=Vector3.new(0.9, 2.5, 0.9), Color=pants, Material=Enum.Material.SmoothPlastic})
		leg.CFrame = cf * CFrame.new(lx, FY + 1.25, 0)
		leg.Parent = m
	end

	-- Torso
	local torso = bp({Name="Torso", Size=Vector3.new(2.4, 2.8, 1.3), Color=shirt, Material=Enum.Material.SmoothPlastic})
	torso.CFrame = cf * CFrame.new(0, FY + 3.9, 0)
	torso.Parent = m

	-- Arms
	for _, ax in ipairs({-1.65, 1.65}) do
		local arm = bp({Name="Arm", Size=Vector3.new(0.9, 2.8, 0.9), Color=shirt, Material=Enum.Material.SmoothPlastic})
		arm.CFrame = cf * CFrame.new(ax, FY + 3.9, 0)
		arm.Parent = m

		local hand = bp({Name="Hand", Size=Vector3.new(0.9, 0.6, 0.9), Color=skin, Material=Enum.Material.SmoothPlastic})
		hand.CFrame = cf * CFrame.new(ax, FY + 2.2, 0)
		hand.Parent = m
	end

	-- Head
	local head = bp({Name="Head", Size=Vector3.new(1.8, 1.8, 1.8), Color=skin, Material=Enum.Material.SmoothPlastic})
	head.CFrame = cf * CFrame.new(0, FY + 6.2, 0)
	head.Parent = m

	-- Hair
	local hairBlock = bp({Name="Hair", Size=Vector3.new(1.9, 0.7, 1.9), Color=hairC, Material=Enum.Material.SmoothPlastic})
	hairBlock.CFrame = cf * CFrame.new(0, FY + 7.4, 0)
	hairBlock.Parent = m

	-- Eyes
	for _, ex in ipairs({-0.4, 0.4}) do
		local eye = bp({Name="Eye", Size=Vector3.new(0.3, 0.35, 0.1), Color=Color3.fromRGB(30, 30, 35), Material=Enum.Material.SmoothPlastic})
		eye.CFrame = cf * CFrame.new(ex, FY + 6.4, -0.95)
		eye.CanCollide = false
		eye.Parent = m
	end

	-- Mouth
	local mouth = bp({Name="Mouth", Size=Vector3.new(0.5, 0.15, 0.1), Color=Color3.fromRGB(180, 100, 100), Material=Enum.Material.SmoothPlastic})
	mouth.CFrame = cf * CFrame.new(0, FY + 5.8, -0.95)
	mouth.CanCollide = false
	mouth.Parent = m

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

-- ---------------------------------------------------------------------------
-- Patapim Node — Rare brainrot character.
-- Proboscis monkey head + server rack tower body + ethernet cable prop.
-- ---------------------------------------------------------------------------

local function buildPatapimNode(posX, posZ)
	local m = Instance.new("Model")
	m.Name = "PatapimNode"

	local function bp(props)
		local p = part(props)
		p.Anchored = true
		p.CanCollide = true
		return p
	end

	-- Colors
	local FUR = Color3.fromRGB(110, 75, 45)
	local FUR_DARK = Color3.fromRGB(80, 55, 30)
	local FACE = Color3.fromRGB(220, 160, 130)
	local NOSE = Color3.fromRGB(200, 100, 110)
	local SERVER = Color3.fromRGB(40, 40, 46)
	local SERVER_GREY = Color3.fromRGB(80, 80, 88)
	local LED_GREEN = Color3.fromRGB(50, 255, 100)
	local LED_RED = Color3.fromRGB(255, 70, 60)
	local CABLE = Color3.fromRGB(255, 210, 50)
	local WHITE = Color3.fromRGB(245, 245, 245)
	local BLACK = Color3.fromRGB(25, 25, 30)

	local FY = 2
	local function cf(x, y, z, ry)
		return CFrame.new(posX + x, FY + y, posZ + z) * CFrame.Angles(0, math.rad(ry or 0), 0)
	end

	-- === HEAD: Proboscis monkey ===
	local skull = bp({Name="MonkeyHead", Size=Vector3.new(3.2, 3, 3), Color=FUR, Material=Enum.Material.Plastic})
	skull.CFrame = cf(0, 12, 0)
	studAllFaces(skull)
	skull.Parent = m

	-- Face plate (lighter)
	local facePlate = bp({Name="FacePlate", Size=Vector3.new(2.6, 2.4, 0.5), Color=FACE, Material=Enum.Material.Plastic})
	facePlate.CFrame = cf(0, 11.8, -1.6)
	studAllFaces(facePlate)
	facePlate.Parent = m

	-- Proboscis nose (long, hanging down - the signature)
	local nose = bp({Name="Proboscis", Size=Vector3.new(0.9, 2.2, 0.9), Color=NOSE, Material=Enum.Material.Plastic})
	nose.CFrame = cf(0, 10.5, -2) * CFrame.Angles(math.rad(15), 0, 0)
	studAllFaces(nose)
	nose.Parent = m

	-- Nose tip (bulbous)
	local noseTip = bp({Name="NoseTip", Size=Vector3.new(1.1, 0.8, 1.1), Color=NOSE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	noseTip.CFrame = cf(0, 9.5, -2.3)
	noseTip.Parent = m

	-- Eyes (white + pupil)
	for _, ex in ipairs({-0.7, 0.7}) do
		local eyeW = bp({Name="EyeWhite", Size=Vector3.new(0.7, 0.7, 0.7), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		eyeW.CFrame = cf(ex, 12.5, -1.6)
		eyeW.Parent = m

		local pupil = bp({Name="Pupil", Size=Vector3.new(0.35, 0.35, 0.35), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pupil.CFrame = cf(ex, 12.5, -1.9)
		pupil.Parent = m
	end

	-- Ears (2 big round, dark fur)
	for _, ex in ipairs({-1.8, 1.8}) do
		local ear = bp({Name="Ear", Size=Vector3.new(1.3, 1.3, 0.6), Color=FUR_DARK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ear.CFrame = cf(ex, 12.8, 0.2)
		ear.Parent = m
	end

	-- Mouth (small line)
	local mouth = bp({Name="Mouth", Size=Vector3.new(1, 0.2, 0.2), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame = cf(0, 10.8, -1.7)
	mouth.CanCollide = false
	mouth.Parent = m

	-- Hair tuft on top
	for i = -1, 1 do
		local tuft = bp({Name="HairTuft", Size=Vector3.new(0.5, 1, 0.5), Color=FUR_DARK, Material=Enum.Material.Plastic})
		tuft.CFrame = cf(i * 0.6, 14, 0) * CFrame.Angles(0, 0, math.rad(i * 20))
		tuft.Parent = m
	end

	-- === BODY: Server rack tower ===
	local server = bp({Name="ServerRack", Size=Vector3.new(3, 6, 2.5), Color=SERVER, Material=Enum.Material.Plastic})
	server.CFrame = cf(0, 6, 0.5)
	studAllFaces(server)
	server.Parent = m

	-- Server top plate
	local topPlate = bp({Name="ServerTop", Size=Vector3.new(3.3, 0.4, 2.8), Color=SERVER_GREY, Material=Enum.Material.Plastic})
	topPlate.CFrame = cf(0, 9.2, 0.5)
	studAllFaces(topPlate)
	topPlate.Parent = m

	-- LED rows (green/red status lights on front face)
	for row = 0, 6 do
		local ledColor = (row % 3 == 0) and LED_RED or LED_GREEN
		local led = bp({Name="LED", Size=Vector3.new(0.4, 0.3, 0.2), Color=ledColor, Material=Enum.Material.Plastic})
		led.CFrame = cf(-1, 4 + row * 0.8, -0.85)
		led.CanCollide = false
		led.Parent = m

		-- Second column of LEDs
		local led2 = bp({Name="LED2", Size=Vector3.new(0.4, 0.3, 0.2), Color=LED_GREEN, Material=Enum.Material.Plastic})
		led2.CFrame = cf(-0.4, 4 + row * 0.8, -0.85)
		led2.CanCollide = false
		led2.Parent = m
	end

	-- Server vents (horizontal slots on front)
	for i = 0, 3 do
		local vent = bp({Name="Vent", Size=Vector3.new(2, 0.25, 0.15), Color=SERVER_GREY, Material=Enum.Material.Plastic})
		vent.CFrame = cf(0.6, 4.5 + i * 1.2, -0.9)
		vent.CanCollide = false
		vent.Parent = m
	end

	-- === LEGS: monkey legs (thin, long) ===
	for _, lx in ipairs({-0.8, 0.8}) do
		local leg = bp({Name="Leg", Size=Vector3.new(1, 3, 1), Color=FUR, Material=Enum.Material.Plastic})
		leg.CFrame = cf(lx, 1.5, 0.5)
		studAllFaces(leg)
		leg.Parent = m

		local foot = bp({Name="Foot", Size=Vector3.new(1.2, 0.7, 1.8), Color=FUR_DARK, Material=Enum.Material.Plastic})
		foot.CFrame = cf(lx, 0.35, 0.1)
		studAllFaces(foot)
		foot.Parent = m
	end

	-- === ARMS (monkey arms, holding cable) ===
	-- Left arm at side
	local armL = bp({Name="ArmL", Size=Vector3.new(0.8, 3.5, 0.8), Color=FUR, Material=Enum.Material.Plastic})
	armL.CFrame = cf(-2.2, 7, 0.5) * CFrame.Angles(0, 0, math.rad(15))
	studAllFaces(armL)
	armL.Parent = m

	-- Right arm raised holding cable
	local armR = bp({Name="ArmR", Size=Vector3.new(0.8, 3.5, 0.8), Color=FUR, Material=Enum.Material.Plastic})
	armR.CFrame = cf(2.2, 8, 0) * CFrame.Angles(0, 0, math.rad(-35))
	studAllFaces(armR)
	armR.Parent = m

	-- Hand (right)
	local handR = bp({Name="HandR", Size=Vector3.new(0.9, 0.8, 0.9), Color=FACE, Material=Enum.Material.Plastic})
	handR.CFrame = cf(3.4, 9.8, 0)
	handR.Parent = m

	-- === PROP: Ethernet cable (yellow, hanging from hand) ===
	local cable1 = bp({Name="Cable1", Size=Vector3.new(0.3, 3, 0.3), Color=CABLE, Material=Enum.Material.Plastic})
	cable1.CFrame = cf(3.4, 8, 0) * CFrame.Angles(math.rad(10), 0, 0)
	cable1.Parent = m

	local cable2 = bp({Name="Cable2", Size=Vector3.new(0.3, 2.5, 0.3), Color=CABLE, Material=Enum.Material.Plastic})
	cable2.CFrame = cf(3.4, 5.5, 0.3) * CFrame.Angles(math.rad(-15), 0, 0)
	cable2.Parent = m

	-- RJ45 connector at cable end
	local rj45 = bp({Name="RJ45", Size=Vector3.new(0.5, 0.7, 0.4), Color=Color3.fromRGB(200, 200, 210), Material=Enum.Material.Plastic})
	rj45.CFrame = cf(3.4, 4, 0.6)
	rj45.Parent = m

	-- === LABEL ===
	local head = m:FindFirstChild("MonkeyHead")
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 340, 0, 68)
		bb.StudsOffset = Vector3.new(0, 4, 0)
		bb.MaxDistance = 50
		bb.AlwaysOnTop = false
		bb.SizeOffset = Vector2.new(0, 0)
		bb.Parent = head
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = "Patapim Node [RARE]"
		label.TextColor3 = Color3.fromRGB(100, 255, 130)
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.25
		label.TextScaled = false
		label.TextSize = 18
		label.Font = Enum.Font.GothamBold
		label.Parent = bb
	end

	m.Parent = workspace
	return m
end

-- ---------------------------------------------------------------------------
-- Bananita Whalebit — Epic brainrot character.
-- Whale head + Bitcoin golden coin body + fish tail.
-- ---------------------------------------------------------------------------

local function buildBananitaWhalebit(posX, posZ)
	local m = Instance.new("Model")
	m.Name = "BananitaWhalebit"

	local function bp(props)
		local p = part(props)
		p.Anchored = true
		p.CanCollide = true
		return p
	end

	-- Colors
	local WHALE_BLUE = Color3.fromRGB(70, 110, 160)
	local WHALE_BELLY = Color3.fromRGB(200, 220, 240)
	local GOLD = Color3.fromRGB(255, 200, 50)
	local GOLD_DARK = Color3.fromRGB(200, 155, 30)
	local WHITE = Color3.fromRGB(245, 245, 245)
	local BLACK = Color3.fromRGB(25, 25, 30)

	local FY = 2
	local function cf(x, y, z, ry)
		return CFrame.new(posX + x, FY + y, posZ + z) * CFrame.Angles(0, math.rad(ry or 0), 0)
	end

	-- === BODY: Bitcoin golden coin (BIG, clearly visible, at bottom) ===
	-- Main coin: vertical disc facing forward (front = -Z)
	local coin = bp({Name="BitcoinBody", Size=Vector3.new(5.5, 6, 1.5), Color=GOLD, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	coin.CFrame = cf(0, 5.5, 0) * CFrame.Angles(math.rad(90), 0, 0)
	studAllFaces(coin)
	coin.Parent = m

	-- Coin rim (darker gold, slightly bigger)
	local rim = bp({Name="CoinRim", Size=Vector3.new(6, 6.3, 1.2), Color=GOLD_DARK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	rim.CFrame = cf(0, 5.5, 0.1) * CFrame.Angles(math.rad(90), 0, 0)
	rim.Parent = m

	-- Bitcoin B symbol (on front face, -Z side)
	local bBar = bp({Name="BTC_B_Bar", Size=Vector3.new(0.7, 3.5, 0.3), Color=BLACK, Material=Enum.Material.Plastic})
	bBar.CFrame = cf(-0.6, 5.5, -0.9)
	bBar.CanCollide = false
	bBar.Parent = m

	local bTop = bp({Name="BTC_B_Top", Size=Vector3.new(1.8, 1.4, 0.3), Color=BLACK, Material=Enum.Material.Plastic})
	bTop.CFrame = cf(0.1, 6.8, -0.9)
	bTop.CanCollide = false
	bTop.Parent = m

	local bBot = bp({Name="BTC_B_Bot", Size=Vector3.new(2, 1.6, 0.3), Color=BLACK, Material=Enum.Material.Plastic})
	bBot.CFrame = cf(0.2, 4.2, -0.9)
	bBot.CanCollide = false
	bBot.Parent = m

	-- === HEAD: Whale (smaller, sits ON TOP of coin) ===
	local skull = bp({Name="WhaleHead", Size=Vector3.new(3.5, 3, 3.5), Color=WHALE_BLUE, Material=Enum.Material.Plastic})
	skull.CFrame = cf(0, 10, -0.5)
	studAllFaces(skull)
	skull.Parent = m

	-- Forehead dome
	local dome = bp({Name="WhaleDome", Size=Vector3.new(3, 1.2, 3), Color=WHALE_BLUE, Material=Enum.Material.Plastic})
	dome.CFrame = cf(0, 12, -0.5)
	studAllFaces(dome)
	dome.Parent = m

	-- Blowhole
	local blowhole = bp({Name="Blowhole", Size=Vector3.new(0.7, 0.4, 1), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	blowhole.CFrame = cf(0, 12.8, -0.5) * CFrame.Angles(math.rad(90), 0, 0)
	blowhole.Parent = m

	-- Snout (front, shorter)
	local snout = bp({Name="WhaleSnout", Size=Vector3.new(3.2, 1.8, 1.5), Color=WHALE_BLUE, Material=Enum.Material.Plastic})
	snout.CFrame = cf(0, 9, -2.5)
	studAllFaces(snout)
	snout.Parent = m

	-- Belly jaw (light)
	local jaw = bp({Name="WhaleJaw", Size=Vector3.new(3, 1, 1.5), Color=WHALE_BELLY, Material=Enum.Material.Plastic})
	jaw.CFrame = cf(0, 8, -2.5)
	studAllFaces(jaw)
	jaw.Parent = m

	-- Mouth line
	local mouth = bp({Name="MouthLine", Size=Vector3.new(2.8, 0.2, 0.2), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame = cf(0, 8.5, -3.3)
	mouth.CanCollide = false
	mouth.Parent = m

	-- Eyes (on sides of head, big)
	for _, ex in ipairs({-1.5, 1.5}) do
		local eyeW = bp({Name="EyeWhite", Size=Vector3.new(1, 1, 1), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		eyeW.CFrame = cf(ex, 10.5, -1.8)
		eyeW.Parent = m

		local pupil = bp({Name="Pupil", Size=Vector3.new(0.5, 0.5, 0.5), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pupil.CFrame = cf(ex + (ex > 0 and 0.15 or -0.15), 10.5, -2.2)
		pupil.Parent = m
	end

	-- Blush
	for _, ex in ipairs({-1.5, 1.5}) do
		local blush = bp({Name="Blush", Size=Vector3.new(0.7, 0.4, 0.2), Color=Color3.fromRGB(255, 150, 160), Material=Enum.Material.Plastic})
		blush.CFrame = cf(ex, 9, -3.1)
		blush.CanCollide = false
		blush.Parent = m
	end

	-- === FINS (whale side fins, attached to coin sides) ===
	for _, sx in ipairs({-1, 1}) do
		local fin = bp({Name="Fin", Size=Vector3.new(2.5, 1.2, 1.5), Color=WHALE_BLUE, Material=Enum.Material.Plastic})
		fin.CFrame = cf(sx * 3.5, 6.5, 0) * CFrame.Angles(0, 0, math.rad(sx * 25))
		studAllFaces(fin)
		fin.Parent = m
	end

	-- === LEGS (2 stubby, whale-blue) ===
	for _, lx in ipairs({-1.3, 1.3}) do
		local leg = bp({Name="Leg", Size=Vector3.new(1.3, 2.5, 1.3), Color=WHALE_BLUE, Material=Enum.Material.Plastic})
		leg.CFrame = cf(lx, 0.25, 0)
		studAllFaces(leg)
		leg.Parent = m

		local foot = bp({Name="Foot", Size=Vector3.new(1.6, 0.8, 2), Color=WHALE_BELLY, Material=Enum.Material.Plastic})
		foot.CFrame = cf(lx, -0.6, -0.3)
		studAllFaces(foot)
		foot.Parent = m
	end

	-- === TAIL (behind coin) ===
	local tail1 = bp({Name="Tail1", Size=Vector3.new(1.5, 1.5, 2), Color=WHALE_BLUE, Material=Enum.Material.Plastic})
	tail1.CFrame = cf(0, 5.5, 2) * CFrame.Angles(math.rad(-20), 0, 0)
	studAllFaces(tail1)
	tail1.Parent = m

	for _, sx in ipairs({-1, 1}) do
		local fluke = bp({Name="TailFluke", Size=Vector3.new(2, 0.5, 1.5), Color=WHALE_BLUE, Material=Enum.Material.Plastic})
		fluke.CFrame = cf(sx * 1.2, 5.5, 3.5) * CFrame.Angles(0, math.rad(sx * 35), 0)
		studAllFaces(fluke)
		fluke.Parent = m
	end

	-- === LABEL ===
	local head = m:FindFirstChild("WhaleHead")
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 340, 0, 68)
		bb.StudsOffset = Vector3.new(0, 4, 0)
		bb.MaxDistance = 50
		bb.AlwaysOnTop = false
		bb.SizeOffset = Vector2.new(0, 0)
		bb.Parent = head
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1,  0)
		label.BackgroundTransparency = 1
		label.Text = "Bananita Whalebit [EPIC]"
		label.TextColor3 = Color3.fromRGB(80, 150, 255)
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.25
		label.TextScaled = false
		label.TextSize = 18
		label.Font = Enum.Font.GothamBold
		label.Parent = bb
	end

	m.Parent = workspace
	return m
end

-- ---------------------------------------------------------------------------
--4 more brainrot characters: Rugpull, Gasfee, Airdrop, Arbitrage.
-- ---------------------------------------------------------------------------

local function buildTralaleroRugpull(posX, posZ)
	local m = Instance.new("Model"); m.Name = "TralaleroRugpull"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end

	-- SHARK HEAD
	local skull = bp({Name="Head", Size=Vector3.new(4,2.5,4), Color=Color3.fromRGB(120,140,160), Material=Enum.Material.Plastic})
	skull.CFrame=cf(0,11,0); studAllFaces(skull); skull.Parent=m
	-- Upper jaw
	local ujaw = bp({Name="UJaw", Size=Vector3.new(3.8,1.2,2.5), Color=Color3.fromRGB(130,150,170), Material=Enum.Material.Plastic})
	ujaw.CFrame=cf(0,10.2,-2.5); studAllFaces(ujaw); ujaw.Parent=m
	-- Lower jaw (open)
	local ljaw = bp({Name="LJaw", Size=Vector3.new(3.6,1,2.3), Color=Color3.fromRGB(170,190,210), Material=Enum.Material.Plastic})
	ljaw.CFrame=cf(0,8.6,-2.4)*CFrame.Angles(math.rad(-20),0,0); studAllFaces(ljaw); ljaw.Parent=m
	-- Teeth (top row)
	for i=-3,3 do
		local t=bp({Name="Tooth", Size=Vector3.new(0.5,0.8,0.4), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic})
		t.CFrame=cf(i*0.55,9.6,-3.5); t.Parent=m
	end
	-- Teeth (bottom row)
	for i=-3,3 do
		local t=bp({Name="Tooth", Size=Vector3.new(0.5,0.7,0.4), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic})
		t.CFrame=cf(i*0.55,9.3,-3.4)*CFrame.Angles(math.rad(-15),0,0); t.Parent=m
	end
	-- Eyes
	for _,ex in ipairs({-1.5,1.5}) do
		local ew=bp({Name="Eye", Size=Vector3.new(1,1,1), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ew.CFrame=cf(ex,12,-1.2); ew.Parent=m
		local pup=bp({Name="Pupil", Size=Vector3.new(0.5,0.5,0.5), Color=Color3.fromRGB(25,25,30), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pup.CFrame=cf(ex,12,-1.6); pup.Parent=m
	end
	-- Gill slits
	for _,sx in ipairs({-1,1}) do
		for g=0,2 do
			local gl=bp({Name="Gill", Size=Vector3.new(0.15,1,0.4), Color=Color3.fromRGB(90,110,130), Material=Enum.Material.Plastic})
			gl.CFrame=cf(sx*2.05,10.5,g*0.7-0.7); gl.CanCollide=false; gl.Parent=m
		end
	end

	-- MONEY BAG BODY (with hole at bottom)
	local bag1=bp({Name="BagBottom", Size=Vector3.new(4,3.5,3.5), Color=Color3.fromRGB(60,160,70), Material=Enum.Material.Plastic})
	bag1.CFrame=cf(0,6,0.5); studAllFaces(bag1); bag1.Parent=m
	local bag2=bp({Name="BagTop", Size=Vector3.new(2.5,2,2.5), Color=Color3.fromRGB(70,175,80), Material=Enum.Material.Plastic})
	bag2.CFrame=cf(0,8.8,0.5); studAllFaces(bag2); bag2.Parent=m
	-- $ symbol
	local dollar=bp({Name="Dollar", Size=Vector3.new(0.3,2,1.2), Color=Color3.fromRGB(30,30,35), Material=Enum.Material.Plastic})
	dollar.CFrame=cf(0,6,-1.3); dollar.CanCollide=false; dollar.Parent=m
	-- HOLE at bottom (dark)
	local hole=bp({Name="Hole", Size=Vector3.new(2,1,1.5), Color=Color3.fromRGB(20,20,22), Material=Enum.Material.Plastic})
	hole.CFrame=cf(0,4.2,0.5); hole.CanCollide=false; hole.Parent=m

	-- BLUE SNEAKERS (Tralalero signature)
	for _,lx in ipairs({-1.3,1.3}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.2,2,1.2), Color=Color3.fromRGB(140,160,180), Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,2.2,0.5); studAllFaces(leg); leg.Parent=m
		local shoe=bp({Name="Sneaker", Size=Vector3.new(1.5,1,2.4), Color=Color3.fromRGB(50,80,220), Material=Enum.Material.Plastic})
		shoe.CFrame=cf(lx,0.9,-0.2); studAllFaces(shoe); shoe.Parent=m
		local sole=bp({Name="Sole", Size=Vector3.new(1.6,0.4,2.5), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic})
		sole.CFrame=cf(lx,0.35,-0.2); sole.Parent=m
	end

	-- Falling coins from hole
	for i=1,3 do
		local coin=bp({Name="Coin", Size=Vector3.new(0.8,0.3,0.8), Color=Color3.fromRGB(255,200,50), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
		coin.CFrame=cf(math.sin(i*2)*1,3-i*0.9,0.5+math.cos(i)*0.6)*CFrame.Angles(math.rad(60*i),0,0)
		coin.CanCollide=false; coin.Parent=m
	end

	-- LABEL
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(skull, "Tralalero Rugpull [GOD]", Color3.fromRGB(255,100,255))

	m.Parent=workspace; return m
end

local function buildBombombiniGasfee(posX, posZ)
	local m = Instance.new("Model"); m.Name = "BombombiniGasfee"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)

	-- GOOSE NECK (segments curving up)
	local neckY=8
	for i=0,3 do
		local seg=bp({Name="Neck", Size=Vector3.new(1.5,1.5,1.5), Color=WHITE, Material=Enum.Material.Plastic})
		seg.CFrame=cf(0,neckY+i*1.5,-0.5-i*0.3); studAllFaces(seg); seg.Parent=m
	end
	-- GOOSE HEAD
	local head=bp({Name="Head", Size=Vector3.new(2.8,2.5,3), Color=WHITE, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,15,-1.8); studAllFaces(head); head.Parent=m
	-- BEAK
	local beak=bp({Name="Beak", Size=Vector3.new(1.5,1,2), Color=Color3.fromRGB(255,150,50), Material=Enum.Material.Plastic})
	beak.CFrame=cf(0,14.5,-3.8); studAllFaces(beak); beak.Parent=m
	-- Eyes
	for _,ex in ipairs({-0.9,0.9}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,15.5,-3); e.Parent=m
	end

	-- GAS CANISTER BODY
	local can=bp({Name="Canister", Size=Vector3.new(3.5,5,3.5), Color=Color3.fromRGB(50,50,55), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	can.CFrame=cf(0,5,0.5)*CFrame.Angles(0,0,math.rad(90)); studAllFaces(can); can.Parent=m
	-- Yellow hazard stripe
	local stripe=bp({Name="Stripe", Size=Vector3.new(3.7,1.2,3.7), Color=Color3.fromRGB(255,220,50), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	stripe.CFrame=cf(0,5.5,0.5)*CFrame.Angles(0,0,math.rad(90)); stripe.Parent=m
	-- Valve on top
	local valve=bp({Name="Valve", Size=Vector3.new(1,1,1), Color=Color3.fromRGB(100,100,108), Material=Enum.Material.Plastic})
	valve.CFrame=cf(0,8,0.5); studAllFaces(valve); valve.Parent=m
	local wheel=bp({Name="ValveWheel", Size=Vector3.new(1.5,0.3,1.5), Color=Color3.fromRGB(200,50,50), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	wheel.CFrame=cf(0,8.7,0.5)*CFrame.Angles(0,0,math.rad(90)); wheel.Parent=m

	-- GOOSE LEGS
	for _,lx in ipairs({-0.9,0.9}) do
		local leg=bp({Name="Leg", Size=Vector3.new(0.7,3,0.7), Color=Color3.fromRGB(255,150,50), Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.5,0.5); studAllFaces(leg); leg.Parent=m
		local foot=bp({Name="Foot", Size=Vector3.new(1,0.5,1.8), Color=Color3.fromRGB(255,150,50), Material=Enum.Material.Plastic})
		foot.CFrame=cf(lx,0.35,0.1); foot.Parent=m
	end

	-- WINGS (folded at sides)
	for _,sx in ipairs({-1,1}) do
		local wing=bp({Name="Wing", Size=Vector3.new(1.5,2.5,3.5), Color=WHITE, Material=Enum.Material.Plastic})
		wing.CFrame=cf(sx*2.5,6,0.5)*CFrame.Angles(0,0,math.rad(sx*15)); studAllFaces(wing); wing.Parent=m
	end

	-- FLAME at valve
	local flame=bp({Name="Flame", Size=Vector3.new(1,1.5,1), Color=Color3.fromRGB(255,120,30), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	flame.CFrame=cf(0,9.5,0.5); flame.CanCollide=false; flame.Parent=m
	local flame2=bp({Name="Flame2", Size=Vector3.new(0.6,1,0.6), Color=Color3.fromRGB(255,220,80), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	flame2.CFrame=cf(0,10.2,0.5); flame2.CanCollide=false; flame2.Parent=m

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Bombombini Gasfee [MYTHIC]", Color3.fromRGB(255,200,50))

	m.Parent=workspace; return m
end

local function buildBombardiroAirdrop(posX, posZ)
	local m = Instance.new("Model"); m.Name = "BombardiroAirdrop"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local GD=Color3.fromRGB(45,110,40); local PLANE=Color3.fromRGB(60,62,68); local BLACK=Color3.fromRGB(25,25,30)

	-- CROC HEAD
	local skull=bp({Name="Head", Size=Vector3.new(3.5,2.5,3.5), Color=GD, Material=Enum.Material.Plastic})
	skull.CFrame=cf(0,9,-1); studAllFaces(skull); skull.Parent=m
	local snout=bp({Name="Snout", Size=Vector3.new(3,1.5,3), Color=GD, Material=Enum.Material.Plastic})
	snout.CFrame=cf(0,8.2,-3.5); studAllFaces(snout); snout.Parent=m
	for i=-2,2 do
		local t=bp({Name="Tooth", Size=Vector3.new(0.5,0.6,0.5), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic})
		t.CFrame=cf(i*0.6,7.5,-4.8); t.Parent=m
	end
	for _,ex in ipairs({-1.2,1.2}) do
		local e=bp({Name="Eye", Size=Vector3.new(1,1,1), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,10,-1.8); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.5,0.5,0.5), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,10,-2.2); p.Parent=m
	end

	-- BOMBER PLANE BODY (the joke body)
	local fuselage=bp({Name="Fuselage", Size=Vector3.new(3,3,8), Color=PLANE, Material=Enum.Material.Plastic})
	fuselage.CFrame=cf(0,6,1); studAllFaces(fuselage); fuselage.Parent=m
	-- Wings
	for _,sx in ipairs({-1,1}) do
		local wing=bp({Name="Wing", Size=Vector3.new(7,0.5,2.5), Color=Color3.fromRGB(50,52,58), Material=Enum.Material.Plastic})
		wing.CFrame=cf(sx*4.5,6,1); studAllFaces(wing); wing.Parent=m
	end
	-- Tail fin
	local fin=bp({Name="TailFin", Size=Vector3.new(0.5,2.5,2), Color=Color3.fromRGB(50,52,58), Material=Enum.Material.Plastic})
	fin.CFrame=cf(0,8.5,4.5); studAllFaces(fin); fin.Parent=m
	-- Propeller
	local prop=bp({Name="Prop", Size=Vector3.new(0.4,4,0.4), Color=Color3.fromRGB(40,40,44), Material=Enum.Material.Plastic})
	prop.CFrame=cf(0,6,-3.5)*CFrame.Angles(0,0,math.rad(45)); prop.Parent=m
	local prop2=bp({Name="Prop2", Size=Vector3.new(0.4,4,0.4), Color=Color3.fromRGB(40,40,44), Material=Enum.Material.Plastic})
	prop2.CFrame=cf(0,6,-3.5)*CFrame.Angles(0,0,math.rad(-45)); prop2.Parent=m
	-- Landing gear / croc legs
	for _,lx in ipairs({-1.5,1.5}) do
		for _,lz in ipairs({-1,2}) do
			local leg=bp({Name="Leg", Size=Vector3.new(0.8,2.5,0.8), Color=GD, Material=Enum.Material.Plastic})
			leg.CFrame=cf(lx,2.5,lz); studAllFaces(leg); leg.Parent=m
		end
	end

	-- PARACHUTE floating above
	local chuteY=16
	-- Canopy (4 wedge panels)
	for i=0,3 do
		local ang=math.rad(i*90)
		local panel=bp({Name="Chute", Size=Vector3.new(5,0.5,5), Color=Color3.fromRGB(80,220,100), Material=Enum.Material.Plastic})
		panel.CFrame=cf(math.cos(ang)*1.5, chuteY, math.sin(ang)*1.5+1)*CFrame.Angles(math.rad(25),ang,0)
		panel.CanCollide=false; panel.Parent=m
	end
	-- Strings
	for _,sx in ipairs({-1,1}) do
		for _,sz in ipairs({-1,1}) do
			local str=bp({Name="ChuteString", Size=Vector3.new(0.15,6,0.15), Color=Color3.fromRGB(200,200,200), Material=Enum.Material.Plastic})
			str.CFrame=cf(sx*2.5, chuteY-3, 1+sz*1.5)*CFrame.Angles(math.rad(sz*15),0,math.rad(-sx*15))
			str.CanCollide=false; str.Parent=m
		end
	end
	-- Airdrop crate (hanging below chute, above plane)
	local crate=bp({Name="AirdropCrate", Size=Vector3.new(2.5,2.5,2.5), Color=Color3.fromRGB(150,110,70), Material=Enum.Material.Plastic})
	crate.CFrame=cf(0, chuteY-6.5, 1); studAllFaces(crate); crate.Parent=m
	local crateDollar=bp({Name="CrateDollar", Size=Vector3.new(0.2,1.5,0.8), Color=Color3.fromRGB(30,30,35), Material=Enum.Material.Plastic})
	crateDollar.CFrame=cf(0, chuteY-6.5, -0.3); crateDollar.CanCollide=false; crateDollar.Parent=m

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(skull, "Bombardiro Airdrop [LEGENDARY]", Color3.fromRGB(255,180,80))

	m.Parent=workspace; return m
end

local function buildBanditoreArbitrage(posX, posZ)
	local m = Instance.new("Model"); m.Name = "BanditoreArbitrage"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local BEAR=Color3.fromRGB(120,80,50); local TAN=Color3.fromRGB(200,165,115); local GOLD=Color3.fromRGB(230,180,60); local BLACK=Color3.fromRGB(25,25,30)

	-- BEAR HEAD
	local head=bp({Name="Head", Size=Vector3.new(3.5,3,3.5), Color=BEAR, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,11.5,0); studAllFaces(head); head.Parent=m
	for _,ex in ipairs({-1.3,1.3}) do
		local ear=bp({Name="Ear", Size=Vector3.new(1.2,1.2,0.6), Color=BEAR, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ear.CFrame=cf(ex,13.3,0.2); ear.Parent=m
	end
	local muzzle=bp({Name="Muzzle", Size=Vector3.new(2,1.2,1.5), Color=TAN, Material=Enum.Material.Plastic})
	muzzle.CFrame=cf(0,10.8,-1.8); studAllFaces(muzzle); muzzle.Parent=m
	local nose=bp({Name="Nose", Size=Vector3.new(0.8,0.6,0.5), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	nose.CFrame=cf(0,11.3,-2.6); nose.Parent=m
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12,-1.5); e.Parent=m
	end

	-- BALANCE SCALE BODY
	local base=bp({Name="ScaleBase", Size=Vector3.new(3.5,0.6,3.5), Color=GOLD, Material=Enum.Material.Plastic})
	base.CFrame=cf(0,4.5,0.5); studAllFaces(base); base.Parent=m
	local post=bp({Name="ScalePost", Size=Vector3.new(0.7,5,0.7), Color=GOLD, Material=Enum.Material.Plastic})
	post.CFrame=cf(0,7.3,0.5); studAllFaces(post); post.Parent=m
	local beam=bp({Name="Beam", Size=Vector3.new(6.5,0.5,0.5), Color=GOLD, Material=Enum.Material.Plastic})
	beam.CFrame=cf(0,9.8,0.5); studAllFaces(beam); beam.Parent=m
	-- Pans (left green, right red)
	for _,cfg in ipairs({{-3,Color3.fromRGB(60,200,80),"UP"},{3,Color3.fromRGB(220,70,60),"DOWN"}}) do
		local chain=bp({Name="Chain", Size=Vector3.new(0.15,2,0.15), Color=Color3.fromRGB(180,180,190), Material=Enum.Material.Plastic})
		chain.CFrame=cf(cfg[1],8.7,0.5); chain.CanCollide=false; chain.Parent=m
		local pan=bp({Name="Pan", Size=Vector3.new(2,0.4,2), Color=cfg[2], Material=Enum.Material.Plastic})
		pan.CFrame=cf(cfg[1],7.6,0.5); studAllFaces(pan); pan.Parent=m
		-- Arrow on pan
		local arrow=bp({Name="Arrow", Size=Vector3.new(0.8,1.5,0.2), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic})
		arrow.CFrame=cf(cfg[1],8.4,0.5); arrow.CanCollide=false; arrow.Parent=m
	end

	-- LEGS + ARMS
	for _,lx in ipairs({-1.3,1.3}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.3,2.5,1.3), Color=BEAR, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,2.5,0.5); studAllFaces(leg); leg.Parent=m
		local foot=bp({Name="Foot", Size=Vector3.new(1.4,0.7,1.8), Color=TAN, Material=Enum.Material.Plastic})
		foot.CFrame=cf(lx,0.6,0.1); studAllFaces(foot); foot.Parent=m
	end
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(1,3,1), Color=BEAR, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*2.8,8.5,0.5)*CFrame.Angles(0,0,math.rad(sx*20)); studAllFaces(arm); arm.Parent=m
	end

	-- Calculator prop in right paw
	local calc=bp({Name="Calc", Size=Vector3.new(1.2,1.8,0.4), Color=Color3.fromRGB(70,70,76), Material=Enum.Material.Plastic})
	calc.CFrame=cf(4.2,7.5,0); calc.Parent=m
	local screen=bp({Name="CalcScreen", Size=Vector3.new(0.9,0.5,0.1), Color=Color3.fromRGB(60,255,100), Material=Enum.Material.Plastic})
	screen.CFrame=cf(4.2,8.1,-0.2); screen.CanCollide=false; screen.Parent=m

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Banditore Arbitrage [LEGENDARY]", Color3.fromRGB(150,255,150))

	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
--6 more: Nodek, FrigoWhale, Sahur, Cappuccina, Potato, Solana.
-- ---------------------------------------------------------------------------

local function buildBrrBrrNodek(posX, posZ)
	local m = Instance.new("Model"); m.Name = "BrrBrrNodek"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local FUR=Color3.fromRGB(110,75,45); local FACE=Color3.fromRGB(220,160,130); local BLACK=Color3.fromRGB(25,25,30)

	-- MONKEY HEAD
	local head=bp({Name="Head", Size=Vector3.new(3,2.8,3), Color=FUR, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	local face=bp({Name="Face", Size=Vector3.new(2.4,2.2,0.5), Color=FACE, Material=Enum.Material.Plastic})
	face.CFrame=cf(0,11.8,-1.6); studAllFaces(face); face.Parent=m
	for _,ex in ipairs({-0.7,0.7}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.7,0.7,0.7), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.4,-1.6); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.35,0.35,0.35), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,12.4,-1.9); p.Parent=m
	end
	for _,ex in ipairs({-1.7,1.7}) do
		local ear=bp({Name="Ear", Size=Vector3.new(1.2,1.2,0.5), Color=FACE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ear.CFrame=cf(ex,12.3,0.2); ear.Parent=m
	end
	-- Smiling mouth
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.5,0.5,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,10.9,-1.7); mouth.CanCollide=false; mouth.Parent=m

	-- NODE CHAIN BODY (ring of glowing cubes around central block)
	local NODE_COLORS={Color3.fromRGB(255,50,50), Color3.fromRGB(50,255,50), Color3.fromRGB(50,80,255), Color3.fromRGB(255,220,50)}
	-- Central node block
	local center=bp({Name="NodeCenter", Size=Vector3.new(2.5,2.5,2.5), Color=Color3.fromRGB(60,60,66), Material=Enum.Material.Plastic})
	center.CFrame=cf(0,6.5,0.5); studAllFaces(center); center.Parent=m
	for i=0,2 do
		local led=bp({Name="NodeLED", Size=Vector3.new(0.5,0.4,0.3), Color=Color3.fromRGB(50,255,100), Material=Enum.Material.Plastic})
		led.CFrame=cf(-0.5+i*0.5,6.8,-0.9); led.CanCollide=false; led.Parent=m
	end
	-- Chain ring (12 cubes in circle)
	for i=0,11 do
		local ang=math.rad(i*30)
		local cube=bp({Name="ChainCube", Size=Vector3.new(0.9,0.9,0.9), Color=NODE_COLORS[(i%4)+1], Material=Enum.Material.Plastic})
		cube.CFrame=cf(math.cos(ang)*3.5, 6.5+math.sin(ang)*3.5, 0.5)
		cube.CanCollide=false; cube.Parent=m
	end

	-- LEGS + ARMS
	for _,lx in ipairs({-0.8,0.8}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1,2.5,1), Color=FUR, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,2.5,0.5); studAllFaces(leg); leg.Parent=m
	end
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(0.8,3,0.8), Color=FUR, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*2,8.5,0.5)*CFrame.Angles(0,0,math.rad(sx*40)); studAllFaces(arm); arm.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Brr Brr Nodek [EPIC]", Color3.fromRGB(100,200,255))
	m.Parent=workspace; return m
end

local function buildFrigoCameloWhale(posX, posZ)
	local m = Instance.new("Model"); m.Name = "FrigoCameloWhale"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local SANDY=Color3.fromRGB(210,175,115); local FRIDGE=Color3.fromRGB(235,235,240)

	-- CAMEL HEAD + neck
	for i=0,2 do
		local seg=bp({Name="Neck", Size=Vector3.new(2.5,2,2.5), Color=SANDY, Material=Enum.Material.Plastic})
		seg.CFrame=cf(0,9+i*2,-1-i*0.4); studAllFaces(seg); seg.Parent=m
	end
	local head=bp({Name="Head", Size=Vector3.new(3,2.5,3), Color=SANDY, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,16,-2.5); studAllFaces(head); head.Parent=m
	local snout=bp({Name="Snout", Size=Vector3.new(2,1.2,1.5), Color=Color3.fromRGB(190,155,100), Material=Enum.Material.Plastic})
	snout.CFrame=cf(0,15.3,-4); studAllFaces(snout); snout.Parent=m
	for _,ex in ipairs({-1,1}) do
		local ear=bp({Name="Ear", Size=Vector3.new(0.6,1,0.4), Color=SANDY, Material=Enum.Material.Plastic})
		ear.CFrame=cf(ex*1.3,17.3,-1.5); studAllFaces(ear); ear.Parent=m
		local e=bp({Name="Eye", Size=Vector3.new(0.7,0.7,0.7), Color=Color3.fromRGB(25,25,30), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,16.3,-3.5); e.Parent=m
	end

	-- FRIDGE BODY
	local fridge=bp({Name="Fridge", Size=Vector3.new(4,7,3), Color=FRIDGE, Material=Enum.Material.Plastic})
	fridge.CFrame=cf(0,7,1); studAllFaces(fridge); fridge.Parent=m
	-- Door split line
	local doorLine=bp({Name="DoorLine", Size=Vector3.new(0.1,6.5,3.1), Color=Color3.fromRGB(180,180,188), Material=Enum.Material.Plastic})
	doorLine.CFrame=cf(0,7,1); doorLine.CanCollide=false; doorLine.Parent=m
	-- Handle
	local handle=bp({Name="Handle", Size=Vector3.new(0.3,3,0.4), Color=Color3.fromRGB(150,150,158), Material=Enum.Material.Plastic})
	handle.CFrame=cf(1.6,7,-0.6); handle.Parent=m
	-- Magnets (decorations)
	local magColors={Color3.fromRGB(255,100,100), Color3.fromRGB(100,150,255), Color3.fromRGB(255,220,80)}
	for i,c in ipairs(magColors) do
		local mag=bp({Name="Magnet", Size=Vector3.new(0.8,0.8,0.2), Color=c, Material=Enum.Material.Plastic})
		mag.CFrame=cf(-1+i*1, 9-i*1.5, -0.6); mag.CanCollide=false; mag.Parent=m
	end

	-- CAMEL LEGS (4, tall thin)
	for _,lx in ipairs({-1.5,1.5}) do
		for _,lz in ipairs({-0.5,2.5}) do
			local leg=bp({Name="Leg", Size=Vector3.new(1,3.5,1), Color=SANDY, Material=Enum.Material.Plastic})
			leg.CFrame=cf(lx,1.75,lz); studAllFaces(leg); leg.Parent=m
			local hoof=bp({Name="Hoof", Size=Vector3.new(1.1,0.5,1.3), Color=Color3.fromRGB(60,45,30), Material=Enum.Material.Plastic})
			hoof.CFrame=cf(lx,0.25,lz-0.2); hoof.Parent=m
		end
	end

	-- WHALE POPSICLE on fridge top
	local stick=bp({Name="Stick", Size=Vector3.new(0.4,2,0.4), Color=Color3.fromRGB(200,170,120), Material=Enum.Material.Plastic})
	stick.CFrame=cf(1,12,1); stick.Parent=m
	local whalePop=bp({Name="WhalePop", Size=Vector3.new(2.5,1.5,1.5), Color=Color3.fromRGB(80,150,220), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	whalePop.CFrame=cf(1,13.5,1); whalePop.Parent=m
	local popTail=bp({Name="PopTail", Size=Vector3.new(1,0.5,1), Color=Color3.fromRGB(80,150,220), Material=Enum.Material.Plastic})
	popTail.CFrame=cf(2,13.8,1); popTail.Parent=m

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Frigo Camelo Whale [EPIC]", Color3.fromRGB(100,200,255))
	m.Parent=workspace; return m
end

local function buildTungTungSahur(posX, posZ)
	local m = Instance.new("Model"); m.Name = "TungTungSahur"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local WOOD=Color3.fromRGB(140,95,55); local SPIDER=Color3.fromRGB(70,50,35); local BLACK=Color3.fromRGB(25,25,30)

	-- WOODEN BAT HEAD (tall, elongated)
	local head=bp({Name="Head", Size=Vector3.new(2.5,4,2.5), Color=WOOD, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,13,0); studAllFaces(head); head.Parent=m
	-- Carved face
	for _,ex in ipairs({-0.5,0.5}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.3), Color=BLACK, Material=Enum.Material.Plastic})
		e.CFrame=cf(ex,13.8,-1.3); e.CanCollide=false; e.Parent=m
	end
	for i=-1,1 do
		local tooth=bp({Name="Mouth", Size=Vector3.new(0.5,0.5,0.3), Color=BLACK, Material=Enum.Material.Plastic})
		tooth.CFrame=cf(i*0.5,12,-1.3); tooth.CanCollide=false; tooth.Parent=m
	end
	-- Grain lines
	for i=0,2 do
		local grain=bp({Name="Grain", Size=Vector3.new(0.1,3.5,0.1), Color=Color3.fromRGB(110,75,40), Material=Enum.Material.Plastic})
		grain.CFrame=cf(-1.26,13,-0.5+i*0.5); grain.CanCollide=false; grain.Parent=m
	end

	-- Waist
	local waist=bp({Name="Waist", Size=Vector3.new(1.5,2,1.5), Color=WOOD, Material=Enum.Material.Plastic})
	waist.CFrame=cf(0,9.5,0); studAllFaces(waist); waist.Parent=m

	-- SPIDER ABDOMEN (body)
	local abdomen=bp({Name="Abdomen", Size=Vector3.new(4,4,4), Color=SPIDER, Material=Enum.Material.Plastic})
	abdomen.CFrame=cf(0,6,1.5); studAllFaces(abdomen); abdomen.Parent=m
	-- Eyes on abdomen
	for _,ex in ipairs({-0.7,0.7}) do
		local e=bp({Name="AbEye", Size=Vector3.new(0.6,0.6,0.6), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,6.5,-0.4); e.Parent=m
		local p=bp({Name="AbPupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,6.5,-0.7); p.Parent=m
	end

	-- 8 SPIDER LEGS
	for _,sx in ipairs({-1,1}) do
		for i=0,3 do
			local ang=(i-1.5)*25
			local leg=bp({Name="SpLeg", Size=Vector3.new(0.4,5,0.4), Color=SPIDER, Material=Enum.Material.Plastic})
			leg.CFrame=cf(sx*3,4.5,1.5)*CFrame.Angles(0,0,math.rad(sx*(60+ang)))*CFrame.Angles(math.rad((i-1.5)*15),0,0)
			studAllFaces(leg); leg.Parent=m
		end
	end

	-- WOODEN BAT prop (held up)
	local bat=bp({Name="Bat", Size=Vector3.new(0.5,6,0.5), Color=Color3.fromRGB(120,80,45), Material=Enum.Material.Plastic})
	bat.CFrame=cf(3.5,10,0)*CFrame.Angles(0,0,math.rad(-30)); studAllFaces(bat); bat.Parent=m

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Tung Tung Sahur [SECRET]", Color3.fromRGB(255,50,50))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Final3: Cappuccina, Potato, Solana.
-- ---------------------------------------------------------------------------

local function buildCapuccinaMining(posX, posZ)
	local m = Instance.new("Model"); m.Name = "CapuccinaMining"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local CAT=Color3.fromRGB(235,150,60); local CAT_DARK=Color3.fromRGB(200,120,40); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)

	-- CAT HEAD
	local head=bp({Name="Head", Size=Vector3.new(3,2.6,3), Color=CAT, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Ears (triangular wedges)
	for _,sx in ipairs({-1,1}) do
		local ear=bp({Name="Ear", Size=Vector3.new(1,1.2,0.6), Color=CAT, Material=Enum.Material.Plastic})
		ear.CFrame=cf(sx*1.1,13.7,0)*CFrame.Angles(0,0,math.rad(sx*-25)); studAllFaces(ear); ear.Parent=m
	end
	-- Muzzle + nose
	local muzzle=bp({Name="Muzzle", Size=Vector3.new(1.8,1,1), Color=WHITE, Material=Enum.Material.Plastic})
	muzzle.CFrame=cf(0,11.3,-1.7); studAllFaces(muzzle); muzzle.Parent=m
	local nose=bp({Name="Nose", Size=Vector3.new(0.5,0.3,0.3), Color=Color3.fromRGB(240,140,150), Material=Enum.Material.Plastic})
	nose.CFrame=cf(0,11.7,-2.3); nose.Parent=m
	-- Green eyes
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.65,0.65,0.65), Color=Color3.fromRGB(80,220,100), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.4,-1.4); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,12.4,-1.7); p.Parent=m
	end
	-- Whiskers
	for _,sx in ipairs({-1,1}) do
		for w=0,1 do
			local wh=bp({Name="Whisker", Size=Vector3.new(1.5,0.1,0.1), Color=WHITE, Material=Enum.Material.Plastic})
			wh.CFrame=cf(sx*1.8,11.3+w*0.4,-1.5)*CFrame.Angles(0,0,math.rad(sx*(w*10-5))); wh.CanCollide=false; wh.Parent=m
		end
	end
	-- Forehead stripes
	for i=-1,1 do
		local st=bp({Name="Stripe", Size=Vector3.new(0.4,0.5,1.5), Color=CAT_DARK, Material=Enum.Material.Plastic})
		st.CFrame=cf(i*0.7,13.4,-0.3); st.CanCollide=false; st.Parent=m
	end

	-- ESPRESSO MACHINE BODY
	local machine=bp({Name="Espresso", Size=Vector3.new(3.5,5,3), Color=Color3.fromRGB(170,170,178), Material=Enum.Material.Plastic})
	machine.CFrame=cf(0,6.5,0.5); studAllFaces(machine); machine.Parent=m
	-- Red accent panel
	local panel=bp({Name="RedPanel", Size=Vector3.new(3,1.5,0.3), Color=Color3.fromRGB(200,50,50), Material=Enum.Material.Plastic})
	panel.CFrame=cf(0,8,-1.1); panel.CanCollide=false; panel.Parent=m
	-- Portafilter spouts
	for _,sx in ipairs({-0.7,0.7}) do
		local spout=bp({Name="Spout", Size=Vector3.new(0.5,1,0.5), Color=Color3.fromRGB(120,120,128), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
		spout.CFrame=cf(sx,4.5,-1)*CFrame.Angles(math.rad(90),0,0); spout.Parent=m
	end
	-- Steam wand
	local wand=bp({Name="Wand", Size=Vector3.new(0.3,2.5,0.3), Color=Color3.fromRGB(120,120,128), Material=Enum.Material.Plastic})
	wand.CFrame=cf(2,6,-0.5)*CFrame.Angles(math.rad(20),0,0); wand.Parent=m

	-- CAT LEGS (4)
	for _,lx in ipairs({-1.3,1.3}) do
		for _,lz in ipairs({-0.5,1.5}) do
			local leg=bp({Name="Leg", Size=Vector3.new(0.9,2.5,0.9), Color=CAT, Material=Enum.Material.Plastic})
			leg.CFrame=cf(lx,1.75,lz); studAllFaces(leg); leg.Parent=m
		end
	end

	-- COFFEE CUP on top
	local cup=bp({Name="Cup", Size=Vector3.new(1.5,1.5,1.5), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	cup.CFrame=cf(0,9.8,0.5); studAllFaces(cup); cup.Parent=m
	local coffee=bp({Name="Coffee", Size=Vector3.new(1.3,0.3,1.3), Color=Color3.fromRGB(90,55,30), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	coffee.CFrame=cf(0,10.5,0.5); coffee.Parent=m
	-- Steam (translucent balls rising)
	for i=0,2 do
		local steam=bp({Name="Steam", Size=Vector3.new(0.6,0.6,0.6), Color=Color3.fromRGB(230,230,235), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		steam.Transparency=0.6-i*0.15
		steam.CFrame=cf(0,11+i*0.8,0.5+math.sin(i)*0.3)
		steam.CanCollide=false; steam.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Capuccina Mining [RARE]", Color3.fromRGB(255,190,110))
	m.Parent=workspace; return m
end

local function buildPipiPotatoStake(posX, posZ)
	local m = Instance.new("Model"); m.Name = "PipiPotatoStake"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local PIG=Color3.fromRGB(245,170,170); local PIG_DARK=Color3.fromRGB(220,130,130); local POTATO=Color3.fromRGB(200,165,110); local BLACK=Color3.fromRGB(25,25,30)

	-- PIG HEAD
	local head=bp({Name="Head", Size=Vector3.new(3,2.6,3), Color=PIG, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Ears
	for _,sx in ipairs({-1,1}) do
		local ear=bp({Name="Ear", Size=Vector3.new(1,1,0.5), Color=PIG, Material=Enum.Material.Plastic})
		ear.CFrame=cf(sx*1,13.6,-0.3)*CFrame.Angles(0,0,math.rad(sx*-20)); studAllFaces(ear); ear.Parent=m
	end
	-- Snout
	local snout=bp({Name="Snout", Size=Vector3.new(1.5,1,0.8), Color=PIG_DARK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	snout.CFrame=cf(0,11.5,-1.7)*CFrame.Angles(math.rad(90),0,0); studAllFaces(snout); snout.Parent=m
	for _,ex in ipairs({-0.3,0.3}) do
		local nostril=bp({Name="Nostril", Size=Vector3.new(0.25,0.25,0.1), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
		nostril.CFrame=cf(ex,11.5,-2.2)*CFrame.Angles(math.rad(90),0,0); nostril.CanCollide=false; nostril.Parent=m
	end
	-- Eyes + blush
	for _,ex in ipairs({-0.9,0.9}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.5,-1.4); e.Parent=m
	end

	-- POTATO BODY (lumpy, rotated)
	local potato=bp({Name="Potato", Size=Vector3.new(4,4.5,3.5), Color=POTATO, Material=Enum.Material.Plastic})
	potato.CFrame=cf(0,6.5,0.5)*CFrame.Angles(math.rad(5),math.rad(8),math.rad(3)); studAllFaces(potato); potato.Parent=m
	-- Potato eyes (dark divots)
	local potEyeSpots={{1,7.5,-1.4},{-1.2,6,-1.5},{0.5,5,1.8}}
	for _,s in ipairs(potEyeSpots) do
		local pe=bp({Name="PotEye", Size=Vector3.new(0.5,0.5,0.3), Color=Color3.fromRGB(130,100,60), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pe.CFrame=cf(s[1],s[2],s[3]); pe.CanCollide=false; pe.Parent=m
	end

	-- PIG LEGS (4)
	for _,lx in ipairs({-1.3,1.3}) do
		for _,lz in ipairs({-0.5,1.5}) do
			local leg=bp({Name="Leg", Size=Vector3.new(0.9,2,0.9), Color=PIG, Material=Enum.Material.Plastic})
			leg.CFrame=cf(lx,1.5,lz); studAllFaces(leg); leg.Parent=m
			local trotter=bp({Name="Trotter", Size=Vector3.new(1,0.5,1.2), Color=PIG_DARK, Material=Enum.Material.Plastic})
			trotter.CFrame=cf(lx,0.25,lz-0.2); trotter.Parent=m
		end
	end

	-- WOODEN STAKE FENCE prop (beside pig)
	for i=0,2 do
		local post=bp({Name="FencePost", Size=Vector3.new(0.4,3,0.4), Color=Color3.fromRGB(150,110,70), Material=Enum.Material.Plastic})
		post.CFrame=cf(3,1.5,-1+i*1.5); studAllFaces(post); post.Parent=m
	end
	for i=0,1 do
		local rail=bp({Name="FenceRail", Size=Vector3.new(0.3,0.3,3.5), Color=Color3.fromRGB(150,110,70), Material=Enum.Material.Plastic})
		rail.CFrame=cf(3,1+i*1.2,0.5); rail.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Pipi Potato Stake [UNCOMMON]", Color3.fromRGB(150,255,150))
	m.Parent=workspace; return m
end

local function buildChimpanziniSolana(posX, posZ)
	local m = Instance.new("Model"); m.Name = "ChimpanziniSolana"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local FUR=Color3.fromRGB(60,50,40); local SKIN=Color3.fromRGB(90,70,55); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)

	-- CHIMP HEAD
	local head=bp({Name="Head", Size=Vector3.new(3,2.8,3), Color=FUR, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Big flat face
	local face=bp({Name="Face", Size=Vector3.new(2.6,2.4,0.6), Color=SKIN, Material=Enum.Material.Plastic})
	face.CFrame=cf(0,11.8,-1.6); studAllFaces(face); face.Parent=m
	-- Eyes (close-set)
	for _,ex in ipairs({-0.6,0.6}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.4,-1.7); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,12.4,-2); p.Parent=m
	end
	-- Big grin
	local grin=bp({Name="Grin", Size=Vector3.new(2,0.6,0.3), Color=WHITE, Material=Enum.Material.Plastic})
	grin.CFrame=cf(0,10.8,-1.7); grin.CanCollide=false; grin.Parent=m
	-- Round ears
	for _,ex in ipairs({-1.7,1.7}) do
		local ear=bp({Name="Ear", Size=Vector3.new(1,1,0.5), Color=SKIN, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ear.CFrame=cf(ex,12.3,0.2); ear.Parent=m
	end

	-- PHONE BODY (Solana phone, vertical slab)
	local phone=bp({Name="Phone", Size=Vector3.new(3,5,0.8), Color=Color3.fromRGB(30,30,36), Material=Enum.Material.Plastic})
	phone.CFrame=cf(0,6.5,0.5); studAllFaces(phone); phone.Parent=m
	-- Screen (purple gradient-ish)
	local screen=bp({Name="Screen", Size=Vector3.new(2.6,4.5,0.2), Color=Color3.fromRGB(150,60,255), Material=Enum.Material.Plastic})
	screen.CFrame=cf(0,6.5,-0.05); screen.CanCollide=false; screen.Parent=m
	-- Solana logo (3 slanted bars)
	for i=0,2 do
		local bar=bp({Name="SolBar", Size=Vector3.new(1.8,0.4,0.1), Color=WHITE, Material=Enum.Material.Plastic})
		bar.CFrame=cf(0,7.6-i*0.7,-0.2)*CFrame.Angles(0,0,math.rad(-12)); bar.CanCollide=false; bar.Parent=m
	end
	-- Phone notch
	local notch=bp({Name="Notch", Size=Vector3.new(1,0.3,0.15), Color=BLACK, Material=Enum.Material.Plastic})
	notch.CFrame=cf(0,8.5,-0.1); notch.CanCollide=false; notch.Parent=m

	-- CHIMP LEGS (bent)
	for _,lx in ipairs({-0.9,0.9}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.1,2.5,1.1), Color=FUR, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,2.5,0.5)*CFrame.Angles(math.rad(10),0,0); studAllFaces(leg); leg.Parent=m
		local foot=bp({Name="Foot", Size=Vector3.new(1.2,0.7,1.8), Color=SKIN, Material=Enum.Material.Plastic})
		foot.CFrame=cf(lx,0.6,0.1); studAllFaces(foot); foot.Parent=m
	end

	-- LONG ARMS (chimp knuckle arms)
	local armL=bp({Name="ArmL", Size=Vector3.new(1,4.5,1), Color=FUR, Material=Enum.Material.Plastic})
	armL.CFrame=cf(-2.3,6,0.5)*CFrame.Angles(0,0,math.rad(15)); studAllFaces(armL); armL.Parent=m
	local armR=bp({Name="ArmR", Size=Vector3.new(1,4.5,1), Color=FUR, Material=Enum.Material.Plastic})
	armR.CFrame=cf(2.3,6.5,0)*CFrame.Angles(0,0,math.rad(-40)); studAllFaces(armR); armR.Parent=m

	-- BANANA prop in right hand
	local handR=bp({Name="HandR", Size=Vector3.new(1,0.8,1), Color=SKIN, Material=Enum.Material.Plastic})
	handR.CFrame=cf(4,8.8,0); handR.Parent=m
	for i=0,2 do
		local seg=bp({Name="Banana", Size=Vector3.new(0.7,1.2,0.7), Color=Color3.fromRGB(255,220,80), Material=Enum.Material.Plastic})
		seg.CFrame=cf(4,9.5+i*0.9,0)*CFrame.Angles(math.rad(i*15),0,math.rad(10)); studAllFaces(seg); seg.Parent=m
	end
	local tip=bp({Name="BananaTip", Size=Vector3.new(0.5,0.5,0.5), Color=Color3.fromRGB(80,160,50), Material=Enum.Material.Plastic})
	tip.CFrame=cf(4.2,12,0); tip.Parent=m

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Chimpanzini Solana [COMMON]", Color3.fromRGB(200,200,210))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Characters14-18: Hamstero, Lameno, Gorillah, Penguino, Froggo.
-- ---------------------------------------------------------------------------

local function buildHamsteroWheel(posX, posZ)
	local m = Instance.new("Model"); m.Name = "HamsteroWheel"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local FUR=Color3.fromRGB(200,160,110); local FUR2=Color3.fromRGB(170,130,85); local PINK=Color3.fromRGB(245,180,185); local BLACK=Color3.fromRGB(25,25,30)

	-- HAMSTER HEAD
	local head=bp({Name="Head", Size=Vector3.new(2.8,2.6,2.8), Color=FUR, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,8,0); studAllFaces(head); head.Parent=m
	for _,ex in ipairs({-1,1}) do
		local ear=bp({Name="Ear", Size=Vector3.new(0.8,0.8,0.4), Color=PINK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ear.CFrame=cf(ex*1,9.5,0.1); ear.Parent=m
	end
	local cheekL=bp({Name="Cheek", Size=Vector3.new(1.2,1.2,1.2), Color=Color3.fromRGB(230,190,140), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	cheekL.CFrame=cf(-1.1,7.5,-1); cheekL.Parent=m
	local cheekR=bp({Name="Cheek", Size=Vector3.new(1.2,1.2,1.2), Color=Color3.fromRGB(230,190,140), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	cheekR.CFrame=cf(1.1,7.5,-1); cheekR.Parent=m
	local nose=bp({Name="Nose", Size=Vector3.new(0.4,0.3,0.3), Color=PINK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	nose.CFrame=cf(0,7.8,-1.5); nose.Parent=m
	for _,ex in ipairs({-0.6,0.6}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.5,0.5,0.5), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,8.4,-1.3); e.Parent=m
	end

	-- HAMSTER BODY (round)
	local body=bp({Name="Body", Size=Vector3.new(3.2,3,3), Color=FUR, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	body.CFrame=cf(0,4.5,0.5); studAllFaces(body); body.Parent=m
	local belly=bp({Name="Belly", Size=Vector3.new(2,2,1), Color=Color3.fromRGB(240,220,190), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	belly.CFrame=cf(0,4.3,-1); belly.Parent=m

	-- WHEEL (big ring behind hamster) -4 arc segments
	for i=0,5 do
		local ang=math.rad(i*60)
		local seg=bp({Name="WheelSeg", Size=Vector3.new(1,4,0.8), Color=Color3.fromRGB(220,80,90), Material=Enum.Material.Plastic})
		seg.CFrame=cf(math.cos(ang)*4.5, 4.5+math.sin(ang)*4.5, 2)*CFrame.Angles(0,0,ang)
		studAllFaces(seg); seg.Parent=m
	end
	-- Wheel base
	local wbase=bp({Name="WheelBase", Size=Vector3.new(6,0.8,4), Color=Color3.fromRGB(120,120,128), Material=Enum.Material.Plastic})
	wbase.CFrame=cf(0,0.4,2); studAllFaces(wbase); wbase.Parent=m

	-- LEGS
	for _,lx in ipairs({-1,1}) do
		local leg=bp({Name="Leg", Size=Vector3.new(0.8,1.5,0.8), Color=FUR2, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.5,0); studAllFaces(leg); leg.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Hamstero Wheel [COMMON]", Color3.fromRGB(200,200,210))
	m.Parent=workspace; return m
end

local function buildLamenoTungsten(posX, posZ)
	local m = Instance.new("Model"); m.Name = "LamenoTungsten"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local LIZ=Color3.fromRGB(90,170,70); local LIZ2=Color3.fromRGB(60,140,50); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)

	-- LIZARD HEAD
	local head=bp({Name="Head", Size=Vector3.new(2.5,2,2.8), Color=LIZ, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,9,-0.5); studAllFaces(head); head.Parent=m
	local snout=bp({Name="Snout", Size=Vector3.new(2,1,1.8), Color=LIZ, Material=Enum.Material.Plastic})
	snout.CFrame=cf(0,8.5,-2.5); studAllFaces(snout); snout.Parent=m
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.7,0.7,0.7), Color=Color3.fromRGB(255,200,50), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,9.7,-1.3); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,9.7,-1.6); p.Parent=m
	end

	-- TUNGSTEN BAR BODY (metallic grey block)
	local bar=bp({Name="TungstenBody", Size=Vector3.new(3.5,4.5,3), Color=Color3.fromRGB(120,125,135), Material=Enum.Material.Plastic})
	bar.CFrame=cf(0,4.5,0.5); studAllFaces(bar); bar.Parent=m
	-- Metallic shine strip
	local shine=bp({Name="Shine", Size=Vector3.new(3.6,0.5,3.1), Color=Color3.fromRGB(170,175,185), Material=Enum.Material.Plastic})
	shine.CFrame=cf(0,6.5,0.5); shine.Parent=m
	-- Warning label
	local label=bp({Name="WarnLabel", Size=Vector3.new(2,1.5,0.2), Color=Color3.fromRGB(255,220,50), Material=Enum.Material.Plastic})
	label.CFrame=cf(0,4.5,-1.1); label.CanCollide=false; label.Parent=m

	-- LEGS (4 lizard legs)
	for _,sx in ipairs({-1,1}) do
		for _,sz in ipairs({-0.5,1.5}) do
			local leg=bp({Name="Leg", Size=Vector3.new(0.7,1.8,0.7), Color=LIZ2, Material=Enum.Material.Plastic})
			leg.CFrame=cf(sx*1.5,0.9,sz); studAllFaces(leg); leg.Parent=m
		end
	end

	-- TAIL (long, tapering)
	for i=0,3 do
		local t=bp({Name="Tail", Size=Vector3.new(1.5-i*0.3,0.8,1.5-i*0.3), Color=LIZ, Material=Enum.Material.Plastic})
		t.CFrame=cf(0,1.5,2.5+i*1.2); studAllFaces(t); t.Parent=m
	end

	-- DORSAL CREST (spikes on bar)
	for i=0,3 do
		local spike=bp({Name="Crest", Size=Vector3.new(0.5,1,0.5), Color=LIZ2, Material=Enum.Material.Plastic})
		spike.CFrame=cf(0,7, -0.5+i*1); spike.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Lameno Tungsten [UNCOMMON]", Color3.fromRGB(150,255,150))
	m.Parent=workspace; return m
end

local function buildGorillahMemecoin(posX, posZ)
	local m = Instance.new("Model"); m.Name = "GorillahMemecoin"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local FUR=Color3.fromRGB(50,45,40); local SKIN=Color3.fromRGB(110,90,75); local GOLD=Color3.fromRGB(255,200,50); local BLACK=Color3.fromRGB(25,25,30)

	-- GORILLA HEAD (big, wide)
	local head=bp({Name="Head", Size=Vector3.new(3.5,3,3.2), Color=FUR, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,11,0); studAllFaces(head); head.Parent=m
	local face=bp({Name="Face", Size=Vector3.new(2.8,2.2,0.5), Color=SKIN, Material=Enum.Material.Plastic})
	face.CFrame=cf(0,10.6,-1.7); studAllFaces(face); face.Parent=m
	-- Brow ridge
	local brow=bp({Name="Brow", Size=Vector3.new(2.8,0.5,0.6), Color=FUR, Material=Enum.Material.Plastic})
	brow.CFrame=cf(0,11.7,-1.7); studAllFaces(brow); brow.Parent=m
	for _,ex in ipairs({-0.7,0.7}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,11.2,-1.8); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,11.2,-2.1); p.Parent=m
	end
	local nose=bp({Name="Nose", Size=Vector3.new(1,0.6,0.4), Color=Color3.fromRGB(70,55,45), Material=Enum.Material.Plastic})
	nose.CFrame=cf(0,10.5,-2.1); nose.Parent=m
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.8,0.4,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,9.8,-1.9); mouth.CanCollide=false; mouth.Parent=m

	-- MEMECOIN BODY (stack of gold coins)
	for i=0,3 do
		local coin=bp({Name="Coin", Size=Vector3.new(4,1.2,4), Color=(i%2==0) and GOLD or Color3.fromRGB(220,170,40), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
		coin.CFrame=cf(0,6-i*1.2,0.5)*CFrame.Angles(math.rad(90),0,math.rad(i*15)); studAllFaces(coin); coin.Parent=m
	end
	-- $ on top coin
	local dollar=bp({Name="Dollar", Size=Vector3.new(0.4,2,1.2), Color=BLACK, Material=Enum.Material.Plastic})
	dollar.CFrame=cf(0,8.2,-1.4); dollar.CanCollide=false; dollar.Parent=m

	-- ARMS (long gorilla arms knuckle-down)
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(1.3,5,1.3), Color=FUR, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*3,4.5,0.5)*CFrame.Angles(0,0,math.rad(sx*10)); studAllFaces(arm); arm.Parent=m
		local hand=bp({Name="Hand", Size=Vector3.new(1.5,1.2,1.5), Color=SKIN, Material=Enum.Material.Plastic})
		hand.CFrame=cf(sx*3,1.5,0.5); studAllFaces(hand); hand.Parent=m
	end
	-- LEGS (short)
	for _,lx in ipairs({-1.3,1.3}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.5,1.8,1.5), Color=FUR, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.4,0.5); studAllFaces(leg); leg.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Gorillah Memecoin [RARE]", Color3.fromRGB(255,200,50))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Characters17-20: Penguino, Froggo, Serpentino, Owlcorn.
-- ---------------------------------------------------------------------------

local function buildPenguinoStable(posX, posZ)
	local m = Instance.new("Model"); m.Name = "PenguinoStable"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local DARK=Color3.fromRGB(40,42,50); local WHITE=Color3.fromRGB(240,242,245); local ORANGE=Color3.fromRGB(255,150,50); local BLACK=Color3.fromRGB(25,25,30)

	-- PENGUIN HEAD
	local head=bp({Name="Head", Size=Vector3.new(3,3,3), Color=DARK, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	local face=bp({Name="Face", Size=Vector3.new(2.4,2.2,0.5), Color=WHITE, Material=Enum.Material.Plastic})
	face.CFrame=cf(0,11.8,-1.6); studAllFaces(face); face.Parent=m
	local beak=bp({Name="Beak", Size=Vector3.new(1.2,0.8,1.5), Color=ORANGE, Material=Enum.Material.Plastic})
	beak.CFrame=cf(0,11.2,-2.5); studAllFaces(beak); beak.Parent=m
	for _,ex in ipairs({-0.7,0.7}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.5,0.5,0.5), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.3,-1.7); e.Parent=m
	end

	-- STABLE VAULT BODY (grey safe)
	local vault=bp({Name="Vault", Size=Vector3.new(4.5,5.5,3.5), Color=Color3.fromRGB(140,142,150), Material=Enum.Material.Plastic})
	vault.CFrame=cf(0,6,0.5); studAllFaces(vault); vault.Parent=m
	-- Vault door (circle)
	local door=bp({Name="VaultDoor", Size=Vector3.new(3,3,0.4), Color=Color3.fromRGB(110,112,120), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	door.CFrame=cf(0,6,-1.4)*CFrame.Angles(math.rad(90),0,0); studAllFaces(door); door.Parent=m
	-- Dial
	local dial=bp({Name="Dial", Size=Vector3.new(1.2,1.2,0.3), Color=Color3.fromRGB(180,182,190), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	dial.CFrame=cf(0,6,-1.7)*CFrame.Angles(math.rad(90),0,0); dial.Parent=m
	local handle=bp({Name="Handle", Size=Vector3.new(0.4,2.5,0.4), Color=Color3.fromRGB(60,60,66), Material=Enum.Material.Plastic})
	handle.CFrame=cf(0,6,-1.9)*CFrame.Angles(0,0,math.rad(45)); handle.Parent=m

	-- PENGUIN FLIPPERS + FEET
	for _,sx in ipairs({-1,1}) do
		local flip=bp({Name="Flipper", Size=Vector3.new(0.8,3.5,1.8), Color=DARK, Material=Enum.Material.Plastic})
		flip.CFrame=cf(sx*2.8,6.5,0.5)*CFrame.Angles(0,0,math.rad(sx*20)); studAllFaces(flip); flip.Parent=m
	end
	for _,lx in ipairs({-1.2,1.2}) do
		local foot=bp({Name="Foot", Size=Vector3.new(1.4,0.7,2.2), Color=ORANGE, Material=Enum.Material.Plastic})
		foot.CFrame=cf(lx,0.6,0); studAllFaces(foot); foot.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Penguino Stable [EPIC]", Color3.fromRGB(100,200,255))
	m.Parent=workspace; return m
end

local function buildFroggoMaker(posX, posZ)
	local m = Instance.new("Model"); m.Name = "FroggoMaker"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local FROG=Color3.fromRGB(70,180,80); local FROG2=Color3.fromRGB(50,150,60); local BELLY=Color3.fromRGB(200,230,170); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)

	-- FROG HEAD (wide, flat, big eyes on top)
	local head=bp({Name="Head", Size=Vector3.new(3.8,2,3.2), Color=FROG, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,9.5,-0.5); studAllFaces(head); head.Parent=m
	-- BIG frog eyes on top (bulging)
	for _,ex in ipairs({-1.2,1.2}) do
		local bulge=bp({Name="EyeBulge", Size=Vector3.new(1.5,1.5,1.5), Color=FROG, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		bulge.CFrame=cf(ex,10.8,-0.8); bulge.Parent=m
		local ew=bp({Name="EyeWhite", Size=Vector3.new(1.1,1.1,1.1), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ew.CFrame=cf(ex,11,-1.2); ew.Parent=m
		local pup=bp({Name="Pupil", Size=Vector3.new(0.55,0.55,0.55), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pup.CFrame=cf(ex,11,-1.7); pup.Parent=m
	end
	-- Wide mouth
	local mouth=bp({Name="Mouth", Size=Vector3.new(3.4,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,8.8,-2); mouth.CanCollide=false; mouth.Parent=m
	-- Belly
	local belly=bp({Name="Belly", Size=Vector3.new(3,1.5,0.4), Color=BELLY, Material=Enum.Material.Plastic})
	belly.CFrame=cf(0,8.8,-1.9); belly.CanCollide=false; belly.Parent=m

	-- TOKEN MAKER MACHINE BODY
	local machine=bp({Name="Machine", Size=Vector3.new(4,5,3.5), Color=Color3.fromRGB(90,90,100), Material=Enum.Material.Plastic})
	machine.CFrame=cf(0,5,0.5); studAllFaces(machine); machine.Parent=m
	-- Slot (where tokens come out)
	local slot=bp({Name="Slot", Size=Vector3.new(2.5,0.6,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	slot.CFrame=cf(0,4.5,-1.3); slot.CanCollide=false; slot.Parent=m
	-- Token coming out
	local token=bp({Name="Token", Size=Vector3.new(1.5,0.4,1.5), Color=Color3.fromRGB(255,200,50), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	token.CFrame=cf(0,3.8,-2)*CFrame.Angles(math.rad(90),0,0); token.CanCollide=false; token.Parent=m
	-- Gears on side (decorative)
	for i=0,1 do
		local gear=bp({Name="Gear", Size=Vector3.new(1.5,1.5,0.4), Color=Color3.fromRGB(150,150,160), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
		gear.CFrame=cf(2.1,4.5+i*1.8,0.5)*CFrame.Angles(0,0,math.rad(90)); gear.Parent=m
	end

	-- FROG LEGS (long, bent)
	for _,sx in ipairs({-1,1}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.2,2.5,1.2), Color=FROG2, Material=Enum.Material.Plastic})
		leg.CFrame=cf(sx*2,1.75,1)*CFrame.Angles(math.rad(-15),0,0); studAllFaces(leg); leg.Parent=m
		local foot=bp({Name="Foot", Size=Vector3.new(1.6,0.6,2.4), Color=FROG2, Material=Enum.Material.Plastic})
		foot.CFrame=cf(sx*2,0.5,0.3); studAllFaces(foot); foot.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Froggo Maker [MYTHIC]", Color3.fromRGB(255,200,50))
	m.Parent=workspace; return m
end

local function buildSerpentinoDex(posX, posZ)
	local m = Instance.new("Model"); m.Name = "SerpentinoDex"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local SNAKE=Color3.fromRGB(180,140,50); local SNAKE2=Color3.fromRGB(150,115,40); local BELLY=Color3.fromRGB(240,230,190); local BLACK=Color3.fromRGB(25,25,30)

	-- SNAKE HEAD (hooded cobra, up high)
	local head=bp({Name="Head", Size=Vector3.new(2.5,2.5,3), Color=SNAKE, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,13,-0.5); studAllFaces(head); head.Parent=m
	-- Cobra hood (wide flat behind head)
	local hood=bp({Name="Hood", Size=Vector3.new(4.5,3.5,0.8), Color=SNAKE2, Material=Enum.Material.Plastic})
	hood.CFrame=cf(0,12.5,1); studAllFaces(hood); hood.Parent=m
	-- Snake eyes (red, angry)
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=Color3.fromRGB(255,60,50), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,13.6,-1.7); e.Parent=m
	end
	-- Fangs
	for _,ex in ipairs({-0.5,0.5}) do
		local fang=bp({Name="Fang", Size=Vector3.new(0.3,0.8,0.3), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic})
		fang.CFrame=cf(ex,11.8,-1.8); fang.Parent=m
	end
	local tongue=bp({Name="Tongue", Size=Vector3.new(0.3,0.2,1.5), Color=Color3.fromRGB(230,60,80), Material=Enum.Material.Plastic})
	tongue.CFrame=cf(0,12,-2.8); tongue.CanCollide=false; tongue.Parent=m

	-- DEX MACHINE BODY (trading screen)
	local machine=bp({Name="DexBody", Size=Vector3.new(4.5,5.5,3), Color=Color3.fromRGB(35,38,45), Material=Enum.Material.Plastic})
	machine.CFrame=cf(0,6,0.5); studAllFaces(machine); machine.Parent=m
	-- Chart screen (green candlesticks)
	local screen=bp({Name="Screen", Size=Vector3.new(4,4,0.3), Color=Color3.fromRGB(20,60,30), Material=Enum.Material.Plastic})
	screen.CFrame=cf(0,6.5,-1.2); screen.CanCollide=false; screen.Parent=m
	for i=0,3 do
		local candle=bp({Name="Candle", Size=Vector3.new(0.5,1+i*0.5,0.15), Color=Color3.fromRGB(60,255,110), Material=Enum.Material.Plastic})
		candle.CFrame=cf(-1.2+i*0.8,6+i*0.3,-1.4); candle.CanCollide=false; candle.Parent=m
	end

	-- SNAKE BODY (coiled around machine - segments)
	for i=0,7 do
		local ang=math.rad(i*45)
		local seg=bp({Name="Coil", Size=Vector3.new(2,1.5,2), Color=(i%2==0) and SNAKE or SNAKE2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		seg.CFrame=cf(math.cos(ang)*3, 3+math.sin(ang)*2, 1.5+math.sin(ang*0.5))
		studAllFaces(seg); seg.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Serpentino Dex [LEGENDARY]", Color3.fromRGB(150,255,150))
	m.Parent=workspace; return m
end

local function buildOwlcornOracle(posX, posZ)
	local m = Instance.new("Model"); m.Name = "OwlcornOracle"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local OWL=Color3.fromRGB(140,100,65); local OWL2=Color3.fromRGB(110,75,50); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30); local GOLD=Color3.fromRGB(255,200,50)

	-- OWL HEAD (round, big eyes)
	local head=bp({Name="Head", Size=Vector3.new(3.5,3.2,3.2), Color=OWL, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Facial disc (lighter)
	local disc=bp({Name="FaceDisc", Size=Vector3.new(3,2.6,0.5), Color=Color3.fromRGB(180,145,105), Material=Enum.Material.Plastic})
	disc.CFrame=cf(0,11.8,-1.6); studAllFaces(disc); disc.Parent=m
	-- HUGE owl eyes
	for _,ex in ipairs({-0.9,0.9}) do
		local ew=bp({Name="EyeWhite", Size=Vector3.new(1.3,1.3,1.3), Color=GOLD, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ew.CFrame=cf(ex,12.2,-1.7); ew.Parent=m
		local pup=bp({Name="Pupil", Size=Vector3.new(0.7,0.7,0.7), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pup.CFrame=cf(ex,12.2,-2.2); pup.Parent=m
	end
	-- Beak
	local beak=bp({Name="Beak", Size=Vector3.new(0.8,1,1.3), Color=Color3.fromRGB(255,170,60), Material=Enum.Material.Plastic})
	beak.CFrame=cf(0,11,-2.3)*CFrame.Angles(math.rad(20),0,0); studAllFaces(beak); beak.Parent=m
	-- UNICORN HORN (spiral gold)
	for i=0,4 do
		local hornSeg=bp({Name="Horn", Size=Vector3.new(0.7-i*0.1,0.7,0.7-i*0.1), Color=GOLD, Material=Enum.Material.Plastic})
		hornSeg.CFrame=cf(0,14+i*0.6,0)*CFrame.Angles(math.rad(i*15),0,0); studAllFaces(hornSeg); hornSeg.Parent=m
	end
	-- Ear tufts
	for _,sx in ipairs({-1,1}) do
		local tuft=bp({Name="EarTuft", Size=Vector3.new(0.6,1.5,0.4), Color=OWL2, Material=Enum.Material.Plastic})
		tuft.CFrame=cf(sx*1.5,14,0)*CFrame.Angles(0,0,math.rad(sx*-15)); studAllFaces(tuft); tuft.Parent=m
	end

	-- BODY (owl, round, feathers)
	local body=bp({Name="Body", Size=Vector3.new(3.5,4,3.2), Color=OWL, Material=Enum.Material.Plastic})
	body.CFrame=cf(0,7,0.5); studAllFaces(body); body.Parent=m
	local chest=bp({Name="Chest", Size=Vector3.new(2.5,3,0.5), Color=Color3.fromRGB(180,145,105), Material=Enum.Material.Plastic})
	chest.CFrame=cf(0,7,-1.4); chest.CanCollide=false; chest.Parent=m

	-- ORACLE CRYSTAL BALL (held below)
	local stand=bp({Name="BallStand", Size=Vector3.new(1.5,1,1.5), Color=Color3.fromRGB(100,75,50), Material=Enum.Material.Plastic})
	stand.CFrame=cf(0,3.5,2); studAllFaces(stand); stand.Parent=m
	local ball=bp({Name="CrystalBall", Size=Vector3.new(2.2,2.2,2.2), Color=Color3.fromRGB(150,200,255), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	ball.Transparency=0.4
	ball.CFrame=cf(0,5,2); ball.CanCollide=false; ball.Parent=m
	-- Glow inside ball
	local glow=bp({Name="BallGlow", Size=Vector3.new(1,1,1), Color=Color3.fromRGB(200,230,255), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	glow.CFrame=cf(0,5,2); glow.CanCollide=false; glow.Parent=m

	-- WINGS + FEET
	for _,sx in ipairs({-1,1}) do
		local wing=bp({Name="Wing", Size=Vector3.new(1,3.5,2.5), Color=OWL2, Material=Enum.Material.Plastic})
		wing.CFrame=cf(sx*2.3,7,0.5)*CFrame.Angles(0,0,math.rad(sx*15)); studAllFaces(wing); wing.Parent=m
	end
	for _,lx in ipairs({-1,1}) do
		local foot=bp({Name="Foot", Size=Vector3.new(1.2,0.8,1.6), Color=Color3.fromRGB(255,170,60), Material=Enum.Material.Plastic})
		foot.CFrame=cf(lx,0.6,0); studAllFaces(foot); foot.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Owlcorn Oracle [EPIC]", Color3.fromRGB(100,200,255))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Characters21-23: Elephante, Crabetto, Pandano.
-- ---------------------------------------------------------------------------

local function buildElephanteBridge(posX, posZ)
	local m = Instance.new("Model"); m.Name = "ElephanteBridge"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local GREY=Color3.fromRGB(150,155,165); local GREY2=Color3.fromRGB(125,130,140); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)

	-- ELEPHANT HEAD (big, with trunk)
	local head=bp({Name="Head", Size=Vector3.new(4,3.5,3.5), Color=GREY, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Ears (big flat)
	for _,sx in ipairs({-1,1}) do
		local ear=bp({Name="Ear", Size=Vector3.new(0.6,3,3.5), Color=GREY2, Material=Enum.Material.Plastic})
		ear.CFrame=cf(sx*2.3,12,0.3); studAllFaces(ear); ear.Parent=m
	end
	-- TRUNK (curled, segments going down then up)
	local trunkSegs={{0,10.5,-2},{0,9,-2.4},{0,7.5,-2.4},{0,6.2,-1.8},{0,5.5,-0.8}}
	for i,pos in ipairs(trunkSegs) do
		local t=bp({Name="Trunk", Size=Vector3.new(1.2-i*0.1,1.5,1.2-i*0.1), Color=GREY, Material=Enum.Material.Plastic})
		t.CFrame=cf(pos[1],pos[2],pos[3]); studAllFaces(t); t.Parent=m
	end
	-- Tusks
	for _,sx in ipairs({-1,1}) do
		local tusk=bp({Name="Tusk", Size=Vector3.new(0.5,2,0.5), Color=WHITE, Material=Enum.Material.Plastic})
		tusk.CFrame=cf(sx*1.2,9.5,-2.5)*CFrame.Angles(math.rad(-30),0,0); studAllFaces(tusk); tusk.Parent=m
	end
	-- Eyes
	for _,ex in ipairs({-1.2,1.2}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,13,-1.5); e.Parent=m
	end

	-- BRIDGE BODY (road deck with railings)
	local deck=bp({Name="BridgeDeck", Size=Vector3.new(4,1.5,7), Color=Color3.fromRGB(130,95,60), Material=Enum.Material.Plastic})
	deck.CFrame=cf(0,6,0.5); studAllFaces(deck); deck.Parent=m
	-- Railings (both sides)
	for _,sx in ipairs({-1,1}) do
		local rail=bp({Name="Rail", Size=Vector3.new(0.3,1.5,7), Color=Color3.fromRGB(90,65,40), Material=Enum.Material.Plastic})
		rail.CFrame=cf(sx*2,7.5,0.5); studAllFaces(rail); rail.Parent=m
	end
	-- Bridge supports (stone pillars underneath)
	for _,lz in ipairs({-2,3}) do
		local pillar=bp({Name="BridgePillar", Size=Vector3.new(3,5,1.5), Color=GREY2, Material=Enum.Material.Plastic})
		pillar.CFrame=cf(0,2.5,lz+0.5); studAllFaces(pillar); pillar.Parent=m
	end

	-- LEGS (4 elephant legs)
	for _,sx in ipairs({-1,1}) do
		for _,sz in ipairs({-0.5,2.5}) do
			local leg=bp({Name="Leg", Size=Vector3.new(2,4,2), Color=GREY, Material=Enum.Material.Plastic})
			leg.CFrame=cf(sx*2,2,sz+0.5); studAllFaces(leg); leg.Parent=m
			local foot=bp({Name="Foot", Size=Vector3.new(2.3,1,2.3), Color=GREY2, Material=Enum.Material.Plastic})
			foot.CFrame=cf(sx*2,0.5,sz+0.5); studAllFaces(foot); foot.Parent=m
		end
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Elephante Bridge [RARE]", Color3.fromRGB(200,200,210))
	m.Parent=workspace; return m
end

local function buildCrabettoCex(posX, posZ)
	local m = Instance.new("Model"); m.Name = "CrabettoCex"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local CRAB=Color3.fromRGB(230,90,70); local CRAB2=Color3.fromRGB(200,70,55); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)

	-- CRAB HEAD/SHELL (wide, domed)
	local shell=bp({Name="Shell", Size=Vector3.new(4.5,2.5,3.5), Color=CRAB, Material=Enum.Material.Plastic})
	shell.CFrame=cf(0,11,0.5); studAllFaces(shell); shell.Parent=m
	-- Shell bumps
	for _,sx in ipairs({-1.2,0,1.2}) do
		local bump=bp({Name="ShellBump", Size=Vector3.new(1,0.8,1), Color=CRAB2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		bump.CFrame=cf(sx,12.3,0.5); bump.Parent=m
	end
	-- Stalk eyes (crab signature - eyes on stalks)
	for _,sx in ipairs({-1,1}) do
		local stalk=bp({Name="EyeStalk", Size=Vector3.new(0.4,1.5,0.4), Color=CRAB2, Material=Enum.Material.Plastic})
		stalk.CFrame=cf(sx*0.8,12.5,-1); studAllFaces(stalk); stalk.Parent=m
		local ew=bp({Name="EyeWhite", Size=Vector3.new(0.8,0.8,0.8), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ew.CFrame=cf(sx*0.8,13.4,-1); ew.Parent=m
		local pup=bp({Name="Pupil", Size=Vector3.new(0.4,0.4,0.4), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pup.CFrame=cf(sx*0.8,13.4,-1.3); pup.Parent=m
	end
	-- Mouth
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.5,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,10,-1.4); mouth.CanCollide=false; mouth.Parent=m

	-- CEX BUILDING BODY (bank-like with columns)
	local cexBody=bp({Name="CexBody", Size=Vector3.new(5,6,4), Color=Color3.fromRGB(220,215,200), Material=Enum.Material.Plastic})
	cexBody.CFrame=cf(0,4,0.5); studAllFaces(cexBody); cexBody.Parent=m
	-- Bank columns (front)
	for i=-2,2 do
		local col=bp({Name="Column", Size=Vector3.new(0.8,5,0.8), Color=WHITE, Material=Enum.Material.Plastic})
		col.CFrame=cf(i*1.2,4,-1.6); studAllFaces(col); col.Parent=m
	end
	-- Pediment (triangle top)
	local ped=bp({Name="Pediment", Size=Vector3.new(5.5,1.5,4.5), Color=Color3.fromRGB(200,195,180), Material=Enum.Material.Plastic})
	ped.CFrame=cf(0,7.7,0.5); studAllFaces(ped); ped.Parent=m
	-- $ sign
	local dollar=bp({Name="Dollar", Size=Vector3.new(1.5,2,0.3), Color=Color3.fromRGB(255,200,50), Material=Enum.Material.Plastic})
	dollar.CFrame=cf(0,7.7,-1.9); dollar.CanCollide=false; dollar.Parent=m

	-- CRAB CLAWS (big, raised)
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="ClawArm", Size=Vector3.new(1.2,3,1.2), Color=CRAB2, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*3.5,8,0.5)*CFrame.Angles(0,0,math.rad(sx*30)); studAllFaces(arm); arm.Parent=m
		-- Claw pincer (2 parts)
		local clawBase=bp({Name="Claw", Size=Vector3.new(1.8,1.5,1.5), Color=CRAB, Material=Enum.Material.Plastic})
		clawBase.CFrame=cf(sx*4.8,10,0.5); studAllFaces(clawBase); clawBase.Parent=m
		local pincer=bp({Name="Pincer", Size=Vector3.new(1.5,0.7,0.8), Color=CRAB2, Material=Enum.Material.Plastic})
		pincer.CFrame=cf(sx*4.8,10.9,0.5)*CFrame.Angles(0,0,math.rad(sx*15)); studAllFaces(pincer); pincer.Parent=m
	end
	-- Small legs
	for _,sx in ipairs({-1,1}) do
		for i=0,2 do
			local leg=bp({Name="Leg", Size=Vector3.new(0.5,2,0.5), Color=CRAB2, Material=Enum.Material.Plastic})
			leg.CFrame=cf(sx*(2+i*0.4),1.5,-0.5+i*1.2)*CFrame.Angles(0,0,math.rad(sx*35)); studAllFaces(leg); leg.Parent=m
		end
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(shell, "Crabetto CEX [LEGENDARY]", Color3.fromRGB(255,150,130))
	m.Parent=workspace; return m
end

local function buildPandanoVault(posX, posZ)
	local m = Instance.new("Model"); m.Name = "PandanoVault"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local BLACK=Color3.fromRGB(35,35,38); local WHITE=Color3.fromRGB(240,240,245); local GREY=Color3.fromRGB(140,142,150); local PINK=Color3.fromRGB(245,180,185)

	-- PANDA HEAD (black & white)
	local head=bp({Name="Head", Size=Vector3.new(3.5,3.2,3.2), Color=WHITE, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Black ears
	for _,sx in ipairs({-1,1}) do
		local ear=bp({Name="Ear", Size=Vector3.new(1.2,1.2,0.8), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ear.CFrame=cf(sx*1.4,14,0.2); ear.Parent=m
	end
	-- Black eye patches
	for _,sx in ipairs({-1,1}) do
		local patch=bp({Name="EyePatch", Size=Vector3.new(1.3,1.3,0.4), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		patch.CFrame=cf(sx*0.9,12.4,-1.5); patch.Parent=m
		local ew=bp({Name="EyeWhite", Size=Vector3.new(0.5,0.5,0.5), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		ew.CFrame=cf(sx*0.9,12.4,-1.8); ew.Parent=m
		local pup=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pup.CFrame=cf(sx*0.9,12.4,-2); pup.Parent=m
	end
	-- Nose + mouth
	local nose=bp({Name="Nose", Size=Vector3.new(0.7,0.5,0.4), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	nose.CFrame=cf(0,11.5,-1.7); nose.Parent=m
	local mouth=bp({Name="Mouth", Size=Vector3.new(1,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,10.9,-1.6); mouth.CanCollide=false; mouth.Parent=m

	-- VAULT BODY (round, metallic with door)
	local vault=bp({Name="Vault", Size=Vector3.new(5,6,4.5), Color=GREY, Material=Enum.Material.Plastic})
	vault.CFrame=cf(0,5,0.5); studAllFaces(vault); vault.Parent=m
	-- Vault door
	local door=bp({Name="VaultDoor", Size=Vector3.new(3.5,3.5,0.5), Color=Color3.fromRGB(110,112,120), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	door.CFrame=cf(0,5,-1.9)*CFrame.Angles(math.rad(90),0,0); studAllFaces(door); door.Parent=m
	-- Combination dial
	local dial=bp({Name="Dial", Size=Vector3.new(1.5,1.5,0.4), Color=Color3.fromRGB(60,60,66), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	dial.CFrame=cf(0,5,-2.2)*CFrame.Angles(math.rad(90),0,0); dial.Parent=m
	local spokes=bp({Name="DialSpokes", Size=Vector3.new(2.5,0.4,0.3), Color=Color3.fromRGB(60,60,66), Material=Enum.Material.Plastic})
	spokes.CFrame=cf(0,5,-2.4); spokes.Parent=m
	-- Gold trim on vault
	local trim=bp({Name="GoldTrim", Size=Vector3.new(5.2,0.6,4.7), Color=Color3.fromRGB(255,200,50), Material=Enum.Material.Plastic})
	trim.CFrame=cf(0,8,0.5); studAllFaces(trim); trim.Parent=m

	-- PANDA ARMS (black) + LEGS
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(1.3,3.5,1.3), Color=BLACK, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*3.3,7,0.5)*CFrame.Angles(0,0,math.rad(sx*20)); studAllFaces(arm); arm.Parent=m
		local paw=bp({Name="Paw", Size=Vector3.new(1.4,1.2,1.4), Color=BLACK, Material=Enum.Material.Plastic})
		paw.CFrame=cf(sx*4,5,0.5); studAllFaces(paw); paw.Parent=m
	end
	for _,sx in ipairs({-1,1}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.8,2.5,1.8), Color=BLACK, Material=Enum.Material.Plastic})
		leg.CFrame=cf(sx*1.6,1.25,0.5); studAllFaces(leg); leg.Parent=m
		local foot=bp({Name="Foot", Size=Vector3.new(2,1,2.4), Color=BLACK, Material=Enum.Material.Plastic})
		foot.CFrame=cf(sx*1.6,0.5,0.2); studAllFaces(foot); foot.Parent=m
		-- Paw pad
		local pad=bp({Name="Pad", Size=Vector3.new(1.2,0.3,1.2), Color=PINK, Material=Enum.Material.Plastic})
		pad.CFrame=cf(sx*1.6,0.05,0.2); pad.CanCollide=false; pad.Parent=m
	end

	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Pandano Vault [MYTHIC]", Color3.fromRGB(255,200,50))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Characters24-28: Tortuga, Viperino, Aquilino, Cucumbro, Gelatino.
-- ---------------------------------------------------------------------------

local function buildTortugaLedger(posX, posZ)
	local m = Instance.new("Model"); m.Name = "TortugaLedger"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local SHELL=Color3.fromRGB(90,140,60); local SKIN=Color3.fromRGB(160,190,120); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Turtle head
	local head=bp({Name="Head", Size=Vector3.new(2.5,2.2,2.5), Color=SKIN, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,9,-1.5); studAllFaces(head); head.Parent=m
	for _,ex in ipairs({-0.7,0.7}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.5,0.5,0.5), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,9.7,-2.4); e.Parent=m
	end
	-- Shell body (ledger book inside)
	local shell=bp({Name="Shell", Size=Vector3.new(4.5,3,4.5), Color=SHELL, Material=Enum.Material.Plastic})
	shell.CFrame=cf(0,5.5,0.5); studAllFaces(shell); shell.Parent=m
	-- Ledger book on shell
	local book=bp({Name="Ledger", Size=Vector3.new(3.5,1,3), Color=Color3.fromRGB(70,50,120), Material=Enum.Material.Plastic})
	book.CFrame=cf(0,7.5,0.5); studAllFaces(book); book.Parent=m
	local pages=bp({Name="Pages", Size=Vector3.new(3.2,0.6,2.7), Color=WHITE, Material=Enum.Material.Plastic})
	pages.CFrame=cf(0,7.7,0.5); pages.Parent=m
	-- Legs
	for _,sx in ipairs({-1,1}) do
		for _,sz in ipairs({-1,2}) do
			local leg=bp({Name="Leg", Size=Vector3.new(1,1.5,1), Color=SKIN, Material=Enum.Material.Plastic})
			leg.CFrame=cf(sx*2,0.75,sz); studAllFaces(leg); leg.Parent=m
		end
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Tortuga Ledger [COMMON]", Color3.fromRGB(200,200,210))
	m.Parent=workspace; return m
end

local function buildViperinoNode(posX, posZ)
	local m = Instance.new("Model"); m.Name = "ViperinoNode"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local VIPER=Color3.fromRGB(70,160,90); local VIPER2=Color3.fromRGB(50,130,70); local BLACK=Color3.fromRGB(25,25,30)
	-- Viper head (triangle-ish)
	local head=bp({Name="Head", Size=Vector3.new(2.2,1.8,2.8), Color=VIPER, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,-0.5); studAllFaces(head); head.Parent=m
	local snout=bp({Name="Snout", Size=Vector3.new(1.5,0.8,1.8), Color=VIPER, Material=Enum.Material.Plastic})
	snout.CFrame=cf(0,11.5,-2.5); studAllFaces(snout); snout.Parent=m
	for _,ex in ipairs({-0.6,0.6}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.5,0.5,0.5), Color=Color3.fromRGB(255,200,50), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.4,-1.4); e.Parent=m
	end
	local tongue=bp({Name="Tongue", Size=Vector3.new(0.2,0.15,1.2), Color=Color3.fromRGB(230,60,80), Material=Enum.Material.Plastic})
	tongue.CFrame=cf(0,11.3,-3.6); tongue.CanCollide=false; tongue.Parent=m
	-- Node tower body (server)
	local tower=bp({Name="NodeTower", Size=Vector3.new(3,6,3), Color=Color3.fromRGB(50,50,56), Material=Enum.Material.Plastic})
	tower.CFrame=cf(0,6,0.5); studAllFaces(tower); tower.Parent=m
	for i=0,4 do
		local led=bp({Name="LED", Size=Vector3.new(0.4,0.3,0.2), Color=(i%2==0) and Color3.fromRGB(50,255,100) or Color3.fromRGB(255,70,60), Material=Enum.Material.Plastic})
		led.CFrame=cf(-0.5,3.5+i*1,-1.1); led.CanCollide=false; led.Parent=m
	end
	-- Snake coils around tower
	for i=0,5 do
		local ang=math.rad(i*60)
		local coil=bp({Name="Coil", Size=Vector3.new(1.5,1.2,1.5), Color=(i%2==0) and VIPER or VIPER2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		coil.CFrame=cf(math.cos(ang)*2.5, 3.5+math.sin(ang)*2.5, 0.5)
		coil.Parent=m
	end
	-- Tail
	for i=0,2 do
		local t=bp({Name="Tail", Size=Vector3.new(1-i*0.25,0.8,1-i*0.25), Color=VIPER, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		t.CFrame=cf(0,1.5+i*0.3,2.5+i*1); t.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Viperino Node [UNCOMMON]", Color3.fromRGB(150,255,150))
	m.Parent=workspace; return m
end

local function buildAquilinoStake(posX, posZ)
	local m = Instance.new("Model"); m.Name = "AquilinoStake"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local FEATHER=Color3.fromRGB(90,70,50); local FEATHER2=Color3.fromRGB(120,95,65); local BEAK=Color3.fromRGB(255,180,50); local BLACK=Color3.fromRGB(25,25,30)
	-- Eagle head
	local head=bp({Name="Head", Size=Vector3.new(2.5,2.5,2.8), Color=FEATHER, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,13,0); studAllFaces(head); head.Parent=m
	local beak=bp({Name="Beak", Size=Vector3.new(1,1,1.8), Color=BEAK, Material=Enum.Material.Plastic})
	beak.CFrame=cf(0,12.5,-2.2)*CFrame.Angles(math.rad(20),0,0); studAllFaces(beak); beak.Parent=m
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.55,0.55,0.55), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,13.7,-1.2); e.Parent=m
	end
	-- Body with wings
	local body=bp({Name="Body", Size=Vector3.new(3,4,2.8), Color=FEATHER, Material=Enum.Material.Plastic})
	body.CFrame=cf(0,8,0.5); studAllFaces(body); body.Parent=m
	for _,sx in ipairs({-1,1}) do
		local wing=bp({Name="Wing", Size=Vector3.new(1,3.5,3), Color=FEATHER2, Material=Enum.Material.Plastic})
		wing.CFrame=cf(sx*2.2,8.5,0.5)*CFrame.Angles(0,0,math.rad(sx*25)); studAllFaces(wing); wing.Parent=m
	end
	-- Staking platform (body is on platform)
	local platform=bp({Name="StakePlatform", Size=Vector3.new(5,2,5), Color=Color3.fromRGB(60,130,200), Material=Enum.Material.Plastic})
	platform.CFrame=cf(0,4,0.5); studAllFaces(platform); platform.Parent=m
	local pole=bp({Name="StakePole", Size=Vector3.new(0.8,4,0.8), Color=Color3.fromRGB(180,180,190), Material=Enum.Material.Plastic})
	pole.CFrame=cf(2.5,6,2); studAllFaces(pole); pole.Parent=m
	-- Flag
	local flag=bp({Name="Flag", Size=Vector3.new(2.5,1.5,0.2), Color=Color3.fromRGB(60,130,200), Material=Enum.Material.Plastic})
	flag.CFrame=cf(3.8,7.3,2); flag.CanCollide=false; flag.Parent=m
	-- Legs + talons
	for _,lx in ipairs({-1,1}) do
		local leg=bp({Name="Leg", Size=Vector3.new(0.7,2,0.7), Color=BEAK, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.5,0.5); studAllFaces(leg); leg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Aquilino Stake [RARE]", Color3.fromRGB(100,255,150))
	m.Parent=workspace; return m
end

local function buildCucumbroChain(posX, posZ)
	local m = Instance.new("Model"); m.Name = "CucumbroChain"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local CUC=Color3.fromRGB(80,165,70); local CUC2=Color3.fromRGB(60,140,55); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Cucumber head (round top)
	local head=bp({Name="Head", Size=Vector3.new(3,3.5,3), Color=CUC, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Cucumber bumps
	for i=0,4 do
		local bump=bp({Name="Bump", Size=Vector3.new(0.5,0.5,0.5), Color=CUC2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		bump.CFrame=cf(math.sin(i*1.5)*1.4, 13+math.cos(i*1.5), math.cos(i*1.5)*1.4); bump.Parent=m
	end
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.7,0.7,0.7), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.3,-1.3); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.35,0.35,0.35), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,12.3,-1.7); p.Parent=m
	end
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.2,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,11,-1.4); mouth.CanCollide=false; mouth.Parent=m
	-- Body (cucumber segment)
	local body=bp({Name="Body", Size=Vector3.new(3.2,4.5,3.2), Color=CUC, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	body.CFrame=cf(0,6,0.5); studAllFaces(body); body.Parent=m
	-- Chain links around body
	for i=0,7 do
		local ang=math.rad(i*45)
		local link=bp({Name="ChainLink", Size=Vector3.new(1.2,0.6,1.2), Color=Color3.fromRGB(180,180,190), Material=Enum.Material.Plastic})
		link.CFrame=cf(math.cos(ang)*2.4, 6+math.sin(ang)*2.4, 0.5)*CFrame.Angles(0,0,ang)
		link.Parent=m
	end
	-- Legs
	for _,lx in ipairs({-1,1}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1,2,1), Color=CUC2, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.5,0.5); studAllFaces(leg); leg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Cucumbro Chain [UNCOMMON]", Color3.fromRGB(150,255,150))
	m.Parent=workspace; return m
end

local function buildGelatinoMint(posX, posZ)
	local m = Instance.new("Model"); m.Name = "GelatinoMint"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local JELLY=Color3.fromRGB(100,220,140); local MINT=Color3.fromRGB(60,180,100); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Jelly head (wobbly dome)
	local head=bp({Name="Head", Size=Vector3.new(3.5,3,3.5), Color=JELLY, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	head.CFrame=cf(0,11.5,0); studAllFaces(head); head.Parent=m
	head.Transparency=0.15
	-- Big eyes inside jelly
	for _,ex in ipairs({-0.9,0.9}) do
		local e=bp({Name="Eye", Size=Vector3.new(1,1,1), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,11.8,-1.3); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.5,0.5,0.5), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,11.8,-1.8); p.Parent=m
	end
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.5,0.4,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,10.5,-1.5); mouth.CanCollide=false; mouth.Parent=m
	-- Mint machine body
	local machine=bp({Name="MintMachine", Size=Vector3.new(4,5,3.5), Color=Color3.fromRGB(140,142,150), Material=Enum.Material.Plastic})
	machine.CFrame=cf(0,5.5,0.5); studAllFaces(machine); machine.Parent=m
	-- Mint leaf logo
	local leaf=bp({Name="MintLeaf", Size=Vector3.new(1.5,1.5,0.3), Color=MINT, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	leaf.CFrame=cf(0,6.5,-1.4); leaf.CanCollide=false; leaf.Parent=m
	-- Output slot with mint coin
	local slot=bp({Name="Slot", Size=Vector3.new(2,0.6,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	slot.CFrame=cf(0,4,-1.3); slot.CanCollide=false; slot.Parent=m
	local coin=bp({Name="MintCoin", Size=Vector3.new(1.3,0.4,1.3), Color=MINT, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	coin.CFrame=cf(0,3.3,-2)*CFrame.Angles(math.rad(90),0,0); coin.CanCollide=false; coin.Parent=m
	-- Legs
	for _,lx in ipairs({-1.3,1.3}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.2,2.5,1.2), Color=JELLY, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Gelatino Mint [RARE]", Color3.fromRGB(100,255,170))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Characters29-33: Piccione, Gattino, Bruschetta, Volpe, Zucchino.
-- ---------------------------------------------------------------------------

local function buildPiccioneBridge(posX, posZ)
	local m = Instance.new("Model"); m.Name = "PiccioneBridge"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local FEATHER=Color3.fromRGB(130,135,150); local NECK=Color3.fromRGB(100,170,130); local BEAK=Color3.fromRGB(255,180,50); local BLACK=Color3.fromRGB(25,25,30)
	-- Pigeon head
	local head=bp({Name="Head", Size=Vector3.new(2.2,2.2,2.2), Color=FEATHER, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,-0.5); studAllFaces(head); head.Parent=m
	local beak=bp({Name="Beak", Size=Vector3.new(0.6,0.5,1.2), Color=BEAK, Material=Enum.Material.Plastic})
	beak.CFrame=cf(0,11.7,-1.9); studAllFaces(beak); beak.Parent=m
	for _,ex in ipairs({-0.7,0.7}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.45,0.45,0.45), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.5,-1.4); e.Parent=m
	end
	-- Neck (iridescent green)
	local neck=bp({Name="Neck", Size=Vector3.new(1.5,2,1.5), Color=NECK, Material=Enum.Material.Plastic})
	neck.CFrame=cf(0,10,0); studAllFaces(neck); neck.Parent=m
	-- Pigeon body
	local body=bp({Name="Body", Size=Vector3.new(3,3,3.8), Color=FEATHER, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	body.CFrame=cf(0,7,0.5); studAllFaces(body); body.Parent=m
	-- Bridge deck body (the joke - body IS a small bridge)
	local deck=bp({Name="Deck", Size=Vector3.new(4,1,5), Color=Color3.fromRGB(130,95,60), Material=Enum.Material.Plastic})
	deck.CFrame=cf(0,5.5,0.5); studAllFaces(deck); deck.Parent=m
	for _,sx in ipairs({-1,1}) do
		local rail=bp({Name="Rail", Size=Vector3.new(0.25,1,5), Color=Color3.fromRGB(90,65,40), Material=Enum.Material.Plastic})
		rail.CFrame=cf(sx*2,6.5,0.5); studAllFaces(rail); rail.Parent=m
	end
	-- Wings + feet
	for _,sx in ipairs({-1,1}) do
		local wing=bp({Name="Wing", Size=Vector3.new(0.8,2.5,3), Color=Color3.fromRGB(110,115,130), Material=Enum.Material.Plastic})
		wing.CFrame=cf(sx*1.9,7.5,0.5); studAllFaces(wing); wing.Parent=m
	end
	for _,lx in ipairs({-0.8,0.8}) do
		local leg=bp({Name="Leg", Size=Vector3.new(0.5,1.5,0.5), Color=BEAK, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,2.25,0.5); studAllFaces(leg); leg.Parent=m
		local foot=bp({Name="Foot", Size=Vector3.new(0.9,0.4,1.3), Color=BEAK, Material=Enum.Material.Plastic})
		foot.CFrame=cf(lx,1.5,0.2); foot.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Piccione Bridge [RARE]", Color3.fromRGB(100,255,150))
	m.Parent=workspace; return m
end

local function buildGattinoSwap(posX, posZ)
	local m = Instance.new("Model"); m.Name = "GattinoSwap"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local CAT=Color3.fromRGB(250,200,120); local CAT2=Color3.fromRGB(220,170,90); local PINK=Color3.fromRGB(245,170,175); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Kitten head
	local head=bp({Name="Head", Size=Vector3.new(3,2.7,3), Color=CAT, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	for _,sx in ipairs({-1,1}) do
		local ear=bp({Name="Ear", Size=Vector3.new(1,1.2,0.5), Color=CAT, Material=Enum.Material.Plastic})
		ear.CFrame=cf(sx*1.1,13.7,0)*CFrame.Angles(0,0,math.rad(sx*-25)); studAllFaces(ear); ear.Parent=m
		local earIn=bp({Name="EarIn", Size=Vector3.new(0.5,0.7,0.3), Color=PINK, Material=Enum.Material.Plastic})
		earIn.CFrame=cf(sx*1.1,13.7,-0.15); earIn.CanCollide=false; earIn.Parent=m
	end
	local muzzle=bp({Name="Muzzle", Size=Vector3.new(1.6,1,1), Color=WHITE, Material=Enum.Material.Plastic})
	muzzle.CFrame=cf(0,11.3,-1.6); studAllFaces(muzzle); muzzle.Parent=m
	local nose=bp({Name="Nose", Size=Vector3.new(0.4,0.3,0.3), Color=PINK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	nose.CFrame=cf(0,11.7,-2.2); nose.Parent=m
	for _,ex in ipairs({-0.7,0.7}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=Color3.fromRGB(80,220,100), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.4,-1.4); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,12.4,-1.7); p.Parent=m
	end
	-- Body
	local body=bp({Name="Body", Size=Vector3.new(3,3.5,2.8), Color=CAT, Material=Enum.Material.Plastic})
	body.CFrame=cf(0,7,0.5); studAllFaces(body); body.Parent=m
	local belly=bp({Name="Belly", Size=Vector3.new(2,2.5,0.4), Color=WHITE, Material=Enum.Material.Plastic})
	belly.CFrame=cf(0,7,-1); belly.CanCollide=false; belly.Parent=m
	-- SWAP arrows on chest (two arrows crossing)
	local arrow1=bp({Name="SwapArrow1", Size=Vector3.new(2,0.5,0.3), Color=Color3.fromRGB(60,130,220), Material=Enum.Material.Plastic})
	arrow1.CFrame=cf(0,7.5,-1.3)*CFrame.Angles(0,0,math.rad(30)); arrow1.CanCollide=false; arrow1.Parent=m
	local arrow2=bp({Name="SwapArrow2", Size=Vector3.new(2,0.5,0.3), Color=Color3.fromRGB(60,130,220), Material=Enum.Material.Plastic})
	arrow2.CFrame=cf(0,7.5,-1.3)*CFrame.Angles(0,0,math.rad(-30)); arrow2.CanCollide=false; arrow2.Parent=m
	-- Legs + tail
	for _,lx in ipairs({-1,1}) do
		for _,lz in ipairs({-0.3,1.3}) do
			local leg=bp({Name="Leg", Size=Vector3.new(0.9,2.5,0.9), Color=CAT2, Material=Enum.Material.Plastic})
			leg.CFrame=cf(lx,1.75,lz); studAllFaces(leg); leg.Parent=m
		end
	end
	for i=0,3 do
		local tailSeg=bp({Name="Tail", Size=Vector3.new(0.7,0.7,0.7), Color=CAT2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		tailSeg.CFrame=cf(1.5+i*0.3, 4+i*0.8, 2+i*0.4); tailSeg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Gattino Swap [EPIC]", Color3.fromRGB(255,220,100))
	m.Parent=workspace; return m
end

local function buildBruschettaBlock(posX, posZ)
	local m = Instance.new("Model"); m.Name = "BruschettaBlock"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local BREAD=Color3.fromRGB(220,185,120); local CRUST=Color3.fromRGB(180,140,80); local TOMATO=Color3.fromRGB(220,70,60); local BASIL=Color3.fromRGB(60,160,70); local BLACK=Color3.fromRGB(25,25,30)
	-- Bread slice head (square, crusty)
	local head=bp({Name="Head", Size=Vector3.new(3.5,3.5,1.5), Color=BREAD, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,11.5,0); studAllFaces(head); head.Parent=m
	-- Crust border
	local crust=bp({Name="Crust", Size=Vector3.new(3.8,3.8,1.2), Color=CRUST, Material=Enum.Material.Plastic})
	crust.CFrame=cf(0,11.5,0.3); studAllFaces(crust); crust.Parent=m
	-- Topping (tomato + basil on face)
	local tomato=bp({Name="Tomato", Size=Vector3.new(2.5,2.5,0.4), Color=TOMATO, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	tomato.CFrame=cf(0,11.5,-0.9)*CFrame.Angles(math.rad(90),0,0); tomato.CanCollide=false; tomato.Parent=m
	for i=0,2 do
		local basilLeaf=bp({Name="Basil", Size=Vector3.new(0.8,0.5,0.2), Color=BASIL, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		basilLeaf.CFrame=cf(math.sin(i*2)*0.8, 11.5+math.cos(i*2)*0.8, -1.15); basilLeaf.CanCollide=false; basilLeaf.Parent=m
	end
	-- Eyes (on tomato)
	for _,ex in ipairs({-0.6,0.6}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.5,0.5,0.4), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,11.9,-1.3); e.CanCollide=false; e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.25,0.25,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,11.9,-1.5); p.CanCollide=false; p.Parent=m
	end
	-- Blockchain block body (the joke - body is a ledger block)
	local block=bp({Name="BlockBody", Size=Vector3.new(4,4.5,3), Color=Color3.fromRGB(90,90,160), Material=Enum.Material.Plastic})
	block.CFrame=cf(0,6,0.5); studAllFaces(block); block.Parent=m
	-- Hash lines on block
	for i=0,2 do
		local line=bp({Name="HashLine", Size=Vector3.new(3,0.4,0.2), Color=Color3.fromRGB(140,140,200), Material=Enum.Material.Plastic})
		line.CFrame=cf(0,7-i*1,-1.1); line.CanCollide=false; line.Parent=m
	end
	-- Legs + arms
	for _,lx in ipairs({-1.3,1.3}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.2,2.5,1.2), Color=CRUST, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(1,3,1), Color=CRUST, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*2.7,7,0.5)*CFrame.Angles(0,0,math.rad(sx*20)); studAllFaces(arm); arm.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Bruschetta Block [UNCOMMON]", Color3.fromRGB(150,255,150))
	m.Parent=workspace; return m
end

local function buildVolpeOracle(posX, posZ)
	local m = Instance.new("Model"); m.Name = "VolpeOracle"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local FOX=Color3.fromRGB(230,130,50); local FOX2=Color3.fromRGB(200,105,35); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Fox head (pointy snout)
	local head=bp({Name="Head", Size=Vector3.new(3,2.8,3.2), Color=FOX, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	local snout=bp({Name="Snout", Size=Vector3.new(1.8,1.2,2), Color=WHITE, Material=Enum.Material.Plastic})
	snout.CFrame=cf(0,11.3,-2.3); studAllFaces(snout); snout.Parent=m
	local nose=bp({Name="Nose", Size=Vector3.new(0.5,0.4,0.4), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	nose.CFrame=cf(0,11.7,-3.4); nose.Parent=m
	-- Pointy ears
	for _,sx in ipairs({-1,1}) do
		local ear=bp({Name="Ear", Size=Vector3.new(1,1.5,0.5), Color=FOX, Material=Enum.Material.Plastic})
		ear.CFrame=cf(sx*1.2,14,0)*CFrame.Angles(0,0,math.rad(sx*-15)); studAllFaces(ear); ear.Parent=m
		local earTip=bp({Name="EarTip", Size=Vector3.new(0.5,0.5,0.3), Color=BLACK, Material=Enum.Material.Plastic})
		earTip.CFrame=cf(sx*1.4,14.9,0); earTip.CanCollide=false; earTip.Parent=m
	end
	-- Eyes (clever fox look)
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=Color3.fromRGB(120,220,90), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.6,-1.3); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,12.6,-1.6); p.Parent=m
	end
	-- Body
	local body=bp({Name="Body", Size=Vector3.new(3.2,4,3), Color=FOX, Material=Enum.Material.Plastic})
	body.CFrame=cf(0,6.5,0.5); studAllFaces(body); body.Parent=m
	local chest=bp({Name="Chest", Size=Vector3.new(2.2,2.5,0.4), Color=WHITE, Material=Enum.Material.Plastic})
	chest.CFrame=cf(0,6.5,-1.2); chest.CanCollide=false; chest.Parent=m
	-- Oracle screen on body
	local screen=bp({Name="OracleScreen", Size=Vector3.new(2.5,2,0.3), Color=Color3.fromRGB(40,30,80), Material=Enum.Material.Plastic})
	screen.CFrame=cf(0,6.5,2.1); screen.CanCollide=false; screen.Parent=m
	local eye=bp({Name="OracleEye", Size=Vector3.new(1.2,1.2,0.2), Color=Color3.fromRGB(150,100,255), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	eye.CFrame=cf(0,6.5,2.3); eye.CanCollide=false; eye.Parent=m
	-- Legs + bushy tail
	for _,lx in ipairs({-1.1,1.1}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.1,2.5,1.1), Color=FOX2, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	for i=0,3 do
		local tailSeg=bp({Name="Tail", Size=Vector3.new(1.5-i*0.2,1.5-i*0.2,1.5-i*0.2), Color=(i==3) and WHITE or FOX, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		tailSeg.CFrame=cf(1.5+i*0.35, 5-i*0.5, 2.5+i*0.5); tailSeg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Volpe Oracle [EPIC]", Color3.fromRGB(255,180,100))
	m.Parent=workspace; return m
end

local function buildZucchinoVault(posX, posZ)
	local m = Instance.new("Model"); m.Name = "ZucchinoVault"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local ZUC=Color3.fromRGB(70,150,60); local ZUC2=Color3.fromRGB(50,125,45); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Zucchini head (elongated top)
	local head=bp({Name="Head", Size=Vector3.new(2.8,3.5,2.8), Color=ZUC, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12.5,0); studAllFaces(head); head.Parent=m
	-- Stem on top
	local stem=bp({Name="Stem", Size=Vector3.new(0.7,1,0.7), Color=ZUC2, Material=Enum.Material.Plastic})
	stem.CFrame=cf(0,14.7,0); studAllFaces(stem); stem.Parent=m
	-- Face
	for _,ex in ipairs({-0.7,0.7}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,13,-1.3); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,13,-1.7); p.Parent=m
	end
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.2,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,11.7,-1.3); mouth.CanCollide=false; mouth.Parent=m
	-- Vault body (zucchini lower = big green cylinder)
	local vault=bp({Name="VaultBody", Size=Vector3.new(4.5,5.5,4.5), Color=ZUC, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	vault.CFrame=cf(0,5.5,0.5)*CFrame.Angles(math.rad(90),0,0); studAllFaces(vault); vault.Parent=m
	-- Vault door
	local door=bp({Name="Door", Size=Vector3.new(3,3,0.5), Color=Color3.fromRGB(100,100,110), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	door.CFrame=cf(0,5.5,-2)*CFrame.Angles(math.rad(90),0,0); studAllFaces(door); door.Parent=m
	local dial=bp({Name="Dial", Size=Vector3.new(1.3,1.3,0.4), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	dial.CFrame=cf(0,5.5,-2.3)*CFrame.Angles(math.rad(90),0,0); dial.Parent=m
	-- Legs + arms
	for _,lx in ipairs({-1.5,1.5}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.3,2.5,1.3), Color=ZUC2, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(1,3,1), Color=ZUC, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*3,7,0.5)*CFrame.Angles(0,0,math.rad(sx*25)); studAllFaces(arm); arm.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Zucchino Vault [RARE]", Color3.fromRGB(100,200,255))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Characters34-38: Moscato, Cannoli, Gnocchi, Focaccia, Pesto.
-- ---------------------------------------------------------------------------

local function buildMoscatoWhale(posX, posZ)
	local m = Instance.new("Model"); m.Name = "MoscatoWhale"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local WINE=Color3.fromRGB(150,60,100); local WINE2=Color3.fromRGB(120,45,80); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Whale head (wine-colored)
	local head=bp({Name="Head", Size=Vector3.new(4,3.2,3.8), Color=WINE, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,11.5,-0.5); studAllFaces(head); head.Parent=m
	local snout=bp({Name="Snout", Size=Vector3.new(3.6,1.8,1.8), Color=WINE, Material=Enum.Material.Plastic})
	snout.CFrame=cf(0,10.5,-2.8); studAllFaces(snout); snout.Parent=m
	local mouth=bp({Name="Mouth", Size=Vector3.new(3.2,0.25,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,10,-3.7); mouth.CanCollide=false; mouth.Parent=m
	for _,ex in ipairs({-1.4,1.4}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.9,0.9,0.9), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.3,-1.8); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.45,0.45,0.45), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,12.3,-2.2); p.Parent=m
	end
	-- Wine bottle body (the joke)
	local bottle=bp({Name="Bottle", Size=Vector3.new(3.5,6,3.5), Color=WINE2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	bottle.CFrame=cf(0,5,0.5); studAllFaces(bottle); bottle.Parent=m
	local neck=bp({Name="BottleNeck", Size=Vector3.new(1.5,2,1.5), Color=WINE2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	neck.CFrame=cf(0,9,0.5); studAllFaces(neck); neck.Parent=m
	-- Label on bottle
	local label=bp({Name="WineLabel", Size=Vector3.new(2.5,2.5,0.3), Color=WHITE, Material=Enum.Material.Plastic})
	label.CFrame=cf(0,5,-1.6); label.CanCollide=false; label.Parent=m
	local grape=bp({Name="Grape", Size=Vector3.new(1,1,0.2), Color=WINE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	grape.CFrame=cf(0,5,-1.8); grape.CanCollide=false; grape.Parent=m
	-- Fins + tail
	for _,sx in ipairs({-1,1}) do
		local fin=bp({Name="Fin", Size=Vector3.new(2.2,1,1.5), Color=WINE, Material=Enum.Material.Plastic})
		fin.CFrame=cf(sx*3,6.5,0.5)*CFrame.Angles(0,0,math.rad(sx*30)); studAllFaces(fin); fin.Parent=m
	end
	for i=0,1 do
		local fluke=bp({Name="Fluke", Size=Vector3.new(2-i*0.5,0.6,1.5), Color=WINE, Material=Enum.Material.Plastic})
		fluke.CFrame=cf(0,2,3+i*1.2)*CFrame.Angles(math.rad(-20),0,0); studAllFaces(fluke); fluke.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Moscato Whale [MYTHIC]", Color3.fromRGB(255,120,180))
	m.Parent=workspace; return m
end

local function buildCannoliBlaster(posX, posZ)
	local m = Instance.new("Model"); m.Name = "CannoliBlaster"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local SHELL=Color3.fromRGB(230,195,130); local CREAM=Color3.fromRGB(250,245,235); local CHOC=Color3.fromRGB(100,60,40); local BLACK=Color3.fromRGB(25,25,30)
	-- Cannoli head (cylinder tube)
	local head=bp({Name="Head", Size=Vector3.new(3,3,3.5), Color=SHELL, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	head.CFrame=cf(0,12,0)*CFrame.Angles(0,0,math.rad(90)); studAllFaces(head); head.Parent=m
	-- Cream poking out both ends
	for _,sx in ipairs({-1,1}) do
		local cream=bp({Name="Cream", Size=Vector3.new(2,2,1), Color=CREAM, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		cream.CFrame=cf(sx*2,12,0); cream.Parent=m
		local chip=bp({Name="Chip", Size=Vector3.new(0.4,0.4,0.4), Color=CHOC, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		chip.CFrame=cf(sx*2.3,12.5,0.3); chip.CanCollide=false; chip.Parent=m
	end
	-- Eyes on cream front
	for _,ex in ipairs({-0.6,0.6}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.55,0.55,0.55), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.5,-1.7); e.Parent=m
	end
	-- Body (cream filling cylinder)
	local body=bp({Name="Body", Size=Vector3.new(3.5,4.5,3.5), Color=CREAM, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	body.CFrame=cf(0,6,0.5)*CFrame.Angles(0,0,math.rad(90)); studAllFaces(body); body.Parent=m
	-- Water blaster prop (the joke)
	local blaster=bp({Name="Blaster", Size=Vector3.new(1,1.5,5), Color=Color3.fromRGB(60,160,230), Material=Enum.Material.Plastic})
	blaster.CFrame=cf(3,7,-1)*CFrame.Angles(math.rad(-15),0,0); studAllFaces(blaster); blaster.Parent=m
	local nozzle=bp({Name="Nozzle", Size=Vector3.new(1.2,1.2,1), Color=Color3.fromRGB(40,120,190), Material=Enum.Material.Plastic})
	nozzle.CFrame=cf(3,7.6,-4); studAllFaces(nozzle); nozzle.Parent=m
	-- Water drop coming out
	local drop=bp({Name="WaterDrop", Size=Vector3.new(0.8,0.8,0.8), Color=Color3.fromRGB(100,190,255), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	drop.CFrame=cf(3,7.6,-5); drop.CanCollide=false; drop.Parent=m
	-- Legs
	for _,lx in ipairs({-1.2,1.2}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.2,2.5,1.2), Color=SHELL, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	-- Left arm
	local armL=bp({Name="ArmL", Size=Vector3.new(1,3,1), Color=CREAM, Material=Enum.Material.Plastic})
	armL.CFrame=cf(-2.5,7,0.5); studAllFaces(armL); armL.Parent=m
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Cannoli Blaster [LEGENDARY]", Color3.fromRGB(255,230,130))
	m.Parent=workspace; return m
end

local function buildGnocchiGolem(posX, posZ)
	local m = Instance.new("Model"); m.Name = "GnocchiGolem"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local DOUGH=Color3.fromRGB(240,225,180); local DOUGH2=Color3.fromRGB(215,195,145); local SAGE=Color3.fromRGB(120,140,80); local BLACK=Color3.fromRGB(25,25,30)
	-- Gnocchi head (round dough ball with fork marks)
	local head=bp({Name="Head", Size=Vector3.new(3.5,3,3.5), Color=DOUGH, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Fork ridge marks
	for i=0,2 do
		local ridge=bp({Name="Ridge", Size=Vector3.new(2.5,0.3,0.3), Color=DOUGH2, Material=Enum.Material.Plastic})
		ridge.CFrame=cf(0,13-i*0.7,-1.4)*CFrame.Angles(math.rad(i*10),0,0); ridge.CanCollide=false; ridge.Parent=m
	end
	-- Eyes (deep-set in dough)
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.3,-1.5); e.Parent=m
	end
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.5,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,11,-1.5); mouth.CanCollide=false; mouth.Parent=m
	-- Golem body (stacked dough blocks, stone-like)
	local body=bp({Name="Body", Size=Vector3.new(4.5,4.5,4), Color=DOUGH, Material=Enum.Material.Plastic})
	body.CFrame=cf(0,6,0.5); studAllFaces(body); body.Parent=m
	-- Sage butter sauce dripping (the topping = decoration)
	for i=0,3 do
		local butter=bp({Name="Butter", Size=Vector3.new(1,0.5,1), Color=SAGE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		butter.CFrame=cf(math.sin(i*1.8)*1.8, 8.3, math.cos(i*1.8)*1.5); butter.CanCollide=false; butter.Parent=m
	end
	-- Big golem arms (dough)
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(1.8,4,1.8), Color=DOUGH, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*3.3,6,0.5)*CFrame.Angles(0,0,math.rad(sx*15)); studAllFaces(arm); arm.Parent=m
		local fist=bp({Name="Fist", Size=Vector3.new(2.2,2,2.2), Color=DOUGH2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		fist.CFrame=cf(sx*4,3.5,0.5); studAllFaces(fist); fist.Parent=m
	end
	-- Golem legs (stubby dough)
	for _,lx in ipairs({-1.5,1.5}) do
		local leg=bp({Name="Leg", Size=Vector3.new(2,2.5,2), Color=DOUGH, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Gnocchi Golem [SECRET]", Color3.fromRGB(255,50,50))
	m.Parent=workspace; return m
end

local function buildFocacciaNode(posX, posZ)
	local m = Instance.new("Model"); m.Name = "FocacciaNode"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local BREAD=Color3.fromRGB(235,200,140); local CRUST=Color3.fromRGB(195,155,95); local ROSE=Color3.fromRGB(220,90,110); local OLIVE=Color3.fromRGB(70,110,50); local BLACK=Color3.fromRGB(25,25,30)
	-- Focaccia head (flat bread square)
	local head=bp({Name="Head", Size=Vector3.new(4,1.8,4), Color=BREAD, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,11,0); studAllFaces(head); head.Parent=m
	-- Dimples + toppings on top
	for i=0,5 do
		local rosemary=bp({Name="Rosemary", Size=Vector3.new(0.8,0.3,0.8), Color=ROSE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		rosemary.CFrame=cf(math.sin(i*1.2)*1.5, 12, math.cos(i*1.2)*1.5); rosemary.CanCollide=false; rosemary.Parent=m
	end
	for i=0,2 do
		local olive=bp({Name="Olive", Size=Vector3.new(0.7,0.4,0.7), Color=OLIVE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		olive.CFrame=cf(-1+i, 12, 1.5); olive.CanCollide=false; olive.Parent=m
	end
	-- Eyes on front face
	for _,ex in ipairs({-1,1}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.7,0.7,0.4), Color=Color3.fromRGB(245,245,245), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,11,-2); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.35,0.35,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,11,-2.2); p.Parent=m
	end
	-- Node server body (below bread)
	local server=bp({Name="NodeServer", Size=Vector3.new(3.5,5,3), Color=Color3.fromRGB(55,55,62), Material=Enum.Material.Plastic})
	server.CFrame=cf(0,6,0.5); studAllFaces(server); server.Parent=m
	for i=0,3 do
		local led=bp({Name="LED", Size=Vector3.new(0.4,0.3,0.2), Color=(i%2==0) and Color3.fromRGB(50,255,100) or Color3.fromRGB(50,80,255), Material=Enum.Material.Plastic})
		led.CFrame=cf(-0.8+i*0.5, 4.5, -1.1); led.CanCollide=false; led.Parent=m
	end
	-- Legs + arms
	for _,lx in ipairs({-1.2,1.2}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.3,2.5,1.3), Color=CRUST, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(1,3,1), Color=BREAD, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*2.7,7,0.5)*CFrame.Angles(0,0,math.rad(sx*20)); studAllFaces(arm); arm.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Focaccia Node [UNCOMMON]", Color3.fromRGB(150,255,150))
	m.Parent=workspace; return m
end

local function buildPestoPirate(posX, posZ)
	local m = Instance.new("Model"); m.Name = "PestoPirate"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local PESTO=Color3.fromRGB(60,140,65); local PESTO2=Color3.fromRGB(45,115,50); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Basil head (leafy green)
	local head=bp({Name="Head", Size=Vector3.new(3.2,3,3.2), Color=PESTO, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Leafy crown (basil leaves sticking up)
	for i=0,4 do
		local leaf=bp({Name="Leaf", Size=Vector3.new(1.5,0.3,2), Color=PESTO2, Material=Enum.Material.Plastic})
		leaf.CFrame=cf(math.sin(i*1.3)*1.2, 14, math.cos(i*1.3)*1.2)*CFrame.Angles(math.rad(20),i*1.3,0)
		studAllFaces(leaf); leaf.Parent=m
	end
	-- Pirate hat
	local hatBrim=bp({Name="HatBrim", Size=Vector3.new(4,0.5,4), Color=BLACK, Material=Enum.Material.Plastic})
	hatBrim.CFrame=cf(0,14,0); studAllFaces(hatBrim); hatBrim.Parent=m
	local hatTop=bp({Name="HatTop", Size=Vector3.new(2.5,2,2.5), Color=BLACK, Material=Enum.Material.Plastic})
	hatTop.CFrame=cf(0,15.3,0); studAllFaces(hatTop); hatTop.Parent=m
	local skull=bp({Name="HatSkull", Size=Vector3.new(1,1,0.3), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	skull.CFrame=cf(0,15.3,-1.4); skull.CanCollide=false; skull.Parent=m
	-- Face
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.3,-1.5); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,12.3,-1.8); p.Parent=m
	end
	-- Pesto jar body
	local jar=bp({Name="Jar", Size=Vector3.new(3.5,4.5,3.5), Color=PESTO, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	jar.CFrame=cf(0,5.5,0.5); studAllFaces(jar); jar.Parent=m
	local lid=bp({Name="Lid", Size=Vector3.new(3.7,0.8,3.7), Color=Color3.fromRGB(180,180,190), Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	lid.CFrame=cf(0,8.1,0.5); studAllFaces(lid); lid.Parent=m
	-- Label
	local label=bp({Name="Label", Size=Vector3.new(2.5,2,0.3), Color=WHITE, Material=Enum.Material.Plastic})
	label.CFrame=cf(0,5.5,-1.7); label.CanCollide=false; label.Parent=m
	-- Legs + cutlass arm
	for _,lx in ipairs({-1.2,1.2}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.2,2.5,1.2), Color=PESTO2, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	local armR=bp({Name="ArmR", Size=Vector3.new(1,3,1), Color=PESTO, Material=Enum.Material.Plastic})
	armR.CFrame=cf(2.7,7.5,0)*CFrame.Angles(0,0,math.rad(-40)); studAllFaces(armR); armR.Parent=m
	-- Cutlass
	local blade=bp({Name="Cutlass", Size=Vector3.new(0.3,4,0.8), Color=Color3.fromRGB(200,200,210), Material=Enum.Material.Plastic})
	blade.CFrame=cf(4.2,10.5,0)*CFrame.Angles(0,0,math.rad(-30)); studAllFaces(blade); blade.Parent=m
	local hilt=bp({Name="Hilt", Size=Vector3.new(0.5,1,1.5), Color=Color3.fromRGB(160,120,60), Material=Enum.Material.Plastic})
	hilt.CFrame=cf(3.4,8.5,0); studAllFaces(hilt); hilt.Parent=m
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Pesto Pirate [EPIC]", Color3.fromRGB(130,255,140))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Characters39-43: Tiramisu, Arancino, Limone, Prosciutto, Polenta.
-- ---------------------------------------------------------------------------

local function buildTiramisuTower(posX, posZ)
	local m = Instance.new("Model"); m.Name = "TiramisuTower"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local CREAM=Color3.fromRGB(245,235,210); local COCO=Color3.fromRGB(110,75,50); local SPONGE=Color3.fromRGB(200,170,120); local BLACK=Color3.fromRGB(25,25,30)
	-- Tiramisu layers head/body (stacked)
	local layer1=bp({Name="Layer1", Size=Vector3.new(4,1.5,4), Color=SPONGE, Material=Enum.Material.Plastic})
	layer1.CFrame=cf(0,4,0.5); studAllFaces(layer1); layer1.Parent=m
	local layer2=bp({Name="Layer2", Size=Vector3.new(3.7,1.5,3.7), Color=CREAM, Material=Enum.Material.Plastic})
	layer2.CFrame=cf(0,5.5,0.5); studAllFaces(layer2); layer2.Parent=m
	local layer3=bp({Name="Layer3", Size=Vector3.new(4,1.5,4), Color=SPONGE, Material=Enum.Material.Plastic})
	layer3.CFrame=cf(0,7,0.5); studAllFaces(layer3); layer3.Parent=m
	local layer4=bp({Name="Layer4", Size=Vector3.new(3.7,1.5,3.7), Color=CREAM, Material=Enum.Material.Plastic})
	layer4.CFrame=cf(0,8.5,0.5); studAllFaces(layer4); layer4.Parent=m
	-- Cocoa dusting on top
	local cocoa=bp({Name="Cocoa", Size=Vector3.new(3.8,0.4,3.8), Color=COCO, Material=Enum.Material.Plastic})
	cocoa.CFrame=cf(0,9.5,0.5); studAllFaces(cocoa); cocoa.Parent=m
	-- Head (top cake layer with face)
	local head=bp({Name="Head", Size=Vector3.new(3.2,2.5,3.2), Color=CREAM, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,11.5,0); studAllFaces(head); head.Parent=m
	local cocoaTop=bp({Name="CocoaTop", Size=Vector3.new(3.3,0.5,3.3), Color=COCO, Material=Enum.Material.Plastic})
	cocoaTop.CFrame=cf(0,13,0); studAllFaces(cocoaTop); cocoaTop.Parent=m
	-- Face
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,11.7,-1.5); e.Parent=m
	end
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.2,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,10.8,-1.5); mouth.CanCollide=false; mouth.Parent=m
	-- Ladyfinger legs
	for _,lx in ipairs({-1.3,1.3}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.3,2.5,1.3), Color=SPONGE, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Tiramisu Tower [EPIC]", Color3.fromRGB(170,100,255))
	m.Parent=workspace; return m
end

local function buildArancinoBomb(posX, posZ)
	local m = Instance.new("Model"); m.Name = "ArancinoBomb"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local RICE=Color3.fromRGB(240,215,150); local CRUMB=Color3.fromRGB(210,175,105); local TOMATO=Color3.fromRGB(220,75,60); local FUSE=Color3.fromRGB(90,90,95); local FLAME=Color3.fromRGB(255,140,30); local BLACK=Color3.fromRGB(25,25,30)
	-- Arancino head (round rice ball)
	local head=bp({Name="Head", Size=Vector3.new(3.5,3.5,3.5), Color=RICE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Crumbs on top
	for i=0,5 do
		local crumb=bp({Name="Crumb", Size=Vector3.new(0.5,0.5,0.5), Color=CRUMB, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		crumb.CFrame=cf(math.sin(i)*1.3, 13.6, math.cos(i)*1.3); crumb.CanCollide=false; crumb.Parent=m
	end
	-- Face (peeking tomato sauce)
	local sauce=bp({Name="Sauce", Size=Vector3.new(2.2,1.5,0.3), Color=TOMATO, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	sauce.CFrame=cf(0,11.5,-1.6); sauce.CanCollide=false; sauce.Parent=m
	for _,ex in ipairs({-0.6,0.6}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.55,0.55,0.4), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,11.8,-1.8); e.CanCollide=false; e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,11.8,-2); p.CanCollide=false; p.Parent=m
	end
	-- Fuse sticking out of top (the bomb joke)
	local fuse=bp({Name="Fuse", Size=Vector3.new(0.4,2,0.4), Color=FUSE, Material=Enum.Material.Plastic})
	fuse.CFrame=cf(0,15,0)*CFrame.Angles(0,0,math.rad(15)); studAllFaces(fuse); fuse.Parent=m
	local flame=bp({Name="Flame", Size=Vector3.new(1,1.2,1), Color=FLAME, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	flame.CFrame=cf(0.5,16.3,0); flame.CanCollide=false; flame.Parent=m
	local flame2=bp({Name="Flame2", Size=Vector3.new(0.6,0.7,0.6), Color=Color3.fromRGB(255,230,90), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	flame2.CFrame=cf(0.6,16.9,0); flame2.CanCollide=false; flame2.Parent=m
	-- Body (bigger rice ball)
	local body=bp({Name="Body", Size=Vector3.new(4.5,5,4.5), Color=RICE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	body.CFrame=cf(0,6,0.5); studAllFaces(body); body.Parent=m
	-- Legs + arms
	for _,lx in ipairs({-1.5,1.5}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.5,2.5,1.5), Color=CRUMB, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	for _,sx in ipairs({-1,1}) do
		local arm=bp({Name="Arm", Size=Vector3.new(1.2,3,1.2), Color=RICE, Material=Enum.Material.Plastic})
		arm.CFrame=cf(sx*3.2,7,0.5)*CFrame.Angles(0,0,math.rad(sx*25)); studAllFaces(arm); arm.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Arancino Bomb [LEGENDARY]", Color3.fromRGB(255,170,90))
	m.Parent=workspace; return m
end

local function buildLimoneFrost(posX, posZ)
	local m = Instance.new("Model"); m.Name = "LimoneFrost"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local LEMON=Color3.fromRGB(255,230,70); local LEMON2=Color3.fromRGB(230,200,50); local ICE=Color3.fromRGB(180,230,255); local WHITE=Color3.fromRGB(245,245,245); local BLACK=Color3.fromRGB(25,25,30)
	-- Lemon head (oval, pointy ends)
	local head=bp({Name="Head", Size=Vector3.new(3.2,3.5,3.2), Color=LEMON, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Lemon tip on top
	local tip=bp({Name="LemonTip", Size=Vector3.new(0.6,0.8,0.6), Color=LEMON2, Material=Enum.Material.Plastic})
	tip.CFrame=cf(0,14,0); studAllFaces(tip); tip.Parent=m
	-- Frost cap (ice on top of lemon)
	local frost=bp({Name="Frost", Size=Vector3.new(3.4,1,3.4), Color=ICE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	frost.CFrame=cf(0,13.7,0); frost.Parent=m
	-- Face
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,12.2,-1.4); e.Parent=m
	end
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.3,0.4,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,11,-1.4); mouth.CanCollide=false; mouth.Parent=m
	-- Frosty body (lemonade glass)
	local glass=bp({Name="Glass", Size=Vector3.new(3.8,5,3.8), Color=ICE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	glass.CFrame=cf(0,5.5,0.5); glass.Transparency=0.3; studAllFaces(glass); glass.Parent=m
	-- Lemonade liquid inside
	local liquid=bp({Name="Liquid", Size=Vector3.new(3.4,3.5,3.4), Color=LEMON, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	liquid.CFrame=cf(0,4.8,0.5); liquid.Parent=m
	-- Straw
	local straw=bp({Name="Straw", Size=Vector3.new(0.5,4,0.5), Color=Color3.fromRGB(255,100,120), Material=Enum.Material.Plastic})
	straw.CFrame=cf(1.3,8.5,0.5)*CFrame.Angles(0,0,math.rad(15)); studAllFaces(straw); straw.Parent=m
	-- Ice cubes floating
	for i=0,2 do
		local cube=bp({Name="IceCube", Size=Vector3.new(0.8,0.8,0.8), Color=WHITE, Material=Enum.Material.Plastic})
		cube.Transparency=0.4
		cube.CFrame=cf(math.sin(i*2)*1, 6.5+i*0.5, math.cos(i*2)*1+0.5); cube.CanCollide=false; cube.Parent=m
	end
	-- Legs
	for _,lx in ipairs({-1.3,1.3}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.2,2.5,1.2), Color=LEMON2, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Limone Frost [RARE]", Color3.fromRGB(100,200,255))
	m.Parent=workspace; return m
end

local function buildProsciuttoSmoke(posX, posZ)
	local m = Instance.new("Model"); m.Name = "ProsciuttoSmoke"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local HAM=Color3.fromRGB(230,140,140); local FAT=Color3.fromRGB(250,225,215); local RIND=Color3.fromRGB(190,150,120); local BLACK=Color3.fromRGB(25,25,30)
	-- Ham slice head (flat, draped)
	local head=bp({Name="Head", Size=Vector3.new(3.5,2.5,3.5), Color=HAM, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Fat marbling on head
	for i=0,2 do
		local marble=bp({Name="Marble", Size=Vector3.new(2,0.3,0.3), Color=FAT, Material=Enum.Material.Plastic})
		marble.CFrame=cf(math.sin(i*2)*0.8, 12.5+i*0.4, math.cos(i*2)*0.8); marble.CanCollide=false; marble.Parent=m
	end
	-- Face
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,11.8,-1.5); e.Parent=m
		local p=bp({Name="Pupil", Size=Vector3.new(0.3,0.3,0.3), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		p.CFrame=cf(ex,11.8,-1.8); p.Parent=m
	end
	-- Smokehouse body (brick oven)
	local oven=bp({Name="Smokehouse", Size=Vector3.new(4.5,5.5,4), Color=Color3.fromRGB(150,90,70), Material=Enum.Material.Plastic})
	oven.CFrame=cf(0,5.5,0.5); studAllFaces(oven); oven.Parent=m
	-- Oven door (arched dark)
	local door=bp({Name="OvenDoor", Size=Vector3.new(2.5,3,0.4), Color=BLACK, Material=Enum.Material.Plastic})
	door.CFrame=cf(0,5,-1.6); door.CanCollide=false; door.Parent=m
	-- Smoke coming out chimney
	local chimney=bp({Name="Chimney", Size=Vector3.new(1.5,3,1.5), Color=Color3.fromRGB(130,75,60), Material=Enum.Material.Plastic})
	chimney.CFrame=cf(1.5,9.5,1.5); studAllFaces(chimney); chimney.Parent=m
	for i=0,2 do
		local smoke=bp({Name="Smoke", Size=Vector3.new(1.5+i*0.5,1.5+i*0.5,1.5+i*0.5), Color=Color3.fromRGB(200,200,210), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		smoke.Transparency=0.5+i*0.15
		smoke.CFrame=cf(1.5, 11.5+i*1.3, 1.5); smoke.CanCollide=false; smoke.Parent=m
	end
	-- Hanging ham legs (side decoration)
	for _,sx in ipairs({-1,1}) do
		local hamLeg=bp({Name="HamLeg", Size=Vector3.new(1.5,3,1.5), Color=HAM, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
		hamLeg.CFrame=cf(sx*3.2,8,0.5)*CFrame.Angles(math.rad(20),0,math.rad(sx*20)); studAllFaces(hamLeg); hamLeg.Parent=m
	end
	-- Legs
	for _,lx in ipairs({-1.5,1.5}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.5,2.5,1.5), Color=RIND, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,1.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Prosciutto Smoke [RARE]", Color3.fromRGB(255,160,160))
	m.Parent=workspace; return m
end

local function buildPolentaPillar(posX, posZ)
	local m = Instance.new("Model"); m.Name = "PolentaPillar"
	local function bp(p) local x=part(p); x.Anchored=true; x.CanCollide=true; return x end
	local function cf(x,y,z,ry) return CFrame.new(posX+x,2+y,posZ+z)*CFrame.Angles(0,math.rad(ry or 0),0) end
	local POLENTA=Color3.fromRGB(250,215,90); local POLENTA2=Color3.fromRGB(230,190,70); local BUTTER=Color3.fromRGB(255,240,150); local BLACK=Color3.fromRGB(25,25,30)
	-- Polenta head (corn mush lump, slightly squared)
	local head=bp({Name="Head", Size=Vector3.new(3.5,3,3.5), Color=POLENTA, Material=Enum.Material.Plastic})
	head.CFrame=cf(0,12,0); studAllFaces(head); head.Parent=m
	-- Butter melting on top
	local butter=bp({Name="Butter", Size=Vector3.new(2,0.8,2), Color=BUTTER, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
	butter.CFrame=cf(0,13.7,0); butter.Parent=m
	-- Corn kernels embedded
	for i=0,5 do
		local kernel=bp({Name="Kernel", Size=Vector3.new(0.5,0.5,0.5), Color=Color3.fromRGB(255,200,60), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		kernel.CFrame=cf(math.sin(i*1.1)*1.4, 11.5+math.cos(i*1.7)*1, math.cos(i*1.1)*1.4); kernel.CanCollide=false; kernel.Parent=m
	end
	-- Face
	for _,ex in ipairs({-0.8,0.8}) do
		local e=bp({Name="Eye", Size=Vector3.new(0.6,0.6,0.6), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		e.CFrame=cf(ex,11.8,-1.5); e.Parent=m
	end
	local mouth=bp({Name="Mouth", Size=Vector3.new(1.4,0.4,0.3), Color=BLACK, Material=Enum.Material.Plastic})
	mouth.CFrame=cf(0,10.8,-1.5); mouth.CanCollide=false; mouth.Parent=m
	-- Pillar body (classical column, polenta-colored)
	local pillar=bp({Name="Pillar", Size=Vector3.new(3.5,6,3.5), Color=POLENTA, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	pillar.CFrame=cf(0,5,0.5); studAllFaces(pillar); pillar.Parent=m
	-- Column flutes (vertical ridges)
	for i=0,5 do
		local ang=math.rad(i*60)
		local flute=bp({Name="Flute", Size=Vector3.new(0.4,5.5,0.4), Color=POLENTA2, Material=Enum.Material.Plastic})
		flute.CFrame=cf(math.cos(ang)*1.9, 5, 0.5+math.sin(ang)*1.9); flute.CanCollide=false; flute.Parent=m
	end
	-- Column capital (top) + base (bottom)
	local capital=bp({Name="Capital", Size=Vector3.new(4.5,1,4.5), Color=POLENTA2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	capital.CFrame=cf(0,8.3,0.5); studAllFaces(capital); capital.Parent=m
	local base=bp({Name="Base", Size=Vector3.new(4.5,1,4.5), Color=POLENTA2, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
	base.CFrame=cf(0,1.8,0.5); studAllFaces(base); base.Parent=m
	-- Legs
	for _,lx in ipairs({-1.3,1.3}) do
		local leg=bp({Name="Leg", Size=Vector3.new(1.2,1.5,1.2), Color=POLENTA2, Material=Enum.Material.Plastic})
		leg.CFrame=cf(lx,0.75,0.5); studAllFaces(leg); leg.Parent=m
	end
	local function addLabel(part, text, color)
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,68); bb.StudsOffset=Vector3.new(0,4,0); bb.MaxDistance=50; bb.Parent=part
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color; l.TextStrokeColor3=Color3.fromRGB(0,0,0); l.TextStrokeTransparency=0.25; l.TextScaled=false; l.TextSize=18; l.Font=Enum.Font.GothamBold; l.Parent=bb
	end
	addLabel(head, "Polenta Pillar [COMMON]", Color3.fromRGB(200,200,210))
	m.Parent=workspace; return m
end

-- ---------------------------------------------------------------------------
-- Satoshino Crocodilo — Mythic brainrot character (display model).
-- Crocodile head + Bitcoin mining rig body + gold pickaxe prop.
-- ---------------------------------------------------------------------------

local function buildSatoshinoCroc(posX, posZ)
	local m = Instance.new("Model")
	m.Name = "SatoshinoCrocodilo"

	local function bp(props)
		local p = part(props)
		p.Anchored = true
		p.CanCollide = true
		return p
	end

	-- Colors
	local CROC_GREEN = Color3.fromRGB(60, 140, 55)
	local CROC_BELLY = Color3.fromRGB(140, 190, 100)
	local RIG_DARK = Color3.fromRGB(45, 45, 50)
	local RIG_GREY = Color3.fromRGB(80, 80, 88)
	local GOLD = Color3.fromRGB(255, 200, 50)
	local GOLD_DARK = Color3.fromRGB(200, 155, 30)
	local WHITE = Color3.fromRGB(245, 245, 245)
	local BLACK = Color3.fromRGB(25, 25, 30)
	local RED = Color3.fromRGB(220, 60, 50)

	local FY = 2  -- floor offset
	local function cf(x, y, z, ry)
		return CFrame.new(posX + x, FY + y, posZ + z) * CFrame.Angles(0, math.rad(ry or 0), 0)
	end

	-- === HEAD: Crocodile (big, 1.5-2x body) ===
	-- Main skull
	local skull = bp({Name="CrocSkull", Size=Vector3.new(3.5, 2.8, 3.5), Color=CROC_GREEN, Material=Enum.Material.Plastic})
	skull.CFrame = cf(0, 11, 0)
	studAllFaces(skull)
	skull.Parent = m

	-- Snout (long, forward - toward road = -X... but character faces +X for display)
	-- Face direction: let's face -Z (road is at x=0, base at x=65, so face -X)
	-- Actually let's just build facing -Z and rotate later if needed
	local snout = bp({Name="CrocSnout", Size=Vector3.new(3, 1.8, 3.5), Color=CROC_GREEN, Material=Enum.Material.Plastic})
	snout.CFrame = cf(0, 9.8, -3)
	studAllFaces(snout)
	snout.Parent = m

	-- Belly jaw (lower snout)
	local jaw = bp({Name="CrocJaw", Size=Vector3.new(2.8, 1, 3.2), Color=CROC_BELLY, Material=Enum.Material.Plastic})
	jaw.CFrame = cf(0, 8.5, -3)
	studAllFaces(jaw)
	jaw.Parent = m

	-- Teeth (top row - white wedges on snout edge)
	for i = -2, 2 do
		local tooth = bp({Name="Tooth", Size=Vector3.new(0.5, 0.7, 0.5), Color=WHITE, Material=Enum.Material.Plastic})
		tooth.CFrame = cf(i * 0.6, 8.9, -4.5)
		tooth.Parent = m
	end
	-- Teeth (bottom row)
	for i = -2, 2 do
		local tooth = bp({Name="Tooth", Size=Vector3.new(0.5, 0.6, 0.5), Color=WHITE, Material=Enum.Material.Plastic})
		tooth.CFrame = cf(i * 0.6, 9.2, -4.4)
		tooth.Parent = m
	end

	-- Eyes (big, on top of head - croc style)
	for _, ex in ipairs({-1.2, 1.2}) do
		-- Eye bulge
		local bulge = bp({Name="EyeBulge", Size=Vector3.new(1.3, 1.3, 1.3), Color=CROC_GREEN, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		bulge.CFrame = cf(ex, 12.5, -0.8)
		bulge.Parent = m

		-- White eye
		local eyeW = bp({Name="EyeWhite", Size=Vector3.new(1, 1, 1), Color=WHITE, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		eyeW.CFrame = cf(ex, 12.6, -1.3)
		eyeW.Parent = m

		-- Pupil (black)
		local pupil = bp({Name="Pupil", Size=Vector3.new(0.5, 0.5, 0.5), Color=BLACK, Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		pupil.CFrame = cf(ex, 12.6, -1.7)
		pupil.Parent = m
	end

	-- Nostrils (2 small bumps on snout tip)
	for _, nx2 in ipairs({-0.6, 0.6}) do
		local nostril = bp({Name="Nostril", Size=Vector3.new(0.5, 0.4, 0.5), Color=Color3.fromRGB(45, 110, 40), Material=Enum.Material.Plastic, Shape=Enum.PartType.Ball})
		nostril.CFrame = cf(nx2, 10.8, -4.5)
		nostril.Parent = m
	end

	-- === BODY: Bitcoin Mining Rig (2-3 parts, vertical) ===
	-- Main rig box
	local rig = bp({Name="MiningRig", Size=Vector3.new(3.5, 4, 3), Color=RIG_DARK, Material=Enum.Material.Plastic})
	rig.CFrame = cf(0, 6, 1)
	studAllFaces(rig)
	rig.Parent = m

	-- Rig top plate
	local rigTop = bp({Name="RigTop", Size=Vector3.new(3.8, 0.5, 3.3), Color=RIG_GREY, Material=Enum.Material.Plastic})
	rigTop.CFrame = cf(0, 8.25, 1)
	studAllFaces(rigTop)
	rigTop.Parent = m

	-- GPU fans (3 circles on front face)
	for i = -1, 1 do
		local fan = bp({Name="Fan", Size=Vector3.new(1, 1, 0.3), Color=RIG_GREY, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
		fan.CFrame = cf(i * 1.1, 6.5, -0.6) * CFrame.Angles(math.rad(90), 0, 0)
		fan.Parent = m

		-- Fan center (red LED)
		local led = bp({Name="FanLED", Size=Vector3.new(0.4, 0.4, 0.35), Color=RED, Material=Enum.Material.Plastic, Shape=Enum.PartType.Cylinder})
		led.CFrame = cf(i * 1.1, 6.5, -0.65) * CFrame.Angles(math.rad(90), 0, 0)
		led.Parent = m
	end

	-- Bitcoin symbol plate on rig side (gold square)
	local btcPlate = bp({Name="BTCPlate", Size=Vector3.new(0.3, 1.5, 1.5), Color=GOLD, Material=Enum.Material.Plastic})
	btcPlate.CFrame = cf(1.9, 6, 1)
	btcPlate.Parent = m

	-- Bitcoin "B" (small block on plate)
	local btcB = bp({Name="BTC_B", Size=Vector3.new(0.2, 0.8, 0.5), Color=BLACK, Material=Enum.Material.Plastic})
	btcB.CFrame = cf(2.05, 6, 1)
	btcB.Parent = m

	-- Cable (hanging from back of rig)
	local cable = bp({Name="Cable", Size=Vector3.new(0.3, 2.5, 0.3), Color=BLACK, Material=Enum.Material.Plastic})
	cable.CFrame = cf(0, 4.5, 2.8) * CFrame.Angles(math.rad(20), 0, 0)
	cable.Parent = m

	-- === LEGS: 4 stubby reptile legs ===
	local legPositions = {
		{-1.5, -0.5}, {1.5, -0.5},
		{-1.5, 2.5}, {1.5, 2.5},
	}
	for _, lp in ipairs(legPositions) do
		-- Upper leg
		local leg = bp({Name="Leg", Size=Vector3.new(1, 2, 1), Color=CROC_GREEN, Material=Enum.Material.Plastic})
		leg.CFrame = cf(lp[1], 2, lp[2])
		studAllFaces(leg)
		leg.Parent = m

		-- Foot (wider, clawed)
		local foot = bp({Name="Foot", Size=Vector3.new(1.4, 0.6, 1.8), Color=CROC_GREEN, Material=Enum.Material.Plastic})
		foot.CFrame = cf(lp[1], 0.7, lp[2] - 0.3)
		studAllFaces(foot)
		foot.Parent = m

		-- Claws (3 small white wedges per foot)
		for c = -1, 1 do
			local claw = bp({Name="Claw", Size=Vector3.new(0.3, 0.3, 0.6), Color=WHITE, Material=Enum.Material.Plastic})
			claw.CFrame = cf(lp[1] + c * 0.4, 0.6, lp[2] - 1.2)
			claw.Parent = m
		end
	end

	-- === ARMS (holding pickaxe) ===
	-- Right arm extended holding pickaxe
	local armR = bp({Name="ArmR", Size=Vector3.new(0.9, 3, 0.9), Color=CROC_GREEN, Material=Enum.Material.Plastic})
	armR.CFrame = cf(2.5, 7, -0.5) * CFrame.Angles(0, 0, math.rad(-30))
	studAllFaces(armR)
	armR.Parent = m

	-- Left arm at side
	local armL = bp({Name="ArmL", Size=Vector3.new(0.9, 3, 0.9), Color=CROC_GREEN, Material=Enum.Material.Plastic})
	armL.CFrame = cf(-2.5, 6.5, 0.5)
	studAllFaces(armL)
	armL.Parent = m

	-- === PROP: Gold Pickaxe ===
	-- Handle (wood)
	local handle = bp({Name="PickHandle", Size=Vector3.new(0.4, 6, 0.4), Color=Color3.fromRGB(130, 90, 50), Material=Enum.Material.Plastic})
	handle.CFrame = cf(4, 8, -1) * CFrame.Angles(math.rad(15), 0, math.rad(-25))
	studAllFaces(handle)
	handle.Parent = m

	-- Pick head (gold, curved shape from2 parts)
	local pickTop = bp({Name="PickTop", Size=Vector3.new(3, 0.6, 0.8), Color=GOLD, Material=Enum.Material.Plastic})
	pickTop.CFrame = cf(4.8, 11, -1.8) * CFrame.Angles(0, 0, math.rad(-25))
	studAllFaces(pickTop)
	pickTop.Parent = m

	local pickTip = bp({Name="PickTip", Size=Vector3.new(1, 0.5, 0.6), Color=GOLD_DARK, Material=Enum.Material.Plastic})
	pickTip.CFrame = cf(6.2, 11.6, -2.2) * CFrame.Angles(0, 0, math.rad(-40))
	studAllFaces(pickTip)
	pickTip.Parent = m

	-- === BACK RIDGE (croc spines) ===
	for i = 0, 5 do
		local spine = bp({Name="Spine", Size=Vector3.new(0.5, 1 + i * 0.15, 0.5), Color=Color3.fromRGB(45, 110, 40), Material=Enum.Material.Plastic})
		spine.CFrame = cf(0, 9 + i * 0.3, 1.5 + i * 0.8)
		spine.Parent = m
	end

	-- === TAIL (croc tail, tapering) ===
	local tail1 = bp({Name="Tail1", Size=Vector3.new(2, 1.5, 3), Color=CROC_GREEN, Material=Enum.Material.Plastic})
	tail1.CFrame = cf(0, 3.5, 4) * CFrame.Angles(math.rad(15), 0, 0)
	studAllFaces(tail1)
	tail1.Parent = m

	local tail2 = bp({Name="Tail2", Size=Vector3.new(1.2, 1, 3), Color=CROC_GREEN, Material=Enum.Material.Plastic})
	tail2.CFrame = cf(0, 2.8, 6.5) * CFrame.Angles(math.rad(25), 0, 0)
	studAllFaces(tail2)
	tail2.Parent = m

	local tail3 = bp({Name="Tail3", Size=Vector3.new(0.6, 0.7, 2), Color=CROC_BELLY, Material=Enum.Material.Plastic})
	tail3.CFrame = cf(0, 2.2, 8.5) * CFrame.Angles(math.rad(35), 0, 0)
	studAllFaces(tail3)
	tail3.Parent = m

	-- === LABEL ===
	local head = m:FindFirstChild("CrocSkull")
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 340, 0, 68)
		bb.StudsOffset = Vector3.new(0, 4, 0)
		bb.MaxDistance = 50
		bb.AlwaysOnTop = false
		bb.SizeOffset = Vector2.new(0, 0)
		bb.Parent = head
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = "Satoshino Crocodilo [MYTHIC]"
		label.TextColor3 = Color3.fromRGB(255, 200, 50)
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.25
		label.TextScaled = false
		label.TextSize = 18
		label.Font = Enum.Font.GothamBold
		label.Parent = bb
	end

	m.Parent = workspace
	return m
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
	-- Pedestal1..4 (starter slots). Named "Pedestal"..slot so placeUnit,
	-- unlockPedestalVisual and resetPedestalVisual find them by name.
	local pedPositions = {{-8, -12}, {-8, 12}, {8, -12}, {8, 12}}
	for i, pos in ipairs(pedPositions) do
		local px = bx + pos[1]
		local step1 = bp({Name="Pedestal" .. i, Size=Vector3.new(7, 1, 7), Color=pedColors[i], Material=Enum.Material.Plastic})
		step1.CFrame = CFrame.new(px, 4, pos[2])
		studAllFaces(step1)
		step1.Parent = m

		local step2 = bp({Name="PedestalTop" .. i, Size=Vector3.new(5, 0.5, 5), Color=Color3.fromRGB(30,30,35), Material=Enum.Material.Plastic})
		step2.CFrame = CFrame.new(px, 4.75, pos[2])
		studAllFaces(step2)
		step2.Parent = m
	end

	-- Pedestal5..10: unlocked later via the shop (slots up to maxSlots=10).
	local pedExtra = {{-16, -6}, {-16, 6}, {16, -6}, {16, 6}, {0, -16}, {0, 16}}
	for j, pos in ipairs(pedExtra) do
		local slot = 4 + j
		local px = bx + pos[1]
		local step1 = bp({Name="Pedestal" .. slot, Size=Vector3.new(6, 1, 6), Color=Color3.fromRGB(95, 100, 115), Material=Enum.Material.Plastic})
		step1.CFrame = CFrame.new(px, 4, pos[2])
		studAllFaces(step1)
		step1.Parent = m

		local step2 = bp({Name="PedestalTop" .. slot, Size=Vector3.new(4.5, 0.5, 4.5), Color=Color3.fromRGB(30,30,35), Material=Enum.Material.Plastic})
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

function WorldBuilder.setBaseSign(model, title, subtitle, color)
	local sign = model:FindFirstChild("Sign")
	if sign == nil then
		return
	end
	local stripe = model:FindFirstChild("SignStripe")
	if stripe then
		stripe.Color = color
	end
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local guiName = "SignGui" .. face.Name
		local gui = sign:FindFirstChild(guiName)
		if gui == nil then
			gui = Instance.new("SurfaceGui")
			gui.Name = guiName
			gui.Face = face
			gui.Parent = sign
			local titleL = Instance.new("TextLabel")
			titleL.Name = "Title"
			titleL.Size = UDim2.new(1, 0, 0.55, 0)
			titleL.BackgroundTransparency = 1
			titleL.TextScaled = true
			titleL.Font = Enum.Font.GothamBold
			titleL.Parent = gui
			local subL = Instance.new("TextLabel")
			subL.Name = "Subtitle"
			subL.Size = UDim2.new(1, 0, 0.4, 0)
			subL.Position = UDim2.new(0, 0, 0.58, 0)
			subL.BackgroundTransparency = 1
			subL.TextScaled = true
			subL.Font = Enum.Font.Gotham
			subL.Parent = gui
		end
		local t = gui:FindFirstChild("Title")
		local s = gui:FindFirstChild("Subtitle")
		if t then
			t.Text = title
			t.TextColor3 = color
		end
		if s then
			s.Text = subtitle
			s.TextColor3 = Color3.fromRGB(235, 235, 240)
		end
	end
end

function WorldBuilder.buildSpawnPad(index)
	local zOffsets = {[1] = 0, [2] = 95, [3] = -95}
	local z = zOffsets[index] or 0
	local pad = part({Name = "SpawnPad" .. index, Size = Vector3.new(6, 1, 6), Color = Color3.fromRGB(50, 200, 50), Material = Enum.Material.Plastic})
	pad.Anchored = true
	pad.CanCollide = true
	pad.TopSurface = Enum.SurfaceType.Studs
	pad.CFrame = CFrame.new(36, 0.5, z)
	pad.Parent = workspace
	return pad
end

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
	-- Build all43 characters (parade script yang atur posisi/jalan)
	safeStep("buildSatoshinoCroc", function() buildSatoshinoCroc(0, 0) end)
	safeStep("buildBananitaWhalebit", function() buildBananitaWhalebit(0, 0) end)
	safeStep("buildPatapimNode", function() buildPatapimNode(0, 0) end)
	safeStep("buildTralaleroRugpull", function() buildTralaleroRugpull(0, 0) end)
	safeStep("buildBombombiniGasfee", function() buildBombombiniGasfee(0, 0) end)
	safeStep("buildBombardiroAirdrop", function() buildBombardiroAirdrop(0, 0) end)
	safeStep("buildBanditoreArbitrage", function() buildBanditoreArbitrage(0, 0) end)
	safeStep("buildBrrBrrNodek", function() buildBrrBrrNodek(0, 0) end)
	safeStep("buildFrigoCameloWhale", function() buildFrigoCameloWhale(0, 0) end)
	safeStep("buildTungTungSahur", function() buildTungTungSahur(0, 0) end)
	safeStep("buildCapuccinaMining", function() buildCapuccinaMining(0, 0) end)
	safeStep("buildPipiPotatoStake", function() buildPipiPotatoStake(0, 0) end)
	safeStep("buildChimpanziniSolana", function() buildChimpanziniSolana(0, 0) end)
	safeStep("buildHamsteroWheel", function() buildHamsteroWheel(0, 0) end)
	safeStep("buildLamenoTungsten", function() buildLamenoTungsten(0, 0) end)
	safeStep("buildGorillahMemecoin", function() buildGorillahMemecoin(0, 0) end)
	safeStep("buildPenguinoStable", function() buildPenguinoStable(0, 0) end)
	safeStep("buildFroggoMaker", function() buildFroggoMaker(0, 0) end)
	safeStep("buildSerpentinoDex", function() buildSerpentinoDex(0, 0) end)
	safeStep("buildOwlcornOracle", function() buildOwlcornOracle(0, 0) end)
	safeStep("buildElephanteBridge", function() buildElephanteBridge(0, 0) end)
	safeStep("buildCrabettoCex", function() buildCrabettoCex(0, 0) end)
	safeStep("buildPandanoVault", function() buildPandanoVault(0, 0) end)
	safeStep("buildTortugaLedger", function() buildTortugaLedger(0, 0) end)
	safeStep("buildViperinoNode", function() buildViperinoNode(0, 0) end)
	safeStep("buildAquilinoStake", function() buildAquilinoStake(0, 0) end)
	safeStep("buildCucumbroChain", function() buildCucumbroChain(0, 0) end)
	safeStep("buildGelatinoMint", function() buildGelatinoMint(0, 0) end)
	safeStep("buildPiccioneBridge", function() buildPiccioneBridge(0, 0) end)
	safeStep("buildGattinoSwap", function() buildGattinoSwap(0, 0) end)
	safeStep("buildBruschettaBlock", function() buildBruschettaBlock(0, 0) end)
	safeStep("buildVolpeOracle", function() buildVolpeOracle(0, 0) end)
	safeStep("buildZucchinoVault", function() buildZucchinoVault(0, 0) end)
	safeStep("buildMoscatoWhale", function() buildMoscatoWhale(0, 0) end)
	safeStep("buildCannoliBlaster", function() buildCannoliBlaster(0, 0) end)
	safeStep("buildGnocchiGolem", function() buildGnocchiGolem(0, 0) end)
	safeStep("buildFocacciaNode", function() buildFocacciaNode(0, 0) end)
	safeStep("buildPestoPirate", function() buildPestoPirate(0, 0) end)
	safeStep("buildTiramisuTower", function() buildTiramisuTower(0, 0) end)
	safeStep("buildArancinoBomb", function() buildArancinoBomb(0, 0) end)
	safeStep("buildLimoneFrost", function() buildLimoneFrost(0, 0) end)
	safeStep("buildProsciuttoSmoke", function() buildProsciuttoSmoke(0, 0) end)
	safeStep("buildPolentaPillar", function() buildPolentaPillar(0, 0) end)

-- Streaming parade:43 karakter berurutan masuk jalan, spacing20, no overlap.
	-- Window [0,290] di aspal; di luar window = hide (muncul berurutan dari z=-145).
	safeStep("buildParade", function()
		local RunService = game:GetService("RunService")
		local SPEED = 6
		local SPACING = 20
		local SPAN = 290
		local PARADE_NAMES = {"SatoshinoCrocodilo", "BananitaWhalebit", "PatapimNode", "TralaleroRugpull", "BombombiniGasfee", "BombardiroAirdrop", "BanditoreArbitrage", "BrrBrrNodek", "FrigoCameloWhale", "TungTungSahur", "CapuccinaMining", "PipiPotatoStake", "ChimpanziniSolana", "HamsteroWheel", "LamenoTungsten", "GorillahMemecoin", "PenguinoStable", "FroggoMaker", "SerpentinoDex", "OwlcornOracle", "ElephanteBridge", "CrabettoCex", "PandanoVault", "TortugaLedger", "ViperinoNode", "AquilinoStake", "CucumbroChain", "GelatinoMint", "PiccioneBridge", "GattinoSwap", "BruschettaBlock", "VolpeOracle", "ZucchinoVault", "MoscatoWhale", "CannoliBlaster", "GnocchiGolem", "FocacciaNode", "PestoPirate", "TiramisuTower", "ArancinoBomb", "LimoneFrost", "ProsciuttoSmoke", "PolentaPillar"}
		local CYCLE = #PARADE_NAMES * SPACING
		local t = 0

		local models = {}
		local ys = {}
		local rots = {}
		for _, n in ipairs(PARADE_NAMES) do
			local m = workspace:FindFirstChild(n)
			if m then
				local p = m:GetPivot()
				models[#models + 1] = m
				ys[#ys + 1] = p.Position.Y
				rots[#rots + 1] = p.Rotation
			end
		end

		-- Pasang ClickDetector biar bisa di-catch (handler di init.server).
		for _, m in ipairs(models) do
			local clicker = m:FindFirstChildWhichIsA("ClickDetector", true)
			if clicker == nil then
				clicker = Instance.new("ClickDetector")
				clicker.MaxActivationDistance = 25
				clicker.Parent = m
			end
		end

		local function update()
			local now = os.time()
			for i, m in ipairs(models) do
				-- Kalo ke-catch (CaughtUntil > now): sembunyikan dari parade.
				local caughtUntil = m:GetAttribute("CaughtUntil") or 0
				local caught = caughtUntil > now
				local pos = ((i - 1) * SPACING + t) % CYCLE
				if pos <= SPAN and not caught then
					if m.Parent ~= workspace then m.Parent = workspace end
					m:PivotTo(CFrame.new(0, ys[i], 145 - pos) * rots[i])
				else
					if m.Parent ~= nil then m.Parent = nil end
				end
			end
		end

		update()
		RunService.Heartbeat:Connect(function(dt)
			t = t + dt * SPEED
			update()
		end)
	end)

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

	-- Base attributes used by claim/lock/tsunami (Index, CenterX, CenterZ).
	local baseInfo = {
		{ baseModel, 1, 65, 0 },
		{ baseModel2, 2, 65, 95 },
		{ baseModel3, 3, 65, -95 },
	}
	for _, info in ipairs(baseInfo) do
		local b, idx, cx, cz = info[1], info[2], info[3], info[4]
		if b then
			b.Name = "Base" .. idx
			b:SetAttribute("Index", idx)
			b:SetAttribute("CenterX", cx)
			b:SetAttribute("CenterZ", cz)
		end
	end

	return {
		pads = { WorldBuilder.buildSpawnPad(1), WorldBuilder.buildSpawnPad(2), WorldBuilder.buildSpawnPad(3) },
		bases = { baseModel, baseModel2, baseModel3 },
	}
end

return WorldBuilder