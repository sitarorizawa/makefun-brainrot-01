-- WorldBuilder: clean tycoon layout matching the operator's reference.
-- Green stud baseplate, wide red carpet down the center, 4 base buildings
-- (2 per side) with grey walls, white-framed windows, red interiors and
-- "YOUR BASE" BillboardGuis. Golden statues along the carpet, capsule
-- pads on both sides, a small vault sign at the far end. Phase 7 adds
-- base-interior machine clusters, environment props (trees, rocks, lamps,
-- benches, bushes), ground detail (plaza tiles, hedge fencing) and
-- hardened lighting with shadows and atmosphere.
-- Phase 8a: bigger bases, doorway openings, roof slabs, perimeter wall,
-- statue repositioning, neat grid interiors, stone paths.
--
-- Keep the interface init.server.luau depends on:
--   build() → { pads = array<Part>, bases = array<Model> }
--   setBaseSign(model, title, subtitle, color)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local CARPET_HALF = 72 -- carpet runs Z = -72 .. +72
local CARPET_WIDTH = 22
local BASE_GAP = 64  -- Z-distance between front-row and back-row bases
local BASE_X = 34    -- absolute X of each base's center
local PEDESTAL_SPACING = 5.2
local MAP_HALF = 110 -- ground extends ±110 on X and Z

-- Colors
local GRASS_GREEN = Color3.fromRGB(98, 178, 72)
local CARPET_RED = Color3.fromRGB(195, 48, 48)
local WALL_GREY = Color3.fromRGB(160, 165, 175)
local WINDOW_WHITE = Color3.fromRGB(245, 245, 250)
local INTERIOR_RED = Color3.fromRGB(188, 52, 52)
local STATUE_GOLD = Color3.fromRGB(255, 210, 48)
local SIGN_DARK = Color3.fromRGB(32, 36, 44)
local DARK_METAL = Color3.fromRGB(52, 56, 66)
local ACCENT_CYAN = Color3.fromRGB(64, 210, 210)
local ACCENT_ORANGE = Color3.fromRGB(255, 155, 65)
local TRUNK_BROWN = Color3.fromRGB(110, 78, 48)
local LEAF_GREEN = Color3.fromRGB(68, 148, 56)
local LEAF_DARK = Color3.fromRGB(48, 110, 38)
local ROCK_GREY = Color3.fromRGB(130, 135, 140)
local LAMP_BLACK = Color3.fromRGB(38, 40, 48)
local LAMP_GOLD = Color3.fromRGB(240, 215, 70)
local BENCH_WOOD = Color3.fromRGB(145, 110, 70)
local HEDGE_GREEN = Color3.fromRGB(52, 128, 42)
local PATH_TILE = Color3.fromRGB(195, 185, 165)
local ROOF_DARK = Color3.fromRGB(42, 44, 54)
local ROOF_TRIM = Color3.fromRGB(255, 210, 48)
local PERIM_WALL = Color3.fromRGB(120, 122, 130)
local PERIM_TRIM = Color3.fromRGB(255, 210, 48)
local DOOR_FRAME = Color3.fromRGB(255, 210, 48)
local GRASS_DARK = Color3.fromRGB(74, 142, 52)
local PATH_STONE = Color3.fromRGB(150, 140, 122)
local COUNTER_WOOD = Color3.fromRGB(120, 88, 56)
local NEON_STRIPE = Color3.fromRGB(64, 210, 210)

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
-- BillboardGui for a base nameplate.  Kept separate from the old `label()`
-- so we never leak floating labels onto the map.
-- ---------------------------------------------------------------------------

