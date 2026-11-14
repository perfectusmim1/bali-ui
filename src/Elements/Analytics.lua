--[[
	Bali UI · Elements/Analytics
	Data visualization & dashboard elements inspired by SEDA, MEXC, and TradingView:
	StatCard, Chart (Line/Area & Bar with hover crosshair), ProgressBar, Table, CardGrid.
]]

local Services = require("Core/Services")
local Util = require("Core/Util")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Tween = require("Core/Tween")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Base = require("Elements/Base")
local Tooltip = require("Systems/Tooltip")

local Analytics = {}

-- ─── Shared Helpers ──────────────────────────────────────────────────────────

local function unwrapCard(cardParent, opts)
	local cardObj = Base.Card(cardParent, opts)
	if typeof(cardObj) == "Instance" then
		return cardObj, cardObj:FindFirstChildOfClass("UIStroke"), nil
	end
	return cardObj.Frame, cardObj.Stroke, cardObj
end

local function resolveColorSpec(spec, fallback)
	if typeof(spec) == "Color3" then
		return spec
	elseif type(spec) == "string" and Theme.Current[spec] ~= nil then
		return spec
	end
	return fallback or "Accent"
end

local function bindColorProp(inst, prop, colorSpec)
	if typeof(colorSpec) == "Color3" then
		Theme.Unbind(inst, prop)
		inst[prop] = colorSpec
	else
		Theme.Bind(inst, { [prop] = colorSpec })
	end
end

local function resolveAlign(align)
	if typeof(align) == "EnumItem" then
		return align
	elseif type(align) == "string" then
		local lower = string.lower(align)
		if lower == "right" then
			return Enum.TextXAlignment.Right
		elseif lower == "center" then
			return Enum.TextXAlignment.Center
		end
	end
	return Enum.TextXAlignment.Left
end

local function formatNumericValue(value, prefix, suffix, decimals)
	if type(value) ~= "number" then
		return tostring(value or "")
	end
	local dec = decimals
	if dec == nil then
		dec = (math.floor(value) == value) and 0 or 2
	end
	return (prefix or "") .. Util.FormatNumber(value, dec) .. (suffix or "")
end

local function computeMinMax(points)
	local minV, maxV = math.huge, -math.huge
	for _, v in ipairs(points) do
		local n = tonumber(v)
		if n then
			if n < minV then
				minV = n
			end
			if n > maxV then
				maxV = n
			end
		end
	end
	if minV == math.huge then
		return 0, 1
	end
	if math.abs(maxV - minV) < 1e-6 then
		return minV - 1, maxV + 1
	end
	return minV, maxV
end

local function renderLineSegments(container, points, colorSpec, thickness, padY)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = type(points) == "table" and #points or 0
	if count < 2 then
		return
	end
	local w = container.AbsoluteSize.X
	local h = container.AbsoluteSize.Y
	if w <= 2 or h <= 2 then
		return
	end

	local minV, maxV = computeMinMax(points)
	local span = maxV - minV
	local insetY = padY or 3
	local usableH = math.max(1, h - insetY * 2)

	local coords = table.create(count)
	for i = 1, count do
		local n = tonumber(points[i]) or minV
		local nx = (i - 1) / (count - 1)
		local ny = 1 - ((n - minV) / span)
		coords[i] = Vector2.new(nx * w, insetY + ny * usableH)
	end

	for i = 1, count - 1 do
		local p1, p2 = coords[i], coords[i + 1]
		local dx, dy = p2.X - p1.X, p2.Y - p1.Y
		local len = math.sqrt(dx * dx + dy * dy)
		local seg = Create.New("Frame", {
			Name = "Seg_" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((p1.X + p2.X) * 0.5, (p1.Y + p2.Y) * 0.5),
			Size = UDim2.fromOffset(len + 1.5, thickness or 2),
			Rotation = math.deg(math.atan2(dy, dx)),
			Corner = 999,
			ZIndex = container.ZIndex + 1,
			Parent = container,
		})
		bindColorProp(seg, "BackgroundColor3", colorSpec)
	end
end

-- ─── 1. StatCard ─────────────────────────────────────────────────────────────

local StatCard = {}
StatCard.__index = StatCard

