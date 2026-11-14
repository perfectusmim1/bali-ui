--[[
	Bali UI · Elements/Toggle
	Apple pill Toggle switch (with optional inline Keybind sub-chip) and Checkbox.
]]

local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Input = require("Systems/Input")
local Base = require("Elements/Base")

local ToggleModule = {}

-- ─── Toggle ──────────────────────────────────────────────────────────────────

local Toggle = {}
function Toggle.new(parent, opts, ctx)
	opts = Util.Options(opts, { Default = false }, "Title")
	local element = Base.New("Toggle", parent, opts, ctx)

	local state = opts.Default == true
	element.Value = state

	local rowOpts = table.clone(opts)
	if rowOpts.IconBadge == nil then
		rowOpts.IconBadge = false
	end

	local hasKeybind = opts.Keybind ~= nil
	element._hasKeybind = hasKeybind
	local row = Base.Row(parent, rowOpts, hasKeybind and 86 or 44)
	element:BindUI(row)

	Create.List(row.Right, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		HAlign = Enum.HorizontalAlignment.Right,
		Gap = 6,
	})

	-- Pill switch (42x22)
	local track = Create.New("Frame", {
		Name = "Track",
		Size = UDim2.fromOffset(42, 22),
		Theme = { BackgroundColor3 = "ToggleOff" },
		Corner = UDim.new(1, 0),
		LayoutOrder = 2,
		Parent = row.Right,
	})

	local trackStroke = Create.Stroke(track, {
		Theme = {
			Color = function(t)
				return state and t.Accent or t.Stroke
			end,
			Transparency = function(t)
				return state and 0.45 or t.StrokeTransparency
			end,
		},
		Thickness = 1,
	})

	local accentFill = Create.New("Frame", {
		Name = "AccentFill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = state and 0 or 1,
		Corner = UDim.new(1, 0),
		ZIndex = 2,
		Parent = track,
	})

	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = Theme.AccentSequence()
	fillGrad.Rotation = 15
	fillGrad.Parent = accentFill

	local knob = Create.New("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(18, 18),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, state and 22 or 2, 0.5, 0),
		Theme = { BackgroundColor3 = "Knob" },
		Corner = UDim.new(1, 0),
		ZIndex = 3,
		Parent = track,
	})

	local inputHandle = nil
	local currentKey = nil
	local listening = false
	local stopPulse = nil
	local keyChip, keyStroke, keyLabel

	local function applyVisual(animate)
		local targetPos = UDim2.new(0, state and 22 or 2, 0.5, 0)
		local targetAlpha = state and 0 or 1
		local targetStrokeColor = state and Theme.Current.Accent or Theme.Current.Stroke
		local targetStrokeTrans = state and 0.45 or Theme.Current.StrokeTransparency

		if animate then
			Tween.Spring(knob, { Position = targetPos }, Tween.Fast + 0.08)
			Tween.Play(knob, { Size = UDim2.fromOffset(22, 18) }, 0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.07, function()
				if knob.Parent and not element._destroyed then
					Tween.Spring(knob, { Size = UDim2.fromOffset(18, 18) }, 0.13)
				end
			end)
			Tween.Play(accentFill, { BackgroundTransparency = targetAlpha }, Tween.Fast, Enum.EasingStyle.Quad)
			Tween.Play(trackStroke, {
				Color = targetStrokeColor,
				Transparency = targetStrokeTrans,
			}, Tween.Fast, Enum.EasingStyle.Quad)
		else
			knob.Position = targetPos
			accentFill.BackgroundTransparency = targetAlpha
			trackStroke.Color = targetStrokeColor
			trackStroke.Transparency = targetStrokeTrans
		end
	end

	element.Maid:Give(Theme.Changed:Connect(function(t)
		if element._destroyed then
			return
		end
		fillGrad.Color = Theme.AccentSequence(t)
		applyVisual(false)
	end))

	-- Optional inline Keybind sub-chip
	if hasKeybind then
		local rawKey = type(opts.Keybind) == "table" and opts.Keybind.Key or (opts.Keybind == true and nil or opts.Keybind)
		currentKey = Util.ResolveKey(rawKey)
		local bindId = "ToggleKB_" .. Util.RandomString(8)

		keyChip = Create.New("TextButton", {
			Name = "KeyChip",
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			Theme = { BackgroundColor3 = "Field" },
			Corner = 6,
			Padding = { 0, 7, 0, 7 },
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
			ZIndex = 16,
			Parent = row.Right,
		})

		keyStroke = Create.Stroke(keyChip, {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
			Thickness = 1,
		})

		keyLabel = Create.Text({
			Name = "KeyLabel",
			Text = Util.KeyName(currentKey),
			Font = "SemiBold",
			TextSize = 11,
			Color = currentKey and "Text" or "Muted",
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 17,
			Parent = keyChip,
		})

		element.Maid:Give(Transition.Hover(keyChip, keyChip, "Field", "FieldHover", keyStroke))

		local function syncChip()
			if not listening then
				keyLabel.Text = Util.KeyName(currentKey)
				Theme.Bind(keyLabel, { TextColor3 = currentKey and "Text" or "Muted" })
				Theme.Bind(keyStroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
			end
			local chipW = math.max(28, math.ceil(keyChip.AbsoluteSize.X))
			row:SetRightWidth(42 + 6 + chipW)
		end

		element.Maid:Give(keyChip:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncChip))
		task.defer(syncChip)

		local function stopListening()
			if not listening then
				return
			end
			listening = false
			if stopPulse then
				pcall(stopPulse)
				stopPulse = nil
			end
			syncChip()
		end

		inputHandle = Input.RegisterKeybind(bindId, currentKey, function(active)
			if element._destroyed or element.Disabled or element.Locked then
				if inputHandle then
					inputHandle.SetActive(state, true)
				end
				return
			end
			element:Set(active)
		end, "Toggle")
		inputHandle.SetActive(state, true)

		element.Maid:Give(function()
			if listening then
				Input.CancelCapture()
			end
			stopListening()
			if inputHandle then
				inputHandle.Destroy()
				inputHandle = nil
			end
		end)

		element.Maid:Give(keyChip.Activated:Connect(function(inputObj)
			if element.Disabled or element.Locked then
				return
			end
			Transition.Ripple(keyChip, inputObj, "Accent")
			if listening then
				Input.CancelCapture()
				stopListening()
				return
			end
			listening = true
			keyLabel.Text = "..."
			Theme.Bind(keyLabel, { TextColor3 = "Accent" })
			Theme.Bind(keyStroke, { Color = "Accent" })
			keyStroke.Transparency = 0.25
			if stopPulse then
				pcall(stopPulse)
			end
			stopPulse = Transition.Pulse(keyStroke, "Transparency", 0.15, 0.72, 0.75)

			Input.CaptureKey(function(captured, cancelled)
				if element._destroyed or not listening then
					return
				end
				stopListening()
				if cancelled then
					return
				end
				currentKey = Util.ResolveKey(captured)
				if inputHandle then
					inputHandle.SetKey(currentKey)
				end
				syncChip()
				element.Changed:Fire(state, currentKey)
			end)
		end))
	end

	local hitBtn = Create.New("TextButton", {
		Name = "HitButton",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 12,
		Parent = row.Frame,
	})

	element.Maid:Give(Transition.Hover(hitBtn, row.Frame, "Tile", "TileHover", row.Stroke))

	local lastPointerPos = nil
	element.Maid:Give(hitBtn.InputBegan:Connect(function(input)
		if element.Disabled or element.Locked then
			return
		end
		if Util.IsPointer(input) then
			lastPointerPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))

	element._onDisabled = function(disabled)
		hitBtn.Visible = not disabled
		if keyChip then
			keyChip.Active = not disabled
		end
		track.BackgroundTransparency = disabled and 0.45 or 0
	end

	function element:Set(val, silent)
		local nextState = (val == true)
		local changed = (state ~= nextState)
		state = nextState
		self.Value = state
		applyVisual(true)
		if inputHandle then
			inputHandle.SetActive(state, true)
		end
		if changed and not silent then
			self.Changed:Fire(state)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, state)
			end
		end
	end

	function element:Get()
		return state
	end

	function element:Toggle()
		self:Set(not state, false)
	end

	function element:Fire()
		self:Toggle()
	end

	function element:SetKeybind(key)
		if not hasKeybind then
			return
		end
		currentKey = Util.ResolveKey(key)
		if inputHandle then
			inputHandle.SetKey(currentKey)
		end
		if keyLabel then
			keyLabel.Text = Util.KeyName(currentKey)
			Theme.Bind(keyLabel, { TextColor3 = currentKey and "Text" or "Muted" })
		end
	end

	function element:GetKeybind()
		return currentKey
	end

	element.Maid:Give(hitBtn.Activated:Connect(function(inputObj)
		if element.Disabled or element.Locked then
			return
		end
		local pos = (inputObj and inputObj.Position) and Vector2.new(inputObj.Position.X, inputObj.Position.Y) or lastPointerPos
		Transition.Ripple(row.Frame, pos, "Accent")
		element:Toggle()
	end))

	return element
