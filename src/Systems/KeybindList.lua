--[[
	Bali UI · Systems/KeybindList
	Draggable obsidian glass HUD displaying active or all registered keybinds
	with AutomaticSize.Y rows and zero text overlap.
]]

local Maid = require("Core/Maid")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Util = require("Core/Util")
local Input = require("Systems/Input")

local KeybindList = {}

local PANEL_WIDTH = 228

local rootMaid = Maid.new()
local layer = nil
local panel = nil
local modeChip = nil
local rowsContainer = nil
local emptyLabel = nil
local dragHandle = nil

local visible = false
local mode = "ActiveOnly" -- "ActiveOnly" | "All"
local entries = {} -- [id] = { Order, Title, KeyName, Mode, Active, Row? }
local orderCounter = 0

local function normalizeMode(value)
	return value == "All" and "All" or "ActiveOnly"
end

local function isRowVisible(entry)
	if mode == "All" then
		return true
	end
	return entry.Active == true
end

local function applyRowState(entry)
	local row = entry.Row
	if not row then
		return
	end

	local show = isRowVisible(entry)
	row.Frame.Visible = show

	row.Title.Text = tostring(entry.Title or "Keybind")
	local keyLabel = entry.KeyName and tostring(entry.KeyName) or "None"
	row.KeyLabel.Text = keyLabel ~= "" and keyLabel or "None"

	local shortMode = entry.Mode == "Hold" and "H" or (entry.Mode == "Always" and "A" or "T")
	row.ModeLabel.Text = shortMode

	if entry.Active then
		Theme.Bind(row.Dot, { BackgroundColor3 = "Accent" })
		Theme.Bind(row.Title, { TextColor3 = "Text" })
		Theme.Bind(row.KeyChip, { BackgroundColor3 = "TileHover" })
		Theme.Bind(row.KeyLabel, { TextColor3 = "Text" })
		Tween.Play(row.Frame, { BackgroundTransparency = 0.25 }, Tween.Fast)
	else
		Theme.Bind(row.Dot, { BackgroundColor3 = "Muted" })
		Theme.Bind(row.Title, { TextColor3 = "SubText" })
		Theme.Bind(row.KeyChip, { BackgroundColor3 = "Field" })
		Theme.Bind(row.KeyLabel, { TextColor3 = "Muted" })
		Tween.Play(row.Frame, { BackgroundTransparency = 1 }, Tween.Fast)
	end
end

local function refreshEmptyState()
	if not emptyLabel then
		return
	end
	local visibleCount = 0
	for _, entry in pairs(entries) do
		if isRowVisible(entry) then
			visibleCount += 1
		end
	end
	emptyLabel.Visible = visibleCount == 0
	emptyLabel.Text = mode == "ActiveOnly" and "No active keybinds" or "No keybinds registered"
end

local function buildRow(id, entry)
	if not rowsContainer or not rowsContainer.Parent then
		return
	end
	if entry.Row and entry.Row.Frame then
		entry.Row.Frame:Destroy()
	end

	local rowFrame = Create.New("Frame", {
		Name = "Keybind_" .. tostring(id),
		Parent = rowsContainer,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Corner = 7,
		Padding = { 5, 6, 5, 6 },
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "Tile" },
		LayoutOrder = entry.Order,
		ZIndex = 342,
	})

	local dot = Create.New("Frame", {
		Name = "Indicator",
		Parent = rowFrame,
		Position = UDim2.fromOffset(2, 6),
		Size = UDim2.fromOffset(6, 6),
		Corner = UDim.new(1, 0),
		Theme = { BackgroundColor3 = "Accent" },
		ZIndex = 343,
	})

	local title = Create.Text({
		Name = "Title",
		Parent = rowFrame,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -92, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Font = "Medium",
		TextSize = 12,
		Color = "Text",
		ZIndex = 343,
	})

	local rightGroup = Create.New("Frame", {
		Name = "Right",
		Parent = rowFrame,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 343,
	})
	Create.List(rightGroup, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 4,
	})
	local function syncTitleWidth()
		local rw = rightGroup.AbsoluteSize.X
		local reserve = math.max(76, rw + 20)
		title.Size = UDim2.new(1, -reserve, 0, 0)
	end
	rightGroup:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncTitleWidth)
	task.defer(syncTitleWidth)

	local modeChipRow = Create.New("Frame", {
		Name = "ModeBadge",
		Parent = rightGroup,
		Size = UDim2.fromOffset(18, 18),
		Corner = 5,
		BackgroundTransparency = 0.4,
		Theme = { BackgroundColor3 = "Field" },
		LayoutOrder = 1,
		ZIndex = 344,
	})
	local modeLabel = Create.Text({
		Name = "Label",
		Parent = modeChipRow,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = "SemiBold",
		TextSize = 10,
		Color = "Muted",
		ZIndex = 345,
	})

	local keyChip = Create.New("Frame", {
		Name = "KeyChip",
		Parent = rightGroup,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Corner = 5,
		Padding = { 0, 6, 0, 6 },
		Theme = { BackgroundColor3 = "Field" },
		LayoutOrder = 2,
		ZIndex = 344,
	})
	Create.GlassStroke(keyChip, 0.02)

	local keyLabel = Create.Text({
		Name = "Label",
		Parent = keyChip,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = "SemiBold",
		TextSize = 10,
		Color = "Text",
		ZIndex = 345,
	})

	entry.Row = {
		Frame = rowFrame,
		Dot = dot,
		Title = title,
		ModeLabel = modeLabel,
		KeyChip = keyChip,
		KeyLabel = keyLabel,
	}

	applyRowState(entry)
