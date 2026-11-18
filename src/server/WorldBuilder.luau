-- WorldBuilder: Crypto Island — a futuristic island combining cryptocurrency
-- aesthetics with Roblox Brainrot style. Colorful, bright, blocky/geometric
-- architecture. NOT realistic, NOT dark, NOT a plain modern city.
--
-- Phase 11a: terrain, ocean, roads, central spawn plaza, base district.
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

local ISLAND_HALF = 150
local ROAD_WIDTH = 12
local SIDEWALK_WIDTH = 3
local SECONDARY_ROAD_WIDTH = 8
local BASE_SIZE = 26
local BASE_HALF = 13
local PEDESTAL_SPACING = 5.2
local PLAZA_HALF = 20

-- Base district: 2×2 grid north of spawn.
local BASE_ROW1_Z = 55 -- front row
local BASE_ROW2_Z = 85 -- back row
local BASE_COL1_X = -15 -- left column
local BASE_COL2_X = 15 -- right column

-- ---------------------------------------------------------------------------
-- Colour palette
-- ---------------------------------------------------------------------------

local GRASS_GREEN = Color3.fromRGB(98, 178, 72)
local GRASS_DARK = Color3.fromRGB(74, 142, 52)
local BITCOIN_GOLD = Color3.fromRGB(255, 200, 40)
local STATUE_GOLD = Color3.fromRGB(255, 210, 48)
local CYAN_BLUE = Color3.fromRGB(80, 200, 255)
local OCEAN_CYAN = Color3.fromRGB(60, 160, 220)
local WHITE = Color3.fromRGB(245, 245, 250)
local DARK_GREY = Color3.fromRGB(50, 52, 60)
local ROAD_GREY = Color3.fromRGB(55, 55, 65)
local SIDEWALK_GREY = Color3.fromRGB(120, 120, 130)
local YELLOW_LINE = Color3.fromRGB(255, 210, 40)
local BEACH_SAND = Color3.fromRGB(230, 210, 160)
local WALL_GREY = Color3.fromRGB(160, 165, 175)
local WINDOW_WHITE = Color3.fromRGB(245, 245, 250)
local INTERIOR_RED = Color3.fromRGB(188, 52, 52)
local SIGN_DARK = Color3.fromRGB(32, 36, 44)
local ROOF_DARK = Color3.fromRGB(42, 44, 54)
local ROOF_TRIM = Color3.fromRGB(255, 210, 48)
local DOOR_FRAME = Color3.fromRGB(255, 210, 48)
local CLIFF_GREY = Color3.fromRGB(120, 125, 130)
local LAMP_POLE = Color3.fromRGB(38, 40, 48)
local LAMP_GLOW = Color3.fromRGB(240, 215, 70)
local COIN_ORNAMENT = Color3.fromRGB(255, 195, 40)
local PLAZA_TILE_A = Color3.fromRGB(235, 235, 240)
local PLAZA_TILE_B = Color3.fromRGB(210, 210, 220)

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
-- Lighting: bright afternoon with shadows, sky and atmosphere. Safe.
-- ---------------------------------------------------------------------------

local function setupLighting()
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
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25

	-- Destroy all existing DirectionalLight children.
	while true do
		local old = Lighting:FindFirstChildWhichIsA("DirectionalLight")
		if not old then break end
		old:Destroy()
	end

	local ok, sunResult = pcall(function()
		local s = Instance.new("DirectionalLight")
		s.Name = "MainSun"
		s.Brightness = 2.5
		s.Shadows = true
		s.CFrame = CFrame.new(Vector3.new(80, 60, -30), Vector3.new(0, 0, 0))
		s.Parent = Lighting
		return s
	end)
	if not ok then
		warn("[WorldBuilder] DirectionalLight creation failed: " .. tostring(sunResult))
	end

	-- Remove any existing Sky.
	local oldSky = Lighting:FindFirstChildWhichIsA("Sky")
	if oldSky then oldSky:Destroy() end
	local okSky, skyResult = pcall(function()
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
		return sky
	end)
	if not okSky then
		warn("[WorldBuilder] Sky creation failed: " .. tostring(skyResult))
	end

	-- Remove any existing Atmosphere.
	local oldAtmo = Lighting:FindFirstChildWhichIsA("Atmosphere")
	if oldAtmo then oldAtmo:Destroy() end
	local okAtmo, atmoResult = pcall(function()
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "VaultAtmosphere"
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.25
		atmosphere.Color = Color3.fromRGB(199, 204, 214)
		atmosphere.Decay = Color3.fromRGB(106, 112, 125)
		atmosphere.Glare = 0.15
		atmosphere.Haze = 0.8
		atmosphere.Parent = Lighting
		return atmosphere
	end)
	if not okAtmo then
		warn("[WorldBuilder] Atmosphere creation failed: " .. tostring(atmoResult))
	end
