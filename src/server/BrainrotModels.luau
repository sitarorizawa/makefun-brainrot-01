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

-- Phase 7 label fix: capsule name labels were overlapping and clipping because
-- every billboard used the same fixed StudsOffset and a two-line layout. Now
-- each caller passes its own vertical offset (capsules float highest, placed
-- units lower, carried units between), the text is a single short line, and a
-- running cap keeps the total visible labels bounded so a busy plaza never
-- stacks a wall of text.
local LABEL_MAX_VISIBLE = 16
local labelsCreated = 0

-- A simple billboard above a model: one short title line. `vOffset` is the
-- studs above the model the label sits at, so nearby labels never share a line.
local function addLabel(model, title, subtitle, titleColor, vOffset)
	local anchor = makePart({
		Name = "LabelAnchor",
		Size = Vector3.new(0.05, 0.05, 0.05),
		Transparency = 1,
	})
	anchor.Position = model:GetPivot().Position
	anchor.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(200, 30)
	gui.StudsOffset = Vector3.new(0, vOffset or 4.0, 0)
	gui.AlwaysOnTop = true -- names must stay readable in screenshots, even across the map
	gui.MaxDistance = 200
	gui.LightInfluence = 0
	gui.Parent = anchor

	-- Cap the total visible labels: once we hit the cap, the oldest labels
	-- stop rendering text so new ones never add to an unreadable stack.
	labelsCreated += 1
	local visible = labelsCreated <= LABEL_MAX_VISIBLE

	-- Short single-line title. If a subtitle was requested, fold it onto the
	-- same line as "title — subtitle" so nothing wraps or clips.
	local line = title
	if subtitle and subtitle ~= "" then
		line = title .. " — " .. subtitle
	end

	local main = Instance.new("TextLabel")
	main.Name = "Title"
	main.Size = UDim2.fromScale(1, 1)
	main.BackgroundTransparency = 1
	main.Font = Enum.Font.GothamBold
	main.TextScaled = true
	main.TextWrapped = false
	main.Text = visible and line or ""
	main.TextColor3 = titleColor or Color3.new(1, 1, 1)
	main.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	main.TextStrokeTransparency = 0.25
	main.TextTruncate = Enum.TextTruncate.AtEnd
	main.Parent = gui

	return gui
end

-- Face: two big eyes and a mouth, so every blob reads as a character even
-- from across the arena.
local function addFace(model, bodyColor, halfWidth, frontOffset, eyeY)
	local white = Color3.new(1, 1, 1)
	local black = Color3.fromRGB(20, 20, 20)
	for _, side in ipairs({ -1, 1 }) do
		local eye = makePart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.68, 0.68, 0.36),
			Color = white,
			Material = Enum.Material.SmoothPlastic,
		})
		eye.CFrame = model:GetPivot() * CFrame.new(side * halfWidth * 0.42, eyeY, frontOffset)
		eye.Parent = model
		local pupil = makePart({
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.34, 0.34, 0.2),
			Color = black,
			Material = Enum.Material.SmoothPlastic,
		})
		pupil.CFrame = eye.CFrame * CFrame.new(0, 0, -0.18)
		pupil.Parent = model
	end
	local mouth = makePart({
		Name = "Mouth",
		Size = Vector3.new(halfWidth * 0.9, 0.2, 0.14),
		Color = black,
		Material = Enum.Material.SmoothPlastic,
	})
	mouth.CFrame = model:GetPivot() * CFrame.new(0, eyeY - 0.8, frontOffset)
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

-- A continuous sparkle stream anchored to a model's body — the visible half
-- of a trait. Every trait wears one, so a traited unit never hides in a number.
local function addTraitSparkle(model, color, rate)
	local anchorPart = model.PrimaryPart
	if anchorPart == nil then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "TraitSparkle"
	attachment.Position = Vector3.new(0, anchorPart.Size.Y / 2, 0)
	attachment.Parent = anchorPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.Lifetime = NumberRange.new(0.4, 1.0)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(1.2, 3)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Size = NumberSequence.new(1.0)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment
end

