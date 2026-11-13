--[[
	Bali UI · Elements/ColorPicker
	Apple-premium dark glass color picker with swatch pill, 2D SV gradient canvas,
	7-stop Hue spectrum, optional Transparency slider, live #HEX & RGB inputs,
	Rainbow mode, and quick preset swatches inside PopupLayer.
]]

local Services = require("Core/Services")
local Util = require("Core/Util")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Base = require("Elements/Base")
local Tooltip = require("Systems/Tooltip")

local ColorPicker = {}
ColorPicker.__index = ColorPicker

local DEFAULT_PRESETS = {
	Color3.fromRGB(214, 64, 236),
	Color3.fromRGB(59, 130, 246),
	Color3.fromRGB(45, 212, 191),
	Color3.fromRGB(52, 211, 153),
	Color3.fromRGB(251, 113, 133),
	Color3.fromRGB(251, 191, 36),
}

local HUE_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
	ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
	ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
	ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
	ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
	ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
})

local function parseColorInput(input, fallback)
	if typeof(input) == "Color3" then
		return input
	elseif type(input) == "string" then
		return Util.FromHex(input) or fallback
	elseif type(input) == "table" then
		if typeof(input.Color) == "Color3" then
			return input.Color
		elseif type(input.Color) == "string" then
			return Util.FromHex(input.Color) or fallback
		elseif type(input.Hex) == "string" then
			return Util.FromHex(input.Hex) or fallback
		elseif input.R and input.G and input.B then
			return Color3.new(input.R, input.G, input.B)
		elseif typeof(input[1]) == "Color3" then
			return input[1]
		elseif type(input[1]) == "number" and type(input[2]) == "number" and type(input[3]) == "number" then
			if input[1] > 1 or input[2] > 1 or input[3] > 1 then
				return Color3.fromRGB(input[1], input[2], input[3])
			end
			return Color3.new(input[1], input[2], input[3])
		end
	end
	return fallback
end

local function isDisabledOrLocked(self)
	return self.Disabled == true or self.Locked == true or self._disabled == true or self._locked == true
end

