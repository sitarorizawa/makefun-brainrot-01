-- WorldBuilder: Phase 12 — COMPLETE WORLD REMAKE.
-- Flat vibrant island, symmetrical 2x2 base grid, detailed pastel buildings with
-- pillars/windows/awnings, orange center path, white border path, tree ring,
-- flower dots, street lamps, perimeter fence. Clean front-page-simulator style.
--
-- Interface init.server.luau depends on:
--   build() -> { pads = array<Part>, bases = array<Model> }
--   setBaseSign(model, title, subtitle, color)
--   buildSpawnPad(index) -> Part

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local ISLAND_SIZE = 250
local OCEAN_SIZE = 500

-- Base district: 2x2 grid, generous spacing.
local BASE_HALF = 10 -- 20x20 footprint
local BASE_WALL_H = 8
local BASE_POSITIONS = { { -25, -35, 1 }, { 25, -35, 2 }, { -25, 35, 3 }, { 25, 35, 4 } }

-- Compound outline (white border path + fence).
local COMPOUND_X = 40
local COMPOUND_Z = 50

-- Orange center path runs east-west at z=0.
local PATH_X_MIN = -80
local PATH_X_MAX = 80
local PATH_WIDTH = 8

-- Spawn plaza at west end.
local SPAWN_X = -80
local PLAZA_HALF = 10

-- Shops at east end.
local SHOP_X = 80

-- Tree border ring.
local TREE_RADIUS = 110
local TREE_COUNT = 24

-- ---------------------------------------------------------------------------
-- Colour palette
-- ---------------------------------------------------------------------------

local GRASS = Color3.fromRGB(80, 180, 70)
local OCEAN = Color3.fromRGB(60, 160, 220)
local WALL_PASTEL = Color3.fromRGB(240, 235, 240)
local PILLAR = Color3.fromRGB(210, 205, 212)
local ROOF_LIME = Color3.fromRGB(120, 200, 80)
local WINDOW_BLUE = Color3.fromRGB(150, 200, 230)
local STEP_GREY = Color3.fromRGB(60, 60, 65)
local AWNING_RED = Color3.fromRGB(200, 50, 50)
local INTERIOR_RED = Color3.fromRGB(180, 50, 50)
local DOOR_GOLD = Color3.fromRGB(255, 200, 40)
local ORANGE_PATH = Color3.fromRGB(255, 140, 30)
local YELLOW_LINE = Color3.fromRGB(255, 220, 40)
local BORDER_PATH = Color3.fromRGB(200, 200, 205)
local CRYPTO_WALL = Color3.fromRGB(230, 240, 255)
local CRYPTO_ROOF = Color3.fromRGB(80, 180, 255)
local UPGRADE_WALL = Color3.fromRGB(240, 230, 255)
local UPGRADE_ROOF = Color3.fromRGB(180, 80, 255)
local TRUNK_BROWN = Color3.fromRGB(100, 70, 40)
local FOLIAGE = Color3.fromRGB(80, 180, 70)
local FENCE_BROWN = Color3.fromRGB(80, 60, 40)
local LAMP_POLE = Color3.fromRGB(50, 50, 55)
local LAMP_GLOW = Color3.fromRGB(255, 220, 100)
local STATUE_GOLD = Color3.fromRGB(255, 200, 40)
local PLAZA_TILE_A = Color3.fromRGB(240, 240, 245)
local PLAZA_TILE_B = Color3.fromRGB(200, 200, 210)
local SIGN_DARK = Color3.fromRGB(32, 36, 44)
local SIGN_GREEN = Color3.fromRGB(120, 255, 150)
local PAD_CORE = Color3.fromRGB(120, 220, 255)
local PAD_RING = Color3.fromRGB(80, 180, 230)

local FLOWER_COLORS = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 220, 60),
	Color3.fromRGB(255, 130, 200),
	Color3.fromRGB(80, 230, 255),
	Color3.fromRGB(255, 255, 255),
}

