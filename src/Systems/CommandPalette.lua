--[[
	Bali UI · Systems/CommandPalette
	Apple Spotlight / Raycast style glass modal with live fuzzy search across tabs,
	elements, and themes, full keyboard navigation, and click/touch execution.
]]

local Services = require("Core/Services")
local Maid = require("Core/Maid")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Util = require("Core/Util")

local CommandPalette = {}

local MAX_RESULTS = 40
local ROW_HEIGHT = 44
local ROW_GAP = 4
local MAX_LIST_HEIGHT = 290

local rootMaid = Maid.new()
local openMaid = Maid.new()
local layer = nil
local windowRef = nil

local backdrop = nil
local shadow = nil
local modal = nil
local searchBox = nil
local resultsScroll = nil
local emptyLabel = nil
local footerHint = nil

local isOpen = false
local results = {} -- current filtered items
local rowViews = {} -- UI rows matching `results`
local selectedIndex = 0
local queryToken = 0

local TYPE_ICONS = {
	Tab = "layers",
	Theme = "palette",
	Button = "pointer",
	ButtonGroup = "pointer",
	Toggle = "toggle",
	Checkbox = "list-checks",
	Slider = "sliders",
	RangeSlider = "sliders",
	Stepper = "sliders",
	Input = "type",
	Dropdown = "list",
	Segmented = "sliders",
	Keybind = "key",
	ColorPicker = "droplet",
	Accordion = "folder",
	StatCard = "chart-line",
	Chart = "chart-line",
	ProgressBar = "gauge",
	Table = "grid",
	CardGrid = "grid",
}

