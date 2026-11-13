--[[
	Bali UI · Systems/Tooltip
	Delayed obsidian glass tooltips with AutomaticSize.Y wrapping, smart viewport clamping,
	and cursor-avoidance positioning.
]]

local Services = require("Core/Services")
local Maid = require("Core/Maid")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Transition = require("Core/Transition")
local Util = require("Core/Util")

local Tooltip = {}

local DEFAULT_DELAY = 0.3
local MAX_WIDTH = 260
local MIN_WIDTH = 44
local EDGE_PAD = 8

local rootMaid = Maid.new()
local layer = nil
local card = nil
local shadow = nil
local label = nil
local visible = false
local activeOwner = nil
local pendingThread = nil
local boundCleanups = {} -- [GuiObject] = cleanupFn

local function getViewportBounds()
	if layer and layer.AbsoluteSize.X > 0 and layer.AbsoluteSize.Y > 0 then
		return layer.AbsolutePosition, layer.AbsoluteSize
	end
	local camera = Services.Workspace.CurrentCamera
	local raw = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local ok, inset = pcall(function()
		return Services.GuiService:GetGuiInset()
	end)
	if ok and inset then
		return Vector2.new(inset.X, inset.Y), Vector2.new(raw.X - inset.X, raw.Y - inset.Y)
	end
	return Vector2.zero, raw
end

local function getCursorPosition()
	if layer then
		local rootGui = layer:FindFirstAncestorWhichIsA("ScreenGui")
		if rootGui and rootGui.IgnoreGuiInset then
			return Services.UserInputService:GetMouseLocation()
		end
	end
	return Util.MousePosition()
end

local function cancelPending()
	if pendingThread then
		pcall(task.cancel, pendingThread)
		pendingThread = nil
	end
end

local function syncShadow()
	if not shadow or not card then
		return
	end
	if not card.Visible then
		shadow.Visible = false
		return
	end
	local shadowInfo = Assets.Shadow()
	local inset = shadowInfo.Inset or 24
	local size = card.AbsoluteSize
	local pos = card.Position
	shadow.Visible = true
	shadow.Position = UDim2.new(pos.X.Scale, pos.X.Offset - inset, pos.Y.Scale, pos.Y.Offset - inset)
	shadow.Size = UDim2.fromOffset(size.X + inset * 2, size.Y + inset * 2)
end

