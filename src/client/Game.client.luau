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

-- Fun panel style: vertical gradient fill + gold border stroke.
local function stylePanel(frame, strokeColor)
	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor or Color3.fromRGB(255, 185, 70)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = frame
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(36, 40, 62)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 16, 24)),
	})
	grad.Rotation = 90
	grad.Parent = frame
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
-- 2. Bottom-left: money counter with a subtle dark rounded panel behind it
-- ---------------------------------------------------------------------------

local moneyPanel = Instance.new("Frame")
moneyPanel.Name = "MoneyPanel"
moneyPanel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
moneyPanel.BackgroundTransparency = 0.25
moneyPanel.BorderSizePixel = 0
moneyPanel.Size = UDim2.fromOffset(260, 60)
moneyPanel.Position = UDim2.new(0, 12, 1, -72)
moneyPanel.ZIndex = 4
moneyPanel.Parent = gui

local moneyCorner = Instance.new("UICorner")
moneyCorner.CornerRadius = UDim.new(0, 12)
moneyCorner.Parent = moneyPanel

local moneyPad = Instance.new("UIPadding")
moneyPad.PaddingLeft = UDim.new(0, 14)
moneyPad.PaddingRight = UDim.new(0, 14)
moneyPad.PaddingTop = UDim.new(0, 4)
moneyPad.PaddingBottom = UDim.new(0, 4)
moneyPad.Parent = moneyPanel
stylePanel(moneyPanel, Color3.fromRGB(255, 205, 80))

local moneyCounter = label({
	Name = "Money",
	Text = "$0",
	Font = Enum.Font.GothamBold,
	TextColor3 = GREEN,
	TextStrokeColor3 = Color3.fromRGB(0, 45, 10),
	TextStrokeTransparency = 0.3,
	TextScaled = false,
	TextSize = 32,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 5,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
})
moneyCounter.Parent = moneyPanel

-- Income rate, bottom-right of the money panel.
local moneyRate = label({
	Name = "MoneyRate",
	Text = "$0/s",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(140, 240, 160),
	TextStrokeColor3 = Color3.fromRGB(0, 45, 10),
	TextStrokeTransparency = 0.4,
	TextScaled = false,
	TextSize = 16,
	Size = UDim2.fromOffset(96, 22),
	Position = UDim2.new(1, -104, 1, -26),
	ZIndex = 6,
	TextXAlignment = Enum.TextXAlignment.Right,
})
moneyRate.Parent = moneyPanel

-- Pop scale when income ticks up.
local moneyScale = Instance.new("UIScale")
moneyScale.Parent = moneyPanel

local showToast -- forward declaration: the button handler below calls it

-- ---------------------------------------------------------------------------
-- Panels: Shop + Index (opened from the left-edge buttons)
-- ---------------------------------------------------------------------------

local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
shopPanel.BackgroundTransparency = 0.12
shopPanel.BorderSizePixel = 0
shopPanel.Size = UDim2.fromOffset(380, 376)
shopPanel.Position = UDim2.new(0.5, -190, 0.5, -150)
shopPanel.Visible = false
shopPanel.ZIndex = 8
shopPanel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = shopPanel
	stylePanel(shopPanel)
	local title = label({
		Name = "Title", Text = "🛒 SHOP", Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(120, 230, 140), TextSize = 24,
		Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 10), ZIndex = 9,
	})
	title.Parent = shopPanel
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "✕"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 20
	close.TextColor3 = Color3.fromRGB(255, 130, 130)
	close.BackgroundTransparency = 1
	close.Size = UDim2.fromOffset(36, 36)
	close.Position = UDim2.new(1, -44, 0, 6)
	close.ZIndex = 10
	close.Parent = shopPanel
	close.MouseButton1Click:Connect(function()
		shopPanel.Visible = false
	end)
end

