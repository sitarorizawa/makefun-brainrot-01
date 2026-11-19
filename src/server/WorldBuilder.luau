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
	addLabel(skull, "Bombardiro Airdrop [MYTHIC]", Color3.fromRGB(255,200,50))

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
	addLabel(head, "Pipi Potato Stake [RARE]", Color3.fromRGB(255,180,190))
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
	addLabel(head, "Chimpanzini Solana [UNCOMMON]", Color3.fromRGB(170,100,255))
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
	-- 13 characters lined up beside the market (shop at x=-50)
	safeStep("buildSatoshinoCroc", function() buildSatoshinoCroc(-50, 25) end)
	safeStep("buildBananitaWhalebit", function() buildBananitaWhalebit(-50, 38) end)
	safeStep("buildPatapimNode", function() buildPatapimNode(-50, 51) end)
	safeStep("buildTralaleroRugpull", function() buildTralaleroRugpull(-50, 64) end)
	safeStep("buildBombombiniGasfee", function() buildBombombiniGasfee(-50, 77) end)
	safeStep("buildBombardiroAirdrop", function() buildBombardiroAirdrop(-50, 90) end)
	safeStep("buildBanditoreArbitrage", function() buildBanditoreArbitrage(-50, 103) end)
	safeStep("buildBrrBrrNodek", function() buildBrrBrrNodek(-50, 116) end)
	safeStep("buildFrigoCameloWhale", function() buildFrigoCameloWhale(-50, 12) end)
	safeStep("buildTungTungSahur", function() buildTungTungSahur(-50, -1) end)
	safeStep("buildCapuccinaMining", function() buildCapuccinaMining(-50, -14) end)
	safeStep("buildPipiPotatoStake", function() buildPipiPotatoStake(-50, -27) end)
	safeStep("buildChimpanziniSolana", function() buildChimpanziniSolana(-50, -40) end)
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