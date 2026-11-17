-- BrainrotModels: builds every 3D character in the game out of plain parts —
-- the twelve catalog brainrots (as carried, placed and capsule-preview versions),
-- their mutations, and the floating capsules that spawn on the map.
-- All animation (bob, spin, rainbow hue) lives here in one Heartbeat loop.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local BrainrotModels = {}

-- Registry for the one animation loop: models that bob, spin or hue-cycle.
local animated = {}
local rainbowParts = {}

local function makePart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

-- A simple billboard above a model: title line and a smaller subtitle line.
local function addLabel(model, title, subtitle, titleColor)
	local anchor = makePart({
		Name = "LabelAnchor",
		Size = Vector3.new(0.05, 0.05, 0.05),
		Transparency = 1,
	})
	anchor.Position = model:GetPivot().Position
	anchor.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(170, 44)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Parent = anchor

	local main = Instance.new("TextLabel")
	main.Name = "Title"
	main.Size = UDim2.fromScale(1, 0.55)
	main.BackgroundTransparency = 1
	main.Font = Enum.Font.GothamBold
	main.TextScaled = true
	main.Text = title
	main.TextColor3 = titleColor or Color3.new(1, 1, 1)
	main.TextStrokeTransparency = 0.4
	main.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Position = UDim2.fromScale(0, 0.55)
	sub.Size = UDim2.fromScale(1, 0.45)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.Text = subtitle or ""
	sub.TextColor3 = Color3.fromRGB(235, 235, 235)
	sub.TextStrokeTransparency = 0.5
	sub.Parent = gui

	return gui
end

-- Face: two eyes and a mouth, so every blob reads as a character.
local function addFace(model, bodyColor, halfWidth, frontOffset, eyeY)
	local white = Color3.new(1, 1, 1)
	local black = Color3.fromRGB(20, 20, 20)
	for _, side in ipairs({ -1, 1 }) do
		local eye = makePart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.5, 0.3),
			Color = white,
			Material = Enum.Material.SmoothPlastic,
		})
		eye.CFrame = model:GetPivot() * CFrame.new(side * halfWidth * 0.45, eyeY, frontOffset)
		eye.Parent = model
		local pupil = makePart({
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.24, 0.24, 0.18),
			Color = black,
			Material = Enum.Material.SmoothPlastic,
		})
		pupil.CFrame = eye.CFrame * CFrame.new(0, 0, -0.14)
		pupil.Parent = model
	end
	local mouth = makePart({
		Name = "Mouth",
		Size = Vector3.new(halfWidth * 0.9, 0.16, 0.12),
		Color = black,
		Material = Enum.Material.SmoothPlastic,
	})
	mouth.CFrame = model:GetPivot() * CFrame.new(0, eyeY - 0.75, frontOffset)
	mouth.Parent = model
end

-- The hat variants that give each catalog entry its silhouette.
local function addHat(model, hat, color, topY)
	if hat == "none" then
		return
	end
	if hat == "antenna" then
		local stem = makePart({
			Name = "Antenna",
			Size = Vector3.new(0.18, 1.1, 0.18),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		})
		stem.CFrame = model:GetPivot() * CFrame.new(0, topY + 0.55, 0)
		stem.Parent = model
		local bulb = makePart({
			Name = "AntennaBulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.5, 0.5),
			Color = Color3.fromRGB(255, 90, 90),
			Material = Enum.Material.Neon,
		})
		bulb.CFrame = model:GetPivot() * CFrame.new(0, topY + 1.2, 0)
		bulb.Parent = model
	elseif hat == "cap" then
		local brim = makePart({
			Name = "CapBrim",
			Size = Vector3.new(2.2, 0.2, 1.0),
			Color = Color3.fromRGB(40, 40, 45),
			Material = Enum.Material.Fabric,
		})
		brim.CFrame = model:GetPivot() * CFrame.new(0, topY + 0.15, -0.9)
		brim.Parent = model
		local dome = makePart({
			Name = "CapDome",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.9, 1.1, 1.9),
			Color = Color3.fromRGB(200, 60, 60),
			Material = Enum.Material.Fabric,
		})
		dome.CFrame = model:GetPivot() * CFrame.new(0, topY + 0.35, 0)
		dome.Parent = model
	elseif hat == "horns" then
		for _, side in ipairs({ -1, 1 }) do
			local horn = makePart({
				Name = "Horn",
				Shape = Enum.PartType.Block,
				Size = Vector3.new(0.3, 0.9, 0.3),
				Color = Color3.fromRGB(240, 240, 230),
				Material = Enum.Material.SmoothPlastic,
			})
			horn.CFrame = model:GetPivot() * CFrame.new(side * 0.9, topY + 0.4, 0) * CFrame.Angles(0, 0, math.rad(-18 * side))
			horn.Parent = model
		end
	elseif hat == "crown" then
		local band = makePart({
			Name = "Crown",
			Size = Vector3.new(1.7, 0.5, 1.7),
			Color = Color3.fromRGB(255, 200, 40),
			Material = Enum.Material.Metal,
		})
		band.CFrame = model:GetPivot() * CFrame.new(0, topY + 0.3, 0)
		band.Parent = model
		for _, offset in ipairs({ -0.6, 0, 0.6 }) do
			local point = makePart({
				Name = "CrownPoint",
				Size = Vector3.new(0.3, 0.45, 0.3),
				Color = Color3.fromRGB(255, 200, 40),
				Material = Enum.Material.Metal,
			})
			point.CFrame = model:GetPivot() * CFrame.new(offset, topY + 0.75, 0)
			point.Parent = model
		end
	end