local shopRows = {}
local rowSpecs = {
	{ key = "slots",      name = "Extra Pedestal", desc = "One more display slot",     attr = "SlotCost" },
	{ key = "multiplier", name = "Income Boost",   desc = "+0.5x income, permanent",   attr = "MultiplierCost" },
	{ key = "speed",      name = "Speed Boost",    desc = "Walk around faster",        attr = "SpeedCost" },
	{ key = "gacha",      name = "Random Brainrot", desc = "Surprise catch (needs a free slot)", attr = "GachaCost" },
}
for i, rs in ipairs(rowSpecs) do
	local row = Instance.new("Frame")
	row.Name = rs.key
	row.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, -24, 0, 64)
	row.Position = UDim2.fromOffset(12, 50 + (i - 1) * 72)
	row.ZIndex = 9
	row.Parent = shopPanel
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 10); rc.Parent = row

	local n = label({ Name = "N", Text = rs.name, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), TextSize = 17, Size = UDim2.new(1, -150, 0, 24), Position = UDim2.fromOffset(12, 8), ZIndex = 10 })
	n.Parent = row
	local d = label({ Name = "D", Text = rs.desc, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(150, 155, 170), TextSize = 13, Size = UDim2.new(1, -150, 0, 20), Position = UDim2.fromOffset(12, 34), ZIndex = 10 })
	d.Parent = row

	local price = label({ Name = "Price", Text = "$...", Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 220, 90), TextSize = 16, Size = UDim2.fromOffset(80, 24), Position = UDim2.new(1, -178, 0, 6), ZIndex = 10, TextXAlignment = Enum.TextXAlignment.Right })
	price.Parent = row

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.Text = "BUY"
	buy.Font = Enum.Font.GothamBold
	buy.BackgroundColor3 = Color3.fromRGB(45, 195, 95)
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.TextSize = 15
	buy.AutoButtonColor = true
	buy.BorderSizePixel = 0
	buy.Size = UDim2.fromOffset(74, 32)
	buy.Position = UDim2.new(1, -86, 0, 26)
	buy.ZIndex = 10
	buy.Parent = row
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = buy
	local bgrad = Instance.new("UIGradient")
	bgrad.Color = ColorSequence.new(Color3.fromRGB(100, 240, 140), Color3.fromRGB(30, 150, 70))
	bgrad.Rotation = 90
	bgrad.Parent = buy
	local actionKey = rs.key
	buy.MouseButton1Click:Connect(function()
		shopRemote:FireServer(actionKey)
	end)

	shopRows[#shopRows + 1] = { attr = rs.attr, price = price, buy = buy }
end

-- Index panel: collection progress straight from the server attributes.
local indexPanel = Instance.new("Frame")
indexPanel.Name = "IndexPanel"
indexPanel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
indexPanel.BackgroundTransparency = 0.12
indexPanel.BorderSizePixel = 0
indexPanel.Size = UDim2.fromOffset(380, 300)
indexPanel.Position = UDim2.new(0.5, -190, 0.5, -150)
indexPanel.Visible = false
indexPanel.ZIndex = 8
indexPanel.Parent = gui
local indexCount, indexRarities
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = indexPanel
	stylePanel(indexPanel, Color3.fromRGB(110, 170, 255))
	local title = label({
		Name = "Title", Text = "📚 INDEX", Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(110, 170, 255), TextSize = 24,
		Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 10), ZIndex = 9,
	})
	title.Parent = indexPanel
	indexCount = label({
		Name = "Count", Text = "0 / 0 caught", Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1), TextSize = 18,
		Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 52), ZIndex = 9,
	})
	indexCount.Parent = indexPanel
	indexRarities = label({
		Name = "Rarities", Text = "", Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(210, 215, 225), TextSize = 17,
		Size = UDim2.new(1, -24, 0, 160), Position = UDim2.fromOffset(12, 90), ZIndex = 9,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	indexRarities.RichText = true
	indexRarities.TextWrapped = true
	indexRarities.Parent = indexPanel
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "✕"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 20
	close.TextColor3 = Color3.fromRGB(255, 130, 130)
	close.BackgroundTransparency = 1
	close.Size = UDim2.fromOffset(36, 36)
	close.Position = UDim2.new(1, -44, 0, 6)
	close.ZIndex = 10
	close.Parent = indexPanel
	close.MouseButton1Click:Connect(function()
		indexPanel.Visible = false
	end)
end

-- ---------------------------------------------------------------------------
-- 3. Left edge: 4 icon buttons with icon glyph, label, rounded corners, padding
-- ---------------------------------------------------------------------------


local iconSpecs = {
	{ name = "Shop",    icon = "🛒", color = Color3.fromRGB(45, 195, 95),  action = "none" }, -- opens shop (tbd)
	{ name = "Rebirth", icon = "♻",  color = Color3.fromRGB(180, 95, 255), action = "rebirth" },
	{ name = "Index",   icon = "📘", color = Color3.fromRGB(60, 140, 255), action = "none" }, -- collection index
	{ name = "Codes",   icon = "🎟",  color = Color3.fromRGB(255, 145, 50),  action = "none" }, -- redeem codes
}

local buttonWidth = 96
local buttonHeight = 64
local buttonStartY = 120
local buttonSpacing = 72

for i, spec in ipairs(iconSpecs) do
	local btn = Instance.new("TextButton")
	btn.Name = spec.name
	btn.BackgroundColor3 = spec.color
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Text = ""
	btn.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
	btn.Position = UDim2.fromOffset(12, buttonStartY + (i - 1) * buttonSpacing)
	btn.ZIndex = 5
	btn.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn

	-- Gradient fill + white outline + bouncy hover.
	local bc = spec.color
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(
		Color3.new(math.min(bc.R + 0.2, 1), math.min(bc.G + 0.2, 1), math.min(bc.B + 0.2, 1)),
		Color3.new(bc.R * 0.5, bc.G * 0.5, bc.B * 0.5)
	)
	grad.Rotation = 90
	grad.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = btn

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = btn

	local iconLabel = label({
		Name = "Icon",
		Text = spec.icon,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = false,
		TextSize = 27,
		Size = UDim2.new(1, 0, 0.55, 0),
		Position = UDim2.fromScale(0, 0),
		ZIndex = 6,
	})
	iconLabel.Parent = btn

	local textLabel = label({
		Name = "Label",
		Text = spec.name,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = false,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0.45, 0),
		Position = UDim2.fromScale(0, 0.52),
		ZIndex = 6,
	})
	textLabel.Parent = btn

	btn.MouseButton1Click:Connect(function()
		if spec.name == "Shop" then
			shopPanel.Visible = not shopPanel.Visible
			indexPanel.Visible = false
		elseif spec.name == "Index" then
			indexPanel.Visible = not indexPanel.Visible
			shopPanel.Visible = false
		elseif spec.name == "Codes" then
			showToast("No active codes right now!")
		elseif spec.action ~= "none" then
			shopRemote:FireServer(spec.action)
		end
	end)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(buttonWidth + 10, buttonHeight + 6),
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), {
			Size = UDim2.fromOffset(buttonWidth, buttonHeight),
		}):Play()
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
-- Wave / tsunami banner — translucent dark rounded panel so it reads over any
-- background. Centered just below the instruction line.
-- ---------------------------------------------------------------------------

