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
-- Active walk items for the convoy gap safety net (keyed by model for fast lookup).
local walkItems = {}

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

local function makeWedge(props)
	local part = Instance.new("WedgePart")
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
local LABEL_MAX_VISIBLE = 8
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
	gui.Size = UDim2.fromOffset(220, 36)
	gui.StudsOffset = Vector3.new(0, vOffset or 4.0, 0)
	gui.AlwaysOnTop = true -- readable up close; MaxDistance keeps far labels off-screen
	gui.MaxDistance = 60
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
	-- Only truncate text longer than ~30 characters so the wider panel never clips.
	if #line > 30 then
		line = string.sub(line, 1, 27) .. "…"
	end

	local main = Instance.new("TextLabel")
	main.Name = "Title"
	main.Size = UDim2.fromScale(1, 1)
	main.BackgroundTransparency = 1
	main.Font = Enum.Font.GothamBold
	main.TextScaled = false
	main.TextSize = 12
	main.TextWrapped = false
	main.Text = visible and line or ""
	main.TextColor3 = titleColor or Color3.new(1, 1, 1)
	main.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	main.TextStrokeTransparency = 0.25
	main.TextTruncate = Enum.TextTruncate.AtEnd
	main.Parent = gui

	return gui
end

-- Phase 9 redesign helpers are defined above; the old addFace/addHat are
-- no longer called — they were replaced by addHeadFace and addHeadHat which
-- accept exact head-center coordinates instead of auto-deriving from the body.

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

-- Phase 9 redesign: every brainrot is an ANIMAL HEAD fused with an UNRELATED
-- OBJECT as the body, plus big eyes/mouth and one signature prop (crypto theme).
-- The builders below share legs/arms/face/prop helpers but each id fashions its
-- own body+head so the twelve characters read as distinct creatures, not blobs.
-- Everything is anchored, non-colliding, and parented to a Model whose
-- PrimaryPart is the fused-object body. `scale` grows it (statue uses a big one).

local BLACK = Color3.fromRGB(20, 20, 20)
local WHITE = Color3.new(1, 1, 1)

-- Two eyes (white ball + black pupil) and a mouth, placed on the head front.
-- `cx,cy,cz` is the head center; `faceZ` is how far in front of center to put
-- the face; `spread` is half the eye distance; `eyeY` offsets eyes above mouth.
local function addHeadFace(model, cx, cy, cz, faceZ, spread, eyeY, scale)
	for _, side in ipairs({ -1, 1 }) do
		local eye = makePart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 0.4) * scale,
			Color = WHITE,
			Material = Enum.Material.SmoothPlastic,
		})
		eye.CFrame = CFrame.new(cx + side * spread, cy + eyeY, cz + faceZ)
		eye.Parent = model
		local pupil = makePart({
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.45, 0.45, 0.22) * scale,
			Color = BLACK,
			Material = Enum.Material.SmoothPlastic,
		})
		pupil.CFrame = eye.CFrame * CFrame.new(0, 0, -0.14 * scale)
		pupil.Parent = model
	end
	local mouth = makePart({
		Name = "Mouth",
		Size = Vector3.new(spread * 1.8, 0.18 * scale, 0.12 * scale),
		Color = BLACK,
		Material = Enum.Material.SmoothPlastic,
	})
	mouth.CFrame = CFrame.new(cx, cy + eyeY - 0.7 * scale, cz + faceZ)
	mouth.Parent = model
end

-- Two stubby legs (or long thin ones for tall shapes) below the body.
local function addLegs(model, body, bodyColor, tall, scale)
	local legH = (tall and 1.8 or 1.6) * scale
	local legW = (tall and 0.9 or 1.1) * scale
	for _, side in ipairs({ -1, 1 }) do
		local leg = makePart({
			Name = "Leg",
			Size = Vector3.new(legW, legH, legW),
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.3),
			Material = Enum.Material.SmoothPlastic,
		})
		leg.CFrame = CFrame.new(side * 0.85 * scale, -body.Size.Y / 2 - legH / 2, 0.2 * scale)
		leg.Parent = model
	end
end

-- Two thin side arms. Returns the two arm CFrames so a prop can be welded to one.
local function addArms(model, body, bodyColor, scale)
	local arms = {}
	for _, side in ipairs({ -1, 1 }) do
		local arm = makePart({
			Name = "Arm",
			Size = Vector3.new(0.45, 1.2, 0.45) * scale,
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.15),
			Material = Enum.Material.SmoothPlastic,
		})
		arm.CFrame = CFrame.new(side * (body.Size.X / 2 + 0.24 * scale), 0.2 * scale, 0)
			* CFrame.Angles(0, 0, math.rad(-12 * side))
		arm.Parent = model
		arms[side] = arm
	end
	return arms
end

-- The hat variants (antenna / cap / horns / crown) ride on top of the head.
local function addHeadHat(model, hat, topY, scale)
	if hat == "none" then
		return
	end
	if hat == "antenna" then
		local stem = makePart({
			Name = "Antenna",
			Size = Vector3.new(0.16, 1.0, 0.16) * scale,
			Color = Color3.fromRGB(60, 60, 70),
			Material = Enum.Material.Metal,
		})
		stem.CFrame = CFrame.new(0, topY + 0.5 * scale, 0)
		stem.Parent = model
		local bulb = makePart({
			Name = "AntennaBulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.45, 0.45, 0.45) * scale,
			Color = Color3.fromRGB(255, 90, 90),
			Material = Enum.Material.Neon,
		})
		bulb.CFrame = CFrame.new(0, topY + 1.1 * scale, 0)
		bulb.Parent = model
	elseif hat == "cap" then
		local brim = makePart({
			Name = "CapBrim",
			Size = Vector3.new(2.0, 0.18, 0.9) * scale,
			Color = Color3.fromRGB(40, 40, 45),
			Material = Enum.Material.Fabric,
		})
		brim.CFrame = CFrame.new(0, topY + 0.12 * scale, -0.8 * scale)
		brim.Parent = model
		local dome = makePart({
			Name = "CapDome",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.7, 1.0, 1.7) * scale,
			Color = Color3.fromRGB(200, 60, 60),
			Material = Enum.Material.Fabric,
		})
		dome.CFrame = CFrame.new(0, topY + 0.3 * scale, 0)
		dome.Parent = model
	elseif hat == "horns" then
		for _, side in ipairs({ -1, 1 }) do
			local horn = makePart({
				Name = "Horn",
				Size = Vector3.new(0.28, 0.85, 0.28) * scale,
				Color = Color3.fromRGB(240, 235, 220),
				Material = Enum.Material.SmoothPlastic,
			})
			horn.CFrame = CFrame.new(side * 0.8 * scale, topY + 0.4 * scale, 0)
				* CFrame.Angles(0, 0, math.rad(-18 * side))
			horn.Parent = model
		end
	elseif hat == "crown" then
		local band = makePart({
			Name = "Crown",
			Size = Vector3.new(1.6, 0.45, 1.6) * scale,
			Color = Color3.fromRGB(255, 200, 40),
			Material = Enum.Material.Metal,
		})
		band.CFrame = CFrame.new(0, topY + 0.25 * scale, 0)
		band.Parent = model
		for _, offset in ipairs({ -0.55, 0, 0.55 }) do
			local point = makePart({
				Name = "CrownPoint",
				Size = Vector3.new(0.28, 0.42, 0.28) * scale,
				Color = Color3.fromRGB(255, 200, 40),
				Material = Enum.Material.Metal,
			})
			point.CFrame = CFrame.new(offset * scale, topY + 0.65 * scale, 0)
			point.Parent = model
		end
	end
