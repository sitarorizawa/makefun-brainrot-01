-- Brainrot Vault Tycoon — minimal client HUD matching the operator's reference.
-- 1. Top-centre: one instruction / state line
-- 2. Bottom-left: money counter ($X)
-- 3. Left edge: 4 icon buttons — Shop (green), Rebirth (purple), Index (blue), Codes (orange)
-- 4. Top-right: "YOUR BASE" arrow indicator
-- Wave warning banner still runs; shop actions still fire ShopAction.
-- No floating panels, no collection panel, no rebirth bar, no owned list, no
-- bottom buttons, no shop panel.

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

-- ---------------------------------------------------------------------------
-- Root GUI
-- ---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- ---------------------------------------------------------------------------
-- 1. Top-centre: one instruction / status line
-- ---------------------------------------------------------------------------

local instructionLine = label({
	Name = "Instruction",
	Text = "Claim an open base!",
	Font = Enum.Font.GothamBold,
	TextColor3 = GOLD,
	TextStrokeColor3 = Color3.fromRGB(40, 30, 0),
	TextStrokeTransparency = 0.35,
	Size = UDim2.fromOffset(620, 36),
	Position = UDim2.new(0.5, -310, 0, 8),
	ZIndex = 5,
})
instructionLine.Parent = gui

-- ---------------------------------------------------------------------------
-- 2. Bottom-left: money counter
-- ---------------------------------------------------------------------------

local moneyCounter = label({
	Name = "Money",
	Text = "$0",
	Font = Enum.Font.GothamBold,
	TextColor3 = GREEN,
	TextStrokeColor3 = Color3.fromRGB(0, 45, 10),
	TextStrokeTransparency = 0.3,
	Size = UDim2.fromOffset(240, 44),
	Position = UDim2.new(0, 16, 1, -60),
	ZIndex = 5,
	TextXAlignment = Enum.TextXAlignment.Left,
})
moneyCounter.Parent = gui

-- ---------------------------------------------------------------------------
-- 3. Left edge: 4 icon buttons as coloured squares
-- ---------------------------------------------------------------------------

local iconSpecs = {
	{ name = "Shop",    color = Color3.fromRGB(45, 195, 95),  action = "none" }, -- opens shop (tbd)
	{ name = "Rebirth", color = Color3.fromRGB(180, 95, 255), action = "rebirth" },
	{ name = "Index",   color = Color3.fromRGB(60, 140, 255), action = "none" }, -- collection index
	{ name = "Codes",   color = Color3.fromRGB(255, 145, 50),  action = "none" }, -- redeem codes
}

for i, spec in ipairs(iconSpecs) do
	local btn = Instance.new("TextButton")
	btn.Name = spec.name
	btn.BackgroundColor3 = spec.color
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextScaled = true
	btn.Text = spec.name
	btn.Size = UDim2.fromOffset(64, 64)
	btn.Position = UDim2.fromOffset(8, 114 + (i - 1) * 72)
	btn.ZIndex = 5
	btn.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		if spec.action ~= "none" then
			shopRemote:FireServer(spec.action)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- 4. Top-right: "YOUR BASE" arrow indicator
-- ---------------------------------------------------------------------------

local yourBaseArrow = label({
	Name = "YourBase",
	Text = "→ YOUR BASE",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(120, 210, 255),
	TextStrokeColor3 = Color3.fromRGB(0, 30, 50),
	TextStrokeTransparency = 0.3,
	Size = UDim2.fromOffset(200, 34),
	Position = UDim2.new(1, -216, 0, 8),
	ZIndex = 5,
	TextXAlignment = Enum.TextXAlignment.Right,
})
yourBaseArrow.Parent = gui

-- ---------------------------------------------------------------------------
-- Wave / tsunami banner — top-centre, just below the instruction line
-- ---------------------------------------------------------------------------

