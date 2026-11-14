--[[
	Bali UI · Elements/Button
	Interactive action buttons (with 2-step confirmation) and equal-width ButtonGroup rows.
]]

local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Tooltip = require("Systems/Tooltip")
local Base = require("Elements/Base")

local ButtonModule = {}

local function applyButtonVariant(btnFrame, stroke, label, iconObj, grad, variant, isConfirming, isHovered)
	if isConfirming then
		if grad then
			grad.Enabled = false
		end
		Theme.Bind(btnFrame, { BackgroundColor3 = "Error" })
		btnFrame.BackgroundTransparency = isHovered and 0.68 or 0.78
		if stroke then
			Theme.Bind(stroke, { Color = "Error" })
			stroke.Transparency = 0.25
		end
		if label then
			Theme.Bind(label, { TextColor3 = "Error" })
		end
		if iconObj then
			Icons.SetColor(iconObj, "Error")
		end
		return
	end

	if variant == "Primary" then
		Theme.Unbind(btnFrame, "BackgroundColor3")
		btnFrame.BackgroundColor3 = Color3.new(1, 1, 1)
		btnFrame.BackgroundTransparency = isHovered and 0.08 or 0
		if grad then
			grad.Color = Theme.AccentSequence()
			grad.Enabled = true
		end
		if stroke then
			Theme.Bind(stroke, { Color = "Accent" })
			stroke.Transparency = isHovered and 0.25 or 0.45
		end
		if label then
			Theme.Bind(label, { TextColor3 = "AccentText" })
		end
		if iconObj then
			Icons.SetColor(iconObj, "AccentText")
		end
	elseif variant == "Danger" then
		if grad then
			grad.Enabled = false
		end
		Theme.Bind(btnFrame, { BackgroundColor3 = "Error" })
		btnFrame.BackgroundTransparency = isHovered and 0.72 or 0.84
		if stroke then
			Theme.Bind(stroke, { Color = "Error" })
			stroke.Transparency = isHovered and 0.35 or 0.55
		end
		if label then
			Theme.Bind(label, { TextColor3 = "Error" })
		end
		if iconObj then
			Icons.SetColor(iconObj, "Error")
		end
	elseif variant == "Ghost" then
		if grad then
			grad.Enabled = false
		end
		Theme.Bind(btnFrame, { BackgroundColor3 = isHovered and "TileHover" or "Tile" })
		btnFrame.BackgroundTransparency = isHovered and 0.45 or 1
		if stroke then
			Theme.Bind(stroke, { Color = "Stroke" })
			stroke.Transparency = isHovered and 0.86 or 0.94
		end
		if label then
			Theme.Bind(label, { TextColor3 = isHovered and "Text" or "SubText" })
		end
		if iconObj then
			Icons.SetColor(iconObj, isHovered and "Text" or "SubText")
		end
	else
		-- "Default"
		if grad then
			grad.Enabled = false
		end
		Theme.Bind(btnFrame, {
			BackgroundColor3 = isHovered and "TileHover" or "Tile",
			BackgroundTransparency = "TileTransparency",
		})
		if stroke then
			Theme.Bind(stroke, {
				Color = "Stroke",
				Transparency = function(t)
					local base = math.max(t.StrokeTransparency - 0.02, 0)
					return isHovered and math.max(base - 0.08, 0) or base
				end,
			})
		end
		if label then
			Theme.Bind(label, { TextColor3 = "Text" })
		end
		if iconObj then
			Icons.SetColor(iconObj, "Accent")
		end
	end
end

local function applyStateTransition(frame, stroke, variant, hovered, pressed, confirming, animate)
	local theme = Theme.Current
	local targetBg = frame.BackgroundColor3
	local targetTrans = frame.BackgroundTransparency
	local targetStroke = stroke.Transparency
	local tileHover = theme.TileHover or theme.Tile
	local accentHover = theme.AccentHover or theme.Accent

	if not confirming and variant == "Default" then
		targetBg = pressed and Util.LerpColor(tileHover, theme.Accent, 0.08) or (hovered and tileHover or theme.Tile)
		targetTrans = pressed and math.max(0.06, theme.TileTransparency - 0.14)
			or (hovered and math.max(0.12, theme.TileTransparency - 0.08) or theme.TileTransparency)
		targetStroke = pressed and 0.42 or (hovered and 0.56 or theme.StrokeTransparency)
	elseif variant == "Primary" and not confirming then
		targetBg = pressed and Util.LerpColor(accentHover, Color3.new(1, 1, 1), 0.08)
			or (hovered and accentHover or theme.Accent)
		targetTrans = pressed and 0.02 or (hovered and 0.06 or 0.14)
	end

	if animate then
		Tween.Play(frame, { BackgroundColor3 = targetBg, BackgroundTransparency = targetTrans }, Tween.Fast, Enum.EasingStyle.Exponential)
		Tween.Play(stroke, { Transparency = targetStroke }, Tween.Fast, Enum.EasingStyle.Exponential)
	else
		frame.BackgroundColor3 = targetBg
		frame.BackgroundTransparency = targetTrans
		stroke.Transparency = targetStroke
	end