local function measureWidth(text)
	local font = Theme.Font("Medium")
	local ok, bounds = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = font
		params.Size = 12
		params.Width = MAX_WIDTH - 20
		return Services.TextService:GetTextBoundsAsync(params)
	end)
	if ok and bounds then
		return Util.Clamp(math.ceil(bounds.X) + 22, MIN_WIDTH, MAX_WIDTH)
	end
	return Util.Clamp(#text * 7 + 22, MIN_WIDTH, MAX_WIDTH)
end

local function placeNearCursor(w, h)
	local origin, vp = getViewportBounds()
	local cursor = getCursorPosition()
	local offset = 14
	local minX = origin.X + EDGE_PAD
	local minY = origin.Y + EDGE_PAD
	local maxX = math.max(minX, origin.X + vp.X - w - EDGE_PAD)
	local maxY = math.max(minY, origin.Y + vp.Y - h - EDGE_PAD)

	local x = cursor.X + offset
	local y = cursor.Y + offset + 4

	if x + w + EDGE_PAD > origin.X + vp.X then
		x = cursor.X - w - offset
	end
	if y + h + EDGE_PAD > origin.Y + vp.Y then
		y = cursor.Y - h - offset
	end

	x = Util.Clamp(x, minX, maxX)
	y = Util.Clamp(y, minY, maxY)

	-- Guarantee cursor does not overlap the clamped tooltip box
	local cursorPad = 10
	local overlapsX = cursor.X >= (x - 4) and cursor.X <= (x + w + 4)
	local overlapsY = cursor.Y >= (y - 4) and cursor.Y <= (y + h + 4)
	if overlapsX and overlapsY then
		local aboveY = cursor.Y - h - cursorPad
		local belowY = cursor.Y + cursorPad + 8
		if aboveY >= minY then
			y = aboveY
		elseif belowY + h + EDGE_PAD <= origin.Y + vp.Y then
			y = belowY
		else
			local leftX = cursor.X - w - cursorPad
			local rightX = cursor.X + cursorPad
			if leftX >= minX then
				x = leftX
			elseif rightX + w + EDGE_PAD <= origin.X + vp.X then
				x = rightX
			end
		end
	end

	return math.round(x), math.round(y)
end

local function placeNearAnchor(anchorGui, w, h)
	local origin, vp = getViewportBounds()
	local absPos = anchorGui.AbsolutePosition
	local absSize = anchorGui.AbsoluteSize
	local gap = 8
	local minX = origin.X + EDGE_PAD
	local minY = origin.Y + EDGE_PAD
	local maxX = math.max(minX, origin.X + vp.X - w - EDGE_PAD)
	local maxY = math.max(minY, origin.Y + vp.Y - h - EDGE_PAD)

	local x = absPos.X + (absSize.X - w) * 0.5
	local y = absPos.Y + absSize.Y + gap

	if y + h + EDGE_PAD > origin.Y + vp.Y then
		local aboveY = absPos.Y - h - gap
		if aboveY >= minY then
			y = aboveY
		end
	end

	x = Util.Clamp(x, minX, maxX)
	y = Util.Clamp(y, minY, maxY)

	return math.round(x), math.round(y)
end

local function updatePosition(anchorGui)
	if not card then
		return
	end
	local size = card.AbsoluteSize
	local w = size.X > 0 and size.X or card.Size.X.Offset
	local h = size.Y > 0 and size.Y or 28

	local x, y
	if anchorGui and typeof(anchorGui) == "Instance" and anchorGui:IsA("GuiObject") and anchorGui.Parent then
		x, y = placeNearAnchor(anchorGui, w, h)
	else
		x, y = placeNearCursor(w, h)
	end

	local parentPos = (layer and layer:IsA("GuiBase2d")) and layer.AbsolutePosition or Vector2.zero
	card.Position = UDim2.fromOffset(x - parentPos.X, y - parentPos.Y)
	syncShadow()
end

local function ensureBuilt()
	if card and card.Parent then
		return true
	end
	if not layer or not layer.Parent then
		return false
	end

	local shadowInfo = Assets.Shadow()
	shadow = Create.New("ImageLabel", {
		Name = "BaliTooltipShadow",
		Parent = layer,
		Visible = false,
		Image = shadowInfo.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowInfo.Slice,
		ImageTransparency = Theme.Current.ShadowTransparency,
		Theme = { ImageColor3 = "Shadow", ImageTransparency = "ShadowTransparency" },
		ZIndex = 499,
	})

	card = Create.New("Frame", {
		Name = "BaliTooltip",
		Parent = layer,
		Visible = false,
		Size = UDim2.fromOffset(120, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Corner = 8,
		Padding = { 7, 10, 7, 10 },
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.06)
			end,
		},
		ZIndex = 500,
	})
	Create.GlassStroke(card, 0.05)

	label = Create.Text({
		Name = "Text",
		Parent = card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Font = "Medium",
		TextSize = 12,
		Color = "Text",
		ZIndex = 501,
	})

	rootMaid:Give(card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if visible then
			updatePosition(activeOwner and typeof(activeOwner) == "Instance" and activeOwner or nil)
		end
	end))

	return true
end

function Tooltip.Init(popupLayer)
	if layer == popupLayer and card and card.Parent then
		return Tooltip
	end
	if card then
		card:Destroy()
		card = nil
	end
	if shadow then
		shadow:Destroy()
		shadow = nil
	end
	layer = popupLayer
	visible = false
	ensureBuilt()
	return Tooltip
end

