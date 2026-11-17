-- Brainrot Vault Tycoon — client HUD.
-- A ScreenGui over the 3D world: cash and income up top (clear of Roblox's
-- own top-left menu), the tsunami banner under it, the catch pill and toasts
-- in the middle, and the owned-units panel and shop along the bottom.
-- Everything numeric comes from player/ReplicatedStorage attributes the
-- server owns; this script only draws and sends ShopAction clicks.

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
local PANEL = Color3.fromRGB(24, 24, 32)

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
	f.BackgroundTransparency = 0.12
	f.BorderSizePixel = 0
	for key, value in pairs(props) do
		f[key] = value
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = f
	return f
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

-- ---------------------------------------------------------------------------
-- Top center: title, cash, income line
-- ---------------------------------------------------------------------------

local title = label({
	Name = "Title",
	Text = "BRAINROT VAULT TYCOON",
	Font = Enum.Font.GothamBold,
	TextColor3 = GOLD,
	TextStrokeColor3 = Color3.fromRGB(40, 30, 0),
	TextStrokeTransparency = 0.4,
	Size = UDim2.fromOffset(520, 26),
	Position = UDim2.new(0.5, -260, 0, 8),
	ZIndex = 3,
})
title.Parent = gui

local cashLabel = label({
	Name = "Cash",
	Text = "$0",
	Font = Enum.Font.GothamBold,
	TextColor3 = GREEN,
	TextStrokeColor3 = Color3.fromRGB(0, 40, 10),
	TextStrokeTransparency = 0.35,
	Size = UDim2.fromOffset(520, 54),
	Position = UDim2.new(0.5, -260, 0, 34),
	ZIndex = 3,
})
cashLabel.TextSize = 44
cashLabel.Parent = gui

local rateLabel = label({
	Name = "Rate",
	Text = "$0/s",
	TextColor3 = YELLOW,
	TextStrokeColor3 = Color3.fromRGB(30, 25, 0),
	TextStrokeTransparency = 0.5,
	Size = UDim2.fromOffset(520, 24),
	Position = UDim2.new(0.5, -260, 0, 88),
	ZIndex = 3,
})
rateLabel.Parent = gui

-- ---------------------------------------------------------------------------
-- Tsunami banner + screen tint
-- ---------------------------------------------------------------------------

local waveBanner = label({
	Name = "WaveBanner",
	Text = "",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	Size = UDim2.fromOffset(700, 40),
	Position = UDim2.new(0.5, -350, 0, 120),
	ZIndex = 4,
	Visible = false,
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
	TextStrokeTransparency = 0.4,
	Size = UDim2.fromOffset(560, 44),
	Position = UDim2.new(0.5, -280, 0.38, 0),
	ZIndex = 5,
	Visible = false,
})
toast.Parent = gui

local carryPill = panel({
	Name = "CarryPill",
	Size = UDim2.fromOffset(420, 44),
	Position = UDim2.new(0.5, -210, 0.6, 0),
	BackgroundTransparency = 0.2,
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
carryBar.Size = UDim2.new(1, 0, 0, 4)
carryBar.Position = UDim2.new(0, 0, 1, -4)
carryBar.BorderSizePixel = 0
carryBar.BackgroundColor3 = GOLD
carryBar.ZIndex = 6
carryBar.Parent = carryPill

-- ---------------------------------------------------------------------------
-- Bottom center: contextual hint
-- ---------------------------------------------------------------------------

local hint = label({
	Name = "Hint",
	Text = "",
	TextColor3 = Color3.fromRGB(225, 225, 235),
	TextStrokeTransparency = 0.6,
	Size = UDim2.fromOffset(760, 30),
	Position = UDim2.new(0.5, -380, 0.68, 0),
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
	TextColor3 = Color3.fromRGB(210, 210, 220),
	Size = UDim2.new(1, -16, 0, 66),
	Position = UDim2.fromOffset(8, 92),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 4,
})
ownedList.Parent = owned

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
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

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

local function refreshWave()
	local state = ReplicatedStorage:GetAttribute("WaveState") or "calm"
	local countdown = math.ceil(ReplicatedStorage:GetAttribute("WaveCountdown") or 0)

	if state == "warning" then
		waveBanner.Visible = true
		waveBanner.Text = string.format("!! TSUNAMI IN %ds — GET TO YOUR BASE !!", countdown)
		waveBanner.TextColor3 = RED
		dangerFlash.BackgroundTransparency = 0.75 + math.sin(tick() * 8) * 0.12
	elseif state == "sweep" then
		waveBanner.Visible = true
		waveBanner.Text = "TSUNAMI! STAY ON YOUR ISLAND!"
		waveBanner.TextColor3 = Color3.fromRGB(160, 220, 255)
		dangerFlash.BackgroundTransparency = 0.8 + math.sin(tick() * 8) * 0.1
	else
		-- Calm: a quiet countdown so players can plan the next run.
		if countdown <= 30 then
			waveBanner.Visible = true
			waveBanner.Text = string.format("Next tsunami in %ds", countdown)
			waveBanner.TextColor3 = YELLOW
		else
			waveBanner.Visible = false
		end
		dangerFlash.BackgroundTransparency = 1
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

	local carryInfo = player:GetAttribute("CarryInfo") or ""
	if carryInfo ~= "" then
		carryPill.Visible = true
		carryText.Text = "CARRYING: " .. carryInfo
		carryText.TextColor3 = player:GetAttribute("CarryColor") or GOLD
		carryBar.BackgroundColor3 = player:GetAttribute("CarryColor") or GOLD
	else
		carryPill.Visible = false
	end

	local hintText = player:GetAttribute("Hint") or ""
	hint.Text = hintText

	refreshShop()
	refreshOwned()
	refreshWave()
end)

-- First paint
showToast("Welcome to the Vault — claim a base!")