local function buildBaseNameplate(parent, title, color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BaseSignGui"
	gui.Size = UDim2.fromOffset(240, 68)
	gui.StudsOffset = Vector3.new(0, 0.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.Parent = parent

	-- Opaque-ish dark background panel so the sign reads over bright surfaces.
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	bg.BackgroundTransparency = 0.18
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 8)
	bgCorner.Parent = bg

	local main = Instance.new("TextLabel")
	main.Name = "Title"
	main.Size = UDim2.fromScale(1, 0.58)
	main.BackgroundTransparency = 1
	main.Font = Enum.Font.GothamBold
	main.TextScaled = true
	main.Text = title
	main.TextColor3 = color or Color3.new(1, 1, 1)
	main.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	main.TextStrokeTransparency = 0.25
	main.ZIndex = 2
	main.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.Size = UDim2.fromScale(1, 0.42)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Text = ""
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	sub.TextStrokeTransparency = 0.3
	sub.ZIndex = 2
	sub.Parent = gui

	return gui
end

-- ---------------------------------------------------------------------------
-- Lighting: bright afternoon with hard-set shadows, sky and atmosphere.
-- Phase 7: every property is set explicitly so a missing shadow/atmosphere
-- is impossible.
-- ---------------------------------------------------------------------------

local function setupLighting()
	-- Hard-set every lighting property so nothing silently fails.
	Lighting.Brightness = 3
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 15
	Lighting.Ambient = Color3.fromRGB(135, 135, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(185, 190, 195)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ExposureCompensation = 0.25
	Lighting.FogStart = 900000
	Lighting.FogEnd = 1000000

	-- Shadows: the project.json sets GlobalShadows and ShadowMap, but we
	-- also force them here in case the template baseplate overwrote them.
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25

	-- DirectionalLight: explicit late-afternoon sun, bright, shadows on.
	-- (Lighting.Technology is intentionally never assigned.)
	local oldSun = Lighting:FindFirstChild("MainSun")
	if oldSun then oldSun:Destroy() end
	local sun = Instance.new("DirectionalLight")
	sun.Name = "MainSun"
	sun.Brightness = 2.5
	sun.Shadows = true
	sun.CFrame = CFrame.new(Vector3.new(80, 60, -30), Vector3.new(0, 0, 0))
	sun.Parent = Lighting

	-- Remove any existing Sky so we always create a fresh one.
	local oldSky = Lighting:FindFirstChildWhichIsA("Sky")
	if oldSky then oldSky:Destroy() end
	local sky = Instance.new("Sky")
	sky.Name = "DaySky"
	sky.SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex"
	sky.SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex"
	sky.SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex"
	sky.SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex"
	sky.SkyboxUp = "rbxasset://textures/sky/sky512_up.tex"
	sky.SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex"
	sky.StarCount = 0
	sky.Parent = Lighting

	-- Remove any existing Atmosphere so we always create a fresh one.
	local oldAtmo = Lighting:FindFirstChildWhichIsA("Atmosphere")
	if oldAtmo then oldAtmo:Destroy() end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "VaultAtmosphere"
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(199, 204, 214)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting
end

-- ---------------------------------------------------------------------------
-- Green stud baseplate + red carpet
-- ---------------------------------------------------------------------------

local function buildGround()
	local template = workspace:FindFirstChild("Baseplate")
	if template then template:Destroy() end

	local half = 110
	-- Green stud baseplate: Plastic material gives the classic stud texture.
	local baseplate = part({
		Name = "Ground",
		Size = Vector3.new(half * 2 + 4, 0.4, half * 2 + 4),
		Color = GRASS_GREEN,
		Material = Enum.Material.Plastic,
	})
	baseplate.CFrame = CFrame.new(0, -0.15, 0)
	baseplate.Parent = workspace

	-- Varied grass patches: slightly darker strips for visual variation.
	for _, gx in ipairs({ -70, -30, 30, 70 }) do
		local grassPatch = part({
			Name = "GrassPatch",
			Size = Vector3.new(18, 0.15, MAP_HALF * 2 + 4),
			Color = GRASS_DARK,
			Material = Enum.Material.Plastic,
		})
		grassPatch.CFrame = CFrame.new(gx, 0.08, 0)
		grassPatch.Parent = workspace
	end

	-- Red carpet: wide, runs Z = -CARPET_HALF .. +CARPET_HALF
	local carpet = part({
		Name = "Carpet",
		Size = Vector3.new(CARPET_WIDTH, 0.22, CARPET_HALF * 2),
		Color = CARPET_RED,
		Material = Enum.Material.SmoothPlastic,
	})
	carpet.CFrame = CFrame.new(0, 0.11, 0)
	carpet.Parent = workspace

	-- Thin gold trim on each side of the carpet so it pops against the green.
	for _, side in ipairs({ -CARPET_WIDTH / 2, CARPET_WIDTH / 2 }) do
		local trim = part({
			Name = "CarpetTrim",
			Size = Vector3.new(0.6, 0.12, CARPET_HALF * 2),
			Color = STATUE_GOLD,
			Material = Enum.Material.Metal,
		})
		trim.CFrame = CFrame.new(side, 0.22, 0)
		trim.CanCollide = false
		trim.Parent = workspace
	end
end

-- ---------------------------------------------------------------------------
-- Base interior machine cluster: a cash generator box, a conveyor strip,
-- an upgrade console, a shelf, an inner wall, a counter desk, and a neon
-- accent stripe. All placed on a tidy grid.
-- ---------------------------------------------------------------------------

local function buildBaseInterior(model, cx, cz, facingDir)
	local halfW = 13
	local wallH = 10

	-- Inner wall: a dividing line about 1/3 back from the front wall, with a gap for passage.
	local innerWallXLen = halfW * 2 - 6
	local innerWall = part({
		Name = "InnerWall",
		Size = Vector3.new(innerWallXLen, wallH, 0.4),
		Color = WALL_GREY,
		Material = Enum.Material.Concrete,
	})
	innerWall.CFrame = CFrame.new(cx, wallH / 2 + 0.2, cz + facingDir * 0)
	innerWall.Parent = model

	-- Counter / cash desk: wooden slab in the front-right area.
	local counter = part({
		Name = "Counter",
		Size = Vector3.new(6, 1.2, 2.8),
		Color = COUNTER_WOOD,
		Material = Enum.Material.Wood,
	})
	counter.CFrame = CFrame.new(cx + 6, 0.6, cz + facingDir * (-halfW + 5))
	counter.Parent = model

	-- Cash generator: dark-metal box with a cyan accent bar, back-left corner.
	local gen = part({
		Name = "CashGenerator",
		Size = Vector3.new(3, 2.6, 2),
		Color = DARK_METAL,
		Material = Enum.Material.Metal,
	})
	gen.CFrame = CFrame.new(cx - 8, 1.5, cz + facingDir * 6)
	gen.Parent = model
	local genAccent = part({
		Name = "GenLight",
		Size = Vector3.new(2.6, 0.3, 0.3),
		Color = ACCENT_CYAN,
		Material = Enum.Material.Neon,
	})
	genAccent.CFrame = CFrame.new(cx - 8, 3.0, cz + facingDir * 5)
	genAccent.Parent = model

	-- Upgrade console: thin angled slab with an orange screen, back-center.
	local console = part({
		Name = "UpgradeConsole",
		Size = Vector3.new(1.6, 2.8, 0.6),
		Color = DARK_METAL,
		Material = Enum.Material.Metal,
	})
	console.CFrame = CFrame.new(cx, 1.6, cz + facingDir * 6)
	console.Parent = model
	local screen = part({
		Name = "Screen",
		Size = Vector3.new(1.2, 1.6, 0.2),
		Color = ACCENT_ORANGE,
		Material = Enum.Material.Neon,
	})
	screen.CFrame = CFrame.new(cx, 2.7, cz + facingDir * 5.7)
	screen.Parent = model

	-- Conveyor strip: low flat rectangles across the back, near the wall.
	local conv = part({
		Name = "Conveyor",
		Size = Vector3.new(8, 0.4, 1.2),
		Color = Color3.fromRGB(72, 76, 86),
		Material = Enum.Material.Metal,
	})
	conv.CFrame = CFrame.new(cx + 4, 0.55, cz + facingDir * (halfW - 2.6))
	conv.Parent = model
	for _, rollX in ipairs({ -2.6, 0, 2.6 }) do
		local roller = part({
			Name = "Roller",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 0.5, 0.5),
			Color = Color3.fromRGB(100, 105, 115),
			Material = Enum.Material.Metal,
		})
		roller.CFrame = CFrame.new(cx + 4 + rollX, 0.72, cz + facingDir * (halfW - 2.6)) * CFrame.Angles(0, 0, math.rad(90))
		roller.Parent = model
	end

	-- Shelf: three shelves against one side wall, back of the room.
	for shelfRow = 0, 2 do
		local shelf = part({
			Name = "Shelf" .. shelfRow,
			Size = Vector3.new(2.8, 0.25, 1.6),
			Color = BENCH_WOOD,
			Material = Enum.Material.Wood,
		})
		shelf.CFrame = CFrame.new(cx - halfW + 3.0, 1.0 + shelfRow * 1.5, cz + facingDir * 8)
		shelf.Parent = model
	end

	-- Neon accent stripe along the inner wall.
	local neon = part({
		Name = "NeonStripe",
		Size = Vector3.new(halfW * 2 - 2, 0.3, 0.3),
		Color = NEON_STRIPE,
		Material = Enum.Material.Neon,
	})
	neon.CFrame = CFrame.new(cx, 3.6, cz + facingDir * 0.3)
	neon.Parent = model
end

-- ---------------------------------------------------------------------------
-- Environment props: trees, rocks, lamp posts, benches, bushes — spread
-- around the carpet but outside every base footprint so nothing clips.
-- ---------------------------------------------------------------------------

local BASE_FOOTPRINT_RADIUS = 14 -- safety margin around each base center (bumped for bigger bases)

local function inBaseFootprint(x, z)
	for _, bp in ipairs({
		{ x = -BASE_X, z = -BASE_GAP / 2 },
		{ x =  BASE_X, z = -BASE_GAP / 2 },
		{ x =  BASE_X, z =  BASE_GAP / 2 },
		{ x = -BASE_X, z =  BASE_GAP / 2 },
	}) do
		if math.abs(x - bp.x) < BASE_FOOTPRINT_RADIUS and math.abs(z - bp.z) < BASE_FOOTPRINT_RADIUS then
			return true
		end
	end
	return false
end

-- Random position on the grass, off the carpet, outside bases.
local function randomPropPos(rng, minDist, maxDist)
	for _ = 1, 40 do
		local ang = rng:NextNumber() * math.pi * 2
		local dist = minDist + rng:NextNumber() * (maxDist - minDist)
		local x = math.cos(ang) * dist
		local z = math.sin(ang) * dist
		-- Keep off the centre carpet.
		if math.abs(x) < CARPET_WIDTH / 2 + 3 and math.abs(z) < CARPET_HALF + 2 then
			continue
		end
		if not inBaseFootprint(x, z) and math.abs(x) < MAP_HALF - 6 and math.abs(z) < MAP_HALF - 6 then
			return x, z
		end
	end
	return nil, nil
end

local function buildTree(rng)
	local x, z = randomPropPos(rng, 14, MAP_HALF - 10)
	if x == nil then return end

	local model = Instance.new("Model")
	model.Name = "Tree"

	local h = 5 + rng:NextNumber() * 4 -- trunk height varies
	local trunkRadius = 0.8 + rng:NextNumber() * 0.3
	local trunk = part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, trunkRadius * 2, trunkRadius * 2),
		Color = TRUNK_BROWN,
		Material = Enum.Material.Wood,
	})
	trunk.CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Parent = model

	-- Pick a leaf palette for this tree (mix of light/dark green).
	local raw = rng:NextNumber()
	local leafColor: Color3
	if raw < 0.5 then
		leafColor = LEAF_GREEN
	else
		leafColor = LEAF_DARK
	end

	-- 3-4 stacked leaf balls of decreasing size, slightly offset for fullness.
	local layers = rng:NextInteger(3, 4)
	local baseSize = 5.5 + rng:NextNumber() * 1.5
	local y = h + baseSize * 0.35
	for i = 1, layers do
		local t = (i - 1) / math.max(1, layers - 1) -- 0 at bottom .. 1 at top
		local size = baseSize * (1 - t * 0.45)
		local ox = (rng:NextNumber() - 0.5) * 0.8
		local oz = (rng:NextNumber() - 0.5) * 0.8
		local leaves = part({
			Name = "Leaves" .. i,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			Color = i % 2 == 0 and LEAF_DARK or leafColor,
			Material = Enum.Material.Grass,
		})
		leaves.CFrame = CFrame.new(x + ox, y, z + oz)
		leaves.Parent = model
		y += size * 0.55
	end

	model.Parent = workspace