function StatCard.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Title = "Metric",
		Value = 0,
		Prefix = "",
		Suffix = "",
		Decimals = nil,
		Delta = nil,
		Icon = "activity",
		Color = "Accent",
		Points = nil,
		Glow = true,
		Animate = true,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("StatCard", parent, opts, ctx)
	local cardParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local cardFrame, cardStroke, cardUI = unwrapCard(cardParent, opts)

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = cardFrame
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	cardFrame.ClipsDescendants = true

	local colorSpec = resolveColorSpec(opts.Color, "Accent")
	local currentRaw = opts.Value
	local currentPoints = type(opts.Points) == "table" and Util.Copy(opts.Points) or {}
	local cancelRoll = nil

	self.Value = currentRaw
	self.Stroke = cardStroke

	-- Subtle top-left radial Glow tint (clipped cleanly to card corner)
	local glowImg = Assets.Get("Glow")
	if opts.Glow ~= false and glowImg then
		local glowClip = Create.New("CanvasGroup", {
			Name = "GlowClip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Corner = opts.Corner or 10,
			ZIndex = 1,
			Parent = cardFrame,
		})
		local glow = Create.New("ImageLabel", {
			Name = "Glow",
			Size = UDim2.fromOffset(180, 120),
			Position = UDim2.fromOffset(-48, -42),
			Image = glowImg,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 1,
			Theme = { ImageTransparency = "GlowTransparency" },
			Parent = glowClip,
		})
		bindColorProp(glow, "ImageColor3", colorSpec)
	end

	local content = Create.New("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = 12,
		ZIndex = 2,
		Parent = cardFrame,
	})
	Create.List(content, { Gap = 10 })

	-- Top Row: IconBadge + Title (left) | Delta Pill (right)
	local topRow = Create.New("Frame", {
		Name = "TopRow",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 2,
		Parent = content,
	})

	local badgeObj = Base.IconBadge(topRow, opts.Icon or "activity", type(colorSpec) == "string" and colorSpec or "Accent")
	local badgeFrame = (typeof(badgeObj) == "Instance") and badgeObj or badgeObj.Frame
	if badgeFrame then
		badgeFrame.Position = UDim2.new(0, 0, 0.5, 0)
		badgeFrame.AnchorPoint = Vector2.new(0, 0.5)
		badgeFrame.ZIndex = 3
	end

	local deltaPill = Create.New("Frame", {
		Name = "DeltaPill",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Corner = 999,
		Padding = { 0, 8, 0, 7 },
		Visible = false,
		ZIndex = 3,
		Theme = {
			BackgroundColor3 = "Success",
			BackgroundTransparency = function() return 0.85 end,
		},
		Parent = topRow,
	})
	Create.List(deltaPill, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 4,
		VAlign = Enum.VerticalAlignment.Center,
	})
	local deltaStroke = Create.Stroke(deltaPill, {
		Theme = { Color = "Success", Transparency = function() return 0.65 end },
	})
	local deltaIcon = Icons.Create("trending-up", {
		Size = UDim2.fromOffset(11, 11),
		Color = "Success",
		LayoutOrder = 1,
		ZIndex = 4,
		Parent = deltaPill,
	})
	local deltaText = Create.Text({
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 11,
		Font = "SemiBold",
		Color = "Success",
		LayoutOrder = 2,
		ZIndex = 4,
		Parent = deltaPill,
	})

	local titleLabel = Create.Text({
		Name = "Title",
		Size = UDim2.new(1, -110, 1, 0),
		Position = UDim2.fromOffset(38, 0),
		Text = tostring(opts.Title or "Metric"),
		TextSize = 12,
		Font = "Medium",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Color = "SubText",
		ZIndex = 3,
		Parent = topRow,
	})

	self.TitleLabel = titleLabel

	-- Bottom Row: Large Value (left) + Inline Sparkline (right)
	local bottomRow = Create.New("Frame", {
		Name = "BottomRow",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		ZIndex = 2,
		Parent = content,
	})

	local sparkContainer = Create.New("Frame", {
		Name = "Sparkline",
		Size = UDim2.fromOffset(82, 28),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Visible = #currentPoints >= 2,
		ZIndex = 3,
		Parent = bottomRow,
	})

	local valueLabel = Create.Text({
		Name = "Value",
		Size = UDim2.new(1, #currentPoints >= 2 and -90 or 0, 0, 28),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = formatNumericValue(currentRaw, opts.Prefix, opts.Suffix, opts.Decimals),
		TextSize = 22,
		Font = "Bold",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Color = "Text",
		ZIndex = 3,
		Parent = bottomRow,
	})

	if self.BindUI then
		self:BindUI({
			Frame = cardFrame,
			Stroke = cardStroke,
			TitleLabel = titleLabel,
			LockOverlay = cardUI and cardUI.LockOverlay or nil,
			SetDisabled = cardUI and cardUI.SetDisabled or nil,
			Lock = cardUI and cardUI.Lock or nil,
			Unlock = cardUI and cardUI.Unlock or nil,
			Flash = cardUI and cardUI.Flash or nil,
		})
	end

	if opts.Tooltip and Tooltip and Tooltip.Bind then
		pcall(Tooltip.Bind, cardFrame, opts.Tooltip)
	end

	local function updateDelta(delta)
		if delta == nil or delta == "" then
			deltaPill.Visible = false
			return
		end
		deltaPill.Visible = true
		local num = tonumber(delta)
		local isNeg = false
		local formatted
		if num then
			isNeg = num < 0
			local sign = num > 0 and "+" or ""
			local dec = (math.floor(num) == num) and 0 or 1
			formatted = string.format("%s%." .. dec .. "f%%", sign, num)
		else
			formatted = tostring(delta)
			isNeg = string.sub(formatted, 1, 1) == "-"
		end
		local key = isNeg and "Error" or "Success"
		Theme.Bind(deltaPill, {
			BackgroundColor3 = key,
			BackgroundTransparency = function() return 0.85 end,
		})
		Theme.Bind(deltaStroke, {
			Color = key,
			Transparency = function() return 0.65 end,
		})
		Theme.Bind(deltaText, { TextColor3 = key })
		deltaText.Text = formatted
		if deltaIcon then
			Icons.Set(deltaIcon, isNeg and "trending-down" or "trending-up")
			Icons.SetColor(deltaIcon, key)
		end
	end

	local function redrawSpark()
		local hasSpark = #currentPoints >= 2
		sparkContainer.Visible = hasSpark
		valueLabel.Size = UDim2.new(1, hasSpark and -90 or 0, 0, 28)
		if hasSpark then
			renderLineSegments(sparkContainer, currentPoints, colorSpec, 2, 3)
		end
	end

	self.Maid:Give(sparkContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if #currentPoints >= 2 then
			renderLineSegments(sparkContainer, currentPoints, colorSpec, 2, 3)
		end
	end))

	function self:SetValue(v, delta)
		if cancelRoll then
			cancelRoll()
			cancelRoll = nil
		end
		local prevNum = tonumber(currentRaw)
		local nextNum = tonumber(v)
		currentRaw = v
		self.Value = v

		if opts.Animate ~= false and prevNum and nextNum and prevNum ~= nextNum then
			cancelRoll = Tween.Number(prevNum, nextNum, Tween.Normal, function(stepVal)
				valueLabel.Text = formatNumericValue(stepVal, opts.Prefix, opts.Suffix, opts.Decimals)
			end, function()
				cancelRoll = nil
			end)
		else
			valueLabel.Text = formatNumericValue(v, opts.Prefix, opts.Suffix, opts.Decimals)
		end

		if delta ~= nil then
			updateDelta(delta)
		end
	end

	function self:SetPoints(pts)
		currentPoints = type(pts) == "table" and Util.Copy(pts) or {}
		redrawSpark()
	end

	function self:Get()
		return currentRaw
	end

	local baseSetTitle = self.SetTitle
	function self:SetTitle(text)
		titleLabel.Text = tostring(text or "")
		if baseSetTitle then
			pcall(baseSetTitle, self, text)
		end
	end

	self.Maid:Give(function()
		if cancelRoll then
			cancelRoll()
			cancelRoll = nil
		end
	end)

	updateDelta(opts.Delta)
	task.defer(redrawSpark)
	return self
end

-- ─── 2. Chart ────────────────────────────────────────────────────────────────

local Chart = {}
Chart.__index = Chart

