-- WorldBuilder: clean tycoon layout matching the operator's reference.
-- Green stud baseplate, wide red carpet down the center, 4 base buildings
-- (2 per side) with grey walls, white-framed windows, red interiors and
-- "YOUR BASE" BillboardGuis. Golden statues along the carpet, capsule
-- pads on both sides, a small vault sign at the far end. No floating
-- text labels — just the base nameplates and the end sign.
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
local BASE_GAP = 46  -- Z-distance between front-row and back-row bases
local BASE_X = 22    -- absolute X of each base's center
local PEDESTAL_SPACING = 5.2

-- Colors
local GRASS_GREEN = Color3.fromRGB(98, 178, 72)
local CARPET_RED = Color3.fromRGB(195, 48, 48)
local WALL_GREY = Color3.fromRGB(160, 165, 175)
local WINDOW_WHITE = Color3.fromRGB(245, 245, 250)
local INTERIOR_RED = Color3.fromRGB(188, 52, 52)
local STATUE_GOLD = Color3.fromRGB(255, 210, 48)
local SIGN_DARK = Color3.fromRGB(32, 36, 44)

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
	gui.Size = UDim2.fromOffset(220, 56)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.Parent = parent

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
	sub.Parent = gui

	return gui
end

-- ---------------------------------------------------------------------------
-- Lighting: bright afternoon
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

	if Lighting:FindFirstChildOfClass("Sky") == nil then
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
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere == nil then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.28
	atmosphere.Color = Color3.fromRGB(199, 204, 214)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 0.8
end

-- ---------------------------------------------------------------------------
-- Green stud baseplate + red carpet
-- ---------------------------------------------------------------------------

local function buildGround()
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
-- One base building: grey-walled room with white-framed windows, red interior,
-- "YOUR BASE" BillboardGui, ProximityPrompt, and rows of pedestals.
-- ---------------------------------------------------------------------------

local function buildSingleBase(cx, cz, index)
	local model = Instance.new("Model")
	model.Name = "Base" .. index

	local wallH = 8
	local halfW = 8.5 -- half-width of the building

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
	local wallDefs = {
		{ name = "WallN", size = Vector3.new(halfW * 2 + 1.2, wallH, 0.6), cf = CFrame.new(cx, wallH / 2 + 0.2, cz - halfW) },
		{ name = "WallS", size = Vector3.new(halfW * 2 + 1.2, wallH, 0.6), cf = CFrame.new(cx, wallH / 2 + 0.2, cz + halfW) },
		{ name = "WallE", size = Vector3.new(0.6, wallH, halfW * 2), cf = CFrame.new(cx + halfW, wallH / 2 + 0.2, cz) },
		{ name = "WallW", size = Vector3.new(0.6, wallH, halfW * 2), cf = CFrame.new(cx - halfW, wallH / 2 + 0.2, cz) },
	}
	for _, w in ipairs(wallDefs) do
		local wall = part({
			Name = w.name,
			Size = w.size,
			Color = WALL_GREY,
			Material = Enum.Material.Concrete,
		})
		wall.CFrame = w.cf
		wall.Parent = model
	end

	-- White-framed windows on each wall: thin white rectangles on the outside face.
	-- Two windows per wall, skipping the front (carpet-facing) wall so the
	-- entrance is clear.
	local function addWindow(wallName, fx, fz, rotY, sx, sz, windowCX, windowCZ)
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
	addWindow("WallW", -halfW - 0.1, -3.3, 0, 3, 3.6, 0, 0)
	addWindow("WallW", -halfW - 0.1, 3.3, 0, 3, 3.6, 0, 0)
	-- Right wall (east): two windows
	addWindow("WallE", halfW + 0.1, -3.3, 0, 3, 3.6, 0, 0)
	addWindow("WallE", halfW + 0.1, 3.3, 0, 3, 3.6, 0, 0)
	-- Back wall (south, away from carpet): two windows
	addWindow("WallS", -3.3, halfW + 0.1, 90, 3, 3.6, 0, 0)
	addWindow("WallS", 3.3, halfW + 0.1, 90, 3, 3.6, 0, 0)

	-- Base sign: a dark slab hovering above the front wall with the BillboardGui.
	local sign = part({
		Name = "BaseSign",
		Size = Vector3.new(12, 2.4, 0.6),
		Color = SIGN_DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	-- Front wall is "WallN" at cz - halfW.  Lift the sign above it.
	sign.CFrame = CFrame.new(cx, wallH + 1.8, cz - halfW)
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
		Color = Color3.fromRGB(70, 58, 85),
		Material = Enum.Material.Slate,
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

	-- Golden statues along the carpet.
	buildGoldStatue(0, -28)
	buildGoldStatue(0, 0)
	buildGoldStatue(0, 28)

	-- Small vault sign at the far end.
	buildVaultSign()

	-- Spawn pads.
	local pads = {}
	for i = 1, Config.Capsule.padCount do
		pads[i] = WorldBuilder.buildSpawnPad(i)
	end

	return { pads = pads, bases = bases }
end

return WorldBuilder