function ColorPicker.new(parent, opts, ctx)
	local rawOpts = type(opts) == "table" and opts or {}
	local hasAlpha = rawOpts.Alpha == true or rawOpts.Transparency ~= nil

	opts = Util.Options(opts, {
		Title = "Color Picker",
		Description = nil,
		Default = Theme.Current.Accent,
		Transparency = 0,
		Rainbow = false,
		Presets = DEFAULT_PRESETS,
		Callback = nil,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("ColorPicker", parent, opts, ctx)
	local rowParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local rightWidth = 112
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

	local initialColor = parseColorInput(opts.Default, Theme.Current.Accent)
	local initialAlpha = Util.Clamp(tonumber(opts.Transparency) or 0, 0, 1)
	if type(rawOpts.Default) == "table" and rawOpts.Default.Alpha ~= nil then
		initialAlpha = Util.Clamp(tonumber(rawOpts.Default.Alpha) or initialAlpha, 0, 1)
	end

	local hue, sat, val = Color3.toHSV(initialColor)
	local currentColor = initialColor
	local currentAlpha = initialAlpha
	local rainbowEnabled = opts.Rainbow == true
	local rainbowConn = nil
	local isOpen = false
	local openGen = 0
	local popupId = "ColorPicker_" .. Util.RandomString(8)

	self.Value = currentColor
	self.Alpha = currentAlpha

	-- Row right-side glass swatch pill
	local swatchPill = Create.New("TextButton", {
		Name = "SwatchPill",
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		Corner = 8,
		Padding = { 0, 6, 0, 8 },
		Theme = { BackgroundColor3 = "Field" },
		Parent = row.Right,
	})
	local pillStroke = Create.Stroke(swatchPill, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})
	Transition.Hover(swatchPill, swatchPill, "Field", "FieldHover", pillStroke)

	local pillHex = Create.Text({
		Name = "HexPreview",
		Size = UDim2.new(1, -34, 1, 0),
		Text = "#" .. Util.ToHex(currentColor),
		TextSize = 11,
		Color = "SubText",
		Parent = swatchPill,
	})
	Theme.Unbind(pillHex, "FontFace")
	pillHex.FontFace = Theme.Mono("Medium")

	local pillSwatchBg = Create.New("Frame", {
		Name = "SwatchBg",
		Size = UDim2.fromOffset(26, 18),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Corner = 5,
		Theme = { BackgroundColor3 = "Card" },
		Parent = swatchPill,
	})
	local pillSwatch = Create.New("Frame", {
		Name = "Swatch",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = currentColor,
		BackgroundTransparency = hasAlpha and currentAlpha or 0,
		Corner = 5,
		Parent = pillSwatchBg,
	})
	Create.Stroke(pillSwatchBg, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})

	-- Floating Popover (236px wide)
	local shadowInfo = Assets.Shadow()
	local shadowInset = shadowInfo.Inset or 24
	local popover = Create.New("Frame", {
		Name = popupId,
		Size = UDim2.fromOffset(236, 100),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 110,
		Corner = 12,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency or 0.12, 0.03)
			end,
		},
	})
	Create.GlassStroke(popover, 0.06)

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
		Parent = popover,
	})

	local body = Create.New("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 111,
		Padding = { 12, 12, 12, 12 },
		Parent = popover,
	})
	Create.List(body, { Gap = 10 })

	-- 1. Header row (Title + Rainbow pill)
	local header = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 112,
		Parent = body,
	})

	local headerSwatch = Create.New("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = currentColor,
		Corner = 4,
		ZIndex = 113,
		Parent = header,
	})
	Create.Stroke(headerSwatch, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })

	local headerTitle = Create.Text({
		Size = UDim2.new(1, -96, 1, 0),
		Position = UDim2.fromOffset(20, 0),
		Text = tostring(opts.Title or "Color"),
		TextSize = 12,
		Font = "SemiBold",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Color = "Text",
		ZIndex = 113,
		Parent = header,
	})

	local rainbowBtn = Create.New("TextButton", {
		Name = "RainbowToggle",
		Size = UDim2.fromOffset(72, 22),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Corner = 999,
		Padding = { 0, 7, 0, 7 },
		ZIndex = 113,
		Theme = { BackgroundColor3 = "Field" },
		Parent = header,
	})
	local rainbowStroke = Create.Stroke(rainbowBtn, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})
	local rainbowIcon = Icons.Create("sparkles", {
		Size = UDim2.fromOffset(11, 11),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = "SubText",
		ZIndex = 114,
		Parent = rainbowBtn,
	})
	local rainbowLbl = Create.Text({
		Size = UDim2.new(1, -14, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		Text = "Rainbow",
		TextSize = 10,
		Font = "SemiBold",
		TextXAlignment = Enum.TextXAlignment.Center,
		Color = "SubText",
		ZIndex = 114,
		Parent = rainbowBtn,
	})

	-- 2. 2D Saturation-Value Canvas + Vertical Hue Bar
	local canvasRow = Create.New("Frame", {
		Name = "CanvasRow",
		Size = UDim2.new(1, 0, 0, 144),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		ZIndex = 112,
		Parent = body,
	})

	local svBox = Create.New("Frame", {
		Name = "SVCanvas",
		Size = UDim2.new(1, -26, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		Corner = 8,
		ZIndex = 112,
		Parent = canvasRow,
	})
	Create.Stroke(svBox, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })

	local svHueGrad = Instance.new("UIGradient")
	svHueGrad.Rotation = 0
	svHueGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
	svHueGrad.Parent = svBox

	local svDark = Create.New("Frame", {
		Name = "ValueOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 113,
		Parent = svBox,
	})
	local svDarkGrad = Instance.new("UIGradient")
	svDarkGrad.Rotation = 90
	svDarkGrad.Transparency = NumberSequence.new(1, 0)
	svDarkGrad.Parent = svDark

	local svCursorRing = Create.New("Frame", {
		Name = "CursorRing",
		Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(sat, 1 - val),
		BackgroundTransparency = 1,
		Corner = 999,
		ZIndex = 115,
		Parent = svBox,
	})
	Create.Stroke(svCursorRing, { Color = Color3.new(0, 0, 0), Transparency = 0.45, Thickness = 1 })

	local svCursor = Create.New("Frame", {
		Name = "Cursor",
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = currentColor,
		Corner = 999,
		ZIndex = 116,
		Parent = svCursorRing,
	})
	Create.Stroke(svCursor, { Color = Color3.new(1, 1, 1), Transparency = 0, Thickness = 2 })

	local hueBar = Create.New("Frame", {
		Name = "HueBar",
		Size = UDim2.fromOffset(18, 144),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Corner = 6,
		ZIndex = 112,
		Parent = canvasRow,
	})
	Create.Stroke(hueBar, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })

	local hueGrad = Instance.new("UIGradient")
	hueGrad.Rotation = 90
	hueGrad.Color = HUE_SEQUENCE
	hueGrad.Parent = hueBar

	local hueThumb = Create.New("Frame", {
		Name = "HueThumb",
		Size = UDim2.new(1, 4, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, hue),
		Corner = 999,
		ZIndex = 114,
		Theme = { BackgroundColor3 = "Knob" },
		Parent = hueBar,
	})
	Create.Stroke(hueThumb, { Color = Color3.new(0, 0, 0), Transparency = 0.45, Thickness = 1 })

	-- 3. Optional Alpha / Transparency Slider
	local alphaFill
	local alphaThumb
	local alphaLabel
	local alphaBar
	if hasAlpha then
		local alphaRow = Create.New("Frame", {
			Name = "AlphaRow",
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			ZIndex = 112,
			Parent = body,
		})

		alphaBar = Create.New("Frame", {
			Name = "AlphaBar",
			Size = UDim2.new(1, -40, 0, 14),
			Position = UDim2.fromScale(0, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			Corner = 6,
			ZIndex = 112,
			Theme = { BackgroundColor3 = "Field" },
			Parent = alphaRow,
		})
		Create.Stroke(alphaBar, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })

		alphaFill = Create.New("Frame", {
			Name = "AlphaFill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = currentColor,
			Corner = 6,
			ZIndex = 113,
			Parent = alphaBar,
		})
		local alphaGrad = Instance.new("UIGradient")
		alphaGrad.Rotation = 0
		alphaGrad.Transparency = NumberSequence.new(0, 1)
		alphaGrad.Parent = alphaFill

		alphaThumb = Create.New("Frame", {
			Name = "AlphaThumb",
			Size = UDim2.fromOffset(7, 18),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(currentAlpha, 0.5),
			Corner = 999,
			ZIndex = 114,
			Theme = { BackgroundColor3 = "Knob" },
			Parent = alphaBar,
		})
		Create.Stroke(alphaThumb, { Color = Color3.new(0, 0, 0), Transparency = 0.45, Thickness = 1 })

		alphaLabel = Create.Text({
			Name = "AlphaPercent",
			Size = UDim2.fromOffset(34, 18),
			Position = UDim2.new(1, 0, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Text = string.format("%d%%", math.floor(currentAlpha * 100 + 0.5)),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			Color = "SubText",
			ZIndex = 113,
			Parent = alphaRow,
		})
		Theme.Unbind(alphaLabel, "FontFace")
		alphaLabel.FontFace = Theme.Mono("Medium")
	end

	-- 4. Live Editable #HEX & R,G,B Inputs
	local inputsRow = Create.New("Frame", {
		Name = "InputsRow",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		ZIndex = 112,
		Parent = body,
	})
	Create.List(inputsRow, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 4,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local function makeInputField(name, width, layoutOrder, initialText)
		local boxWrap = Create.New("Frame", {
			Name = name .. "Wrap",
			Size = UDim2.fromOffset(width, 26),
			LayoutOrder = layoutOrder,
			Corner = 6,
			Padding = { 0, 5, 0, 5 },
			ZIndex = 112,
			Theme = { BackgroundColor3 = "Field" },
			Parent = inputsRow,
		})
		local stroke = Create.Stroke(boxWrap, {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
		})
		local box = Create.Text({
			Class = "TextBox",
			Name = name,
			Size = UDim2.fromScale(1, 1),
			Text = initialText,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			Color = "Text",
			ZIndex = 113,
			Parent = boxWrap,
		})
		Theme.Unbind(box, "FontFace")
		box.FontFace = Theme.Mono("Medium")
		box.Focused:Connect(function()
			Theme.Bind(stroke, { Color = "Accent", Transparency = function() return 0.35 end })
		end)
		box.FocusLost:Connect(function()
			Theme.Bind(stroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
		end)
		return box
	end

	local hexInput = makeInputField("Hex", 78, 1, "#" .. Util.ToHex(currentColor))
	local rInput = makeInputField("R", 40, 2, tostring(math.floor(currentColor.R * 255 + 0.5)))
	local gInput = makeInputField("G", 40, 3, tostring(math.floor(currentColor.G * 255 + 0.5)))
	local bInput = makeInputField("B", 40, 4, tostring(math.floor(currentColor.B * 255 + 0.5)))

	-- 5. Quick Preset Swatches (6 per row)
	local presetsList = type(opts.Presets) == "table" and #opts.Presets > 0 and opts.Presets or DEFAULT_PRESETS
	local presetWrap = Create.New("Frame", {
		Name = "Presets",
		Size = UDim2.new(1, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 2, 2, 2, 2 },
		LayoutOrder = 5,
		ZIndex = 112,
		Parent = body,
	})
	Create.List(presetWrap, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		Wraps = true,
	})

	local function syncVisuals()
		currentColor = Color3.fromHSV(hue, sat, val)
		self.Value = currentColor
		self.Alpha = currentAlpha

		local hexStr = "#" .. Util.ToHex(currentColor)
		pillHex.Text = hexStr
		pillSwatch.BackgroundColor3 = currentColor
		pillSwatch.BackgroundTransparency = hasAlpha and currentAlpha or 0
		headerSwatch.BackgroundColor3 = currentColor

		svHueGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
		svCursorRing.Position = UDim2.fromScale(sat, 1 - val)
		svCursor.BackgroundColor3 = currentColor
		hueThumb.Position = UDim2.fromScale(0.5, hue)

		if hasAlpha and alphaFill and alphaThumb and alphaLabel then
			alphaFill.BackgroundColor3 = currentColor
			alphaThumb.Position = UDim2.fromScale(currentAlpha, 0.5)
			alphaLabel.Text = string.format("%d%%", math.floor(currentAlpha * 100 + 0.5))
		end

		if not hexInput:IsFocused() then
			hexInput.Text = hexStr
		end
		if not rInput:IsFocused() then
			rInput.Text = tostring(math.floor(currentColor.R * 255 + 0.5))
		end
		if not gInput:IsFocused() then
			gInput.Text = tostring(math.floor(currentColor.G * 255 + 0.5))
		end
		if not bInput:IsFocused() then
			bInput.Text = tostring(math.floor(currentColor.B * 255 + 0.5))
		end
	end

	local function fireChanged(silent)
		syncVisuals()
		if not silent then
			local alphaArg = hasAlpha and currentAlpha or nil
			if opts.Callback then
				Util.Spawn(opts.Callback, currentColor, alphaArg)
			end
			self.Changed:Fire(currentColor, alphaArg)
		end
	end

	local function updateRainbowVisuals()
		Theme.Bind(rainbowBtn, {
			BackgroundColor3 = rainbowEnabled and "Accent" or "Field",
			BackgroundTransparency = rainbowEnabled and function() return 0.78 end or function() return 0 end,
		})
		Theme.Bind(rainbowStroke, {
			Color = rainbowEnabled and "Accent" or "Stroke",
			Transparency = rainbowEnabled and function() return 0.35 end or "StrokeTransparency",
		})
		Theme.Bind(rainbowLbl, { TextColor3 = rainbowEnabled and "Text" or "SubText" })
		if rainbowIcon then
			Icons.SetColor(rainbowIcon, rainbowEnabled and "Accent" or "SubText")
		end
	end

	local function stopRainbowLoop()
		if rainbowConn then
			rainbowConn:Disconnect()
			rainbowConn = nil
		end
	end

	local function startRainbowLoop()
		stopRainbowLoop()
		rainbowConn = Services.RunService.RenderStepped:Connect(function(dt)
			hue = (hue + dt * 0.18) % 1
			fireChanged(false)
		end)
	end

	function self:SetRainbow(enabled)
		local state = enabled == true
		if rainbowEnabled == state then
			updateRainbowVisuals()
			if state and not rainbowConn then
				startRainbowLoop()
			end
			return
		end
		rainbowEnabled = state
		updateRainbowVisuals()
		if rainbowEnabled then
			startRainbowLoop()
		else
			stopRainbowLoop()
		end
	end

	-- Preset swatch buttons
	for idx, entry in ipairs(presetsList) do
		local col = parseColorInput(entry, Theme.Current.Accent)
		local sw = Create.New("TextButton", {
			Name = "Preset_" .. idx,
			Size = UDim2.fromOffset(28, 20),
			LayoutOrder = idx,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 0,
			BackgroundColor3 = col,
			Corner = 5,
			ZIndex = 113,
			Parent = presetWrap,
		})
		Create.Stroke(sw, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })
		sw.Activated:Connect(function()
			if isDisabledOrLocked(self) then
				return
			end
			self:SetRainbow(false)
			self:Set(col, currentAlpha, false)
		end)
	end

	rainbowBtn.Activated:Connect(function()
		if isDisabledOrLocked(self) then
			return
		end
		Transition.Ripple(rainbowBtn, nil, "Accent")
		self:SetRainbow(not rainbowEnabled)
	end)

	-- Smooth pointer/touch drag helper for SV, Hue, and Alpha
	local activeDrag = nil -- "SV" | "Hue" | "Alpha"
	local function applyDragAt(pos)
		if activeDrag == "SV" then
			local aPos, aSize = svBox.AbsolutePosition, svBox.AbsoluteSize
			if aSize.X > 0 and aSize.Y > 0 then
				sat = Util.Clamp((pos.X - aPos.X) / aSize.X, 0, 1)
				val = 1 - Util.Clamp((pos.Y - aPos.Y) / aSize.Y, 0, 1)
				fireChanged(false)
			end
		elseif activeDrag == "Hue" then
			local aPos, aSize = hueBar.AbsolutePosition, hueBar.AbsoluteSize
			if aSize.Y > 0 then
				hue = Util.Clamp((pos.Y - aPos.Y) / aSize.Y, 0, 1)
				fireChanged(false)
			end
		elseif activeDrag == "Alpha" and alphaBar then
			local aPos, aSize = alphaBar.AbsolutePosition, alphaBar.AbsoluteSize
			if aSize.X > 0 then
				currentAlpha = Util.Clamp((pos.X - aPos.X) / aSize.X, 0, 1)
				fireChanged(false)
			end
		end
	end

	local dragMoveConn = Services.UserInputService.InputChanged:Connect(function(input)
		if activeDrag and Util.IsMove(input) then
			applyDragAt(Util.MousePosition())
		end
	end)
	local dragEndConn = Services.UserInputService.InputEnded:Connect(function(input)
		if activeDrag and Util.IsPointer(input) then
			activeDrag = nil
		end
	end)

	local function bindSliderDrag(target, kind, disableRainbow)
		target.InputBegan:Connect(function(input)
			if isDisabledOrLocked(self) then
				return
			end
			if Util.IsPointer(input) then
				if disableRainbow then
					self:SetRainbow(false)
				end
				activeDrag = kind
				applyDragAt(Util.MousePosition())
			end
		end)
	end

	bindSliderDrag(svBox, "SV", false)
	bindSliderDrag(hueBar, "Hue", true)
	if alphaBar then
		bindSliderDrag(alphaBar, "Alpha", false)
	end

	-- HEX & RGB input handlers
	hexInput.FocusLost:Connect(function()
		local parsed = Util.FromHex(hexInput.Text)
		if parsed then
			self:SetRainbow(false)
			self:Set(parsed, currentAlpha, false)
		else
			hexInput.Text = "#" .. Util.ToHex(currentColor)
		end
	end)

	local function commitRGB()
		local r = tonumber(rInput.Text)
		local g = tonumber(gInput.Text)
		local b = tonumber(bInput.Text)
		if r and g and b then
			local col = Color3.fromRGB(
				Util.Clamp(math.floor(r + 0.5), 0, 255),
				Util.Clamp(math.floor(g + 0.5), 0, 255),
				Util.Clamp(math.floor(b + 0.5), 0, 255)
			)
			self:SetRainbow(false)
			self:Set(col, currentAlpha, false)
		else
			syncVisuals()
		end
	end
	rInput.FocusLost:Connect(commitRGB)
	gInput.FocusLost:Connect(commitRGB)
	bInput.FocusLost:Connect(commitRGB)

	-- Popup open/close handling
	local fallbackOutsideConn
	local function handleClosedState()
		if not isOpen then
			return
		end
		isOpen = false
		activeDrag = nil
		openGen += 1
		local myGen = openGen
		if fallbackOutsideConn then
			fallbackOutsideConn:Disconnect()
			fallbackOutsideConn = nil
		end
		Transition.Unmount(popover, 0.94, function()
			if openGen == myGen and not isOpen then
				popover.Visible = false
			end
		end)
	end

	function self:Open()
		if isOpen or isDisabledOrLocked(self) then
			return
		end
		isOpen = true
		openGen += 1
		popover.Visible = true
		if ctx.OpenPopup then
			if ctx.PopupLayer then
				popover.Parent = ctx.PopupLayer
			end
			ctx.OpenPopup(popupId, popover, swatchPill, handleClosedState)
		else
			local layer = ctx.PopupLayer or row.Frame:FindFirstAncestorOfClass("ScreenGui")
			if layer then
				popover.Parent = layer
				local view = layer.AbsoluteSize
				local aPos, aSize = swatchPill.AbsolutePosition, swatchPill.AbsoluteSize
				local popH = math.max(popover.AbsoluteSize.Y, hasAlpha and 272 or 244)
				local px = Util.Clamp(aPos.X + aSize.X - 236, 8, math.max(8, view.X - 244))
				local py = aPos.Y + aSize.Y + 6
				if py + popH > view.Y - 8 then
					local above = aPos.Y - popH - 6
					if above >= 8 then
						py = above
					end
				end
				popover.Position = UDim2.fromOffset(px, py)
				fallbackOutsideConn = Services.UserInputService.InputBegan:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Escape then
						self:Close()
					elseif Util.IsPointer(input) then
						local pos = Util.MousePosition()
						local pPos, pSize = popover.AbsolutePosition, popover.AbsoluteSize
						local tPos, tSize = swatchPill.AbsolutePosition, swatchPill.AbsoluteSize
						local inPop = pos.X >= pPos.X and pos.X <= pPos.X + pSize.X and pos.Y >= pPos.Y and pos.Y <= pPos.Y + pSize.Y
						local inTrig = pos.X >= tPos.X and pos.X <= tPos.X + tSize.X and pos.Y >= tPos.Y and pos.Y <= tPos.Y + tSize.Y
						if not inPop and not inTrig then
							self:Close()
						end
					end
				end)
			end
		end
		Transition.Mount(popover, 0.94)
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

	swatchPill.Activated:Connect(function()
		if isDisabledOrLocked(self) then
			return
		end
		Transition.Ripple(swatchPill, nil, "Accent")
		if isOpen then
			self:Close()
		else
			self:Open()
		end
	end)

	function self:Set(color, alphaOrSilent, silentArg)
		local nextColor = color
		local nextAlpha = currentAlpha
		local silent = false

		if type(color) == "table" then
			nextColor = parseColorInput(color, currentColor)
			if color.Alpha ~= nil then
				nextAlpha = Util.Clamp(tonumber(color.Alpha) or currentAlpha, 0, 1)
			elseif color.Transparency ~= nil then
				nextAlpha = Util.Clamp(tonumber(color.Transparency) or currentAlpha, 0, 1)
			end
		else
			nextColor = parseColorInput(color, currentColor)
		end

		if type(alphaOrSilent) == "boolean" then
			silent = alphaOrSilent
		elseif type(alphaOrSilent) == "number" then
			nextAlpha = Util.Clamp(alphaOrSilent, 0, 1)
			silent = silentArg == true
		elseif silentArg ~= nil then
			silent = silentArg == true
		end

		hue, sat, val = Color3.toHSV(nextColor)
		currentAlpha = nextAlpha
		fireChanged(silent == true)
	end

	function self:Get()
		return currentColor, currentAlpha
	end

	local baseSetTitle = self.SetTitle
	function self:SetTitle(text)
		local str = tostring(text or "")
		headerTitle.Text = str
		if baseSetTitle then
			pcall(baseSetTitle, self, text)
		end
		if row.TitleLabel then
			row.TitleLabel.Text = str
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
		stopRainbowLoop()
		if dragMoveConn then
			dragMoveConn:Disconnect()
		end
		if dragEndConn then
			dragEndConn:Disconnect()
		end
		if fallbackOutsideConn then
			fallbackOutsideConn:Disconnect()
			fallbackOutsideConn = nil
		end
		popover:Destroy()
	end)

	syncVisuals()
	updateRainbowVisuals()
	if rainbowEnabled then
		startRainbowLoop()
	end

	return self
end

return ColorPicker