end

local function buildRock(rng)
	local x, z = randomPropPos(rng, 10, MAP_HALF - 14)
	if x == nil then return end

	local model = Instance.new("Model")
	model.Name = "Rock"

	local sx = 1.8 + rng:NextNumber() * 2.5
	local sy = 1.2 + rng:NextNumber() * 2
	local sz = 1.4 + rng:NextNumber() * 2.2
	local body = part({
		Name = "Body",
		Size = Vector3.new(sx, sy, sz),
		Color = ROCK_GREY,
		Material = Enum.Material.Slate,
	})
	body.CFrame = CFrame.new(x, sy / 2, z) * CFrame.Angles(0, math.rad(rng:NextNumber() * 360), 0)
	body.Parent = model

	-- A second smaller chunk on top
	local top = part({
		Name = "Top",
		Size = Vector3.new(sx * 0.55, sy * 0.5, sz * 0.55),
		Color = ROCK_GREY,
		Material = Enum.Material.Slate,
	})
	top.CFrame = CFrame.new(x + 0.4, sy + 0.25, z - 0.2) * CFrame.Angles(math.rad(5), math.rad(15), 0)
	top.Parent = model

	model.Parent = workspace
end

local function buildLampPost(rng)
	local x, z = randomPropPos(rng, 16, MAP_HALF - 16)
	if x == nil then return end

	local model = Instance.new("Model")
	model.Name = "LampPost"

	local poleH = 9
	local pole = part({
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(poleH, 0.45, 0.45),
		Color = LAMP_BLACK,
		Material = Enum.Material.Metal,
	})
	pole.CFrame = CFrame.new(x, poleH / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	pole.Parent = model

	-- Lamp head: a glowing warm-yellow sphere on top.
	local head = part({
		Name = "LampHead",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Color = LAMP_GOLD,
		Material = Enum.Material.Neon,
	})
	head.CFrame = CFrame.new(x, poleH + 0.8, z)
	head.Parent = model

	local pointLight = Instance.new("PointLight")
	pointLight.Color = LAMP_GOLD
	pointLight.Brightness = 3.2
	pointLight.Range = 24
	pointLight.Parent = head

	model.Parent = workspace
end

local function buildBench(rng)
	local x, z = randomPropPos(rng, 12, MAP_HALF - 12)
	if x == nil then return end

	local model = Instance.new("Model")
	model.Name = "Bench"

	local seat = part({
		Name = "Seat",
		Size = Vector3.new(3.6, 0.3, 1.0),
		Color = BENCH_WOOD,
		Material = Enum.Material.Wood,
	})
	seat.CFrame = CFrame.new(x, 1.1, z) * CFrame.Angles(0, math.rad(rng:NextNumber() * 360), 0)
	seat.Parent = model

	for _, side in ipairs({ -1, 1 }) do
		local leg = part({
			Name = "Leg",
			Size = Vector3.new(0.4, 1.0, 1.0),
			Color = BENCH_WOOD,
			Material = Enum.Material.Wood,
		})
		leg.CFrame = CFrame.new(x + side * 1.3, 0.5, z)
		leg.Parent = model
	end

	-- Back rest
	local back = part({
		Name = "Back",
		Size = Vector3.new(3.6, 0.3, 0.8),
		Color = BENCH_WOOD,
		Material = Enum.Material.Wood,
	})
	back.CFrame = CFrame.new(x, 1.55, z - 0.9) * CFrame.Angles(math.rad(-15), 0, 0)
	back.Parent = model

	model.Parent = workspace
end

local function buildBush(rng)
	local x, z = randomPropPos(rng, 8, MAP_HALF - 6)
	if x == nil then return end

	local model = Instance.new("Model")
	model.Name = "Bush"
	local count = rng:NextInteger(2, 4)
	for _ = 1, count do
		local bx = x + (rng:NextNumber() - 0.5) * 1.5
		local bz = z + (rng:NextNumber() - 0.5) * 1.5
		local sz = 0.8 + rng:NextNumber() * 1.2
		local ball = part({
			Name = "Leaf",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(sz, sz, sz),
			Color = LEAF_DARK,
			Material = Enum.Material.Grass,
		})
		ball.CFrame = CFrame.new(bx, sz * 0.5, bz)
		ball.Parent = model
	end
	model.Parent = workspace
end

local function buildEnvironmentProps()
	local rng = Random.new(42)

	-- 8 trees (aim for 6-10)
	for _ = 1, 8 do
		buildTree(rng)
	end

	-- 5 rocks (aim for 4-6)
	for _ = 1, 5 do
		buildRock(rng)
	end

	-- 4 lamp posts
	for _ = 1, 4 do
		buildLampPost(rng)
	end

	-- 2 benches
	for _ = 1, 2 do
		buildBench(rng)
	end

	-- 6 bushes
	for _ = 1, 6 do
		buildBush(rng)
	end
end

-- ---------------------------------------------------------------------------
-- Perimeter wall: solid wall on all four map edges, grey concrete with gold
-- trim along the top and thicker pillar blocks at the four corners.
-- ---------------------------------------------------------------------------

local function buildPerimeterWall()
	local h = 28
	local half = MAP_HALF
	local thick = 2

	-- Four wall slabs: one per edge.
	local wallLength = half * 2 + thick -- full edge length corner-to-corner

	-- North edge (z = -half)
	local nWall = part({
		Name = "PerimeterN",
		Size = Vector3.new(wallLength, h, thick),
		Color = PERIM_WALL,
		Material = Enum.Material.Concrete,
	})
	nWall.CFrame = CFrame.new(0, h / 2, -half)
	nWall.Parent = workspace

	-- South edge (z = +half)
	local sWall = part({
		Name = "PerimeterS",
		Size = Vector3.new(wallLength, h, thick),
		Color = PERIM_WALL,
		Material = Enum.Material.Concrete,
	})
	sWall.CFrame = CFrame.new(0, h / 2, half)
	sWall.Parent = workspace

	-- East edge (x = +half)
	local eWall = part({
		Name = "PerimeterE",
		Size = Vector3.new(thick, h, wallLength),
		Color = PERIM_WALL,
		Material = Enum.Material.Concrete,
	})
	eWall.CFrame = CFrame.new(half, h / 2, 0)
	eWall.Parent = workspace

	-- West edge (x = -half)
	local wWall = part({
		Name = "PerimeterW",
		Size = Vector3.new(thick, h, wallLength),
		Color = PERIM_WALL,
		Material = Enum.Material.Concrete,
	})
	wWall.CFrame = CFrame.new(-half, h / 2, 0)
	wWall.Parent = workspace

	-- Gold trim along the top of each edge.
	for _, edge in ipairs({
		{ name = "TrimN", cf = CFrame.new(0, h, -half), size = Vector3.new(wallLength, 1.2, 2.6) },
		{ name = "TrimS", cf = CFrame.new(0, h, half), size = Vector3.new(wallLength, 1.2, 2.6) },
		{ name = "TrimE", cf = CFrame.new(half, h, 0), size = Vector3.new(2.6, 1.2, wallLength) },
		{ name = "TrimW", cf = CFrame.new(-half, h, 0), size = Vector3.new(2.6, 1.2, wallLength) },
	}) do
		local trim = part({
			Name = edge.name,
			Size = edge.size,
			Color = PERIM_TRIM,
			Material = Enum.Material.Metal,
		})
		trim.CFrame = edge.cf
		trim.Parent = workspace
	end

	-- Thicker pillar blocks at the four corners.
	for _, corner in ipairs({
		{ x = -half, z = -half },
		{ x =  half, z = -half },
		{ x =  half, z =  half },
		{ x = -half, z =  half },
	}) do
		local pillar = part({
			Name = "CornerPillar",
			Size = Vector3.new(4, h + 2, 4),
			Color = PERIM_WALL,
			Material = Enum.Material.Concrete,
		})
		pillar.CFrame = CFrame.new(corner.x, h / 2 + 1, corner.z)
		pillar.Parent = workspace

		-- Gold cap on top of pillar
		local cap = part({
			Name = "PillarCap",
			Size = Vector3.new(4.8, 1.6, 4.8),
			Color = PERIM_TRIM,
			Material = Enum.Material.Metal,
		})
		cap.CFrame = CFrame.new(corner.x, h + 1.8, corner.z)
		cap.Parent = workspace
	end
end

-- ---------------------------------------------------------------------------
-- Stone/brick path from spawn area to each base entrance.
-- ---------------------------------------------------------------------------

local function buildStonePaths()
	local basePositions = {
		{ x = -BASE_X, z = -BASE_GAP / 2 },
		{ x =  BASE_X, z = -BASE_GAP / 2 },
		{ x =  BASE_X, z =  BASE_GAP / 2 },
		{ x = -BASE_X, z =  BASE_GAP / 2 },
	}

	for _, bp in ipairs(basePositions) do
		-- Carpet side toward base entrance
		local carpetX = bp.x > 0 and CARPET_WIDTH / 2 or -CARPET_WIDTH / 2
		-- Entrance is on the carpet-facing side (north or south depending on row)
		local entranceZ = bp.z + (bp.z > 0 and -1 or 1) * (23) -- halfW=13 for the new base, front wall
		-- Actually entrance Z is bp.z - halfW (for north-facing) or bp.z + halfW (south)
		-- For front row (z < 0, index 1,2): front wall is WallN at bp.z - halfW, facing carpet at larger z
		-- For back row (z > 0, index 3,4): front wall is WallS at bp.z + halfW, facing carpet at smaller z
		-- Carpet is in the middle, so:
		local dir = bp.z > 0 and -1 or 1 -- front row faces +z, back row faces -z
		local entranceZ = bp.z + dir * 13
		-- Path runs from (entranceX = bp.x, entranceZ) toward (carpetEdgeX, carpetEdgeZ at same z)
		-- Actually let's do a simple path: from the edge of carpet toward the base entrance
		local sx = bp.x > 0 and CARPET_WIDTH / 2 + 2 or -CARPET_WIDTH / 2 - 2
		local sz = entranceZ
		local ex = bp.x
		local ez = entranceZ

		-- Draw stepping stones along the line from (sx, sz) to (ex, ez)
		local steps = math.max(1, math.floor(math.abs(ex - sx) / 4))
		for i = 1, steps do
			local t = i / (steps + 1)
			local px = sx + (ex - sx) * t
			local pz = sz -- keep same z, just walk along X
			local stone = part({
				Name = "PathStone",
				Size = Vector3.new(2.6, 0.12, 3.0),
				Color = PATH_STONE,
				Material = Enum.Material.Slate,
			})
			stone.CFrame = CFrame.new(px, 0.18, pz)
			stone.Parent = workspace
		end
	end
end

-- ---------------------------------------------------------------------------
-- Single base building (Phase 8a overhaul).
-- ---------------------------------------------------------------------------

local function buildSingleBase(cx, cz, index)
	local model = Instance.new("Model")
	model.Name = "Base" .. index

	local wallH = 10
	local halfW = 13 -- half-width of the building

	-- Red interior floor — also the "Island" part the server hooks .Touched on.
	local floor = part({
		Name = "Island",
		Size = Vector3.new(halfW * 2, 0.4, halfW * 2),
		Color = INTERIOR_RED,
		Material = Enum.Material.SmoothPlastic,
	})
	floor.CFrame = CFrame.new(cx, 0.2, cz)
	floor.Parent = model

	-- Grey walls: four slabs around the floor, each 0.6 thick.
	-- Front wall (carpet-facing) gets a 5-stud doorway opening.
	-- Determine which wall faces the carpet:
	-- Row A (cz < 0, index 1,2): carpet is south (+z), front wall is WallS (cz + halfW)
	-- Row B (cz > 0, index 3,4): carpet is north (-z), front wall is WallN (cz - halfW)
	local carpetDir = cz > 0 and -1 or 1 -- direction from base center toward carpet

	-- Build all four walls as segments around the doorway.
	if carpetDir == 1 then
		-- Front wall (WallS at cz + halfW): doorway in the middle 5 studs.
		local doorHalf = 2.5
		-- Left segment
		local segL = part({
			Name = "WallS_L",
			Size = Vector3.new(halfW - doorHalf, wallH, 0.6),
			Color = WALL_GREY,
			Material = Enum.Material.Concrete,
		})
		segL.CFrame = CFrame.new(cx - (halfW + doorHalf) / 2, wallH / 2 + 0.2, cz + halfW)
		segL.Parent = model
		-- Right segment
		local segR = part({
			Name = "WallS_R",
			Size = Vector3.new(halfW - doorHalf, wallH, 0.6),
			Color = WALL_GREY,
			Material = Enum.Material.Concrete,
		})
		segR.CFrame = CFrame.new(cx + (halfW + doorHalf) / 2, wallH / 2 + 0.2, cz + halfW)
		segR.Parent = model
	else
		-- Front wall (WallN at cz - halfW): doorway in the middle 5 studs.
		local doorHalf = 2.5
		-- Left segment
		local segL = part({
			Name = "WallN_L",
			Size = Vector3.new(halfW - doorHalf, wallH, 0.6),
			Color = WALL_GREY,
			Material = Enum.Material.Concrete,
		})
		segL.CFrame = CFrame.new(cx - (halfW + doorHalf) / 2, wallH / 2 + 0.2, cz - halfW)
		segL.Parent = model
		-- Right segment
		local segR = part({
			Name = "WallN_R",
			Size = Vector3.new(halfW - doorHalf, wallH, 0.6),
			Color = WALL_GREY,
			Material = Enum.Material.Concrete,
		})
		segR.CFrame = CFrame.new(cx + (halfW + doorHalf) / 2, wallH / 2 + 0.2, cz - halfW)
		segR.Parent = model
	end

	-- Doorframe: gold pillars on each side of the opening and a threshold.
	local doorZ = cz + carpetDir * halfW
	local doorHalf = 2.5
	for _, dx in ipairs({ -doorHalf, doorHalf }) do
		local framePost = part({
			Name = "DoorFrame",
			Size = Vector3.new(0.8, wallH, 0.8),
			Color = DOOR_FRAME,
			Material = Enum.Material.Metal,
		})
		framePost.CFrame = CFrame.new(cx + dx, wallH / 2 + 0.2, doorZ)
		framePost.Parent = model
	end

	-- Threshold: a low gold block across the bottom of the doorway.
	local threshold = part({
		Name = "Threshold",
		Size = Vector3.new(doorHalf * 2 + 0.8, 0.4, 1.0),
		Color = DOOR_FRAME,
		Material = Enum.Material.Metal,
	})
	threshold.CFrame = CFrame.new(cx, 0.4, doorZ)
	threshold.Parent = model

	-- Solid side walls and back wall.
	local solidWalls = {
		{ name = "WallW", size = Vector3.new(0.6, wallH, halfW * 2), cf = CFrame.new(cx - halfW, wallH / 2 + 0.2, cz) },
		{ name = "WallE", size = Vector3.new(0.6, wallH, halfW * 2), cf = CFrame.new(cx + halfW, wallH / 2 + 0.2, cz) },
	}
	if carpetDir == 1 then
		-- Back wall is WallN
		table.insert(solidWalls, { name = "WallN", size = Vector3.new(halfW * 2 + 1.2, wallH, 0.6), cf = CFrame.new(cx, wallH / 2 + 0.2, cz - halfW) })
	else
		-- Back wall is WallS
		table.insert(solidWalls, { name = "WallS", size = Vector3.new(halfW * 2 + 1.2, wallH, 0.6), cf = CFrame.new(cx, wallH / 2 + 0.2, cz + halfW) })
	end
	for _, w in ipairs(solidWalls) do
		local wall = part({
			Name = w.name,
			Size = w.size,
			Color = WALL_GREY,
			Material = Enum.Material.Concrete,
		})
		wall.CFrame = w.cf
		wall.Parent = model
	end

	-- Roof slab: dark colour with gold accent trim, sized to the new footprint.
	local roofSlab = part({
		Name = "Roof",
		Size = Vector3.new(halfW * 2 + 1.8, 1.2, halfW * 2 + 1.8),
		Color = ROOF_DARK,
		Material = Enum.Material.Concrete,
	})
	roofSlab.CFrame = CFrame.new(cx, wallH + 1.2, cz)
	roofSlab.Parent = model

	-- Gold roof trim around the edge.
	local roofOverhang = halfW + 1.2
	for _, rt in ipairs({
		{ name = "RoofTrimN", cf = CFrame.new(cx, wallH + 2.0, cz - roofOverhang), size = Vector3.new(halfW * 2 + 2.2, 0.6, 0.6) },
		{ name = "RoofTrimS", cf = CFrame.new(cx, wallH + 2.0, cz + roofOverhang), size = Vector3.new(halfW * 2 + 2.2, 0.6, 0.6) },
		{ name = "RoofTrimE", cf = CFrame.new(cx + roofOverhang, wallH + 2.0, cz), size = Vector3.new(0.6, 0.6, halfW * 2 + 2.2) },
		{ name = "RoofTrimW", cf = CFrame.new(cx - roofOverhang, wallH + 2.0, cz), size = Vector3.new(0.6, 0.6, halfW * 2 + 2.2) },
	}) do
		local trimPart = part({
			Name = rt.name,
			Size = rt.size,
			Color = ROOF_TRIM,
			Material = Enum.Material.Metal,
		})
		trimPart.CFrame = rt.cf
		trimPart.Parent = model
	end

	-- White-framed windows on the side walls and back wall only.
	local function addWindow(fx, fz, rotY, sx)
		local frame = part({
			Name = "Window",
			Size = Vector3.new(sx, 3.6, 0.2),
			Color = WINDOW_WHITE,
			Material = Enum.Material.SmoothPlastic,
		})
		frame.CFrame = CFrame.new(cx + fx, 4.6, cz + fz) * CFrame.Angles(0, math.rad(rotY), 0)
		frame.CanCollide = false
		frame.Parent = model
	end

	-- Left wall (west): two windows
	addWindow(-halfW - 0.1, -5, 0, 4)
	addWindow(-halfW - 0.1, 5, 0, 4)
	-- Right wall (east): two windows
	addWindow(halfW + 0.1, -5, 0, 4)
	addWindow(halfW + 0.1, 5, 0, 4)
	-- Back wall: two windows
	if carpetDir == 1 then
		addWindow(-5, -halfW - 0.1, 90, 4)
		addWindow(5, -halfW - 0.1, 90, 4)
	else
		addWindow(-5, halfW + 0.1, 90, 4)
		addWindow(5, halfW + 0.1, 90, 4)
	end

	-- Base sign: a dark slab hovering above the front wall with the BillboardGui.
	local sign = part({
		Name = "BaseSign",
		Size = Vector3.new(16, 2.4, 0.6),
		Color = SIGN_DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	sign.CFrame = CFrame.new(cx, wallH + 3.6, cz + carpetDir * halfW)
	sign.CanCollide = false
	sign.Parent = model
	buildBaseNameplate(sign, "YOUR BASE", Color3.fromRGB(120, 255, 150))

	-- ProximityPrompt on the floor so a player sees "Claim Base" when close.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPrompt"
	prompt.ActionText = "Claim Base"
	prompt.ObjectText = "YOUR BASE"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 18
	prompt.Parent = floor

	-- Pedestal rows: 2 rows of 5, arranged inside the building.
	local facingDir = cz > 0 and -1 or 1 -- pedestals face the carpet
	for slot = 1, Config.Economy.maxSlots do
		local row = math.floor((slot - 1) / 5)
		local col = (slot - 1) % 5
		local px = cx + (col - 2) * PEDESTAL_SPACING
		local pz = cz + (row - 0.5) * 6 * facingDir + 1.5 * facingDir
		local pedestal = part({
			Name = "Pedestal" .. slot,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.8, 4.2, 4.2),
			Color = slot <= Config.Economy.startSlots and Color3.fromRGB(115, 120, 135) or Color3.fromRGB(58, 60, 70),
			Material = Enum.Material.Slate,
		})
		pedestal.CFrame = CFrame.new(px, 2.3, pz) * CFrame.Angles(0, 0, math.rad(90))
		pedestal:SetAttribute("Slot", slot)
		pedestal.Parent = model
	end

	-- Attributes the server reads.
	model:SetAttribute("Index", index)
	model:SetAttribute("CenterX", cx)
	model:SetAttribute("CenterZ", cz)
	model:SetAttribute("TopY", 0.4) -- floor height for tsunami teleport

	-- Phase 8a: neat grid interior with inner wall, counter, and neon stripe.
	buildBaseInterior(model, cx, cz, facingDir)

	model.Parent = workspace
	return model
end

-- ---------------------------------------------------------------------------
-- Golden statue: a simple trophy shape along the carpet.
-- ---------------------------------------------------------------------------

local function buildGoldStatue(x, z)
	local model = Instance.new("Model")
	model.Name = "GoldStatue"

	local base = part({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 4.5, 4.5),
		Color = STATUE_GOLD,
		Material = Enum.Material.Metal,
	})
	base.CFrame = CFrame.new(x, 0.6, z) * CFrame.Angles(0, 0, math.rad(90))
	base.Parent = model

	local pillar = part({
		Name = "Pillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5.2, 1.8, 1.8),
		Color = STATUE_GOLD,
		Material = Enum.Material.Metal,
	})
	pillar.CFrame = CFrame.new(x, 3.8, z) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = model

	local head = part({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 2.8, 2.8),
		Color = STATUE_GOLD,
		Material = Enum.Material.Metal,
	})
	head.CFrame = CFrame.new(x, 7.4, z)
	head.Parent = model

	model.Parent = workspace
	return model
