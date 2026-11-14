--[[
	Bali UI · Elements/Base
	Shared element lifecycle, Tile rows, Glass cards, badges, lock overlays, and flash feedback.
]]

local Util = require("Core/Util")
local Signal = require("Core/Signal")
local Maid = require("Core/Maid")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Tooltip = require("Systems/Tooltip")

local Base = {}

local uiByFrame = setmetatable({}, { __mode = "k" })
local tooltipBound = setmetatable({}, { __mode = "k" })

local function bindColor(instance, prop, colorKey, fallback)
	local key = colorKey or fallback or "Accent"
	if typeof(key) == "Color3" then
		Theme.Unbind(instance, prop)
		instance[prop] = key
	else
		Theme.Bind(instance, { [prop] = key })
	end
end

local function resolveColor(colorKey, fallback)
	local key = colorKey or fallback or "Accent"
	if typeof(key) == "Color3" then
		return key
	end
	return Theme.Resolve(key) or Theme.Current.Accent
end

local function bindTooltipOnce(frame, tooltipOpt, maid)
	if not frame or not tooltipOpt or tooltipBound[frame] then
		return
	end
	tooltipBound[frame] = true
	local ok, cleanup = pcall(Tooltip.Bind, frame, tooltipOpt)
	if ok and cleanup ~= nil and maid then
		maid:Give(cleanup)
	end
end

function Base.FlashFrame(frame, stroke, surfaceKey)
	if not frame or not frame.Parent then
		return
	end
	local token = (frame:GetAttribute("_BaliFlashToken") or 0) + 1
	frame:SetAttribute("_BaliFlashToken", token)

	local targetStroke = stroke or frame:FindFirstChildOfClass("UIStroke")
	local accent = Theme.Current.Accent
	local baseBgKey = surfaceKey or frame:GetAttribute("_BaliSurfaceKey") or "Tile"
	local baseBg = Theme.Resolve(baseBgKey) or Theme.Current.Tile
	local hoverBg = Theme.Current.TileHover or baseBg
	local hasBg = frame.BackgroundTransparency < 0.95

	if targetStroke then
		Tween.Play(targetStroke, {
			Color = accent,
			Transparency = 0.05,
			Thickness = 1.8,
		}, Tween.Fast, Enum.EasingStyle.Quad)
	end
	if hasBg and typeof(baseBg) == "Color3" then
		Tween.Play(frame, {
			BackgroundColor3 = Util.LerpColor(hoverBg, accent, 0.16),
		}, Tween.Fast, Enum.EasingStyle.Quad)
	end

	task.delay(Tween.Reduced and 0.05 or 0.36, function()
		if not frame.Parent or frame:GetAttribute("_BaliFlashToken") ~= token then
			return
		end
		if targetStroke and targetStroke.Parent then
			local restTrans = math.max(Theme.Current.StrokeTransparency - 0.02, 0)
			Tween.Play(targetStroke, {
				Color = Theme.Current.Stroke,
				Transparency = restTrans,
				Thickness = 1,
			}, Tween.Smooth, Enum.EasingStyle.Quad)
		end
		if hasBg and frame.Parent then
			local restoreColor = Theme.Resolve(baseBgKey)
			if typeof(restoreColor) == "Color3" then
				Tween.Play(frame, {
					BackgroundColor3 = restoreColor,
				}, Tween.Smooth, Enum.EasingStyle.Quad)
			end
		end
	end)
end

