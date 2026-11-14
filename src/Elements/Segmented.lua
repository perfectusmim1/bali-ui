--[[
	Bali UI · Elements/Segmented
	Apple-style sliding pill segmented control with optional icons and smooth indicator glide.
]]

local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Base = require("Elements/Base")

local Segmented = {}

local function normalizeItems(values)
	local items = {}
	if type(values) ~= "table" then
		return items
	end
	for index, raw in ipairs(values) do
		if type(raw) == "table" then
			local title = tostring(raw.Title or raw.Name or raw.Text or raw[1] or ("Option " .. index))
			local val = raw.Value ~= nil and raw.Value or title
			table.insert(items, {
				Title = title,
				Icon = raw.Icon,
				Value = val,
			})
		else
			local str = tostring(raw)
			table.insert(items, {
				Title = str,
				Icon = nil,
				Value = raw,
			})
		end
	end
	return items
end

function Segmented.new(parent, opts, ctx)
	opts = Util.Options(opts, { Values = { "One", "Two" } }, "Title")
	local element = Base.New("Segmented", parent, opts, ctx)

	local useAccent = (opts.Accent == true)
	local titleText = tostring(opts.Title or "")
	local descText = tostring(opts.Description or opts.Desc or "")
	local hasHeader = (titleText ~= "" or descText ~= "")

	local container
	local card = nil
	local titleLabel = nil
	local descLabel = nil
	local body

	if hasHeader then
		card = Base.Card(parent, { Padding = 0 })
		container = card.Frame
		body = Create.New("Frame", {
			Name = "Body",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Padding = { 10, 12, 12, 12 },
			ZIndex = 2,
			Parent = card.Frame,
		})
		Create.List(body, {
			Direction = Enum.FillDirection.Vertical,
			Gap = 8,
		})

		local headerParent = body
		local textLayoutOrder = 1
		local hasHeaderIcon = type(opts.Icon) == "string" and opts.Icon ~= "" and titleText ~= ""
		if hasHeaderIcon then
			local headerRow = Create.New("Frame", {
				Name = "HeaderRow",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 1,
				Parent = body,
			})
			Create.List(headerRow, {
				Direction = Enum.FillDirection.Horizontal,
				Gap = 10,
				VAlign = Enum.VerticalAlignment.Center,
			})
			Icons.Create(opts.Icon, {
				Name = "Icon",
				Size = UDim2.fromOffset(18, 18),
				Color = "SubText",
				LayoutOrder = 1,
				Parent = headerRow,
			})
			headerParent = headerRow
			textLayoutOrder = 2
		end

		local textCol = Create.New("Frame", {
			Name = "TextColumn",
			Size = hasHeaderIcon and UDim2.new(1, -28, 0, 0) or UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = textLayoutOrder,
			Parent = headerParent,
		})
		Create.List(textCol, {
			Direction = Enum.FillDirection.Vertical,
			Gap = 2,
		})

		titleLabel = Create.Text({
			Name = "Title",
			Text = titleText,
			Font = "Medium",
			TextSize = 13,
			Color = "Text",
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Visible = titleText ~= "",
			Parent = textCol,
		})

		descLabel = Create.Text({
			Name = "Description",
			Text = descText,
			Font = "Regular",
			TextSize = 12,
			Color = "SubText",
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Visible = descText ~= "",
			Parent = textCol,
		})
	else
		container = Create.New("Frame", {
			Name = "Segmented",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = parent,
		})
		body = container
	end

	local barTrack = Create.New("Frame", {
		Name = "Bar",
		Size = UDim2.new(1, 0, 0, 34),
		Theme = { BackgroundColor3 = "Field" },
		Corner = 9,
		Padding = 3,
		Stroke = {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
			Thickness = 1,
		},
		LayoutOrder = 2,
		Parent = body,
	})

	local inner = Create.New("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = barTrack,
	})

	local indicator = Create.New("Frame", {
		Name = "Indicator",
		Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.fromScale(0, 0),
		Corner = 6,
		ZIndex = 2,
		Visible = false,
		Parent = inner,
	})

	local indicatorGrad = nil
	if useAccent then
		indicator.BackgroundColor3 = Color3.new(1, 1, 1)
		indicatorGrad = Instance.new("UIGradient")
		indicatorGrad.Color = Theme.AccentSequence()
		indicatorGrad.Rotation = 15
		indicatorGrad.Parent = indicator
		Create.Stroke(indicator, {
			Theme = { Color = "Accent" },
			Transparency = 0.45,
			Thickness = 1,
		})
		element.Maid:Give(Theme.Changed:Connect(function(t)
			if not element._destroyed and indicatorGrad then
				indicatorGrad.Color = Theme.AccentSequence(t)
			end
		end))
	else
		Theme.Bind(indicator, { BackgroundColor3 = "TileHover" })
		Create.Stroke(indicator, {
			Theme = { Color = "Stroke" },
			Transparency = 0.82,
			Thickness = 1,
		})
	end

	local buttonsRow = Create.New("Frame", {
		Name = "Buttons",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = inner,
	})

	local GAP = 2
	Create.List(buttonsRow, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = GAP,
	})

	local items = {}
	local segments = {}
	local activeIndex = nil
	local currentValue = nil

	local function resolveIndex(valOrIdx)
		if #items == 0 then
			return nil
		end
		for i, item in ipairs(items) do
			if item.Value == valOrIdx or item.Title == valOrIdx then
				return i
			end
		end
		if type(valOrIdx) == "number" and items[valOrIdx] then
			return valOrIdx
		end
		return nil
	end

	local function updateIndicator(animate)
		local n = #items
		if n == 0 or not activeIndex or not items[activeIndex] then
			indicator.Visible = false
			return
		end
		indicator.Visible = true
		local idx = activeIndex
		local targetSize = UDim2.new(1 / n, -((n - 1) * GAP) / n, 1, 0)
		local targetPos = UDim2.new((idx - 1) / n, ((idx - 1) * GAP) / n, 0, 0)

		if animate then
			Tween.Play(indicator, {
				Size = targetSize,
				Position = targetPos,
			}, Tween.Fast + 0.04, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		else
			indicator.Size = targetSize
			indicator.Position = targetPos
		end

		for i, seg in ipairs(segments) do
			local isActive = (i == activeIndex)
			local textColorKey = isActive and (useAccent and "AccentText" or "Text") or "SubText"
			Theme.Bind(seg.Label, {
				TextColor3 = textColorKey,
				FontFace = isActive and "@SemiBold" or "@Medium",
			})
			if seg.Icon then
				Icons.SetColor(seg.Icon, textColorKey)
			end
		end
	end

	local function rebuild(rawValues, targetDefault)
		for _, seg in ipairs(segments) do
			if seg.Button and seg.Button.Parent then
				seg.Button:Destroy()
			end
		end
		table.clear(segments)
		items = normalizeItems(rawValues)

		local n = #items
		if n == 0 then
			activeIndex = nil
			currentValue = nil
			element.Value = nil
			indicator.Visible = false
			return
		end

		local widthOffset = -((n - 1) * GAP) / n
		for i, item in ipairs(items) do
			local btn = Create.New("TextButton", {
				Name = "Seg_" .. i,
				Size = UDim2.new(1 / n, widthOffset, 1, 0),
				BackgroundTransparency = 1,
				Corner = 6,
				Padding = { 0, 6, 0, 6 },
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = i,
				ZIndex = 4,
				Parent = buttonsRow,
			})

			local content = Create.New("Frame", {
				Name = "Content",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Parent = btn,
			})

			Create.List(content, {
				Direction = Enum.FillDirection.Horizontal,
				HAlign = Enum.HorizontalAlignment.Center,
				VAlign = Enum.VerticalAlignment.Center,
				Gap = 5,
			})

			local iconObj = nil
			if item.Icon and item.Icon ~= "" and item.Icon ~= false then
				iconObj = Icons.Create(item.Icon, {
					Size = UDim2.fromOffset(14, 14),
					Color = "SubText",
					LayoutOrder = 1,
					ZIndex = 5,
					Parent = content,
				})
			end

			local lbl = Create.Text({
				Name = "Label",
				Text = item.Title,
				Font = "Medium",
				TextSize = 12,
				Color = "SubText",
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
				ZIndex = 5,
				Parent = content,
			})

			local sizeLimit = Instance.new("UISizeConstraint")
			sizeLimit.MaxSize = Vector2.new(9999, 28)
			sizeLimit.Parent = lbl

			btn.MouseEnter:Connect(function()
				if element.Disabled or element.Locked or activeIndex == i or Util.IsTouchDevice() then
					return
				end
				Theme.Bind(lbl, { TextColor3 = "Text" })
			end)

			btn.MouseLeave:Connect(function()
				if activeIndex ~= i then
					Theme.Bind(lbl, { TextColor3 = "SubText" })
				end
			end)

			btn.Activated:Connect(function(inputObj)
				if element.Disabled or element.Locked then
					return
				end
				Transition.Ripple(btn, inputObj, useAccent and "AccentText" or "Accent")
				element:Set(item.Value, false)
			end)

			segments[i] = {
				Button = btn,
				Label = lbl,
				Icon = iconObj,
			}
		end

		local initialIdx = resolveIndex(targetDefault) or 1
		activeIndex = initialIdx
		currentValue = items[initialIdx].Value
		element.Value = currentValue
		updateIndicator(false)
	end

	rebuild(opts.Values, opts.Default)

	function element:Set(valOrIdx, silent)
		local nextIdx = resolveIndex(valOrIdx)
		if not nextIdx then
			return
		end
		local nextVal = items[nextIdx].Value
		local changed = (nextIdx ~= activeIndex or nextVal ~= currentValue)
		activeIndex = nextIdx
		currentValue = nextVal
		self.Value = currentValue
		updateIndicator(true)
		if changed and not silent then
			self.Changed:Fire(currentValue, activeIndex)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, currentValue, activeIndex)
			end
		end
	end

	function element:Get()
		return currentValue
	end

	function element:SetValues(newValues, defaultOverride)
		local target = defaultOverride ~= nil and defaultOverride or currentValue
		rebuild(newValues, target)
	end

	element._onDisabled = function(disabled)
		for _, seg in ipairs(segments) do
			seg.Button.Active = not disabled
			seg.Label.TextTransparency = disabled and 0.48 or 0
			if seg.Icon then
				Icons.SetTransparency(seg.Icon, disabled and 0.48 or 0)
			end
		end
	end

	if card then
		card.TitleLabel = titleLabel
		card.DescLabel = descLabel
		function card:SetTitle(s)
			local txt = tostring(s or "")
			titleLabel.Text = txt
			titleLabel.Visible = (txt ~= "")
		end
		function card:SetDesc(s)
			local txt = tostring(s or "")
			descLabel.Text = txt
			descLabel.Visible = (txt ~= "")
		end
		element:BindUI(card)
	else
		element:BindUI({
			Frame = container,
			Flash = function()
				Base.FlashFrame(barTrack, nil, "Field")
			end,
		})
	end

	return element
end

return Segmented