end

-- ---------------------------------------------------------------------------
-- Small vault sign at the far end of the carpet.
-- ---------------------------------------------------------------------------

local function buildVaultSign()
	local z = CARPET_HALF + 4
	local board = part({
		Name = "VaultSign",
		Size = Vector3.new(12, 5, 0.8),
		Color = Color3.fromRGB(50, 48, 62),
		Material = Enum.Material.SmoothPlastic,
	})
	board.CFrame = CFrame.new(0, 4.5, z)
	board.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(300, 60)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.65)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Text = "BRAINROT VAULT"
	title.TextColor3 = Color3.fromRGB(255, 210, 90)
	title.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	title.TextStrokeTransparency = 0.25
	title.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromScale(0, 0.65)
	sub.Size = UDim2.fromScale(1, 0.35)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Text = "TYCOON"
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	sub.TextStrokeTransparency = 0.3
	sub.Parent = gui

	-- Two posts
	for _, sx in ipairs({ -5.5, 5.5 }) do
		local post = part({
			Name = "Post",
			Size = Vector3.new(1, 8, 1),
			Color = Color3.fromRGB(60, 56, 74),
			Material = Enum.Material.Metal,
		})
		post.CFrame = CFrame.new(sx, 4, z)
		post.Parent = workspace
	end