-- ---------------------------------------------------------------------------
-- Part helpers
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

-- Box part already parented to a model.
local function box(parent, name, size, cf, color, mat, collide)
	local p = part({
		Name = name,
		Size = size,
		Color = color,
		Material = mat or Enum.Material.SmoothPlastic,
	})
	p.CFrame = cf
	if collide == false then
		p.CanCollide = false
	end
	p.Parent = parent
	return p
end

-- BillboardGui text label. Always MaxDistance set, TextScaled false, TextSize 12.
local function makeBillboard(parent, text, color, width, height, maxDist, textSize)
	local gui = Instance.new("BillboardGui")
	gui.Name = "ZoneLabel"
	gui.Size = UDim2.fromOffset(width or 200, height or 50)
	gui.AlwaysOnTop = true
	gui.MaxDistance = maxDist or 80
	gui.Parent = parent
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = false
	lbl.TextSize = textSize or 12
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	lbl.TextStrokeTransparency = 0.25
	lbl.Parent = gui
	return gui
end

-- Base nameplate: BaseSign part holds BaseSignGui with Title + Subtitle.
-- setBaseSign() updates these by name.
local function buildBaseNameplate(parent, title, color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BaseSignGui"
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, 0.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Parent = parent

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = SIGN_DARK
	bg.BackgroundTransparency = 0.18
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bg

	local main = Instance.new("TextLabel")
	main.Name = "Title"
	main.Size = UDim2.fromScale(1, 0.6)
	main.BackgroundTransparency = 1
	main.Font = Enum.Font.GothamBold
	main.TextScaled = false
	main.TextSize = 12
	main.Text = title
	main.TextColor3 = color or Color3.new(1, 1, 1)
	main.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	main.TextStrokeTransparency = 0.25
	main.ZIndex = 2
	main.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = false
	sub.TextSize = 12
	sub.Text = ""
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	sub.TextStrokeTransparency = 0.3
	sub.ZIndex = 2
	sub.Parent = gui

	return gui
end

-- ---------------------------------------------------------------------------
-- Lighting: empty of custom setup, just enforce shadows + brightness safely.
-- ---------------------------------------------------------------------------

local function setupLighting()
	-- Operator requested no custom lighting. Only nudge the two safe globals.
	pcall(function()
		Lighting.GlobalShadows = true
		Lighting.Brightness = 2
	end)
end

-- ---------------------------------------------------------------------------
-- Terrain: flat green plane, no hills/beach/cliffs.
-- ---------------------------------------------------------------------------

local function buildTerrain()
	local m = Instance.new("Model")
	m.Name = "Terrain"

	local grass = part({
		Name = "GrassBase",
		Size = Vector3.new(ISLAND_SIZE, 0.4, ISLAND_SIZE),
		Color = GRASS,
		Material = Enum.Material.Grass,
	})
	grass.CFrame = CFrame.new(0, 0, 0)
	grass.Parent = m

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Ocean: translucent plane underneath.
-- ---------------------------------------------------------------------------

local function buildOcean()
	local m = Instance.new("Model")
	m.Name = "Ocean"

	local water = part({
		Name = "OceanPlane",
		Size = Vector3.new(OCEAN_SIZE, 0.2, OCEAN_SIZE),
		Color = OCEAN,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.3,
	})
	water.CFrame = CFrame.new(0, -3, 0)
	water.CanCollide = false
	water.Parent = m

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Paths: orange center walkway + yellow line + white border ring.
-- ---------------------------------------------------------------------------

local function buildPaths()
	local m = Instance.new("Model")
	m.Name = "Paths"

	local pathLen = PATH_X_MAX - PATH_X_MIN

	-- Orange center path (east-west, z=0).
	local orange = box(m, "OrangePath", Vector3.new(pathLen, 0.2, PATH_WIDTH),
		CFrame.new(0, 0.11, 0), ORANGE_PATH, Enum.Material.SmoothPlastic)

	-- Yellow center line.
	box(m, "YellowLine", Vector3.new(pathLen, 0.06, 0.3),
		CFrame.new(0, 0.22, 0), YELLOW_LINE, Enum.Material.Neon, false)

	-- White/grey border path around the compound (4-wide ring).
	local bw = 4
	box(m, "BorderN", Vector3.new(COMPOUND_X * 2 + bw * 2, 0.2, bw),
		CFrame.new(0, 0.11, COMPOUND_Z + bw / 2), BORDER_PATH, Enum.Material.Concrete)
	box(m, "BorderS", Vector3.new(COMPOUND_X * 2 + bw * 2, 0.2, bw),
		CFrame.new(0, 0.11, -COMPOUND_Z - bw / 2), BORDER_PATH, Enum.Material.Concrete)
	box(m, "BorderE", Vector3.new(bw, 0.2, COMPOUND_Z * 2),
		CFrame.new(COMPOUND_X + bw / 2, 0.11, 0), BORDER_PATH, Enum.Material.Concrete)
	box(m, "BorderW", Vector3.new(bw, 0.2, COMPOUND_Z * 2),
		CFrame.new(-COMPOUND_X - bw / 2, 0.11, 0), BORDER_PATH, Enum.Material.Concrete)

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Building shell: pastel walls, pillars, windows, doorframe, awning, roof.
-- Shared by bases and shops. Door is on the z-face toward z=0 (normalZ).
-- ---------------------------------------------------------------------------

local function buildShell(model, cx, cz, halfW, halfD, wallH, wallColor, roofColor, normalZ, doorWidth, awningColor)
	local doorHalf = doorWidth / 2
	local doorWallZ = cz + normalZ * halfD
	local oppZ = cz - normalZ * halfD
	local wallY = wallH / 2 + 0.2

	-- Door wall (split around opening).
	local segW = halfW - doorHalf
	box(model, "WallDoorL", Vector3.new(segW, wallH, 0.5),
		CFrame.new(cx - (halfW + doorHalf) / 2, wallY, doorWallZ), wallColor, Enum.Material.SmoothPlastic)
	box(model, "WallDoorR", Vector3.new(segW, wallH, 0.5),
		CFrame.new(cx + (halfW + doorHalf) / 2, wallY, doorWallZ), wallColor, Enum.Material.SmoothPlastic)

	-- Back wall.
	box(model, "WallBack", Vector3.new(halfW * 2, wallH, 0.5),
		CFrame.new(cx, wallY, oppZ), wallColor, Enum.Material.SmoothPlastic)

	-- Side walls.
	box(model, "WallW", Vector3.new(0.5, wallH, halfD * 2),
		CFrame.new(cx - halfW, wallY, cz), wallColor, Enum.Material.SmoothPlastic)
	box(model, "WallE", Vector3.new(0.5, wallH, halfD * 2),
		CFrame.new(cx + halfW, wallY, cz), wallColor, Enum.Material.SmoothPlastic)

	-- Four corner pillars.
	for _, px in ipairs({ -halfW, halfW }) do
		for _, pz in ipairs({ -halfD, halfD }) do
			box(model, "Pillar", Vector3.new(0.4, wallH, 0.4),
				CFrame.new(cx + px, wallY, cz + pz), PILLAR, Enum.Material.SmoothPlastic)
		end
	end

	-- Windows: 2 on back wall, 2 on each side wall (blue-tinted insets).
	local winY = wallH / 2 + 0.2
	local backOff = math.min(halfW - 2, 3)
	local sideOff = math.min(halfD - 2, 3)
	box(model, "Window", Vector3.new(2.6, 2.6, 0.2),
		CFrame.new(cx - backOff, winY, oppZ), WINDOW_BLUE, Enum.Material.SmoothPlastic, false)
	box(model, "Window", Vector3.new(2.6, 2.6, 0.2),
		CFrame.new(cx + backOff, winY, oppZ), WINDOW_BLUE, Enum.Material.SmoothPlastic, false)
	for _, sx in ipairs({ -halfW, halfW }) do
		box(model, "Window", Vector3.new(0.2, 2.6, 2.6),
			CFrame.new(cx + sx, winY, cz - sideOff), WINDOW_BLUE, Enum.Material.SmoothPlastic, false)
		box(model, "Window", Vector3.new(0.2, 2.6, 2.6),
			CFrame.new(cx + sx, winY, cz + sideOff), WINDOW_BLUE, Enum.Material.SmoothPlastic, false)
	end

	-- Gold neon doorframe pillars + lintel.
	for _, dx in ipairs({ -doorHalf, doorHalf }) do
		box(model, "DoorFrame", Vector3.new(0.6, wallH + 1, 0.6),
			CFrame.new(cx + dx, (wallH + 1) / 2 + 0.2, doorWallZ), DOOR_GOLD, Enum.Material.Neon)
	end
	box(model, "DoorLintel", Vector3.new(doorWidth + 1, 0.4, 0.4),
		CFrame.new(cx, wallH + 0.6, doorWallZ), DOOR_GOLD, Enum.Material.Neon)

	-- Dark grey entrance step.
	box(model, "DoorStep", Vector3.new(doorWidth, 0.3, 1),
		CFrame.new(cx, 0.35, doorWallZ + normalZ * 0.5), STEP_GREY, Enum.Material.SmoothPlastic)

	-- Red awning above the door.
	box(model, "Awning", Vector3.new(doorWidth + 0.5, 0.3, 1.5),
		CFrame.new(cx, wallH + 0.4, doorWallZ + normalZ * 0.6), awningColor, Enum.Material.SmoothPlastic, false)

	-- Roof slab with 1-stud overhang.
	box(model, "Roof", Vector3.new(halfW * 2 + 2, 0.6, halfD * 2 + 2),
		CFrame.new(cx, wallH + 0.5, cz), roofColor, Enum.Material.SmoothPlastic)

	return doorWallZ
end

-- ---------------------------------------------------------------------------
-- Single player base.
-- ---------------------------------------------------------------------------

local function buildSingleBase(cx, cz, index)
	local model = Instance.new("Model")
	model.Name = "Base" .. index

	local halfW, halfD, wallH = BASE_HALF, BASE_HALF, BASE_WALL_H
	local normalZ = cz > 0 and -1 or 1 -- door faces toward z=0 (center path)
	local doorWallZ = buildShell(model, cx, cz, halfW, halfD, wallH,
		WALL_PASTEL, ROOF_LIME, normalZ, 5, AWNING_RED)

	-- Interior red floor — the "Island" the server hooks .Touched on.
	local floor = box(model, "Island", Vector3.new(halfW * 2, 0.4, halfD * 2),
		CFrame.new(cx, 0.2, cz), INTERIOR_RED, Enum.Material.SmoothPlastic)

	-- 2x5 pedestals, open interior.
	for slot = 1, Config.Economy.maxSlots do
		local row = math.floor((slot - 1) / 5)
		local col = (slot - 1) % 5
		local px = cx + (col - 2) * 4
		local pz = cz + (row == 0 and -3 or 3)
		local pedColor = slot <= Config.Economy.startSlots
			and Color3.fromRGB(115, 120, 135)
			or Color3.fromRGB(58, 60, 70)
		local pedestal = part({
			Name = "Pedestal" .. slot,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.8, 4.2, 4.2),
			Color = pedColor,
			Material = Enum.Material.Slate,
		})
		pedestal.CFrame = CFrame.new(px, 2.3, pz) * CFrame.Angles(0, 0, math.rad(90))
		pedestal:SetAttribute("Slot", slot)
		pedestal.Parent = model
	end

	-- YOUR BASE nameplate above the door.
	local sign = box(model, "BaseSign", Vector3.new(12, 1.6, 0.4),
		CFrame.new(cx, wallH + 2, doorWallZ + normalZ * 0.3), SIGN_DARK, Enum.Material.SmoothPlastic, false)
	buildBaseNameplate(sign, "YOUR BASE", SIGN_GREEN)

	-- Attributes the server reads.
	model:SetAttribute("Index", index)
	model:SetAttribute("CenterX", cx)
	model:SetAttribute("CenterZ", cz)
	model:SetAttribute("TopY", 0.4)

	model.Parent = workspace
	return model