end

-- Each builder returns the body Part (PrimaryPart) and reports its top Y so the
-- head and hat can stack on it. All coordinates are relative to the model pivot
-- at the origin (the body center sits at y=0).
local builders = {}

-- 1. Satoshi Nekotto — HUMANISED crypto-degen cat: hoodie, sunglasses, grin,
-- chain, sneakers, Bitcoin coin backpack, pickaxe. Full blocky voxel aesthetic.
builders["satoshi-nekotto"] = function(model, bodyColor, scale)
	local CAT_ORANGE    = Color3.fromRGB(255, 165, 60)
	local HOODIE_ORANGE = Color3.fromRGB(255, 140, 0)
	local SNEAKER_WHITE = Color3.fromRGB(255, 255, 255)
	local RED           = Color3.fromRGB(220, 30, 30)
	local DARK_SOLE     = Color3.fromRGB(30, 30, 30)
	local GLASSES_BLACK = Color3.fromRGB(15, 15, 15)
	local COIN_GOLD     = Color3.fromRGB(255, 200, 40)
	local CHAIN_GOLD    = Color3.fromRGB(255, 215, 0)
	local WOOD_BROWN    = Color3.fromRGB(100, 60, 20)
	local SILVER        = Color3.fromRGB(190, 190, 200)
	local CAP_DOME_GOLD = Color3.fromRGB(200, 140, 40)

	-- === BODY — orange hoodie ===
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2.0, 3.2, 1.5) * scale,
		Color = HOODIE_ORANGE,
		Material = Enum.Material.SmoothPlastic,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model

	-- "HODL" dark strip on the hoodie front.
	local hodl = makePart({
		Name = "HodlStrip",
		Size = Vector3.new(1.2, 0.4, 0.08) * scale,
		Color = Color3.fromRGB(20, 20, 20),
		Material = Enum.Material.SmoothPlastic,
	})
	hodl.CFrame = CFrame.new(0, 0.1 * scale, body.Size.Z / 2 + 0.04 * scale)
	hodl.Parent = model

	-- Gold chain: thin cylinder ring around the neck, rotated horizontal.
	local chain = makePart({
		Name = "Chain",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 2.4, 2.4) * scale,
		Color = CHAIN_GOLD,
		Material = Enum.Material.Metal,
	})
	chain.CFrame = CFrame.new(0, body.Size.Y / 2 - 0.6 * scale, 0)
		* CFrame.Angles(math.rad(90), 0, 0)
	chain.Parent = model

	-- === HEAD — large blocky cat head ===
	local headY = body.Size.Y / 2 + 2.2
	local head = makePart({
		Name = "Head",
		Size = Vector3.new(3.5, 3.5, 3.0) * scale,
		Color = CAT_ORANGE,
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0)
	head.Parent = model

	local faceZ = head.Size.Z / 2 -- front-surface world Z

	-- Black sunglasses: two chunky panels with a thin bridge ("thug life").
	for _, side in ipairs({ -1, 1 }) do
		local lens = makePart({
			Name = "Sunglass",
			Size = Vector3.new(1.2, 1.2, 0.3) * scale,
			Color = GLASSES_BLACK,
			Material = Enum.Material.SmoothPlastic,
		})
		lens.CFrame = CFrame.new(side * 0.85 * scale, headY + 0.12 * scale, faceZ + 0.15 * scale)
		lens.Parent = model
	end
	local bridge = makePart({
		Name = "SunglassBridge",
		Size = Vector3.new(0.55, 0.18, 0.3) * scale,
		Color = GLASSES_BLACK,
		Material = Enum.Material.SmoothPlastic,
	})
	bridge.CFrame = CFrame.new(0, headY + 0.12 * scale, faceZ + 0.15 * scale)
	bridge.Parent = model

	-- Thick eyebrows floating above the glasses.
	for _, side in ipairs({ -1, 1 }) do
		local brow = makePart({
			Name = "Eyebrow",
			Size = Vector3.new(1.4, 0.3, 0.3) * scale,
			Color = GLASSES_BLACK,
			Material = Enum.Material.SmoothPlastic,
		})
		brow.CFrame = CFrame.new(side * 0.85 * scale, headY + 1.05 * scale, faceZ + 0.1 * scale)
		brow.Parent = model
	end

	-- Wide grinning mouth :D — bright red box.
	local mouth = makePart({
		Name = "Mouth",
		Size = Vector3.new(2.4, 1.2, 0.3) * scale,
		Color = RED,
		Material = Enum.Material.SmoothPlastic,
	})
	mouth.CFrame = CFrame.new(0, headY - 0.7 * scale, faceZ + 0.15 * scale)
	mouth.Parent = model

	-- Cat ears: wedge triangles on the top corners.
	for _, side in ipairs({ -1, 1 }) do
		local ear = makeWedge({
			Name = "Ear",
			Size = Vector3.new(0.8, 1.0, 0.5) * scale,
			Color = CAT_ORANGE,
			Material = Enum.Material.SmoothPlastic,
		})
		ear.CFrame = CFrame.new(side * 1.4 * scale, headY + head.Size.Y / 2 - 0.4 * scale, 0)
			* CFrame.Angles(0, 0, math.rad(-20 * side))
		ear.Parent = model
	end

	-- Baseball cap.
	local capTop = headY + head.Size.Y / 2
	local brim = makePart({
		Name = "CapBrim",
		Size = Vector3.new(3.0, 0.3, 2.2) * scale,
		Color = CAT_ORANGE,
		Material = Enum.Material.SmoothPlastic,
	})
	brim.CFrame = CFrame.new(0, capTop - 0.15 * scale, faceZ * 0.55)
	brim.Parent = model

	local dome = makePart({
		Name = "CapDome",
		Size = Vector3.new(2.2, 1.0, 2.2) * scale,
		Color = CAP_DOME_GOLD,
		Material = Enum.Material.SmoothPlastic,
	})
	dome.CFrame = CFrame.new(0, capTop + 0.25 * scale, 0)
	dome.Parent = model

	-- "₿" decal on the cap dome (dark marker box).
	local btcMark = makePart({
		Name = "BtcMark",
		Size = Vector3.new(0.6, 0.55, 0.1) * scale,
		Color = GLASSES_BLACK,
		Material = Enum.Material.SmoothPlastic,
	})
	btcMark.CFrame = CFrame.new(0, capTop + 0.25 * scale, dome.Size.Z / 2 + 0.05 * scale)
	btcMark.Parent = model

	-- === ARMS — box arms hanging from body sides, ending in box hands ===
	local arms = {}
	for _, side in ipairs({ -1, 1 }) do
		local arm = makePart({
			Name = "Arm",
			Size = Vector3.new(0.8, 2.8, 0.8) * scale,
			Color = HOODIE_ORANGE,
			Material = Enum.Material.SmoothPlastic,
		})
		arm.CFrame = CFrame.new(side * (body.Size.X / 2 + 0.4 * scale), 0.1 * scale, 0)
			* CFrame.Angles(0, 0, math.rad(-10 * side))
		arm.Parent = model

		local hand = makePart({
			Name = "Hand",
			Size = Vector3.new(0.9, 0.9, 0.9) * scale,
			Color = CAT_ORANGE,
			Material = Enum.Material.SmoothPlastic,
		})
		hand.CFrame = arm.CFrame * CFrame.new(0, -arm.Size.Y / 2 - 0.45 * scale, 0)
		hand.Parent = model
		arms[side] = arm
	end

	-- === LEGS — box legs with white sneakers ===
	for _, side in ipairs({ -1, 1 }) do
		local legX = side * 0.75 * scale
		local legY = -body.Size.Y / 2 - 1.25 * scale
		local leg = makePart({
			Name = "Leg",
			Size = Vector3.new(1.0, 2.5, 1.0) * scale,
			Color = Color3.fromRGB(40, 40, 45),
			Material = Enum.Material.SmoothPlastic,
		})
		leg.CFrame = CFrame.new(legX, legY, 0.1 * scale)
		leg.Parent = model

		-- Sneaker body sits exactly at the leg bottom.
		local sneakerY = legY - leg.Size.Y / 2 - 0.35 * scale
		local sneaker = makePart({
			Name = "Sneaker",
			Size = Vector3.new(1.3, 0.7, 2.0) * scale,
			Color = SNEAKER_WHITE,
			Material = Enum.Material.SmoothPlastic,
		})
		sneaker.CFrame = CFrame.new(legX, sneakerY, 0.15 * scale)
		sneaker.Parent = model

		-- Red accent stripe on the outer side.
		local stripe = makePart({
			Name = "SneakerStripe",
			Size = Vector3.new(0.12, 0.4, 1.8) * scale,
			Color = RED,
			Material = Enum.Material.SmoothPlastic,
		})
		stripe.CFrame = CFrame.new(legX + side * sneaker.Size.X / 2, sneakerY, 0.15 * scale)
		stripe.Parent = model

		-- Dark thick sole.
		local sole = makePart({
			Name = "SneakerSole",
			Size = Vector3.new(1.4, 0.3, 2.2) * scale,
			Color = DARK_SOLE,
			Material = Enum.Material.SmoothPlastic,
		})
		sole.CFrame = CFrame.new(legX, sneakerY - sneaker.Size.Y / 2 - 0.15 * scale, 0.15 * scale)
		sole.Parent = model
	end

	-- === CRYPTO BACKPACK — standing Bitcoin coin behind the character ===
	local coin = makePart({
		Name = "CoinBackpack",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 3.2, 3.2) * scale, -- axis = X, thin standing coin
		Color = COIN_GOLD,
		Material = Enum.Material.Metal,
	})
	-- Rotate so the coin faces backward (flat face perpendicular to Z).
	coin.CFrame = CFrame.new(0, 0, -body.Size.Z / 2 - 1.65 * scale)
		* CFrame.Angles(0, math.rad(90), 0)
	coin.Parent = model

	-- Dark "₿" mark disc on the coin's outward face.
	local coinMark = makePart({
		Name = "CoinMark",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, 1.2, 1.2) * scale,
		Color = Color3.fromRGB(160, 110, 0),
		Material = Enum.Material.Metal,
	})
	coinMark.CFrame = coin.CFrame * CFrame.new(0, 0, -coin.Size.Y / 2 - 0.03 * scale)
	coinMark.Parent = model

	-- === PROP — pickaxe in right hand (side=1) ===
	local pickHandle = makePart({
		Name = "Prop",
		Size = Vector3.new(0.15, 2.5, 0.15) * scale,
		Color = WOOD_BROWN,
		Material = Enum.Material.Wood,
	})
	pickHandle.CFrame = arms[1].CFrame
		* CFrame.new(0, -arms[1].Size.Y / 2 - 0.45 * scale - 1.25 * scale, 0)
	pickHandle.Parent = model

	-- Two wedge blades at the pickaxe head.
	for _, bside in ipairs({ -1, 1 }) do
		local blade = makeWedge({
			Name = "PickBlade",
			Size = Vector3.new(0.8, 0.3, 0.3) * scale,
			Color = SILVER,
			Material = Enum.Material.Metal,
		})
		blade.CFrame = pickHandle.CFrame
			* CFrame.new(bside * 0.22 * scale, -1.25 * scale, 0)
			* CFrame.Angles(0, math.rad(90), math.rad(-40 * bside))
		blade.Parent = model
	end

	return body
