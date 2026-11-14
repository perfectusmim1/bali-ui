--[[
	Bali UI · Elements/Slider
	Interactive Slider (with editable numeric pill), dual-thumb RangeSlider, and Stepper.
]]

local Services = require("Core/Services")
local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Base = require("Elements/Base")

local SliderModule = {}

local function resolveNumericSpec(opts)
	local step = opts.Step or opts.Increment
	if not step or step <= 0 then
		if opts.Rounding ~= nil and opts.Rounding > 0 then
			step = 10 ^ (-opts.Rounding)
		else
			step = 1
		end
	end
	local decimals = opts.Rounding ~= nil and math.max(0, math.floor(opts.Rounding)) or Util.Decimals(step)
	local minVal = tonumber(opts.Min) or 0
	local maxVal = tonumber(opts.Max) or 100
	if maxVal <= minVal then
		maxVal = minVal + step
	end
	return minVal, maxVal, step, decimals
end

local function createThumb(track, zBase)
	local thumb = Create.New("Frame", {
		Name = "Thumb",
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Theme = { BackgroundColor3 = "Knob" },
		Corner = UDim.new(1, 0),
		ZIndex = zBase or 4,
		Parent = track,
	})

	local stroke = Create.Stroke(thumb, {
		Theme = { Color = "Accent" },
		Transparency = 0.25,
		Thickness = 1.5,
	})

	local glowAsset = Assets.Get("Glow")
	local glow
	if glowAsset then
		glow = Create.New("ImageLabel", {
			Name = "Glow",
			Size = UDim2.fromOffset(28, 28),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = glowAsset,
			Theme = { ImageColor3 = "Accent" },
			ImageTransparency = 0.72,
			ZIndex = (zBase or 4) - 1,
			Parent = thumb,
		})
	else
		glow = Create.New("Frame", {
			Name = "Glow",
			Size = UDim2.fromOffset(22, 22),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Corner = UDim.new(1, 0),
			Theme = { BackgroundColor3 = "Accent" },
			BackgroundTransparency = 0.78,
			ZIndex = (zBase or 4) - 1,
			Parent = thumb,
		})
	end

	local function setActive(active)
		Tween.Play(thumb, { Size = active and UDim2.fromOffset(17, 17) or UDim2.fromOffset(14, 14) }, Tween.Instant, Enum.EasingStyle.Quad)
		if glow:IsA("ImageLabel") then
			Tween.Play(glow, { ImageTransparency = active and 0.42 or 0.72 }, Tween.Instant, Enum.EasingStyle.Quad)
		else
			Tween.Play(glow, { BackgroundTransparency = active and 0.52 or 0.78 }, Tween.Instant, Enum.EasingStyle.Quad)
		end
	end

	return thumb, nil, stroke, setActive
end

-- ─── Slider ──────────────────────────────────────────────────────────────────

