--[[
	Bali UI · Systems/Notification
	Apple-inspired obsidian glass toast stack with radial glow, AutomaticSize.Y wrapping,
	hover-to-pause linear progress bar, action pills, and unread history tracking.
]]

local Services = require("Core/Services")
local Signal = require("Core/Signal")
local Maid = require("Core/Maid")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Util = require("Core/Util")

local MAX_VISIBLE = 5
local MAX_HISTORY = 50
local DEFAULT_DURATION = 4.5
local TOAST_MAX_WIDTH = 296
local TOAST_MIN_HEIGHT = 76

local Notification = {
	History = {},
	UnreadCount = 0,
	Changed = Signal.new(),
}

local rootMaid = Maid.new()
local layer = nil
local container = nil
local listLayout = nil
local currentPosition = "BottomRight"
local activeToasts = {}
local idCounter = 0

local TYPE_STYLE = {
	Info = { ColorKey = "Info", Icon = "info" },
	Success = { ColorKey = "Success", Icon = "circle-check" },
	Warning = { ColorKey = "Warning", Icon = "triangle-alert" },
	Error = { ColorKey = "Error", Icon = "circle-x" },
	Accent = { ColorKey = "Accent", Icon = "sparkles" },
}

local function getTypeMeta(kind)
	return TYPE_STYLE[kind] or TYPE_STYLE.Info
end

local function getViewportWidth()
	if layer and layer.AbsoluteSize.X > 0 then
		return layer.AbsoluteSize.X
	end
	local cam = Services.Workspace.CurrentCamera
	return cam and cam.ViewportSize.X or 1280
end

local function computeWidth()
	return math.max(220, math.min(TOAST_MAX_WIDTH, getViewportWidth() - 24))
end

local function applyPositionLayout()
	if not container or not listLayout then
		return
	end

	local pos = currentPosition
	local width = computeWidth()
	local isTop = pos == "TopRight" or pos == "TopLeft"
	local isLeft = pos == "BottomLeft" or pos == "TopLeft"

	container.Size = UDim2.new(0, width, 1, -32)
	if isTop and isLeft then
		container.AnchorPoint = Vector2.new(0, 0)
		container.Position = UDim2.fromOffset(16, 16)
	elseif isTop then
		container.AnchorPoint = Vector2.new(1, 0)
		container.Position = UDim2.new(1, -16, 0, 16)
	elseif isLeft then
		container.AnchorPoint = Vector2.new(0, 1)
		container.Position = UDim2.new(0, 16, 1, -16)
	else
		container.AnchorPoint = Vector2.new(1, 1)
		container.Position = UDim2.new(1, -16, 1, -16)
	end

	listLayout.VerticalAlignment = isTop and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom
	listLayout.HorizontalAlignment = isLeft and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right
end

local function ensureContainer()
	if container and container.Parent then
		return true
	end
	if not layer or not layer.Parent then
		return false
	end

	container = Create.New("Frame", {
		Name = "BaliNotificationStack",
		Parent = layer,
		BackgroundTransparency = 1,
		ZIndex = 400,
	})

	listLayout = Create.List(container, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 8,
	})

	applyPositionLayout()

	rootMaid:Give(layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyPositionLayout()
	end))

	return true
end

function Notification.Init(targetLayer)
	if layer == targetLayer and container and container.Parent then
		return Notification
	end

	-- Migrate existing active toast container seamlessly to the new host layer
	if container and container.Parent and targetLayer and targetLayer.Parent then
		rootMaid:Clean()
		layer = targetLayer
		container.Parent = targetLayer
		applyPositionLayout()
		rootMaid:Give(layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			applyPositionLayout()
		end))
		return Notification
	end

	for index = #activeToasts, 1, -1 do
		local toast = activeToasts[index]
		if toast and toast.Dismiss then
			toast.Dismiss(true)
		end
	end
	table.clear(activeToasts)

	if container then
		container:Destroy()
		container = nil
		listLayout = nil
	end
	rootMaid:Clean()

	layer = targetLayer
	ensureContainer()
	return Notification
end

function Notification.SetPosition(position)
	if position ~= "BottomRight" and position ~= "TopRight" and position ~= "BottomLeft" and position ~= "TopLeft" then
		return
	end
	currentPosition = position
	applyPositionLayout()