end

local function ensureBuilt()
	if panel and panel.Parent then
		return true
	end
	if not layer or not layer.Parent then
		return false
	end

	panel = Create.New("Frame", {
		Name = "BaliKeybindList",
		Parent = layer,
		Visible = visible,
		Active = true,
		Position = UDim2.fromOffset(16, 112),
		Size = UDim2.fromOffset(PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Corner = 12,
		ClipsDescendants = true,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.08)
			end,
		},
		ZIndex = 340,
	})
	Create.GlassStroke(panel, 0.06)

	local bgClip = Create.New("CanvasGroup", {
		Name = "BackgroundClip",
		Parent = panel,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Corner = 12,
		ZIndex = 340,
	})

	local glowId = Assets.Get("Glow")
	if glowId then
		Create.New("ImageLabel", {
			Name = "Glow",
			Parent = bgClip,
			Size = UDim2.fromScale(0.85, 0.9),
			Position = UDim2.fromScale(-0.2, -0.35),
			Image = glowId,
			ScaleType = Enum.ScaleType.Stretch,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = function(t)
					return math.min(t.GlowTransparency + 0.05, 0.94)
				end,
			},
			ZIndex = 340,
		})
	end

	local noiseId = Assets.Get("Noise")
	if noiseId then
		Create.New("ImageLabel", {
			Name = "Noise",
			Parent = bgClip,
			Size = UDim2.fromScale(1, 1),
			Corner = 12,
			Image = noiseId,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(128, 128),
			Theme = {
				ImageColor3 = "Stroke",
				ImageTransparency = "NoiseTransparency",
			},
			ZIndex = 340,
		})
	end

	local wrapper = Create.New("Frame", {
		Name = "Wrapper",
		Parent = panel,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 341,
	})
	Create.List(wrapper, { Direction = Enum.FillDirection.Vertical, Gap = 0 })

	local header = Create.New("Frame", {
		Name = "Header",
		Parent = wrapper,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Padding = { 0, 10, 0, 12 },
		LayoutOrder = 1,
		ZIndex = 342,
	})

	Icons.Create("keyboard", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Color = "Accent",
		ZIndex = 343,
		Parent = header,
	})

	Create.Text({
		Name = "Title",
		Parent = header,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		Size = UDim2.new(1, -86, 0, 18),
		Text = "Keybinds",
		Font = "SemiBold",
		TextSize = 12,
		Color = "Text",
		ZIndex = 343,
	})

	modeChip = Create.Text({
		Class = "TextButton",
		Name = "ModeChip",
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(48, 20),
		Corner = 6,
		BackgroundTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = mode == "ActiveOnly" and "Active" or "All",
		Font = "SemiBold",
		TextSize = 10,
		Color = "SubText",
		Theme = { BackgroundColor3 = "Tile", TextColor3 = "SubText" },
		ZIndex = 343,
	})
	Create.GlassStroke(modeChip, 0.02)
	rootMaid:Give(modeChip.Activated:Connect(function(input)
		Transition.Ripple(modeChip, input)
		KeybindList.SetMode(mode == "ActiveOnly" and "All" or "ActiveOnly")
	end))

	Create.New("Frame", {
		Name = "Divider",
		Parent = wrapper,
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = 2,
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		ZIndex = 342,
	})

	rowsContainer = Create.New("Frame", {
		Name = "Rows",
		Parent = wrapper,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 6, 8, 8, 8 },
		LayoutOrder = 3,
		ZIndex = 342,
	})
	Create.List(rowsContainer, { Direction = Enum.FillDirection.Vertical, Gap = 4 })

	emptyLabel = Create.Text({
		Name = "Empty",
		Parent = rowsContainer,
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "No active keybinds",
		Font = "Regular",
		TextSize = 11,
		Color = "Muted",
		LayoutOrder = 999999,
		ZIndex = 343,
	})

	dragHandle = Input.BindDrag(header, panel, { Clamp = true, Padding = 8 })
	rootMaid:Give(dragHandle)

	for id, entry in pairs(entries) do
		buildRow(id, entry)
	end
	refreshEmptyState()

	return true