end

-- ---------------------------------------------------------------------------
-- Capsule spawn pad: glowing disc (public API — init.server uses it).
-- ---------------------------------------------------------------------------

function WorldBuilder.buildSpawnPad(index)
	-- 4 pads on each side of the carpet, alternating Z.
	local side = index % 2 == 1 and -1 or 1
	local row = math.floor((index - 1) / 2)   -- 0..3
	local z = -45 + row * 30
	local x = side * 32

	local pad = part({
		Name = "SpawnPad" .. index,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 8, 8),
		Color = Color3.fromRGB(210, 130, 255),
		Material = Enum.Material.Neon,
	})
	pad.CFrame = CFrame.new(x, 0.2, z) * CFrame.Angles(0, 0, math.rad(90))
	pad:SetAttribute("PadIndex", index)
	pad.Parent = workspace

	local ring = part({
		Name = "SpawnPadRing" .. index,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 10, 10),
		Color = Color3.fromRGB(160, 110, 230),
		Material = Enum.Material.Neon,
	})
	ring.CFrame = CFrame.new(x, 0.1, z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	return pad
end

-- ---------------------------------------------------------------------------
-- setBaseSign: update a claimed base's nameplate.  Called by init.server.
-- ---------------------------------------------------------------------------

function WorldBuilder.setBaseSign(baseModel, title, subtitle, color)
	local sign = baseModel:FindFirstChild("BaseSign")
	if sign == nil then
		return
	end
	local gui = sign:FindFirstChild("BaseSignGui")
	if gui == nil then
		return
	end
	local main = gui:FindFirstChild("Title")
	local sub = gui:FindFirstChild("Subtitle")
	if main then
		main.Text = title
		main.TextColor3 = color
	end
	if sub then
		sub.Text = subtitle
	end
end

-- ---------------------------------------------------------------------------
-- Build everything.  Returns { pads, bases }.
-- ---------------------------------------------------------------------------

function WorldBuilder.build()
	setupLighting()
	buildGround()

	-- 4 bases: row A at Z = -BASE_GAP/2, row B at Z = +BASE_GAP/2.
	-- Indices 1-4: front-left, front-right, back-right, back-left (clockwise).
	local basePositions = {
		{ x = -BASE_X, z = -BASE_GAP / 2, index = 1 },
		{ x =  BASE_X, z = -BASE_GAP / 2, index = 2 },
		{ x =  BASE_X, z =  BASE_GAP / 2, index = 3 },
		{ x = -BASE_X, z =  BASE_GAP / 2, index = 4 },
	}

	local bases = {}
	for _, bp in ipairs(basePositions) do
		bases[bp.index] = buildSingleBase(bp.x, bp.z, bp.index)
	end

	-- Golden statues off the carpet at x = -14 and x = +14.
	buildGoldStatue(-14, -28)
	buildGoldStatue(14, 0)
	buildGoldStatue(-14, 28)

	-- Small vault sign at the far end.
	buildVaultSign()

	-- Perimeter wall around all four map edges.
	buildPerimeterWall()

	-- Stone/brick paths from spawn area to each base entrance.
	buildStonePaths()

	-- Environment props: trees, rocks, lamps, benches, bushes.
	buildEnvironmentProps()

	-- Spawn pads.
	local pads = {}
	for i = 1, Config.Capsule.padCount do
		pads[i] = WorldBuilder.buildSpawnPad(i)
	end

	return { pads = pads, bases = bases }
end

return WorldBuilder