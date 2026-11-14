--[[
	Bali UI · Window/Tab
	Sidebar category headers, grouped tab buttons with animated active pill &
	collapse rail support, Apple segmented SubTab bar, and responsive 2-col -> 1-col layout.
]]

local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Maid = require("Core/Maid")
local Theme = require("Core/Theme")
local Transition = require("Core/Transition")
local Tween = require("Core/Tween")
local Util = require("Core/Util")
local Tooltip = require("Systems/Tooltip")
local Container = require("Window/Container")
local Section = require("Window/Section")

local Tab = {}
Tab.__index = Tab

-- ─── Category Header Helper ──────────────────────────────────────────────────

function Tab.CategoryHeader(parent, name, layoutOrder)
	local header = Create.New("Frame", {
		Name = "Category_" .. tostring(name),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = layoutOrder or 0,
		Parent = parent,
	})

	local label = Create.Text({
		Name = "Label",
		Text = string.upper(tostring(name)),
		Font = "Bold",
		TextSize = 10,
		Color = "Muted",
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -16, 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})

	local compactLine = Create.New("Frame", {
		Name = "CompactDivider",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 1),
		Visible = false,
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = header,
	})

	local obj = {
		Name = name,
		Frame = header,
		Label = label,
		CompactLine = compactLine,
	}

	function obj:SetCompact(compact, instant)
		compact = compact == true
		label.Visible = not compact
		compactLine.Visible = compact
		local targetHeight = compact and 12 or 24
		if instant then
			header.Size = UDim2.new(1, 0, 0, targetHeight)
		else
			Tween.Play(header, { Size = UDim2.new(1, 0, 0, targetHeight) }, Tween.Fast)
		end
	end

	return obj
end

-- ─── Responsive Flow Page Helper ─────────────────────────────────────────────