end

function KeybindList.Init(targetLayer)
	if layer == targetLayer and panel and panel.Parent then
		return KeybindList
	end
	rootMaid:Clean()
	for _, entry in pairs(entries) do
		entry.Row = nil
	end
	if panel then
		panel:Destroy()
		panel = nil
	end
	layer = targetLayer
	ensureBuilt()
	return KeybindList
end

function KeybindList.SetVisible(state)
	local targetState = state == true
	visible = targetState
	if not ensureBuilt() then
		return
	end

	if targetState then
		Transition.Mount(panel, 0.94)
	else
		Transition.Unmount(panel, 0.94, function()
			if not visible and panel and panel.Parent then
				panel.Visible = false
			end
		end)
	end
end

function KeybindList.IsVisible()
	return visible
end

function KeybindList.SetMode(newMode)
	mode = normalizeMode(newMode)
	if modeChip then
		modeChip.Text = mode == "ActiveOnly" and "Active" or "All"
	end
	for _, entry in pairs(entries) do
		applyRowState(entry)
	end
	refreshEmptyState()
end

function KeybindList.Register(id, meta)
	if id == nil then
		return
	end
	meta = type(meta) == "table" and meta or {}

	local existing = entries[id]
	if existing then
		KeybindList.Update(id, meta)
		return
	end

	orderCounter += 1
	local entry = {
		Order = orderCounter,
		Title = meta.Title or tostring(id),
		KeyName = meta.KeyName or "None",
		Mode = meta.Mode or "Toggle",
		Active = meta.Active == true,
		Row = nil,
	}
	entries[id] = entry
	if rowsContainer and rowsContainer.Parent then
		buildRow(id, entry)
		refreshEmptyState()
	end
end

function KeybindList.Update(id, meta)
	if id == nil or type(meta) ~= "table" then
		return
	end
	local entry = entries[id]
	if not entry then
		KeybindList.Register(id, meta)
		return
	end

	if meta.Title ~= nil then
		entry.Title = meta.Title
	end
	if meta.KeyName ~= nil then
		entry.KeyName = meta.KeyName
	end
	if meta.Mode ~= nil then
		entry.Mode = meta.Mode
	end
	if meta.Active ~= nil then
		entry.Active = meta.Active == true
	end

	applyRowState(entry)
	refreshEmptyState()
end

function KeybindList.Unregister(id)
	local entry = entries[id]
	if not entry then
		return
	end
	if entry.Row and entry.Row.Frame then
		entry.Row.Frame:Destroy()
	end
	entries[id] = nil
	refreshEmptyState()
end

function KeybindList.Destroy()
	visible = false
	rootMaid:Clean()
	for _, entry in pairs(entries) do
		if entry.Row and entry.Row.Frame then
			entry.Row.Frame:Destroy()
		end
		entry.Row = nil
	end
	table.clear(entries)
	if panel then
		panel:Destroy()
		panel = nil
	end
	modeChip = nil
	rowsContainer = nil
	emptyLabel = nil
	dragHandle = nil
	layer = nil
end

return KeybindList