end

-- ---------------------------------------------------------------------------
-- Base district: 2x2 grid + perimeter fence with gate openings.
-- ---------------------------------------------------------------------------

local function buildBaseDistrict()
	local district = Instance.new("Model")
	district.Name = "BaseDistrict"

	local bases = {}
	for _, bp in ipairs(BASE_POSITIONS) do
		bases[bp[3]] = buildSingleBase(bp[1], bp[2], bp[3])
		bases[bp[3]].Parent = district
	end

	-- Perimeter fence around the compound (dark brown, 2 tall), gates at x=+/-40
	-- where the orange path enters (gap at z=0 on east/west edges).
	local fenceH = 2
	local gateHalf = 4
	-- North / south fences (full spans).
	box(district, "FenceN", Vector3.new(COMPOUND_X * 2, fenceH, 0.3),
		CFrame.new(0, fenceH / 2 + 0.2, COMPOUND_Z), FENCE_BROWN, Enum.Material.Wood)
	box(district, "FenceS", Vector3.new(COMPOUND_X * 2, fenceH, 0.3),
		CFrame.new(0, fenceH / 2 + 0.2, -COMPOUND_Z), FENCE_BROWN, Enum.Material.Wood)
	-- West fence split around gate at z=0.
	box(district, "FenceW1", Vector3.new(0.3, fenceH, COMPOUND_Z - gateHalf),
		CFrame.new(-COMPOUND_X, fenceH / 2 + 0.2, -(COMPOUND_Z + gateHalf) / 2 + gateHalf / 2), FENCE_BROWN, Enum.Material.Wood)
	box(district, "FenceW2", Vector3.new(0.3, fenceH, COMPOUND_Z - gateHalf),
		CFrame.new(-COMPOUND_X, fenceH / 2 + 0.2, (COMPOUND_Z + gateHalf) / 2 - gateHalf / 2), FENCE_BROWN, Enum.Material.Wood)
	-- East fence split around gate at z=0.
	box(district, "FenceE1", Vector3.new(0.3, fenceH, COMPOUND_Z - gateHalf),
		CFrame.new(COMPOUND_X, fenceH / 2 + 0.2, -(COMPOUND_Z + gateHalf) / 2 + gateHalf / 2), FENCE_BROWN, Enum.Material.Wood)
	box(district, "FenceE2", Vector3.new(0.3, fenceH, COMPOUND_Z - gateHalf),
		CFrame.new(COMPOUND_X, fenceH / 2 + 0.2, (COMPOUND_Z + gateHalf) / 2 - gateHalf / 2), FENCE_BROWN, Enum.Material.Wood)

	district.Parent = workspace
	return bases
