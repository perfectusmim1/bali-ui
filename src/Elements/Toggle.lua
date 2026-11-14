--[[
	Bali UI · Elements/Toggle
	Apple pill Toggle switch (with optional inline Keybind sub-chip) and Checkbox.
]]

local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Input = require("Systems/Input")
local KeybindList = require("Systems/KeybindList")
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
	local row = Base.Row(parent, rowOpts, hasKeybind and 88 or 46)
	element:BindUI(row)

	Create.List(row.Right, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		HAlign = Enum.HorizontalAlignment.Right,
		Gap = 6,
	})

	-- Glass capsule switch (44x22)
	local track = Create.New("Frame", {
		Name = "Track",
		Size = UDim2.fromOffset(44, 22),
		Theme = {
			BackgroundColor3 = function(t)
				return state and t.Accent or t.Field
			end,
		},
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
				return state and 0.45 or math.min(0.48, t.StrokeTransparency)
			end,
		},
		Thickness = 1.2,
	})

	local knob = Create.New("Frame", {
		Name = "Knob",
		Size = state and UDim2.fromOffset(20, 16) or UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, state and 21 or 3, 0.5, 0),
		BackgroundColor3 = state and Theme.Current.Knob or (Theme.Current.Dark and Color3.fromRGB(186, 192, 206) or Theme.Current.Knob),
		Corner = UDim.new(1, 0),
		ZIndex = 3,
		Parent = track,
	})

	local knobStroke = Create.Stroke(knob, {
		Theme = { Color = "Stroke" },
		Transparency = state and 0.25 or 0.68,
		Thickness = 1,
	})

	local glowAsset = Assets.Get("Glow")
	local knobGlow
	if glowAsset then
		knobGlow = Create.New("ImageLabel", {
			Name = "KnobGlow",
			Size = UDim2.fromOffset(32, 32),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = glowAsset,
			Theme = { ImageColor3 = "Accent" },
			ImageTransparency = state and 0.52 or 1,
			ZIndex = 2,
			Parent = knob,
		})
	else
		knobGlow = Create.New("Frame", {
			Name = "KnobGlow",
			Size = UDim2.fromOffset(26, 26),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Corner = UDim.new(1, 0),
			Theme = { BackgroundColor3 = "Accent" },
			BackgroundTransparency = state and 0.68 or 1,
			ZIndex = 2,
			Parent = knob,
		})
	end

	local inputHandle = nil
	local currentKey = nil
	local listening = false
	local stopPulse = nil
	local syncKeybindList = nil
	local keyChip, keyStroke, keyLabel
	local trackHovered = false
	local knobAnimToken = 0

	local function applyVisual(animate)
		local targetPos = UDim2.new(0, state and 21 or 3, 0.5, 0)
		local targetSize = state and UDim2.fromOffset(20, 16) or UDim2.fromOffset(16, 16)
		local targetKnobColor = state and Theme.Current.Knob or (Theme.Current.Dark and Color3.fromRGB(186, 192, 206) or Theme.Current.Knob)
		local targetTrackBg = state and Theme.Current.Accent or Theme.Current.Field
		local targetStrokeColor = state and Theme.Current.Accent or Theme.Current.Stroke
		local restStrokeTrans = state and 0.45 or math.min(0.48, Theme.Current.StrokeTransparency)
		local targetStrokeTrans = trackHovered and math.max(0.18, restStrokeTrans - 0.16) or restStrokeTrans
		local targetKnobStrokeTrans = state and 0.25 or 0.68
		local isImgGlow = knobGlow:IsA("ImageLabel")
		local glowProp = isImgGlow and "ImageTransparency" or "BackgroundTransparency"
		local targetGlowTrans = state and (isImgGlow and 0.52 or 0.68) or 1

		knobAnimToken += 1
		local myToken = knobAnimToken

		if animate then
			Tween.Play(knob, {
				Position = targetPos,
				BackgroundColor3 = targetKnobColor,
			}, 0.38, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
			Tween.Play(knob, {
				Size = UDim2.fromOffset(23, 16),
			}, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.08, function()
				if knob.Parent and not element._destroyed and knobAnimToken == myToken then
					Tween.Play(knob, { Size = targetSize }, 0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end)
			Tween.Play(knobStroke, { Transparency = targetKnobStrokeTrans }, 0.32, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
			Tween.Play(knobGlow, { [glowProp] = targetGlowTrans }, 0.38, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
			Tween.Play(track, { BackgroundColor3 = targetTrackBg }, 0.34, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
			Tween.Play(trackStroke, {
				Color = targetStrokeColor,
				Transparency = targetStrokeTrans,
			}, 0.34, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
		else
			knob.Position = targetPos
			knob.Size = targetSize
			knob.BackgroundColor3 = targetKnobColor
			knobStroke.Transparency = targetKnobStrokeTrans
			knobGlow[glowProp] = targetGlowTrans
			track.BackgroundColor3 = targetTrackBg
			trackStroke.Color = targetStrokeColor
			trackStroke.Transparency = targetStrokeTrans
		end
	end

	element.Maid:Give(Theme.Changed:Connect(function(t)
		if element._destroyed then
			return
		end
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
			BackgroundTransparency = 0.12,
			Theme = { BackgroundColor3 = "TileHover" },
			Corner = 6,
			Padding = { 0, 7, 0, 7 },
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
			ZIndex = 16,
			Parent = row.Right,
		})

		keyStroke = Create.Stroke(keyChip, {
			Theme = { Color = "Stroke" },
			Transparency = 0.48,
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

		element.Maid:Give(Transition.Hover(keyChip, keyChip, "TileHover", "FieldHover", keyStroke))

		local function syncChip()
			if not listening then
				keyLabel.Text = Util.KeyName(currentKey)
				Theme.Bind(keyLabel, { TextColor3 = currentKey and "Text" or "Muted" })
				Theme.Bind(keyStroke, { Color = "Stroke" })
				keyStroke.Transparency = 0.48
			end
			local chipW = math.max(28, math.ceil(keyChip.AbsoluteSize.X))
			row:SetRightWidth(44 + 6 + chipW)
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

		local syncList = opts.SyncList ~= false
		syncKeybindList = function()
			if not syncList or not KeybindList or not KeybindList.Update then
				return
			end
			KeybindList.Update(bindId, {
				Title = tostring(element.Title or opts.Title or "Toggle"),
				KeyName = Util.KeyName(currentKey),
				Mode = "Toggle",
				Active = state,
			})
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

		if syncList and KeybindList and KeybindList.Register then
			KeybindList.Register(bindId, {
				Title = tostring(opts.Title or "Toggle"),
				KeyName = Util.KeyName(currentKey),
				Mode = "Toggle",
				Active = state,
			})
		end

		element.Maid:Give(function()
			if listening then
				Input.CancelCapture()
			end
			stopListening()
			if inputHandle then
				inputHandle.Destroy()
				inputHandle = nil
			end
			if syncList and KeybindList and KeybindList.Unregister then
				KeybindList.Unregister(bindId)
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
				syncKeybindList()
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

	element.Maid:Give(hitBtn.MouseEnter:Connect(function()
		if element.Disabled or element.Locked or Util.IsTouchDevice() or Transition.IsHiddenOrUnmounting(row.Frame) then
			return
		end
		trackHovered = true
		local restStrokeTrans = state and 0.45 or math.min(0.48, Theme.Current.StrokeTransparency)
		Tween.Play(trackStroke, { Transparency = math.max(0.18, restStrokeTrans - 0.16) }, Tween.Fast, Enum.EasingStyle.Exponential)
	end))

	element.Maid:Give(hitBtn.MouseLeave:Connect(function()
		trackHovered = false
		if Transition.IsHiddenOrUnmounting(row.Frame) then
			return
		end
		local restStrokeTrans = state and 0.45 or math.min(0.48, Theme.Current.StrokeTransparency)
		Tween.Play(trackStroke, { Transparency = restStrokeTrans }, Tween.Fast, Enum.EasingStyle.Exponential)
	end))

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
		if disabled then
			trackHovered = false
		end
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
		if syncKeybindList then
			syncKeybindList()
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
		if syncKeybindList then
			syncKeybindList()
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

	local row = Base.Row(parent, rowOpts, 26)
	element:BindUI(row)

	local box = Create.New("Frame", {
		Name = "CheckBox",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -11, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ClipsDescendants = false,
		Theme = {
			BackgroundColor3 = function(t)
				return state and t.Accent or t.Field
			end,
		},
		Corner = 7,
		Parent = row.Right,
	})

	local boxStroke = Create.Stroke(box, {
		Theme = {
			Color = function(t)
				return state and t.Accent or t.Stroke
			end,
			Transparency = function(t)
				return state and 0.4 or 0.38
			end,
		},
		Thickness = 1.25,
	})

	local boxGlowAsset = Assets.Get("Glow")
	local boxGlow
	if boxGlowAsset then
		boxGlow = Create.New("ImageLabel", {
			Name = "BoxGlow",
			Size = UDim2.fromOffset(36, 36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = boxGlowAsset,
			Theme = { ImageColor3 = "Accent" },
			ImageTransparency = state and 0.58 or 1,
			ZIndex = 1,
			Parent = box,
		})
	else
		boxGlow = Create.New("Frame", {
			Name = "BoxGlow",
			Size = UDim2.fromOffset(30, 30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Corner = 10,
			Theme = { BackgroundColor3 = "Accent" },
			BackgroundTransparency = state and 0.72 or 1,
			ZIndex = 1,
			Parent = box,
		})
	end

	local innerFill = Create.New("Frame", {
		Name = "InnerFill",
		Size = state and UDim2.fromScale(1, 1) or UDim2.fromOffset(6, 6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = state and 0 or 1,
		Theme = { BackgroundColor3 = "Accent" },
		Corner = 6,
		ZIndex = 2,
		Parent = box,
	})

	local innerGrad = Instance.new("UIGradient")
	innerGrad.Rotation = 90
	innerGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.16),
	})
	innerGrad.Parent = innerFill

	local checkIcon = Icons.Create("check", {
		Size = state and UDim2.fromOffset(14, 14) or UDim2.fromOffset(6, 6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = "AccentText",
		Transparency = state and 0 or 1,
		ZIndex = 4,
		Parent = box,
	})

	local boxHovered = false

	local function applyVisual(animate)
		local targetAlpha = state and 0 or 1
		local targetBg = state and Theme.Current.Accent or Theme.Current.Field
		local targetBoxTrans = state and (element.Disabled and 0.5 or 0.15) or (element.Disabled and 0.5 or 0)
		local targetFillSize = state and UDim2.fromScale(1, 1) or UDim2.fromOffset(6, 6)
		local targetFillTrans = state and (element.Disabled and 0.5 or 0) or 1
		local targetIconSize = state and UDim2.fromOffset(14, 14) or UDim2.fromOffset(6, 6)
		local targetStrokeColor = state and Theme.Current.Accent or Theme.Current.Stroke
		local targetStrokeTrans = state and 0.4 or (boxHovered and 0.18 or 0.38)
		local isImgGlow = boxGlow:IsA("ImageLabel")
		local glowProp = isImgGlow and "ImageTransparency" or "BackgroundTransparency"
		local targetGlowTrans = state and (isImgGlow and 0.58 or 0.72) or 1
		local iconTarget = checkIcon and Icons.TransparencyTarget(checkIcon) or nil
		local iconTransProp = iconTarget and Icons.TransparencyProperty(iconTarget) or "ImageTransparency"

		if animate then
			box.Size = UDim2.fromOffset(18, 18)
			Tween.Play(box, {
				Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = targetBg,
				BackgroundTransparency = targetBoxTrans,
			}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			Tween.Play(innerFill, {
				Size = targetFillSize,
				BackgroundTransparency = targetFillTrans,
			}, 0.34, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
			Tween.Play(boxGlow, { [glowProp] = targetGlowTrans }, 0.38, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
			if checkIcon and iconTarget then
				if state then
					checkIcon.Size = UDim2.fromOffset(6, 6)
					checkIcon.Rotation = -16
					Tween.Play(checkIcon, {
						Size = targetIconSize,
						Rotation = 0,
					}, 0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
					if iconTarget == checkIcon then
						Tween.Play(checkIcon, { [iconTransProp] = targetAlpha }, 0.22, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
					else
						Tween.Play(iconTarget, { [iconTransProp] = targetAlpha }, 0.22, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
					end
				else
					Tween.Play(checkIcon, {
						Size = targetIconSize,
						Rotation = 10,
					}, 0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
					Tween.Play(iconTarget, { [iconTransProp] = targetAlpha }, 0.16, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
				end
			end
			Tween.Play(boxStroke, {
				Color = targetStrokeColor,
				Transparency = targetStrokeTrans,
			}, 0.26, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
		else
			box.Size = UDim2.fromOffset(22, 22)
			box.BackgroundColor3 = targetBg
			box.BackgroundTransparency = targetBoxTrans
			innerFill.Size = targetFillSize
			innerFill.BackgroundTransparency = targetFillTrans
			boxGlow[glowProp] = targetGlowTrans
			if checkIcon and iconTarget then
				iconTarget[iconTransProp] = targetAlpha
				checkIcon.Size = targetIconSize
				checkIcon.Rotation = 0
			end
			boxStroke.Color = targetStrokeColor
			boxStroke.Transparency = targetStrokeTrans
		end
	end

	element.Maid:Give(Theme.Changed:Connect(function()
		if element._destroyed then
			return
		end
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

	element.Maid:Give(hitBtn.MouseEnter:Connect(function()
		if element.Disabled or element.Locked or Util.IsTouchDevice() or Transition.IsHiddenOrUnmounting(row.Frame) then
			return
		end
		boxHovered = true
		if not state then
			Tween.Play(boxStroke, { Transparency = 0.18 }, Tween.Fast, Enum.EasingStyle.Exponential)
		end
	end))

	element.Maid:Give(hitBtn.MouseLeave:Connect(function()
		boxHovered = false
		if Transition.IsHiddenOrUnmounting(row.Frame) then
			return
		end
		if not state then
			Tween.Play(boxStroke, { Transparency = 0.38 }, Tween.Fast, Enum.EasingStyle.Exponential)
		end
	end))

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
		box.BackgroundTransparency = state and (disabled and 0.5 or 0.15) or (disabled and 0.5 or 0)
		innerFill.BackgroundTransparency = state and (disabled and 0.5 or 0) or 1
		if disabled then
			boxHovered = false
		end
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
