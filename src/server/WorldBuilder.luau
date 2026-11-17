-- WorldBuilder: constructs the whole 3D arena at server start — bright daytime
-- lighting and sky, the grass ground with sand paths, the four player bases
-- (raised SAFE ZONE islands with pedestals and stairs), the spawn court, the
-- eight capsule pads, the central plaza with mascot and signs, the museum
-- showcase of all twelve brainrots, and the neon-trimmed perimeter walls.
-- Everything is anchored plain parts, so the place stays cheap and the whole
-- map lives in code next to the scripts that use it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)

local BrainrotModels = require(script.Parent.BrainrotModels)

local WorldBuilder = {}

local ARENA_HALF = 110 -- play area is a 220-stud square inside the walls
local BASE_RADIUS = 70 -- distance from plaza center to each base
local BASE_TOP = 16 -- top of a base island; the tsunami stays below it
local PEDESTAL_SPACING = 6.2

local GRASS = Color3.fromRGB(115, 195, 100)
local SAND = Color3.fromRGB(238, 216, 150)
local ISLAND = Color3.fromRGB(232, 234, 240)
local NEON_TRIM = Color3.fromRGB(80, 255, 170)

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

local function label(parent, title, subtitle, color, studsOffset)
	local anchor = part({
		Name = "LabelAnchor",
		Size = Vector3.new(0.05, 0.05, 0.05),
		Transparency = 1,
		CanCollide = false,
	})
	anchor.CFrame = parent.CFrame * CFrame.new(0, (parent.Size.Y / 2) + 0.2, 0)
	anchor.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 60)
	gui.StudsOffset = studsOffset or Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	gui.Parent = anchor

	local main = Instance.new("TextLabel")
	main.Size = UDim2.fromScale(1, 0.55)
	main.BackgroundTransparency = 1
	main.Font = Enum.Font.GothamBold
	main.TextScaled = true
	main.Text = title
	main.TextColor3 = color or Color3.new(1, 1, 1)
	main.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	main.TextStrokeTransparency = 0.25
	main.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromScale(0, 0.55)
	sub.Size = UDim2.fromScale(1, 0.45)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Text = subtitle or ""
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	sub.TextStrokeTransparency = 0.3
	sub.Parent = gui

	return gui
end

-- ---------------------------------------------------------------------------
-- Lighting: bright afternoon so every screenshot is clearly readable.
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

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain and terrain:FindFirstChild("Clouds") == nil then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.4
		clouds.Density = 0.45
		clouds.Parent = terrain
	end
end

-- ---------------------------------------------------------------------------
-- Ground plane and the sand paths that link plaza to every base
-- ---------------------------------------------------------------------------

local function buildGround()
	local grass = part({
		Name = "Ground",
		Size = Vector3.new(ARENA_HALF * 2 + 4, 0.4, ARENA_HALF * 2 + 4),
		Color = GRASS,
		Material = Enum.Material.Grass,
	})
	grass.CFrame = CFrame.new(0, -0.15, 0) -- top sits at 0.05, above the baseplate
	grass.Parent = workspace

	-- One sand path from the plaza to each base's staircase.
	for index = 1, 4 do
		local angle = math.rad((index - 1) * 90 - 90)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local mid = dir * 31
		local path = part({
			Name = "Path" .. index,
			Size = Vector3.new(12, 0.18, 18),
			Color = SAND,
			Material = Enum.Material.Sand,
		})
		path.CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.1, 0), mid + dir * 45 + Vector3.new(0, 0.1, 0))
		path.Parent = workspace
	end
end

-- ---------------------------------------------------------------------------
-- Spawn court: a decorated platform with the SpawnLocation moved onto it
-- (the default project spawns players in the plaza fountain otherwise).
-- ---------------------------------------------------------------------------