end

-- 2. Vitalik Froghini — frog head + ETH diamond body, gas meter on back.
builders["vitalik-froghini"] = function(model, bodyColor, scale)
	-- ETH diamond body: elongated ball standing upright.
	local body = makePart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.5, 3.5, 2.5) * scale,
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Diamond facet on the front.
	local diamond = makePart({
		Name = "Diamond",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 2.2, 0.3) * scale,
		Color = Color3.fromRGB(220, 240, 255),
		Material = Enum.Material.Glass,
	})
	diamond.CFrame = CFrame.new(0, 0, -body.Size.Z / 2 - 0.05 * scale)
	diamond.Parent = model
	-- Gas meter dial on the back.
	local meter = makePart({
		Name = "GasMeter",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 1.4, 1.4) * scale,
		Color = Color3.fromRGB(70, 80, 90),
		Material = Enum.Material.Metal,
	})
	meter.CFrame = CFrame.new(0, 0.2 * scale, body.Size.Z / 2) * CFrame.Angles(0, 0, math.rad(90))
	meter.Parent = model

	addLegs(model, body, bodyColor, false, scale)
	addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + 0.6 * scale
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 2.0, 2.8) * scale,
		Color = bodyColor:Lerp(Color3.fromRGB(90, 180, 90), 0.4),
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0)
	head.Parent = model
	-- Frog eye bumps on top.
	for _, side in ipairs({ -1, 1 }) do
		local bump = makePart({
			Name = "EyeBump",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.0, 0.6, 1.0) * scale,
			Color = head.Color,
			Material = Enum.Material.SmoothPlastic,
		})
		bump.CFrame = CFrame.new(side * 0.7 * scale, headY + 0.6 * scale, 0)
		bump.Parent = model
	end
	addHeadFace(model, 0, headY, 0, 1.4 * scale, 0.65 * scale, 0.3 * scale, scale)
	addHeadHat(model, "none", headY + head.Size.Y / 2, scale)
	return body