function Chart.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Title = "Chart",
		Subtitle = nil,
		Value = nil,
		Mode = "Line",
		Points = {},
		Labels = {},
		Height = 110,
		Color = "Accent",
		ShowGrid = true,
		Prefix = "",
		Suffix = "",
		Decimals = nil,
		MaxPoints = nil,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("Chart", parent, opts, ctx)
	local cardParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local cardFrame, cardStroke, cardUI = unwrapCard(cardParent, opts)

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = cardFrame
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	local mode = (type(opts.Mode) == "string" and string.lower(opts.Mode) == "bar") and "Bar" or "Line"
	local colorSpec = resolveColorSpec(opts.Color, "Accent")
	local chartHeight = math.max(56, tonumber(opts.Height) or 110)
	local showGrid = opts.ShowGrid ~= false
	local points = type(opts.Points) == "table" and Util.Copy(opts.Points) or {}
	local labels = type(opts.Labels) == "table" and Util.Copy(opts.Labels) or {}
	local maxPoints = opts.MaxPoints or math.max(#points, 24)
	local staticHeadline = opts.Value

	self.Value = points
	self.Stroke = cardStroke

	local content = Create.New("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = 12,
		Parent = cardFrame,
	})
	Create.List(content, { Gap = 8 })

	-- Header row
	local header = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = content,
	})

	local headerLeft = Create.New("Frame", {
		Size = UDim2.new(1, -104, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = header,
	})
	Create.List(headerLeft, { Gap = 2 })

	local titleLabel = Create.Text({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = tostring(opts.Title or "Chart"),
		TextSize = 13,
		Font = "SemiBold",
		TextWrapped = true,
		Color = "Text",
		LayoutOrder = 1,
		Parent = headerLeft,
	})

	local subtitleLabel
	if opts.Subtitle and opts.Subtitle ~= "" then
		subtitleLabel = Create.Text({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = tostring(opts.Subtitle),
			TextSize = 11,
			TextWrapped = true,
			Color = "SubText",
			LayoutOrder = 2,
			Parent = headerLeft,
		})
	end

	local headerRight = Create.New("Frame", {
		Size = UDim2.fromOffset(100, 32),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = header,
	})
	Create.List(headerRight, { Gap = 1, HAlign = Enum.HorizontalAlignment.Right })

	local readoutLabel = Create.Text({
		Size = UDim2.new(1, 0, 0, 18),
		Text = "",
		TextSize = 14,
		Font = "Bold",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Color = "Text",
		LayoutOrder = 1,
		Parent = headerRight,
	})

	local hoverTagLabel = Create.Text({
		Size = UDim2.new(1, 0, 0, 13),
		Text = "Latest",
		TextSize = 10,
		Font = "Medium",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Color = "SubText",
		TextTransparency = 0.25,
		Visible = true,
		LayoutOrder = 2,
		Parent = headerRight,
	})

	-- Main plot area
	local plotArea = Create.New("Frame", {
		Name = "PlotArea",
		Size = UDim2.new(1, 0, 0, chartHeight),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = content,
	})

	local yAxis = Create.New("Frame", {
		Name = "YAxis",
		Size = UDim2.new(0, 38, 1, 0),
		BackgroundTransparency = 1,
		Parent = plotArea,
	})

	local function makeYLabel(yScale, yAnchor)
		return Create.Text({
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.fromScale(0, yScale),
			AnchorPoint = Vector2.new(0, yAnchor),
			Text = "",
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Color = "Muted",
			Parent = yAxis,
		})
	end

	local yMaxLabel = makeYLabel(0, 0)
	local yMidLabel = makeYLabel(0.5, 0.5)
	local yMinLabel = makeYLabel(1, 1)

	local plotCanvas = Create.New("Frame", {
		Name = "PlotCanvas",
		Size = UDim2.new(1, -46, 1, -6),
		Position = UDim2.fromOffset(44, 3),
		BackgroundTransparency = 1,
		Parent = plotArea,
	})

	local gridLayer = Create.New("Frame", {
		Name = "GridLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = plotCanvas,
	})
	if showGrid then
		for _, yScale in ipairs({ 0, 0.5, 1 }) do
			Create.New("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.fromScale(0, yScale),
				AnchorPoint = Vector2.new(0, yScale == 1 and 1 or (yScale == 0.5 and 0.5 or 0)),
				ZIndex = 1,
				Theme = {
					BackgroundColor3 = "Divider",
					BackgroundTransparency = "DividerTransparency",
				},
				Parent = gridLayer,
			})
		end
	end

	local geomLayer = Create.New("Frame", {
		Name = "Geometry",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = plotCanvas,
	})

	local crosshair = Create.New("Frame", {
		Name = "Crosshair",
		Size = UDim2.new(0, 1, 1, 0),
		Visible = false,
		ZIndex = 5,
		Theme = {
			BackgroundColor3 = "Stroke",
			BackgroundTransparency = function() return 0.55 end,
		},
		Parent = plotCanvas,
	})

	local dotHalo = Create.New("Frame", {
		Name = "HoverHalo",
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Corner = 999,
		Visible = false,
		ZIndex = 6,
		BackgroundTransparency = 0.72,
		Parent = plotCanvas,
	})
	bindColorProp(dotHalo, "BackgroundColor3", colorSpec)

	local dotCenter = Create.New("Frame", {
		Name = "HoverDot",
		Size = UDim2.fromOffset(7, 7),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Corner = 999,
		ZIndex = 7,
		Theme = { BackgroundColor3 = "Knob" },
		Parent = dotHalo,
	})
	local dotStroke = Create.Stroke(dotCenter, { Thickness = 2, Transparency = 0 })
	bindColorProp(dotStroke, "Color", colorSpec)

	local hitOverlay = Create.New("Frame", {
		Name = "HitOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = plotCanvas,
	})

	local xAxisWrap = Create.New("Frame", {
		Name = "XAxisWrap",
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Visible = #labels > 0,
		LayoutOrder = 3,
		Parent = content,
	})

	local xAxisRow = Create.New("Frame", {
		Name = "XAxis",
		Size = UDim2.new(1, -46, 1, 0),
		Position = UDim2.fromOffset(44, 0),
		BackgroundTransparency = 1,
		Visible = #labels > 0,
		Parent = xAxisWrap,
	})

	if self.BindUI then
		self:BindUI({
			Frame = cardFrame,
			Stroke = cardStroke,
			TitleLabel = titleLabel,
			DescLabel = subtitleLabel,
			LockOverlay = cardUI and cardUI.LockOverlay or nil,
			SetDisabled = cardUI and cardUI.SetDisabled or nil,
			Lock = cardUI and cardUI.Lock or nil,
			Unlock = cardUI and cardUI.Unlock or nil,
			Flash = cardUI and cardUI.Flash or nil,
		})
	end

	if opts.Tooltip and Tooltip and Tooltip.Bind then
		pcall(Tooltip.Bind, cardFrame, opts.Tooltip)
	end

	local plottedCoords = {}
	local barFrames = {}
	local hoveredIndex = nil

	local function refreshDefaultReadout()
		if hoveredIndex ~= nil then
			return
		end
		if staticHeadline ~= nil then
			readoutLabel.Text = type(staticHeadline) == "number"
				and formatNumericValue(staticHeadline, opts.Prefix, opts.Suffix, opts.Decimals)
				or tostring(staticHeadline)
		elseif #points > 0 then
			readoutLabel.Text = formatNumericValue(tonumber(points[#points]) or points[#points], opts.Prefix, opts.Suffix, opts.Decimals)
		else
			readoutLabel.Text = "—"
		end
		hoverTagLabel.Visible = true
		hoverTagLabel.TextTransparency = 0.25
		if #labels > 0 then
			hoverTagLabel.Text = tostring(labels[#labels])
		elseif staticHeadline ~= nil then
			hoverTagLabel.Text = "Current"
		else
			hoverTagLabel.Text = "Latest"
		end
	end

	local function rebuildXLabels()
		for _, child in ipairs(xAxisRow:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if #labels == 0 then
			xAxisWrap.Visible = false
			xAxisRow.Visible = false
			return
		end
		xAxisWrap.Visible = true
		xAxisRow.Visible = true
		local canvasW = plotCanvas.AbsoluteSize.X
		local maxByWidth = canvasW > 40 and math.max(2, math.floor(canvasW / 54) + 1) or 6
		local maxShown = math.min(6, maxByWidth)
		local step = math.max(1, math.ceil(#labels / math.max(1, maxShown - 1)))
		local minEndGap = math.max(step, math.ceil(#labels * 0.18))
		local lastPlacedScale = -1
		local labelWidth = 48
		local minNormDist = canvasW > 0 and ((labelWidth + 6) / canvasW) or 0.2
		for i = 1, #labels do
			local scaleX = #labels == 1 and 0.5 or (i - 1) / (#labels - 1)
			local isEnd = (i == 1 or i == #labels)
			local isCadence = ((i - 1) % step == 0 and (i - 1) >= minEndGap and (#labels - i) >= minEndGap)
			if isEnd or (isCadence and (scaleX - lastPlacedScale) >= minNormDist and (1 - scaleX) >= minNormDist) then
				local align = Enum.TextXAlignment.Center
				local anchorX = 0.5
				if i == 1 and #labels > 1 then
					align = Enum.TextXAlignment.Left
					anchorX = 0
				elseif i == #labels and #labels > 1 then
					align = Enum.TextXAlignment.Right
					anchorX = 1
				end
				Create.Text({
					Size = UDim2.fromOffset(labelWidth, 14),
					Position = UDim2.fromScale(scaleX, 0),
					AnchorPoint = Vector2.new(anchorX, 0),
					Text = tostring(labels[i]),
					TextSize = 10,
					TextXAlignment = align,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Color = "Muted",
					Parent = xAxisRow,
				})
				lastPlacedScale = scaleX
			end
		end
	end

	local function redrawChart()
		for _, child in ipairs(geomLayer:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(plottedCoords)
		table.clear(barFrames)

		local count = #points
		if count == 0 then
			yMaxLabel.Text = ""
			yMidLabel.Text = ""
			yMinLabel.Text = ""
			refreshDefaultReadout()
			return
		end

		local minV, maxV = computeMinMax(points)
		local span = maxV - minV
		local midV = (minV + maxV) * 0.5

		yMaxLabel.Text = formatNumericValue(maxV, opts.Prefix, "", opts.Decimals)
		yMidLabel.Text = formatNumericValue(midV, opts.Prefix, "", opts.Decimals)
		yMinLabel.Text = formatNumericValue(minV, opts.Prefix, "", opts.Decimals)

		local w = plotCanvas.AbsoluteSize.X
		local h = plotCanvas.AbsoluteSize.Y
		if w <= 4 or h <= 4 then
			refreshDefaultReadout()
			return
		end

		if mode == "Bar" then
			local gap = count > 24 and 2 or 4
			local barW = math.max(2, (w - (count - 1) * gap) / count)
			for i = 1, count do
				local val = tonumber(points[i]) or minV
				local norm = Util.Clamp((val - minV) / span, 0, 1)
				local barH = math.max(4, norm * (h - 4))
				local xLeft = (i - 1) * (barW + gap)
				local yTop = h - barH

				local bar = Create.New("Frame", {
					Name = "Bar_" .. i,
					Size = UDim2.fromOffset(barW, barH),
					Position = UDim2.fromOffset(xLeft, yTop),
					Corner = math.min(4, math.floor(barW * 0.4)),
					ZIndex = 2,
					Parent = geomLayer,
				})
				bindColorProp(bar, "BackgroundColor3", colorSpec)

				local grad = Instance.new("UIGradient")
				grad.Rotation = 90
				grad.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.08),
					NumberSequenceKeypoint.new(1, 0.58),
				})
				grad.Parent = bar

				plottedCoords[i] = Vector2.new(xLeft + barW * 0.5, yTop)
				barFrames[i] = bar
			end
		else
			if count == 1 then
				local py = h * 0.5
				plottedCoords[1] = Vector2.new(w * 0.5, py)
			else
				local padTop = 4
				local usableH = math.max(1, h - padTop * 2)
				for i = 1, count do
					local val = tonumber(points[i]) or minV
					local norm = Util.Clamp((val - minV) / span, 0, 1)
					local px = ((i - 1) / (count - 1)) * w
					local py = padTop + (1 - norm) * usableH
					plottedCoords[i] = Vector2.new(px, py)
				end

				-- Smooth area gradient strips beneath the piecewise line
				local stripCount = math.min(44, math.max(count * 2, 24))
				local stripW = (w / stripCount) + 1
				for s = 0, stripCount - 1 do
					local sampleX = ((s + 0.5) / stripCount) * w
					local t = (sampleX / w) * (count - 1) + 1
					local idx0 = Util.Clamp(math.floor(t), 1, count - 1)
					local frac = t - idx0
					local yVal = Util.Lerp(plottedCoords[idx0].Y, plottedCoords[idx0 + 1].Y, frac)
					local stripH = math.max(1, h - yVal)

					local strip = Create.New("Frame", {
						Name = "Area_" .. s,
						Position = UDim2.fromOffset(s * (w / stripCount), yVal),
						Size = UDim2.fromOffset(stripW, stripH),
						ZIndex = 2,
						Parent = geomLayer,
					})
					bindColorProp(strip, "BackgroundColor3", colorSpec)

					local areaGrad = Instance.new("UIGradient")
					areaGrad.Rotation = 90
					areaGrad.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.72),
						NumberSequenceKeypoint.new(1, 0.99),
					})
					areaGrad.Parent = strip
				end

				-- Crisp rotated line segments + vertex dots
				for i = 1, count - 1 do
					local p1, p2 = plottedCoords[i], plottedCoords[i + 1]
					local dx, dy = p2.X - p1.X, p2.Y - p1.Y
					local len = math.sqrt(dx * dx + dy * dy)
					local seg = Create.New("Frame", {
						Name = "Line_" .. i,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset((p1.X + p2.X) * 0.5, (p1.Y + p2.Y) * 0.5),
						Size = UDim2.fromOffset(len + 1.5, 2),
						Rotation = math.deg(math.atan2(dy, dx)),
						Corner = 999,
						ZIndex = 3,
						Parent = geomLayer,
					})
					bindColorProp(seg, "BackgroundColor3", colorSpec)
				end

				for i = 1, count do
					local p = plottedCoords[i]
					local vertex = Create.New("Frame", {
						Name = "Pt_" .. i,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(p.X, p.Y),
						Size = UDim2.fromOffset(4, 4),
						Corner = 999,
						ZIndex = 4,
						Parent = geomLayer,
					})
					bindColorProp(vertex, "BackgroundColor3", colorSpec)
				end
			end
		end

		refreshDefaultReadout()
	end

	local function updateHoverAt(pos)
		local count = #points
		if count == 0 or #plottedCoords == 0 then
			return
		end
		local cPos, cSize = plotCanvas.AbsolutePosition, plotCanvas.AbsoluteSize
		if cSize.X <= 0 then
			return
		end
		local relX = Util.Clamp((pos.X - cPos.X) / cSize.X, 0, 1)
		local idx
		if mode == "Bar" then
			idx = Util.Clamp(math.floor(relX * count) + 1, 1, count)
		else
			idx = count == 1 and 1 or Util.Clamp(math.floor(relX * (count - 1) + 0.5) + 1, 1, count)
		end

		hoveredIndex = idx
		local coord = plottedCoords[idx]
		if coord then
			crosshair.Visible = true
			crosshair.Position = UDim2.fromOffset(coord.X, 0)
			dotHalo.Visible = true
			dotHalo.Position = UDim2.fromOffset(coord.X, coord.Y)
		end

		local val = tonumber(points[idx]) or points[idx]
		readoutLabel.Text = formatNumericValue(val, opts.Prefix, opts.Suffix, opts.Decimals)
		hoverTagLabel.TextTransparency = 0
		local lbl = labels[idx]
		if lbl and lbl ~= "" then
			hoverTagLabel.Text = tostring(lbl)
			hoverTagLabel.Visible = true
		else
			hoverTagLabel.Text = "#" .. idx
			hoverTagLabel.Visible = true
		end
	end

	local function clearHover()
		hoveredIndex = nil
		crosshair.Visible = false
		dotHalo.Visible = false
		refreshDefaultReadout()
	end

	self.Maid:Give(hitOverlay.MouseMoved:Connect(function()
		if Transition.IsOverlayBlocking(hitOverlay) then
			clearHover()
			return
		end
		updateHoverAt(Util.MousePosition())
	end))
	self.Maid:Give(hitOverlay.MouseLeave:Connect(clearHover))
	self.Maid:Give(hitOverlay.InputBegan:Connect(function(input)
		if Transition.IsOverlayBlocking(hitOverlay) then
			return
		end
		if Util.IsPointer(input) then
			updateHoverAt(Util.MousePosition())
		end
	end))
	self.Maid:Give(hitOverlay.InputChanged:Connect(function(input)
		if Transition.IsOverlayBlocking(hitOverlay) then
			clearHover()
			return
		end
		if Util.IsMove(input) then
			updateHoverAt(Util.MousePosition())
		end
	end))

	self.Maid:Give(plotCanvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		rebuildXLabels()
		redrawChart()
	end))

	function self:SetPoints(pts, newLabels)
		points = type(pts) == "table" and Util.Copy(pts) or {}
		if newLabels ~= nil then
			labels = type(newLabels) == "table" and Util.Copy(newLabels) or {}
			rebuildXLabels()
		end
		self.Value = points
		redrawChart()
	end

	function self:Push(val, label)
		table.insert(points, val)
		if label ~= nil then
			table.insert(labels, label)
		end
		if type(maxPoints) == "number" and maxPoints > 0 then
			while #points > maxPoints do
				table.remove(points, 1)
				if #labels > 0 then
					table.remove(labels, 1)
				end
			end
		end
		self.Value = points
		if label ~= nil then
			rebuildXLabels()
		end
		redrawChart()
	end

	function self:Get()
		return Util.Copy(points)
	end

	local baseSetTitle = self.SetTitle
	function self:SetTitle(text)
		titleLabel.Text = tostring(text or "")
		if baseSetTitle then
			pcall(baseSetTitle, self, text)
		end
	end

	rebuildXLabels()
	task.defer(redrawChart)
	return self
end

-- ─── 3. ProgressBar ──────────────────────────────────────────────────────────

local ProgressBar = {}
ProgressBar.__index = ProgressBar

function ProgressBar.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Title = "Progress",
		Value = 0,
		Max = 100,
		Suffix = "%",
		Badge = nil,
		SecondaryLabel = nil,
		Gradient = true,
		Height = 8,
		Color = "Accent",
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("ProgressBar", parent, opts, ctx)
	local cardParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local cardFrame, cardStroke, cardUI = unwrapCard(cardParent, opts)

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = cardFrame
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	local currentVal = tonumber(opts.Value) or 0
	local currentMax = math.max(1e-6, tonumber(opts.Max) or 100)
	local useGradient = opts.Gradient ~= false
	local colorSpec = resolveColorSpec(opts.Color, "Accent")
	local barHeight = math.max(4, tonumber(opts.Height) or 8)

	self.Value = currentVal
	self.Stroke = cardStroke

	local content = Create.New("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = 12,
		Parent = cardFrame,
	})
	Create.List(content, { Gap = 8 })

	local topRow = Create.New("Frame", {
		Name = "TopRow",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = content,
	})

	local rightRow = Create.New("Frame", {
		Name = "Right",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = topRow,
	})
	Create.List(rightRow, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		HAlign = Enum.HorizontalAlignment.Right,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local valueText = Create.Text({
		Name = "ValueText",
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 12,
		Font = "SemiBold",
		Color = "SubText",
		LayoutOrder = 1,
		Parent = rightRow,
	})

	local badgeObj
	local badgeFrame
	local badgeLabel
	if opts.Badge and opts.Badge ~= "" then
		badgeObj = Base.Badge(rightRow, tostring(opts.Badge), "Accent")
		if typeof(badgeObj) == "Instance" then
			badgeFrame = badgeObj
			badgeLabel = badgeObj:IsA("TextLabel") and badgeObj or badgeObj:FindFirstChildOfClass("TextLabel")
		else
			badgeFrame = badgeObj.Frame
			badgeLabel = badgeObj.Label
		end
		if badgeFrame then
			badgeFrame.LayoutOrder = 2
		end
	end

	local titleLabel = Create.Text({
		Name = "Title",
		Size = UDim2.new(1, -148, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = tostring(opts.Title or "Progress"),
		TextSize = 13,
		Font = "Medium",
		TextWrapped = true,
		Color = "Text",
		Parent = topRow,
	})

	local track = Create.New("Frame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 0, barHeight),
		Corner = 999,
		ClipsDescendants = true,
		LayoutOrder = 2,
		Theme = { BackgroundColor3 = "Field" },
		Parent = content,
	})
	Create.Stroke(track, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })

	local ratio = Util.Clamp(currentVal / currentMax, 0, 1)
	local fill = Create.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(ratio, 1),
		Corner = 999,
		Parent = track,
	})

	if useGradient then
		fill.BackgroundColor3 = Color3.new(1, 1, 1)
		local grad = Instance.new("UIGradient")
		grad.Color = Theme.AccentSequence()
		grad.Parent = fill
		local conn = Theme.Changed:Connect(function(t)
			grad.Color = Theme.AccentSequence(t)
		end)
		self.Maid:Give(conn)
	else
		bindColorProp(fill, "BackgroundColor3", colorSpec)
	end

	local secondaryLabel
	if opts.SecondaryLabel and opts.SecondaryLabel ~= "" then
		secondaryLabel = Create.Text({
			Name = "Secondary",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = tostring(opts.SecondaryLabel),
			TextSize = 11,
			TextWrapped = true,
			Color = "Muted",
			LayoutOrder = 3,
			Parent = content,
		})
	end

	if self.BindUI then
		self:BindUI({
			Frame = cardFrame,
			Stroke = cardStroke,
			TitleLabel = titleLabel,
			DescLabel = secondaryLabel,
			LockOverlay = cardUI and cardUI.LockOverlay or nil,
			SetDisabled = cardUI and cardUI.SetDisabled or nil,
			Lock = cardUI and cardUI.Lock or nil,
			Unlock = cardUI and cardUI.Unlock or nil,
			Flash = cardUI and cardUI.Flash or nil,
		})
	end

	if opts.Tooltip and Tooltip and Tooltip.Bind then
		pcall(Tooltip.Bind, cardFrame, opts.Tooltip)
	end

	local function refreshText()
		local displayNum
		if opts.Suffix == "%" and currentMax ~= 100 then
			displayNum = Util.Clamp((currentVal / currentMax) * 100, 0, 100)
		else
			displayNum = currentVal
		end
		valueText.Text = formatNumericValue(displayNum, "", opts.Suffix or "%")
	end

	function self:Set(val, maxVal, badgeText, silent)
		if maxVal ~= nil then
			currentMax = math.max(1e-6, tonumber(maxVal) or currentMax)
		end
		currentVal = Util.Clamp(tonumber(val) or 0, 0, currentMax)
		self.Value = currentVal

		local targetRatio = Util.Clamp(currentVal / currentMax, 0, 1)
		Tween.Play(fill, { Size = UDim2.fromScale(targetRatio, 1) }, Tween.Normal)
		refreshText()

		if badgeText ~= nil and badgeObj then
			if type(badgeObj) == "table" and badgeObj.SetText then
				pcall(badgeObj.SetText, badgeObj, tostring(badgeText))
			end
			if badgeLabel then
				badgeLabel.Text = tostring(badgeText)
			end
		end

		if not silent then
			self.Changed:Fire(currentVal, currentMax)
		end
	end

	function self:Get()
		return currentVal
	end

	local baseSetTitle = self.SetTitle
	function self:SetTitle(text)
		titleLabel.Text = tostring(text or "")
		if baseSetTitle then
			pcall(baseSetTitle, self, text)
		end
	end

	refreshText()
	return self
end

-- ─── 4. Table ────────────────────────────────────────────────────────────────

local Table = {}
Table.__index = Table

function Table.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Title = nil,
		Columns = {},
		Rows = {},
		Selectable = false,
		MaxHeight = 240,
		Searchable = false,
		OnRowClick = nil,
		Action = nil,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("Table", parent, opts, ctx)
	local cardParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local cardFrame, cardStroke, cardUI = unwrapCard(cardParent, opts)

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = cardFrame
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	local columns = type(opts.Columns) == "table" and opts.Columns or {}
	local rowsData = type(opts.Rows) == "table" and opts.Rows or {}
	local selectable = opts.Selectable == true
	local searchable = opts.Searchable == true
	local maxHeight = math.max(80, tonumber(opts.MaxHeight) or 240)
	local actionDef = type(opts.Action) == "table" and opts.Action or nil
	local selectedSet = {} -- [rowTable] = true
	local searchQuery = ""

	self.Value = rowsData
	self.Stroke = cardStroke

	local content = Create.New("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = 12,
		Parent = cardFrame,
	})
	Create.List(content, { Gap = 8 })

	local titleLabel
	local searchInput
	if (opts.Title and opts.Title ~= "") or searchable then
		local topHeader = Create.New("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = content,
		})

		titleLabel = Create.Text({
			Name = "Title",
			Size = UDim2.new(1, searchable and -154 or 0, 1, 0),
			Text = tostring(opts.Title or ""),
			TextSize = 13,
			Font = "SemiBold",
			TextTruncate = Enum.TextTruncate.AtEnd,
			Color = "Text",
			Parent = topHeader,
		})

		if searchable then
			local searchWrap = Create.New("Frame", {
				Name = "SearchWrap",
				Size = UDim2.fromOffset(146, 26),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Corner = 7,
				Padding = { 0, 8, 0, 8 },
				Theme = { BackgroundColor3 = "Field" },
				Parent = topHeader,
			})
			local searchStroke = Create.Stroke(searchWrap, {
				Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
			})
			Icons.Create("search", {
				Size = UDim2.fromOffset(12, 12),
				Position = UDim2.new(0, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Color = "Muted",
				Parent = searchWrap,
			})
			searchInput = Create.Text({
				Class = "TextBox",
				Size = UDim2.new(1, -18, 1, 0),
				Position = UDim2.fromOffset(18, 0),
				Text = "",
				PlaceholderText = "Filter...",
				TextSize = 11,
				Theme = {
					TextColor3 = "Text",
					PlaceholderColor3 = "Muted",
				},
				Parent = searchWrap,
			})
			searchInput.Focused:Connect(function()
				Theme.Bind(searchStroke, { Color = "Accent", Transparency = function() return 0.35 end })
			end)
			searchInput.FocusLost:Connect(function()
				Theme.Bind(searchStroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
			end)
		end
	end

	-- Exact shared column geometry calculator
	local checkReserve = selectable and 28 or 0
	local actionReserve = actionDef and 78 or 0
	local colGap = 6

	local fixedPx = 0
	local fixedScale = 0
	local autoCount = 0
	for _, col in ipairs(columns) do
		if type(col.Width) == "number" then
			if col.Width > 0 and col.Width <= 1 then
				fixedScale += col.Width
			else
				fixedPx += col.Width
			end
		elseif typeof(col.Width) == "UDim" then
			fixedScale += col.Width.Scale
			fixedPx += col.Width.Offset
		else
			autoCount += 1
		end
	end
	local totalGap = math.max(0, #columns - 1) * colGap

	local function colUDim(col)
		if type(col.Width) == "number" then
			if col.Width > 0 and col.Width <= 1 then
				return UDim.new(col.Width, -math.ceil(totalGap * col.Width + 0.5))
			end
			return UDim.new(0, col.Width)
		elseif typeof(col.Width) == "UDim" then
			return col.Width
		end
		local s = math.max(0.05, (1 - fixedScale) / math.max(1, autoCount))
		local o = -math.ceil((fixedPx + totalGap) / math.max(1, autoCount))
		return UDim.new(s, o)
	end

	-- Column Header Bar
	local colHeader = Create.New("Frame", {
		Name = "ColumnsHeader",
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 2,
		Corner = 7,
		Padding = { 0, 8, 0, 8 },
		Theme = {
			BackgroundColor3 = "Tile",
			BackgroundTransparency = "TileTransparency",
		},
		Parent = content,
	})

	local headerColsWrap = Create.New("Frame", {
		Size = UDim2.new(1, -(checkReserve + actionReserve), 1, 0),
		Position = UDim2.fromOffset(checkReserve, 0),
		BackgroundTransparency = 1,
		Parent = colHeader,
	})
	Create.List(headerColsWrap, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = colGap,
		VAlign = Enum.VerticalAlignment.Center,
	})

	for idx, col in ipairs(columns) do
		local w = colUDim(col)
		Create.Text({
			Name = "ColH_" .. idx,
			Size = UDim2.new(w.Scale, w.Offset, 1, 0),
			LayoutOrder = idx,
			Text = tostring(col.Title or col.Key or ""),
			TextSize = 11,
			Font = "SemiBold",
			TextXAlignment = resolveAlign(col.Align),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Color = "SubText",
			Parent = headerColsWrap,
		})
	end

	local scroll = Create.New("ScrollingFrame", {
		Name = "RowsScroll",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		LayoutOrder = 3,
		Theme = { ScrollBarImageColor3 = "Muted" },
		Parent = content,
	})
	Create.Padding(scroll, { 3, 6, 3, 3 })
	local scrollLayout = Create.List(scroll, { Gap = 4 })

	local emptyLabel = Create.Text({
		Name = "Empty",
		Size = UDim2.new(1, 0, 0, 34),
		Text = "No matching rows",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Color = "Muted",
		Visible = false,
		Parent = scroll,
	})

	if self.BindUI then
		self:BindUI({
			Frame = cardFrame,
			Stroke = cardStroke,
			TitleLabel = titleLabel,
			LockOverlay = cardUI and cardUI.LockOverlay or nil,
			SetDisabled = cardUI and cardUI.SetDisabled or nil,
			Lock = cardUI and cardUI.Lock or nil,
			Unlock = cardUI and cardUI.Unlock or nil,
			Flash = cardUI and cardUI.Flash or nil,
		})
	end

	if opts.Tooltip and Tooltip and Tooltip.Bind then
		pcall(Tooltip.Bind, cardFrame, opts.Tooltip)
	end

	local rowObjects = {}

	local function syncScrollHeight()
		local contentY = scrollLayout.AbsoluteContentSize.Y
		if contentY > 0 then
			scroll.Size = UDim2.new(1, 0, 0, math.min(contentY, maxHeight))
		else
			local visibleCount = 0
			for _, obj in ipairs(rowObjects) do
				if obj.Button.Visible then
					visibleCount += 1
				end
			end
			local est = visibleCount == 0 and 34 or (visibleCount * 36 + math.max(0, visibleCount - 1) * 4)
			scroll.Size = UDim2.new(1, 0, 0, math.min(est, maxHeight))
		end
	end

	scrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncScrollHeight)

	local function rowMatchesQuery(row)
		if searchQuery == "" then
			return true
		end
		for _, col in ipairs(columns) do
			local raw = row[col.Key]
			local txt = type(raw) == "table" and (raw.Text or raw.Value or "") or raw
			if txt ~= nil and Util.Matches(tostring(txt), searchQuery) then
				return true
			end
		end
		return false
	end

	local function applyFilter()
		local any = false
		for _, obj in ipairs(rowObjects) do
			local ok = rowMatchesQuery(obj.Row)
			obj.Button.Visible = ok
			if ok then
				any = true
			end
		end
		emptyLabel.Visible = not any
		task.defer(syncScrollHeight)
	end

	local function updateRowCheck(obj)
		local active = selectedSet[obj.Row] == true
		if obj.CheckBox then
			Theme.Bind(obj.CheckBox, {
				BackgroundColor3 = active and "Accent" or "Field",
			})
			Theme.Bind(obj.CheckStroke, {
				Color = active and "Accent" or "Stroke",
				Transparency = active and function() return 0.2 end or "StrokeTransparency",
			})
			if obj.CheckIcon then
				obj.CheckIcon.Visible = active
			end
		end
		Theme.Bind(obj.Button, {
			BackgroundColor3 = active and "Accent" or "TileHover",
			BackgroundTransparency = active and function() return 0.88 end or function() return obj.Hovered and 0.48 or 1 end,
		})
	end

	local function rebuildRows()
		for _, obj in ipairs(rowObjects) do
			obj.Button:Destroy()
		end
		table.clear(rowObjects)

		for rowIdx, row in ipairs(rowsData) do
			local rowBtn = Create.New("TextButton", {
				Name = "Row_" .. rowIdx,
				Size = UDim2.new(1, 0, 0, 36),
				LayoutOrder = rowIdx,
				Corner = 7,
				Padding = { 0, 4, 0, 8 },
				BackgroundTransparency = 1,
				Theme = { BackgroundColor3 = "TileHover" },
				Parent = scroll,
			})

			local checkBox, checkStroke, checkIcon
			if selectable then
				checkBox = Create.New("Frame", {
					Name = "Checkbox",
					Size = UDim2.fromOffset(18, 18),
					Position = UDim2.new(0, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					Corner = 5,
					Theme = { BackgroundColor3 = "Field" },
					Parent = rowBtn,
				})
				checkStroke = Create.Stroke(checkBox, {
					Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
				})
				checkIcon = Icons.Create("check", {
					Size = UDim2.fromOffset(11, 11),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Color = "AccentText",
					Parent = checkBox,
				})
				checkIcon.Visible = false
			end

			local cellsWrap = Create.New("Frame", {
				Size = UDim2.new(1, -(checkReserve + actionReserve), 1, 0),
				Position = UDim2.fromOffset(checkReserve, 0),
				BackgroundTransparency = 1,
				Parent = rowBtn,
			})
			Create.List(cellsWrap, {
				Direction = Enum.FillDirection.Horizontal,
				Gap = colGap,
				VAlign = Enum.VerticalAlignment.Center,
			})

			for colIdx, col in ipairs(columns) do
				local w = colUDim(col)
				local cellFrame = Create.New("Frame", {
					Name = "Cell_" .. colIdx,
					Size = UDim2.new(w.Scale, w.Offset, 1, 0),
					LayoutOrder = colIdx,
					BackgroundTransparency = 1,
					Parent = cellsWrap,
				})

				local raw = row[col.Key]
				local cellText, cellColor, cellIcon, isBadge
				if type(raw) == "table" then
					cellText = tostring(raw.Text ~= nil and raw.Text or (raw.Value or ""))
					cellColor = raw.Color
					cellIcon = raw.Icon
					isBadge = raw.Badge == true
				else
					cellText = raw ~= nil and tostring(raw) or ""
				end
				if not cellIcon and colIdx == 1 then
					cellIcon = row.Icon
				end
				if not cellColor and col.Color then
					if type(col.Color) == "function" then
						cellColor = col.Color(raw, row)
					else
						cellColor = col.Color
					end
				end

				local resolvedColor = cellColor and resolveColorSpec(cellColor, "Text") or "Text"
				local align = resolveAlign(col.Align)

				if isBadge then
					local pill = Create.New("Frame", {
						Size = UDim2.fromOffset(0, 22),
						AutomaticSize = Enum.AutomaticSize.X,
						Position = UDim2.new(
							align == Enum.TextXAlignment.Right and 1 or (align == Enum.TextXAlignment.Center and 0.5 or 0),
							0,
							0.5,
							0
						),
						AnchorPoint = Vector2.new(
							align == Enum.TextXAlignment.Right and 1 or (align == Enum.TextXAlignment.Center and 0.5 or 0),
							0.5
						),
						Corner = 999,
						Padding = { 0, 8, 0, 8 },
						Theme = { BackgroundTransparency = function() return 0.85 end },
						Parent = cellFrame,
					})
					bindColorProp(pill, "BackgroundColor3", resolvedColor)
					local pillLbl = Create.Text({
						Size = UDim2.fromOffset(0, 22),
						AutomaticSize = Enum.AutomaticSize.X,
						Text = cellText,
						TextSize = 11,
						Font = "SemiBold",
						TextTruncate = Enum.TextTruncate.AtEnd,
						Parent = pill,
					})
					bindColorProp(pillLbl, "TextColor3", resolvedColor)
				else
					local iconOffset = 0
					if cellIcon then
						iconOffset = 20
						Icons.Create(cellIcon, {
							Size = UDim2.fromOffset(14, 14),
							Position = UDim2.new(0, 0, 0.5, 0),
							AnchorPoint = Vector2.new(0, 0.5),
							Color = resolvedColor == "Text" and "SubText" or resolvedColor,
							Parent = cellFrame,
						})
					end
					local cellLbl = Create.Text({
						Size = UDim2.new(1, -iconOffset, 1, 0),
						Position = UDim2.fromOffset(iconOffset, 0),
						Text = cellText,
						TextSize = 12,
						Font = colIdx == 1 and "Medium" or "Regular",
						TextXAlignment = align,
						TextTruncate = Enum.TextTruncate.AtEnd,
						Parent = cellFrame,
					})
					bindColorProp(cellLbl, "TextColor3", resolvedColor)
				end
			end

			if actionDef then
				local actBtn = Create.New("TextButton", {
					Name = "ActionBtn",
					Size = UDim2.fromOffset(72, 24),
					Position = UDim2.new(1, 0, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Text = "",
					AutoButtonColor = false,
					BackgroundTransparency = 0,
					Corner = 6,
					Padding = { 0, 6, 0, 6 },
					Theme = { BackgroundColor3 = "Field" },
					Parent = rowBtn,
				})
				local actStroke = Create.Stroke(actBtn, {
					Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
				})
				Transition.Hover(actBtn, actBtn, "Field", "FieldHover", actStroke)
				local actInner = Create.New("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Parent = actBtn,
				})
				Create.List(actInner, {
					Direction = Enum.FillDirection.Horizontal,
					Gap = 4,
					HAlign = Enum.HorizontalAlignment.Center,
					VAlign = Enum.VerticalAlignment.Center,
				})
				if actionDef.Icon then
					Icons.Create(actionDef.Icon, {
						Size = UDim2.fromOffset(11, 11),
						Color = "Accent",
						LayoutOrder = 1,
						Parent = actInner,
					})
				end
				if actionDef.Title and actionDef.Title ~= "" then
					Create.Text({
						Size = UDim2.fromOffset(0, 24),
						AutomaticSize = Enum.AutomaticSize.X,
						Text = tostring(actionDef.Title),
						TextSize = 11,
						Font = "SemiBold",
						TextXAlignment = Enum.TextXAlignment.Center,
						TextTruncate = Enum.TextTruncate.AtEnd,
						Color = "Accent",
						LayoutOrder = 2,
						Parent = actInner,
					})
				end
				actBtn.Activated:Connect(function()
					Transition.Ripple(actBtn, nil, "Accent")
					if actionDef.Callback then
						Util.Spawn(actionDef.Callback, row, rowIdx)
					end
				end)
			end

			local obj = {
				Row = row,
				Index = rowIdx,
				Button = rowBtn,
				CheckBox = checkBox,
				CheckStroke = checkStroke,
				CheckIcon = checkIcon,
				Hovered = false,
			}

			rowBtn.MouseEnter:Connect(function()
				obj.Hovered = true
				updateRowCheck(obj)
			end)
			rowBtn.MouseLeave:Connect(function()
				obj.Hovered = false
				updateRowCheck(obj)
			end)
			rowBtn.Activated:Connect(function()
				if selectable then
					selectedSet[row] = not selectedSet[row] or nil
					updateRowCheck(obj)
					self.Changed:Fire(self:GetSelected())
				end
				if opts.OnRowClick then
					Util.Spawn(opts.OnRowClick, row, rowIdx)
				end
			end)

			updateRowCheck(obj)
			table.insert(rowObjects, obj)
		end

		applyFilter()
	end

	if searchInput then
		searchInput:GetPropertyChangedSignal("Text"):Connect(function()
			searchQuery = Util.Trim(searchInput.Text)
			applyFilter()
		end)
	end

	function self:SetRows(newRows)
		rowsData = type(newRows) == "table" and newRows or {}
		self.Value = rowsData
		table.clear(selectedSet)
		rebuildRows()
	end

	function self:GetSelected()
		local rows, indices = {}, {}
		for _, obj in ipairs(rowObjects) do
			if selectedSet[obj.Row] then
				table.insert(rows, obj.Row)
				table.insert(indices, obj.Index)
			end
		end
		return rows, indices
	end

	local baseSetTitle = self.SetTitle
	function self:SetTitle(text)
		if titleLabel then
			titleLabel.Text = tostring(text or "")
		end
		if baseSetTitle then
			pcall(baseSetTitle, self, text)
		end
	end

	rebuildRows()
	return self
end

-- ─── 5. CardGrid ─────────────────────────────────────────────────────────────

local CardGrid = {}
CardGrid.__index = CardGrid

function CardGrid.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Cards = {},
		Default = nil,
		Callback = nil,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("CardGrid", parent, opts, ctx)

	local container = Create.New("Frame", {
		Name = "CardGrid",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = container
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
		container.Parent = self.Frame
	end

	if self.BindUI then
		self:BindUI({ Frame = container })
	end

	if opts.Tooltip and Tooltip and Tooltip.Bind then
		pcall(Tooltip.Bind, container, opts.Tooltip)
	end

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.Parent = container

	local cards = type(opts.Cards) == "table" and Util.Copy(opts.Cards) or {}
	local activeId = opts.Default
	if activeId == nil and opts.Default ~= false then
		for _, c in ipairs(cards) do
			if c.Active then
				activeId = c.Id
				break
			end
		end
		if activeId == nil and cards[1] then
			activeId = cards[1].Id
		end
	elseif activeId == false then
		activeId = nil
	end
	self.Value = activeId

	local cardEntries = {} -- [id] = { CardData, Button, Stroke, Gradient, TitleLabel, IconObj, MetricRows }

	local function getCardHeight()
		local maxMetrics = 0
		for _, c in ipairs(cards) do
			local count = type(c.Metrics) == "table" and #c.Metrics or 0
			if count > maxMetrics then
				maxMetrics = count
			end
		end
		return math.max(76, 44 + maxMetrics * 20 + 12)
	end

	local function updateGridCellSize()
		local count = math.max(1, #cards)
		local width = container.AbsoluteSize.X
		local cols
		if count == 1 then
			cols = 1
		elseif width <= 0 or width >= 520 then
			cols = math.min(count, 4)
		elseif width >= 220 then
			cols = math.min(count, 2)
		else
			cols = 1
		end
		local gapTotal = (cols - 1) * 8
		local offsetAdjust = -math.ceil(gapTotal / cols)
		gridLayout.CellSize = UDim2.new(1 / cols, offsetAdjust, 0, getCardHeight())
	end

	local function styleCardEntry(entry, isActive)
		if isActive then
			entry.Button.BackgroundColor3 = Color3.new(1, 1, 1)
			Theme.Unbind(entry.Button, "BackgroundColor3")
			Theme.Unbind(entry.Button, "BackgroundTransparency")
			entry.Button.BackgroundTransparency = 0.04
			entry.Button:SetAttribute("_BaliRestBg", 0.04)
			entry.Button:SetAttribute("_BaliCascadeBg", 0.04)
			entry.Gradient.Enabled = true
			entry.Gradient.Color = Theme.AccentSequence()
			Theme.Bind(entry.Stroke, {
				Color = "Accent",
				Transparency = function() return 0.25 end,
			})
			entry.Stroke:SetAttribute("_BaliRestStr", 0.25)
			entry.Stroke:SetAttribute("_BaliCascadeStroke", 0.25)
			Theme.Bind(entry.TitleLabel, { TextColor3 = "AccentText" })
			if entry.IconObj then
				Icons.SetColor(entry.IconObj, "AccentText")
			end
			for _, m in ipairs(entry.MetricRows) do
				Theme.Bind(m.Label, { TextColor3 = "AccentText" })
				m.Label.TextTransparency = 0.08
				Theme.Bind(m.Value, { TextColor3 = "AccentText" })
			end
		else
			entry.Gradient.Enabled = false
			Theme.Bind(entry.Button, {
				BackgroundColor3 = entry.Hovered and "TileHover" or "Tile",
				BackgroundTransparency = "TileTransparency",
			})
			entry.Button:SetAttribute("_BaliRestBg", Theme.Current.TileTransparency)
			entry.Button:SetAttribute("_BaliCascadeBg", Theme.Current.TileTransparency)
			Theme.Bind(entry.Stroke, {
				Color = "Stroke",
				Transparency = "StrokeTransparency",
			})
			entry.Stroke:SetAttribute("_BaliRestStr", Theme.Current.StrokeTransparency)
			entry.Stroke:SetAttribute("_BaliCascadeStroke", Theme.Current.StrokeTransparency)
			Theme.Bind(entry.TitleLabel, { TextColor3 = "Text" })
			if entry.IconObj then
				Icons.SetColor(entry.IconObj, "Accent")
			end
			for _, m in ipairs(entry.MetricRows) do
				Theme.Bind(m.Label, { TextColor3 = "SubText" })
				m.Label.TextTransparency = 0
				Theme.Bind(m.Value, { TextColor3 = "Text" })
			end
		end
	end

	local function refreshAllCards()
		for id, entry in pairs(cardEntries) do
			styleCardEntry(entry, id == activeId)
		end
	end

	local themeConn = Theme.Changed:Connect(refreshAllCards)
	self.Maid:Give(themeConn)

	local function buildCard(index, card)
		local btn = Create.New("TextButton", {
			Name = "Card_" .. tostring(card.Id or index),
			LayoutOrder = index,
			Corner = 11,
			Padding = 11,
			Theme = {
				BackgroundColor3 = "Tile",
				BackgroundTransparency = "TileTransparency",
			},
			Parent = container,
		})
		local stroke = Create.GlassStroke(btn, 0.05)

		local grad = Instance.new("UIGradient")
		grad.Rotation = 135
		grad.Color = Theme.AccentSequence()
		grad.Enabled = false
		grad.Parent = btn

		local inner = Create.New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = btn,
		})
		Create.List(inner, { Gap = 8 })

		local top = Create.New("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = inner,
		})

		local iconOffset = 0
		local iconObj
		if card.Icon then
			iconOffset = 20
			iconObj = Icons.Create(card.Icon, {
				Size = UDim2.fromOffset(15, 15),
				Position = UDim2.new(0, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Color = "Accent",
				Parent = top,
			})
		end

		local titleLbl = Create.Text({
			Size = UDim2.new(1, -iconOffset, 1, 0),
			Position = UDim2.fromOffset(iconOffset, 0),
			Text = tostring(card.Title or card.Id or ""),
			TextSize = 13,
			Font = "SemiBold",
			TextTruncate = Enum.TextTruncate.AtEnd,
			Color = "Text",
			Parent = top,
		})

		local metricsBox = Create.New("Frame", {
			Name = "Metrics",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = inner,
		})
		Create.List(metricsBox, { Gap = 4 })

		local metricRows = {}
		if type(card.Metrics) == "table" then
			for mIdx, metric in ipairs(card.Metrics) do
				local mRow = Create.New("Frame", {
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					LayoutOrder = mIdx,
					Parent = metricsBox,
				})
				local lbl = Create.Text({
					Size = UDim2.new(0.55, 0, 1, 0),
					Text = tostring(metric.Label or ""),
					TextSize = 11,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Color = "SubText",
					Parent = mRow,
				})
				local val = Create.Text({
					Size = UDim2.new(0.45, 0, 1, 0),
					Position = UDim2.fromScale(1, 0),
					AnchorPoint = Vector2.new(1, 0),
					Text = tostring(metric.Value or ""),
					TextSize = 11,
					Font = "SemiBold",
					TextXAlignment = Enum.TextXAlignment.Right,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Color = "Text",
					Parent = mRow,
				})
				table.insert(metricRows, { Label = lbl, Value = val })
			end
		end

		local entry = {
			Card = card,
			Button = btn,
			Stroke = stroke,
			Gradient = grad,
			TitleLabel = titleLbl,
			IconObj = iconObj,
			MetricRows = metricRows,
			Hovered = false,
		}

		btn.MouseEnter:Connect(function()
			entry.Hovered = true
			if activeId ~= card.Id then
				Theme.Bind(btn, { BackgroundColor3 = "TileHover" })
			end
		end)
		btn.MouseLeave:Connect(function()
			entry.Hovered = false
			if activeId ~= card.Id then
				Theme.Bind(btn, { BackgroundColor3 = "Tile" })
			end
		end)
		btn.Activated:Connect(function()
			Transition.Ripple(btn, nil, "Accent")
			self:SetActive(card.Id, false)
		end)

		cardEntries[card.Id] = entry
		styleCardEntry(entry, card.Id == activeId)
	end

	local function rebuildAll()
		for _, entry in pairs(cardEntries) do
			entry.Button:Destroy()
		end
		table.clear(cardEntries)
		for index, card in ipairs(cards) do
			buildCard(index, card)
		end
		updateGridCellSize()
	end

	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridCellSize)

	function self:SetActive(id, silent)
		activeId = id
		self.Value = activeId
		refreshAllCards()
		if not silent then
			local entry = cardEntries[id]
			local cardData = entry and entry.Card or nil
			if opts.Callback then
				Util.Spawn(opts.Callback, id, cardData)
			end
			self.Changed:Fire(id, cardData)
		end
	end
	self.Set = self.SetActive

	function self:UpdateCard(id, data)
		if type(data) ~= "table" then
			return
		end
		for i, card in ipairs(cards) do
			if card.Id == id then
				for k, v in pairs(data) do
					card[k] = v
				end
				if data.Active == true then
					activeId = card.Id
					self.Value = activeId
				end
				local old = cardEntries[id]
				if old then
					old.Button:Destroy()
					cardEntries[id] = nil
				end
				buildCard(i, card)
				updateGridCellSize()
				refreshAllCards()
				return
			end
		end
	end

	function self:Get()
		return activeId
	end

	rebuildAll()
	return self
end

Analytics.StatCard = StatCard
Analytics.Chart = Chart
Analytics.ProgressBar = ProgressBar
Analytics.Table = Table
Analytics.CardGrid = CardGrid

return Analytics