local wavePanel = Instance.new("Frame")
wavePanel.Name = "WavePanel"
wavePanel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
wavePanel.BackgroundTransparency = 0.22
wavePanel.BorderSizePixel = 0
wavePanel.Size = UDim2.fromOffset(340, 46)
wavePanel.Position = UDim2.new(0.5, -170, 0, 48)
wavePanel.ZIndex = 3
wavePanel.Parent = gui

local waveCorner = Instance.new("UICorner")
waveCorner.CornerRadius = UDim.new(0, 10)
waveCorner.Parent = wavePanel
stylePanel(wavePanel, Color3.fromRGB(255, 120, 90))

local waveBanner = label({
	Name = "WaveBanner",
	Text = "",
	Font = Enum.Font.GothamBold,
	TextColor3 = YELLOW,
	TextStrokeColor3 = Color3.fromRGB(30, 20, 0),
	TextStrokeTransparency = 0.3,
	TextScaled = false,
	TextSize = 18,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 4,
})
waveBanner.Parent = wavePanel

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
	BackgroundColor3 = Color3.fromRGB(26, 28, 44),
	BackgroundTransparency = 0.12,
	Size = UDim2.fromOffset(560, 46),
	Position = UDim2.new(0.5, -280, 0.42, 0),
	ZIndex = 6,
	Visible = false,
})
toast.Parent = gui
do
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 12); tc.Parent = toast
	local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(255, 205, 80); ts.Thickness = 2; ts.Transparency = 0.3; ts.Parent = toast
