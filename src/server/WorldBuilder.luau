-- WorldBuilder: constructs the whole 3D arena at server start — the four player
-- bases (raised islands with pedestals and stairs), the eight capsule spawn pads,
-- the central plaza with its mascot statue and rules signs, and the perimeter
-- walls, trees and rocks. Everything is anchored plain parts, so the place stays
-- cheap and the whole map lives in code next to the scripts that use it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local BrainrotModels = require(script.Parent.BrainrotModels)

local WorldBuilder = {}

local ARENA_HALF = 110 -- play area is a 220-stud square inside the walls
local BASE_RADIUS = 70 -- distance from plaza center to each base
local BASE_TOP = 16 -- top of a base island; the tsunami stays below it
local PEDESTAL_SPACING = 6.2

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
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = studsOffset or Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 120
	gui.Parent = anchor

	local main = Instance.new("TextLabel")
	main.Size = UDim2.fromScale(1, 0.55)
	main.BackgroundTransparency = 1
	main.Font = Enum.Font.GothamBold
	main.TextScaled = true
	main.Text = title
	main.TextColor3 = color or Color3.new(1, 1, 1)
	main.TextStrokeTransparency = 0.4
	main.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromScale(0, 0.55)
	sub.Size = UDim2.fromScale(1, 0.45)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.Text = subtitle or ""
	sub.TextColor3 = Color3.fromRGB(230, 230, 230)
	sub.TextStrokeTransparency = 0.5
	sub.Parent = gui

	return gui
end

-- A text sign standing on the plaza, so the loop is readable in a screenshot.
-- The text is put on both faces so it reads correctly from either side.
local function buildSign(position, rotationY, title, lines)
	local board = part({
		Name = "Sign",
		Size = Vector3.new(14, 8, 1),
		Color = Color3.fromRGB(60, 45, 35),
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
		titleBox.TextColor3 = Color3.fromRGB(255, 220, 120)
		titleBox.Text = title
		titleBox.Parent = face

		local body = Instance.new("TextLabel")
		body.Position = UDim2.fromScale(0, 0.3)
		body.Size = UDim2.fromScale(1, 0.7)
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.Gotham
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
		Color = Color3.fromRGB(80, 60, 45),
		Material = Enum.Material.Wood,
	})
	post.CFrame = CFrame.new(position - Vector3.new(0, 7, 0)) * CFrame.Angles(0, math.rad(rotationY), 0)
	post.Parent = workspace
end

-- One player base: a raised island, a ring of pedestals (locked ones dimmed),
-- stairs up from the plaza, and a sign that flips to the owner's name.
function WorldBuilder.buildBase(index)
	local angle = math.rad((index - 1) * 90 - 90) -- bases at north/east/south/west
	local center = Vector3.new(math.cos(angle) * BASE_RADIUS, 0, math.sin(angle) * BASE_RADIUS)

	local base = Instance.new("Model")
	base.Name = "Base" .. index

	local island = part({
		Name = "Island",
		Size = Vector3.new(38, BASE_TOP, 38),
		Color = Color3.fromRGB(200, 200, 205),
		Material = Enum.Material.Concrete,
	})
	island.CFrame = CFrame.new(center + Vector3.new(0, BASE_TOP / 2, 0))
	island.Parent = base

	-- Glowing floor inlay so each island reads as yours from across the map.
	-- It sits a hair above the island top (walk surface stays the island itself).
	local trim = part({
		Name = "Trim",
		Size = Vector3.new(37.4, 0.2, 37.4),
		Color = Color3.fromRGB(90, 200, 255),
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
			Color = Color3.fromRGB(200, 200, 205),
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
			Color = slot <= Config.Economy.startSlots and Color3.fromRGB(70, 70, 80) or Color3.fromRGB(45, 45, 50),
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
		Color = Color3.fromRGB(35, 35, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	signAnchor.CFrame = CFrame.new(center + Vector3.new(0, BASE_TOP + 6, 0)) * CFrame.Angles(0, angle + math.rad(90), 0)
	signAnchor.CanCollide = false
	signAnchor.Parent = base
	local signGui = label(signAnchor, "BASE " .. index .. " — OPEN", "stand on it to claim", Color3.fromRGB(120, 230, 140))
	signGui.Name = "BaseSignGui"

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
		Color = Color3.fromRGB(200, 120, 255),
		Material = Enum.Material.Neon,
	})
	pad.CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad:SetAttribute("PadIndex", index)
	pad.Parent = workspace

	local ring = part({
		Name = "SpawnPadRing" .. index,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 11, 11),
		Color = Color3.fromRGB(60, 50, 70),
		Material = Enum.Material.Slate,
	})
	ring.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	return pad
end

-- Perimeter walls: four slabs that keep everyone inside the arena.
local function buildWalls()
	local height = 22
	local length = ARENA_HALF * 2 + 4
	for i = 1, 4 do
		local wall = part({
			Name = "Wall" .. i,
			Size = i % 2 == 1 and Vector3.new(length, height, 3) or Vector3.new(3, height, length),
			Color = Color3.fromRGB(70, 75, 90),
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
	end
end

-- A tree: trunk + blob canopy.
local function buildTree(position, size)
	local trunk = part({
		Name = "Trunk",
		Size = Vector3.new(2, 7 * size, 2),
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
	})
	trunk.CFrame = CFrame.new(position + Vector3.new(0, 3.5 * size, 0))
	trunk.Parent = workspace

	local canopy = part({
		Name = "Canopy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(9, 8, 9) * size,
		Color = Color3.fromRGB(60, 150, 70),
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
		Color = Color3.fromRGB(130, 130, 135),
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
		Color = Color3.fromRGB(225, 220, 210),
		Material = Enum.Material.Concrete,
	})
	disc.CFrame = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace

	local plinth = part({
		Name = "Plinth",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 12, 12),
		Color = Color3.fromRGB(150, 140, 160),
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
		"2. Carry it to YOUR base and step on it",
		"3. It earns cash every second while placed",
		"4. When the TSUNAMI warning sounds, RUN HOME",
	})
	buildSign(Vector3.new(26, 7, -26), -45, "THE VAULT", {
		"12 brainrots from Common to Mythic",
		"Mutations multiply a unit's rate up to 5x",
		"Buy slots, multipliers and speed in the SHOP",
		"REBIRTH resets cash for a permanent boost",
	})
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
	buildWalls()
	buildPlaza()

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