end

-- ---------------------------------------------------------------------------
-- Shops: two buildings flanking the east end of the orange path.
-- ---------------------------------------------------------------------------

local function buildShop(cx, cz, name, wallColor, roofColor, signText, signColor, normalZ)
	local model = Instance.new("Model")
	model.Name = name

	local halfW, halfD, wallH = 6, 4, 6 -- 12x8 footprint
	local doorWallZ = buildShell(model, cx, cz, halfW, halfD, wallH,
		wallColor, roofColor, normalZ, 4, AWNING_RED)

	-- Interior floor.
	box(model, "Floor", Vector3.new(halfW * 2, 0.3, halfD * 2),
		CFrame.new(cx, 0.2, cz), STEP_GREY, Enum.Material.SmoothPlastic)

	-- Sign above the door.
	local sign = box(model, "ShopSign", Vector3.new(halfW * 2, 1.4, 0.3),
		CFrame.new(cx, wallH + 1.6, doorWallZ + normalZ * 0.3), SIGN_DARK, Enum.Material.SmoothPlastic, false)
	makeBillboard(sign, signText, signColor, 180, 44, 60, 12)

	model.Parent = workspace
	return model
end

local function buildShops()
	local m = Instance.new("Model")
	m.Name = "Shops"

	-- Crypto Shop south of path (z=-12), door faces +z toward path.
	local crypto = buildShop(SHOP_X, -12, "CryptoShop", CRYPTO_WALL, CRYPTO_ROOF, "CRYPTO SHOP", CRYPTO_ROOF, 1)
	crypto.Parent = m
	-- Upgrade Center north of path (z=+12), door faces -z toward path.
	local upgrade = buildShop(SHOP_X, 12, "UpgradeCenter", UPGRADE_WALL, UPGRADE_ROOF, "UPGRADE CENTER", UPGRADE_ROOF, -1)
	upgrade.Parent = m

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Spawn area: checkerboard plaza + bitcoin statue at west end.
-- ---------------------------------------------------------------------------