end

-- 3. Schnorpellino — duck head + sneaker body (red), shoelace arms.
builders["schnorpellino"] = function(model, bodyColor, scale)
	-- Sneaker body: a shoe-shaped block standing upright, sole on the bottom.
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2.5, 2.0, 3.5) * scale,
		Color = Color3.fromRGB(220, 40, 40),
		Material = Enum.Material.Fabric,
	})
	body.CFrame = CFrame.new(0, 0.5 * scale, 0)
	body.Parent = model
	-- Darker sole under the sneaker.
	local sole = makePart({
		Name = "Sole",
		Size = Vector3.new(2.7, 0.6, 3.7) * scale,
		Color = Color3.fromRGB(60, 20, 20),
		Material = Enum.Material.SmoothPlastic,
	})
	sole.CFrame = CFrame.new(0, -body.Size.Y / 2 - 0.3 * scale, 0.1 * scale)
	sole.Parent = model
	-- White swoosh stripe.
	local swoosh = makePart({
		Name = "Swoosh",
		Size = Vector3.new(0.2, 1.2, 2.4) * scale,
		Color = WHITE,
		Material = Enum.Material.Fabric,
	})
	swoosh.CFrame = CFrame.new(body.Size.X / 2, 0.5 * scale, 0) * CFrame.Angles(0, 0, math.rad(-20))
	swoosh.Parent = model

	addLegs(model, body, bodyColor, true, scale)
	-- Shoelace arms: thin crossed laces on the sides.
	for _, side in ipairs({ -1, 1 }) do
		local lace = makePart({
			Name = "Arm",
			Size = Vector3.new(0.12, 1.2, 0.12) * scale,
			Color = WHITE,
			Material = Enum.Material.Fabric,
		})
		lace.CFrame = CFrame.new(side * (body.Size.X / 2 + 0.1 * scale), 0.8 * scale, 0)
			* CFrame.Angles(0, 0, math.rad(-30 * side))
		lace.Parent = model
	end

	local headY = body.Position.Y + body.Size.Y / 2 + 1.6 * scale
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 2.8, 2.8) * scale,
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0)
	head.Parent = model
	-- Orange duck beak (wedge).
	local beak = makePart({
		Name = "Beak",
		Size = Vector3.new(1.0, 0.6, 1.2) * scale,
		Color = Color3.fromRGB(255, 140, 0),
		Material = Enum.Material.SmoothPlastic,
	})
	beak.CFrame = CFrame.new(0, headY - 0.4 * scale, 1.4 * scale) * CFrame.Angles(math.rad(20), 0, 0)
	beak.Parent = model
	addHeadFace(model, 0, headY, 0, 1.4 * scale, 0.6 * scale, 0.25 * scale, scale)
	addHeadHat(model, "none", headY + head.Size.Y / 2, scale)
	return body
end

-- 4. Wumbino Antennini — toad head + portable radio body, blinking antenna.
builders["wumbino-antennini"] = function(model, bodyColor, scale)
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2.2, 2.8, 2.2) * scale,
		Color = Color3.fromRGB(80, 70, 60),
		Material = Enum.Material.SmoothPlastic,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Radio speaker grill.
	local speaker = makePart({
		Name = "Speaker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 1.8, 1.8) * scale,
		Color = Color3.fromRGB(40, 40, 40),
		Material = Enum.Material.Metal,
	})
	speaker.CFrame = CFrame.new(0, -0.2 * scale, -body.Size.Z / 2) * CFrame.Angles(0, 0, math.rad(90))
	speaker.Parent = model
	-- Tuning dial with knob.
	local dial = makePart({
		Name = "Dial",
		Size = Vector3.new(1.8, 0.5, 0.1) * scale,
		Color = Color3.fromRGB(255, 220, 80),
		Material = Enum.Material.Neon,
	})
	dial.CFrame = CFrame.new(0, 0.7 * scale, -body.Size.Z / 2)
	dial.Parent = model
	local dialKnob = makePart({
		Name = "DialKnob",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 0.5, 0.5) * scale,
		Color = Color3.fromRGB(180, 180, 190),
		Material = Enum.Material.Metal,
	})
	dialKnob.CFrame = CFrame.new(0.9 * scale, 0.7 * scale, -body.Size.Z / 2) * CFrame.Angles(0, 0, math.rad(90))
	dialKnob.Parent = model

	addLegs(model, body, bodyColor, false, scale)
	addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + 0.8 * scale
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 2.0, 2.8) * scale,
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0)
	head.Parent = model
	addHeadFace(model, 0, headY, 0, 1.4 * scale, 0.6 * scale, 0.25 * scale, scale)
	addHeadHat(model, "antenna", headY + head.Size.Y / 2, scale)
	return body