local function getViewportSize()
	if layer and layer.AbsoluteSize.X > 0 and layer.AbsoluteSize.Y > 0 then
		return layer.AbsoluteSize
	end
	local cam = Services.Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local function fuzzyScore(query, text)
	if not query or query == "" then
		return 1
	end
	if not text or text == "" then
		return nil
	end

	local q = string.lower(query)
	local t = string.lower(tostring(text))

	if t == q then
		return 1000
	end
	if string.sub(t, 1, #q) == q then
		return 850 - #t
	end

	local foundPos = string.find(t, q, 1, true)
	if foundPos then
		return 650 - foundPos * 2
	end

	-- Subsequence fuzzy match
	local qi = 1
	local qLen = #q
	local score = 200
	local lastMatch = 0
	for ti = 1, #t do
		if string.byte(t, ti) == string.byte(q, qi) then
			if lastMatch > 0 then
				if ti == lastMatch + 1 then
					score += 18
				else
					score -= math.min(ti - lastMatch, 12)
				end
			end
			if ti == 1 or string.sub(t, ti - 1, ti - 1) == " " then
				score += 14
			end
			lastMatch = ti
			qi += 1
			if qi > qLen then
				return math.max(score, 10)
			end
		end
	end

	return nil
end

local function syncShadow()
	if not shadow or not modal then
		return
	end
	if not modal.Visible then
		shadow.Visible = false
		return
	end
	local shadowInfo = Assets.Shadow()
	local inset = shadowInfo.Inset or 24
	local absPos = modal.AbsolutePosition
	local absSize = modal.AbsoluteSize
	local parentPos = (backdrop and backdrop:IsA("GuiBase2d")) and backdrop.AbsolutePosition or Vector2.zero

	shadow.Visible = true
	shadow.Position = UDim2.fromOffset(absPos.X - parentPos.X - inset, absPos.Y - parentPos.Y - inset)
	shadow.Size = UDim2.fromOffset(absSize.X + inset * 2, absSize.Y + inset * 2)
end

local function scrollElementIntoView(tab, element)
	if not tab or not element or not element.Frame then
		return
	end
	task.defer(function()
		pcall(function()
			local page = tab.Page or tab._page or tab.Container
			if not page or not page:IsA("ScrollingFrame") then
				return
			end
			local frame = element.Frame
			if not frame or not frame.Parent then
				return
			end
			local relY = frame.AbsolutePosition.Y - page.AbsolutePosition.Y + page.CanvasPosition.Y
			local targetY = math.max(0, relY - page.AbsoluteSize.Y * 0.35)
			Tween.Play(page, { CanvasPosition = Vector2.new(page.CanvasPosition.X, targetY) }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end)
	end)
end

local function executeItem(item)
	if not item then
		return
	end

	CommandPalette.Close()

	if item.Kind == "Theme" then
		Theme.Set(item.ThemeName, true)
		return
	end

	if item.Kind == "Tab" then
		if windowRef and type(windowRef.SelectTab) == "function" and item.Tab then
			pcall(windowRef.SelectTab, windowRef, item.Tab)
		elseif item.Tab and type(item.Tab.Select) == "function" then
			pcall(item.Tab.Select, item.Tab)
		end
		return
	end

	if item.Kind == "Element" then
		if windowRef and type(windowRef.SelectTab) == "function" and item.Tab then
			pcall(windowRef.SelectTab, windowRef, item.Tab)
		elseif item.Tab and type(item.Tab.Select) == "function" then
			pcall(item.Tab.Select, item.Tab)
		end
		if item.SubTab and type(item.SubTab.Select) == "function" then
			pcall(item.SubTab.Select, item.SubTab)
		end

		local el = item.Element
		if el then
			scrollElementIntoView(item.Tab, el)
			if item.ElemType == "Button" and type(el.Fire) == "function" then
				Util.Spawn(el.Fire, el)
			elseif (item.ElemType == "Toggle" or item.ElemType == "Checkbox") then
				if type(el.Toggle) == "function" then
					Util.Spawn(el.Toggle, el)
				elseif type(el.Set) == "function" and type(el.Get) == "function" then
					local ok, cur = pcall(el.Get, el)
					if ok then
						Util.Spawn(el.Set, el, not cur)
					end
				end
			end
			if type(el.Flash) == "function" then
				pcall(el.Flash, el)
			end
		end
	end
end

local function collectMatches(query)
	local candidates = {}

	-- Tabs
	if windowRef and type(windowRef.Tabs) == "table" then
		for _, tab in ipairs(windowRef.Tabs) do
			local title = tab.Title or "Tab"
			local score = fuzzyScore(query, title)
			if tab.Category and tab.Category ~= "" then
				local catScore = fuzzyScore(query, tab.Category .. " " .. title)
				if catScore and (not score or catScore > score) then
					score = catScore - 20
				end
			end
			if score then
				table.insert(candidates, {
					Score = score + (query == "" and 20 or 15),
					Kind = "Tab",
					Title = title,
					Subtitle = tab.Category and (tostring(tab.Category) .. "  •  Tab") or "Navigation Tab",
					Badge = "Jump",
					Icon = tab.Icon or "layers",
					Tab = tab,
				})
			end
		end
	end

	-- Registered Elements
	if windowRef and type(windowRef._elements) == "table" then
		for _, entry in ipairs(windowRef._elements) do
			if type(entry) == "table" and entry.Title and entry.Title ~= "" then
				local tabTitle = entry.Tab and entry.Tab.Title or ""
				local secTitle = entry.Section and entry.Section.Title or ""
				local subTitle = entry.SubTab and entry.SubTab.Title or ""
				local breadcrumb = ""
				if tabTitle ~= "" and secTitle ~= "" then
					breadcrumb = tabTitle .. (subTitle ~= "" and (" › " .. subTitle) or "") .. " › " .. secTitle
				elseif tabTitle ~= "" then
					breadcrumb = tabTitle
				elseif secTitle ~= "" then
					breadcrumb = secTitle
				end

				local best = fuzzyScore(query, entry.Title)
				if entry.Desc and entry.Desc ~= "" then
					local dScore = fuzzyScore(query, entry.Desc)
					if dScore and (not best or dScore - 30 > best) then
						best = dScore - 30
					end
				end
				if breadcrumb ~= "" then
					local bScore = fuzzyScore(query, breadcrumb .. " " .. entry.Title)
					if bScore and (not best or bScore - 40 > best) then
						best = bScore - 40
					end
				end

				if best then
					local elemType = tostring(entry.Type or "Control")
					local badge = elemType
					if elemType == "Button" then
						badge = "Run"
					elseif (elemType == "Toggle" or elemType == "Checkbox") and entry.Element and type(entry.Element.Get) == "function" then
						local ok, val = pcall(entry.Element.Get, entry.Element)
						if ok then
							badge = val and "ON" or "OFF"
						end
					end

					table.insert(candidates, {
						Score = best,
						Kind = "Element",
						ElemType = elemType,
						Title = tostring(entry.Title),
						Subtitle = breadcrumb ~= "" and breadcrumb or elemType,
						Badge = badge,
						Icon = TYPE_ICONS[elemType] or "chevron-right",
						Tab = entry.Tab,
						SubTab = entry.SubTab,
						Element = entry.Element,
					})
				end
			end
		end
	end

	-- Themes
	for _, themeName in ipairs(Theme.Order) do
		local score = fuzzyScore(query, themeName)
		local prefixed = fuzzyScore(query, "Theme " .. themeName)
		if prefixed and (not score or prefixed - 15 > score) then
			score = prefixed - 15
		end
		if score then
			table.insert(candidates, {
				Score = score - (query == "" and 10 or 0),
				Kind = "Theme",
				ThemeName = themeName,
				Title = "Theme: " .. themeName,
				Subtitle = Theme.Name == themeName and "Active Theme Preset" or "Switch Theme Preset",
				Badge = Theme.Name == themeName and "Active" or "Apply",
				Icon = "palette",
			})
		end
	end

	table.sort(candidates, function(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.Title < b.Title
	end)

	if #candidates > MAX_RESULTS then
		local trimmed = {}
		for idx = 1, MAX_RESULTS do
			trimmed[idx] = candidates[idx]
		end
		return trimmed
	end
	return candidates
end

local function updateSelectionVisuals(ensureVisible)
	for idx, view in ipairs(rowViews) do
		local selected = idx == selectedIndex
		view.Indicator.Visible = selected
		if selected then
			Theme.Bind(view.Button, { BackgroundColor3 = "TileHover" })
			view.Button.BackgroundTransparency = 0.08
			Theme.Bind(view.Title, { TextColor3 = "Text" })
		else
			Theme.Bind(view.Button, { BackgroundColor3 = "Tile" })
			view.Button.BackgroundTransparency = 0.65
			Theme.Bind(view.Title, { TextColor3 = "Text" })
		end
	end

	if ensureVisible and selectedIndex >= 1 and selectedIndex <= #results and resultsScroll then
		local step = ROW_HEIGHT + ROW_GAP
		local itemTop = (selectedIndex - 1) * step
		local itemBottom = itemTop + ROW_HEIGHT
		local viewHeight = resultsScroll.AbsoluteSize.Y
		local canvasY = resultsScroll.CanvasPosition.Y
		if itemTop < canvasY then
			resultsScroll.CanvasPosition = Vector2.new(0, itemTop)
		elseif itemBottom > canvasY + viewHeight and viewHeight > 0 then
			resultsScroll.CanvasPosition = Vector2.new(0, itemBottom - viewHeight)
		end
	end
end

local function rebuildResults(query)
	if not resultsScroll then
		return
	end
	queryToken += 1

	for _, view in ipairs(rowViews) do
		if view.Button and view.Button.Parent then
			view.Button:Destroy()
		end
	end
	table.clear(rowViews)

	results = collectMatches(query)
	local count = #results
	emptyLabel.Visible = count == 0

	local vp = getViewportSize()
	local maxH = math.min(MAX_LIST_HEIGHT, math.max(120, vp.Y * 0.44))
	local contentH = count > 0 and (count * ROW_HEIGHT + (count - 1) * ROW_GAP + 12) or 84
	resultsScroll.Size = UDim2.new(1, 0, 0, math.min(maxH, contentH))
	resultsScroll.CanvasPosition = Vector2.zero

	for idx, item in ipairs(results) do
		local row = Create.New("TextButton", {
			Name = "Result_" .. tostring(idx),
			Parent = resultsScroll,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Corner = 9,
			Padding = { 6, 10, 6, 10 },
			Text = "",
			BackgroundTransparency = 0.65,
			Theme = { BackgroundColor3 = "Tile" },
			LayoutOrder = idx,
			ZIndex = 312,
		})

		local indicator = Create.New("Frame", {
			Name = "ActiveBar",
			Parent = row,
			Visible = false,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(3, 22),
			Corner = 2,
			Theme = { BackgroundColor3 = "Accent" },
			ZIndex = 314,
		})

		local iconBox = Create.New("Frame", {
			Name = "IconBox",
			Parent = row,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(26, 26),
			Corner = 7,
			BackgroundTransparency = 0.25,
			Theme = { BackgroundColor3 = "Field" },
			ZIndex = 313,
		})
		Icons.Create(item.Icon, {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Color = item.Kind == "Theme" and "Accent" or "SubText",
			ZIndex = 314,
			Parent = iconBox,
		})

		local textBox = Create.New("Frame", {
			Name = "TextGroup",
			Parent = row,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 44, 0.5, 0),
			Size = UDim2.new(1, -112, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = 313,
		})

		local titleLabel = Create.Text({
			Name = "Title",
			Parent = textBox,
			Position = UDim2.fromOffset(0, 1),
			Size = UDim2.new(1, 0, 0, 16),
			Text = item.Title,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = "Medium",
			TextSize = 13,
			Color = "Text",
			ZIndex = 314,
		})

		Create.Text({
			Name = "Subtitle",
			Parent = textBox,
			Position = UDim2.fromOffset(0, 17),
			Size = UDim2.new(1, 0, 0, 14),
			Text = item.Subtitle,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = "Regular",
			TextSize = 11,
			Color = "SubText",
			ZIndex = 314,
		})

		local badge = Create.New("Frame", {
			Name = "Badge",
			Parent = row,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(0, 20),
			AutomaticSize = Enum.AutomaticSize.X,
			Corner = 6,
			Padding = { 0, 8, 0, 8 },
			BackgroundTransparency = 0.25,
			Theme = { BackgroundColor3 = "Field" },
			ZIndex = 313,
		})
		Create.GlassStroke(badge, 0.02)
		Create.Text({
			Name = "Label",
			Parent = badge,
			Size = UDim2.fromOffset(0, 20),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = item.Badge,
			Font = "SemiBold",
			TextSize = 10,
			Color = item.Badge == "ON" and "Accent" or "SubText",
			ZIndex = 314,
		})

		row.MouseEnter:Connect(function()
			if Util.IsTouchDevice() then
				return
			end
			selectedIndex = idx
			updateSelectionVisuals(false)
		end)

		row.Activated:Connect(function(input)
			Transition.Ripple(row, input)
			executeItem(item)
		end)

		rowViews[idx] = {
			Button = row,
			Indicator = indicator,
			Title = titleLabel,
		}
	end

	selectedIndex = count > 0 and 1 or 0
	updateSelectionVisuals(false)
	syncShadow()
end

local function updateModalWidth()
	if not modal then
		return
	end
	local vp = getViewportSize()
	local wrapper = windowRef and windowRef.MainWrapper
	if wrapper and wrapper.Parent and (not windowRef.IsVisible or windowRef:IsVisible()) and wrapper.AbsoluteSize.X > 0 and wrapper.AbsoluteSize.Y > 0 then
		local wPos = wrapper.AbsolutePosition
		local wSize = wrapper.AbsoluteSize
		local width = math.max(260, math.min(540, math.floor(wSize.X * 0.88), vp.X - 32))
		local modalH = modal.AbsoluteSize.Y > 0 and modal.AbsoluteSize.Y or 260
		local cx = Util.Clamp(wPos.X + wSize.X * 0.5, width * 0.5 + 12, math.max(width * 0.5 + 12, vp.X - width * 0.5 - 12))
		local topY = wPos.Y + Util.Clamp(math.floor(wSize.Y * 0.16), 24, 96)
		topY = Util.Clamp(topY, 12, math.max(12, vp.Y - modalH - 12))
		modal.Size = UDim2.fromOffset(width, 0)
		modal.Position = UDim2.fromOffset(math.floor(cx), math.floor(topY))
	else
		local width = math.max(260, math.min(540, vp.X - 32))
		local topRatio = vp.Y < 500 and 0.08 or 0.16
		modal.Size = UDim2.fromOffset(width, 0)
		modal.Position = UDim2.new(0.5, 0, topRatio, 0)
	end
	syncShadow()
end

local function ensureBuilt()
	if backdrop and backdrop.Parent then
		return true
	end
	if not layer or not layer.Parent then
		return false
	end

	backdrop = Create.New("TextButton", {
		Name = "BaliCommandPaletteBackdrop",
		Parent = layer,
		Visible = false,
		Active = true,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "Overlay" },
		ZIndex = 300,
	})

	local shadowInfo = Assets.Shadow()
	shadow = Create.New("ImageLabel", {
		Name = "Shadow",
		Parent = backdrop,
		Visible = false,
		Image = shadowInfo.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowInfo.Slice,
		Theme = { ImageColor3 = "Shadow", ImageTransparency = "ShadowTransparency" },
		ZIndex = 301,
	})

	modal = Create.New("Frame", {
		Name = "Modal",
		Parent = backdrop,
		Visible = false,
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.16, 0),
		Size = UDim2.fromOffset(520, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Corner = 14,
		ClipsDescendants = true,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.04)
			end,
		},
		ZIndex = 305,
	})
	Create.GlassStroke(modal, 0.06)

	Create.New("TextButton", {
		Name = "InputSink",
		Parent = modal,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Active = true,
		ZIndex = 305,
	})

	local bgClip = Create.New("CanvasGroup", {
		Name = "BackgroundClip",
		Parent = modal,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Corner = 14,
		ZIndex = 305,
	})

	local glowId = Assets.Get("Glow")
	if glowId then
		Create.New("ImageLabel", {
			Name = "Glow",
			Parent = bgClip,
			Size = UDim2.fromScale(0.75, 0.7),
			Position = UDim2.fromScale(-0.18, -0.25),
			Image = glowId,
			ScaleType = Enum.ScaleType.Stretch,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = function(t)
					return math.min(t.GlowTransparency + 0.05, 0.94)
				end,
			},
			ZIndex = 305,
		})
	end

	local noiseId = Assets.Get("Noise")
	if noiseId then
		Create.New("ImageLabel", {
			Name = "Noise",
			Parent = bgClip,
			Size = UDim2.fromScale(1, 1),
			Corner = 14,
			Image = noiseId,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(128, 128),
			Theme = {
				ImageColor3 = "Stroke",
				ImageTransparency = "NoiseTransparency",
			},
			ZIndex = 305,
		})
	end

	local body = Create.New("Frame", {
		Name = "Body",
		Parent = modal,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 308,
	})
	Create.List(body, { Direction = Enum.FillDirection.Vertical, Gap = 0 })

	local searchBar = Create.New("Frame", {
		Name = "SearchBar",
		Parent = body,
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		Padding = { 0, 12, 0, 14 },
		LayoutOrder = 1,
		ZIndex = 309,
	})

	Icons.Create("search", {
		Size = UDim2.fromOffset(17, 17),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Color = "SubText",
		ZIndex = 310,
		Parent = searchBar,
	})

	searchBox = Create.Text({
		Class = "TextBox",
		Name = "SearchInput",
		Parent = searchBar,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 28, 0.5, 0),
		Size = UDim2.new(1, -78, 0, 32),
		PlaceholderText = "Search commands, tabs, settings, themes...",
		Font = "Medium",
		TextSize = 14,
		Color = "Text",
		Theme = {
			TextColor3 = "Text",
			PlaceholderColor3 = "Muted",
		},
		ZIndex = 310,
	})

	local escChip = Create.Text({
		Class = "TextButton",
		Name = "EscChip",
		Parent = searchBar,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(38, 22),
		Corner = 6,
		BackgroundTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "ESC",
		Font = "SemiBold",
		TextSize = 10,
		Color = "SubText",
		Theme = { BackgroundColor3 = "Field", TextColor3 = "SubText" },
		ZIndex = 310,
	})
	Create.GlassStroke(escChip, 0.02)

	Create.New("Frame", {
		Name = "TopDivider",
		Parent = body,
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = 2,
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		ZIndex = 309,
	})

	local listWrap = Create.New("Frame", {
		Name = "ListWrap",
		Parent = body,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ZIndex = 309,
	})

	resultsScroll = Create.New("ScrollingFrame", {
		Name = "Results",
		Parent = listWrap,
		Size = UDim2.new(1, 0, 0, 220),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Padding = { 6, 8, 6, 8 },
		Theme = { ScrollBarImageColor3 = "Muted" },
		ZIndex = 310,
	})
	Create.List(resultsScroll, { Direction = Enum.FillDirection.Vertical, Gap = ROW_GAP })

	emptyLabel = Create.Text({
		Name = "Empty",
		Parent = listWrap,
		Visible = false,
		Size = UDim2.new(1, 0, 0, 84),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "No matching commands or settings found",
		Font = "Medium",
		TextSize = 12,
		Color = "Muted",
		ZIndex = 311,
	})

	local footer = Create.New("Frame", {
		Name = "Footer",
		Parent = body,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 0.35,
		Padding = { 0, 14, 0, 14 },
		Theme = { BackgroundColor3 = "Field" },
		LayoutOrder = 4,
		ZIndex = 309,
	})

	footerHint = Create.Text({
		Name = "Hint",
		Parent = footer,
		Size = UDim2.fromScale(1, 1),
		Text = Util.IsTouchDevice() and "Tap any result to jump or execute" or "Up / Down to navigate   •   Enter to execute   •   Esc to close",
		Font = "Regular",
		TextSize = 11,
		Color = "Muted",
		ZIndex = 310,
	})

	rootMaid:Give(backdrop.Activated:Connect(function(input)
		-- Close only when clicking backdrop outside modal
		local pos = typeof(input) == "InputObject" and Vector2.new(input.Position.X, input.Position.Y) or Util.MousePosition()
		local mPos = modal.AbsolutePosition
		local mSize = modal.AbsoluteSize
		local inside = pos.X >= mPos.X and pos.X <= mPos.X + mSize.X and pos.Y >= mPos.Y and pos.Y <= mPos.Y + mSize.Y
		if not inside then
			CommandPalette.Close()
		end
	end))

	rootMaid:Give(escChip.Activated:Connect(function(input)
		Transition.Ripple(escChip, input)
		CommandPalette.Close()
	end))

	rootMaid:Give(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		if isOpen then
			rebuildResults(searchBox.Text)
		end
	end))

	rootMaid:Give(searchBox.FocusLost:Connect(function(enterPressed)
		if isOpen and enterPressed and selectedIndex >= 1 and results[selectedIndex] then
			executeItem(results[selectedIndex])
		end
	end))

	rootMaid:Give(modal:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncShadow))
	rootMaid:Give(layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateModalWidth))

	updateModalWidth()
	return true