local function createLockOverlay(frame, cornerRadius)
	local overlay = Create.New("Frame", {
		Name = "LockOverlay",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 0.14,
		Theme = { BackgroundColor3 = "Background" },
		Corner = cornerRadius or 10,
		Active = true,
		Visible = false,
		ZIndex = 30,
		Parent = frame,
	})

	local pill = Create.New("Frame", {
		Name = "LockPill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Theme = { BackgroundColor3 = "Card" },
		BackgroundTransparency = 0.04,
		Corner = UDim.new(1, 0),
		Padding = { 4, 10, 4, 10 },
		Stroke = {
			Theme = { Color = "Stroke" },
			Transparency = 0.78,
			Thickness = 1,
		},
		ZIndex = 31,
		Parent = overlay,
	})

	Create.List(pill, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 6,
	})

	Icons.Create("lock", {
		Size = UDim2.fromOffset(12, 12),
		Color = "SubText",
		LayoutOrder = 1,
		ZIndex = 32,
		Parent = pill,
	})

	local textLabel = Create.Text({
		Name = "LockText",
		Text = "Locked",
		Font = "Medium",
		TextSize = 11,
		Color = "SubText",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		ZIndex = 32,
		Parent = pill,
	})

	return overlay, textLabel
end

function Base.Badge(parent, text, colorKey)
	colorKey = colorKey or "Accent"

	local frame = Create.New("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 0.84,
		Corner = UDim.new(1, 0),
		Padding = { 3, 8, 3, 8 },
		Parent = parent,
	})
	bindColor(frame, "BackgroundColor3", colorKey, "Accent")

	local stroke = Create.Stroke(frame, {
		Transparency = 0.72,
		Thickness = 1,
	})
	bindColor(stroke, "Color", colorKey, "Accent")

	local label = Create.Text({
		Name = "Label",
		Text = tostring(text or ""),
		Font = "SemiBold",
		TextSize = 11,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = frame,
	})
	bindColor(label, "TextColor3", colorKey, "Accent")

	local badge = {
		Frame = frame,
		Label = label,
		Stroke = stroke,
	}

	function badge:SetText(newText)
		label.Text = tostring(newText or "")
	end

	function badge:SetColor(newColorKey)
		newColorKey = newColorKey or "Accent"
		bindColor(frame, "BackgroundColor3", newColorKey, "Accent")
		bindColor(stroke, "Color", newColorKey, "Accent")
		bindColor(label, "TextColor3", newColorKey, "Accent")
	end

	return badge
end

function Base.IconBadge(parent, icon, colorKey)
	colorKey = colorKey or "Accent"

	local frame = Create.New("Frame", {
		Name = "IconBadge",
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 0.84,
		Corner = 8,
		Parent = parent,
	})
	bindColor(frame, "BackgroundColor3", colorKey, "Accent")

	local stroke = Create.Stroke(frame, {
		Transparency = 0.74,
		Thickness = 1,
	})
	bindColor(stroke, "Color", colorKey, "Accent")

	local iconObj = Icons.Create(icon or "sparkles", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = colorKey,
		Parent = frame,
	})

	local badge = {
		Frame = frame,
		Icon = iconObj,
		Stroke = stroke,
	}

	function badge:SetIcon(newIcon)
		if iconObj then
			Icons.Set(iconObj, newIcon)
		end
	end

	function badge:SetColor(newColorKey)
		newColorKey = newColorKey or "Accent"
		bindColor(frame, "BackgroundColor3", newColorKey, "Accent")
		bindColor(stroke, "Color", newColorKey, "Accent")
		if iconObj then
			Icons.SetColor(iconObj, newColorKey)
		end
	end

	return badge
end