end

-- 5. Flibberino Pizzarolo — chicken head + pizza box body, pizza slice hat.
builders["flibberino-pizza"] = function(model, bodyColor, scale)
	-- Pizza box body: flat, wide box with yellow cheese top.
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2.8, 0.6, 2.8) * scale,
		Color = Color3.fromRGB(190, 120, 60),
		Material = Enum.Material.Cardboard,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Pizza surface (cheese + pepperoni bumps) — yellow top.
	local cheese = makePart({
		Name = "Cheese",
		Size = Vector3.new(2.6, 0.25, 2.6) * scale,
		Color = Color3.fromRGB(255, 210, 120),
		Material = Enum.Material.SmoothPlastic,
	})
	cheese.CFrame = CFrame.new(0, body.Size.Y / 2, 0)
	cheese.Parent = model
	for _, p in ipairs({ { -0.7, -0.5 }, { 0.6, 0.3 }, { -0.2, 0.8 }, { 0.8, -0.7 } }) do
		local pep = makePart({
			Name = "Pepperoni",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.22, 0.5) * scale,
			Color = Color3.fromRGB(200, 50, 40),
			Material = Enum.Material.SmoothPlastic,
		})
		pep.CFrame = CFrame.new(p[1] * scale, body.Size.Y / 2 + 0.12 * scale, p[2] * scale)
		pep.Parent = model
	end

	addLegs(model, body, bodyColor, false, scale)
	addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + 2.0 * scale
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 2.8, 2.8) * scale,
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0)
	head.Parent = model
	-- Red comb on top.
	local comb = makePart({
		Name = "Comb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.5, 0.8) * scale,
		Color = Color3.fromRGB(220, 40, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	comb.CFrame = CFrame.new(0, headY + 1.3 * scale, -0.2 * scale)
	comb.Parent = model
	-- Orange beak.
	local beak = makePart({
		Name = "Beak",
		Size = Vector3.new(0.6, 0.5, 1.0) * scale,
		Color = Color3.fromRGB(255, 150, 0),
		Material = Enum.Material.SmoothPlastic,
	})
	beak.CFrame = CFrame.new(0, headY - 0.3 * scale, 1.4 * scale)
	beak.Parent = model
	addHeadFace(model, 0, headY, 0, 1.4 * scale, 0.6 * scale, 0.3 * scale, scale)
	-- Pizza slice hat (triangle wedge) replaces the generic cap silhouette.
	local slice = makeWedge({
		Name = "CapDome",

		Size = Vector3.new(1.0, 1.2, 1.2) * scale,
		Color = Color3.fromRGB(255, 200, 100),
		Material = Enum.Material.SmoothPlastic,
	})
	slice.CFrame = CFrame.new(0, headY + 1.6 * scale, 0)
	slice.Parent = model
	return body
end

-- 6. Grumbolo Melonotto — gorilla head + watermelon body, seed armor.
builders["grumbolo-melon"] = function(model, bodyColor, scale)
	-- Watermelon body: large round ball.
	local body = makePart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.0, 3.0, 3.0) * scale,
		Color = Color3.fromRGB(40, 120, 50),
		Material = Enum.Material.SmoothPlastic,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Lighter green stripes around the melon.
	for _, off in ipairs({ -0.9, -0.3, 0.3, 0.9 }) do
		local stripe = makePart({
			Name = "MelonStripe",
			Size = Vector3.new(3.1, 0.3, 3.1) * scale,
			Color = Color3.fromRGB(90, 180, 90),
			Material = Enum.Material.SmoothPlastic,
		})
		stripe.CFrame = CFrame.new(0, off * scale, 0)
		stripe.Parent = model
	end
	-- Seed armor: black seeds studded on the front.
	for _, s in ipairs({ { -0.6, 0.4, -1.5 }, { 0.5, -0.2, -1.5 }, { 0.1, 0.9, -1.5 }, { -0.9, -0.6, -1.4 } }) do
		local seed = makePart({
			Name = "Seed",
			Size = Vector3.new(0.22, 0.4, 0.1) * scale,
			Color = BLACK,
			Material = Enum.Material.SmoothPlastic,
		})
		seed.CFrame = CFrame.new(s[1] * scale, s[2] * scale, s[3] * scale)
		seed.Parent = model
	end

	addLegs(model, body, bodyColor, true, scale)
	addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + 1.0 * scale
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 3.0, 2.8) * scale,
		Color = Color3.fromRGB(70, 50, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0.2 * scale)
	head.Parent = model
	-- Gorilla brow ridge.
	local brow = makePart({
		Name = "Brow",
		Size = Vector3.new(2.2, 0.5, 0.3) * scale,
		Color = Color3.fromRGB(50, 35, 25),
		Material = Enum.Material.SmoothPlastic,
	})
	brow.CFrame = CFrame.new(0, headY + 0.5 * scale, 1.1 * scale)
	brow.Parent = model
	addHeadFace(model, 0, headY, 0.2 * scale, 1.4 * scale, 0.6 * scale, 0.15 * scale, scale)
	addHeadHat(model, "horns", headY + head.Size.Y / 2, scale)
	return body
end

-- 7. Zonketto Limonele — shark head + giant lemon body, yellow fins.
builders["zonketto-limone"] = function(model, bodyColor, scale)
	-- Lemon body: large slightly-tall ball.
	local body = makePart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 3.2, 2.8) * scale,
		Color = Color3.fromRGB(255, 230, 60),
		Material = Enum.Material.SmoothPlastic,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Lemon texture bumps (subtle).
	for _, off in ipairs({ { 0.6, 0.8, 1.3 }, { -0.7, -0.3, 1.2 }, { 0.2, -0.9, 1.4 } }) do
		local bump = makePart({
			Name = "LemonBump",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.3, 0.3, 0.1) * scale,
			Color = Color3.fromRGB(255, 240, 120),
			Material = Enum.Material.SmoothPlastic,
		})
		bump.CFrame = CFrame.new(off[1] * scale, off[2] * scale, off[3] * scale)
		bump.Parent = model
	end

	addLegs(model, body, bodyColor, false, scale)
	-- Yellow fins as arms.
	for _, side in ipairs({ -1, 1 }) do
		local fin = makeWedge({
			Name = "Arm",

			Size = Vector3.new(0.5, 1.6, 0.9) * scale,
			Color = Color3.fromRGB(255, 240, 100),
			Material = Enum.Material.SmoothPlastic,
		})
		fin.CFrame = CFrame.new(side * (body.Size.X / 2 + 0.1 * scale), 0.2 * scale, 0)
			* CFrame.Angles(0, 0, math.rad(90 * side))
		fin.Parent = model
	end

	local headY = body.Size.Y / 2 + 0.8 * scale
	local head = makePart({
		Name = "Head",
		Size = Vector3.new(2.8, 2.4, 3.2) * scale,
		Color = Color3.fromRGB(150, 170, 180),
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0.4 * scale)
	head.Parent = model
	-- Shark dorsal fin on top.
	local dorsal = makeWedge({
		Name = "Dorsal",

		Size = Vector3.new(0.4, 1.4, 1.2) * scale,
		Color = Color3.fromRGB(130, 150, 160),
		Material = Enum.Material.SmoothPlastic,
	})
	dorsal.CFrame = CFrame.new(0, headY + 1.1 * scale, -0.3 * scale)
	dorsal.Parent = model
	-- Rows of teeth under the mouth.
	local teeth = makePart({
		Name = "Teeth",
		Size = Vector3.new(1.8, 0.3, 0.2) * scale,
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	})
	teeth.CFrame = CFrame.new(0, headY - 0.8 * scale, 1.6 * scale)
	teeth.Parent = model
	addHeadFace(model, 0, headY, 0.4 * scale, 1.6 * scale, 0.6 * scale, 0.35 * scale, scale)
	addHeadHat(model, "crown", headY + head.Size.Y / 2, scale)
	return body
end

-- 8. Binglebop Macchinino — hamster head + arcade machine body, joystick prop.
builders["binglebop-arcade"] = function(model, bodyColor, scale)
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2.0, 3.0, 2.5) * scale,
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Arcade screen.
	local screen = makePart({
		Name = "Screen",
		Size = Vector3.new(1.5, 1.2, 0.15) * scale,
		Color = Color3.fromRGB(40, 200, 255),
		Material = Enum.Material.Neon,
	})
	screen.CFrame = CFrame.new(0, 0.5 * scale, -body.Size.Z / 2)
	screen.Parent = model
	-- Control panel.
	local panel = makePart({
		Name = "Panel",
		Size = Vector3.new(1.8, 0.3, 0.6) * scale,
		Color = Color3.fromRGB(40, 40, 45),
		Material = Enum.Material.SmoothPlastic,
	})
	panel.CFrame = CFrame.new(0, -0.6 * scale, -body.Size.Z / 2 + 0.35 * scale)
	panel.Parent = model

	addLegs(model, body, bodyColor, false, scale)
	local arms = addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + 0.6 * scale
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 2.4, 2.8) * scale,
		Color = Color3.fromRGB(255, 220, 180),
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0)
	head.Parent = model
	-- Hamster round ears.
	for _, side in ipairs({ -1, 1 }) do
		local ear = makePart({
			Name = "Ear",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 0.4) * scale,
			Color = Color3.fromRGB(220, 170, 140),
			Material = Enum.Material.SmoothPlastic,
		})
		ear.CFrame = CFrame.new(side * 0.9 * scale, headY + 1.1 * scale, 0)
		ear.Parent = model
	end
	addHeadFace(model, 0, headY, 0, 1.4 * scale, 0.6 * scale, 0.25 * scale, scale)
	addHeadHat(model, "antenna", headY + head.Size.Y / 2, scale)

	-- Joystick prop in the right hand.
	local stick = makePart({
		Name = "Prop",
		Size = Vector3.new(0.16, 1.0, 0.16) * scale,
		Color = Color3.fromRGB(30, 30, 35),
		Material = Enum.Material.SmoothPlastic,
	})
	stick.CFrame = arms[1].CFrame * CFrame.new(0, -0.5 * scale, 0)
	stick.Parent = model
	local knob = makePart({
		Name = "PropHead",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.4, 0.4, 0.4) * scale,
		Color = Color3.fromRGB(255, 60, 60),
		Material = Enum.Material.Neon,
	})
	knob.CFrame = stick.CFrame * CFrame.new(0, -0.5 * scale, 0)
	knob.Parent = model
	return body
