--[[
	Bali UI · Window/MobileButton
	Draggable glass floating pill button for mobile/touch users and minimized windows.
	Uses a pointer drag-distance threshold so dragging never accidentally toggles the UI.
]]

local Assets = require("Core/Assets")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Maid = require("Core/Maid")
local Services = require("Core/Services")
local Theme = require("Core/Theme")
local Transition = require("Core/Transition")
local Util = require("Core/Util")

local MobileButton = {}
MobileButton.__index = MobileButton

local DRAG_THRESHOLD = 6

function MobileButton.new(parentLayer, window, options)
	assert(typeof(parentLayer) == "Instance", "[Bali] MobileButton expects a parentLayer Instance")
	options = Util.Options(options, {
		Title = "Bali",
		Icon = "sparkles",
		Enabled = true,
		AlwaysShow = false,
		Position = UDim2.fromOffset(18, 18),
	}, "Title")

	local maid = Maid.new()

	local wrapper = Create.New("Frame", {
		Name = "BaliMobileButton",
		Position = options.Position or UDim2.fromOffset(18, 18),
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
		Parent = parentLayer,
	})
	maid:Give(wrapper)

	local shadowDesc = Assets.Shadow()
	Create.New("ImageLabel", {
		Name = "Shadow",
		Image = shadowDesc.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowDesc.Slice,
		Position = UDim2.fromOffset(-shadowDesc.Inset, -shadowDesc.Inset + 3),
		Size = UDim2.new(1, shadowDesc.Inset * 2, 1, shadowDesc.Inset * 2),
		BackgroundTransparency = 1,
		Theme = {
			ImageColor3 = "Shadow",
			ImageTransparency = "ShadowTransparency",
		},
		ZIndex = 1,
		Parent = wrapper,
	})

	local pill = Create.New("TextButton", {
		Name = "Pill",
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Corner = 999,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = "CardTransparency",
		},
		Padding = { 0, 12, 0, 8 },
		ZIndex = 2,
		Parent = wrapper,
	})
	local stroke = Create.GlassStroke(pill, 0.05)

	local content = Create.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = pill,
	})
	Create.List(content, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 8,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local badge = Create.New("Frame", {
		Size = UDim2.fromOffset(24, 24),
		Corner = 999,
		Theme = { BackgroundColor3 = "Accent" },
		LayoutOrder = 1,
		Parent = content,
	})
	local badgeGrad = Instance.new("UIGradient")
	badgeGrad.Color = Theme.AccentSequence()
	badgeGrad.Rotation = 35
	badgeGrad.Parent = badge
	maid:Give(Theme.Changed:Connect(function(theme)
		badgeGrad.Color = Theme.AccentSequence(theme)
	end))

	Icons.Create(options.Icon or "sparkles", {
		Size = UDim2.fromOffset(13, 13),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "AccentText",
		Parent = badge,
	})

	local titleLabel = Create.Text({
		Text = tostring(options.Title or "Bali"),
		Font = "SemiBold",
		TextSize = 12,
		Color = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = content,
	})

	local statusDot = Create.New("Frame", {
		Size = UDim2.fromOffset(6, 6),
		Corner = 999,
		Theme = { BackgroundColor3 = "Success" },
		LayoutOrder = 3,
		Parent = content,
	})

	Transition.Hover(pill, pill, "Card", "TileHover", stroke)

	local self = setmetatable({
		Frame = wrapper,
		Pill = pill,
		Window = window,
		Maid = maid,
		Enabled = options.Enabled ~= false,
		AlwaysShow = options.AlwaysShow == true,
		_titleLabel = titleLabel,
		_statusDot = statusDot,
	}, MobileButton)

	-- Drag + tap threshold logic
	local dragging = false
	local moved = false
	local dragStartMouse
	local dragStartPos

	local function clampPosition(x, y)
		local vp = parentLayer.AbsoluteSize
		local size = wrapper.AbsoluteSize
		local maxX = math.max(8, vp.X - size.X - 8)
		local maxY = math.max(8, vp.Y - size.Y - 8)
		return Util.Clamp(x, 8, maxX), Util.Clamp(y, 8, maxY)
	end

	maid:Give(pill.InputBegan:Connect(function(input)
		if not Util.IsPointer(input) then
			return
		end
		dragging = true
		moved = false
		dragStartMouse = Vector2.new(input.Position.X, input.Position.Y)
		dragStartPos = Vector2.new(wrapper.Position.X.Offset, wrapper.Position.Y.Offset)
	end))

	maid:Give(Services.UserInputService.InputChanged:Connect(function(input)
		if not dragging or not Util.IsMove(input) then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartMouse
		if not moved and delta.Magnitude >= DRAG_THRESHOLD then
			moved = true
		end
		if moved then
			local nx, ny = clampPosition(dragStartPos.X + delta.X, dragStartPos.Y + delta.Y)
			wrapper.Position = UDim2.fromOffset(math.floor(nx), math.floor(ny))
		end
	end))

	maid:Give(Services.UserInputService.InputEnded:Connect(function(input)
		if not dragging or not Util.IsPointer(input) then
			return
		end
		local wasMoved = moved
		dragging = false
		moved = false
		if not wasMoved and self.Window and type(self.Window.Toggle) == "function" then
			Transition.Ripple(pill, input, "Accent")
			self.Window:Toggle()
		end
	end))

	maid:Give(parentLayer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local nx, ny = clampPosition(wrapper.Position.X.Offset, wrapper.Position.Y.Offset)
		wrapper.Position = UDim2.fromOffset(math.floor(nx), math.floor(ny))
	end))

	self:UpdateVisibility()
	return self
end

function MobileButton:SetTitle(text)
	self._titleLabel.Text = tostring(text or "Bali")
end

function MobileButton:SetEnabled(enabled)
	self.Enabled = enabled == true
	self:UpdateVisibility()
end

function MobileButton:IsEnabled()
	return self.Enabled
end

function MobileButton:SetVisible(visible)
	self.Frame.Visible = visible == true
end

function MobileButton:UpdateVisibility()
	local winVisible = self.Window and self.Window:IsVisible()
	Theme.Bind(self._statusDot, { BackgroundColor3 = winVisible and "Success" or "Muted" })
	local shouldShow = self.Enabled and (self.AlwaysShow or Util.IsTouchDevice() or not winVisible)
	self.Frame.Visible = shouldShow
end

function MobileButton:Destroy()
	self.Maid:Clean()
end

return MobileButton