function Base.Card(parent, options)
	options = options or {}
	local surfaceKey = options.SurfaceKey or "Tile"
	local transKey = options.SurfaceTransparency or "TileTransparency"
	local cornerRadius = options.Corner or 10

	local frame = Create.New("Frame", {
		Name = options.Name or "Card",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = {
			BackgroundColor3 = surfaceKey,
			BackgroundTransparency = transKey,
		},
		Corner = cornerRadius,
		Parent = parent,
	})
	frame:SetAttribute("_BaliSurfaceKey", surfaceKey)

	if options.MinHeight and options.MinHeight > 0 then
		local constraint = Instance.new("UISizeConstraint")
		constraint.MinSize = Vector2.new(0, options.MinHeight)
		constraint.Parent = frame
	end

	local stroke = Create.GlassStroke(frame, options.StrokeStrength or 0.02)

	if options.Padding ~= nil then
		Create.Padding(frame, options.Padding)
	end

	local lockOverlay, lockLabel = createLockOverlay(frame, cornerRadius)
	if options.Padding ~= nil then
		-- Compensate LockOverlay bounds when caller places UIPadding directly on Card.Frame
		local p = options.Padding
		local top, right, bottom, left
		if type(p) == "number" then
			top, right, bottom, left = p, p, p, p
		else
			top = p[1] or 0
			right = p[2] or top
			bottom = p[3] or top
			left = p[4] or right
		end
		lockOverlay.Position = UDim2.fromOffset(-left, -top)
		lockOverlay.Size = UDim2.new(1, left + right, 1, top + bottom)
	end

	local card = {
		Frame = frame,
		Stroke = stroke,
		LockOverlay = lockOverlay,
		_disabled = false,
		_locked = false,
	}

	function card:SetDisabled(disabled)
		card._disabled = (disabled == true)
		for _, desc in ipairs(frame:GetDescendants()) do
			if desc ~= lockOverlay and not desc:IsDescendantOf(lockOverlay) then
				if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
					if desc:GetAttribute("_BaliOrigTextTrans") == nil then
						desc:SetAttribute("_BaliOrigTextTrans", desc.TextTransparency)
					end
					local baseT = desc:GetAttribute("_BaliOrigTextTrans") or 0
					desc.TextTransparency = card._disabled and math.min(baseT + 0.45, 0.78) or baseT
				elseif desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
					if desc:GetAttribute("_BaliOrigImgTrans") == nil then
						desc:SetAttribute("_BaliOrigImgTrans", desc.ImageTransparency)
					end
					local baseT = desc:GetAttribute("_BaliOrigImgTrans") or 0
					desc.ImageTransparency = card._disabled and math.min(baseT + 0.45, 0.78) or baseT
				end
			end
		end
	end

	function card:Lock(reason)
		card._locked = true
		lockLabel.Text = (reason and reason ~= "") and tostring(reason) or "Locked"
		lockOverlay.Visible = true
	end

	function card:Unlock()
		card._locked = false
		lockOverlay.Visible = false
	end

	function card:Flash()
		Base.FlashFrame(frame, stroke, surfaceKey)
	end

	uiByFrame[frame] = card
	return card
end

