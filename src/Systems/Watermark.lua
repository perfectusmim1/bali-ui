--[[
	Bali UI · Systems/Watermark
	Draggable Dynamic-Island style obsidian glass HUD pill with live pulse status dot,
	viewport clamping, and optional live FPS/Ping/Time/Players telemetry.
]]

local Services = require("Core/Services")
local Maid = require("Core/Maid")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Transition = require("Core/Transition")
local Util = require("Core/Util")
local Input = require("Systems/Input")

local Watermark = {}

local rootMaid = Maid.new()
local layer = nil
local pill = nil
local dot = nil
local dotHalo = nil
local titleLabel = nil
local divider = nil
local statsLabel = nil
local stopPulseFn = nil
local dragHandle = nil
local renderConn = nil

local visible = false
local titleText = "Bali"
local customText = nil
local statsConfig = {
	FPS = true,
	Ping = true,
	Time = true,
	Players = false,
	Custom = nil,
}

local fpsSamples = 0
local fpsElapsed = 0
local currentFps = 60
local lastRefresh = 0

local function readPingMs()
	local ok, value = pcall(function()
		local net = Services.Stats and Services.Stats.Network
		local item = net and net.ServerStatsItem and net.ServerStatsItem["Data Ping"]
		return item and item:GetValue() or 0
	end)
	return (ok and type(value) == "number") and math.max(0, math.round(value)) or 0
end

local function readPlayerCount()
	local ok, text = pcall(function()
		local players = Services.Players
		return tostring(#players:GetPlayers()) .. "/" .. tostring(players.MaxPlayers)
	end)
	return ok and text or "1/1"
end

local function formatStats()
	if customText ~= nil then
		return tostring(customText)
	end

	local parts = {}
	local cfg = statsConfig

	if cfg.FPS == true then
		table.insert(parts, tostring(math.max(0, math.round(currentFps))) .. " FPS")
	elseif type(cfg.FPS) == "number" then
		table.insert(parts, tostring(math.round(cfg.FPS)) .. " FPS")
	elseif type(cfg.FPS) == "string" and cfg.FPS ~= "" then
		table.insert(parts, cfg.FPS)
	end

	if cfg.Ping == true then
		table.insert(parts, tostring(readPingMs()) .. " ms")
	elseif type(cfg.Ping) == "number" then
		table.insert(parts, tostring(math.round(cfg.Ping)) .. " ms")
	elseif type(cfg.Ping) == "string" and cfg.Ping ~= "" then
		table.insert(parts, cfg.Ping)
	end

	if cfg.Time == true then
		table.insert(parts, tostring(os.date("%H:%M:%S")))
	elseif type(cfg.Time) == "string" and cfg.Time ~= "" then
		table.insert(parts, cfg.Time)
	end

	if cfg.Players == true then
		table.insert(parts, readPlayerCount() .. " Players")
	elseif type(cfg.Players) == "string" or type(cfg.Players) == "number" then
		table.insert(parts, tostring(cfg.Players))
	end

	if type(cfg.Custom) == "string" and cfg.Custom ~= "" then
		table.insert(parts, cfg.Custom)
	end

	return table.concat(parts, "  •  ")
end

local function refreshLabels()
	if not pill then
		return
	end
	titleLabel.Text = titleText
	local text = formatStats()
	statsLabel.Text = text
	local hasStats = text ~= ""
	statsLabel.Visible = hasStats
	divider.Visible = hasStats and titleText ~= ""
	titleLabel.Visible = titleText ~= ""
end

local function stopLiveEffects()
	if stopPulseFn then
		stopPulseFn()
		stopPulseFn = nil
	end
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function startLiveEffects()
	stopLiveEffects()
	if not pill or not visible then
		return
	end

	if dotHalo then
		stopPulseFn = Transition.Pulse(dotHalo, "BackgroundTransparency", 0.5, 0.92, 1.6)
	end

	fpsSamples = 0
	fpsElapsed = 0
	lastRefresh = os.clock()

	renderConn = Services.RunService.RenderStepped:Connect(function(dt)
		if not visible or not pill or not pill.Parent then
			stopLiveEffects()
			return
		end
		fpsSamples += 1
		fpsElapsed += dt
		local now = os.clock()
		if now - lastRefresh >= 0.5 then
			if fpsElapsed > 0 then
				currentFps = fpsSamples / fpsElapsed
			end
			fpsSamples = 0
			fpsElapsed = 0
			lastRefresh = now
			refreshLabels()
		end
	end)
end

local function ensureBuilt()
	if pill and pill.Parent then
		return true
	end
	if not layer or not layer.Parent then
		return false
	end

	pill = Create.New("Frame", {
		Name = "BaliWatermark",
		Parent = layer,
		Visible = visible,
		Active = true,
		Position = UDim2.fromOffset(16, 68),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Corner = UDim.new(1, 0),
		ClipsDescendants = true,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.08)
			end,
		},
		ZIndex = 350,
	})
	Create.GlassStroke(pill, 0.06)

	local glowId = Assets.Get("Glow")
	if glowId then
		Create.New("ImageLabel", {
			Name = "Glow",
			Parent = pill,
			Size = UDim2.fromOffset(100, 34),
			Position = UDim2.fromOffset(-20, 0),
			Corner = UDim.new(1, 0),
			Image = glowId,
			ScaleType = Enum.ScaleType.Stretch,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = function(t)
					return math.min(t.GlowTransparency + 0.06, 0.94)
				end,
			},
			ZIndex = 350,
		})
	end

	local content = Create.New("Frame", {
		Name = "Content",
		Parent = pill,
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Padding = { 0, 14, 0, 12 },
		ZIndex = 352,
	})
	Create.List(content, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 8,
	})

	local dotHolder = Create.New("Frame", {
		Name = "PulseHolder",
		Parent = content,
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 353,
	})

	dotHalo = Create.New("Frame", {
		Name = "Halo",
		Parent = dotHolder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		Corner = UDim.new(1, 0),
		BackgroundTransparency = 0.6,
		Theme = { BackgroundColor3 = "Accent" },
		ZIndex = 353,
	})

	dot = Create.New("Frame", {
		Name = "Dot",
		Parent = dotHolder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		Corner = UDim.new(1, 0),
		Theme = { BackgroundColor3 = "Accent" },
		ZIndex = 354,
	})

	titleLabel = Create.Text({
		Name = "Title",
		Parent = content,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = titleText,
		Font = "SemiBold",
		TextSize = 12,
		Color = "Text",
		LayoutOrder = 2,
		ZIndex = 353,
	})

	divider = Create.New("Frame", {
		Name = "Divider",
		Parent = content,
		Size = UDim2.fromOffset(1, 13),
		LayoutOrder = 3,
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		ZIndex = 353,
	})

	statsLabel = Create.Text({
		Name = "Stats",
		Parent = content,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		Font = "Medium",
		TextSize = 12,
		Color = "SubText",
		LayoutOrder = 4,
		ZIndex = 353,
	})

	dragHandle = Input.BindDrag(pill, pill, { Clamp = true, Padding = 8 })
	rootMaid:Give(dragHandle)
	refreshLabels()

	if visible then
		startLiveEffects()
	end

	return true