end

-- ─── Checkbox ────────────────────────────────────────────────────────────────

local Checkbox = {}
function Checkbox.new(parent, opts, ctx)
	opts = Util.Options(opts, { Default = false }, "Title")
	local element = Base.New("Checkbox", parent, opts, ctx)

	local state = opts.Default == true
	element.Value = state

	local rowOpts = table.clone(opts)
	if rowOpts.IconBadge == nil then
		rowOpts.IconBadge = false
	end

	local row = Base.Row(parent, rowOpts, 24)
	element:BindUI(row)

	local box = Create.New("Frame", {
		Name = "CheckBox",
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.fromScale(1, 0.5),
		AnchorPoint = Vector2.new(1, 0.5),
		Theme = { BackgroundColor3 = "Field" },
		Corner = 6,
		Parent = row.Right,
	})

	local boxStroke = Create.Stroke(box, {
		Theme = {
			Color = function(t)
				return state and t.Accent or t.Stroke
			end,
			Transparency = function(t)
				return state and 0.25 or t.StrokeTransparency
			end,
		},
		Thickness = 1,
	})

	local accentFill = Create.New("Frame", {
		Name = "AccentFill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = state and 0 or 1,
		Corner = 6,
		ZIndex = 2,
		Parent = box,
	})

	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = Theme.AccentSequence()
	fillGrad.Rotation = 35
	fillGrad.Parent = accentFill

	local checkIcon = Icons.Create("check", {
		Size = UDim2.fromOffset(13, 13),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = "AccentText",
		Transparency = state and 0 or 1,
		ZIndex = 3,
		Parent = box,
	})

	local function applyVisual(animate)
		local targetAlpha = state and 0 or 1
		local targetSize = state and UDim2.fromOffset(13, 13) or UDim2.fromOffset(6, 6)
		local targetStrokeColor = state and Theme.Current.Accent or Theme.Current.Stroke
		local targetStrokeTrans = state and 0.25 or Theme.Current.StrokeTransparency
		local iconTarget = checkIcon and Icons.TransparencyTarget(checkIcon) or nil
		local iconTransProp = iconTarget and Icons.TransparencyProperty(iconTarget) or "ImageTransparency"

		if animate then
			Tween.Play(accentFill, { BackgroundTransparency = targetAlpha }, Tween.Fast, Enum.EasingStyle.Quad)
			if checkIcon and iconTarget then
				if iconTarget == checkIcon then
					Tween.Play(checkIcon, { [iconTransProp] = targetAlpha, Size = targetSize }, Tween.Fast, Enum.EasingStyle.Exponential)
				else
					Tween.Play(iconTarget, { [iconTransProp] = targetAlpha }, Tween.Fast, Enum.EasingStyle.Exponential)
					Tween.Play(checkIcon, { Size = targetSize }, Tween.Fast, Enum.EasingStyle.Exponential)
				end
			end
			Tween.Play(boxStroke, {
				Color = targetStrokeColor,
				Transparency = targetStrokeTrans,
			}, Tween.Fast, Enum.EasingStyle.Quad)
		else
			accentFill.BackgroundTransparency = targetAlpha
			if checkIcon then
				checkIcon[iconTransProp] = targetAlpha
				checkIcon.Size = targetSize
			end
			boxStroke.Color = targetStrokeColor
			boxStroke.Transparency = targetStrokeTrans
		end
	end

	element.Maid:Give(Theme.Changed:Connect(function(t)
		if element._destroyed then
			return
		end
		fillGrad.Color = Theme.AccentSequence(t)
		applyVisual(false)
	end))

	local hitBtn = Create.New("TextButton", {
		Name = "HitButton",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 12,
		Parent = row.Frame,
	})

	element.Maid:Give(Transition.Hover(hitBtn, row.Frame, "Tile", "TileHover", row.Stroke))

	local lastPointerPos = nil
	element.Maid:Give(hitBtn.InputBegan:Connect(function(input)
		if element.Disabled or element.Locked then
			return
		end
		if Util.IsPointer(input) then
			lastPointerPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))

	element._onDisabled = function(disabled)
		hitBtn.Visible = not disabled
		box.BackgroundTransparency = disabled and 0.5 or 0
	end

	function element:Set(val, silent)
		local nextState = (val == true)
		local changed = (state ~= nextState)
		state = nextState
		self.Value = state
		applyVisual(true)
		if changed and not silent then
			self.Changed:Fire(state)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, state)
			end
		end
	end

	function element:Get()
		return state
	end

	function element:Toggle()
		self:Set(not state, false)
	end

	function element:Fire()
		self:Toggle()
	end

	element.Maid:Give(hitBtn.Activated:Connect(function(inputObj)
		if element.Disabled or element.Locked then
			return
		end
		local pos = (inputObj and inputObj.Position) and Vector2.new(inputObj.Position.X, inputObj.Position.Y) or lastPointerPos
		Transition.Ripple(row.Frame, pos, "Accent")
		element:Toggle()
	end))

	return element
end

ToggleModule.Toggle = Toggle
ToggleModule.Checkbox = Checkbox

return ToggleModule
