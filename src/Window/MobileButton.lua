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
		Subtitle = "Tap to show",
		Icon = "bali-logo",
		Enabled = true,
		AlwaysShow = false,
		Centered = true,
		Position = nil,
	}, "Title")

	local maid = Maid.new()
	local userDragged = options.Position ~= nil

	local function defaultCenteredPos()
		local vpX = parentLayer.AbsoluteSize.X
		local approxW = 168
		local x = vpX > 0 and math.floor((vpX - approxW) * 0.5) or 18
		return UDim2.fromOffset(math.max(8, x), 12)
	end

	local wrapper = Create.New("Frame", {
		Name = "BaliMobileButton",
		Position = options.Position or defaultCenteredPos(),
		Size = UDim2.fromOffset(0, 42),
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
		Size = UDim2.fromOffset(0, 42),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Corner = 999,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.04)
			end,
		},
		Padding = { 0, 14, 0, 10 },
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
		Gap = 9,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local badge = Create.New("Frame", {
		Size = UDim2.fromOffset(24, 24),
		Corner = 7,
		Theme = { BackgroundColor3 = "Accent" },
		BackgroundTransparency = 0.88,
		LayoutOrder = 1,
		Parent = content,
	})
	Create.Stroke(badge, {
		Theme = { Color = "Accent" },
		Transparency = 0.68,
		Thickness = 1,
	})

	Icons.Create(options.Icon or "bali-logo", {
		Size = UDim2.fromOffset(15, 15),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "Accent",
		Parent = badge,
	})

	local textCol = Create.New("Frame", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = content,
	})
	Create.List(textCol, {
		Gap = 1,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local titleLabel = Create.Text({
		Text = tostring(options.Title or "Bali"),
		Font = "SemiBold",
		TextSize = 12,
		Color = "Text",
		Size = UDim2.fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = textCol,
	})

	local subLabel = Create.Text({
		Text = tostring(options.Subtitle or "Tap to show"),
		Font = "Regular",
		TextSize = 10,
		Color = "SubText",
		Size = UDim2.fromOffset(0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = textCol,
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
		_subLabel = subLabel,
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

	local function recenterIfAuto()
		if userDragged then
			return
		end
		local vpX = parentLayer.AbsoluteSize.X
		local w = wrapper.AbsoluteSize.X > 0 and wrapper.AbsoluteSize.X or 168
		if vpX > 0 then
			local nx, ny = clampPosition(math.floor((vpX - w) * 0.5), 12)
			wrapper.Position = UDim2.fromOffset(math.floor(nx), math.floor(ny))
		end
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
			userDragged = true
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
		if not userDragged then
			recenterIfAuto()
		else
			local nx, ny = clampPosition(wrapper.Position.X.Offset, wrapper.Position.Y.Offset)
			wrapper.Position = UDim2.fromOffset(math.floor(nx), math.floor(ny))
		end
	end))
	maid:Give(wrapper:GetPropertyChangedSignal("AbsoluteSize"):Connect(recenterIfAuto))

	self:UpdateVisibility()
	return self
end

function MobileButton:GetRect()
	local w = self.Frame.AbsoluteSize.X > 0 and self.Frame.AbsoluteSize.X or 168
	local h = self.Frame.AbsoluteSize.Y > 0 and self.Frame.AbsoluteSize.Y or 40
	local vp = self.Frame.Parent and self.Frame.Parent.AbsoluteSize or Vector2.new(1280, 720)
	local slideTarget = self.Frame:GetAttribute("_BaliSlideTargetPos")
	local refPos = typeof(slideTarget) == "UDim2" and slideTarget or self.Frame.Position
	local x = refPos.X.Offset
	if x <= 0 and vp.X > 0 then
		x = math.floor((vp.X - w) * 0.5)
	end
	local y = refPos.Y.Offset > 0 and refPos.Y.Offset or 12
	return x, y, w, h
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
	local wasVisible = self.Frame.Visible
	local winVisible = self.Window and self.Window:IsVisible()
	local mobileMode = self.Window and type(self.Window.IsMobileMode) == "function" and self.Window:IsMobileMode()
	Theme.Bind(self._statusDot, { BackgroundColor3 = winVisible and "Success" or "Muted" })
	local shouldShow = self.Enabled and (self.AlwaysShow or mobileMode or Util.IsTouchDevice() or not winVisible)
	self.Frame.Visible = shouldShow
	if shouldShow and not wasVisible and self.Frame.Parent then
		Transition.SlideFade(self.Frame, 0, -8)
	end
end

function MobileButton:Destroy()
	self.Maid:Clean()
end

return MobileButton