local Slider = {}
function Slider.new(parent, opts, ctx)
	opts = Util.Options(opts, { Min = 0, Max = 100 }, "Title")
	local element = Base.New("Slider", parent, opts, ctx)

	local minVal, maxVal, step, decimals = resolveNumericSpec(opts)
	local prefix = tostring(opts.Prefix or "")
	local suffix = tostring(opts.Suffix or "")

	local function snap(v)
		return Util.Snap(tonumber(v) or minVal, minVal, maxVal, step)
	end

	local function formatVal(v)
		return prefix .. Util.FormatNumber(v, decimals) .. suffix
	end

	local currentVal = snap(opts.Default ~= nil and opts.Default or minVal)
	element.Value = currentVal

	local card = Base.Card(parent, { Padding = 0 })

	local body = Create.New("Frame", {
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

	local header = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = body,
	})

	Create.List(header, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 10,
	})

	local left = Create.New("Frame", {
		Name = "Left",
		Size = UDim2.new(1, -64, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = header,
	})

	Create.List(left, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 8,
	})

	local iconWidth = 0
	if opts.Icon and opts.Icon ~= "" and opts.Icon ~= false then
		Icons.Create(opts.Icon, {
			Size = UDim2.fromOffset(17, 17),
			Color = opts.IconColor or "SubText",
			LayoutOrder = 1,
			Parent = left,
		})
		iconWidth = 17
	end

	local textCol = Create.New("Frame", {
		Name = "TextColumn",
		Size = UDim2.new(1, iconWidth > 0 and -(iconWidth + 8) or 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = left,
	})

	Create.List(textCol, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 2,
	})

	local titleText = tostring(opts.Title or "Slider")
	local descText = tostring(opts.Description or opts.Desc or "")

	local titleLabel = Create.Text({
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

	local descLabel = Create.Text({
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

	local pill = Create.New("Frame", {
		Name = "ValuePill",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Theme = { BackgroundColor3 = "Field" },
		Corner = 6,
		Padding = { 0, 8, 0, 8 },
		LayoutOrder = 2,
		Parent = header,
	})

	local pillConstraint = Instance.new("UISizeConstraint")
	pillConstraint.MinSize = Vector2.new(44, 24)
	pillConstraint.Parent = pill

	local pillStroke = Create.Stroke(pill, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
		Thickness = 1,
	})

	local readoutBox = Create.New("TextBox", {
		Name = "Readout",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = formatVal(currentVal),
		TextSize = 12,
		Font = "SemiBold",
		Theme = { TextColor3 = "Text" },
		TextXAlignment = Enum.TextXAlignment.Center,
		ClearTextOnFocus = false,
		ZIndex = 4,
		Parent = pill,
	})

	local function syncHeaderInset()
		local pw = math.max(44, math.ceil(pill.AbsoluteSize.X))
		left.Size = UDim2.new(1, -(pw + 10), 0, 0)
	end
	element.Maid:Give(pill:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncHeaderInset))
	task.defer(syncHeaderInset)

	-- Track & Thumb
	local trackHit = Create.New("Frame", {
		Name = "TrackHit",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Active = true,
		LayoutOrder = 2,
		Parent = body,
	})

	local track = Create.New("Frame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 0, 6),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Theme = { BackgroundColor3 = "ToggleOff" },
		Corner = UDim.new(1, 0),
		Parent = trackHit,
	})

	local fill = Create.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Corner = UDim.new(1, 0),
		ZIndex = 2,
		Parent = track,
	})

	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = Theme.AccentSequence()
	fillGrad.Parent = fill

	local thumb, _, _, setThumbActive = createThumb(track, 4)

	local function updateVisual(animate)
		local alpha = Util.Clamp((currentVal - minVal) / (maxVal - minVal), 0, 1)
		if not readoutBox:IsFocused() then
			readoutBox.Text = formatVal(currentVal)
		end
		if animate then
			Tween.Play(fill, { Size = UDim2.fromScale(alpha, 1) }, Tween.Instant, Enum.EasingStyle.Quad)
			Tween.Play(thumb, { Position = UDim2.fromScale(alpha, 0.5) }, Tween.Instant, Enum.EasingStyle.Quad)
		else
			fill.Size = UDim2.fromScale(alpha, 1)
			thumb.Position = UDim2.fromScale(alpha, 0.5)
		end
	end

	updateVisual(false)
	element.Maid:Give(Theme.Changed:Connect(function(t)
		if not element._destroyed then
			fillGrad.Color = Theme.AccentSequence(t)
		end
	end))

	function element:Set(val, silent)
		local nextVal = snap(val)
		local changed = (nextVal ~= currentVal)
		currentVal = nextVal
		self.Value = currentVal
		updateVisual(true)
		if changed and not silent then
			self.Changed:Fire(currentVal)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, currentVal)
			end
		end
	end

	function element:Get()
		return currentVal
	end

	function element:SetMin(newMin)
		minVal = tonumber(newMin) or minVal
		if maxVal <= minVal then
			maxVal = minVal + step
		end
		self:Set(currentVal, true)
	end

	function element:SetMax(newMax)
		maxVal = tonumber(newMax) or maxVal
		if maxVal <= minVal then
			maxVal = minVal + step
		end
		self:Set(currentVal, true)
	end

	-- Editable readout pill
	element.Maid:Give(readoutBox.Focused:Connect(function()
		if element.Disabled or element.Locked then
			readoutBox:ReleaseFocus()
			return
		end
		readoutBox.Text = tostring(currentVal)
		Tween.Play(pillStroke, {
			Color = Theme.Current.Accent,
			Transparency = 0.18,
		}, Tween.Fast, Enum.EasingStyle.Quad)
	end))

	element.Maid:Give(readoutBox.FocusLost:Connect(function()
		Tween.Play(pillStroke, {
			Color = Theme.Current.Stroke,
			Transparency = Theme.Current.StrokeTransparency,
		}, Tween.Fast, Enum.EasingStyle.Quad)
		local raw = Util.Trim(readoutBox.Text)
		raw = raw:gsub(",", "")
		local parsed = tonumber(raw)
		if not parsed then
			local extracted = raw:match("[%-]?%d+%.?%d*")
			parsed = extracted and tonumber(extracted) or nil
		end
		if parsed then
			element:Set(parsed, false)
		end
		readoutBox.Text = formatVal(currentVal)
	end))

	-- Dragging (mouse & touch)
	local dragging = false
	local hovered = false
	local activeInput = nil

	local function applyPointerX(posX)
		local width = math.max(track.AbsoluteSize.X, 1)
		local alpha = Util.Clamp((posX - track.AbsolutePosition.X) / width, 0, 1)
		element:Set(minVal + (maxVal - minVal) * alpha, false)
	end

	element.Maid:Give(trackHit.MouseEnter:Connect(function()
		if element.Disabled or element.Locked or Util.IsTouchDevice() or Transition.IsOverlayBlocking(trackHit) then
			return
		end
		hovered = true
		setThumbActive(true)
	end))

	element.Maid:Give(trackHit.MouseLeave:Connect(function()
		hovered = false
		if not dragging then
			setThumbActive(false)
		end
	end))

	element.Maid:Give(trackHit.InputBegan:Connect(function(input)
		if element.Disabled or element.Locked or Transition.IsOverlayBlocking(trackHit) then
			return
		end
		if Util.IsPointer(input) then
			dragging = true
			activeInput = input
			setThumbActive(true)
			applyPointerX(input.Position.X)
		end
	end))

	element.Maid:Give(Services.UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if Transition.IsOverlayBlocking(trackHit) then
			dragging = false
			activeInput = nil
			setThumbActive(false)
			return
		end
		local isTouch = activeInput and activeInput.UserInputType == Enum.UserInputType.Touch
		if (isTouch and input == activeInput) or (not isTouch and input.UserInputType == Enum.UserInputType.MouseMovement) then
			applyPointerX(input.Position.X)
		end
	end))

	element.Maid:Give(Services.UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		local isTouch = activeInput and activeInput.UserInputType == Enum.UserInputType.Touch
		if (isTouch and input == activeInput) or (not isTouch and input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			activeInput = nil
			setThumbActive(hovered)
		end
	end))

	element._onDisabled = function(disabled)
		readoutBox.TextEditable = not disabled
		trackHit.Active = not disabled
		if disabled then
			dragging = false
			activeInput = nil
			setThumbActive(false)
		end
	end

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
	return element