-- Apply a character's traits to its freshly built body: colour shifts, neon,
-- a hue cycle, a floating halo — always visible on the 3D model itself.
local function applyTraits(model, traits, mutation)
	if traits == nil or #traits == 0 then
		return
	end

	local bodyParts = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart")
			and part.Name ~= "LabelAnchor"
			and part.Name ~= "Eye"
			and part.Name ~= "Pupil"
			and part.Name ~= "Mouth"
			and part.Name ~= "Halo" then
			table.insert(bodyParts, part)
		end
	end

	-- A rainbow mutation already hue-cycles the body; traits add sparkle on top.
	local hueCycling = mutation ~= nil and mutation.id == "rainbow"

	for _, trait in ipairs(traits) do
		if trait.id == "golden" then
			if not hueCycling then
				for _, part in ipairs(bodyParts) do
					part.Color = part.Color:Lerp(Color3.fromRGB(255, 215, 60), 0.55)
				end
			end
			addTraitSparkle(model, trait.color, 6)
		elseif trait.id == "glitched" then
			if not hueCycling then
				for _, part in ipairs(bodyParts) do
					part.Color = part.Color:Lerp(Color3.fromRGB(175, 95, 255), 0.5)
					part.Material = Enum.Material.Neon
				end
			end
			addTraitSparkle(model, trait.color, 8)
			local light = Instance.new("PointLight")
			light.Color = trait.color
			light.Range = 8
			light.Brightness = 1.2
			light.Parent = model.PrimaryPart
		elseif trait.id == "rainbow" then
			if not hueCycling then
				for _, part in ipairs(bodyParts) do
					part.Material = Enum.Material.Neon
					table.insert(rainbowParts, part)
				end
				hueCycling = true
			end
			addTraitSparkle(model, trait.color, 10)
		elseif trait.id == "halo" then
			-- A glowing ring floating clear of the hat, plus a soft light.
			local body = model.PrimaryPart
			local halo = makePart({
				Name = "Halo",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(3.4, 0.5, 3.4),
				Color = trait.color,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
			})
			halo.CFrame = model:GetPivot() * CFrame.new(0, (body and body.Size.Y or 3) / 2 + 1.6, 0)
			halo.CanCollide = false
			halo.Parent = model
			local light = Instance.new("PointLight")
			light.Color = trait.color
			light.Range = 8
			light.Brightness = 1.3
			light.Parent = halo
			addTraitSparkle(model, trait.color, 4)
		end
	end
end

-- Build one brainrot character as an anchored Model whose PrimaryPart is the body.
-- `scale` grows it (the plaza statue uses a big one).
function BrainrotModels.build(entry, mutation, scale, traits)
	scale = scale or 1
	local model = Instance.new("Model")
	model.Name = mutation and mutation.id ~= "none" and (mutation.name .. " " .. entry.name) or entry.name
	if traits and #traits > 0 then
		model.Name = Config.unitTitle(entry, mutation, traits)
	end

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

	-- Stubby feet and arms so the blob reads as a little creature, not a block.
	for _, side in ipairs({ -1, 1 }) do
		local foot = makePart({
			Name = "Foot",
			Size = Vector3.new(0.9, 0.7, 1.3) * scale,
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.SmoothPlastic,
		})
		foot.CFrame = CFrame.new(side * 0.8 * scale, -1.7 * scale, 0.3 * scale)
		foot.Parent = model

		local arm = makePart({
			Name = "Arm",
			Size = Vector3.new(0.55, 1.3, 0.55) * scale,
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.15),
			Material = Enum.Material.SmoothPlastic,
		})
		arm.CFrame = CFrame.new(side * (body.Size.X / 2 + 0.28 * scale), 0.1 * scale, 0)
			* CFrame.Angles(0, 0, math.rad(-14 * side))
		arm.Parent = model
	end

	addFace(model, bodyColor, body.Size.X, -body.Size.Z / 2 - 0.05, 0.5 * scale)
	addHat(model, entry.hat, bodyColor, body.Size.Y / 2)

	applyMutation(model, mutation)
	applyTraits(model, traits, mutation)
	return model
end

-- A floating capsule: a glowing rarity-colored orb with the brainrot itself
-- spinning inside a glass shell, plus a name/rate billboard. Touch to catch it.
function BrainrotModels.buildCapsule(entry, mutation, position, traits)
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
	local unit = BrainrotModels.build(entry, mutation, 0.55, traits)
	unit:PivotTo(CFrame.new(orb.Position) * CFrame.Angles(0, math.rad(180), 0))
	unit.Parent = model

	-- Capsule labels sit highest (above the floating orb + shell) and carry a
	-- compact one-line "name $rate/s · rarity" so they never wrap or clip.
	local rate = Config.unitIncome(entry, mutation, traits)
	local gui = addLabel(
		model,
		entry.name,
		string.format("$%d/s %s", rate, string.upper(string.sub(entry.rarity, 1, 1))),
		rarity.color,
		4.4
	)

	table.insert(animated, { model = model, kind = "spin", base = orb.Position })
	return model
end