end

-- 9. Crungus Funghetto — deer head + giant mushroom body, glowing spores.
builders["crungus-funghetto"] = function(model, bodyColor, scale)
	-- Mushroom stem body (cylinder).
	local body = makePart({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 3.0, 1.6) * scale,
		Color = Color3.fromRGB(240, 235, 220),
		Material = Enum.Material.SmoothPlastic,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Mushroom cap (the colored top, fused as the body's object).
	local cap = makePart({
		Name = "Cap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 2.2, 2.8) * scale,
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	cap.CFrame = CFrame.new(0, body.Size.Y / 2 + 0.2 * scale, 0)
	cap.Parent = model
	-- White spots on the cap.
	for _, s in ipairs({ { -0.7, 1.8, -0.4 }, { 0.6, 2.0, 0.3 }, { 0.1, 2.2, -0.8 }, { -0.3, 1.6, 0.9 } }) do
		local spot = makePart({
			Name = "Spore",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.2, 0.5) * scale,
			Color = WHITE,
			Material = Enum.Material.Neon,
		})
		spot.CFrame = CFrame.new(s[1] * scale, s[2] * scale, s[3] * scale)
		spot.Parent = model
	end

	addLegs(model, body, bodyColor, true, scale)
	addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + cap.Size.Y / 2 + 0.8 * scale
	local head = makePart({
		Name = "Head",
		Size = Vector3.new(2.8, 2.6, 2.8) * scale,
		Color = Color3.fromRGB(160, 120, 80),
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0.2 * scale)
	head.Parent = model
	-- Deer snout (wedge).
	local snout = makeWedge({
		Name = "Snout",

		Size = Vector3.new(0.8, 0.8, 1.2) * scale,
		Color = Color3.fromRGB(120, 90, 60),
		Material = Enum.Material.SmoothPlastic,
	})
	snout.CFrame = CFrame.new(0, headY - 0.4 * scale, 1.6 * scale)
	snout.Parent = model
	addHeadFace(model, 0, headY, 0.2 * scale, 1.4 * scale, 0.55 * scale, 0.25 * scale, scale)
	addHeadHat(model, "cap", headY + head.Size.Y / 2, scale)
	return body
end

-- 10. Fartellone Bombetta — pig head + round bomb body, lit fuse on back.
builders["fartellone-bomb"] = function(model, bodyColor, scale)
	-- Bomb body: large round ball.
	local body = makePart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.0, 3.2, 3.0) * scale,
		Color = Color3.fromRGB(40, 40, 45),
		Material = Enum.Material.Metal,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Highlight band on the bomb.
	local band = makePart({
		Name = "Band",
		Size = Vector3.new(3.1, 0.3, 3.1) * scale,
		Color = bodyColor,
		Material = Enum.Material.Neon,
	})
	band.CFrame = CFrame.new(0, 0, 0)
	band.Parent = model
	-- Fuse cylinder on top-back.
	local fuse = makePart({
		Name = "Fuse",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 0.3, 0.3) * scale,
		Color = Color3.fromRGB(90, 70, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	fuse.CFrame = CFrame.new(0, body.Size.Y / 2 + 0.2 * scale, 0.4 * scale) * CFrame.Angles(math.rad(20), 0, 0)
	fuse.Parent = model
	-- Lit spark on the fuse tip.
	local spark = makePart({
		Name = "Spark",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.5, 0.5, 0.5) * scale,
		Color = Color3.fromRGB(255, 180, 40),
		Material = Enum.Material.Neon,
	})
	spark.CFrame = fuse.CFrame * CFrame.new(0, -0.5 * scale, 0)
	spark.Parent = model
	local fuseLight = Instance.new("PointLight")
	fuseLight.Color = Color3.fromRGB(255, 160, 40)
	fuseLight.Range = 8
	fuseLight.Brightness = 1.6
	fuseLight.Parent = spark

	addLegs(model, body, bodyColor, false, scale)
	addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + 0.6 * scale
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.8, 2.8, 2.8) * scale,
		Color = Color3.fromRGB(255, 160, 170),
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0.6 * scale)
	head.Parent = model
	-- Pig snout (cylinder).
	local snout = makePart({
		Name = "Snout",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 0.9, 0.9) * scale,
		Color = Color3.fromRGB(255, 140, 150),
		Material = Enum.Material.SmoothPlastic,
	})
	snout.CFrame = CFrame.new(0, headY - 0.2 * scale, 1.6 * scale) * CFrame.Angles(0, 0, math.rad(90))
	snout.Parent = model
	-- Pig ears.
	for _, side in ipairs({ -1, 1 }) do
		local ear = makeWedge({
			Name = "Ear",

			Size = Vector3.new(0.4, 0.7, 0.5) * scale,
			Color = Color3.fromRGB(230, 140, 150),
			Material = Enum.Material.SmoothPlastic,
		})
		ear.CFrame = CFrame.new(side * 0.9 * scale, headY + 1.1 * scale, 0)
			* CFrame.Angles(0, 0, math.rad(-20 * side))
		ear.Parent = model
	end
	addHeadFace(model, 0, headY, 0.6 * scale, 1.5 * scale, 0.6 * scale, 0.25 * scale, scale)
	addHeadHat(model, "crown", headY + head.Size.Y / 2, scale)
	return body
end

-- 11. Schnozzolo Gelatone — elephant head + fridge body, trunk = hose.
builders["schnozzolo-fridge"] = function(model, bodyColor, scale)
	-- Fridge body: tall box.
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2.2, 3.5, 2.2) * scale,
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Fridge handle.
	local handle = makePart({
		Name = "Handle",
		Size = Vector3.new(0.2, 1.4, 0.3) * scale,
		Color = Color3.fromRGB(120, 130, 140),
		Material = Enum.Material.Metal,
	})
	handle.CFrame = CFrame.new(body.Size.X / 2 - 0.35 * scale, 0.3 * scale, -body.Size.Z / 2 - 0.1 * scale)
	handle.Parent = model
	-- Door split line.
	local split = makePart({
		Name = "DoorSplit",
		Size = Vector3.new(2.2, 0.1, 0.1) * scale,
		Color = Color3.fromRGB(180, 190, 200),
		Material = Enum.Material.SmoothPlastic,
	})
	split.CFrame = CFrame.new(0, 0.3 * scale, -body.Size.Z / 2)
	split.Parent = model

	addLegs(model, body, bodyColor, true, scale)
	addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + 1.0 * scale
	local head = makePart({
		Name = "Head",
		Size = Vector3.new(2.8, 2.6, 3.0) * scale,
		Color = Color3.fromRGB(150, 160, 170),
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0.2 * scale)
	head.Parent = model
	-- Big floppy ears.
	for _, side in ipairs({ -1, 1 }) do
		local ear = makePart({
			Name = "Ear",
			Size = Vector3.new(0.5, 1.2, 1.2) * scale,
			Color = Color3.fromRGB(130, 140, 150),
			Material = Enum.Material.SmoothPlastic,
		})
		ear.CFrame = CFrame.new(side * 1.5 * scale, headY, 0) * CFrame.Angles(0, 0, math.rad(15 * side))
		ear.Parent = model
	end
	-- Trunk = hose curving down from the face.
	local trunk = makePart({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 0.5, 0.5) * scale,
		Color = Color3.fromRGB(140, 150, 160),
		Material = Enum.Material.SmoothPlastic,
	})
	trunk.CFrame = CFrame.new(0, headY - 0.8 * scale, 1.2 * scale) * CFrame.Angles(math.rad(70), 0, 0)
	trunk.Parent = model
	addHeadFace(model, 0, headY, 0.2 * scale, 1.5 * scale, 0.6 * scale, 0.3 * scale, scale)
	addHeadHat(model, "horns", headY + head.Size.Y / 2, scale)
	return body