end

-- Apply a mutation's look to every colored part of a freshly built model.
local function applyMutation(model, mutation)
	if mutation == nil or mutation.id == "none" then
		return
	end
	if mutation.id == "rainbow" then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "LabelAnchor" and part.Name ~= "Eye" and part.Name ~= "Pupil" and part.Name ~= "Mouth" then
				part.Material = Enum.Material.Neon
				table.insert(rainbowParts, part)
			end
		end
		return
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "LabelAnchor" and part.Name ~= "Eye" and part.Name ~= "Pupil" and part.Name ~= "Mouth" then
			part.Color = mutation.color
			if mutation.material then
				part.Material = mutation.material
			end
		end
	end
	if mutation.id == "toxic" then
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(90, 255, 90)
		glow.Range = 9
		glow.Brightness = 1.4
		glow.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	end
end

-- Build one brainrot character as an anchored Model whose PrimaryPart is the body.
-- `scale` grows it (the plaza statue uses a big one).
function BrainrotModels.build(entry, mutation, scale)
	scale = scale or 1
	local model = Instance.new("Model")
	model.Name = mutation and mutation.id ~= "none" and (mutation.name .. " " .. entry.name) or entry.name

	local bodyColor = entry.color
	if mutation and mutation.color then
		bodyColor = mutation.color
	end

	local body
	if entry.shape == "round" then
		body = makePart({
			Name = "Body",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.2, 3.2, 3.2) * scale,
			Color = bodyColor,
			Material = Enum.Material.SmoothPlastic,
		})
	elseif entry.shape == "box" then
		body = makePart({
			Name = "Body",
			Size = Vector3.new(3.0, 3.4, 2.6) * scale,
			Color = bodyColor,
			Material = Enum.Material.SmoothPlastic,
		})
	else -- tall
		body = makePart({
			Name = "Body",
			Size = Vector3.new(2.4, 4.4, 2.4) * scale,
			Color = bodyColor,
			Material = Enum.Material.SmoothPlastic,
		})
	end
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	model.PrimaryPart = body

	-- Stubby feet so the blob looks like it could waddle.
	for _, side in ipairs({ -1, 1 }) do
		local foot = makePart({
			Name = "Foot",
			Size = Vector3.new(0.9, 0.7, 1.3) * scale,
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.SmoothPlastic,
		})
		foot.CFrame = CFrame.new(side * 0.8 * scale, -1.7 * scale, 0.3 * scale)
		foot.Parent = model
	end

	addFace(model, bodyColor, body.Size.X, -body.Size.Z / 2 - 0.05, 0.5 * scale)
	addHat(model, entry.hat, bodyColor, body.Size.Y / 2)

	applyMutation(model, mutation)
	return model
end

