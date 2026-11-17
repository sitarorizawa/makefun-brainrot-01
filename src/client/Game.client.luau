-- Brainrot Vault Tycoon — client HUD.
-- A ScreenGui over the 3D world: cash and income up top (clear of Roblox's
-- own top-left menu), the collection panel top-right, an always-on tsunami
-- banner with countdown, the catch pill and toasts in the middle, the owned-
-- units panel bottom-left, big COLLECT / UPGRADE / REBIRTH buttons along the
-- bottom, and the shop bottom-right. Floating +$ texts rise from the cash
-- counter every time income lands, and a bright flash fires when a tsunami
-- warning starts. Everything numeric comes from player/ReplicatedStorage
-- attributes the server owns; this script only draws and fires ShopAction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shopRemote = ReplicatedStorage:WaitForChild("ShopAction")

local GOLD = Color3.fromRGB(255, 210, 90)
local GREEN = Color3.fromRGB(120, 255, 150)
local YELLOW = Color3.fromRGB(255, 235, 130)
local RED = Color3.fromRGB(255, 80, 80)
local PANEL = Color3.fromRGB(22, 24, 34)

local function fmt(n)
	n = math.floor(n + 0.5)
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

local function label(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.TextWrapped = true
	for key, value in pairs(props) do
		l[key] = value
	end
	return l
end

local function panel(props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	for key, value in pairs(props) do
		f[key] = value
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.75
	stroke.Thickness = 2
	stroke.Parent = f
	return f
end

local function styleButton(button)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.6
	stroke.Thickness = 2
	stroke.Parent = button
end

-- ---------------------------------------------------------------------------
-- Root GUI
-- ---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- A soft red pulse across the screen while the tsunami warning is up.
local dangerFlash = Instance.new("Frame")
dangerFlash.Name = "DangerFlash"
dangerFlash.Size = UDim2.fromScale(1, 1)
dangerFlash.BackgroundColor3 = Color3.fromRGB(180, 20, 20)
dangerFlash.BackgroundTransparency = 1
dangerFlash.BorderSizePixel = 0
dangerFlash.ZIndex = 1
dangerFlash.Parent = gui

-- A bright full-screen flash the moment a wave phase begins.
local startFlash = Instance.new("Frame")
startFlash.Name = "StartFlash"
startFlash.Size = UDim2.fromScale(1, 1)
startFlash.BackgroundColor3 = Color3.fromRGB(255, 250, 235)
startFlash.BackgroundTransparency = 1
startFlash.BorderSizePixel = 0
startFlash.ZIndex = 9
startFlash.Parent = gui

-- ---------------------------------------------------------------------------
-- Top center: title, cash, income line
-- ---------------------------------------------------------------------------

local title = label({
	Name = "Title",
	Text = "BRAINROT VAULT TYCOON",
	Font = Enum.Font.GothamBold,
	TextColor3 = GOLD,
	TextStrokeColor3 = Color3.fromRGB(40, 30, 0),
	TextStrokeTransparency = 0.35,
	Size = UDim2.fromOffset(560, 30),
	Position = UDim2.new(0.5, -280, 0, 6),
	ZIndex = 3,
})
title.Parent = gui

local cashLabel = label({
	Name = "Cash",
	Text = "$0",
	Font = Enum.Font.GothamBold,
	TextColor3 = GREEN,
	TextStrokeColor3 = Color3.fromRGB(0, 40, 10),
	TextStrokeTransparency = 0.3,
	Size = UDim2.fromOffset(560, 58),
	Position = UDim2.new(0.5, -280, 0, 34),
	ZIndex = 3,
})
cashLabel.Parent = gui

local rateLabel = label({
	Name = "Rate",
	Text = "$0/s",
	TextColor3 = YELLOW,
	TextStrokeColor3 = Color3.fromRGB(30, 25, 0),
	TextStrokeTransparency = 0.4,
	Size = UDim2.fromOffset(560, 26),
	Position = UDim2.new(0.5, -280, 0, 94),
	ZIndex = 3,
})
rateLabel.Parent = gui

-- ---------------------------------------------------------------------------
-- Top right: collection / rarity progress + rebirth counter
-- ---------------------------------------------------------------------------

local collection = panel({
	Name = "CollectionPanel",
	Size = UDim2.fromOffset(340, 152),
	Position = UDim2.new(1, -352, 0, 12),
	ZIndex = 3,
})
collection.Parent = gui

local collectionTitle = label({
	Name = "CollectionTitle",
	Text = "★ COLLECTION ★",
	Font = Enum.Font.GothamBold,
	TextColor3 = GOLD,
	Size = UDim2.new(1, -16, 0, 26),
	Position = UDim2.fromOffset(8, 6),
	ZIndex = 4,
})
collectionTitle.Parent = collection

local collectionCount = label({
	Name = "CollectionCount",
	Text = "0 / 12 BRAINROTS",
	Font = Enum.Font.GothamBold,
	TextColor3 = GREEN,
	Size = UDim2.new(1, -16, 0, 34),
	Position = UDim2.fromOffset(8, 32),
	ZIndex = 4,
})
collectionCount.Parent = collection

local rarityProgress = label({
	Name = "RarityProgress",
	Text = "",
	Font = Enum.Font.GothamBold,
	Size = UDim2.new(1, -16, 0, 40),
	Position = UDim2.fromOffset(8, 68),
	ZIndex = 4,
})
rarityProgress.RichText = true
rarityProgress.Parent = collection

local collectionStats = label({
	Name = "CollectionStats",
	Text = "REBIRTHS x0 · INCOME x1.0",
	TextColor3 = YELLOW,
	Size = UDim2.new(1, -16, 0, 26),
	Position = UDim2.fromOffset(8, 112),
	ZIndex = 4,
})
collectionStats.Parent = collection

-- ---------------------------------------------------------------------------
-- Tsunami banner (always visible) + screen tint
-- ---------------------------------------------------------------------------

local waveBanner = label({
	Name = "WaveBanner",
	Text = "",
	Font = Enum.Font.GothamBold,
	TextColor3 = YELLOW,
	TextStrokeColor3 = Color3.fromRGB(30, 20, 0),
	TextStrokeTransparency = 0.3,
	Size = UDim2.fromOffset(760, 46),
	Position = UDim2.new(0.5, -380, 0, 126),
	ZIndex = 4,
})
waveBanner.Parent = gui

-- ---------------------------------------------------------------------------
-- Center: toast and catch pill
-- ---------------------------------------------------------------------------

local toast = label({
	Name = "Toast",
	Text = "",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.35,
	Size = UDim2.fromOffset(640, 50),
	Position = UDim2.new(0.5, -320, 0.36, 0),
	ZIndex = 5,
	Visible = false,
})
toast.Parent = gui

local carryPill = panel({
	Name = "CarryPill",
	Size = UDim2.fromOffset(460, 46),
	Position = UDim2.new(0.5, -230, 0.58, 0),
	BackgroundTransparency = 0.15,
	ZIndex = 5,
	Visible = false,
})
carryPill.Parent = gui

local carryText = label({
	Name = "CarryText",
	Text = "",
	Font = Enum.Font.GothamBold,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 6,
})
carryText.Parent = carryPill

local carryBar = Instance.new("Frame")
carryBar.Name = "Bar"
carryBar.Size = UDim2.new(1, 0, 0, 5)
carryBar.Position = UDim2.new(0, 0, 1, -5)
carryBar.BorderSizePixel = 0
carryBar.BackgroundColor3 = GOLD
carryBar.ZIndex = 6
carryBar.Parent = carryPill

-- ---------------------------------------------------------------------------
-- Hint above the action buttons
-- ---------------------------------------------------------------------------

local hint = label({
	Name = "Hint",
	Text = "",
	TextColor3 = Color3.fromRGB(235, 235, 245),
	TextStrokeTransparency = 0.5,
	Size = UDim2.fromOffset(760, 30),
	Position = UDim2.new(0.5, -380, 0.66, 0),
	ZIndex = 3,
})
hint.Parent = gui

-- ---------------------------------------------------------------------------
-- Bottom left: what is on your base right now
-- ---------------------------------------------------------------------------

local owned = panel({
	Name = "OwnedPanel",
	Size = UDim2.fromOffset(300, 170),
	Position = UDim2.new(0, 12, 1, -186),
	ZIndex = 3,
})
owned.Parent = gui

local ownedTitle = label({
	Name = "OwnedTitle",
	Text = "ON YOUR BASE",
	Font = Enum.Font.GothamBold,
	TextColor3 = GOLD,
	Size = UDim2.new(1, -16, 0, 24),
	Position = UDim2.fromOffset(8, 8),
	ZIndex = 4,
})
ownedTitle.Parent = owned

local ownedCount = label({
	Name = "OwnedCount",
	Text = "0 / 4 units",
	Font = Enum.Font.GothamBold,
	TextColor3 = GREEN,
	Size = UDim2.new(1, -16, 0, 26),
	Position = UDim2.fromOffset(8, 36),
	ZIndex = 4,
})
ownedCount.Parent = owned

local ownedRate = label({
	Name = "OwnedRate",
	Text = "$0/s placed",
	TextColor3 = YELLOW,
	Size = UDim2.new(1, -16, 0, 22),
	Position = UDim2.fromOffset(8, 64),
	ZIndex = 4,
})
ownedRate.Parent = owned

local ownedList = label({
	Name = "OwnedList",
	Text = "—",
	TextColor3 = Color3.fromRGB(215, 215, 225),
	Size = UDim2.new(1, -16, 0, 66),
	Position = UDim2.fromOffset(8, 92),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 4,
})
ownedList.Parent = owned

-- ---------------------------------------------------------------------------
-- Bottom center: big COLLECT / UPGRADE / REBIRTH buttons
-- ---------------------------------------------------------------------------

local buttonSpecs = {
	{ key = "collect", name = "COLLECT", color = Color3.fromRGB(45, 195, 95) },
	{ key = "upgrade", name = "UPGRADE", color = Color3.fromRGB(60, 140, 255) },
	{ key = "rebirth", name = "REBIRTH", color = Color3.fromRGB(180, 95, 255) },
}

local actionButtons = {}
for index, spec in ipairs(buttonSpecs) do
	local button = Instance.new("TextButton")
	button.Name = spec.name
	button.BackgroundColor3 = spec.color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.TextStrokeColor3 = Color3.fromRGB(15, 15, 20)
	button.TextStrokeTransparency = 0.5
	button.Size = UDim2.fromOffset(150, 64)
	button.Position = UDim2.new(0.5, -235 + (index - 1) * 160, 1, -140)
	button.ZIndex = 5
	button.Parent = gui
	styleButton(button)

	button.MouseButton1Click:Connect(function()
		shopRemote:FireServer(spec.key)
	end)

	actionButtons[index] = { spec = spec, button = button }
end

-- ---------------------------------------------------------------------------
-- Bottom right: the shop
-- ---------------------------------------------------------------------------

local shop = panel({
	Name = "ShopPanel",
	Size = UDim2.fromOffset(330, 300),
	Position = UDim2.new(1, -342, 1, -316),
	ZIndex = 3,
})
shop.Parent = gui

local shopTitle = label({
	Name = "ShopTitle",
	Text = "SHOP",
	Font = Enum.Font.GothamBold,
	TextColor3 = GOLD,
	Size = UDim2.new(1, -16, 0, 28),
	Position = UDim2.fromOffset(8, 8),
	ZIndex = 4,
})
shopTitle.Parent = shop

-- Each row: a description on the left, a button with the price on the right.
local rows = {}
local rowActions = {
	{ key = "slots", name = "Pedestal slot", getCost = function(state)
		return state.slots < Config.Economy.maxSlots and Config.slotCost(state.slots) or nil
	end, getMax = function() return "MAX" end },
	{ key = "multiplier", name = "Income boost", getCost = function(state)
		return state.multLevel < Config.Economy.maxMultiplierLevel and Config.multiplierCost(state.multLevel) or nil
	end, getMax = function() return "MAX" end },
	{ key = "speed", name = "Speed boost", getCost = function(state)
		return state.speedLevel < Config.Economy.maxSpeedLevel and Config.speedCost(state.speedLevel) or nil
	end, getMax = function() return "MAX" end },
	{ key = "rebirth", name = "REBIRTH", getCost = function(state)
		return Config.rebirthRequirement(state.rebirths)
	end, getMax = function(state) return "REBIRTH " .. (state.rebirths + 1) end },
}

for index, spec in ipairs(rowActions) do
	local row = Instance.new("Frame")
	row.Name = spec.key
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -16, 0, 54)
	row.Position = UDim2.fromOffset(8, 44 + (index - 1) * 60)
	row.ZIndex = 4
	row.Parent = shop

	local nameLabel = label({
		Name = "Name",
		Text = spec.name,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, -110, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	nameLabel.Parent = row

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.Size = UDim2.fromOffset(100, 40)
	button.Position = UDim2.new(1, -100, 0.5, -20)
	button.ZIndex = 5
	button.Parent = row
	styleButton(button)

	button.MouseButton1Click:Connect(function()
		shopRemote:FireServer(spec.key)
	end)

	rows[index] = { spec = spec, button = button, name = nameLabel }
end

-- ---------------------------------------------------------------------------
-- Toast animation
-- ---------------------------------------------------------------------------

local toastToken = 0
local function showToast(text)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextTransparency = 0
	toast.Visible = true
	task.delay(2.4, function()
		if token ~= toastToken then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.6), { TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end

player:GetAttributeChangedSignal("ToastAt"):Connect(function()
	local text = player:GetAttribute("Toast")
	if text and text ~= "" then
		showToast(text)
	end
end)

-- ---------------------------------------------------------------------------
-- Floating +$ gain texts rising from the cash counter
-- ---------------------------------------------------------------------------

local lastCash = player:GetAttribute("Cash") or 0
local lastGainAt = 0

local function spawnGainText(amount)
	local gain = label({
		Name = "Gain",
		Text = "+$" .. fmt(amount),
		Font = Enum.Font.GothamBold,
		TextColor3 = GREEN,
		TextStrokeColor3 = Color3.fromRGB(0, 45, 10),
		TextStrokeTransparency = 0.3,
		Size = UDim2.fromOffset(240, 40),
		Position = UDim2.new(0.5, -120, 0, 92),
		ZIndex = 8,
	})
	gain.Parent = gui
	local tween = TweenService:Create(gain, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -120, 0, 34),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		gain:Destroy()
	end)
end

-- ---------------------------------------------------------------------------
-- Bright flash when a wave phase begins
-- ---------------------------------------------------------------------------

local lastWaveState = "calm"

local function fireWaveFlash(state)
	startFlash.BackgroundColor3 = state == "warning"
		and Color3.fromRGB(255, 244, 210)
		or Color3.fromRGB(170, 225, 255)
	startFlash.BackgroundTransparency = 0.05
	local tween = TweenService:Create(startFlash, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	tween:Play()
end

-- ---------------------------------------------------------------------------
-- Per-frame refresh
-- ---------------------------------------------------------------------------

local function refreshShop()
	local state = {
		slots = player:GetAttribute("Slots") or Config.Economy.startSlots,
		multLevel = player:GetAttribute("MultiplierLevel") or 0,
		speedLevel = player:GetAttribute("SpeedLevel") or 0,
		rebirths = player:GetAttribute("Rebirths") or 0,
	}
	local cash = player:GetAttribute("Cash") or 0

	for index, row in ipairs(rows) do
		local spec = row.spec
		local cost = spec.getCost(state)
		if cost == nil then
			row.button.Text = spec.getMax(state)
			row.button.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
		elseif cash >= cost then
			row.button.Text = "$" .. fmt(cost)
			row.button.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
		else
			row.button.Text = "$" .. fmt(cost)
			row.button.BackgroundColor3 = Color3.fromRGB(120, 70, 70)
		end
		if spec.key == "rebirth" then
			row.name.Text = string.format("REBIRTH %d", state.rebirths + 1)
		end
	end
end

local function refreshOwned()
	local slots = player:GetAttribute("Slots") or Config.Economy.startSlots
	local placed = player:GetAttribute("UnitsPlaced") or 0
	local rate = player:GetAttribute("CashPerSecond") or 0
	ownedCount.Text = string.format("%d / %d units", placed, slots)
	ownedRate.Text = string.format("$%d/s placed", rate)
	local list = player:GetAttribute("UnitList") or ""
	ownedList.Text = list ~= "" and list or "— catch a capsule and place it!"
end

local function refreshCollection()
	local count = player:GetAttribute("CollectionCount") or 0
	local max = player:GetAttribute("CollectionMax") or #Config.Brainrots
	collectionCount.Text = string.format("%d / %d BRAINROTS", count, max)

	local progress = player:GetAttribute("RarityProgress") or ""
	rarityProgress.Text = progress ~= "" and progress or "catch capsules to discover them!"

	local rebirths = player:GetAttribute("Rebirths") or 0
	local multiplier = 1
		+ (player:GetAttribute("MultiplierLevel") or 0) * Config.Economy.multiplierPerLevel
		+ rebirths * Config.Economy.rebirthMultiplierBonus
	local slots = player:GetAttribute("Slots") or Config.Economy.startSlots
	collectionStats.Text = string.format("REBIRTHS x%d · INCOME x%.1f · SLOTS %d/%d",
		rebirths, multiplier, slots, Config.Economy.maxSlots)
end

local function refreshWave()
	local state = ReplicatedStorage:GetAttribute("WaveState") or "calm"
	local countdown = math.ceil(ReplicatedStorage:GetAttribute("WaveCountdown") or 0)

	if state ~= lastWaveState then
		if state == "warning" or state == "sweep" then
			fireWaveFlash(state)
		end
		lastWaveState = state
	end

	if state == "warning" then
		waveBanner.Visible = true
		waveBanner.Text = string.format("!! TSUNAMI IN %ds — GET TO YOUR BASE !!", countdown)
		waveBanner.TextColor3 = RED
		dangerFlash.BackgroundTransparency = 0.75 + math.sin(tick() * 8) * 0.12
	elseif state == "sweep" then
		waveBanner.Visible = true
		waveBanner.Text = "TSUNAMI! STAY ON YOUR SAFE ZONE!"
		waveBanner.TextColor3 = Color3.fromRGB(170, 225, 255)
		dangerFlash.BackgroundTransparency = 0.8 + math.sin(tick() * 8) * 0.1
	else
		-- Calm: always show the countdown so players can plan the next run.
		waveBanner.Visible = true
		waveBanner.Text = string.format("NEXT TSUNAMI IN %ds — CATCH & UPGRADE", countdown)
		waveBanner.TextColor3 = YELLOW
		dangerFlash.BackgroundTransparency = 1
	end
end

local function refreshButtons()
	local cash = player:GetAttribute("Cash") or 0
	local lifetime = player:GetAttribute("Lifetime") or 0
	local rebirths = player:GetAttribute("Rebirths") or 0
	local multLevel = player:GetAttribute("MultiplierLevel") or 0
	local carrying = (player:GetAttribute("CarryInfo") or "") ~= ""

	for _, entry in ipairs(actionButtons) do
		local spec = entry.spec
		local button = entry.button
		if spec.key == "collect" then
			button.Text = carrying and "PLACE CATCH" or "COLLECT"
			button.BackgroundColor3 = carrying and Color3.fromRGB(60, 230, 110) or spec.color
		elseif spec.key == "upgrade" then
			if multLevel >= Config.Economy.maxMultiplierLevel then
				button.Text = "UPGRADE MAXED"
				button.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
			else
				local cost = Config.multiplierCost(multLevel)
				button.Text = "UPGRADE  $" .. fmt(cost)
				button.BackgroundColor3 = cash >= cost and spec.color or Color3.fromRGB(95, 105, 140)
			end
		elseif spec.key == "rebirth" then
			local requirement = Config.rebirthRequirement(rebirths)
			if lifetime >= requirement then
				button.Text = "REBIRTH NOW!"
				button.BackgroundColor3 = Color3.fromRGB(220, 120, 255)
			else
				button.Text = "NEED $" .. fmt(requirement)
				button.BackgroundColor3 = Color3.fromRGB(105, 75, 140)
			end
		end
	end
end

RunService.RenderStepped:Connect(function()
	local cash = player:GetAttribute("Cash") or 0
	local rate = player:GetAttribute("CashPerSecond") or 0
	local multiplier = 1
		+ (player:GetAttribute("MultiplierLevel") or 0) * Config.Economy.multiplierPerLevel
		+ (player:GetAttribute("Rebirths") or 0) * Config.Economy.rebirthMultiplierBonus

	cashLabel.Text = "$" .. fmt(cash)
	rateLabel.Text = string.format("$%d/s  ·  x%.1f income  ·  Rebirths %d", rate, multiplier, player:GetAttribute("Rebirths") or 0)

	-- Floating +$ whenever cash increases (income tick, mostly).
	if cash > lastCash then
		local delta = cash - lastCash
		local now = tick()
		if delta >= 1 and now - lastGainAt > 0.35 then
			lastGainAt = now
			spawnGainText(delta)
		end
	end
	lastCash = cash

	local carryInfo = player:GetAttribute("CarryInfo") or ""
	if carryInfo ~= "" then
		carryPill.Visible = true
		carryText.Text = "CARRYING: " .. carryInfo
		carryText.TextColor3 = player:GetAttribute("CarryColor") or GOLD
		carryBar.BackgroundColor3 = player:GetAttribute("CarryColor") or GOLD
	else
		carryPill.Visible = false
	end

	hint.Text = player:GetAttribute("Hint") or ""

	refreshShop()
	refreshOwned()
	refreshCollection()
	refreshWave()
	refreshButtons()
end)

-- First paint
showToast("Welcome to the Vault — claim a base!")