end

function Notification.MarkAllRead()
	local changed = Notification.UnreadCount > 0
	for _, item in ipairs(Notification.History) do
		if not item.Read then
			item.Read = true
			changed = true
		end
	end
	Notification.UnreadCount = 0
	if changed then
		Notification.Changed:Fire()
	end
end

function Notification.ClearHistory()
	table.clear(Notification.History)
	Notification.UnreadCount = 0
	Notification.Changed:Fire()
end

function Notification.SetDefaultDuration(seconds)
	local num = tonumber(seconds)
	if num ~= nil then
		DEFAULT_DURATION = Util.Clamp(num, 1, 30)
	end
	return DEFAULT_DURATION
end

function Notification.GetDefaultDuration()
	return DEFAULT_DURATION
end

function Notification.Notify(opts)
	opts = Util.Options(opts, {
		Title = "Notification",
		Duration = DEFAULT_DURATION,
		Type = "Info",
	}, "Content")

	idCounter += 1
	local noteId = idCounter
	local noteType = TYPE_STYLE[opts.Type] and opts.Type or "Info"
	local titleText = tostring(opts.Title or "Notification")
	local bodyText = opts.Content or opts.Description or ""
	bodyText = bodyText ~= nil and tostring(bodyText) or ""

	local historyEntry = {
		Id = noteId,
		Title = titleText,
		Content = bodyText,
		Type = noteType,
		Icon = opts.Icon,
		Timestamp = os.time(),
		TimeText = os.date("%H:%M"),
		Read = false,
	}
	table.insert(Notification.History, 1, historyEntry)
	if #Notification.History > MAX_HISTORY then
		table.remove(Notification.History, #Notification.History)
	end
	Notification.UnreadCount += 1
	Notification.Changed:Fire()

	if not ensureContainer() then
		local noop = {}
		function noop.Dismiss() end
		function noop.Update() end
		return noop
	end

	-- Evict oldest visible toast when stack hits MAX_VISIBLE
	while #activeToasts >= MAX_VISIBLE do
		local oldest = activeToasts[1]
		if oldest then
			oldest.Dismiss(true)
		else
			table.remove(activeToasts, 1)
		end
	end

	local toastMaid = Maid.new()
	local dismissed = false
	local typeMeta = getTypeMeta(noteType)
	local dismiss

	local wrapper = Create.New("Frame", {
		Name = "Toast_" .. tostring(noteId),
		Parent = container,
		Size = UDim2.new(1, 0, 0, TOAST_MIN_HEIGHT + 2),
		AutomaticSize = Enum.AutomaticSize.None,
		ClipsDescendants = false,
		BackgroundTransparency = 1,
		LayoutOrder = noteId,
		ZIndex = 401,
	})

	local cardShell = Create.New("Frame", {
		Name = "CardShell",
		Parent = wrapper,
		Size = UDim2.new(1, 0, 0, TOAST_MIN_HEIGHT + 2),
		AutomaticSize = Enum.AutomaticSize.None,
		ClipsDescendants = false,
		BackgroundTransparency = 1,
		ZIndex = 401,
	})

	local shadowDesc = Assets.Shadow()
	local shadowInset = shadowDesc.Inset or 24
	Create.New("ImageLabel", {
		Name = "Shadow",
		Parent = cardShell,
		Image = shadowDesc.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowDesc.Slice,
		Position = UDim2.fromOffset(-shadowInset, -shadowInset + 4),
		Size = UDim2.new(1, shadowInset * 2, 1, shadowInset * 2),
		BackgroundTransparency = 1,
		Theme = {
			ImageColor3 = "Shadow",
			ImageTransparency = "ShadowTransparency",
		},
		ZIndex = 401,
	})

	local card = Create.New("Frame", {
		Name = "Card",
		Parent = cardShell,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Corner = 14,
		ClipsDescendants = true,
		BackgroundTransparency = 0.08,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.clamp((t.CardTransparency or 0.06) + 0.04, 0.06, 0.14)
			end,
		},
		ZIndex = 402,
	})
	local cardMinConst = Instance.new("UISizeConstraint")
	cardMinConst.MinSize = Vector2.new(0, TOAST_MIN_HEIGHT)
	cardMinConst.Parent = card
	Create.GlassStroke(card, 0.12)

	local glassSheen = Create.New("Frame", {
		Name = "GlassSheen",
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		Corner = 14,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.94,
		ZIndex = 402,
	})
	local sheenGrad = Instance.new("UIGradient")
	sheenGrad.Rotation = 125
	sheenGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	sheenGrad.Parent = glassSheen

	local noiseId = Assets.Get("Noise")
	if noiseId then
		Create.New("ImageLabel", {
			Name = "Noise",
			Parent = card,
			Size = UDim2.fromScale(1, 1),
			Corner = 14,
			Image = noiseId,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(128, 128),
			ImageTransparency = 0.965,
			ZIndex = 402,
		})
	end

	local glowId = Assets.Get("Glow")
	local glowImg = nil
	if glowId then
		glowImg = Create.New("ImageLabel", {
			Name = "Glow",
			Parent = card,
			Size = UDim2.new(0, 185, 1, 0),
			Position = UDim2.fromOffset(-14, 0),
			Corner = 14,
			Image = glowId,
			ScaleType = Enum.ScaleType.Stretch,
			Theme = {
				ImageColor3 = typeMeta.ColorKey,
				ImageTransparency = function(t)
					return math.min((t.GlowTransparency or 0.82) + 0.02, 0.91)
				end,
			},
			ZIndex = 402,
		})
	end

	local accentBar = Create.New("Frame", {
		Name = "AccentBar",
		Parent = card,
		Size = UDim2.new(1, -28, 0, 1),
		Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 0.18,
		Corner = UDim.new(1, 0),
		Theme = { BackgroundColor3 = typeMeta.ColorKey },
		ZIndex = 405,
	})
	local barGrad = Instance.new("UIGradient")
	barGrad.Rotation = 0
	barGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.25),
		NumberSequenceKeypoint.new(0.3, 0),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	barGrad.Parent = accentBar

	local body = Create.New("Frame", {
		Name = "Body",
		Parent = card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 14, 14, 16, 14 },
		ZIndex = 404,
	})
	local bodyPad = body:FindFirstChildOfClass("UIPadding")

	local iconBadge = Create.New("Frame", {
		Name = "IconBadge",
		Parent = body,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(0, 2),
		Corner = 11,
		BackgroundTransparency = 0.83,
		Theme = { BackgroundColor3 = typeMeta.ColorKey },
		ZIndex = 406,
	})
	local iconBadgeGrad = Instance.new("UIGradient")
	iconBadgeGrad.Rotation = 90
	iconBadgeGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	iconBadgeGrad.Parent = iconBadge

	local iconStroke = Create.Stroke(iconBadge, {
		Theme = { Color = typeMeta.ColorKey },
		Transparency = 0.45,
		Thickness = 1,
	})
	local iconStrokeGrad = Instance.new("UIGradient")
	iconStrokeGrad.Rotation = 90
	iconStrokeGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	iconStrokeGrad.Parent = iconStroke

	local iconObj = Icons.Create(opts.Icon or typeMeta.Icon, {
		Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = typeMeta.ColorKey,
		ZIndex = 407,
		Parent = iconBadge,
	})

	local contentCol = Create.New("Frame", {
		Name = "ContentCol",
		Parent = body,
		Position = UDim2.fromOffset(52, 0),
		Size = UDim2.new(1, -52, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 405,
	})
	Create.List(contentCol, { Direction = Enum.FillDirection.Vertical, Gap = 5 })

	local header = Create.New("Frame", {
		Name = "Header",
		Parent = contentCol,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 405,
	})

	local titleLabel = Create.Text({
		Name = "Title",
		Parent = header,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -30, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = titleText,
		TextWrapped = true,
		Font = "Bold",
		TextSize = 15,
		LineHeight = 1.12,
		Color = "Text",
		ZIndex = 406,
	})

	local closeBtn = Create.New("TextButton", {
		Name = "Close",
		Parent = header,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 2, 0, -1),
		Size = UDim2.fromOffset(24, 24),
		Corner = 7,
		BackgroundTransparency = 0.78,
		Theme = { BackgroundColor3 = "Tile" },
		Text = "",
		ZIndex = 406,
	})
	Create.GlassStroke(closeBtn, 0.02)
	local closeIcon = Icons.Create("x", {
		Size = UDim2.fromOffset(13, 13),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "Muted",
		ZIndex = 407,
		Parent = closeBtn,
	})

	toastMaid:Give(closeBtn.MouseEnter:Connect(function()
		if Util.IsTouchDevice() then
			return
		end
		Tween.Play(closeBtn, { BackgroundTransparency = 0.25, BackgroundColor3 = Theme.Current.TileHover }, Tween.Fast)
		Icons.SetColor(closeIcon, "Text")
	end))
	toastMaid:Give(closeBtn.MouseLeave:Connect(function()
		Tween.Play(closeBtn, { BackgroundTransparency = 0.78, BackgroundColor3 = Theme.Current.Tile }, Tween.Fast)
		Icons.SetColor(closeIcon, "Muted")
	end))

	local descLabel = Create.Text({
		Name = "Description",
		Parent = contentCol,
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = bodyText,
		TextWrapped = true,
		Font = "Medium",
		TextSize = 13,
		LineHeight = 1.18,
		TextTransparency = 0.05,
		Color = "SubText",
		Visible = bodyText ~= "",
		LayoutOrder = 2,
		ZIndex = 405,
	})

	local actionsRow = nil
	if type(opts.Actions) == "table" and #opts.Actions > 0 then
		if bodyPad then
			bodyPad.PaddingBottom = UDim.new(0, 20)
		end
		actionsRow = Create.New("Frame", {
			Name = "Actions",
			Parent = contentCol,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Padding = { 3, 0, 0, 0 },
			LayoutOrder = 3,
			ZIndex = 405,
		})
		Create.List(actionsRow, {
			Direction = Enum.FillDirection.Horizontal,
			Gap = 6,
			Wraps = true,
		})

		for idx, action in ipairs(opts.Actions) do
			if type(action) == "table" then
				local isPrimary = action.Primary == true
				local btn = Create.New("TextButton", {
					Name = "Action_" .. tostring(idx),
					Parent = actionsRow,
					Size = UDim2.fromOffset(0, 28),
					AutomaticSize = Enum.AutomaticSize.X,
					Corner = 8,
					Padding = { 0, 12, 0, 12 },
					LayoutOrder = idx,
					Text = tostring(action.Title or "Action"),
					TextXAlignment = Enum.TextXAlignment.Center,
					Font = "SemiBold",
					TextSize = 12,
					Theme = isPrimary and {
						BackgroundColor3 = "Accent",
						TextColor3 = "AccentText",
					} or {
						BackgroundColor3 = "Tile",
						TextColor3 = "Text",
					},
					ZIndex = 406,
				})
				if not isPrimary then
					local actionStroke = Create.GlassStroke(btn, 0.02)
					toastMaid:Give(Transition.Hover(btn, btn, "Tile", "TileHover", actionStroke))
				end
				toastMaid:Give(btn.Activated:Connect(function(input)
					Transition.Ripple(btn, input, isPrimary and "AccentText" or "Stroke")
					if action.Callback then
						Util.Spawn(action.Callback)
					end
					if action.Dismiss ~= false and dismiss then
						dismiss(false)
					end
				end))
			end
		end
	end

	local progressTrack = Create.New("Frame", {
		Name = "ProgressTrack",
		Parent = card,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -28, 0, 2),
		Corner = UDim.new(1, 0),
		ClipsDescendants = false,
		BackgroundTransparency = 0.76,
		Theme = { BackgroundColor3 = "Stroke" },
		ZIndex = 405,
	})

	local progressFill = Create.New("Frame", {
		Name = "Fill",
		Parent = progressTrack,
		Size = UDim2.fromScale(1, 1),
		Corner = UDim.new(1, 0),
		BackgroundTransparency = 0.05,
		Theme = { BackgroundColor3 = typeMeta.ColorKey },
		ZIndex = 406,
	})
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Rotation = 0
	fillGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.38),
		NumberSequenceKeypoint.new(0.65, 0.08),
		NumberSequenceKeypoint.new(1, 0),
	})
	fillGrad.Parent = progressFill

	local tipGlow = Create.New("Frame", {
		Name = "TipGlow",
		Parent = progressFill,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(10, 4),
		Corner = UDim.new(1, 0),
		BackgroundTransparency = 0.35,
		Theme = { BackgroundColor3 = typeMeta.ColorKey },
		ZIndex = 407,
	})

	local function syncShellHeight()
		if dismissed then
			return
		end
		local h = math.max(TOAST_MIN_HEIGHT, math.ceil(card.AbsoluteSize.Y))
		if math.abs(wrapper.Size.Y.Offset - h) > 0.5 then
			wrapper.Size = UDim2.new(1, 0, 0, h)
		end
		if math.abs(cardShell.Size.Y.Offset - h) > 0.5 then
			cardShell.Size = UDim2.new(1, 0, 0, h)
		end
	end
	toastMaid:Give(card:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncShellHeight))
	syncShellHeight()

	-- Timer & hover-to-pause state
	local totalDuration = tonumber(opts.Duration)
	if totalDuration == nil then
		totalDuration = opts.Duration == false and 0 or DEFAULT_DURATION
	end
	local remaining = totalDuration
	local isPaused = false
	local runStart = 0
	local progressTween = nil
	local timerToken = 0

	local toast = {}

	local function stopProgressTween()
		timerToken += 1
		if progressTween then
			pcall(function()
				progressTween:Cancel()
			end)
			progressTween = nil
		end
	end

	dismiss = function(immediate)
		if dismissed then
			return
		end
		dismissed = true
		stopProgressTween()

		local index = table.find(activeToasts, toast)
		if index then
			table.remove(activeToasts, index)
		end

		if not historyEntry.Read then
			historyEntry.Read = true
			Notification.UnreadCount = math.max(0, Notification.UnreadCount - 1)
			Notification.Changed:Fire()
		end

		local function finalize()
			toastMaid:Clean()
			if wrapper and wrapper.Parent then
				wrapper:Destroy()
			end
		end

		if immediate or Tween.Reduced then
			finalize()
		else
			local isTop = currentPosition == "TopRight" or currentPosition == "TopLeft"
			local isLeft = currentPosition == "BottomLeft" or currentPosition == "TopLeft"
			local slideOutX = isLeft and -24 or 24
			local slideOutY = isTop and -10 or 10
			if wrapper and wrapper.Parent then
				local h = math.max(wrapper.AbsoluteSize.Y, card.AbsoluteSize.Y)
				wrapper.ClipsDescendants = true
				wrapper.AutomaticSize = Enum.AutomaticSize.None
				wrapper.Size = UDim2.new(1, 0, 0, h)
				Tween.Play(wrapper, { Size = UDim2.new(1, 0, 0, 0) }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
			Tween.Play(cardShell, { Position = UDim2.fromOffset(slideOutX, slideOutY) }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Transition.Unmount(cardShell, 1, finalize, { NoPositionTween = true })
		end
	end

	local function startTimer(durationSec)
		stopProgressTween()
		if dismissed or durationSec <= 0 or durationSec == math.huge then
			progressTrack.Visible = false
			return
		end

		progressTrack.Visible = true
		totalDuration = durationSec
		remaining = durationSec
		progressFill.Size = UDim2.fromScale(1, 1)

		if isPaused then
			return
		end

		timerToken += 1
		local myToken = timerToken
		runStart = os.clock()
		progressTween = Tween.Linear(progressFill, { Size = UDim2.fromScale(0, 1) }, remaining)
		Tween.Then(progressTween, function()
			if not dismissed and timerToken == myToken then
				dismiss(false)
			end
		end)
	end

	local function pauseTimer()
		if dismissed or isPaused or remaining <= 0 or totalDuration <= 0 or totalDuration == math.huge then
			return
		end
		isPaused = true
		local elapsed = os.clock() - runStart
		remaining = math.max(0.05, remaining - elapsed)
		stopProgressTween()
		local ratio = Util.Clamp(remaining / totalDuration, 0, 1)
		progressFill.Size = UDim2.fromScale(ratio, 1)
	end

	local function resumeTimer()
		if dismissed or not isPaused or remaining <= 0 or totalDuration <= 0 or totalDuration == math.huge then
			return
		end
		isPaused = false
		timerToken += 1
		local myToken = timerToken
		runStart = os.clock()
		progressTween = Tween.Linear(progressFill, { Size = UDim2.fromScale(0, 1) }, remaining)
		Tween.Then(progressTween, function()
			if not dismissed and timerToken == myToken then
				dismiss(false)
			end
		end)
	end

	function toast.Dismiss(arg1, arg2)
		local immediate = (arg1 == toast) and (arg2 == true) or (arg1 == true)
		dismiss(immediate)
	end

	function toast.Update(arg1, arg2)
		if dismissed then
			return
		end
		local newOpts = (arg1 == toast) and arg2 or arg1
		if type(newOpts) ~= "table" then
			return
		end

		if newOpts.Title ~= nil then
			titleText = tostring(newOpts.Title)
			titleLabel.Text = titleText
			historyEntry.Title = titleText
		end
		if newOpts.Content ~= nil or newOpts.Description ~= nil then
			bodyText = tostring(newOpts.Content or newOpts.Description or "")
			descLabel.Text = bodyText
			descLabel.Visible = bodyText ~= ""
			historyEntry.Content = bodyText
		end
		if newOpts.Type ~= nil and TYPE_STYLE[newOpts.Type] then
			noteType = newOpts.Type
			typeMeta = getTypeMeta(noteType)
			historyEntry.Type = noteType
			-- Accent styling updated via iconBadge/icon/progressBar below
			Theme.Bind(iconBadge, { BackgroundColor3 = typeMeta.ColorKey })
			Theme.Bind(iconStroke, { Color = typeMeta.ColorKey })
			Theme.Bind(accentBar, { BackgroundColor3 = typeMeta.ColorKey })
			Theme.Bind(progressFill, { BackgroundColor3 = typeMeta.ColorKey })
			Theme.Bind(tipGlow, { BackgroundColor3 = typeMeta.ColorKey })
			Icons.SetColor(iconObj, typeMeta.ColorKey)
			if glowImg then
				Theme.Bind(glowImg, { ImageColor3 = typeMeta.ColorKey })
			end
			if newOpts.Icon == nil then
				Icons.Set(iconObj, typeMeta.Icon)
			end
		end
		if newOpts.Icon ~= nil then
			Icons.Set(iconObj, newOpts.Icon)
			historyEntry.Icon = newOpts.Icon
		end
		if newOpts.Duration ~= nil then
			local newDur = newOpts.Duration == false and 0 or (tonumber(newOpts.Duration) or DEFAULT_DURATION)
			startTimer(newDur)
		end

		syncShellHeight()
		Notification.Changed:Fire()
	end

	toastMaid:Give(closeBtn.Activated:Connect(function(input)
		Transition.Ripple(closeBtn, input)
		dismiss(false)
	end))

	toastMaid:Give(card.MouseEnter:Connect(function()
		if not Util.IsTouchDevice() then
			pauseTimer()
		end
	end))
	toastMaid:Give(card.MouseLeave:Connect(function()
		resumeTimer()
	end))

	toastMaid:Give(wrapper.Destroying:Connect(function()
		if not dismissed then
			dismissed = true
			stopProgressTween()
			local idx = table.find(activeToasts, toast)
			if idx then
				table.remove(activeToasts, idx)
			end
			toastMaid:Clean()
		end
	end))

	table.insert(activeToasts, toast)
	local isTop = currentPosition == "TopRight" or currentPosition == "TopLeft"
	local isLeft = currentPosition == "BottomLeft" or currentPosition == "TopLeft"
	local slideInY = isTop and -18 or 18
	local slideInX = isLeft and -28 or 28
	Transition.SlideFade(cardShell, slideInY, slideInX)
	startTimer(totalDuration)

	return toast
end

function Notification.Destroy()
	for index = #activeToasts, 1, -1 do
		local toast = activeToasts[index]
		if toast and toast.Dismiss then
			toast.Dismiss(true)
		end
	end
	table.clear(activeToasts)
	rootMaid:Clean()
	if container then
		container:Destroy()
		container = nil
		listLayout = nil
	end
	layer = nil
	Notification.ClearHistory()
end

return Notification