end

-- ─── Button ──────────────────────────────────────────────────────────────────

local Button = {}
function Button.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Title")
	local element = Base.New("Button", parent, opts, ctx)

	local rowOpts = table.clone(opts)
	if rowOpts.IconBadge == nil then
		rowOpts.IconBadge = false
	end

	local variant = opts.Variant or "Default"
	local row = Base.Row(parent, rowOpts, 0)
	element:BindUI(row)

	local grad = Instance.new("UIGradient")
	grad.Color = Theme.AccentSequence()
	grad.Rotation = 15
	grad.Enabled = false
	grad.Parent = row.Frame

	local rightIcon = nil
	if opts.ShowArrow ~= false then
		Create.List(row.Right, {
			Direction = Enum.FillDirection.Horizontal,
			VAlign = Enum.VerticalAlignment.Center,
			HAlign = Enum.HorizontalAlignment.Right,
			Gap = 6,
		})
		if opts.Badge then
			local bText = type(opts.Badge) == "table" and (opts.Badge.Text or opts.Badge[1]) or tostring(opts.Badge)
			local bColor = type(opts.Badge) == "table" and (opts.Badge.Color or opts.Badge[2]) or "Accent"
			local b = Base.Badge(row.Right, bText, bColor)
			b.Frame.LayoutOrder = 1
		end
		rightIcon = Icons.Create(opts.RightIcon or "chevron-right", {
			Size = UDim2.fromOffset(15, 15),
			Color = "Muted",
			LayoutOrder = 2,
			Parent = row.Right,
		})
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

	row.Left.ZIndex = 2
	row.Right.ZIndex = 2

	local hovered = false
	local pressed = false
	local confirming = false
	local confirmToken = 0
	local baseTitle = element.Title

	local function refreshVisual(animate)
		applyButtonVariant(row.Frame, row.Stroke, row.TitleLabel, row.IconObj, grad, variant, confirming, hovered or pressed)

		if row.DescLabel then
			if confirming then
				Theme.Bind(row.DescLabel, { TextColor3 = "Error" })
			elseif variant == "Primary" then
				Theme.Bind(row.DescLabel, { TextColor3 = "AccentText" })
				row.DescLabel.TextTransparency = 0.18
			else
				Theme.Bind(row.DescLabel, { TextColor3 = "SubText" })
				row.DescLabel.TextTransparency = element.Disabled and 0.48 or 0
			end
		end

		if rightIcon then
			Icons.SetColor(rightIcon, confirming and "Error" or (variant == "Primary" and "AccentText" or "Muted"))
		end

		applyStateTransition(row.Frame, row.Stroke, variant, hovered, pressed, confirming, animate)
	end

	refreshVisual(false)
	element.Maid:Give(Theme.Changed:Connect(function()
		if not element._destroyed then
			refreshVisual(false)
		end
	end))

	element._onDisabled = function(disabled)
		hitBtn.Visible = not disabled
		if disabled then
			hovered = false
			pressed = false
		end
		refreshVisual(false)
	end

	element.Maid:Give(hitBtn.MouseEnter:Connect(function()
		if element.Disabled or element.Locked or Util.IsTouchDevice() then
			return
		end
		hovered = true
		refreshVisual(true)
	end))

	element.Maid:Give(hitBtn.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		refreshVisual(true)
	end))

	local lastPointerPos = nil
	element.Maid:Give(hitBtn.InputBegan:Connect(function(input)
		if element.Disabled or element.Locked then
			return
		end
		if Util.IsPointer(input) then
			lastPointerPos = Vector2.new(input.Position.X, input.Position.Y)
			pressed = true
			refreshVisual(true)
		end
	end))

	element.Maid:Give(hitBtn.InputEnded:Connect(function(input)
		if Util.IsPointer(input) then
			pressed = false
			refreshVisual(true)
		end
	end))

	local function shakeBody()
		if Tween.Reduced or not row.Body or not row.Body.Parent then
			return
		end
		local offsets = { -5, 5, -3, 3, 0 }
		task.spawn(function()
			for _, x in ipairs(offsets) do
				if element._destroyed or not row.Body.Parent then
					return
				end
				Tween.Play(row.Body, { Position = UDim2.fromOffset(x, 0) }, 0.04, Enum.EasingStyle.Sine)
				task.wait(0.045)
			end
			if row.Body and row.Body.Parent then
				row.Body.Position = UDim2.fromOffset(0, 0)
			end
		end)
	end

	local function resetConfirm()
		confirming = false
		row:SetTitle(baseTitle)
		if rightIcon then
			Icons.Set(rightIcon, opts.RightIcon or "chevron-right")
		end
		refreshVisual(true)
	end

	local function executeCallback()
		element.Changed:Fire()
		if type(opts.Callback) == "function" then
			Util.Spawn(opts.Callback)
		end
	end

	local function trigger(posOverride)
		if element.Disabled or element.Locked then
			return
		end
		local rippleColor = variant == "Primary" and "AccentText" or (variant == "Danger" and "Error" or "Accent")
		Transition.Ripple(row.Frame, posOverride or lastPointerPos, rippleColor)

		if opts.Confirm then
			if not confirming then
				confirming = true
				confirmToken += 1
				local myToken = confirmToken
				local confirmPrompt = type(opts.Confirm) == "string" and opts.Confirm or "Click again to confirm"
				row:SetTitle(confirmPrompt)
				if rightIcon then
					Icons.Set(rightIcon, "triangle-alert")
				end
				refreshVisual(true)
				shakeBody()
				task.delay(3, function()
					if not element._destroyed and confirming and confirmToken == myToken then
						resetConfirm()
					end
				end)
				return
			else
				confirmToken += 1
				resetConfirm()
			end
		end

		executeCallback()
	end

	element.Maid:Give(hitBtn.Activated:Connect(function(inputObj)
		local pos = lastPointerPos
		if inputObj and inputObj.Position then
			pos = Vector2.new(inputObj.Position.X, inputObj.Position.Y)
		end
		trigger(pos)
	end))

	function element:SetText(s)
		local text = tostring(s or "")
		baseTitle = text
		self.Title = text
		if self._record then
			self._record.Title = text
		end
		if not confirming then
			row:SetTitle(text)
		end
	end
	element.SetTitle = element.SetText

	function element:SetVariant(newVariant)
		variant = newVariant or "Default"
		refreshVisual(true)
	end

	function element:Fire()
		if self.Disabled or self.Locked then
			return
		end
		Transition.Ripple(row.Frame, nil, variant == "Primary" and "AccentText" or "Accent")
		executeCallback()
	end

	return element
