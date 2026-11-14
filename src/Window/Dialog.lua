--[[
	Bali UI · Window/Dialog
	Centered obsidian glass modal dialog over a dimmed backdrop with spring mount,
	optional icon badge, text input field, action buttons, and Escape support.
]]

local Assets = require("Core/Assets")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Maid = require("Core/Maid")
local Services = require("Core/Services")
local Theme = require("Core/Theme")
local Transition = require("Core/Transition")
local Tween = require("Core/Tween")
local Util = require("Core/Util")

local Dialog = {}

local function applyButtonStyle(button, stroke, label, variant)
	if variant == "Primary" then
		Theme.Bind(button, { BackgroundColor3 = "Accent", BackgroundTransparency = 0 })
		Theme.Bind(label, { TextColor3 = "AccentText" })
		if stroke then
			Theme.Bind(stroke, { Color = "Accent", Transparency = 0.55 })
		end
		local gradient = Instance.new("UIGradient")
		gradient.Color = Theme.AccentSequence()
		gradient.Rotation = 18
		gradient.Parent = button
		return gradient
	elseif variant == "Danger" then
		Theme.Bind(button, { BackgroundColor3 = "Error", BackgroundTransparency = 0.82 })
		Theme.Bind(label, { TextColor3 = "Error" })
		if stroke then
			Theme.Bind(stroke, { Color = "Error", Transparency = 0.55 })
		end
	elseif variant == "Ghost" then
		Theme.Bind(button, { BackgroundColor3 = "Tile", BackgroundTransparency = 1 })
		Theme.Bind(label, { TextColor3 = "SubText" })
		if stroke then
			Theme.Bind(stroke, { Color = "Stroke", Transparency = 1 })
		end
	else
		Theme.Bind(button, { BackgroundColor3 = "Tile", BackgroundTransparency = "TileTransparency" })
		Theme.Bind(label, { TextColor3 = "Text" })
		if stroke then
			Theme.Bind(stroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
		end
	end
	return nil
end

function Dialog.Show(dialogLayer, options)
	assert(typeof(dialogLayer) == "Instance", "[Bali] Dialog.Show expects a dialogLayer Instance")
	options = Util.Options(options, {
		Title = "Confirm",
		Content = nil,
		Description = nil,
		Message = nil,
		Icon = nil,
		Buttons = nil,
		Input = nil,
		Dismissible = true,
		OnClose = nil,
	}, "Title")

	local maid = Maid.new()
	local closed = false

	-- Dimmed click-catcher backdrop
	local backdrop = Create.New("TextButton", {
		Name = "DialogBackdrop",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Theme = { BackgroundColor3 = "Overlay" },
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = dialogLayer,
	})
	maid:Give(backdrop)

	local container = Create.New("Frame", {
		Name = "DialogContainer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = dialogLayer,
	})
	maid:Give(container)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(400, 620)
	constraint.Parent = container

	local shadowDesc = Assets.Shadow()
	local shadow = Create.New("ImageLabel", {
		Name = "Shadow",
		Image = shadowDesc.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowDesc.Slice,
		Position = UDim2.fromOffset(-shadowDesc.Inset, -shadowDesc.Inset + 4),
		Size = UDim2.new(1, shadowDesc.Inset * 2, 1, shadowDesc.Inset * 2),
		BackgroundTransparency = 1,
		Theme = {
			ImageColor3 = "Shadow",
			ImageTransparency = "ShadowTransparency",
		},
		ZIndex = 1,
		Parent = container,
	})

	local modal = Create.New("Frame", {
		Name = "DialogModal",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency or 0.12, 0.03)
			end,
		},
		Corner = 14,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = container,
	})
	Create.GlassStroke(modal, 0.05)

	local glowAsset = Assets.Get("Glow")
	if glowAsset and Assets.Available then
		Create.New("ImageLabel", {
			Name = "Glow",
			Image = glowAsset,
			Size = UDim2.fromOffset(260, 260),
			Position = UDim2.fromOffset(-95, -95),
			BackgroundTransparency = 1,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = modal,
		})
	end

	local noiseAsset = Assets.Get("Noise")
	if noiseAsset and Assets.Available then
		Create.New("ImageLabel", {
			Name = "Noise",
			Image = noiseAsset,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(128, 128),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Theme = { ImageTransparency = "NoiseTransparency" },
			ZIndex = 1,
			Parent = modal,
		})
	end

	local inner = Create.New("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = 18,
		ZIndex = 2,
		Parent = modal,
	})
	Create.List(inner, { Gap = 12 })

	-- Header row
	local header = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = inner,
	})
	Create.List(header, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 10,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local hasIcon = false
	if options.Icon then
		local iconBadge = Create.New("Frame", {
			Name = "IconBadge",
			Size = UDim2.fromOffset(34, 34),
			Corner = 9,
			Theme = { BackgroundColor3 = "Accent" },
			BackgroundTransparency = 0.86,
			LayoutOrder = 1,
			Parent = header,
		})
		Create.Stroke(iconBadge, { Theme = { Color = "Accent" }, Transparency = 0.72 })
		local iconInst = Icons.Create(options.Icon, {
			Size = UDim2.fromOffset(17, 17),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Color = "Accent",
			Parent = iconBadge,
		})
		if iconInst then
			hasIcon = true
		else
			iconBadge:Destroy()
		end
	end

	local titleLabel = Create.Text({
		Name = "Title",
		Text = tostring(options.Title or "Confirm"),
		Font = "SemiBold",
		TextSize = 15,
		Color = "Text",
		Size = UDim2.new(1, hasIcon and -44 or 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = header,
	})

	local bodyText = options.Content or options.Description or options.Message
	if bodyText ~= nil and tostring(bodyText) ~= "" then
		Create.Text({
			Name = "Content",
			Text = tostring(bodyText),
			Font = "Regular",
			TextSize = 13,
			Color = "SubText",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 2,
			Parent = inner,
		})
	end

	-- Optional Input field
	local inputBox
	if options.Input then
		local inputOpts = type(options.Input) == "table" and options.Input
			or { Placeholder = type(options.Input) == "string" and options.Input or "Enter value..." }

		local inputWrap = Create.New("Frame", {
			Name = "InputWrap",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			Parent = inner,
		})
		Create.List(inputWrap, { Gap = 6 })

		if inputOpts.Label and inputOpts.Label ~= "" then
			Create.Text({
				Text = tostring(inputOpts.Label),
				Font = "Medium",
				TextSize = 12,
				Color = "SubText",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 1,
				Parent = inputWrap,
			})
		end

		local field = Create.New("Frame", {
			Name = "Field",
			Size = UDim2.new(1, 0, 0, 36),
			Corner = 8,
			Theme = { BackgroundColor3 = "Field" },
			LayoutOrder = 2,
			Parent = inputWrap,
		})
		local fieldStroke = Create.Stroke(field, {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
		})

		local isMasked = inputOpts.Mask == true or inputOpts.Password == true
		local showMasked = isMasked

		inputBox = Create.New("TextBox", {
			Name = "Input",
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, isMasked and -42 or -20, 1, 0),
			Text = tostring(inputOpts.Default or ""),
			PlaceholderText = tostring(inputOpts.Placeholder or "Type here..."),
			TextSize = 13,
			Font = "Regular",
			Theme = {
				TextColor3 = "Text",
				PlaceholderColor3 = "Muted",
			},
			Parent = field,
		})

		if isMasked then
			local maskOverlay = Create.Text({
				Name = "MaskOverlay",
				Position = inputBox.Position,
				Size = inputBox.Size,
				Text = string.rep("●", #inputBox.Text),
				Font = "SemiBold",
				TextSize = 11,
				Color = "Text",
				TextTruncate = Enum.TextTruncate.AtEnd,
				Visible = showMasked,
				ZIndex = inputBox.ZIndex + 1,
				Parent = field,
			})
			local function syncMask()
				maskOverlay.Text = string.rep("●", #inputBox.Text)
				maskOverlay.Visible = showMasked and inputBox.Text ~= ""
				inputBox.TextTransparency = (showMasked and inputBox.Text ~= "") and 1 or 0
			end
			maid:Give(inputBox:GetPropertyChangedSignal("Text"):Connect(syncMask))

			local eyeBtn = Create.New("TextButton", {
				Name = "MaskToggle",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.fromOffset(24, 24),
				Text = "",
				Corner = 6,
				BackgroundTransparency = 1,
				Parent = field,
			})
			local eyeIcon = Icons.Create("eye-off", {
				Size = UDim2.fromOffset(14, 14),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Color = "SubText",
				Parent = eyeBtn,
			})
			maid:Give(eyeBtn.Activated:Connect(function()
				showMasked = not showMasked
				if eyeIcon then
					Icons.Set(eyeIcon, showMasked and "eye-off" or "eye")
				end
				syncMask()
			end))
			syncMask()
		end

		if inputOpts.Numeric then
			maid:Give(inputBox:GetPropertyChangedSignal("Text"):Connect(function()
				local filtered = inputBox.Text:gsub("[^%d%.%-]", "")
				if filtered ~= inputBox.Text then
					inputBox.Text = filtered
				end
			end))
		end

		maid:Give(inputBox.Focused:Connect(function()
			Theme.Bind(fieldStroke, { Color = "Accent" })
			Tween.Play(fieldStroke, { Transparency = 0.25 }, Tween.Fast)
		end))

		maid:Give(inputBox.FocusLost:Connect(function()
			Theme.Bind(fieldStroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
		end))
	end

	-- Buttons row
	local buttonDefs = (type(options.Buttons) == "table" and #options.Buttons > 0)
		and options.Buttons
		or { { Title = "OK", Variant = "Primary" } }

	local btnRow = Create.New("Frame", {
		Name = "Buttons",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = inner,
	})
	Create.List(btnRow, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 8,
		HAlign = Enum.HorizontalAlignment.Right,
		Wraps = true,
	})

	local controller = {
		Frame = container,
		Modal = modal,
		InputBox = inputBox,
		TitleLabel = titleLabel,
		Shadow = shadow,
	}

	function controller:Close()
		if closed then
			return
		end
		closed = true
		backdrop.Active = false
		backdrop:SetAttribute("_BaliClosing", true)
		Tween.Play(backdrop, { BackgroundTransparency = 1 }, Tween.Fast)
		Transition.Unmount(container, 0.94, function()
			maid:Clean()
			if type(options.OnClose) == "function" then
				Util.Spawn(options.OnClose)
			end
		end)
	end

	local primaryAction
	for index, def in ipairs(buttonDefs) do
		local variant = def.Variant
		if not variant then
			if def.Primary then
				variant = "Primary"
			elseif def.Danger then
				variant = "Danger"
			else
				variant = "Default"
			end
		end

		local btnTitle = tostring(def.Title or def.Text or "Button")
		local btn = Create.New("TextButton", {
			Name = "DialogBtn_" .. index,
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "",
			AutoButtonColor = false,
			ClipsDescendants = true,
			Corner = 9,
			Padding = { 0, 14, 0, 14 },
			LayoutOrder = index,
			Parent = btnRow,
		})
		local sizeMin = Instance.new("UISizeConstraint")
		sizeMin.MinSize = Vector2.new(74, 34)
		sizeMin.Parent = btn

		local btnStroke = Create.Stroke(btn, { Thickness = 1 })
		local btnContent = Create.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = btn,
		})
		Create.List(btnContent, {
			Direction = Enum.FillDirection.Horizontal,
			Gap = 6,
			HAlign = Enum.HorizontalAlignment.Center,
			VAlign = Enum.VerticalAlignment.Center,
		})

		local btnLabel = Create.Text({
			Text = btnTitle,
			Font = (variant == "Primary") and "SemiBold" or "Medium",
			TextSize = 13,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 2,
			Parent = btnContent,
		})

		local resolvedIcon = def.Icon
		if resolvedIcon == nil then
			local lower = string.lower(btnTitle)
			if lower == "cancel" or lower == "close" or lower == "dismiss" or lower == "no" then
				resolvedIcon = "x"
			elseif variant == "Danger" then
				resolvedIcon = "trash"
			elseif variant == "Primary" then
				resolvedIcon = "check"
			end
		end

		if resolvedIcon and resolvedIcon ~= false then
			Icons.Create(resolvedIcon, {
				Size = UDim2.fromOffset(14, 14),
				Color = (variant == "Primary") and "AccentText" or (variant == "Danger" and "Error" or "Text"),
				LayoutOrder = 1,
				Parent = btnContent,
			})
		end

		local grad = applyButtonStyle(btn, btnStroke, btnLabel, variant)
		if grad then
			maid:Give(Theme.Changed:Connect(function(theme)
				grad.Color = Theme.AccentSequence(theme)
			end))
		end

		if variant == "Default" then
			Transition.Hover(btn, btn, "Tile", "TileHover", btnStroke)
		end

		local function trigger(input)
			if closed then
				return
			end
			Transition.Ripple(btn, input, variant == "Primary" and "AccentText" or "Accent")
			local value = inputBox and inputBox.Text or nil
			if def.CloseOnClick ~= false then
				controller:Close()
			end
			if type(def.Callback) == "function" then
				Util.Spawn(def.Callback, value)
			end
		end

		if not primaryAction and variant == "Primary" then
			primaryAction = trigger
		end

		maid:Give(btn.Activated:Connect(function(input)
			trigger(input)
		end))
	end

	if inputBox then
		maid:Give(inputBox.FocusLost:Connect(function(enterPressed)
			if enterPressed and primaryAction and not closed then
				primaryAction()
			end
		end))
	end

	if options.Dismissible ~= false then
		maid:Give(backdrop.Activated:Connect(function()
			controller:Close()
		end))
		maid:Give(Services.UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				controller:Close()
			end
		end))
	end

	local targetOverlayTrans = math.max(0.32, (Theme.Current.OverlayTransparency or 0.56) - 0.14)
	Tween.Play(backdrop, { BackgroundTransparency = targetOverlayTrans }, Tween.Fast)
	maid:Give(Theme.Changed:Connect(function(theme)
		if not closed then
			backdrop.BackgroundTransparency = math.max(0.32, (theme.OverlayTransparency or 0.56) - 0.14)
		end
	end))
	Transition.Mount(container, 0.94)

	return controller
end

return Dialog