-- A floating capsule: a glowing rarity-colored orb with the brainrot itself
-- spinning inside a glass shell, plus a name/rate billboard. Touch to catch it.
function BrainrotModels.buildCapsule(entry, mutation, position)
	local rarity = Config.rarity(entry.rarity)
	local model = Instance.new("Model")
	model.Name = "Capsule"

	local orb = makePart({
		Name = "Orb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.6, 3.6, 3.6),
		Color = rarity.color,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	})
	orb.CFrame = CFrame.new(position + Vector3.new(0, 3.6, 0))
	orb.CanCollide = true -- a solid ball guarantees the Touched catch fires
	orb.Parent = model
	model.PrimaryPart = orb

	local shell = makePart({
		Name = "Shell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.6, 4.6, 4.6),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
	})
	shell.CFrame = orb.CFrame
	shell.CanCollide = false -- the inner orb is the solid, touchable core
	shell.Parent = model

	local light = Instance.new("PointLight")
	light.Color = rarity.color
	light.Range = 14
	light.Brightness = 1.6
	light.Parent = orb

	-- The brainrot preview inside the ball.
	local unit = BrainrotModels.build(entry, mutation, 0.55)
	unit:PivotTo(CFrame.new(orb.Position) * CFrame.Angles(0, math.rad(180), 0))
	unit.Parent = model

	local rate = math.floor(entry.rate * (mutation and mutation.multiplier or 1) + 0.5)
	local mutationText = mutation and mutation.name ~= "" and (mutation.name .. " · ") or ""
	local gui = addLabel(model, mutationText .. entry.name, string.format("$%d/s  ·  %s", rate, entry.rarity), rarity.color)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)

	table.insert(animated, { model = model, kind = "spin", base = orb.Position })
	return model
end

-- The unit a player is carrying: the game script positions it above the
-- character each frame, so it is not registered for idle animation here.
function BrainrotModels.buildCarried(entry, mutation)
	local model = BrainrotModels.build(entry, mutation)
	local rarity = Config.rarity(entry.rarity)
	local rateText = string.format("$%d/s", entry.rate * (mutation and mutation.multiplier or 1))
	local mutationText = mutation and mutation.name ~= "" and (mutation.name .. " ") or ""
	addLabel(model, mutationText .. entry.name, rateText, rarity.color)
	return model
end

-- The unit resting on a pedestal: label shows name, mutation and rate.
function BrainrotModels.buildPlaced(entry, mutation)
	local model = BrainrotModels.build(entry, mutation)
	local rarity = Config.rarity(entry.rarity)
	local rate = math.floor(entry.rate * (mutation and mutation.multiplier or 1) + 0.5)
	local mutationText = mutation and mutation.name ~= "" and (mutation.name .. " · ") or ""
	addLabel(model, mutationText .. entry.name, string.format("$%d/s  ·  %s", rate, entry.rarity), rarity.color)
	return model
end

-- Register a placed unit for its gentle idle sway. Call after positioning it:
-- the animation pivots around the pose it has right now.
function BrainrotModels.startSway(model)
	table.insert(animated, { model = model, kind = "sway", base = model:GetPivot() })
end

-- Remove a model from the animation registries (called on destroy/drop).
function BrainrotModels.retire(model)
	for i = #animated, 1, -1 do
		if animated[i].model == model then
			table.remove(animated, i)
		end
	end
	for i = #rainbowParts, 1, -1 do
		if not rainbowParts[i].Parent then
			table.remove(rainbowParts, i)
		end
	end
end

-- One loop drives every animation in the game: capsule spin, carried bob,
-- placed sway and the rainbow mutation's hue cycle.
RunService.Heartbeat:Connect(function()
	local now = tick()
	for i = #animated, 1, -1 do
		local item = animated[i]
		local model = item.model
		if not model.Parent then
			table.remove(animated, i)
		elseif item.kind == "spin" then
			-- Capsules spin and hover around the pad position they were built at.
			local hover = math.sin(now * 2) * 0.35
			local yaw = (now * 1.4) % (math.pi * 2)
			model:PivotTo(CFrame.new(item.base + Vector3.new(0, hover, 0)) * CFrame.Angles(0, yaw, 0))
		elseif item.kind == "sway" then
			-- Placed units bob gently around the pose they were registered with.
			local lift = math.sin(now * 2 + item.base.Position.X) * 0.12
			local yaw = math.sin(now * 1.5 + item.base.Position.Z) * 0.18
			model:PivotTo(item.base * CFrame.new(0, lift, 0) * CFrame.Angles(0, yaw, 0))
		end
	end
	-- Rainbow mutation: cycle hue across the whole body.
	if #rainbowParts > 0 then
		local hue = (now * 0.4) % 1
		for i = #rainbowParts, 1, -1 do
			local part = rainbowParts[i]
			if not part.Parent then
				table.remove(rainbowParts, i)
			else
				part.Color = Color3.fromHSV(hue, 0.85, 1)
			end
		end
	end
end)

-- The plaza statue: a giant Gunko over the fountain, built once by the world builder.
function BrainrotModels.buildStatue(entry)
	local model = BrainrotModels.build(entry, nil, 4)
	local gui = addLabel(model, entry.name, "mascot of the vault", Config.rarity(entry.rarity).color)
	gui.StudsOffset = Vector3.new(0, 14, 0) -- the body is four times normal size
	return model
end

return BrainrotModels