function Tooltip.Show(text, anchorGui)
	if text == nil or text == "" then
		Tooltip.Hide()
		return
	end
	if not ensureBuilt() then
		return
	end

	local str = tostring(text)
	local width = measureWidth(str)
	card.Size = UDim2.fromOffset(width, 0)
	label.Text = str

	local wasVisible = visible
	visible = true
	if anchorGui and typeof(anchorGui) == "Instance" then
		activeOwner = anchorGui
	elseif not activeOwner then
		activeOwner = nil
	end

	updatePosition(anchorGui)
	if not wasVisible then
		Transition.Mount(card, 0.94)
		syncShadow()
	else
		card.Visible = true
		syncShadow()
	end
end

function Tooltip.Hide()
	cancelPending()
	activeOwner = nil
	if not visible or not card then
		visible = false
		if shadow then
			shadow.Visible = false
		end
		return
	end
	visible = false
	if shadow then
		shadow.Visible = false
	end
	Transition.Unmount(card, 0.94, function()
		if not visible and card and card.Parent then
			card.Visible = false
		end
	end)
end

function Tooltip.Bind(guiObj, textOrFn, opts)
	if not guiObj then
		return function() end
	end

	if boundCleanups[guiObj] then
		boundCleanups[guiObj]()
	end

	opts = opts or {}
	local delayTime = opts.Delay ~= nil and opts.Delay or DEFAULT_DELAY
	local anchorMode = opts.Anchor or (Util.IsTouchDevice() and "Element" or "Cursor")
	local bindMaid = Maid.new()
	local hovering = false
	local cleaned = false

	local function resolveText()
		if type(textOrFn) == "function" then
			local ok, result = Util.SafeCall(textOrFn)
			return ok and result or nil
		end
		return textOrFn
	end

	local function showForObject()
		if cleaned or not hovering or not guiObj.Parent then
			return
		end
		local content = resolveText()
		if content == nil or content == "" then
			return
		end
		activeOwner = guiObj
		local anchor = anchorMode == "Element" and guiObj or nil
		Tooltip.Show(content, anchor)
	end

	bindMaid:Give(guiObj.MouseEnter:Connect(function()
		if cleaned or Util.IsTouchDevice() then
			return
		end
		hovering = true
		cancelPending()
		pendingThread = task.delay(delayTime, function()
			pendingThread = nil
			showForObject()
		end)
	end))

	bindMaid:Give(guiObj.MouseMoved:Connect(function()
		if cleaned or not hovering then
			return
		end
		if visible and activeOwner == guiObj and anchorMode ~= "Element" then
			updatePosition(nil)
		end
	end))

	local function cancelHover()
		hovering = false
		cancelPending()
		if activeOwner == guiObj then
			Tooltip.Hide()
		end
	end

	bindMaid:Give(guiObj.MouseLeave:Connect(cancelHover))

	bindMaid:Give(guiObj.InputBegan:Connect(function(input)
		if Util.IsPointer(input) then
			if Util.IsTouchDevice() and anchorMode == "Element" then
				hovering = true
				cancelPending()
				pendingThread = task.delay(delayTime, function()
					pendingThread = nil
					showForObject()
				end)
			else
				cancelHover()
			end
		end
	end))

	if Util.IsTouchDevice() then
		bindMaid:Give(guiObj.InputEnded:Connect(function(input)
			if Util.IsPointer(input) then
				cancelHover()
			end
		end))
	end

	bindMaid:Give(guiObj.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			cancelHover()
		end
	end))

	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		cancelHover()
		if boundCleanups[guiObj] == cleanup then
			boundCleanups[guiObj] = nil
		end
		bindMaid:Clean()
	end

	bindMaid:Give(guiObj.Destroying:Connect(cleanup))
	boundCleanups[guiObj] = cleanup
	rootMaid:Give(cleanup)

	return cleanup
end

function Tooltip.Destroy()
	cancelPending()
	for _, fn in pairs(boundCleanups) do
		pcall(fn)
	end
	table.clear(boundCleanups)
	rootMaid:Clean()
	if card then
		card:Destroy()
		card = nil
	end
	if shadow then
		shadow:Destroy()
		shadow = nil
	end
	layer = nil
	label = nil
	activeOwner = nil
	visible = false
end

return Tooltip