end

-- ---------------------------------------------------------------------------
-- Terrain: multi-part island with grass, hills, beach, cliffs.
-- ---------------------------------------------------------------------------

local function buildTerrain()
	local terrainModel = Instance.new("Model")
	terrainModel.Name = "Terrain"

	-- Main grass base: large flat slab at Y=0.
	local grassBase = part({
		Name = "GrassBase",
		Size = Vector3.new(ISLAND_HALF * 2, 0.4, ISLAND_HALF * 2),
		Color = GRASS_GREEN,
		Material = Enum.Material.Grass,
	})
	grassBase.CFrame = CFrame.new(0, 0, 0)
	grassBase.Parent = terrainModel

	-- Varied grass patches for visual interest.
	for _, gx in ipairs({ -100, -50, 50, 100 }) do
		local patch = part({
			Name = "GrassPatch",
			Size = Vector3.new(22, 0.15, ISLAND_HALF * 2 - 8),
			Color = GRASS_DARK,
			Material = Enum.Material.Grass,
		})
		patch.CFrame = CFrame.new(gx, 0.08, 0)
		patch.Parent = terrainModel
	end

	-- Small hills: 3 elevated areas using rounded parts.
	local hills = {
		{ cx = -100, cz = -80, h = 6, r = 18 },
		{ cx = 90, cz = 100, h = 8, r = 22 },
		{ cx = -80, cz = 100, h = 4, r = 14 },
	}
	for _, hill in ipairs(hills) do
		local mound = part({
			Name = "Hill",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(hill.r * 2, hill.h * 2, hill.r * 2),
			Color = GRASS_GREEN,
			Material = Enum.Material.Grass,
		})
		mound.CFrame = CFrame.new(hill.cx, hill.h * 0.5, hill.cz)
		mound.Parent = terrainModel

		-- Darker cap for visual depth.
		local cap = part({
			Name = "HillCap",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(hill.r * 1.3, hill.h * 0.7, hill.r * 1.3),
			Color = GRASS_DARK,
			Material = Enum.Material.Grass,
		})
		cap.CFrame = CFrame.new(hill.cx, hill.h * 0.7, hill.cz)
		cap.Parent = terrainModel
	end

	-- Beach edges: sandy parts around the island perimeter, slightly lower than grass.
	local beachHalf = ISLAND_HALF - 4
	for _, edge in ipairs({
		{ name = "BeachN", cf = CFrame.new(0, -0.15, -beachHalf), size = Vector3.new(ISLAND_HALF * 2, 0.3, 10) },
		{ name = "BeachS", cf = CFrame.new(0, -0.15, beachHalf), size = Vector3.new(ISLAND_HALF * 2, 0.3, 10) },
		{ name = "BeachE", cf = CFrame.new(beachHalf, -0.15, 0), size = Vector3.new(10, 0.3, ISLAND_HALF * 2) },
		{ name = "BeachW", cf = CFrame.new(-beachHalf, -0.15, 0), size = Vector3.new(10, 0.3, ISLAND_HALF * 2) },
	}) do
		local beach = part({
			Name = edge.name,
			Size = edge.size,
			Color = BEACH_SAND,
			Material = Enum.Material.Sand,
		})
		beach.CFrame = edge.cf
		beach.Parent = terrainModel
	end

	-- Corner beach fills (rounded squares at the four corners).
	for _, corner in ipairs({
		{ x = -beachHalf, z = -beachHalf },
		{ x = beachHalf, z = -beachHalf },
		{ x = beachHalf, z = beachHalf },
		{ x = -beachHalf, z = beachHalf },
	}) do
		local cb = part({
			Name = "BeachCorner",
			Size = Vector3.new(14, 0.25, 14),
			Color = BEACH_SAND,
			Material = Enum.Material.Sand,
		})
		cb.CFrame = CFrame.new(corner.x, -0.15, corner.z)
		cb.Parent = terrainModel
	end

	-- Geometric cliffs: WedgePart slopes where island drops to ocean (N and E edges).
	local cliffPositions = {
		-- North cliff: wedge sloping down from z=-ISLAND_HALF toward z=-ISLAND_HALF-10
		{ cf = CFrame.new(0, 3, -ISLAND_HALF + 1) * CFrame.Angles(0, math.rad(180), 0), size = Vector3.new(ISLAND_HALF * 2 - 20, 6, 10) },
		-- East cliff: wedge sloping down from x=+ISLAND_HALF toward x=+ISLAND_HALF+10
		{ cf = CFrame.new(ISLAND_HALF - 1, 3, 40) * CFrame.Angles(0, math.rad(-90), 0), size = Vector3.new(60, 6, 10) },
	}
	for _, cp in ipairs(cliffPositions) do
		local cliff = part({
			Name = "Cliff",
			Shape = Enum.PartType.Wedge,
			Size = cp.size,
			Color = CLIFF_GREY,
			Material = Enum.Material.Slate,
		})
		cliff.CFrame = cp.cf
		cliff.Parent = terrainModel
	end

	-- Flat clearings: ensure the buildable zones (plaza, base district) are flat.
	-- Plaza area: clear any terrain protrusions at origin.
	local plazaClear = part({
		Name = "PlazaClearing",
		Size = Vector3.new(PLAZA_HALF * 2 + 10, 0.15, PLAZA_HALF * 2 + 10),
		Color = GRASS_GREEN,
		Material = Enum.Material.Grass,
	})
	plazaClear.CFrame = CFrame.new(0, 0.08, 0)
	plazaClear.Parent = terrainModel

	-- Base district clearing: flat area north of spawn for the 2×2 base grid.
	local baseDistrictClear = part({
		Name = "BaseDistrictClearing",
		Size = Vector3.new(50, 0.15, 60),
		Color = GRASS_GREEN,
		Material = Enum.Material.Grass,
	})
	baseDistrictClear.CFrame = CFrame.new(0, 0.08, 70)
	baseDistrictClear.Parent = terrainModel

	terrainModel.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Ocean boundary: large blue plane surrounding the island at Y=-2.