end

-- ─── RangeSlider ─────────────────────────────────────────────────────────────

local RangeSlider = {}
function RangeSlider.new(parent, opts, ctx)
	opts = Util.Options(opts, { Min = 0, Max = 100 }, "Title")
	local element = Base.New("RangeSlider", parent, opts, ctx)

	local minVal, maxVal, step, decimals = resolveNumericSpec(opts)
	local prefix = tostring(opts.Prefix or "")
	local suffix = tostring(opts.Suffix or "")
	local minGap = math.max(tonumber(opts.MinGap) or 0, 0)

	local function snap(v)
		return Util.Snap(tonumber(v) or minVal, minVal, maxVal, step)
	end

	local function formatRange(lo, hi)
		local a = prefix .. Util.FormatNumber(lo, decimals) .. suffix
		local b = prefix .. Util.FormatNumber(hi, decimals) .. suffix
		return a .. " – " .. b
	end

	local defLow, defHigh = minVal, maxVal
	if type(opts.Default) == "table" then
		defLow = opts.Default.Min ~= nil and opts.Default.Min or (opts.Default[1] ~= nil and opts.Default[1] or minVal)
		defHigh = opts.Default.Max ~= nil and opts.Default.Max or (opts.Default[2] ~= nil and opts.Default[2] or maxVal)
	end

	local lowVal = snap(defLow)
	local highVal = snap(defHigh)
	if highVal < lowVal then
		lowVal, highVal = highVal, lowVal
	end
	if highVal - lowVal < minGap then
		highVal = snap(math.min(maxVal, lowVal + minGap))
		if highVal - lowVal < minGap then
			lowVal = snap(math.max(minVal, highVal - minGap))
		end
	end
	element.Value = { Min = lowVal, Max = highVal }

	local card = Base.Card(parent, { Padding = 0 })

	local body = Create.New("Frame", {
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

	local header = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = body,
	})

	Create.List(header, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 10,
	})

	local left = Create.New("Frame", {
		Name = "Left",
		Size = UDim2.new(1, -90, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = header,
	})

	Create.List(left, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 2,
	})

	local titleText = tostring(opts.Title or "Range")
	local descText = tostring(opts.Description or opts.Desc or "")

	local titleLabel = Create.Text({
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
		Parent = left,
	})

	local descLabel = Create.Text({
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
		Parent = left,
	})

	local pill = Create.New("Frame", {
		Name = "ValuePill",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Theme = { BackgroundColor3 = "Field" },
		Corner = 6,
		Padding = { 0, 8, 0, 8 },
		Stroke = {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
			Thickness = 1,
		},
		LayoutOrder = 2,
		Parent = header,
	})

	local readoutLabel = Create.Text({
		Name = "Readout",
		Text = formatRange(lowVal, highVal),
		Font = "SemiBold",
		TextSize = 12,
		Color = "Text",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = pill,
	})

	local function syncHeaderInset()
		local pw = math.ceil(pill.AbsoluteSize.X)
		left.Size = UDim2.new(1, -(pw + 10), 0, 0)
	end
	element.Maid:Give(pill:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncHeaderInset))
	task.defer(syncHeaderInset)

	local trackHit = Create.New("Frame", {
		Name = "TrackHit",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Active = true,
		LayoutOrder = 2,
		Parent = body,
	})

	local track = Create.New("Frame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 0, 6),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Theme = { BackgroundColor3 = "ToggleOff" },
		Corner = UDim.new(1, 0),
		Parent = trackHit,
	})

	local fill = Create.New("Frame", {
		Name = "Fill",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Corner = UDim.new(1, 0),
		ZIndex = 2,
		Parent = track,
	})

	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = Theme.AccentSequence()
	fillGrad.Parent = fill

	local thumbLow, _, _, setLowActive = createThumb(track, 4)
	local thumbHigh, _, _, setHighActive = createThumb(track, 5)

	local function updateVisual(animate)
		local span = maxVal - minVal
		local aLow = Util.Clamp((lowVal - minVal) / span, 0, 1)
		local aHigh = Util.Clamp((highVal - minVal) / span, 0, 1)
		readoutLabel.Text = formatRange(lowVal, highVal)
		local fillPos = UDim2.fromScale(aLow, 0)
		local fillSize = UDim2.fromScale(math.max(0, aHigh - aLow), 1)
		local posLow = UDim2.fromScale(aLow, 0.5)
		local posHigh = UDim2.fromScale(aHigh, 0.5)

		if animate then
			Tween.Play(fill, { Position = fillPos, Size = fillSize }, Tween.Instant, Enum.EasingStyle.Quad)
			Tween.Play(thumbLow, { Position = posLow }, Tween.Instant, Enum.EasingStyle.Quad)
			Tween.Play(thumbHigh, { Position = posHigh }, Tween.Instant, Enum.EasingStyle.Quad)
		else
			fill.Position = fillPos
			fill.Size = fillSize
			thumbLow.Position = posLow
			thumbHigh.Position = posHigh
		end
	end

	updateVisual(false)
	element.Maid:Give(Theme.Changed:Connect(function(t)
		if not element._destroyed then
			fillGrad.Color = Theme.AccentSequence(t)
		end
	end))

	function element:Set(valOrMin, maxOrSilent, silentArg)
		local rawLow, rawHigh, silent
		if type(valOrMin) == "table" then
			rawLow = valOrMin.Min ~= nil and valOrMin.Min or (valOrMin[1] ~= nil and valOrMin[1] or lowVal)
			rawHigh = valOrMin.Max ~= nil and valOrMin.Max or (valOrMin[2] ~= nil and valOrMin[2] or highVal)
			silent = (maxOrSilent == true)
		else
			rawLow = tonumber(valOrMin) or lowVal
			rawHigh = tonumber(maxOrSilent) or highVal
			silent = (silentArg == true)
		end

		local nextLow = snap(rawLow)
		local nextHigh = snap(rawHigh)
		if nextHigh < nextLow then
			nextLow, nextHigh = nextHigh, nextLow
		end
		if nextHigh - nextLow < minGap then
			nextHigh = snap(math.min(maxVal, nextLow + minGap))
			if nextHigh - nextLow < minGap then
				nextLow = snap(math.max(minVal, nextHigh - minGap))
			end
		end

		local changed = (nextLow ~= lowVal or nextHigh ~= highVal)
		lowVal = nextLow
		highVal = nextHigh
		self.Value = { Min = lowVal, Max = highVal }
		updateVisual(true)

		if changed and not silent then
			local payload = { Min = lowVal, Max = highVal }
			self.Changed:Fire(payload)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, payload)
			end
		end
	end

	function element:Get()
		return { Min = lowVal, Max = highVal }
	end

	local activeHandle = nil -- "Min" | "Max" | nil
	local activeInput = nil

	local function applyPointerX(posX)
		local width = math.max(track.AbsoluteSize.X, 1)
		local alpha = Util.Clamp((posX - track.AbsolutePosition.X) / width, 0, 1)
		local targetVal = snap(minVal + (maxVal - minVal) * alpha)
		if activeHandle == "Min" then
			local capped = snap(math.min(targetVal, highVal - minGap))
			element:Set(capped, highVal, false)
		elseif activeHandle == "Max" then
			local floored = snap(math.max(targetVal, lowVal + minGap))
			element:Set(lowVal, floored, false)
		end
	end

	element.Maid:Give(trackHit.InputBegan:Connect(function(input)
		if element.Disabled or element.Locked or Transition.IsOverlayBlocking(trackHit) then
			return
		end
		if Util.IsPointer(input) then
			local width = math.max(track.AbsoluteSize.X, 1)
			local pointerAlpha = Util.Clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
			local span = maxVal - minVal
			local aLow = (lowVal - minVal) / span
			local aHigh = (highVal - minVal) / span
			local dLow = math.abs(pointerAlpha - aLow)
			local dHigh = math.abs(pointerAlpha - aHigh)

			if dLow < dHigh or (math.abs(dLow - dHigh) < 1e-4 and pointerAlpha < aLow) then
				activeHandle = "Min"
				thumbLow.ZIndex = 6
				thumbHigh.ZIndex = 4
				setLowActive(true)
			else
				activeHandle = "Max"
				thumbHigh.ZIndex = 6
				thumbLow.ZIndex = 4
				setHighActive(true)
			end
			activeInput = input
			applyPointerX(input.Position.X)
		end
	end))

	element.Maid:Give(Services.UserInputService.InputChanged:Connect(function(input)
		if not activeHandle then
			return
		end
		if Transition.IsOverlayBlocking(trackHit) then
			setLowActive(false)
			setHighActive(false)
			activeHandle = nil
			activeInput = nil
			return
		end
		local isTouch = activeInput and activeInput.UserInputType == Enum.UserInputType.Touch
		if (isTouch and input == activeInput) or (not isTouch and input.UserInputType == Enum.UserInputType.MouseMovement) then
			applyPointerX(input.Position.X)
		end
	end))

	element.Maid:Give(Services.UserInputService.InputEnded:Connect(function(input)
		if not activeHandle then
			return
		end
		local isTouch = activeInput and activeInput.UserInputType == Enum.UserInputType.Touch
		if (isTouch and input == activeInput) or (not isTouch and input.UserInputType == Enum.UserInputType.MouseButton1) then
			setLowActive(false)
			setHighActive(false)
			activeHandle = nil
			activeInput = nil
		end
	end))

	element._onDisabled = function(disabled)
		trackHit.Active = not disabled
		if disabled then
			activeHandle = nil
			activeInput = nil
			setLowActive(false)
			setHighActive(false)
		end
	end

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
	return element