local function buildSpawnArea()
	local center = Vector3.new(0, 0, 30)

	local court = part({
		Name = "SpawnCourt",
		Size = Vector3.new(22, 0.6, 18),
		Color = Color3.fromRGB(70, 150, 230),
		Material = Enum.Material.Concrete,
	})
	court.CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0))
	court.Parent = workspace

	local rim = part({
		Name = "SpawnRim",
		Size = Vector3.new(23.4, 0.4, 19.4),
		Color = Color3.fromRGB(80, 230, 255),
		Material = Enum.Material.Neon,
	})
	rim.CFrame = CFrame.new(center + Vector3.new(0, 0.4, 0))
	rim.CanCollide = false
	rim.Parent = workspace

	local spawn = workspace:FindFirstChild("SpawnLocation")
	if spawn then
		spawn.Anchored = true
		spawn.Size = Vector3.new(16, 1.2, 12)
		spawn.Color = Color3.fromRGB(240, 245, 255)
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.Position = center + Vector3.new(0, 1.2, 0) -- bottom rests on the court
	end

	local signAnchor = part({
		Name = "SpawnSign",
		Size = Vector3.new(12, 2.6, 0.6),
		Color = Color3.fromRGB(8, 35, 60),
		Material = Enum.Material.SmoothPlastic,
	})
	signAnchor.CFrame = CFrame.new(center + Vector3.new(0, 7, 0))
	signAnchor.CanCollide = false
	signAnchor.Parent = workspace
	label(signAnchor, "SPAWN AREA", "grab a capsule in the plaza!", Color3.fromRGB(140, 235, 255))
end

-- A text sign standing on the plaza, so the loop is readable in a screenshot.
-- The text is put on both faces so it reads correctly from either side.
local function buildSign(position, rotationY, title, lines)
	local board = part({
		Name = "Sign",
		Size = Vector3.new(14, 8, 1),
		Color = Color3.fromRGB(70, 52, 40),
		Material = Enum.Material.WoodPlanks,
	})
	board.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotationY), 0)
	board.Parent = workspace

	local function addFaceText(faceNormal)
		local face = Instance.new("SurfaceGui")
		face.Face = faceNormal
		face.CanvasSize = Vector2.new(700, 400)
		face.Parent = board

		local titleBox = Instance.new("TextLabel")
		titleBox.Size = UDim2.fromScale(1, 0.28)
		titleBox.BackgroundTransparency = 1
		titleBox.Font = Enum.Font.GothamBold
		titleBox.TextScaled = true
		titleBox.TextColor3 = Color3.fromRGB(255, 225, 120)
		titleBox.Text = title
		titleBox.Parent = face

		local body = Instance.new("TextLabel")
		body.Position = UDim2.fromScale(0, 0.3)
		body.Size = UDim2.fromScale(1, 0.7)
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.GothamBold
		body.TextScaled = true
		body.TextColor3 = Color3.new(1, 1, 1)
		body.Text = table.concat(lines, "\n")
		body.Parent = face
	end
	addFaceText(Enum.NormalId.Front)
	addFaceText(Enum.NormalId.Back)

	local post = part({
		Name = "SignPost",
		Size = Vector3.new(1.2, 6, 1.2),
		Color = Color3.fromRGB(90, 68, 50),
		Material = Enum.Material.Wood,
	})
	post.CFrame = CFrame.new(position - Vector3.new(0, 7, 0)) * CFrame.Angles(0, math.rad(rotationY), 0)
	post.Parent = workspace
end