end

function Watermark.Init(targetLayer)
	if layer == targetLayer and pill and pill.Parent then
		return Watermark
	end
	stopLiveEffects()
	rootMaid:Clean()
	if pill then
		pill:Destroy()
		pill = nil
	end
	layer = targetLayer
	ensureBuilt()
	return Watermark
end

function Watermark.SetVisible(state)
	local targetState = state == true
	visible = targetState
	if not ensureBuilt() then
		return
	end

	if targetState then
		refreshLabels()
		Transition.Mount(pill, 0.92)
		startLiveEffects()
	else
		stopLiveEffects()
		Transition.Unmount(pill, 0.92, function()
			if not visible and pill and pill.Parent then
				pill.Visible = false
			end
		end)
	end
end

function Watermark.IsVisible()
	return visible
end

function Watermark.SetTitle(text)
	titleText = text ~= nil and tostring(text) or ""
	refreshLabels()
end

function Watermark.SetText(text)
	customText = text ~= nil and tostring(text) or nil
	refreshLabels()
end

function Watermark.SetStats(stats)
	if type(stats) == "table" then
		customText = nil
		for key, value in pairs(stats) do
			statsConfig[key] = value
		end
	end
	refreshLabels()
end

function Watermark.Destroy()
	visible = false
	stopLiveEffects()
	rootMaid:Clean()
	if pill then
		pill:Destroy()
		pill = nil
	end
	dot = nil
	dotHalo = nil
	titleLabel = nil
	divider = nil
	statsLabel = nil
	dragHandle = nil
	layer = nil
end

return Watermark