end

local toastToken = 0
showToast = function(text)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.12
	toast.Visible = true
	-- Slide down into place.
	toast.Position = UDim2.new(0.5, -280, 0.42, -40)
	TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -280, 0.42, 0),
	}):Play()
	task.delay(2.4, function()
		if token ~= toastToken then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.6), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end

-- Market counter (press E) asks the server for the shop; open it here.
player:GetAttributeChangedSignal("ShopOpenAt"):Connect(function()
	shopPanel.Visible = true
	indexPanel.Visible = false
end)

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
stylePanel(carryPill, Color3.fromRGB(255, 205, 80))

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
local lastCash = nil

-- Floating "+$N" text that rises and fades above the money panel.
local function floatIncome(amount)
	moneyScale.Scale = 1.08
	TweenService:Create(moneyScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local t = Instance.new("TextLabel")
	t.Text = "+$" .. fmt(amount)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 22
	t.TextColor3 = Color3.fromRGB(140, 255, 160)
	t.TextStrokeColor3 = Color3.fromRGB(0, 45, 10)
	t.TextStrokeTransparency = 0.4
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromOffset(180, 30)
	t.Position = UDim2.new(0, 16, 1, -140)
	t.ZIndex = 7
	t.Parent = gui
	local goal = {
		Position = UDim2.new(0, 16, 1, -215),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}
	TweenService:Create(t, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	game:GetService("Debris"):AddItem(t, 1.2)
end

RunService.RenderStepped:Connect(function()
	-- Money counter + income rate
	local cash = player:GetAttribute("Cash") or 0
	moneyCounter.Text = "💰 $" .. fmt(cash)
	moneyRate.Text = "⚡ $" .. fmt(player:GetAttribute("CashPerSecond") or 0) .. "/s"
	if lastCash == nil then
		lastCash = cash
	elseif cash > lastCash then
		floatIncome(cash - lastCash)
	end
	lastCash = cash

	-- Shop panel prices (−1 attribute = maxed)
	if shopPanel.Visible then
		for _, row in ipairs(shopRows) do
			local cost
			if row.attr == "GachaCost" then
				cost = Config.Economy.gachaCost
			else
				cost = player:GetAttribute(row.attr) or -1
			end
			if cost < 0 then
				row.price.Text = "MAXED"
				row.price.TextColor3 = Color3.fromRGB(150, 155, 170)
				row.buy.Visible = false
			else
				row.price.Text = "$" .. fmt(cost)
				row.price.TextColor3 = Color3.fromRGB(255, 220, 90)
				row.buy.Visible = true
			end
		end
	end

	-- Index panel content
	if indexPanel.Visible then
		indexCount.Text = string.format("%d / %d caught",
			player:GetAttribute("CollectionCount") or 0,
			player:GetAttribute("CollectionMax") or 0)
		indexRarities.Text = player:GetAttribute("RarityProgress") or ""
	end

	-- Instruction line: use the server Hint attribute, or a default.
	local hint = player:GetAttribute("Hint") or ""
	if hint ~= "" then
		instructionLine.Text = "🎯 " .. hint
	else
		local carrying = (player:GetAttribute("CarryInfo") or "") ~= ""
		if carrying then
			instructionLine.Text = "🏃 Bring the catch to your base!"
		else
			instructionLine.Text = "👆 Click a brainrot on the road, then bring it to your base!"
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