function Base.Row(parent, options, rightWidth)
	options = options or {}
	rightWidth = rightWidth or 0
	local surfaceKey = options.SurfaceKey or "Tile"
	local transKey = options.SurfaceTransparency or "TileTransparency"
	local cornerRadius = options.Corner or 10

	local frame = Create.New("Frame", {
		Name = options.Name or "Row",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = {
			BackgroundColor3 = surfaceKey,
			BackgroundTransparency = transKey,
		},
		Corner = cornerRadius,
		Parent = parent,
	})
	frame:SetAttribute("_BaliSurfaceKey", surfaceKey)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(0, options.MinHeight or 42)
	constraint.Parent = frame

	local stroke = Create.GlassStroke(frame, options.StrokeStrength or 0.02)

	local body = Create.New("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = options.Padding or { 10, 12, 10, 12 },
		ZIndex = 2,
		Parent = frame,
	})

	local bodyList = Create.List(body, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		HAlign = Enum.HorizontalAlignment.Left,
		Gap = 10,
	})

	local left = Create.New("Frame", {
		Name = "Left",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, rightWidth > 0 and -(rightWidth + 10) or 0, 0, 0),
		Parent = body,
	})

	Create.List(left, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		HAlign = Enum.HorizontalAlignment.Left,
		Gap = 10,
	})

	local iconObj = nil
	local iconBadge = nil
	local iconWidth = 0
	if options.Icon and options.Icon ~= "" and options.Icon ~= false then
		if options.IconBadge == false then
			iconObj = Icons.Create(options.Icon, {
				Size = UDim2.fromOffset(18, 18),
				Color = options.IconColor or "SubText",
				LayoutOrder = 1,
				Parent = left,
			})
			iconWidth = 18
		else
			iconBadge = Base.IconBadge(left, options.Icon, options.IconColor or "Accent")
			iconBadge.Frame.LayoutOrder = 1
			iconObj = iconBadge.Icon
			iconWidth = 30
		end
	end

	local textCol = Create.New("Frame", {
		Name = "TextColumn",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, iconWidth > 0 and -(iconWidth + 10) or 0, 0, 0),
		Parent = left,
	})

	Create.List(textCol, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 2,
	})

	local titleText = tostring(options.Title or options.Name or "")
	local descText = tostring(options.Description or options.Desc or "")

	local titleLabel = Create.Text({
		Name = "Title",
		Text = titleText,
		Font = options.TitleFont or "Medium",
		TextSize = options.TitleSize or 13,
		Color = options.TitleColor or "Text",
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

	local right = Create.New("Frame", {
		Name = "Right",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, rightWidth, 0, 0),
		AutomaticSize = rightWidth > 0 and Enum.AutomaticSize.Y or Enum.AutomaticSize.XY,
		Visible = rightWidth > 0,
		Parent = body,
	})

	local reservedRight = rightWidth
	local rightConstraint = nil
	if reservedRight <= 0 then
		rightConstraint = Instance.new("UISizeConstraint")
		rightConstraint.MaxSize = Vector2.new(9999, 9999)
		rightConstraint.Parent = right
	end

	local function updateLeftInset()
		local hasVisibleChild = false
		if reservedRight <= 0 then
			for _, child in ipairs(right:GetChildren()) do
				if child:IsA("GuiObject") and child.Visible then
					hasVisibleChild = true
					break
				end
			end
		end
		right.Visible = (reservedRight > 0) or hasVisibleChild
		local bodyW = math.floor(body.AbsoluteSize.X)
		local rightLayout = reservedRight <= 0 and right:FindFirstChildOfClass("UIListLayout") or nil
		local naturalRightW = rightLayout and math.ceil(rightLayout.AbsoluteContentSize.X) or math.ceil(right.AbsoluteSize.X)
		local measureW = reservedRight > 0 and reservedRight or naturalRightW
		local actualW = right.Visible and math.max(reservedRight, measureW) or 0
		local availLeft = bodyW - 24 - actualW - 10 - (iconWidth > 0 and (iconWidth + 10) or 0)
		local stackRight = (options.StackRight == true) or (actualW >= 100 and bodyW > 0 and availLeft < 132)
		local compactStack = stackRight and (reservedRight > 0 and reservedRight < 130 or (reservedRight <= 0 and actualW > 0 and actualW < 130))

		if rightConstraint then
			if stackRight or bodyW <= 180 or titleText == "" then
				rightConstraint.MaxSize = Vector2.new(9999, 9999)
			else
				local maxR = math.max(96, bodyW - math.max(132, math.floor(bodyW * 0.44)) - 10)
				rightConstraint.MaxSize = Vector2.new(maxR, 9999)
			end
		end

		if stackRight and right.Visible then
			bodyList.FillDirection = Enum.FillDirection.Vertical
			bodyList.VerticalAlignment = Enum.VerticalAlignment.Top
			bodyList.HorizontalAlignment = compactStack and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
			bodyList.Padding = UDim.new(0, 8)
			left.Size = UDim2.new(1, 0, 0, 0)
			if compactStack then
				right.Size = UDim2.new(0, math.max(reservedRight, actualW), 0, 0)
			else
				right.Size = UDim2.new(1, 0, 0, 0)
			end
			right.AutomaticSize = Enum.AutomaticSize.Y
		else
			bodyList.FillDirection = Enum.FillDirection.Horizontal
			bodyList.VerticalAlignment = Enum.VerticalAlignment.Center
			bodyList.HorizontalAlignment = Enum.HorizontalAlignment.Left
			bodyList.Padding = UDim.new(0, 10)
			right.Size = UDim2.new(0, reservedRight, 0, 0)
			right.AutomaticSize = reservedRight > 0 and Enum.AutomaticSize.Y or Enum.AutomaticSize.XY
			left.Size = UDim2.new(1, actualW > 0 and -(actualW + 10) or 0, 0, 0)
		end
	end

	right.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			child:GetPropertyChangedSignal("Visible"):Connect(updateLeftInset)
		end
		task.defer(updateLeftInset)
	end)

	right:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLeftInset)
	body:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLeftInset)

	local lockOverlay, lockLabel = createLockOverlay(frame, cornerRadius)

	local row = {
		Frame = frame,
		Body = body,
		Left = left,
		Right = right,
		TextColumn = textCol,
		TitleLabel = titleLabel,
		DescLabel = descLabel,
		IconObj = iconObj,
		IconBadge = iconBadge,
		Stroke = stroke,
		LockOverlay = lockOverlay,
		_disabled = false,
		_locked = false,
	}

	function row:SetRightWidth(w)
		reservedRight = math.max(w or 0, 0)
		right.Size = UDim2.new(0, reservedRight, 0, 0)
		right.AutomaticSize = reservedRight > 0 and Enum.AutomaticSize.Y or Enum.AutomaticSize.XY
		right.Visible = reservedRight > 0 or (#right:GetChildren() > 0)
		updateLeftInset()
	end

	function row:SetTitle(s)
		local text = tostring(s or "")
		titleLabel.Text = text
		titleLabel.Visible = (text ~= "")
	end

	function row:SetDesc(s)
		local text = tostring(s or "")
		descLabel.Text = text
		descLabel.Visible = (text ~= "")
	end

	function row:SetDisabled(disabled)
		row._disabled = (disabled == true)
		local targetTextTrans = row._disabled and 0.48 or 0
		titleLabel.TextTransparency = targetTextTrans
		descLabel.TextTransparency = targetTextTrans
		if iconObj then
			iconObj[Icons.TransparencyProperty(iconObj)] = row._disabled and 0.48 or 0
		end
		if iconBadge then
			iconBadge.Frame.BackgroundTransparency = row._disabled and 0.92 or 0.84
		end
	end

	function row:Lock(reason)
		row._locked = true
		lockLabel.Text = (reason and reason ~= "") and tostring(reason) or "Locked"
		lockOverlay.Visible = true
	end

	function row:Unlock()
		row._locked = false
		lockOverlay.Visible = false
	end

	function row:Flash()
		Base.FlashFrame(frame, stroke, surfaceKey)
	end

	uiByFrame[frame] = row
	return row
end

function Base.New(typeName, parent, options, ctx)
	options = Util.Options(options, {}, "Title")
	ctx = ctx or {}

	local title = tostring(options.Title or options.Name or "")
	local desc = tostring(options.Description or options.Desc or options.Content or "")

	local element = {
		Type = typeName,
		Flag = options.Flag,
		Title = title,
		Desc = desc,
		Frame = nil,
		Value = options.Default,
		Changed = Signal.new(),
		Maid = Maid.new(),
		Tab = ctx.Tab,
		SubTab = ctx.SubTab,
		Section = ctx.Section,
		Options = options,
		IgnoreConfig = (options.IgnoreConfig == true),
		Disabled = false,
		Locked = false,
		Visible = options.Visible ~= false,
		_destroyed = false,
		_ui = nil,
		_lockReason = nil,
	}

	local function getUI()
		if element._ui then
			return element._ui
		end
		if element.Frame then
			return uiByFrame[element.Frame]
		end
		return nil
	end

	function element:BindUI(ui)
		self._ui = ui
		if type(ui) == "table" and ui.Frame then
			self.Frame = ui.Frame
		elseif typeof(ui) == "Instance" then
			self.Frame = ui
		end
		if self.Frame then
			if self.Visible == false then
				self.Frame.Visible = false
			end
			if options.Tooltip then
				bindTooltipOnce(self.Frame, options.Tooltip, self.Maid)
			end
		end
		local resolvedUI = getUI()
		if resolvedUI then
			if self.Disabled and type(resolvedUI.SetDisabled) == "function" then
				resolvedUI:SetDisabled(true)
			end
			if self.Locked and type(resolvedUI.Lock) == "function" then
				resolvedUI:Lock(self._lockReason)
			end
		end
		return self
	end

	function element:SetTitle(s)
		local text = tostring(s or "")
		self.Title = text
		if self._record then
			self._record.Title = text
		end
		local ui = getUI()
		if ui and type(ui.SetTitle) == "function" then
			ui:SetTitle(text)
		elseif ui and ui.TitleLabel then
			ui.TitleLabel.Text = text
			ui.TitleLabel.Visible = (text ~= "")
		end
	end

	function element:SetDesc(s)
		local text = tostring(s or "")
		self.Desc = text
		if self._record then
			self._record.Desc = text
		end
		local ui = getUI()
		if ui and type(ui.SetDesc) == "function" then
			ui:SetDesc(text)
		elseif ui and ui.DescLabel then
			ui.DescLabel.Text = text
			ui.DescLabel.Visible = (text ~= "")
		end
	end

	function element:SetVisible(b)
		local visible = (b ~= false)
		self.Visible = visible
		if self.Frame then
			self.Frame.Visible = visible
		end
	end

	function element:SetDisabled(b)
		local disabled = (b == true)
		self.Disabled = disabled
		local ui = getUI()
		if ui and type(ui.SetDisabled) == "function" then
			ui:SetDisabled(disabled)
		end
		if type(self._onDisabled) == "function" then
			self._onDisabled(disabled)
		end
	end

	function element:Lock(reason)
		self.Locked = true
		self._lockReason = reason
		local ui = getUI()
		if ui and type(ui.Lock) == "function" then
			ui:Lock(reason)
		end
		if type(self._onLocked) == "function" then
			self._onLocked(true, reason)
		end
	end

	function element:Unlock()
		self.Locked = false
		self._lockReason = nil
		local ui = getUI()
		if ui and type(ui.Unlock) == "function" then
			ui:Unlock()
		end
		if type(self._onLocked) == "function" then
			self._onLocked(false, nil)
		end
	end

	function element:Flash()
		local ui = getUI()
		if ui and type(ui.Flash) == "function" then
			ui:Flash()
		elseif self.Frame then
			Base.FlashFrame(self.Frame)
		end
	end

	function element:OnChanged(fn)
		if type(fn) ~= "function" then
			return nil
		end
		local conn = self.Changed:Connect(fn)
		self.Maid:Give(conn)
		return conn
	end

	function element:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		self.Maid:Clean()
		self.Changed:Destroy()
		if self.Frame and self.Frame.Parent then
			self.Frame:Destroy()
		end
		self.Frame = nil
		self._ui = nil
	end

	-- Support callers that assign element.Frame directly without calling :BindUI
	if options.Tooltip or options.Visible == false then
		task.defer(function()
			if element._destroyed or not element.Frame then
				return
			end
			if options.Visible == false then
				element.Frame.Visible = false
			end
			if options.Tooltip then
				bindTooltipOnce(element.Frame, options.Tooltip, element.Maid)
			end
		end)
	end

	if ctx.Maid then
		ctx.Maid:Give(element)
	end

	local record = {
		Type = element.Type,
		Title = element.Title,
		Desc = element.Desc,
		Flag = element.Flag,
		Tab = element.Tab,
		SubTab = element.SubTab,
		Section = element.Section,
		Element = element,
	}
	element._record = record
	if type(ctx.RegisterElement) == "function" then
		ctx.RegisterElement(record)
	end

	return element
end

return Base