-- One player base: a raised island, a ring of pedestals (locked ones dimmed),
-- stairs up from the plaza, and signs that flip to the owner's name.
function WorldBuilder.buildBase(index)
	local angle = math.rad((index - 1) * 90 - 90) -- bases at north/east/south/west
	local center = Vector3.new(math.cos(angle) * BASE_RADIUS, 0, math.sin(angle) * BASE_RADIUS)

	local base = Instance.new("Model")
	base.Name = "Base" .. index

	local island = part({
		Name = "Island",
		Size = Vector3.new(38, BASE_TOP, 38),
		Color = ISLAND,
		Material = Enum.Material.Concrete,
	})
	island.CFrame = CFrame.new(center + Vector3.new(0, BASE_TOP / 2, 0))
	island.Parent = base

	-- Glowing green floor inlay: "safe zone" colour, readable from the plaza.
	local trim = part({
		Name = "Trim",
		Size = Vector3.new(37.4, 0.2, 37.4),
		Color = NEON_TRIM,
		Material = Enum.Material.Neon,
	})
	trim.CFrame = CFrame.new(center + Vector3.new(0, BASE_TOP + 0.1, 0))
	trim.CanCollide = false
	trim.Parent = base

	-- Four steps up the plaza-facing side; each is jumpable.
	local inward = -Vector3.new(math.cos(angle), 0, math.sin(angle)) -- toward plaza
	for step = 1, 4 do
		local height = BASE_TOP * step / 4
		local depth = 3
		local offset = 19 + (4 - step) * depth + depth / 2
		local stair = part({
			Name = "Stair" .. step,
			Size = Vector3.new(14, height, depth),
			Color = ISLAND,
			Material = Enum.Material.Concrete,
		})
		stair.CFrame = CFrame.lookAt(center + inward * offset + Vector3.new(0, height / 2, 0), center + inward * (offset + 1) + Vector3.new(0, height / 2, 0))
		stair.Parent = base
	end

	-- Pedestals: the first Economy.startSlots accept units, the rest start locked.
	local right = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	local rowCount = 5
	for slot = 1, Config.Economy.maxSlots do
		local row = math.floor((slot - 1) / rowCount)
		local col = (slot - 1) % rowCount
		local rowOffset = row * 7 - 3.5
		local colOffset = (col - (rowCount - 1) / 2) * PEDESTAL_SPACING
		local pos = center + right * colOffset + inward * rowOffset + Vector3.new(0, BASE_TOP + 0.9, 0)

		local pedestal = part({
			Name = "Pedestal" .. slot,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.8, 4.4, 4.4),
			Color = slot <= Config.Economy.startSlots and Color3.fromRGB(115, 120, 135) or Color3.fromRGB(58, 60, 70),
			Material = Enum.Material.Slate,
		})
		pedestal.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		pedestal:SetAttribute("Slot", slot)
		pedestal.Parent = base
	end

	-- The sign above the island: "OPEN" until a player claims it.
	local signAnchor = part({
		Name = "BaseSign",
		Size = Vector3.new(14, 3.2, 0.8),
		Color = Color3.fromRGB(28, 30, 38),
		Material = Enum.Material.SmoothPlastic,
	})
	signAnchor.CFrame = CFrame.new(center + Vector3.new(0, BASE_TOP + 6.5, 0)) * CFrame.Angles(0, angle + math.rad(90), 0)
	signAnchor.CanCollide = false
	signAnchor.Parent = base
	local signGui = label(signAnchor, "BASE " .. index .. " — OPEN", "stand on it to claim", Color3.fromRGB(120, 255, 150))
	signGui.Name = "BaseSignGui"

	-- Permanent SAFE ZONE marker on the plaza-facing edge of the island.
	local safeAnchor = part({
		Name = "SafeSign",
		Size = Vector3.new(11, 2.6, 0.6),
		Color = Color3.fromRGB(8, 50, 22),
		Material = Enum.Material.SmoothPlastic,
	})
	safeAnchor.CFrame = CFrame.new(center + inward * 17.5 + Vector3.new(0, BASE_TOP + 2.8, 0))
	safeAnchor.CanCollide = false
	safeAnchor.Parent = base
	label(safeAnchor, "SAFE ZONE", "the tsunami can't reach here", Color3.fromRGB(130, 255, 165))

	base:SetAttribute("Index", index)
	base:SetAttribute("CenterX", center.X)
	base:SetAttribute("CenterZ", center.Z)
	base:SetAttribute("TopY", BASE_TOP)
	base.Parent = workspace
	return base
end

-- One capsule spawn pad: a glowing disc the capsules appear on.
function WorldBuilder.buildSpawnPad(index)
	local angle = math.rad((index - 1) * (360 / Config.Capsule.padCount) + 22.5)
	local radius = 40
	local center = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

	local pad = part({
		Name = "SpawnPad" .. index,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 9, 9),
		Color = Color3.fromRGB(210, 130, 255),
		Material = Enum.Material.Neon,
	})
	pad.CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad:SetAttribute("PadIndex", index)
	pad.Parent = workspace

	local ring = part({
		Name = "SpawnPadRing" .. index,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 11, 11),
		Color = Color3.fromRGB(70, 58, 85),
		Material = Enum.Material.Slate,
	})
	ring.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	return pad
end