-- ---------------------------------------------------------------------------

local function buildOcean()
	local oceanModel = Instance.new("Model")
	oceanModel.Name = "Ocean"

	local water = part({
		Name = "OceanPlane",
		Size = Vector3.new(600, 0.2, 600),
		Color = OCEAN_CYAN,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.3,
	})
	water.CFrame = CFrame.new(0, -2, 0)
	water.CanCollide = false
	water.Parent = oceanModel

	-- Subtle wave ripple: a second semi-transparent layer slightly higher.
	local ripple = part({
		Name = "OceanRipple",
		Size = Vector3.new(580, 0.1, 580),
		Color = Color3.fromRGB(100, 200, 240),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.5,
	})
	ripple.CFrame = CFrame.new(0, -1.6, 0)
	ripple.CanCollide = false
	ripple.Parent = oceanModel

	oceanModel.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Roads: main N-S road, secondary roads, sidewalks, markings, street lamps.
-- ---------------------------------------------------------------------------

local function buildRoads()
	local roadsModel = Instance.new("Model")
	roadsModel.Name = "Roads"

	-- Main N-S road: x=0, z from -120 to +120, 12 studs wide.
	local mainRoad = part({
		Name = "MainRoad",
		Size = Vector3.new(ROAD_WIDTH, 0.22, 240),
		Color = ROAD_GREY,
		Material = Enum.Material.Asphalt,
	})
	mainRoad.CFrame = CFrame.new(0, 0.11, 0)
	mainRoad.Parent = roadsModel

	-- Main E-W road: z=0, x from -80 to +80, 12 studs wide.
	local mainRoadEW = part({
		Name = "MainRoadEW",
		Size = Vector3.new(160, 0.22, ROAD_WIDTH),
		Color = ROAD_GREY,
		Material = Enum.Material.Asphalt,
	})
	mainRoadEW.CFrame = CFrame.new(0, 0.11, 0)
	mainRoadEW.Parent = roadsModel

	-- Sidewalks: lighter grey strips on each side of main N-S road.
	for _, side in ipairs({ -ROAD_WIDTH / 2 - SIDEWALK_WIDTH / 2, ROAD_WIDTH / 2 + SIDEWALK_WIDTH / 2 }) do
		local sw = part({
			Name = "SidewalkNS",
			Size = Vector3.new(SIDEWALK_WIDTH, 0.24, 240),
			Color = SIDEWALK_GREY,
			Material = Enum.Material.Concrete,
		})
		sw.CFrame = CFrame.new(side, 0.12, 0)
		sw.Parent = roadsModel
	end

	-- Sidewalks on E-W road.
	for _, side in ipairs({ -ROAD_WIDTH / 2 - SIDEWALK_WIDTH / 2, ROAD_WIDTH / 2 + SIDEWALK_WIDTH / 2 }) do
		local sw = part({
			Name = "SidewalkEW",
			Size = Vector3.new(160, 0.24, SIDEWALK_WIDTH),
			Color = SIDEWALK_GREY,
			Material = Enum.Material.Concrete,
		})
		sw.CFrame = CFrame.new(0, 0.12, side)
		sw.Parent = roadsModel
	end

	-- Road markings: thin yellow centre line on main N-S road.
	for _, segZ in ipairs({ -80, -40, 0, 40, 80 }) do
		local line = part({
			Name = "RoadLineNS",
			Size = Vector3.new(0.4, 0.06, 30),
			Color = YELLOW_LINE,
			Material = Enum.Material.SmoothPlastic,
		})
		line.CFrame = CFrame.new(0, 0.28, segZ)
		line.CanCollide = false
		line.Parent = roadsModel
	end

	-- Road markings on E-W road.
	for _, segX in ipairs({ -60, -20, 20, 60 }) do
		local line = part({
			Name = "RoadLineEW",
			Size = Vector3.new(30, 0.06, 0.4),
			Color = YELLOW_LINE,
			Material = Enum.Material.SmoothPlastic,
		})
		line.CFrame = CFrame.new(segX, 0.28, 0)
		line.CanCollide = false
		line.Parent = roadsModel
	end

	-- Secondary E-W roads in the base district.
	local secondaryRoads = {
		{ z = BASE_ROW1_Z, name = "BaseRoadFront" },
		{ z = BASE_ROW2_Z, name = "BaseRoadBack" },
	}
	for _, sr in ipairs(secondaryRoads) do
		local secRoad = part({
			Name = sr.name,
			Size = Vector3.new(50, 0.2, SECONDARY_ROAD_WIDTH),
			Color = ROAD_GREY,
			Material = Enum.Material.Asphalt,
		})
		secRoad.CFrame = CFrame.new(0, 0.1, sr.z)
		secRoad.Parent = roadsModel
	end

	-- Secondary N-S roads connecting front and back base rows.
	local secNS = part({
		Name = "BaseRoadNS",
		Size = Vector3.new(SECONDARY_ROAD_WIDTH, 0.2, BASE_ROW2_Z - BASE_ROW1_Z + SECONDARY_ROAD_WIDTH),
		Color = ROAD_GREY,
		Material = Enum.Material.Asphalt,
	})
	secNS.CFrame = CFrame.new(BASE_COL1_X - BASE_HALF - 4, 0.1, (BASE_ROW1_Z + BASE_ROW2_Z) / 2)
	secNS.Parent = roadsModel

	local secNS2 = part({
		Name = "BaseRoadNS2",
		Size = Vector3.new(SECONDARY_ROAD_WIDTH, 0.2, BASE_ROW2_Z - BASE_ROW1_Z + SECONDARY_ROAD_WIDTH),
		Color = ROAD_GREY,
		Material = Enum.Material.Asphalt,
	})
	secNS2.CFrame = CFrame.new(BASE_COL2_X + BASE_HALF + 4, 0.1, (BASE_ROW1_Z + BASE_ROW2_Z) / 2)
	secNS2.Parent = roadsModel

	-- Street lamps along main N-S road: cylinder pole + neon ball head, every 20 studs.
	for _, z in ipairs({ -100, -80, -60, -40, -20, 20, 40, 60, 80, 100 }) do
		for _, sx in ipairs({ ROAD_WIDTH / 2 + SIDEWALK_WIDTH + 0.5, -(ROAD_WIDTH / 2 + SIDEWALK_WIDTH + 0.5) }) do
			local lampModel = Instance.new("Model")
			lampModel.Name = "StreetLamp"

			local poleH = 9
			local pole = part({
				Name = "Pole",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(poleH, 0.35, 0.35),
				Color = LAMP_POLE,
				Material = Enum.Material.Metal,
			})
			pole.CFrame = CFrame.new(sx, poleH / 2 + 0.2, z) * CFrame.Angles(0, 0, math.rad(90))
			pole.Parent = lampModel

			local head = part({
				Name = "LampHead",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.6, 1.6, 1.6),
				Color = LAMP_GLOW,
				Material = Enum.Material.Neon,
			})
			head.CFrame = CFrame.new(sx, poleH + 1.0, z)
			head.Parent = lampModel

			local pointLight = Instance.new("PointLight")
			pointLight.Color = LAMP_GLOW
			pointLight.Brightness = 3.2
			pointLight.Range = 24
			pointLight.Parent = head

			lampModel.Parent = roadsModel
		end
	end

	roadsModel.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Central Spawn Plaza: large paved area at origin with Bitcoin landmark.