end

-- ─── Stepper ─────────────────────────────────────────────────────────────────

local Stepper = {}
function Stepper.new(parent, opts, ctx)
	opts = Util.Options(opts, { Min = 0, Max = 100 }, "Title")
	local element = Base.New("Stepper", parent, opts, ctx)

	local minVal, maxVal, step, decimals = resolveNumericSpec(opts)
	local prefix = tostring(opts.Prefix or "")
	local suffix = tostring(opts.Suffix or "")

	local function snap(v)
		return Util.Snap(tonumber(v) or minVal, minVal, maxVal, step)
	end

	local function formatVal(v)
		return prefix .. Util.FormatNumber(v, decimals) .. suffix
	end

	local currentVal = snap(opts.Default ~= nil and opts.Default or minVal)
	element.Value = currentVal

	local rowOpts = table.clone(opts)
	if rowOpts.IconBadge == nil then
		rowOpts.IconBadge = false
	end

	local row = Base.Row(parent, rowOpts, 132)
	element:BindUI(row)

	local pill = Create.New("Frame", {
		Name = "StepperPill",
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		Theme = { BackgroundColor3 = "Field" },
		Corner = 8,
		Stroke = {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
			Thickness = 1,
		},
		Parent = row.Right,
	})

	Create.List(pill, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 0,
	})

	local minusBtn = Create.New("TextButton", {
		Name = "Minus",
		Size = UDim2.fromOffset(28, 30),
		Theme = { BackgroundColor3 = "Field" },
		Corner = 8,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 1,
		Parent = pill,
	})

	local minusIcon = Icons.Create("minus", {
		Size = UDim2.fromOffset(13, 13),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = "Text",
		Parent = minusBtn,
	})

	Create.New("Frame", {
		Name = "Sep1",
		Size = UDim2.fromOffset(1, 18),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		LayoutOrder = 2,
		Parent = pill,
	})

	local valueBox = Create.New("TextBox", {
		Name = "Value",
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = formatVal(currentVal),
		TextSize = 12,
		Font = "SemiBold",
		Theme = { TextColor3 = "Text" },
		TextXAlignment = Enum.TextXAlignment.Center,
		ClearTextOnFocus = false,
		Padding = { 0, 8, 0, 8 },
		LayoutOrder = 3,
		Parent = pill,
	})

	local valConstraint = Instance.new("UISizeConstraint")
	valConstraint.MinSize = Vector2.new(54, 30)
	valConstraint.Parent = valueBox

	Create.New("Frame", {
		Name = "Sep2",
		Size = UDim2.fromOffset(1, 18),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		LayoutOrder = 4,
		Parent = pill,
	})

	local plusBtn = Create.New("TextButton", {
		Name = "Plus",
		Size = UDim2.fromOffset(28, 30),
		Theme = { BackgroundColor3 = "Field" },
		Corner = 8,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 5,
		Parent = pill,
	})

	local plusIcon = Icons.Create("plus", {
		Size = UDim2.fromOffset(13, 13),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = "Text",
		Parent = plusBtn,
	})

	element.Maid:Give(Transition.Hover(minusBtn, minusBtn, "Field", "TileHover"))
	element.Maid:Give(Transition.Hover(plusBtn, plusBtn, "Field", "TileHover"))

	local function syncPillWidth()
		row:SetRightWidth(math.max(114, math.ceil(pill.AbsoluteSize.X)))
	end
	element.Maid:Give(pill:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncPillWidth))
	task.defer(syncPillWidth)

	local function refreshStepperVisual()
		if not valueBox:IsFocused() then
			valueBox.Text = formatVal(currentVal)
		end
		if minusIcon then
			local atMin = (currentVal <= minVal) or element.Disabled
			Icons.SetTransparency(minusIcon, atMin and 0.65 or 0)
		end
		if plusIcon then
			local atMax = (currentVal >= maxVal) or element.Disabled
			Icons.SetTransparency(plusIcon, atMax and 0.65 or 0)
		end
	end

	refreshStepperVisual()

	function element:Set(val, silent)
		local nextVal = snap(val)
		local changed = (nextVal ~= currentVal)
		currentVal = nextVal
		self.Value = currentVal
		refreshStepperVisual()
		if changed and not silent then
			self.Changed:Fire(currentVal)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, currentVal)
			end
		end
	end

	function element:Get()
		return currentVal
	end

	function element:Step(delta)
		self:Set(currentVal + delta * step, false)
	end

	local function bindRepeatButton(btn, delta)
		local holdToken = 0
		element.Maid:Give(btn.InputBegan:Connect(function(input)
			if element.Disabled or element.Locked or Transition.IsOverlayBlocking(btn) or not Util.IsPointer(input) then
				return
			end
			Transition.Ripple(btn, input, "Accent")
			element:Step(delta)

			holdToken += 1
			local myToken = holdToken
			task.spawn(function()
				task.wait(0.38)
				while not element._destroyed and holdToken == myToken and not element.Disabled and not element.Locked and not Transition.IsOverlayBlocking(btn) do
					element:Step(delta)
					task.wait(0.08)
				end
			end)
		end))

		local function cancelHold()
			holdToken += 1
		end
		element.Maid:Give(btn.InputEnded:Connect(cancelHold))
		element.Maid:Give(btn.MouseLeave:Connect(cancelHold))
	end

	bindRepeatButton(minusBtn, -1)
	bindRepeatButton(plusBtn, 1)

	element.Maid:Give(valueBox.Focused:Connect(function()
		if element.Disabled or element.Locked then
			valueBox:ReleaseFocus()
			return
		end
		valueBox.Text = tostring(currentVal)
	end))

	element.Maid:Give(valueBox.FocusLost:Connect(function()
		local raw = Util.Trim(valueBox.Text):gsub(",", "")
		local parsed = tonumber(raw)
		if not parsed then
			local extracted = raw:match("[%-]?%d+%.?%d*")
			parsed = extracted and tonumber(extracted) or nil
		end
		if parsed then
			element:Set(parsed, false)
		end
		valueBox.Text = formatVal(currentVal)
	end))

	element._onDisabled = function(disabled)
		valueBox.TextEditable = not disabled
		refreshStepperVisual()
	end

	return element
end

SliderModule.Slider = Slider
SliderModule.RangeSlider = RangeSlider
SliderModule.Stepper = Stepper

return SliderModule