local function createFlowController(tab, parent, subTab)
	local window = tab.Window

	local scroll = Create.New("ScrollingFrame", {
		Name = subTab and ("SubPage_" .. tostring(subTab.Title)) or "DefaultPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Theme = { ScrollBarImageColor3 = "Muted" },
		Padding = (window and window.IsMobileMode and window:IsMobileMode()) and { 10, 10, 14, 10 } or { 14, 16, 18, 16 },
		Parent = parent,
	})
	Create.List(scroll, { Gap = 12 })

	local flow = {
		Scroll = scroll,
		SubTab = subTab,
		CurrentPair = nil,
		Order = 0,
		_pairs = {},
	}

	function flow.NextOrder()
		flow.Order += 1
		return flow.Order
	end

	function flow.ClosePair()
		flow.CurrentPair = nil
	end

	local function getOrCreatePair()
		if flow.CurrentPair then
			return flow.CurrentPair
		end

		local row = Create.New("Frame", {
			Name = "ColumnRow",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = flow.NextOrder(),
			Parent = scroll,
		})

		local rowLayout = Create.List(row, {
			Direction = Enum.FillDirection.Horizontal,
			Gap = 12,
		})

		local leftCol = Create.New("Frame", {
			Name = "LeftColumn",
			Size = UDim2.new(0.5, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = row,
		})
		local leftLayout = Create.List(leftCol, { Gap = 12 })

		local rightCol = Create.New("Frame", {
			Name = "RightColumn",
			Size = UDim2.new(0.5, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = row,
		})
		local rightLayout = Create.List(rightCol, { Gap = 12 })

		local pair = {
			Row = row,
			Left = leftCol,
			Right = rightCol,
			LeftLayout = leftLayout,
			RightLayout = rightLayout,
			LeftCount = 0,
			RightCount = 0,
		}

		function pair.ApplyLayout(windowWidth)
			local isMobile = window and window.IsMobileMode and window:IsMobileMode()
			local stacked = isMobile or (windowWidth or 820) < 620
			if stacked then
				rowLayout.FillDirection = Enum.FillDirection.Vertical
				leftCol.Size = UDim2.new(1, 0, 0, 0)
				rightCol.Size = UDim2.new(1, 0, 0, 0)
				leftCol.Visible = pair.LeftCount > 0
				rightCol.Visible = pair.RightCount > 0
			else
				rowLayout.FillDirection = Enum.FillDirection.Horizontal
				leftCol.Size = UDim2.new(0.5, -6, 0, 0)
				rightCol.Size = UDim2.new(0.5, -6, 0, 0)
				leftCol.Visible = true
				rightCol.Visible = true
			end
		end

		if window and window._layoutChanged then
			tab.Maid:Give(window._layoutChanged:Connect(function(size)
				pair.ApplyLayout(size.X)
			end))
		end
		pair.ApplyLayout(window and window:GetWidth() or 820)

		table.insert(flow._pairs, pair)
		flow.CurrentPair = pair
		return pair
	end

	function flow.RefreshLayout(windowWidth)
		local isMobile = window and window.IsMobileMode and window:IsMobileMode()
		local pad = scroll:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, isMobile and 10 or 14)
			pad.PaddingRight = UDim.new(0, isMobile and 10 or 16)
			pad.PaddingBottom = UDim.new(0, isMobile and 14 or 18)
			pad.PaddingLeft = UDim.new(0, isMobile and 10 or 16)
		end
		for _, pair in ipairs(flow._pairs) do
			pair.ApplyLayout(windowWidth)
		end
	end

	function flow.AddSection(opts)
		opts = Util.Options(opts, { Side = "Auto" }, "Title")
		local side = string.lower(tostring(opts.Side or "Auto"))

		if side == "full" then
			flow.ClosePair()
			opts.LayoutOrder = flow.NextOrder()
			return Section.new(scroll, opts, tab, window, subTab)
		end

		local pair = getOrCreatePair()
		local targetSide
		if side == "left" then
			targetSide = "left"
		elseif side == "right" then
			targetSide = "right"
		else
			local leftH = pair.LeftLayout.AbsoluteContentSize.Y
			local rightH = pair.RightLayout.AbsoluteContentSize.Y
			if leftH ~= rightH and (leftH > 0 or rightH > 0) then
				targetSide = (leftH <= rightH) and "left" or "right"
			else
				targetSide = (pair.LeftCount <= pair.RightCount) and "left" or "right"
			end
		end

		local colParent
		if targetSide == "left" then
			pair.LeftCount += 1
			opts.LayoutOrder = pair.LeftCount
			colParent = pair.Left
		else
			pair.RightCount += 1
			opts.LayoutOrder = pair.RightCount
			colParent = pair.Right
		end

		pair.ApplyLayout(window and window:GetWidth() or 820)
		return Section.new(colParent, opts, tab, window, subTab)
	end

	return flow
end

-- ─── Tab Constructor ─────────────────────────────────────────────────────────

function Tab.new(window, options)
	options = Util.Options(options, {
		Title = "Tab",
		Icon = nil,
		Category = nil,
		Badge = nil,
		LayoutOrder = 0,
	}, "Title")

	local maid = Maid.new()

	-- Sidebar navigation button
	local button = Create.New("TextButton", {
		Name = "Tab_" .. tostring(options.Title),
		Size = UDim2.new(1, 0, 0, 36),
		Theme = { BackgroundColor3 = "Tile" },
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Corner = 9,
		LayoutOrder = options.LayoutOrder or 0,
		Parent = window._tabScroll,
	})
	maid:Give(button)

	local activeFill = Create.New("Frame", {
		Name = "ActiveFill",
		Size = UDim2.fromScale(1, 1),
		Theme = { BackgroundColor3 = "Accent" },
		BackgroundTransparency = 1,
		Corner = 9,
		ZIndex = 1,
		Parent = button,
	})
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = 0
	fillGradient.Color = Theme.AccentSequence()
	fillGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	fillGradient.Parent = activeFill
	maid:Give(Theme.Changed:Connect(function(theme)
		fillGradient.Color = Theme.AccentSequence(theme)
	end))

	local activeStroke = Create.Stroke(button, {
		Theme = { Color = "Accent" },
		Thickness = 1,
		Transparency = 1,
	})

	local indicator = Create.New("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 0),
		Corner = 2,
		Theme = { BackgroundColor3 = "Accent" },
		ZIndex = 3,
		Parent = button,
	})

	local iconInst = Icons.Create(options.Icon, {
		Name = "Icon",
		Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 13, 0.5, 0),
		Color = "SubText",
		ZIndex = 3,
		Parent = button,
	})

	local titleLabel = Create.Text({
		Name = "Title",
		Text = tostring(options.Title),
		Font = "Medium",
		TextSize = 13,
		Color = "SubText",
		Position = UDim2.new(0, iconInst and 38 or 12, 0, 0),
		Size = UDim2.new(1, iconInst and -46 or -20, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = button,
	})

	local badgeFrame = Create.New("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Corner = 999,
		Theme = { BackgroundColor3 = "Accent" },
		BackgroundTransparency = 0.82,
		Visible = false,
		ZIndex = 3,
		Padding = { 0, 7, 0, 7 },
		Parent = button,
	})
	local badgeLabel = Create.Text({
		Name = "Text",
		Text = "",
		Font = "SemiBold",
		TextSize = 10,
		Color = "Accent",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = badgeFrame,
	})

	-- Main tab page container
	local page = Create.New("Frame", {
		Name = "Page_" .. tostring(options.Title),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ClipsDescendants = true,
		Parent = window.PageContainer,
	})
	maid:Give(page)

	-- Optional SubTab header bar (hidden until AddSubTab is called)
	local subTabWrap = Create.New("Frame", {
		Name = "SubTabBar",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 36),
		Corner = 10,
		Theme = { BackgroundColor3 = "Field" },
		Visible = false,
		Padding = 3,
		Parent = page,
	})
	Create.GlassStroke(subTabWrap, 0.02)

	local subTabScroll = Create.New("ScrollingFrame", {
		Name = "SubTabScroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Parent = subTabWrap,
	})

	local subTabIndicator = Create.New("Frame", {
		Name = "ActivePill",
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.new(0, 0, 1, -4),
		Corner = 8,
		Theme = { BackgroundColor3 = "Accent" },
		BackgroundTransparency = 0.78,
		Visible = false,
		ZIndex = 1,
		Parent = subTabScroll,
	})
	local pillGradient = Create.New("UIGradient", {
		Color = Theme.AccentSequence(),
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
		Parent = subTabIndicator,
	})
	maid:Give(Theme.Changed:Connect(function(theme)
		pillGradient.Color = Theme.AccentSequence(theme)
	end))
	Create.Stroke(subTabIndicator, {
		Theme = { Color = "Accent" },
		Transparency = 0.35,
		Thickness = 1,
	})

	local subTabButtons = Create.New("Frame", {
		Name = "Buttons",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = subTabScroll,
	})
	Create.List(subTabButtons, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 4,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local subPageHolder = Create.New("Frame", {
		Name = "SubPages",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = page,
	})

	local self = setmetatable({
		Type = "Tab",
		Title = tostring(options.Title),
		Icon = options.Icon,
		Category = options.Category,
		Window = window,
		Maid = maid,
		_button = button,
		Page = page,
		SubTabs = {},
		ActiveSubTab = nil,
		Selected = false,
		_compact = window._sidebarCollapsed == true,
		_activeFill = activeFill,
		_activeStroke = activeStroke,
		_indicator = indicator,
		_iconInst = iconInst,
		_titleLabel = titleLabel,
		_badgeFrame = badgeFrame,
		_badgeLabel = badgeLabel,
		_subTabWrap = subTabWrap,
		_subTabScroll = subTabScroll,
		_subTabIndicator = subTabIndicator,
		_subTabButtons = subTabButtons,
		_subPageHolder = subPageHolder,
	}, Tab)

	self._defaultFlow = createFlowController(self, subPageHolder, nil)
	self._flows = { self._defaultFlow }

	-- Attach Container directly onto Tab as a convenience fallback for direct calls
	self._beforeAdd = function()
		self._defaultFlow.ClosePair()
	end
	Container.Attach(self, self._defaultFlow.Scroll, self, nil, window, nil)

	if options.Badge ~= nil then
		self:SetBadge(options.Badge)
	end
	self:SetCompact(self._compact, true)

	maid:Give(button.MouseEnter:Connect(function()
		if not self.Selected and not Transition.IsOverlayBlocking(button) then
			Tween.Play(button, { BackgroundTransparency = 0.55 }, Tween.Instant)
			if self._iconInst then
				Icons.SetColor(self._iconInst, "Text")
			end
			Theme.Bind(titleLabel, { TextColor3 = "Text" })
		end
	end))

	maid:Give(button.MouseLeave:Connect(function()
		if not self.Selected then
			Tween.Play(button, { BackgroundTransparency = 1 }, Tween.Instant)
			if self._iconInst then
				Icons.SetColor(self._iconInst, "SubText")
			end
			Theme.Bind(titleLabel, { TextColor3 = "SubText" })
		end
	end))

	maid:Give(button.Activated:Connect(function(input)
		if Transition.IsOverlayBlocking(button) then
			return
		end
		Transition.Ripple(button, input, "Accent")
		self:Select()
	end))

	Tooltip.Bind(button, function()
		if window._sidebarCollapsed then
			return self.Title
		end
		return ""
	end)

	return self
end

function Tab:SetTitle(text)
	self.Title = tostring(text or "")
	self._titleLabel.Text = self.Title
	if self.Window and self.Window.ActiveTab == self then
		self.Window:_updateBreadcrumb()
	end
end

function Tab:SetBadge(text)
	if text == nil or text == "" or text == false then
		self._badgeFrame.Visible = false
		self._badgeLabel.Text = ""
	else
		self._badgeLabel.Text = tostring(text)
		self._badgeFrame.Visible = not self._compact
	end
	local rightPad = self._badgeFrame.Visible and -86 or -46
	local leftX = self._iconInst and 38 or 12
	self._titleLabel.Size = UDim2.new(1, self._iconInst and rightPad or -20, 1, 0)
	self._titleLabel.Position = UDim2.new(0, leftX, 0, 0)
end

function Tab:SetCompact(compact, instant)
	compact = compact == true
	self._compact = compact
	if compact then
		self._titleLabel.Visible = false
		self._badgeFrame.Visible = false
		if self._iconInst then
			self._iconInst.AnchorPoint = Vector2.new(0.5, 0.5)
			self._iconInst.Position = UDim2.fromScale(0.5, 0.5)
		end
	else
		self._titleLabel.Visible = true
		self._titleLabel.TextTransparency = 1
		self._badgeFrame.Visible = self._badgeLabel.Text ~= ""
		if self._iconInst then
			self._iconInst.AnchorPoint = Vector2.new(0, 0.5)
			self._iconInst.Position = UDim2.new(0, 13, 0.5, 0)
		end
		if instant then
			self._titleLabel.TextTransparency = 0
		else
			Tween.Play(self._titleLabel, { TextTransparency = 0 }, Tween.Fast)
		end
	end
	if self._indicator then
		self._indicator.Position = UDim2.new(0, compact and 2 or 0, 0.5, 0)
		if self.Selected then
			self._indicator.Size = compact and UDim2.fromOffset(2, 14) or UDim2.fromOffset(3, 18)
		else
			self._indicator.Size = compact and UDim2.fromOffset(2, 0) or UDim2.fromOffset(3, 0)
		end
	end
end

function Tab:_setActiveVisual(active, instant)
	self.Selected = active == true
	local fillT = active and 0.8 or 1
	local strokeT = active and 0.68 or 1
	local indW = self._compact and 2 or 3
	local indH = active and (self._compact and 14 or 18) or 0
	local indSize = UDim2.fromOffset(indW, indH)

	if active then
		Theme.Bind(self._titleLabel, { TextColor3 = "Text", FontFace = "@SemiBold" })
		if self._iconInst then
			Icons.SetColor(self._iconInst, "Accent")
		end
	else
		Theme.Bind(self._titleLabel, { TextColor3 = "SubText", FontFace = "@Medium" })
		if self._iconInst then
			Icons.SetColor(self._iconInst, "SubText")
		end
	end

	if instant then
		self._button.BackgroundTransparency = 1
		self._activeFill.BackgroundTransparency = fillT
		self._activeStroke.Transparency = strokeT
		self._indicator.Size = indSize
	else
		Tween.Play(self._button, { BackgroundTransparency = 1 }, Tween.Fast)
		Tween.Play(self._activeFill, { BackgroundTransparency = fillT }, Tween.Fast)
		Tween.Play(self._activeStroke, { Transparency = strokeT }, Tween.Fast)
		Tween.Spring(self._indicator, { Size = indSize }, Tween.Normal)
	end

	if not active then
		if self._defaultFlow and self._defaultFlow.Scroll then
			Transition.RestoreCascade(self._defaultFlow.Scroll)
		end
		for _, candidate in ipairs(self.SubTabs) do
			if candidate.Scroll then
				Transition.RestoreCascade(candidate.Scroll)
			end
		end
	else
		self:_syncSubTabIndicator(instant)
	end
	self.Page.Visible = active
	if active and not instant then
		local activeScroll = self.ActiveSubTab and self.ActiveSubTab.Scroll or self._defaultFlow.Scroll
		Transition.Cascade(activeScroll, 0.018, 12, 10)
	end
end

function Tab:_syncSubTabIndicator(instant)
	local subTab = self.ActiveSubTab
	if not subTab or not subTab._button then
		return
	end
	local btn = subTab._button
	local function applyPill()
		if not btn.Parent or not self._subTabButtons.Parent then
			return
		end
		local x = btn.AbsolutePosition.X - self._subTabButtons.AbsolutePosition.X
		local w = btn.AbsoluteSize.X
		if w <= 0 then
			return
		end
		self._subTabIndicator.Visible = true
		local targetPos = UDim2.fromOffset(x, 2)
		local targetSize = UDim2.new(0, w, 1, -4)
		if instant then
			self._subTabIndicator.Position = targetPos
			self._subTabIndicator.Size = targetSize
		else
			Tween.Play(
				self._subTabIndicator,
				{ Position = targetPos, Size = targetSize },
				Tween.Normal,
				Enum.EasingStyle.Exponential,
				Enum.EasingDirection.Out
			)
		end
	end
	applyPill()
	task.defer(applyPill)
end

function Tab:Select()
	if self.Window and type(self.Window.SelectTab) == "function" then
		self.Window:SelectTab(self)
	end
end

function Tab:AddSection(options)
	return self._defaultFlow.AddSection(options)
end

function Tab:SelectSubTab(subTab)
	if type(subTab) == "string" then
		for _, candidate in ipairs(self.SubTabs) do
			if candidate.Title == subTab then
				subTab = candidate
				break
			end
		end
	elseif type(subTab) == "number" then
		subTab = self.SubTabs[subTab]
	end
	if type(subTab) ~= "table" or not subTab.Scroll then
		return
	end

	if self.ActiveSubTab == subTab then
		return
	end

	local oldIdx, newIdx = 1, 1
	for idx, candidate in ipairs(self.SubTabs) do
		if candidate == self.ActiveSubTab then
			oldIdx = idx
		end
		if candidate == subTab then
			newIdx = idx
		end
	end
	local dir = (newIdx >= oldIdx) and 1 or -1

	for _, candidate in ipairs(self.SubTabs) do
		local isCurrent = (candidate == subTab)
		if not isCurrent and candidate.Scroll then
			Transition.RestoreCascade(candidate.Scroll)
		end
		candidate.Scroll.Visible = isCurrent
		Theme.Bind(candidate._titleLabel, {
			TextColor3 = isCurrent and "Text" or "SubText",
			FontFace = isCurrent and "@Bold" or "@Medium",
		})
		if candidate._iconInst then
			Icons.SetColor(candidate._iconInst, isCurrent and "Accent" or "SubText")
		end
	end

	self.ActiveSubTab = subTab
	Transition.Cascade(subTab.Scroll, 0.018, 12, dir * 12)
	self:_syncSubTabIndicator(false)

	if self.Window and self.Window.ActiveTab == self then
		self.Window:_updateBreadcrumb()
	end
end

function Tab:AddSubTab(options)
	options = Util.Options(options, { Title = "SubTab", Icon = nil }, "Title")

	if not self._subTabWrap.Visible then
		self._subTabWrap.Visible = true
		self._defaultFlow.Scroll.Visible = false
		self._subPageHolder.Position = UDim2.fromOffset(0, 50)
		self._subPageHolder.Size = UDim2.new(1, 0, 1, -50)
	end

	local order = #self.SubTabs + 1
	local subBtn = Create.New("TextButton", {
		Name = "SubTab_" .. tostring(options.Title),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Corner = 8,
		Padding = { 0, 12, 0, 12 },
		LayoutOrder = order,
		Parent = self._subTabButtons,
	})
	Create.List(subBtn, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local subIcon = Icons.Create(options.Icon, {
		Size = UDim2.fromOffset(14, 14),
		Color = "SubText",
		LayoutOrder = 1,
		Parent = subBtn,
	})

	local subLabel = Create.Text({
		Name = "Title",
		Text = tostring(options.Title),
		Font = "Medium",
		TextSize = 12,
		Color = "SubText",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = subBtn,
	})

	local subTab = {
		Type = "SubTab",
		Title = tostring(options.Title),
		Icon = options.Icon,
		Tab = self,
		Window = self.Window,
		Maid = self.Maid,
		_button = subBtn,
		_titleLabel = subLabel,
		_iconInst = subIcon,
	}

	local flow = createFlowController(self, self._subPageHolder, subTab)
	table.insert(self._flows, flow)
	flow.Scroll.Visible = false
	subTab.Scroll = flow.Scroll
	subTab.Page = flow.Scroll
	subTab._beforeAdd = function()
		flow.ClosePair()
	end

	function subTab:AddSection(secOpts)
		return flow.AddSection(secOpts)
	end

	function subTab:Select()
		self.Tab:SelectSubTab(self)
	end

	function subTab:SetTitle(text)
		self.Title = tostring(text or "")
		self._titleLabel.Text = self.Title
		if self.Tab.ActiveSubTab == self and self.Window and self.Window.ActiveTab == self.Tab then
			self.Window:_updateBreadcrumb()
		end
	end

	Container.Attach(subTab, flow.Scroll, self, nil, self.Window, subTab)

	Theme.Bind(subBtn, { BackgroundColor3 = "Tile" })
	local subHovered = false
	self.Maid:Give(subBtn.MouseEnter:Connect(function()
		if self.ActiveSubTab == subTab or Util.IsTouchDevice() or Transition.IsOverlayBlocking(subBtn) then
			return
		end
		subHovered = true
		Tween.Play(subBtn, { BackgroundTransparency = 0.52 }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween.Play(subLabel, { TextColor3 = Theme.Current.Text }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end))
	self.Maid:Give(subBtn.MouseLeave:Connect(function()
		subHovered = false
		Tween.Play(subBtn, { BackgroundTransparency = 1 }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		if self.ActiveSubTab ~= subTab then
			Tween.Play(subLabel, { TextColor3 = Theme.Current.SubText }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
	end))

	self.Maid:Give(subBtn.Activated:Connect(function()
		if Transition.IsOverlayBlocking(subBtn) then
			return
		end
		if subHovered then
			subBtn.BackgroundTransparency = 1
		end
		self:SelectSubTab(subTab)
	end))

	table.insert(self.SubTabs, subTab)
	if #self.SubTabs == 1 then
		self:SelectSubTab(subTab)
	end

	return subTab
end

function Tab:RefreshLayout(windowWidth)
	local w = windowWidth or (self.Window and self.Window:GetWidth()) or 820
	if self._flows then
		for _, flow in ipairs(self._flows) do
			if flow.RefreshLayout then
				flow.RefreshLayout(w)
			end
		end
	end
	if self._syncSubTabIndicator then
		self:_syncSubTabIndicator(true)
	end
end

function Tab:Destroy()
	self.Maid:Clean()
end

return Tab