-- The unit a player is carrying: the game script positions it above the
-- character each frame, so it is not registered for idle animation here.
-- Label sits just above the head, lower than a capsule label.
function BrainrotModels.buildCarried(entry, mutation, traits)
	local model = BrainrotModels.build(entry, mutation, nil, traits)
	local rarity = Config.rarity(entry.rarity)
	local rateText = string.format("$%d/s", Config.unitIncome(entry, mutation, traits))
	addLabel(model, entry.name, rateText, rarity.color, 3.4)
	return model
end

-- A walking brainrot on the red carpet: the body from build(), a non-colliding
-- touch hitbox the catch flow listens on, and a label at a high vertical offset
-- so the walker labels never overlap the capsule/carried/placed labels.
-- Returns the model plus the hitbox part (PrimaryPart) the server hooks .Touched on.
function BrainrotModels.buildWalker(entry, mutation, traits)
	local model = BrainrotModels.build(entry, mutation, nil, traits)
	local rarity = Config.rarity(entry.rarity)

	-- A non-colliding hitbox wraps the body: CanCollide=false so walkers never
	-- block the player or the tsunami, but .Touched still fires for a catch.
	local hitbox = makePart({
		Name = "WalkerHitbox",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.2, 4.2, 4.2),
		Color = rarity.color,
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	hitbox.CFrame = model:GetPivot()
	hitbox.Parent = model
	model.PrimaryPart = hitbox

	-- Label sits highest of all the unit labels so it never stacks on a
	-- capsule, carried or placed label sharing the screen.
	addLabel(model, entry.name, nil, rarity.color, Config.Walkers.labelVOffset)
	return model, hitbox
end

-- Register a walker model for its walking animation along the carpet lane.
-- `laneX` is the fixed x the walker travels at; `progress` is the starting z
-- position and `speed` is studs/sec. The walker moves +z and wraps to the
-- start when it passes +CARPET_HALF.
function BrainrotModels.startWalker(model, laneX, startZ, speed, carpetHalf)
	local item = {
		model = model,
		kind = "walk",
		laneX = laneX,
		z = startZ,
		speed = speed,
		carpetHalf = carpetHalf,
		lastTick = tick(),
	}
	table.insert(animated, item)
	return item
end

-- Stop walking a walker (called on catch). Removes it from the animation loop.
function BrainrotModels.stopWalker(model)
	for i = #animated, 1, -1 do
		if animated[i].model == model then
			table.remove(animated, i)
		end
	end
end
	-- The unit resting on a pedestal: label shows name and rate, just above the
-- unit (lower than carried/capsule so stacked placed units don't collide).
function BrainrotModels.buildPlaced(entry, mutation, traits)
	local model = BrainrotModels.build(entry, mutation, nil, traits)
	local rarity = Config.rarity(entry.rarity)
	local rate = Config.unitIncome(entry, mutation, traits)
	addLabel(model, entry.name, string.format("$%d/s", rate), rarity.color, 3.0)
	return model
end

-- Register a placed unit for its gentle idle sway. Call after positioning it:
-- the animation pivots around the pose it has right now.
function BrainrotModels.startSway(model)
	table.insert(animated, { model = model, kind = "sway", base = model:GetPivot() })
end

-- A one-shot sparkle burst at a world position. Used when a capsule is caught
-- (bigger for Rare and above) and when a rare unit is placed on a pedestal.
function BrainrotModels.sparkleAt(position, color, big)
	local anchor = makePart({
		Name = "SparkleBurst",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		Position = position,
	})
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(big and 8 or 5, big and 16 or 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(big and 2.4 or 1.5)
	emitter.Acceleration = Vector3.new(0, big and 8 or 4, 0)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = anchor
	emitter:Emit(big and 60 or 20)

	if big then
		local flash = Instance.new("PointLight")
		flash.Color = color
		flash.Range = 18
		flash.Brightness = 3
		flash.Parent = anchor
	end

	task.delay(1.6, function()
		anchor:Destroy()
	end)
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
-- placed sway, walker stride and the rainbow mutation's hue cycle.
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
		elseif item.kind == "walk" then
			-- Walkers travel one lane (fixed x) in +z, wrap to the start past the end.
			item.z += item.speed * (now - (item.lastTick or now))
			item.lastTick = now
			if item.z > item.carpetHalf then
				item.z = -item.carpetHalf
			end
			local bob = math.sin(now * 8 + item.z) * 0.18
			local sway = math.sin(now * 6 + item.z) * 0.12
			model:PivotTo(CFrame.new(item.laneX, Config.Walkers.spawnY + bob, item.z)
				* CFrame.Angles(0, sway, 0))
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
	local gui = addLabel(model, entry.name, "mascot of the vault", Config.rarity(entry.rarity).color, 14)
	return model
end

return BrainrotModels
