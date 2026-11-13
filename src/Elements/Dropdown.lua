--[[
	Lumina UI · Elements/Dropdown
	Single & multi-select glass dropdown with optional search, item icons/descriptions,
	and floating PopupLayer menu with smart flip & smooth mount/unmount animations.
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

local Dropdown = {}
Dropdown.__index = Dropdown

local function normalizeItem(entry)
	if type(entry) == "table" then
		local title = tostring(entry.Title or entry.Name or entry.Text or entry.Value or "")
		local value = entry.Value
		if value == nil then
			value = entry.Title or entry.Name or entry.Text or title
		end
		return {
			Title = title,
			Desc = entry.Desc or entry.Description,
			Icon = entry.Icon,
			Value = value,
		}
	end
	local text = tostring(entry)
	return {
		Title = text,
		Desc = nil,
		Icon = nil,
		Value = entry,
	}
end

local function normalizeList(values)
	local items = {}
	if type(values) ~= "table" then
		return items
	end
	for _, entry in ipairs(values) do
		table.insert(items, normalizeItem(entry))
	end
	return items
end

local function cloneArray(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

local function isDisabledOrLocked(self)
	return self.Disabled == true or self.Locked == true or self._disabled == true or self._locked == true
end

function Dropdown.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Title = "Dropdown",
		Description = nil,
		Values = {},
		Default = nil,
		Multi = false,
		Searchable = false,
		AllowNull = false,
		MaxVisible = 6,
		Callback = nil,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("Dropdown", parent, opts, ctx)
	local rowParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local rightWidth = 136
	local row = Base.Row(rowParent, opts, rightWidth)

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = row.Frame
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	if self.BindUI then
		self:BindUI(row)
	end

	self._row = row
	self.Row = row
	self.TitleLabel = row.TitleLabel
	self.DescLabel = row.DescLabel
	self.Stroke = row.Stroke
	self.LockOverlay = row.LockOverlay

	if opts.Tooltip and Tooltip and Tooltip.Bind then
		pcall(Tooltip.Bind, row.Frame, opts.Tooltip)
	end

	local items = normalizeList(opts.Values)
	local multi = opts.Multi == true
	local allowNull = opts.AllowNull == true
	local searchable = opts.Searchable == true
	local maxVisible = math.max(1, tonumber(opts.MaxVisible) or 6)

	local selectedSingle = nil
	local selectedMap = {} -- [item] = true (keyed by item reference for exact identity)
	local isOpen = false
	local searchQuery = ""
	local popupId = "Dropdown_" .. Util.RandomString(8)
	local optionRows = {} -- { { Item, Button, CheckIcon, TitleLabel, DescLabel } }
	local openGen = 0

	-- Right-side trigger pill
	local trigger = Create.New("TextButton", {
		Name = "Trigger",
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		Corner = 8,
		Padding = { 0, 8, 0, 10 },
		Theme = {
			BackgroundColor3 = "Field",
		},
		Parent = row.Right,
	})
	local triggerStroke = Create.Stroke(trigger, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})

	local summaryLabel = Create.Text({
		Name = "Summary",
		Size = UDim2.new(1, -20, 1, 0),
		Text = "Select...",
		TextSize = 12,
		Font = "Medium",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Color = "Muted",
		Parent = trigger,
	})

	local chevron = Icons.Create("chevron-down", {
		Name = "Chevron",
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = "SubText",
		Parent = trigger,
	})
	local chevronBaseRot = chevron and chevron.Rotation or 0

	Transition.Hover(trigger, trigger, "Field", "FieldHover", triggerStroke)

	-- Floating popup frame (parented in PopupLayer when open)
	local shadowInfo = Assets.Shadow()
	local shadowInset = shadowInfo.Inset or 24

	local popup = Create.New("Frame", {
		Name = popupId,
		Size = UDim2.fromOffset(220, 120),
		Visible = false,
		ZIndex = 110,
		Corner = 10,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency or 0.12, 0.04)
			end,
		},
	})
	Create.GlassStroke(popup, 0.06)

	Create.New("ImageLabel", {
		Name = "Shadow",
		Size = UDim2.new(1, shadowInset * 2, 1, shadowInset * 2),
		Position = UDim2.fromOffset(-shadowInset, -shadowInset),
		Image = shadowInfo.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowInfo.Slice,
		ZIndex = 109,
		Theme = {
			ImageColor3 = "Shadow",
			ImageTransparency = "ShadowTransparency",
		},
		Parent = popup,
	})

	local popupInner = Create.New("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 111,
		Corner = 10,
		Padding = { 8, 8, 8, 8 },
		Parent = popup,
	})
	Create.List(popupInner, { Gap = 6 })

	local searchBox
	local clearSearchBtn
	if searchable then
		local searchWrap = Create.New("Frame", {
			Name = "SearchWrap",
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = 1,
			ZIndex = 112,
			Corner = 7,
			Padding = { 0, 8, 0, 8 },
			Theme = { BackgroundColor3 = "Field" },
			Parent = popupInner,
		})
		local searchStroke = Create.Stroke(searchWrap, {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
		})

		Icons.Create("search", {
			Size = UDim2.fromOffset(13, 13),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = "Muted",
			ZIndex = 113,
			Parent = searchWrap,
		})

		searchBox = Create.Text({
			Class = "TextBox",
			Name = "SearchInput",
			Size = UDim2.new(1, -38, 1, 0),
			Position = UDim2.fromOffset(19, 0),
			Text = "",
			PlaceholderText = "Search...",
			TextSize = 12,
			Font = "Regular",
			ZIndex = 113,
			Theme = {
				TextColor3 = "Text",
				PlaceholderColor3 = "Muted",
			},
			Parent = searchWrap,
		})

		clearSearchBtn = Create.New("TextButton", {
			Name = "ClearSearch",
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, 0, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Visible = false,
			ZIndex = 113,
			Parent = searchWrap,
		})
		Icons.Create("x", {
			Size = UDim2.fromOffset(12, 12),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = "Muted",
			ZIndex = 114,
			Parent = clearSearchBtn,
		})

		searchBox.Focused:Connect(function()
			Theme.Bind(searchStroke, { Color = "Accent", Transparency = function() return 0.35 end })
		end)
		searchBox.FocusLost:Connect(function()
			Theme.Bind(searchStroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
		end)
	end

	local scroll = Create.New("ScrollingFrame", {
		Name = "OptionsScroll",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		LayoutOrder = 2,
		ZIndex = 112,
		Theme = { ScrollBarImageColor3 = "Muted" },
		Parent = popupInner,
	})
	Create.Padding(scroll, { 0, 4, 0, 0 })
	local scrollLayout = Create.List(scroll, { Gap = 4 })

	local emptyLabel = Create.Text({
		Name = "Empty",
		Size = UDim2.new(1, 0, 0, 28),
		Text = "No results found",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Color = "Muted",
		Visible = false,
		ZIndex = 113,
		Parent = scroll,
	})

	local function findItemByInput(val)
		if val == nil then
			return nil
		end
		for _, item in ipairs(items) do
			if item.Value == val then
				return item
			end
		end
		local strVal = tostring(val)
		for _, item in ipairs(items) do
			if item.Title == strVal or tostring(item.Value) == strVal then
				return item
			end
		end
		if type(val) == "number" and items[val] then
			return items[val]
		end
		return nil
	end

	local function getSelectedValues()
		if multi then
			local list = {}
			for _, item in ipairs(items) do
				if selectedMap[item] then
					table.insert(list, item.Value)
				end
			end
			return list
		end
		return selectedSingle and selectedSingle.Value or nil
	end

	local function updateSummary()
		if multi then
			local titles = {}
			for _, item in ipairs(items) do
				if selectedMap[item] then
					table.insert(titles, item.Title)
				end
			end
			if #titles == 0 then
				summaryLabel.Text = "None"
				Theme.Bind(summaryLabel, { TextColor3 = "Muted" })
			else
				summaryLabel.Text = table.concat(titles, ", ")
				Theme.Bind(summaryLabel, { TextColor3 = "Text" })
			end
		else
			if selectedSingle then
				summaryLabel.Text = selectedSingle.Title
				Theme.Bind(summaryLabel, { TextColor3 = "Text" })
			else
				summaryLabel.Text = "Select..."
				Theme.Bind(summaryLabel, { TextColor3 = "Muted" })
			end
		end
	end

	local function isItemSelected(item)
		if multi then
			return selectedMap[item] == true
		end
		return selectedSingle == item
	end

	local function updateOptionVisuals()
		for _, entry in ipairs(optionRows) do
			local active = isItemSelected(entry.Item)
			Theme.Bind(entry.Button, {
				BackgroundColor3 = active and "Accent" or "TileHover",
				BackgroundTransparency = active and function() return 0.84 end or function() return entry.Hovered and 0.4 or 1 end,
			})
			Theme.Bind(entry.Stroke, {
				Color = active and "Accent" or "Stroke",
				Transparency = active and function() return 0.58 end or function() return 1 end,
			})
			Theme.Bind(entry.TitleLabel, {
				TextColor3 = active and "Text" or "SubText",
				FontFace = active and "@SemiBold" or "@Medium",
			})
			if entry.CheckIcon then
				entry.CheckIcon.Visible = active
			end
		end
	end

	local function resizePopup(preserveFlip)
		local searchH = searchable and 36 or 0
		local visibleCount = 0
		local hasDesc = false
		for _, entry in ipairs(optionRows) do
			if entry.Button.Visible then
				visibleCount += 1
				if entry.Item.Desc and entry.Item.Desc ~= "" then
					hasDesc = true
				end
			end
		end

		local contentH = scrollLayout.AbsoluteContentSize.Y
		local estPerRow = hasDesc and 44 or 32
		local maxListH = maxVisible * estPerRow + math.max(0, maxVisible - 1) * 4
		local listH
		if visibleCount == 0 then
			listH = 30
		elseif contentH > 0 then
			listH = math.min(contentH, maxListH)
		else
			local shown = math.min(visibleCount, maxVisible)
			listH = shown * estPerRow + math.max(0, shown - 1) * 4
		end

		local anchorW = (trigger.AbsoluteSize.X > 0) and trigger.AbsoluteSize.X or 136
		local width = Util.Clamp(anchorW + 56, 192, 268)
		local totalH = 16 + searchH + listH

		local prevBottom = popup.AbsolutePosition.Y + popup.AbsoluteSize.Y
		local anchorTop = trigger.AbsolutePosition.Y
		local wasFlipped = preserveFlip == true and isOpen and popup.Parent ~= nil and prevBottom <= anchorTop + 4

		scroll.Size = UDim2.new(1, 0, 0, listH)
		popup.Size = UDim2.fromOffset(width, totalH)

		-- Keep bottom anchored if popup flipped above trigger and search shrank height
		if wasFlipped and popup.AbsolutePosition.Y > 0 then
			local newY = anchorTop - totalH - 6
			popup.Position = UDim2.fromOffset(popup.Position.X.Offset, math.max(8, newY))
		end
	end

	local function applyFilter(preserveFlip)
		local anyVisible = false
		for _, entry in ipairs(optionRows) do
			local match = Util.Matches(entry.Item.Title, searchQuery)
				or (entry.Item.Desc and Util.Matches(entry.Item.Desc, searchQuery))
			entry.Button.Visible = match
			if match then
				anyVisible = true
			end
		end
		emptyLabel.Visible = not anyVisible
		if clearSearchBtn then
			clearSearchBtn.Visible = searchQuery ~= ""
		end
		task.defer(function()
			if popup.Parent then
				resizePopup(preserveFlip)
			end
		end)
	end

	local function fireSelection(silent)
		local value = getSelectedValues()
		self.Value = value
		updateSummary()
		updateOptionVisuals()
		if not silent then
			if opts.Callback then
				Util.Spawn(opts.Callback, multi and cloneArray(value) or value)
			end
			self.Changed:Fire(multi and cloneArray(value) or value)
		end
	end

	local function onSelectItem(item)
		if isDisabledOrLocked(self) then
			return
		end
		if multi then
			if selectedMap[item] then
				if not allowNull then
					local count = 0
					for _ in pairs(selectedMap) do
						count += 1
					end
					if count <= 1 then
						return
					end
				end
				selectedMap[item] = nil
			else
				selectedMap[item] = true
			end
			fireSelection(false)
		else
			if selectedSingle == item then
				if allowNull then
					selectedSingle = nil
					fireSelection(false)
				end
			else
				selectedSingle = item
				fireSelection(false)
			end
			self:Close()
		end
	end

	local function rebuildOptions()
		for _, entry in ipairs(optionRows) do
			entry.Button:Destroy()
		end
		table.clear(optionRows)

		for index, item in ipairs(items) do
			local btn = Create.New("TextButton", {
				Name = "Opt_" .. index,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = index,
				ZIndex = 113,
				Corner = 7,
				Padding = { 6, 8, 6, 8 },
				BackgroundTransparency = 1,
				Theme = { BackgroundColor3 = "TileHover" },
				Parent = scroll,
			})
			local optStroke = Create.Stroke(btn, {
				Transparency = 1,
				Theme = { Color = "Accent" },
			})

			local leftReserve = item.Icon and 22 or 0
			local rightReserve = 20

			if item.Icon then
				Icons.Create(item.Icon, {
					Size = UDim2.fromOffset(14, 14),
					Position = UDim2.new(0, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					Color = "SubText",
					ZIndex = 114,
					Parent = btn,
				})
			end

			local textCol = Create.New("Frame", {
				Size = UDim2.new(1, -(leftReserve + rightReserve), 0, 0),
				Position = UDim2.fromOffset(leftReserve, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 114,
				Parent = btn,
			})
			Create.List(textCol, { Gap = 2 })

			local titleLbl = Create.Text({
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = item.Title,
				TextSize = 12,
				TextWrapped = true,
				Font = "Medium",
				Color = "SubText",
				LayoutOrder = 1,
				ZIndex = 114,
				Parent = textCol,
			})

			local descLbl
			if item.Desc and item.Desc ~= "" then
				descLbl = Create.Text({
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = item.Desc,
					TextSize = 10,
					TextWrapped = true,
					Color = "Muted",
					LayoutOrder = 2,
					ZIndex = 114,
					Parent = textCol,
				})
			end

			local checkIcon = Icons.Create("check", {
				Size = UDim2.fromOffset(13, 13),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Color = "Accent",
				ZIndex = 114,
				Parent = btn,
			})
			if checkIcon then
				checkIcon.Visible = false
			end

			local entry = {
				Item = item,
				Button = btn,
				Stroke = optStroke,
				TitleLabel = titleLbl,
				DescLabel = descLbl,
				CheckIcon = checkIcon,
				Hovered = false,
			}

			btn.MouseEnter:Connect(function()
				entry.Hovered = true
				if not isItemSelected(item) then
					Theme.Bind(btn, { BackgroundColor3 = "TileHover", BackgroundTransparency = function() return 0.45 end })
				end
			end)
			btn.MouseLeave:Connect(function()
				entry.Hovered = false
				if not isItemSelected(item) then
					Theme.Bind(btn, { BackgroundColor3 = "TileHover", BackgroundTransparency = function() return 1 end })
				end
			end)
			btn.Activated:Connect(function()
				Transition.Ripple(btn, nil, "Accent")
				onSelectItem(item)
			end)

			table.insert(optionRows, entry)
		end

		updateOptionVisuals()
		applyFilter()
	end

	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			searchQuery = Util.Trim(searchBox.Text)
			applyFilter(true)
		end)
		clearSearchBtn.Activated:Connect(function()
			searchBox.Text = ""
			searchQuery = ""
			applyFilter(true)
		end)
	end

	-- Fallback screen positioning if ctx.OpenPopup is unavailable
	local fallbackOutsideConn
	local function placePopupFallback()
		local layer = ctx.PopupLayer or row.Frame:FindFirstAncestorOfClass("ScreenGui")
		if not layer then
			return
		end
		popup.Parent = layer
		local viewSize = layer.AbsoluteSize
		local anchorPos = trigger.AbsolutePosition
		local anchorSize = trigger.AbsoluteSize
		local popSize = popup.Size
		local px = Util.Clamp(anchorPos.X + anchorSize.X - popSize.X.Offset, 8, math.max(8, viewSize.X - popSize.X.Offset - 8))
		local py = anchorPos.Y + anchorSize.Y + 6
		if py + popSize.Y.Offset > viewSize.Y - 8 then
			local above = anchorPos.Y - popSize.Y.Offset - 6
			if above >= 8 then
				py = above
			end
		end
		popup.Position = UDim2.fromOffset(px, py)
	end

	local function handleClosedState()
		if not isOpen then
			return
		end
		isOpen = false
		openGen += 1
		local myGen = openGen
		if chevron then
			Tween.Play(chevron, { Rotation = chevronBaseRot }, Tween.Fast)
		end
		if fallbackOutsideConn then
			fallbackOutsideConn:Disconnect()
			fallbackOutsideConn = nil
		end
		Transition.Unmount(popup, 0.94, function()
			if openGen == myGen and not isOpen then
				popup.Visible = false
			end
		end)
	end

	function self:Open()
		if isOpen or isDisabledOrLocked(self) then
			return
		end
		isOpen = true
		openGen += 1

		if searchBox then
			searchBox.Text = ""
			searchQuery = ""
			applyFilter()
		end
		resizePopup()
		popup.Visible = true

		if chevron then
			Tween.Play(chevron, { Rotation = chevronBaseRot + 180 }, Tween.Fast)
		end

		if ctx.OpenPopup then
			if ctx.PopupLayer then
				popup.Parent = ctx.PopupLayer
			end
			ctx.OpenPopup(popupId, popup, trigger, handleClosedState)
		else
			placePopupFallback()
			fallbackOutsideConn = Services.UserInputService.InputBegan:Connect(function(input)
				if input.KeyCode == Enum.KeyCode.Escape then
					self:Close()
				elseif Util.IsPointer(input) then
					local pos = Util.MousePosition()
					local pPos, pSize = popup.AbsolutePosition, popup.AbsoluteSize
					local tPos, tSize = trigger.AbsolutePosition, trigger.AbsoluteSize
					local insidePopup = pos.X >= pPos.X and pos.X <= pPos.X + pSize.X and pos.Y >= pPos.Y and pos.Y <= pPos.Y + pSize.Y
					local insideTrigger = pos.X >= tPos.X and pos.X <= tPos.X + tSize.X and pos.Y >= tPos.Y and pos.Y <= tPos.Y + tSize.Y
					if not insidePopup and not insideTrigger then
						self:Close()
					end
				end
			end)
		end

		Transition.Mount(popup, 0.94)
	end

	function self:Close()
		if not isOpen then
			return
		end
		handleClosedState()
		if ctx.ClosePopup then
			ctx.ClosePopup(popupId)
		end
	end

	function self:Set(val, silent)
		if multi then
			table.clear(selectedMap)
			if type(val) == "table" then
				local isArray = #val > 0
				if isArray then
					for _, v in ipairs(val) do
						local found = findItemByInput(v)
						if found then
							selectedMap[found] = true
						end
					end
				else
					for k, flag in pairs(val) do
						if flag == true then
							local found = findItemByInput(k)
							if found then
								selectedMap[found] = true
							end
						end
					end
				end
			elseif val ~= nil then
				local found = findItemByInput(val)
				if found then
					selectedMap[found] = true
				end
			end
		else
			selectedSingle = findItemByInput(val)
			if not selectedSingle and not allowNull and #items > 0 and val ~= nil then
				selectedSingle = items[1]
			end
		end
		fireSelection(silent == true)
	end

	function self:Get()
		return getSelectedValues()
	end

	function self:SetValues(list)
		local prev = getSelectedValues()
		items = normalizeList(list)
		rebuildOptions()
		if multi then
			self:Set(prev, true)
		else
			local found = findItemByInput(prev)
			if found then
				selectedSingle = found
			elseif not allowNull and #items > 0 then
				selectedSingle = items[1]
			else
				selectedSingle = nil
			end
			self.Value = getSelectedValues()
			updateSummary()
			updateOptionVisuals()
		end
	end
	self.Refresh = self.SetValues

	trigger.Activated:Connect(function()
		if isDisabledOrLocked(self) then
			return
		end
		Transition.Ripple(trigger, nil, "Accent")
		if isOpen then
			self:Close()
		else
			self:Open()
		end
	end)

	-- Wrap Base lifecycle methods to ensure row updates + popup dismissal
	local baseSetTitle = self.SetTitle
	function self:SetTitle(text)
		if baseSetTitle then
			pcall(baseSetTitle, self, text)
		end
		if row.TitleLabel then
			row.TitleLabel.Text = tostring(text or "")
		end
	end

	local baseSetDesc = self.SetDesc
	function self:SetDesc(text)
		if baseSetDesc then
			pcall(baseSetDesc, self, text)
		end
		if row.DescLabel then
			local str = text and tostring(text) or ""
			row.DescLabel.Text = str
			row.DescLabel.Visible = str ~= ""
		end
	end

	local baseSetDisabled = self.SetDisabled
	function self:SetDisabled(disabled)
		self.Disabled = disabled == true
		if disabled then
			self:Close()
		end
		if baseSetDisabled then
			pcall(baseSetDisabled, self, disabled)
		end
	end

	local baseLock = self.Lock
	function self:Lock(reason)
		self.Locked = true
		self:Close()
		if baseLock then
			pcall(baseLock, self, reason)
		end
	end

	local baseUnlock = self.Unlock
	function self:Unlock()
		self.Locked = false
		if baseUnlock then
			pcall(baseUnlock, self)
		end
	end

	self.Maid:Give(function()
		self:Close()
		if fallbackOutsideConn then
			fallbackOutsideConn:Disconnect()
			fallbackOutsideConn = nil
		end
		popup:Destroy()
	end)

	rebuildOptions()
	if opts.Default ~= nil then
		self:Set(opts.Default, true)
	elseif not multi and not allowNull and #items > 0 then
		selectedSingle = items[1]
		self.Value = selectedSingle.Value
		updateSummary()
		updateOptionVisuals()
	else
		self.Value = getSelectedValues()
		updateSummary()
	end

	return self
end

return Dropdown