-- Perimeter walls: four slabs with a glowing top trim that mark the boundary.
local function buildWalls()
	local height = 22
	local length = ARENA_HALF * 2 + 4
	for i = 1, 4 do
		local wall = part({
			Name = "Wall" .. i,
			Size = i % 2 == 1 and Vector3.new(length, height, 3) or Vector3.new(3, height, length),
			Color = Color3.fromRGB(95, 125, 185),
			Material = Enum.Material.Brick,
		})
		local half = ARENA_HALF + 1.5
		local offset = Vector3.new(
			i == 2 and half or (i == 4 and -half or 0),
			height / 2,
			i == 1 and -half or (i == 3 and half or 0)
		)
		wall.CFrame = CFrame.new(offset)
		wall.Parent = workspace

		local trim = part({
			Name = "WallTrim" .. i,
			Size = i % 2 == 1 and Vector3.new(length + 0.4, 0.9, 3.6) or Vector3.new(3.6, 0.9, length + 0.4),
			Color = Color3.fromRGB(80, 235, 255),
			Material = Enum.Material.Neon,
		})
		trim.CFrame = CFrame.new(offset + Vector3.new(0, height / 2 + 0.45, 0))
		trim.CanCollide = false
		trim.Parent = workspace
	end
end

-- A tree: trunk + blob canopy.
local function buildTree(position, size)
	local trunk = part({
		Name = "Trunk",
		Size = Vector3.new(2, 7 * size, 2),
		Color = Color3.fromRGB(120, 82, 50),
		Material = Enum.Material.Wood,
	})
	trunk.CFrame = CFrame.new(position + Vector3.new(0, 3.5 * size, 0))
	trunk.Parent = workspace

	local canopy = part({
		Name = "Canopy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(9, 8, 9) * size,
		Color = Color3.fromRGB(70, 175, 85),
		Material = Enum.Material.Grass,
	})
	canopy.CFrame = CFrame.new(position + Vector3.new(0, 9 * size, 0))
	canopy.Parent = workspace
end

-- A rock: a squashed grey sphere.
local function buildRock(position, size)
	local rock = part({
		Name = "Rock",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size * 0.6, size),
		Color = Color3.fromRGB(145, 145, 150),
		Material = Enum.Material.Slate,
	})
	rock.CFrame = CFrame.new(position + Vector3.new(0, size * 0.2, 0))
	rock.Parent = workspace
end

-- The central plaza: disc, fountain plinth with the mascot statue, and the
-- how-to-play signs a new player walks past first.
local function buildPlaza()
	local disc = part({
		Name = "PlazaDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 46, 46),
		Color = Color3.fromRGB(250, 243, 215),
		Material = Enum.Material.Concrete,
	})
	disc.CFrame = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace

	local plinth = part({
		Name = "Plinth",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 12, 12),
		Color = Color3.fromRGB(170, 160, 185),
		Material = Enum.Material.Marble,
	})
	plinth.CFrame = CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	plinth.Parent = workspace

	-- Mascot: a giant Gunko looking over the arena.
	local statue = BrainrotModels.buildStatue(Config.Brainrots[1])
	local statuePivot = CFrame.new(0, 5 + 8.5, 0) * CFrame.Angles(0, math.rad(180), 0)
	statue:PivotTo(statuePivot)
	statue.Parent = workspace

	buildSign(Vector3.new(-26, 7, -26), 45, "HOW TO PLAY", {
		"1. Touch a capsule to CATCH a brainrot",
		"2. Bring it to YOUR base — the green SAFE ZONE",
		"3. It earns cash every second while placed",
		"4. When the TSUNAMI warning sounds, RUN HOME",
	})
	buildSign(Vector3.new(26, 7, -26), -45, "THE VAULT", {
		"12 brainrots from Common to Mythic",
		"Mutations + traits multiply a rate up to 9x",
		"Guard your base — the robbery lock is 60s+",
		"REBIRTH: more income, +2 base slots each",
	})
end

