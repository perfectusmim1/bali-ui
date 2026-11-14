--[[
	Bali UI · Elements/Dropdown
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

local function resolveCustomColor(val)
	if typeof(val) == "Color3" then
		return val, nil
	elseif type(val) == "string" and val ~= "" then
		if string.sub(val, 1, 1) == "#" then
			local ok, col = pcall(Color3.fromHex, val)
			if ok and typeof(col) == "Color3" then
				return col, nil
			end
		end
		return nil, val
	end
	return nil, nil
end

local function normalizeImageAsset(val)
	if val == nil or val == false or val == "" then
		return nil
	end
	if type(val) == "number" then
		return "rbxassetid://" .. tostring(val)
	elseif type(val) == "string" then
		if string.find(val, "^%d+$") then
			return "rbxassetid://" .. val
		end
		return val
	end
	return nil
end

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
			Image = entry.Image or entry.Thumbnail or entry.Avatar,
			Color = entry.Color or entry.TextColor,
			IconColor = entry.IconColor or entry.Color or entry.TextColor,
			Badge = entry.Badge or entry.Tag,
			BadgeColor = entry.BadgeColor or entry.TagColor or entry.Color,
			RightText = entry.RightText or entry.Hint,
			Disabled = entry.Disabled == true,
			Value = value,
		}
	end
	local text = tostring(entry)
	return {
		Title = text,
		Desc = nil,
		Icon = nil,
		Image = nil,
		Color = nil,
		IconColor = nil,
		Badge = nil,
		BadgeColor = nil,
		RightText = nil,
		Disabled = false,
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

local function resolveDropdownMode(opts)
	if opts.Inline == true then
		return "Inline"
	elseif opts.Inline == false then
		return "Popup"
	end
	if type(opts.Mode) == "string" then
		local lower = string.lower(opts.Mode)
		if lower == "inline" or lower == "expand" or lower == "push" then
			return "Inline"
		end
	end
	return "Popup"
end

function Dropdown.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Title = "Dropdown",
		Description = nil,
		Values = {},
		Default = nil,
		Multi = false,
		Searchable = true,
		AllowNull = false,
		MaxVisible = 7,
		Mode = nil,
		Inline = nil,
		Callback = nil,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("Dropdown", parent, opts, ctx)
	local rowParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local rightWidth = 168
	local rowOpts = table.clone(opts)
	if rowOpts.IconBadge == nil then
		rowOpts.IconBadge = false
	end
	if rowOpts.StackRight == nil then
		rowOpts.StackRight = true
	end
	local row = Base.Row(rowParent, rowOpts, rightWidth)

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = row.Frame
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	-- Host trigger row + optional InlineClip inside CardContent so LockOverlay stays full-bleed
	local cardContent = Create.New("Frame", {
		Name = "CardContent",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = row.Frame,
	})
	Create.List(cardContent, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 0,
	})
	row.Body.LayoutOrder = 1
	row.Body.Parent = cardContent

	local inlineClip = Create.New("Frame", {
		Name = "InlineClip",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = cardContent,
	})

	local inlineDivider = Create.New("Frame", {
		Name = "InlineDivider",
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.fromOffset(12, 0),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		ZIndex = 4,
		Parent = inlineClip,
	})

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
	local searchable = opts.Searchable ~= false
	local maxVisible = math.max(1, tonumber(opts.MaxVisible) or 7)
	local mode = resolveDropdownMode(opts)
	self.Mode = mode

	local selectedSingle = nil
	local selectedMap = {} -- [item] = true (keyed by item reference for exact identity)
	local isOpen = false
	local searchQuery = ""
	local popupId = "Dropdown_" .. Util.RandomString(8)
	local optionRows = {} -- { { Item, Button, CheckIcon, TitleLabel, DescLabel } }
	local openGen = 0
	local inlineTween = nil
	local dividerTween = nil

	local function cancelInlineTween()
		if inlineTween then
			pcall(function()
				inlineTween:Cancel()
			end)
			inlineTween = nil
		end
		if dividerTween then
			pcall(function()
				dividerTween:Cancel()
			end)
			dividerTween = nil
		end
	end

	-- Right-side trigger pill
	local trigger = Create.New("TextButton", {
		Name = "Trigger",
		Size = UDim2.new(1, 0, 0, 32),
		Text = "",
		Corner = 8,
		Padding = { 0, 10, 0, 12 },
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
		Active = true,
		Visible = false,
		ZIndex = 110,
		Corner = 10,
		BackgroundTransparency = 0,
		Theme = {
			BackgroundColor3 = "Card",
		},
	})
	Create.GlassStroke(popup, 0.12)

	Create.New("TextButton", {
		Name = "InputSink",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Active = true,
		ZIndex = 110,
		Parent = popup,
	})

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

	local glassClip = Create.New("CanvasGroup", {
		Name = "GlassClip",
		Size = UDim2.fromScale(1, 1),
		Corner = 10,
		ClipsDescendants = true,
		BackgroundTransparency = 1,
		ZIndex = 110,
		Parent = popup,
	})

	local glassSheen = Create.New("Frame", {
		Name = "GlassSheen",
		Size = UDim2.fromScale(1, 1),
		Corner = 10,
		BackgroundTransparency = 0.72,
		Theme = { BackgroundColor3 = "Elevated" },
		ZIndex = 110,
		Parent = glassClip,
	})
	local sheenGrad = Instance.new("UIGradient")
	sheenGrad.Rotation = 125
	sheenGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.62),
		NumberSequenceKeypoint.new(0.45, 0.90),
		NumberSequenceKeypoint.new(1, 0.78),
	})
	sheenGrad.Parent = glassSheen

	local glowAsset = Assets.Get("Glow")
	if glowAsset and Assets.Available then
		Create.New("ImageLabel", {
			Name = "Glow",
			Size = UDim2.fromScale(0.85, 0.85),
			Position = UDim2.fromScale(-0.25, -0.25),
			Image = glowAsset,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 110,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = function(t)
					return math.min((t.GlowTransparency or 0.84) + 0.04, 0.93)
				end,
			},
			Parent = glassClip,
		})
	end

	local glassAsset = Assets.Get("Glass")
	if glassAsset and Assets.Available then
		Create.New("ImageLabel", {
			Name = "Glass",
			Size = UDim2.fromScale(1, 1),
			Image = glassAsset,
			ScaleType = Enum.ScaleType.Stretch,
			ImageTransparency = 0.80,
			Corner = 10,
			Theme = { ImageColor3 = "Text" },
			ZIndex = 110,
			Parent = glassClip,
		})
	end

	local noiseAsset = Assets.Get("Noise")
	if noiseAsset and Assets.Available then
		Create.New("ImageLabel", {
			Name = "Noise",
			Size = UDim2.fromScale(1, 1),
			Image = noiseAsset,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(128, 128),
			Corner = 10,
			ZIndex = 110,
			Theme = {
				ImageColor3 = "Stroke",
				ImageTransparency = "NoiseTransparency",
			},
			Parent = glassClip,
		})
	end

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
			Size = UDim2.fromOffset(14, 14),
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
			Size = UDim2.fromOffset(13, 13),
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
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Active = true,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		LayoutOrder = 2,
		ZIndex = 112,
		Theme = { ScrollBarImageColor3 = "Muted" },
		Parent = popupInner,
	})
	Create.Padding(scroll, { 3, 7, 3, 3 })
	local scrollLayout = Create.List(scroll, { Gap = 3 })

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
				local customCol, customToken = resolveCustomColor(selectedSingle.Color)
				if customCol then
					Theme.Unbind(summaryLabel, "TextColor3")
					summaryLabel.TextColor3 = customCol
				else
					Theme.Bind(summaryLabel, { TextColor3 = customToken or "Text" })
				end
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

	local function cancelEntryTweens(entry)
		if entry._bgTween then
			pcall(function()
				entry._bgTween:Cancel()
			end)
			entry._bgTween = nil
		end
		if entry._strTween then
			pcall(function()
				entry._strTween:Cancel()
			end)
			entry._strTween = nil
		end
		if entry._chkTween then
			pcall(function()
				entry._chkTween:Cancel()
			end)
			entry._chkTween = nil
		end
	end

	local function syncEntryVisual(entry, animated)
		local item = entry.Item
		local active = isItemSelected(item)
		local disabled = item.Disabled == true
		local targetBg = active and 0.82 or ((entry.Hovered and not disabled) and 0.42 or 1)
		local targetStroke = active and 0.52 or ((entry.Hovered and not disabled) and 0.86 or 1)
		local targetCheck = active and 0 or 1

		Theme.Bind(entry.Button, {
			BackgroundColor3 = active and "Accent" or "TileHover",
		})
		Theme.Bind(entry.Stroke, {
			Color = active and "Accent" or "Stroke",
		})

		local customCol, customToken = resolveCustomColor(item.Color)
		if customCol then
			Theme.Unbind(entry.TitleLabel, "TextColor3")
			Theme.Bind(entry.TitleLabel, {
				FontFace = active and "@SemiBold" or "@Medium",
			})
			entry.TitleLabel.TextColor3 = customCol
		else
			Theme.Bind(entry.TitleLabel, {
				TextColor3 = customToken or (active and "Text" or "SubText"),
				FontFace = active and "@SemiBold" or "@Medium",
			})
		end
		entry.TitleLabel.TextTransparency = disabled and 0.48 or 0

		if entry.IconInst and not item.IconColor then
			Icons.SetColor(entry.IconInst, active and "Accent" or "SubText")
		end

		cancelEntryTweens(entry)
		if animated and not Tween.Reduced and isOpen then
			entry.Button:SetAttribute("_BaliRestBg", targetBg)
			entry.Stroke:SetAttribute("_BaliRestStr", targetStroke)
			entry._bgTween = Tween.Play(entry.Button, { BackgroundTransparency = targetBg }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			entry._strTween = Tween.Play(entry.Stroke, { Transparency = targetStroke }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			if entry.CheckIcon then
				entry.CheckIcon.Visible = true
				entry.CheckIcon:SetAttribute("_BaliRestImg", targetCheck)
				entry._chkTween = Tween.Play(entry.CheckIcon, { ImageTransparency = targetCheck }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
		else
			entry.Button.BackgroundTransparency = targetBg
			entry.Button:SetAttribute("_BaliRestBg", targetBg)
			entry.Stroke.Transparency = targetStroke
			entry.Stroke:SetAttribute("_BaliRestStr", targetStroke)
			if entry.CheckIcon then
				entry.CheckIcon.Visible = true
				entry.CheckIcon.ImageTransparency = targetCheck
				entry.CheckIcon:SetAttribute("_BaliRestImg", targetCheck)
			end
		end
	end

	local function updateOptionVisuals(animated)
		local animateNow = (animated == true) and isOpen
		for _, entry in ipairs(optionRows) do
			syncEntryVisual(entry, animateNow)
		end
	end

	local function resizePopup(preserveFlip, animateInline)
		local searchH = searchable and 38 or 0
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

		local padV = 8
		local contentH = scrollLayout.AbsoluteContentSize.Y
		local estPerRow = hasDesc and 44 or 28
		local maxListH = maxVisible * estPerRow + math.max(0, maxVisible - 1) * 3 + padV
		local estAllH = visibleCount * estPerRow + math.max(0, visibleCount - 1) * 3 + padV
		local fullContentH = (contentH > 0) and (contentH + padV) or estAllH

		local listH
		if visibleCount == 0 then
			listH = 36
		elseif contentH > 0 then
			listH = math.min(contentH + padV, maxListH)
		else
			local shown = math.min(visibleCount, maxVisible)
			listH = shown * estPerRow + math.max(0, shown - 1) * 3 + padV
		end

		local needsScroll = (visibleCount > maxVisible) or (fullContentH > listH)
		scroll.ScrollingEnabled = needsScroll
		scroll.ScrollBarThickness = needsScroll and 3 or 0
		scroll.CanvasSize = UDim2.fromOffset(0, needsScroll and fullContentH or 0)

		if mode == "Inline" then
			local inlineTotalH = 16 + searchH + listH
			local inlineClipH = inlineTotalH + 1
			scroll.Size = UDim2.new(1, 0, 0, listH)
			popupInner.Position = UDim2.fromOffset(0, 1)
			popupInner.Size = UDim2.new(1, 0, 0, inlineTotalH)
			if isOpen and animateInline then
				cancelInlineTween()
				inlineTween = Tween.Play(inlineClip, { Size = UDim2.new(1, 0, 0, inlineClipH) }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			end
			return inlineClipH
		end

		local layerH = (ctx.PopupLayer and ctx.PopupLayer.AbsoluteSize.Y > 0) and ctx.PopupLayer.AbsoluteSize.Y or 680
		local anchorW = (trigger.AbsoluteSize.X > 0) and trigger.AbsoluteSize.X or 168
		local width = (anchorW >= 180) and anchorW or Util.Clamp(math.max(anchorW + 40, 200), 200, 252)
		local totalH = math.min(16 + searchH + listH, math.max(120, layerH - 16))
		listH = math.max(36, totalH - 16 - searchH)

		local prevBottom = popup.AbsolutePosition.Y + popup.AbsoluteSize.Y
		local anchorTop = trigger.AbsolutePosition.Y
		local wasFlipped = preserveFlip == true and isOpen and popup.Parent ~= nil and prevBottom <= anchorTop + 4

		needsScroll = (visibleCount > maxVisible) or (fullContentH > listH)
		scroll.ScrollingEnabled = needsScroll
		scroll.ScrollBarThickness = needsScroll and 3 or 0
		scroll.CanvasSize = UDim2.fromOffset(0, needsScroll and fullContentH or 0)
		scroll.Size = UDim2.new(1, 0, 0, listH)
		popupInner.Position = UDim2.fromOffset(0, 0)
		popupInner.Size = UDim2.fromScale(1, 1)
		popup.Size = UDim2.fromOffset(width, totalH)

		-- Keep bottom anchored if popup flipped above trigger and search shrank height
		if wasFlipped and popup.AbsolutePosition.Y > 0 then
			local newY = anchorTop - totalH - 6
			popup.Position = UDim2.fromOffset(popup.Position.X.Offset, math.max(8, newY))
		end

		return totalH
	end

	self.Maid:Give(scrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if isOpen then
			resizePopup(true, mode == "Inline")
		end
	end))

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
			if isOpen and ((mode == "Inline" and inlineClip.Parent) or popup.Parent) then
				resizePopup(preserveFlip, mode == "Inline")
			end
		end)
	end

	local function fireSelection(silent, animated)
		if animated == nil then
			animated = true
		end
		local value = getSelectedValues()
		self.Value = value
		updateSummary()
		updateOptionVisuals(animated)
		if not silent then
			if opts.Callback then
				Util.Spawn(opts.Callback, multi and cloneArray(value) or value)
			end
			self.Changed:Fire(multi and cloneArray(value) or value)
		end
	end

	local function onSelectItem(item)
		if isDisabledOrLocked(self) or item.Disabled then
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
			fireSelection(false, true)
		else
			if selectedSingle == item then
				if allowNull then
					selectedSingle = nil
					fireSelection(false, false)
				end
			else
				selectedSingle = item
				fireSelection(false, false)
			end
			self:Close()
		end
	end

	local function rebuildOptions()
		for _, entry in ipairs(optionRows) do
			cancelEntryTweens(entry)
			entry.Button:Destroy()
		end
		table.clear(optionRows)

		for index, item in ipairs(items) do
			local hasDesc = (item.Desc ~= nil and item.Desc ~= "")
			local imgAsset = normalizeImageAsset(item.Image)
			local hasAccessory = (item.Badge ~= nil and item.Badge ~= "") or (item.RightText ~= nil and item.RightText ~= "")
			local btn = Create.New("TextButton", {
				Name = "Opt_" .. index,
				Size = UDim2.new(1, 0, 0, hasDesc and 44 or 28),
				AutomaticSize = hasDesc and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
				LayoutOrder = index,
				AutoButtonColor = false,
				Active = not item.Disabled,
				ZIndex = 113,
				Corner = 7,
				Padding = hasDesc and { 6, 10, 6, 10 } or { 0, 10, 0, 10 },
				BackgroundTransparency = 1,
				Theme = { BackgroundColor3 = "TileHover" },
				Parent = scroll,
			})
			local optStroke = Create.Stroke(btn, {
				Transparency = 1,
				Theme = { Color = "Accent" },
			})

			local leftReserve = imgAsset and 26 or (item.Icon and 22 or 0)
			local rightReserve = hasAccessory and 82 or 20
			local iconInst = nil
			local thumbInst = nil

			if imgAsset then
				thumbInst = Create.New("ImageLabel", {
					Name = "Thumb",
					Size = UDim2.fromOffset(18, 18),
					Position = UDim2.new(0, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundTransparency = 1,
					Image = imgAsset,
					ScaleType = Enum.ScaleType.Crop,
					Corner = 5,
					ZIndex = 114,
					Parent = btn,
				})
				Create.Stroke(thumbInst, {
					Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
					Thickness = 1,
				})
			elseif item.Icon then
				local iconCol, iconToken = resolveCustomColor(item.IconColor)
				iconInst = Icons.Create(item.Icon, {
					Size = UDim2.fromOffset(15, 15),
					Position = UDim2.new(0, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					Color = iconCol or iconToken or "SubText",
					Transparency = item.Disabled and 0.45 or 0,
					ZIndex = 114,
					Parent = btn,
				})
			end

			if item.Badge ~= nil and item.Badge ~= "" then
				local badgeCol, badgeToken = resolveCustomColor(item.BadgeColor)
				local badgeFrame = Create.New("Frame", {
					Name = "OptionBadge",
					Size = UDim2.fromOffset(0, 18),
					AutomaticSize = Enum.AutomaticSize.X,
					Position = UDim2.new(1, -20, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Corner = 99,
					Padding = { 0, 7, 0, 7 },
					BackgroundTransparency = 0.82,
					BackgroundColor3 = badgeCol or Color3.new(1, 1, 1),
					Theme = (not badgeCol) and { BackgroundColor3 = badgeToken or "Accent" } or nil,
					ZIndex = 114,
					Parent = btn,
				})
				Create.Stroke(badgeFrame, {
					Color = badgeCol,
					Theme = (not badgeCol) and { Color = badgeToken or "Accent" } or nil,
					Transparency = 0.55,
					Thickness = 1,
				})
				local badgeTxt = Create.Text({
					Size = UDim2.fromOffset(0, 18),
					AutomaticSize = Enum.AutomaticSize.X,
					Text = tostring(item.Badge),
					Font = "SemiBold",
					TextSize = 10,
					Color = badgeToken or "Accent",
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = 115,
					Parent = badgeFrame,
				})
				if badgeCol then
					Theme.Unbind(badgeTxt, "TextColor3")
					badgeTxt.TextColor3 = badgeCol
				end
			elseif item.RightText ~= nil and item.RightText ~= "" then
				local hintCol, hintToken = resolveCustomColor(item.BadgeColor)
				local hintTxt = Create.Text({
					Name = "RightText",
					Size = UDim2.fromOffset(0, 16),
					AutomaticSize = Enum.AutomaticSize.X,
					Position = UDim2.new(1, -20, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Text = tostring(item.RightText),
					Font = "Medium",
					TextSize = 11,
					Color = hintToken or "Muted",
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = 114,
					Parent = btn,
				})
				if hintCol then
					Theme.Unbind(hintTxt, "TextColor3")
					hintTxt.TextColor3 = hintCol
				end
			end

			local titleLbl
			local descLbl
			if hasDesc then
				local textCol = Create.New("Frame", {
					Size = UDim2.new(1, -(leftReserve + rightReserve), 0, 0),
					Position = UDim2.fromOffset(leftReserve, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					ZIndex = 114,
					Parent = btn,
				})
				Create.List(textCol, { Gap = 2 })

				titleLbl = Create.Text({
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
			else
				titleLbl = Create.Text({
					Size = UDim2.new(1, -(leftReserve + rightReserve), 1, 0),
					Position = UDim2.fromOffset(leftReserve, 0),
					AutomaticSize = Enum.AutomaticSize.None,
					Text = item.Title,
					TextSize = 12,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextYAlignment = Enum.TextYAlignment.Center,
					Font = "Medium",
					Color = "SubText",
					ZIndex = 114,
					Parent = btn,
				})
			end

			local checkIcon = Icons.Create("check", {
				Size = UDim2.fromOffset(14, 14),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Color = "Accent",
				ZIndex = 114,
				Parent = btn,
			})
			if checkIcon then
				checkIcon.Visible = true
				checkIcon.ImageTransparency = 1
			end

			local entry = {
				Item = item,
				Button = btn,
				Stroke = optStroke,
				TitleLabel = titleLbl,
				DescLabel = descLbl,
				CheckIcon = checkIcon,
				IconInst = iconInst,
				ThumbInst = thumbInst,
				Hovered = false,
			}

			btn.MouseEnter:Connect(function()
				if item.Disabled or Transition.IsOverlayBlocking(btn) then
					return
				end
				entry.Hovered = true
				syncEntryVisual(entry, true)
			end)
			btn.MouseLeave:Connect(function()
				if item.Disabled then
					return
				end
				entry.Hovered = false
				syncEntryVisual(entry, true)
			end)
			btn.Activated:Connect(function()
				if item.Disabled or Transition.IsOverlayBlocking(btn) then
					return
				end
				Transition.Ripple(btn, nil, "Accent")
				onSelectItem(item)
			end)

			table.insert(optionRows, entry)
		end

		updateOptionVisuals(false)
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
		for _, entry in ipairs(optionRows) do
			entry.Hovered = false
			syncEntryVisual(entry, false)
		end
		if scroll then
			Transition.RestoreCascade(scroll)
		end
		if chevron then
			Tween.Play(chevron, { Rotation = chevronBaseRot }, Tween.Fast)
		end
		if fallbackOutsideConn then
			fallbackOutsideConn:Disconnect()
			fallbackOutsideConn = nil
		end
		if mode == "Inline" then
			cancelInlineTween()
			local currentH = inlineClip.AbsoluteSize.Y
			if currentH <= 0 then
				currentH = inlineClip.Size.Y.Offset
			end
			if currentH > 0 then
				inlineClip.Size = UDim2.new(1, 0, 0, currentH)
			end
			dividerTween = Tween.Play(inlineDivider, { BackgroundTransparency = 1 }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			inlineTween = Tween.Play(inlineClip, { Size = UDim2.new(1, 0, 0, 0) }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween.Then(inlineTween, function()
				if openGen == myGen and not isOpen then
					inlineClip.Visible = false
				end
			end)
			return
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

		for _, entry in ipairs(optionRows) do
			entry.Hovered = false
		end
		if searchBox then
			searchBox.Text = ""
			searchQuery = ""
			applyFilter()
		end
		updateOptionVisuals(false)

		if chevron then
			Tween.Play(chevron, { Rotation = chevronBaseRot + 180 }, Tween.Fast)
		end

		if mode == "Inline" then
			cancelInlineTween()
			popup.Visible = false
			popupInner.Parent = inlineClip
			local targetClipH = resizePopup(false, false)
			local tNow = Theme.Current
			Theme.Bind(inlineDivider, {
				BackgroundColor3 = "Divider",
				BackgroundTransparency = "DividerTransparency",
			})
			inlineDivider.BackgroundTransparency = tNow and tNow.DividerTransparency or 0.85
			inlineClip.Size = UDim2.new(1, 0, 0, 0)
			inlineClip.Visible = true
			inlineTween = Tween.Play(inlineClip, { Size = UDim2.new(1, 0, 0, targetClipH) }, Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			return
		end

		inlineClip.Visible = false
		inlineClip.Size = UDim2.new(1, 0, 0, 0)
		popupInner.Parent = popup
		resizePopup()
		popup.Visible = true

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
		local wasPopup = (mode == "Popup")
		handleClosedState()
		if wasPopup and ctx.ClosePopup then
			ctx.ClosePopup(popupId)
		end
	end

	function self:SetMode(newMode)
		local resolved
		if newMode == true then
			resolved = "Inline"
		elseif newMode == false then
			resolved = "Popup"
		elseif type(newMode) == "string" then
			local lower = string.lower(newMode)
			if lower == "inline" or lower == "expand" or lower == "push" then
				resolved = "Inline"
			else
				resolved = "Popup"
			end
		else
			resolved = "Popup"
		end
		if resolved == mode then
			return
		end
		if isOpen then
			self:Close()
		end
		cancelInlineTween()
		mode = resolved
		self.Mode = mode
		if mode == "Inline" then
			popup.Visible = false
			inlineClip.Size = UDim2.new(1, 0, 0, 0)
			inlineClip.Visible = false
			popupInner.Parent = inlineClip
		else
			inlineClip.Visible = false
			inlineClip.Size = UDim2.new(1, 0, 0, 0)
			popupInner.Parent = popup
		end
	end

	function self:GetMode()
		return mode
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
		if isDisabledOrLocked(self) or Transition.IsOverlayBlocking(trigger) then
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
		cancelInlineTween()
		if fallbackOutsideConn then
			fallbackOutsideConn:Disconnect()
			fallbackOutsideConn = nil
		end
		popup:Destroy()
	end)

	if mode == "Inline" then
		popupInner.Parent = inlineClip
		popupInner.Position = UDim2.fromOffset(0, 1)
	end

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