-- ---------------------------------------------------------------------------

local function buildSpawnPlaza()
	local plazaModel = Instance.new("Model")
	plazaModel.Name = "SpawnPlaza"

	-- Plaza floor: alternating tile pattern (checkerboard of Box parts).
	local tileCount = 4
	local tileSize = PLAZA_HALF * 2 / tileCount
	for ix = 0, tileCount - 1 do
		for iz = 0, tileCount - 1 do
			local isLight = (ix + iz) % 2 == 0
			local tile = part({
				Name = "PlazaTile",
				Size = Vector3.new(tileSize - 0.2, 0.18, tileSize - 0.2),
				Color = isLight and PLAZA_TILE_A or PLAZA_TILE_B,
				Material = Enum.Material.SmoothPlastic,
			})
			local tx = -PLAZA_HALF + tileSize / 2 + ix * tileSize
			local tz = -PLAZA_HALF + tileSize / 2 + iz * tileSize
			tile.CFrame = CFrame.new(tx, 0.2, tz)
			tile.Parent = plazaModel
		end
	end

	-- Plaza border trim: gold edge around the plaza perimeter.
	for _, edge in ipairs({
		{ name = "PlazaBorderN", cf = CFrame.new(0, 0.15, -PLAZA_HALF), size = Vector3.new(PLAZA_HALF * 2, 0.16, 0.6) },
		{ name = "PlazaBorderS", cf = CFrame.new(0, 0.15, PLAZA_HALF), size = Vector3.new(PLAZA_HALF * 2, 0.16, 0.6) },
		{ name = "PlazaBorderE", cf = CFrame.new(PLAZA_HALF, 0.15, 0), size = Vector3.new(0.6, 0.16, PLAZA_HALF * 2) },
		{ name = "PlazaBorderW", cf = CFrame.new(-PLAZA_HALF, 0.15, 0), size = Vector3.new(0.6, 0.16, PLAZA_HALF * 2) },
	}) do
		local border = part({
			Name = edge.name,
			Size = edge.size,
			Color = BITCOIN_GOLD,
			Material = Enum.Material.Metal,
		})
		border.CFrame = edge.cf
		border.Parent = plazaModel
	end

	-- Bitcoin Statue: large gold Cylinder with ₿ mark, standing in the plaza centre.
	local statueBase = part({
		Name = "StatueBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.5, 6, 6),
		Color = STATUE_GOLD,
		Material = Enum.Material.Metal,
	})
	statueBase.CFrame = CFrame.new(0, 0.75, -8) * CFrame.Angles(0, 0, math.rad(90))
	statueBase.Parent = plazaModel

	local statuePillar = part({
		Name = "StatuePillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(12, 4, 4),
		Color = STATUE_GOLD,
		Material = Enum.Material.Metal,
	})
	statuePillar.CFrame = CFrame.new(0, 7.5, -8) * CFrame.Angles(0, 0, math.rad(90))
	statuePillar.Parent = plazaModel

	-- ₿ symbol as a large flat box on top of the pillar.
	local bitcoinSymbol = part({
		Name = "BitcoinSymbol",
		Size = Vector3.new(3.5, 3.5, 0.4),
		Color = STATUE_GOLD,
		Material = Enum.Material.Metal,
	})
	bitcoinSymbol.CFrame = CFrame.new(0, 14, -8)
	bitcoinSymbol.Parent = plazaModel

	-- BillboardGui for the ₿ symbol text.
	local symbolGui = Instance.new("BillboardGui")
	symbolGui.Size = UDim2.fromOffset(200, 80)
	symbolGui.AlwaysOnTop = true
	symbolGui.MaxDistance = 200
	symbolGui.Parent = bitcoinSymbol

	local symbolLabel = Instance.new("TextLabel")
	symbolLabel.Size = UDim2.fromScale(1, 1)
	symbolLabel.BackgroundTransparency = 1
	symbolLabel.Font = Enum.Font.GothamBold
	symbolLabel.TextScaled = true
	symbolLabel.Text = "₿"
	symbolLabel.TextColor3 = BITCOIN_GOLD
	symbolLabel.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	symbolLabel.TextStrokeTransparency = 0.3
	symbolLabel.Parent = symbolGui

	-- Glowing ring around the statue base.
	local glowRing = part({
		Name = "StatueGlowRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 7, 7),
		Color = CYAN_BLUE,
		Material = Enum.Material.Neon,
	})
	glowRing.CFrame = CFrame.new(0, 0.3, -8) * CFrame.Angles(0, 0, math.rad(90))
	glowRing.CanCollide = false
	glowRing.Parent = plazaModel

	-- Leaderboard board: tall dark panel with BillboardGui.
	local leaderboardPanel = part({
		Name = "LeaderboardSign",
		Size = Vector3.new(10, 8, 0.6),
		Color = SIGN_DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	leaderboardPanel.CFrame = CFrame.new(10, 4.4, -PLAZA_HALF + 2)
	leaderboardPanel.CanCollide = false
	leaderboardPanel.Parent = plazaModel

	local leaderGui = Instance.new("BillboardGui")
	leaderGui.Size = UDim2.fromOffset(260, 60)
	leaderGui.AlwaysOnTop = true
	leaderGui.MaxDistance = 200
	leaderGui.Parent = leaderboardPanel

	local leaderTitle = Instance.new("TextLabel")
	leaderTitle.Size = UDim2.fromScale(1, 0.65)
	leaderTitle.BackgroundTransparency = 1
	leaderTitle.Font = Enum.Font.GothamBold
	leaderTitle.TextScaled = true
	leaderTitle.Text = "🏆 LEADERBOARD"
	leaderTitle.TextColor3 = BITCOIN_GOLD
	leaderTitle.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	leaderTitle.TextStrokeTransparency = 0.25
	leaderTitle.Parent = leaderGui

	-- Info board: smaller panel with instructions.
	local infoPanel = part({
		Name = "InfoBoard",
		Size = Vector3.new(8, 5, 0.6),
		Color = SIGN_DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	infoPanel.CFrame = CFrame.new(-10, 3.0, -PLAZA_HALF + 2)
	infoPanel.CanCollide = false
	infoPanel.Parent = plazaModel

	local infoGui = Instance.new("BillboardGui")
	infoGui.Size = UDim2.fromOffset(240, 50)
	infoGui.AlwaysOnTop = true
	infoGui.MaxDistance = 200
	infoGui.Parent = infoPanel

	local infoTitle = Instance.new("TextLabel")
	infoTitle.Size = UDim2.fromScale(1, 1)
	infoTitle.BackgroundTransparency = 1
	infoTitle.Font = Enum.Font.GothamBold
	infoTitle.TextScaled = true
	infoTitle.Text = "📦 COLLECT · 💰 EARN · 🏗️ BUILD"
	infoTitle.TextColor3 = Color3.fromRGB(200, 220, 255)
	infoTitle.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	infoTitle.TextStrokeTransparency = 0.3
	infoTitle.Parent = infoGui

	-- Decorative coin ornaments around the plaza edge: small gold Cylinders.
	local coinRadius = PLAZA_HALF + 1
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		local cx = math.cos(angle) * coinRadius
		local cz = math.sin(angle) * coinRadius

		-- Skip coins in the road paths (N/S/E/W at angles 0°, 90°, 180°, 270°).
		local absAngle = (i * 45) % 180
		if math.abs(absAngle - 90) < 5 then
			-- E/W road — skip but still place smaller coins further out.
		end

		local coin = part({
			Name = "CoinOrnament",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 3, 3),
			Color = COIN_ORNAMENT,
			Material = Enum.Material.Metal,
		})
		coin.CFrame = CFrame.new(cx, 0.3, cz) * CFrame.Angles(0, 0, math.rad(90))
		coin.CanCollide = false
		coin.Parent = plazaModel
	end

	-- 4 radiating path markers: gold strips pointing N/S/E/W.
	local paths = {
		{ name = "PathN", cf = CFrame.new(0, 0.13, -PLAZA_HALF - 2), size = Vector3.new(ROAD_WIDTH, 0.1, 4) },
		{ name = "PathS", cf = CFrame.new(0, 0.13, PLAZA_HALF + 2), size = Vector3.new(ROAD_WIDTH, 0.1, 4) },
		{ name = "PathE", cf = CFrame.new(PLAZA_HALF + 2, 0.13, 0), size = Vector3.new(4, 0.1, ROAD_WIDTH) },
		{ name = "PathW", cf = CFrame.new(-PLAZA_HALF - 2, 0.13, 0), size = Vector3.new(4, 0.1, ROAD_WIDTH) },
	}
	for _, p in ipairs(paths) do
		local marker = part({
			Name = p.name,
			Size = p.size,
			Color = BITCOIN_GOLD,
			Material = Enum.Material.Metal,
		})
		marker.CFrame = p.cf
		marker.Parent = plazaModel
	end

	plazaModel.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Single base building: structure for one player's base.
-- ---------------------------------------------------------------------------

local function buildSingleBase(cx, cz, index)
	local model = Instance.new("Model")
	model.Name = "Base" .. index

	local wallH = 10
	local halfW = BASE_HALF

	-- Red interior floor — also the "Island" part the server hooks .Touched on.
	local floor = part({
		Name = "Island",
		Size = Vector3.new(halfW * 2, 0.4, halfW * 2),
		Color = INTERIOR_RED,
		Material = Enum.Material.SmoothPlastic,
	})
	floor.CFrame = CFrame.new(cx, 0.2, cz)
	floor.Parent = model

	-- All bases have their doorway facing south (toward spawn / the road).
	-- South wall (WallS at cz + halfW): doorway in the middle 6 studs.
	local doorHalf = 3.0

	-- Left segment of south wall.
	local segL = part({
		Name = "WallS_L",
		Size = Vector3.new(halfW - doorHalf, wallH, 0.6),
		Color = WALL_GREY,
		Material = Enum.Material.Concrete,
	})
	segL.CFrame = CFrame.new(cx - (halfW + doorHalf) / 2, wallH / 2 + 0.2, cz + halfW)
	segL.Parent = model

	-- Right segment of south wall.
	local segR = part({
		Name = "WallS_R",
		Size = Vector3.new(halfW - doorHalf, wallH, 0.6),
		Color = WALL_GREY,
		Material = Enum.Material.Concrete,
	})
	segR.CFrame = CFrame.new(cx + (halfW + doorHalf) / 2, wallH / 2 + 0.2, cz + halfW)
	segR.Parent = model

	-- Doorframe: gold pillars on each side of the opening and a threshold.
	local doorZ = cz + halfW
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

	-- Threshold: low gold block across the doorway bottom.
	local threshold = part({
		Name = "Threshold",
		Size = Vector3.new(doorHalf * 2 + 0.8, 0.4, 1.0),
		Color = DOOR_FRAME,
		Material = Enum.Material.Metal,
	})
	threshold.CFrame = CFrame.new(cx, 0.4, doorZ)
	threshold.Parent = model

	-- Solid walls: west, east, north.
	local solidWalls = {
		{ name = "WallW", size = Vector3.new(0.6, wallH, halfW * 2), cf = CFrame.new(cx - halfW, wallH / 2 + 0.2, cz) },
		{ name = "WallE", size = Vector3.new(0.6, wallH, halfW * 2), cf = CFrame.new(cx + halfW, wallH / 2 + 0.2, cz) },
		{ name = "WallN", size = Vector3.new(halfW * 2 + 1.2, wallH, 0.6), cf = CFrame.new(cx, wallH / 2 + 0.2, cz - halfW) },
	}
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

	-- Roof slab: dark colour with gold accent trim.
	local roofSlab = part({
		Name = "Roof",
		Size = Vector3.new(halfW * 2 + 1.8, 1.2, halfW * 2 + 1.8),
		Color = ROOF_DARK,
		Material = Enum.Material.Concrete,
	})
	roofSlab.CFrame = CFrame.new(cx, wallH + 1.2, cz)
	roofSlab.Parent = model

	-- Gold roof trim.
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

	-- White-framed windows on the side walls (west, east) and back wall (north).
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

	-- West wall: two windows.
	addWindow(-halfW - 0.1, -5, 0, 4)
	addWindow(-halfW - 0.1, 5, 0, 4)
	-- East wall: two windows.
	addWindow(halfW + 0.1, -5, 0, 4)
	addWindow(halfW + 0.1, 5, 0, 4)
	-- North (back) wall: two windows.
	addWindow(-5, -halfW - 0.1, 90, 4)
	addWindow(5, -halfW - 0.1, 90, 4)

	-- Base sign: dark slab above the front (south) wall with BillboardGui.
	local sign = part({
		Name = "BaseSign",
		Size = Vector3.new(16, 2.4, 0.6),
		Color = SIGN_DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	sign.CFrame = CFrame.new(cx, wallH + 3.6, cz + halfW)
	sign.CanCollide = false
	sign.Parent = model
	buildBaseNameplate(sign, "YOUR BASE", Color3.fromRGB(120, 255, 150))

	-- ProximityPrompt on the floor for "Claim Base".
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPrompt"
	prompt.ActionText = "Claim Base"
	prompt.ObjectText = "YOUR BASE"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 18
	prompt.Parent = floor

	-- Pedestal rows: 2 rows of 5 inside the building, facing south.
	for slot = 1, Config.Economy.maxSlots do
		local row = math.floor((slot - 1) / 5)
		local col = (slot - 1) % 5
		local px = cx + (col - 2) * PEDESTAL_SPACING
		local pz = cz + (row - 0.5) * 6 + 3
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

	model.Parent = workspace
	return model
end

-- ---------------------------------------------------------------------------
-- Player Base District: 4 base plots in a 2×2 grid north of spawn.
-- ---------------------------------------------------------------------------

local function buildBaseDistrict()
	local districtModel = Instance.new("Model")
	districtModel.Name = "BaseDistrict"

	-- 2×2 grid layout (read row-major from south):
	--   Base 1 (front-left):  x=-15, z=55
	--   Base 2 (front-right): x=+15, z=55
	--   Base 3 (back-right):  x=+15, z=85
	--   Base 4 (back-left):   x=-15, z=85
	local basePositions = {
		{ x = BASE_COL1_X, z = BASE_ROW1_Z, index = 1 },
		{ x = BASE_COL2_X, z = BASE_ROW1_Z, index = 2 },
		{ x = BASE_COL2_X, z = BASE_ROW2_Z, index = 3 },
		{ x = BASE_COL1_X, z = BASE_ROW2_Z, index = 4 },
	}

	local bases = {}
	for _, bp in ipairs(basePositions) do
		bases[bp.index] = buildSingleBase(bp.x, bp.z, bp.index)
	end

	-- Connecting paths between plots: stone walkways.
	local function addPath(sx, sz, ex, ez)
		local dx = ex - sx
		local dz = ez - sz
		local dist = math.sqrt(dx * dx + dz * dz)
		local steps = math.max(2, math.floor(dist / 4))
		for i = 1, steps do
			local t = i / (steps + 1)
			local px = sx + dx * t
			local pz = sz + dz * t
			local stone = part({
				Name = "PathStone",
				Size = Vector3.new(2.4, 0.1, 2.4),
				Color = SIDEWALK_GREY,
				Material = Enum.Material.Slate,
			})
			stone.CFrame = CFrame.new(px, 0.18, pz)
			stone.Parent = districtModel
		end
	end

	-- Paths from main road to each base doorway (south side of each base).
	for _, bp in ipairs(basePositions) do
		local doorX = bp.x
		local doorZ = bp.z + BASE_HALF
		local roadX = 0
		local roadZ = bp.z
		addPath(roadX, roadZ, doorX, doorZ)
	end

	-- Paths between front and back row bases (north-south connectors).
	addPath(BASE_COL1_X, BASE_ROW1_Z, BASE_COL1_X, BASE_ROW2_Z)
	addPath(BASE_COL2_X, BASE_ROW1_Z, BASE_COL2_X, BASE_ROW2_Z)

	districtModel.Parent = workspace
	return bases
end

-- ---------------------------------------------------------------------------
-- Capsule spawn pad: glowing disc along the main road.
-- ---------------------------------------------------------------------------

function WorldBuilder.buildSpawnPad(index)
	-- 8 pads, 4 on each side of the main N-S road, spread along Z.
	local side = index % 2 == 1 and -1 or 1
	local row = math.floor((index - 1) / 2) -- 0..3
	local z = -60 + row * 40
	local x = side * (ROAD_WIDTH / 2 + SIDEWALK_WIDTH + 6)

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
-- setBaseSign: update a claimed base's nameplate. Called by init.server.
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
-- Build everything. Returns { pads, bases }.
-- ---------------------------------------------------------------------------

function WorldBuilder.build()
	local function safeStep(name, fn)
		local ok, err = pcall(fn)
		if not ok then
			warn("[WorldBuilder] step failed (" .. name .. "): " .. tostring(err))
		end
	end

	-- Destroy old template Baseplate if present.
	local template = workspace:FindFirstChild("Baseplate")
	if template then template:Destroy() end

	safeStep("setupLighting", setupLighting)
	safeStep("buildTerrain", buildTerrain)
	safeStep("buildOcean", buildOcean)
	safeStep("buildRoads", buildRoads)
	safeStep("buildSpawnPlaza", buildSpawnPlaza)

	local bases = buildBaseDistrict()

	-- Spawn pads.
	local pads = {}
	for i = 1, Config.Capsule.padCount do
		pads[i] = WorldBuilder.buildSpawnPad(i)
	end

	return { pads = pads, bases = bases }
end

return WorldBuilder