-- The museum: one pedestal per catalog entry along the north edge, so a
-- screenshot instantly reads "collection game".
local function buildShowcase()
	local count = #Config.Brainrots
	local spacing = 11
	local startX = -(count - 1) / 2 * spacing
	local z = -84

	for i, entry in ipairs(Config.Brainrots) do
		local pos = Vector3.new(startX + (i - 1) * spacing, 0, z)
		local rarity = Config.rarity(entry.rarity)

		local pedestal = part({
			Name = "MuseumPedestal" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6, 5, 5),
			Color = Color3.fromRGB(40, 42, 52),
			Material = Enum.Material.Slate,
		})
		pedestal.CFrame = CFrame.new(pos + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pedestal.Parent = workspace

		local plate = part({
			Name = "MuseumPlate" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 5.4, 5.4),
			Color = rarity.color,
			Material = Enum.Material.Neon,
		})
		plate.CFrame = CFrame.new(pos + Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.rad(90))
		plate.CanCollide = false
		plate.Parent = workspace

		local unit = BrainrotModels.buildPlaced(entry, nil)
		unit:PivotTo(CFrame.new(pos + Vector3.new(0, 4.7, 0)) * CFrame.Angles(0, math.rad(180), 0))
		unit.Parent = workspace
		BrainrotModels.startSway(unit)
	end

	-- Wide banner board behind the row.
	local board = part({
		Name = "ShowcaseBoard",
		Size = Vector3.new(72, 9, 1),
		Color = Color3.fromRGB(30, 26, 45),
		Material = Enum.Material.SmoothPlastic,
	})
	board.CFrame = CFrame.new(0, 14, -97)
	board.CanCollide = false
	board.Parent = workspace

	for _, faceNormal in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local face = Instance.new("SurfaceGui")
		face.Face = faceNormal
		face.CanvasSize = Vector2.new(1440, 180)
		face.Parent = board

		local titleBox = Instance.new("TextLabel")
		titleBox.Size = UDim2.fromScale(1, 0.55)
		titleBox.BackgroundTransparency = 1
		titleBox.Font = Enum.Font.GothamBold
		titleBox.TextScaled = true
		titleBox.TextColor3 = Color3.fromRGB(255, 215, 90)
		titleBox.Text = "★ VAULT SHOWCASE — ALL 12 BRAINROTS ★"
		titleBox.Parent = face

		local sub = Instance.new("TextLabel")
		sub.Position = UDim2.fromScale(0, 0.55)
		sub.Size = UDim2.fromScale(1, 0.45)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(235, 235, 245)
		sub.Text = "Common → Mythic · catch them all to fill your collection"
		sub.Parent = face
	end

	for _, side in ipairs({ -1, 1 }) do
		local post = part({
			Name = "ShowcasePost",
			Size = Vector3.new(1.6, 19, 1.6),
			Color = Color3.fromRGB(45, 40, 60),
			Material = Enum.Material.Metal,
		})
		post.CFrame = CFrame.new(side * 32, 9.5, -97)
		post.Parent = workspace
	end
end

-- Flip a base's sign to a new owner (called when a player claims their island).
function WorldBuilder.setBaseSign(baseModel, title, subtitle, color)
	local sign = baseModel:FindFirstChild("BaseSign")
	if sign == nil then
		return
	end
	local anchor = sign:FindFirstChild("LabelAnchor")
	local gui = anchor and (anchor:FindFirstChild("BaseSignGui") or anchor:FindFirstChild("Label"))
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

-- Build everything. Returns { pads = {spawn pad parts}, bases = {base models} }.
function WorldBuilder.build()
	setupLighting()
	buildGround()
	buildWalls()
	buildPlaza()
	buildShowcase()
	buildSpawnArea()

	local pads = {}
	for i = 1, Config.Capsule.padCount do
		pads[i] = WorldBuilder.buildSpawnPad(i)
	end

	local bases = {}
	for i = 1, 4 do
		bases[i] = WorldBuilder.buildBase(i)
	end

	-- Decoration tucked between the bases and the walls.
	local scenery = {
		{ Vector3.new(-95, 0, -40), "tree", 1.2 },
		{ Vector3.new(-95, 0, 40), "tree", 0.9 },
		{ Vector3.new(95, 0, -40), "tree", 1.1 },
		{ Vector3.new(95, 0, 45), "tree", 1.0 },
		{ Vector3.new(-40, 0, 95), "tree", 1.3 },
		{ Vector3.new(40, 0, 95), "tree", 0.95 },
		{ Vector3.new(-40, 0, -95), "tree", 1.05 },
		{ Vector3.new(45, 0, -95), "tree", 1.25 },
		{ Vector3.new(-55, 0, 55), "rock", 6 },
		{ Vector3.new(58, 0, -52), "rock", 7 },
		{ Vector3.new(-58, 0, -58), "rock", 5 },
		{ Vector3.new(60, 0, 60), "rock", 6.5 },
	}
	for _, item in ipairs(scenery) do
		local position, kind, size = item[1], item[2], item[3]
		if kind == "tree" then
			buildTree(position, size)
		else
			buildRock(position, size)
		end
	end

	return { pads = pads, bases = bases }
end

return WorldBuilder
