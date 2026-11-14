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
local TOAST_MAX_WIDTH = 336

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
		Gap = 10,
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
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ClipsDescendants = true,
		BackgroundTransparency = 1,
		LayoutOrder = noteId,
		ZIndex = 401,
	})

	local card = Create.New("Frame", {
		Name = "Card",
		Parent = wrapper,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Corner = 12,
		ClipsDescendants = true,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.06)
			end,
		},
		ZIndex = 402,
	})
	Create.GlassStroke(card, 0.06)

	local glowId = Assets.Get("Glow")
	local glowImg = nil
	if glowId then
		glowImg = Create.New("ImageLabel", {
			Name = "Glow",
			Parent = card,
			Size = UDim2.fromScale(0.75, 1.5),
			Position = UDim2.fromScale(-0.22, -0.32),
			Image = glowId,
			ScaleType = Enum.ScaleType.Stretch,
			Theme = {
				ImageColor3 = typeMeta.ColorKey,
				ImageTransparency = function(t)
					return math.min(t.GlowTransparency + 0.04, 0.94)
				end,
			},
			ZIndex = 402,
		})
	end

	local noiseId = Assets.Get("Noise")
	if noiseId then
		Create.New("ImageLabel", {
			Name = "Noise",
			Parent = card,
			Size = UDim2.fromScale(1, 1),
			Image = noiseId,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(128, 128),
			Theme = {
				ImageColor3 = "Stroke",
				ImageTransparency = "NoiseTransparency",
			},
			ZIndex = 402,
		})
	end

	-- Left vertical accent bar removed in favor of modern icon-badge silhouette

	local body = Create.New("Frame", {
		Name = "Body",
		Parent = card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 12, 12, 14, 14 },
		ZIndex = 404,
	})
	Create.List(body, { Direction = Enum.FillDirection.Vertical, Gap = 6 })

	local header = Create.New("Frame", {
		Name = "Header",
		Parent = body,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 405,
	})

	local iconBadge = Create.New("Frame", {
		Name = "IconBadge",
		Parent = header,
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(0, 0),
		Corner = 7,
		BackgroundTransparency = 0.84,
		Theme = { BackgroundColor3 = typeMeta.ColorKey },
		ZIndex = 406,
	})

	local iconObj = Icons.Create(opts.Icon or typeMeta.Icon, {
		Size = UDim2.fromOffset(13, 13),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = typeMeta.ColorKey,
		ZIndex = 407,
		Parent = iconBadge,
	})

	local titleLabel = Create.Text({
		Name = "Title",
		Parent = header,
		Position = UDim2.fromOffset(30, 2),
		Size = UDim2.new(1, -56, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = titleText,
		TextWrapped = true,
		Font = "SemiBold",
		TextSize = 13,
		Color = "Text",
		ZIndex = 406,
	})

	local closeBtn = Create.New("TextButton", {
		Name = "Close",
		Parent = header,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(22, 22),
		Corner = 6,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "TileHover" },
		Text = "",
		ZIndex = 406,
	})
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
		Tween.Play(closeBtn, { BackgroundTransparency = 0.2, BackgroundColor3 = Theme.Current.TileHover }, Tween.Fast)
		Icons.SetColor(closeIcon, "Text")
	end))
	toastMaid:Give(closeBtn.MouseLeave:Connect(function()
		Tween.Play(closeBtn, { BackgroundTransparency = 1 }, Tween.Fast)
		Icons.SetColor(closeIcon, "Muted")
	end))

	local descLabel = Create.Text({
		Name = "Description",
		Parent = body,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = bodyText,
		TextWrapped = true,
		Font = "Regular",
		TextSize = 12,
		Color = "SubText",
		Visible = bodyText ~= "",
		LayoutOrder = 2,
		ZIndex = 405,
	})

	local actionsRow = nil
	if type(opts.Actions) == "table" and #opts.Actions > 0 then
		actionsRow = Create.New("Frame", {
			Name = "Actions",
			Parent = body,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
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
					Size = UDim2.fromOffset(0, 26),
					AutomaticSize = Enum.AutomaticSize.X,
					Corner = 7,
					Padding = { 0, 10, 0, 10 },
					LayoutOrder = idx,
					Text = tostring(action.Title or "Action"),
					TextXAlignment = Enum.TextXAlignment.Center,
					Font = "SemiBold",
					TextSize = 11,
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
		Size = UDim2.new(1, -24, 0, 2),
		Corner = 999,
		ClipsDescendants = true,
		BackgroundTransparency = 0.85,
		Theme = { BackgroundColor3 = "Stroke" },
		ZIndex = 405,
	})

	local progressFill = Create.New("Frame", {
		Name = "Fill",
		Parent = progressTrack,
		Size = UDim2.fromScale(1, 1),
		Theme = { BackgroundColor3 = typeMeta.ColorKey },
		ZIndex = 406,
	})

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
			local isLeft = currentPosition == "BottomLeft" or currentPosition == "TopLeft"
			local slideOutX = isLeft and -48 or 48
			if wrapper and wrapper.Parent then
				local h = math.max(wrapper.AbsoluteSize.Y, card.AbsoluteSize.Y)
				wrapper.AutomaticSize = Enum.AutomaticSize.None
				wrapper.Size = UDim2.new(1, 0, 0, h)
				Tween.Play(wrapper, { Size = UDim2.new(1, 0, 0, 0) }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
			Tween.Play(card, { Position = UDim2.fromOffset(slideOutX, 0) }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Transition.Unmount(card, 1, finalize, { NoPositionTween = true })
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
			Theme.Bind(progressFill, { BackgroundColor3 = typeMeta.ColorKey })
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
	local isLeft = currentPosition == "BottomLeft" or currentPosition == "TopLeft"
	local slideInX = isLeft and -48 or 48
	Transition.SlideFade(card, 0, slideInX)
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