end

-- ─── ButtonGroup ─────────────────────────────────────────────────────────────

local ButtonGroup = {}
function ButtonGroup.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Title")
	local element = Base.New("ButtonGroup", parent, opts, ctx)

	local wrapper = Create.New("Frame", {
		Name = "ButtonGroup",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})

	Create.List(wrapper, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 6,
	})

	local titleText = tostring(opts.Title or "")
	local titleLabel = Create.Text({
		Name = "Title",
		Text = titleText,
		Font = "Medium",
		TextSize = 12,
		Color = "SubText",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Visible = titleText ~= "",
		Parent = wrapper,
	})

	local row = Create.New("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = wrapper,
	})

	local gap = opts.Gap or 8
	Create.List(row, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = gap,
	})

	local buttonsList = opts.Buttons or {}
	local count = math.max(#buttonsList, 1)
	local createdButtons = {}

	for index, item in ipairs(buttonsList) do
		local bOpts = type(item) == "table" and item or { Title = tostring(item) }
		local bVariant = bOpts.Variant or "Default"
		local widthOffset = -((count - 1) * gap) / count

		local btn = Create.New("TextButton", {
			Name = "Pill_" .. index,
			Size = UDim2.new(1 / count, widthOffset, 0, 38),
			Theme = { BackgroundColor3 = "Tile" },
			Corner = UDim.new(1, 0),
			Padding = { 0, 12, 0, 12 },
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = index,
			Parent = row,
		})

		local stroke = Create.GlassStroke(btn, 0.02)
		local grad = Instance.new("UIGradient")
		grad.Color = Theme.AccentSequence()
		grad.Rotation = 15
		grad.Enabled = false
		grad.Parent = btn

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
			Gap = 6,
		})

		local iconObj = nil
		if bOpts.Icon and bOpts.Icon ~= "" and bOpts.Icon ~= false then
			iconObj = Icons.Create(bOpts.Icon, {
				Size = UDim2.fromOffset(14, 14),
				Color = "Text",
				LayoutOrder = 1,
				Parent = content,
			})
		end

		local lbl = Create.Text({
			Name = "Label",
			Text = tostring(bOpts.Title or bOpts.Text or ("Action " .. index)),
			Font = "SemiBold",
			TextSize = 12,
			Color = "Text",
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 2,
			Parent = content,
		})

		local isHovered = false
		local isPressed = false
		local itemDisabled = (bOpts.Disabled == true)

		local function refreshBtn(animate)
			applyButtonVariant(btn, stroke, lbl, iconObj, grad, bVariant, false, isHovered or isPressed)
			local dim = (element.Disabled or itemDisabled) and 0.48 or 0
			lbl.TextTransparency = dim
			if iconObj then
				Icons.SetTransparency(iconObj, dim)
			end

			applyStateTransition(btn, stroke, bVariant, isHovered, isPressed, false, animate)
		end

		refreshBtn(false)
		element.Maid:Give(Theme.Changed:Connect(function()
			if not element._destroyed then
				refreshBtn(false)
			end
		end))

		if bOpts.Tooltip then
			pcall(Tooltip.Bind, btn, bOpts.Tooltip)
		end

		element.Maid:Give(btn.MouseEnter:Connect(function()
			if element.Disabled or element.Locked or itemDisabled or Util.IsTouchDevice() then
				return
			end
			isHovered = true
			refreshBtn(true)
		end))

		element.Maid:Give(btn.MouseLeave:Connect(function()
			isHovered = false
			isPressed = false
			refreshBtn(true)
		end))

		local lastPos = nil
		element.Maid:Give(btn.InputBegan:Connect(function(input)
			if element.Disabled or element.Locked or itemDisabled then
				return
			end
			if Util.IsPointer(input) then
				lastPos = Vector2.new(input.Position.X, input.Position.Y)
				isPressed = true
				refreshBtn(true)
			end
		end))

		element.Maid:Give(btn.InputEnded:Connect(function(input)
			if Util.IsPointer(input) then
				isPressed = false
				refreshBtn(true)
			end
		end))

		element.Maid:Give(btn.Activated:Connect(function(inputObj)
			if element.Disabled or element.Locked or itemDisabled then
				return
			end
			local pos = (inputObj and inputObj.Position) and Vector2.new(inputObj.Position.X, inputObj.Position.Y) or lastPos
			Transition.Ripple(btn, pos, bVariant == "Primary" and "AccentText" or "Accent")
			element.Changed:Fire(index, bOpts.Title)
			if type(bOpts.Callback) == "function" then
				Util.Spawn(bOpts.Callback)
			end
		end))

		createdButtons[index] = {
			Frame = btn,
			Label = lbl,
			Icon = iconObj,
			SetText = function(_, s)
				lbl.Text = tostring(s or "")
			end,
			SetVariant = function(_, v)
				bVariant = v or "Default"
				refreshBtn()
			end,
			SetDisabled = function(_, d)
				itemDisabled = (d == true)
				refreshBtn()
			end,
			Refresh = refreshBtn,
		}
	end

	element:BindUI({
		Frame = wrapper,
		TitleLabel = titleLabel,
		SetTitle = function(_, s)
			local txt = tostring(s or "")
			titleLabel.Text = txt
			titleLabel.Visible = (txt ~= "")
		end,
		SetDisabled = function(_, disabled)
			for _, b in ipairs(createdButtons) do
				b.Refresh()
			end
		end,
		Flash = function()
			for _, b in ipairs(createdButtons) do
				Base.FlashFrame(b.Frame)
			end
		end,
	})

	function element:GetButton(index)
		return createdButtons[index]
	end

	return element
end

ButtonModule.Button = Button
ButtonModule.ButtonGroup = ButtonGroup

return ButtonModule