end

-- 12. Finale Dragoespresso — dragon head + espresso machine body, steam wings.
builders["finale-drago"] = function(model, bodyColor, scale)
	-- Espresso machine body: tall box.
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2.0, 2.8, 2.0) * scale,
		Color = Color3.fromRGB(60, 60, 68),
		Material = Enum.Material.Metal,
	})
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	-- Chrome espresso spout.
	local spout = makePart({
		Name = "Spout",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 0.3, 0.3) * scale,
		Color = Color3.fromRGB(200, 200, 210),
		Material = Enum.Material.Metal,
	})
	spout.CFrame = CFrame.new(0, 0.2 * scale, -body.Size.Z / 2) * CFrame.Angles(math.rad(90), 0, 0)
	spout.Parent = model
	-- Portafilter cup under the spout.
	local cup = makePart({
		Name = "Cup",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 0.6, 0.6) * scale,
		Color = Color3.fromRGB(30, 30, 35),
		Material = Enum.Material.Metal,
	})
	cup.CFrame = CFrame.new(0, -0.5 * scale, -body.Size.Z / 2 + 0.2 * scale) * CFrame.Angles(math.rad(90), 0, 0)
	cup.Parent = model
	-- Steam wings on the back/sides.
	for _, side in ipairs({ -1, 1 }) do
		local wing = makeWedge({
			Name = "Wing",

			Size = Vector3.new(0.3, 1.4, 1.2) * scale,
			Color = bodyColor,
			Material = Enum.Material.Neon,
		})
		wing.CFrame = CFrame.new(side * (body.Size.X / 2 + 0.35 * scale), 0.5 * scale, 0)
			* CFrame.Angles(0, math.rad(90), math.rad(-20 * side))
		wing.Parent = model
		local steam = Instance.new("ParticleEmitter")
		steam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		steam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		steam.Lifetime = NumberRange.new(0.6, 1.2)
		steam.Rate = 4
		steam.Speed = NumberRange.new(1, 2)
		steam.SpreadAngle = Vector2.new(30, 30)
		steam.Size = NumberSequence.new(1.2)
		steam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		steam.Parent = wing
	end

	addLegs(model, body, bodyColor, true, scale)
	addArms(model, body, bodyColor, scale)

	local headY = body.Size.Y / 2 + 0.6 * scale
	local head = makePart({
		Name = "Head",
		Size = Vector3.new(2.8, 2.8, 3.0) * scale,
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	head.CFrame = CFrame.new(0, headY, 0.4 * scale)
	head.Parent = model
	-- Dragon snout (wedge).
	local snout = makeWedge({
		Name = "Snout",

		Size = Vector3.new(1.0, 1.0, 1.4) * scale,
		Color = bodyColor:Lerp(BLACK, 0.2),
		Material = Enum.Material.SmoothPlastic,
	})
	snout.CFrame = CFrame.new(0, headY - 0.2 * scale, 1.8 * scale)
	snout.Parent = model
	-- Spikes along the head.
	for _, off in ipairs({ -0.5, 0.25, 0.9 }) do
		local spike = makeWedge({
			Name = "Spike",

			Size = Vector3.new(0.4, 0.8, 0.4) * scale,
			Color = Color3.fromRGB(255, 200, 60),
			Material = Enum.Material.Neon,
		})
		spike.CFrame = CFrame.new(off * scale, headY + 1.3 * scale, 0)
		spike.Parent = model
	end
	addHeadFace(model, 0, headY, 0.4 * scale, 1.6 * scale, 0.6 * scale, 0.25 * scale, scale)
	addHeadHat(model, "crown", headY + head.Size.Y / 2, scale)
	return body
end

-- Build one brainrot character as an anchored Model whose PrimaryPart is the
-- fused-object body. `scale` grows it (the plaza statue uses a big one).
function BrainrotModels.build(entry, mutation, scale, traits)
	scale = scale or 1.6
	local model = Instance.new("Model")
	model.Name = mutation and mutation.id ~= "none" and (mutation.name .. " " .. entry.name) or entry.name
	if traits and #traits > 0 then
		model.Name = Config.unitTitle(entry, mutation, traits)
	end

	local bodyColor = entry.color
	if mutation and mutation.color then
		bodyColor = mutation.color
	end

	local builder = builders[entry.id]
	local body
	if builder then
		body = builder(model, bodyColor, scale)
	else
		-- Fallback: a plain colored body so an unknown id never crashes a build.
		body = makePart({
			Name = "Body",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.2, 3.2, 3.2) * scale,
			Color = bodyColor,
			Material = Enum.Material.SmoothPlastic,
		})
		body.CFrame = CFrame.new(0, 0, 0)
		body.Parent = model
		addLegs(model, body, bodyColor, entry.shape == "tall", scale)
		addHeadFace(model, 0, body.Size.Y / 2 + 1.0 * scale, 0, 1.0 * scale, 0.5 * scale, 0.2 * scale, scale)
		addHeadHat(model, entry.hat, body.Size.Y / 2 + 2.0 * scale, scale)
	end
	model.PrimaryPart = body

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
	walkItems[model] = item
	return item
end

-- Stop walking a walker (called on catch). Removes it from the animation loop.
function BrainrotModels.stopWalker(model)
	for i = #animated, 1, -1 do
		if animated[i].model == model then
			table.remove(animated, i)
		end
	end
	walkItems[model] = nil
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
	walkItems[model] = nil
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

			-- Convoy safety net: never let a walker close on the one ahead.
			-- Find the nearest other walker with a greater z (the one in front,
			-- accounting for wrap). If this walker is within laneSpacing * 0.8 of
			-- it, clamp its z so the 9-stud gap can never collapse.
			local minGap = Config.Walkers.laneSpacing * 0.8
			local span = item.carpetHalf * 2
			local aheadDelta = nil
			for otherModel, other in pairs(walkItems) do
				if otherModel ~= model then
					local d = other.z - item.z
					if d < 0 then
						d += span -- other wrapped behind; treat as ahead
					end
					if d > 0 and (aheadDelta == nil or d < aheadDelta) then
						aheadDelta = d
					end
				end
			end
			if aheadDelta ~= nil and aheadDelta < minGap then
				item.z = item.z + (aheadDelta - minGap)
				if item.z > item.carpetHalf then
					item.z = -item.carpetHalf
				end
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

-- The plaza statue: a giant mascot over the fountain, built once by the world builder.
function BrainrotModels.buildStatue(entry)
	local model = BrainrotModels.build(entry, nil, 4)
	local gui = addLabel(model, entry.name, "mascot of the vault", Config.rarity(entry.rarity).color, 14)
	return model
end

return BrainrotModels