local waveBanner = label({
	Name = "WaveBanner",
	Text = "",
	Font = Enum.Font.GothamBold,
	TextColor3 = YELLOW,
	TextStrokeColor3 = Color3.fromRGB(30, 20, 0),
	TextStrokeTransparency = 0.3,
	Size = UDim2.fromOffset(620, 38),
	Position = UDim2.new(0.5, -310, 0, 48),
	ZIndex = 4,
})
waveBanner.Parent = gui

-- ---------------------------------------------------------------------------
-- Danger flash: soft red pulse when tsunami is on
-- ---------------------------------------------------------------------------

local dangerFlash = Instance.new("Frame")
dangerFlash.Name = "DangerFlash"
dangerFlash.Size = UDim2.fromScale(1, 1)
dangerFlash.BackgroundColor3 = Color3.fromRGB(180, 20, 20)
dangerFlash.BackgroundTransparency = 1
dangerFlash.BorderSizePixel = 0
dangerFlash.ZIndex = 1
dangerFlash.Parent = gui

-- ---------------------------------------------------------------------------
-- Toast (catch / place notifications) — centre screen
-- ---------------------------------------------------------------------------

local toast = label({
	Name = "Toast",
	Text = "",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.35,
	Size = UDim2.fromOffset(560, 46),
	Position = UDim2.new(0.5, -280, 0.42, 0),
	ZIndex = 6,
	Visible = false,
})
toast.Parent = gui

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
-- Carried-unit pill — centre-bottom when holding a catch
-- ---------------------------------------------------------------------------

local carryPill = Instance.new("Frame")
carryPill.Name = "CarryPill"
carryPill.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
carryPill.BackgroundTransparency = 0.12
carryPill.BorderSizePixel = 0
carryPill.Size = UDim2.fromOffset(420, 40)
carryPill.Position = UDim2.new(0.5, -210, 0.62, 0)
carryPill.ZIndex = 5
carryPill.Visible = false
carryPill.Parent = gui

local carryCorner = Instance.new("UICorner")
carryCorner.CornerRadius = UDim.new(0, 10)
carryCorner.Parent = carryPill

local carryText = label({
	Name = "CarryText",
	Text = "",
	Font = Enum.Font.GothamBold,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 6,
})
carryText.Parent = carryPill

-- ---------------------------------------------------------------------------
-- Per-frame refresh
-- ---------------------------------------------------------------------------

local lastWaveState = "calm"

RunService.RenderStepped:Connect(function()
	-- Money counter
	local cash = player:GetAttribute("Cash") or 0
	moneyCounter.Text = "$" .. fmt(cash)

	-- Instruction line: use the server Hint attribute, or a default.
	local hint = player:GetAttribute("Hint") or ""
	if hint ~= "" then
		instructionLine.Text = hint
	else
		local carrying = (player:GetAttribute("CarryInfo") or "") ~= ""
		local baseIndex = player:GetAttribute("BaseIndex") -- no direct attribute for this, approximate
		if carrying then
			instructionLine.Text = "Bring the catch to your base!"
		else
			instructionLine.Text = "Catch a capsule and bring it to your base!"
		end
	end

	-- YOUR BASE indicator — always visible.
	-- The arrow hints at which way your claimed base is; an unclaimed player
	-- still sees it as a reminder to go claim one.
	yourBaseArrow.Visible = true

	-- Wave banner
	local state = ReplicatedStorage:GetAttribute("WaveState") or "calm"
	local countdown = math.ceil(ReplicatedStorage:GetAttribute("WaveCountdown") or 0)

	if state ~= lastWaveState then
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
		waveBanner.Visible = true
		waveBanner.Text = string.format("NEXT TSUNAMI IN %ds", countdown)
		waveBanner.TextColor3 = YELLOW
		dangerFlash.BackgroundTransparency = 1
	end

	-- Carry pill
	local carryInfo = player:GetAttribute("CarryInfo") or ""
	if carryInfo ~= "" then
		carryPill.Visible = true
		carryText.Text = "CARRYING: " .. carryInfo
		carryText.TextColor3 = player:GetAttribute("CarryColor") or GOLD
	else
		carryPill.Visible = false
	end
end)

-- First paint
showToast("Welcome to the Vault — claim a base!")