local function buildSpawnArea()
	local m = Instance.new("Model")
	m.Name = "SpawnArea"

	-- Checkerboard plaza tiles.
	local tileCount = 4
	local tileSize = PLAZA_HALF * 2 / tileCount
	for ix = 0, tileCount - 1 do
		for iz = 0, tileCount - 1 do
			local isLight = (ix + iz) % 2 == 0
			local tx = SPAWN_X - PLAZA_HALF + tileSize / 2 + ix * tileSize
			local tz = -PLAZA_HALF + tileSize / 2 + iz * tileSize
			box(m, "PlazaTile", Vector3.new(tileSize - 0.15, 0.18, tileSize - 0.15),
				CFrame.new(tx, 0.2, tz), isLight and PLAZA_TILE_A or PLAZA_TILE_B, Enum.Material.SmoothPlastic)
		end
	end

	-- Bitcoin statue: gold cylinder (3 x 10 x 3).
	local statue = part({
		Name = "BitcoinStatue",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10, 3, 3),
		Color = STATUE_GOLD,
		Material = Enum.Material.Metal,
	})
	statue.CFrame = CFrame.new(SPAWN_X, 5.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	statue.Parent = m

	-- ₿ symbol label.
	makeBillboard(statue, "₿", STATUE_GOLD, 120, 60, 100, 12)

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Tree border: dense ring around the island edge.
-- ---------------------------------------------------------------------------

local function buildTreeBorder()
	local m = Instance.new("Model")
	m.Name = "TreeBorder"

	for i = 0, TREE_COUNT - 1 do
		local angle = (i / TREE_COUNT) * math.pi * 2
		local tx = math.cos(angle) * TREE_RADIUS
		local tz = math.sin(angle) * TREE_RADIUS

		local trunk = part({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(4, 0.8, 0.8),
			Color = TRUNK_BROWN,
			Material = Enum.Material.Wood,
		})
		trunk.CFrame = CFrame.new(tx, 2, tz) * CFrame.Angles(0, 0, math.rad(90))
		trunk.Parent = m

		for _, layer in ipairs({ { 3.5, 5.0 }, { 2.8, 6.8 }, { 2.0, 8.2 } }) do
			local foliage = part({
				Name = "Foliage",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(layer[1], layer[1], layer[1]),
				Color = FOLIAGE,
				Material = Enum.Material.Grass,
			})
			foliage.CFrame = CFrame.new(tx, layer[2], tz)
			foliage.Parent = m
		end
	end

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Decorations: flower dots scattered on the grass.
-- ---------------------------------------------------------------------------

local function buildDecorations()
	local m = Instance.new("Model")
	m.Name = "Decorations"

	local flowerPositions = {
		{ -60, 20 }, { -60, -20 }, { -50, 30 }, { -50, -30 },
		{ -40, 12 }, { -40, -12 }, { 60, 20 }, { 60, -20 },
		{ 50, 30 }, { 50, -30 }, { 40, 12 }, { 40, -12 },
		{ 0, 60 }, { 0, -60 }, { 30, 60 }, { -30, 60 },
		{ 30, -60 }, { -30, -60 },
	}

	for i, fp in ipairs(flowerPositions) do
		local color = FLOWER_COLORS[((i - 1) % #FLOWER_COLORS) + 1]
		local flower = part({
			Name = "Flower" .. i,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.4, 0.4, 0.4),
			Color = color,
			Material = Enum.Material.Neon,
		})
		flower.CFrame = CFrame.new(fp[1], 0.3, fp[2])
		flower.CanCollide = false
		flower.Parent = m
	end

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Street lamps: 8 along the orange path.
-- ---------------------------------------------------------------------------

local function buildLamps()
	local m = Instance.new("Model")
	m.Name = "Lamps"

	for i = 1, 8 do
		local lx = PATH_X_MIN + (i - 1) * 20 + 10
		local lz = (i % 2 == 1) and -6 or 6

		local pole = part({
			Name = "Pole",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6, 0.2, 0.2),
			Color = LAMP_POLE,
			Material = Enum.Material.Metal,
		})
		pole.CFrame = CFrame.new(lx, 3.2, lz) * CFrame.Angles(0, 0, math.rad(90))
		pole.Parent = m

		local head = part({
			Name = "LampHead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.5, 0.5),
			Color = LAMP_GLOW,
			Material = Enum.Material.Neon,
		})
		head.CFrame = CFrame.new(lx, 6.4, lz)
		head.CanCollide = false
		head.Parent = m

		local light = Instance.new("PointLight")
		light.Color = LAMP_GLOW
		light.Brightness = 2.5
		light.Range = 20
		light.Parent = head
	end

	m.Parent = workspace
end

-- ---------------------------------------------------------------------------
-- Spawn pad: glowing disc along the orange path.
-- ---------------------------------------------------------------------------

function WorldBuilder.buildSpawnPad(index)
	local x = PATH_X_MIN + (index - 1) * 20 + 10
	local z = (index % 2 == 1) and -6 or 6

	local pad = part({
		Name = "SpawnPad" .. index,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 8, 8),
		Color = PAD_CORE,
		Material = Enum.Material.Neon,
	})
	pad.CFrame = CFrame.new(x, 0.2, z) * CFrame.Angles(0, 0, math.rad(90))
	pad:SetAttribute("PadIndex", index)
	pad.Parent = workspace

	local ring = part({
		Name = "SpawnPadRing" .. index,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 10, 10),
		Color = PAD_RING,
		Material = Enum.Material.Neon,
	})
	ring.CFrame = CFrame.new(x, 0.1, z) * CFrame.Angles(0, 0, math.rad(90))
	ring.CanCollide = false
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

	local template = workspace:FindFirstChild("Baseplate")
	if template then
		template:Destroy()
	end

	safeStep("setupLighting", setupLighting)
	safeStep("buildTerrain", buildTerrain)
	safeStep("buildOcean", buildOcean)
	safeStep("buildPaths", buildPaths)
	safeStep("buildSpawnArea", buildSpawnArea)
	safeStep("buildLamps", buildLamps)
	safeStep("buildTreeBorder", buildTreeBorder)
	safeStep("buildDecorations", buildDecorations)
	safeStep("buildShops", buildShops)

	local bases = buildBaseDistrict()

	local pads = {}
	for i = 1, Config.Capsule.padCount do
		pads[i] = WorldBuilder.buildSpawnPad(i)
	end

	return { pads = pads, bases = bases }
end

return WorldBuilder