end

function CommandPalette.Init(popupLayer, window)
	if layer ~= popupLayer then
		rootMaid:Clean()
		openMaid:Clean()
		if backdrop then
			backdrop:Destroy()
			backdrop = nil
		end
		layer = popupLayer
	end
	windowRef = window
	isOpen = false
	ensureBuilt()
	return CommandPalette
end

function CommandPalette.Open()
	if isOpen then
		return
	end
	if not ensureBuilt() or not searchBox then
		return
	end

	isOpen = true
	openMaid:Clean()
	updateModalWidth()

	backdrop.Active = true
	backdrop:SetAttribute("_BaliClosing", nil)
	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	Tween.Play(backdrop, { BackgroundTransparency = Theme.Current.OverlayTransparency }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	searchBox.Text = ""
	rebuildResults("")
	updateModalWidth()
	Transition.Mount(modal, 0.95)
	syncShadow()
	if shadow then
		shadow.ImageTransparency = 1
		Tween.Play(shadow, { ImageTransparency = Theme.Current.ShadowTransparency }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end

	openMaid:Give(Services.UserInputService.InputBegan:Connect(function(input)
		if not isOpen then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local code = input.KeyCode
		if code == Enum.KeyCode.Escape then
			CommandPalette.Close()
		elseif code == Enum.KeyCode.Down then
			if #results > 0 then
				selectedIndex = (selectedIndex % #results) + 1
				updateSelectionVisuals(true)
			end
		elseif code == Enum.KeyCode.Up then
			if #results > 0 then
				selectedIndex = ((selectedIndex - 2) % #results) + 1
				updateSelectionVisuals(true)
			end
		elseif (code == Enum.KeyCode.Return or code == Enum.KeyCode.KeypadEnter) then
			if Services.UserInputService:GetFocusedTextBox() ~= searchBox then
				if selectedIndex >= 1 and results[selectedIndex] then
					executeItem(results[selectedIndex])
				end
			end
		end
	end))

	task.defer(function()
		if isOpen and searchBox and searchBox.Parent then
			pcall(function()
				searchBox:CaptureFocus()
			end)
		end
	end)
end

function CommandPalette.Close()
	if not isOpen then
		return
	end
	isOpen = false
	openMaid:Clean()

	if searchBox then
		pcall(function()
			searchBox:ReleaseFocus()
		end)
	end
	if shadow then
		Tween.Play(shadow, { ImageTransparency = 1 }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	if backdrop then
		backdrop.Active = false
		backdrop:SetAttribute("_BaliClosing", true)
		Tween.Play(backdrop, { BackgroundTransparency = 1 }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	if modal then
		Transition.Unmount(modal, 0.95, function()
			if not isOpen then
				if shadow and shadow.Parent then
					shadow.Visible = false
				end
				if backdrop and backdrop.Parent then
					backdrop.Visible = false
				end
				if modal and modal.Parent then
					modal.Visible = false
				end
			end
		end)
	elseif backdrop then
		if shadow and shadow.Parent then
			shadow.Visible = false
		end
		backdrop.Visible = false
	end
end

function CommandPalette.Toggle()
	if isOpen then
		CommandPalette.Close()
	else
		CommandPalette.Open()
	end
end

function CommandPalette.IsOpen()
	return isOpen
end

function CommandPalette.Destroy()
	isOpen = false
	openMaid:Clean()
	rootMaid:Clean()
	table.clear(results)
	table.clear(rowViews)
	if backdrop then
		backdrop:Destroy()
		backdrop = nil
	end
	shadow = nil
	modal = nil
	searchBox = nil
	resultsScroll = nil
	emptyLabel = nil
	footerHint = nil
	layer = nil
	windowRef = nil
end

return CommandPalette
