--[[
	Bali UI · Window/Loader
	Glassmorphic LoadingScreen splash and KeySystem verification modal with
	Get Key clipboard copy, Check Key verification, error shake, and saved key support.
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

local Loader = {}

local function createBackdropAndCard(parentGui, maid, maxWidth, withOverlay)
	local root = Create.New("Frame", {
		Name = "LoaderOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 250,
		Parent = parentGui,
	})
	maid:Give(root)

	local backdrop
	if withOverlay then
		backdrop = Create.New("TextButton", {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			Text = "",
			AutoButtonColor = false,
			Theme = { BackgroundColor3 = "Overlay" },
			BackgroundTransparency = 1,
			ZIndex = 1,
			Parent = root,
		})
		Tween.Play(backdrop, { BackgroundTransparency = Theme.Current.OverlayTransparency }, Tween.Fast)
	end

	local container = Create.New("Frame", {
		Name = "CardContainer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(maxWidth or 380, 560)
	constraint.Parent = container

	local shadowDesc = Assets.Shadow()
	Create.New("ImageLabel", {
		Name = "Shadow",
		Image = shadowDesc.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowDesc.Slice,
		Position = UDim2.fromOffset(-shadowDesc.Inset, -shadowDesc.Inset + 6),
		Size = UDim2.new(1, shadowDesc.Inset * 2, 1, shadowDesc.Inset * 2),
		BackgroundTransparency = 1,
		Theme = {
			ImageColor3 = "Shadow",
			ImageTransparency = "ShadowTransparency",
		},
		ZIndex = 1,
		Parent = container,
	})

	local card = Create.New("Frame", {
		Name = "GlassCard",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.03)
			end,
		},
		Corner = 14,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = container,
	})
	Create.GlassStroke(card, 0.05)

	local glowAsset = Assets.Get("Glow")
	if glowAsset and Assets.Available then
		Create.New("ImageLabel", {
			Name = "GlowTop",
			Image = glowAsset,
			Size = UDim2.fromOffset(240, 150),
			Position = UDim2.fromOffset(-80, -80),
			Corner = 14,
			BackgroundTransparency = 1,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = card,
		})
	end

	local inner = Create.New("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = 20,
		ZIndex = 2,
		Parent = card,
	})
	Create.List(inner, { Gap = 14 })

	return root, backdrop, container, card, inner
end

-- ─── LoadingScreen ───────────────────────────────────────────────────────────

function Loader.LoadingScreen(parentGui, options)
	assert(typeof(parentGui) == "Instance", "[Bali] Loader.LoadingScreen expects a parentGui Instance")
	if not Assets.Loaded then
		pcall(Assets.Load)
	end

	options = Util.Options(options, {
		Title = "Bali",
		Subtitle = "Preparing workspace...",
		Icon = "bali-logo",
		Duration = 1.6,
		Steps = nil,
		AutoClose = true,
		Backdrop = true,
		Yield = false,
		OnComplete = nil,
		Callback = nil,
	}, "Title")

	local maid = Maid.new()
	local closed = false
	local finished = false
	local root, backdrop, container, _, inner = createBackdropAndCard(parentGui, maid, 360, options.Backdrop ~= false)

	local header = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = inner,
	})
	Create.List(header, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 12,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local customIcon = options.Icon and options.Icon ~= "bali-logo" and options.Icon ~= "bali"
	local badge = Create.New("Frame", {
		Size = UDim2.fromOffset(40, 40),
		Corner = 11,
		Theme = { BackgroundColor3 = customIcon and "Accent" or "TileHover" },
		BackgroundTransparency = customIcon and 0.88 or 0.8,
		LayoutOrder = 1,
		Parent = header,
	})
	Create.Stroke(badge, {
		Theme = { Color = customIcon and "Accent" or "Stroke" },
		Transparency = customIcon and 0.65 or 0.52,
		Thickness = 1,
	})

	local badgeIcon = Icons.Create(options.Icon or "bali-logo", {
		Size = UDim2.fromOffset(customIcon and 22 or 26, customIcon and 22 or 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = customIcon and "Accent" or Color3.fromRGB(255, 255, 255),
		Parent = badge,
	})
	local stopPulse = nil
	if badgeIcon then
		local pulseTarget = Icons.TransparencyTarget(badgeIcon) or badgeIcon
		stopPulse = Transition.Pulse(pulseTarget, Icons.TransparencyProperty(pulseTarget), 0, 0.45, 0.9)
		maid:Give(stopPulse)
	end

	local titleCol = Create.New("Frame", {
		Size = UDim2.new(1, -52, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = header,
	})
	Create.List(titleCol, { Gap = 2 })

	Create.Text({
		Text = tostring(options.Title or "Bali"),
		Font = "Bold",
		TextSize = 17,
		Color = "Text",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = titleCol,
	})

	local statusLabel = Create.Text({
		Text = tostring(options.Subtitle or "Loading..."),
		Font = "Regular",
		TextSize = 12,
		Color = "SubText",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = titleCol,
	})

	local progressBlock = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = inner,
	})
	Create.List(progressBlock, { Gap = 6 })

	local track = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 5),
		Corner = UDim.new(1, 0),
		Theme = { BackgroundColor3 = "Field" },
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = progressBlock,
	})

	local fill = Create.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		Corner = UDim.new(1, 0),
		Theme = { BackgroundColor3 = "Accent" },
		Parent = track,
	})
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = Theme.AccentSequence()
	fillGrad.Parent = fill
	maid:Give(Theme.Changed:Connect(function(theme)
		fillGrad.Color = Theme.AccentSequence(theme)
	end))

	local metaRow = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = progressBlock,
	})
	local stepLabel = Create.Text({
		Text = "Initializing...",
		Font = "Medium",
		TextSize = 11,
		Color = "Muted",
		Size = UDim2.new(1, -46, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = metaRow,
	})
	local pctLabel = Create.Text({
		Text = "0%",
		Font = "SemiBold",
		TextSize = 11,
		Color = "SubText",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 44, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = metaRow,
	})

	Transition.Mount(container, 0.94)

	local controller = {
		Frame = root,
	}

	function controller:SetStatus(text)
		local str = tostring(text or "")
		statusLabel.Text = str
		stepLabel.Text = str
	end

	function controller:SetProgress(alpha, statusText)
		alpha = Util.Clamp(tonumber(alpha) or 0, 0, 1)
		Tween.Play(fill, { Size = UDim2.fromScale(alpha, 1) }, Tween.Fast)
		pctLabel.Text = string.format("%d%%", math.floor(alpha * 100 + 0.5))
		if statusText ~= nil then
			self:SetStatus(statusText)
		end
	end

	function controller:Close(onDone)
		if closed then
			if onDone then
				onDone()
			end
			return
		end
		closed = true
		if stopPulse then
			pcall(stopPulse)
			stopPulse = nil
		end
		if backdrop then
			Tween.Play(backdrop, { BackgroundTransparency = 1 }, Tween.Fast)
		end
		Transition.Unmount(container, 0.94, function()
			finished = true
			maid:Clean()
			if type(onDone) == "function" then
				Util.Spawn(onDone)
			end
		end)
	end

	function controller:Wait()
		while not finished do
			task.wait()
		end
		return true
	end

	function controller:Destroy()
		finished = true
		closed = true
		maid:Clean()
	end

	if options.AutoClose ~= false then
		local doneCallback = options.OnComplete or options.Callback
		maid:Give(task.spawn(function()
			local steps = options.Steps
			if type(steps) == "table" and #steps > 0 then
				local total = #steps
				local stepDefault = math.max((options.Duration or 1.6) / total, 0.15)
				for index, item in ipairs(steps) do
					if closed then
						return
					end
					local labelText = type(item) == "table" and (item.Text or item.Title) or tostring(item)
					local waitTime = type(item) == "table" and item.Duration or stepDefault
					controller:SetProgress(index / total, labelText)
					task.wait(waitTime)
				end
			else
				local duration = math.max(options.Duration or 1.6, 0.15)
				local started = os.clock()
				while os.clock() - started < duration do
					if closed then
						return
					end
					local t = Util.Clamp((os.clock() - started) / duration, 0, 1)
					fill.Size = UDim2.fromScale(t, 1)
					pctLabel.Text = string.format("%d%%", math.floor(t * 100 + 0.5))
					task.wait()
				end
				controller:SetProgress(1, "Ready")
				task.wait(0.15)
			end

			if not closed then
				controller:Close(doneCallback)
			end
		end))
	end

	if options.Yield then
		controller:Wait()
	end

	return controller
end

-- ─── KeySystem ───────────────────────────────────────────────────────────────

local function checkSavedKey(options, verifyFn)
	if not options.SaveKey or not Util.FS.Supported() then
		return nil
	end
	local folder = options.Folder or "Bali"
	local path = options.SavePath or (folder .. "/" .. tostring(options.FileName or "key.txt"))
	if not Util.FS.IsFile(path) then
		return nil
	end
	local saved = Util.Trim(Util.FS.Read(path) or "")
	if saved == "" then
		return nil
	end
	local ok = verifyFn(saved)
	return ok and saved or nil
end

local function writeSavedKey(options, key)
	if not options.SaveKey or not Util.FS.Supported() then
		return
	end
	local folder = options.Folder or "Bali"
	Util.FS.MakeFolder(folder)
	local path = options.SavePath or (folder .. "/" .. tostring(options.FileName or "key.txt"))
	Util.FS.Write(path, tostring(key))
end

local function fetchJson(url)
	local body, status = Util.HttpGet(url, true)
	if not body then
		return nil, status
	end
	local ok, data = pcall(function()
		return Services.HttpService:JSONDecode(body)
	end)
	if ok and type(data) == "table" then
		return data, status
	end
	local presence = tonumber(body:match('"approximate_presence_count"%s*:%s*(%d+)'))
	local total = tonumber(body:match('"approximate_member_count"%s*:%s*(%d+)'))
	if presence or total then
		return {
			approximate_presence_count = presence,
			approximate_member_count = total,
		}, status
	end
	return nil, status
end

local function createPillBadge(parent, bgColorKey, strokeColorKey, dotColorKey, text, textSize, layoutOrder)
	local badge = Create.New("Frame", {
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Corner = 99,
		Theme = { BackgroundColor3 = "Tile" },
		BackgroundTransparency = 0.15,
		Padding = { 0, 8, 0, 7 },
		LayoutOrder = layoutOrder or 1,
		Parent = parent,
	})
	Create.List(badge, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 5,
		VAlign = Enum.VerticalAlignment.Center,
	})
	local badgeStroke = Create.Stroke(badge, {
		Theme = { Color = strokeColorKey or "Stroke" },
		Transparency = 0.42,
		Thickness = 1,
	})
	local dot = Create.New("Frame", {
		Size = UDim2.fromOffset(6, 6),
		Corner = 99,
		Theme = { BackgroundColor3 = dotColorKey or "Accent" },
		LayoutOrder = 1,
		Parent = badge,
	})
	local label = Create.Text({
		Text = tostring(text or ""),
		Font = "SemiBold",
		TextSize = textSize or 11,
		Color = dotColorKey or "Text",
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = badge,
	})
	return badge, badgeStroke, dot, label
end

function Loader.KeySystem(parentGui, options)
	assert(typeof(parentGui) == "Instance", "[Bali] Loader.KeySystem expects a parentGui Instance")
	if not Assets.Loaded then
		pcall(Assets.Load)
	end

	options = Util.Options(options, {
		Title = "Key Verification",
		Subtitle = "Key System",
		Version = "v1.0.0",
		Note = nil,
		Icon = "key",
		Key = nil,
		Keys = nil,
		Verify = nil,
		CheckKey = nil,
		Callback = nil,
		KeyUrl = nil,
		GetKeyUrl = nil,
		Link = nil,
		KeyLink = nil,
		OnGetKey = nil,
		SaveKey = false,
		RememberByDefault = nil,
		Folder = "Bali",
		FileName = "key.txt",
		SavePath = nil,
		SupportedGames = nil,
		DefaultSupported = true,
		DiscordName = nil,
		DiscordInvite = nil,
		DiscordGuildId = nil,
		DiscordIcon = nil,
		Changelog = nil,
		MaxAttempts = 5,
		Cooldown = 8,
		Closable = true,
		Minimizable = true,
		Yield = false,
		OnSuccess = nil,
		OnCancel = nil,
	}, "Title")

	local rememberKey = options.SaveKey == true or options.RememberByDefault == true
	local runtimeOpts = table.clone(options)
	runtimeOpts.SaveKey = rememberKey

	local customVerify = options.Verify or options.CheckKey or options.Callback
	local function verifyKey(candidate)
		candidate = Util.Trim(candidate or "")
		if candidate == "" then
			return false, "Please enter a key."
		end
		if type(customVerify) == "function" then
			local ok, result, message = pcall(customVerify, candidate)
			if not ok then
				return false, "Verification error: " .. tostring(result)
			end
			if result == true then
				return true, message
			end
			return false, tostring(message or "Invalid key. Please try again.")
		end
		local list = options.Keys
		if type(list) == "table" then
			for _, valid in ipairs(list) do
				if tostring(valid) == candidate then
					return true
				end
			end
			return false, "Invalid key. Please try again."
		end
		if options.Key ~= nil then
			if tostring(options.Key) == candidate then
				return true
			end
			return false, "Invalid key. Please try again."
		end
		return true
	end

	local savedValid = checkSavedKey(runtimeOpts, verifyKey)
	if savedValid then
		if type(options.OnSuccess) == "function" then
			Util.Spawn(options.OnSuccess, savedValid)
		end
		local immediate = {
			Verified = true,
			Key = savedValid,
			Wait = function()
				return true, savedValid
			end,
			Close = function() end,
			Destroy = function() end,
		}
		if options.Yield then
			return true, savedValid
		end
		return immediate
	end

	local maid = Maid.new()
	local closed = false
	local done = false
	local verified = false
	local finalKey = nil
	local busy = false
	local minimized = false
	local masked = false
	local attemptsLeft = math.max(0, tonumber(options.MaxAttempts) or 5)
	local cooldownUntil = 0

	local vp = parentGui.AbsoluteSize
	local useWide = vp.X <= 0 or vp.X >= 680
	local cardW = useWide and 640 or math.max(300, math.min(440, vp.X - 24))
	local cardH = useWide and 386 or 530

	local root = Create.New("Frame", {
		Name = "LoaderOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 250,
		Parent = parentGui,
	})
	maid:Give(root)

	local backdrop = Create.New("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Theme = { BackgroundColor3 = "Overlay" },
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = root,
	})
	Tween.Play(backdrop, { BackgroundTransparency = Theme.Current.OverlayTransparency }, Tween.Fast)

	local container = Create.New("Frame", {
		Name = "CardContainer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(cardW, cardH),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})

	local shadowDesc = Assets.Shadow()
	Create.New("ImageLabel", {
		Name = "Shadow",
		Image = shadowDesc.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowDesc.Slice,
		Position = UDim2.fromOffset(-shadowDesc.Inset, -shadowDesc.Inset + 8),
		Size = UDim2.new(1, shadowDesc.Inset * 2, 1, shadowDesc.Inset * 2),
		BackgroundTransparency = 1,
		Theme = {
			ImageColor3 = "Shadow",
			ImageTransparency = "ShadowTransparency",
		},
		ZIndex = 1,
		Parent = container,
	})

	local mainCard = Create.New("Frame", {
		Name = "GlassCard",
		Size = UDim2.fromScale(1, 1),
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.02)
			end,
		},
		Corner = 16,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = container,
	})
	Create.GlassStroke(mainCard, 0.05)

	local keyBgClip = Create.New("CanvasGroup", {
		Name = "BackgroundClip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Corner = 16,
		ZIndex = 1,
		Parent = mainCard,
	})

	local glowAsset = Assets.Get("Glow")
	if glowAsset and Assets.Available then
		Create.New("ImageLabel", {
			Name = "GlowTop",
			Image = glowAsset,
			Size = UDim2.fromOffset(320, 320),
			Position = UDim2.fromOffset(-120, -120),
			BackgroundTransparency = 1,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = keyBgClip,
		})
		Create.New("ImageLabel", {
			Name = "GlowBottom",
			Image = glowAsset,
			AnchorPoint = Vector2.new(1, 1),
			Size = UDim2.fromOffset(290, 290),
			Position = UDim2.new(1, 110, 1, 110),
			BackgroundTransparency = 1,
			Theme = {
				ImageColor3 = "Accent2",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = keyBgClip,
		})
	end

	-- Minimized floating restore pill
	local restorePill = Create.New("TextButton", {
		Name = "KeyMinimizePill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		AutoButtonColor = false,
		Corner = 999,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.04)
			end,
		},
		Padding = { 0, 14, 0, 10 },
		Visible = false,
		ZIndex = 5,
		Parent = root,
	})
	local pillStroke = Create.GlassStroke(restorePill, 0.05)
	Transition.Hover(restorePill, restorePill, "Card", "TileHover", pillStroke)
	local pillRow = Create.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = restorePill,
	})
	Create.List(pillRow, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 8,
		VAlign = Enum.VerticalAlignment.Center,
	})
	Icons.Create(options.Icon or "key", {
		Size = UDim2.fromOffset(14, 14),
		Color = "Accent",
		LayoutOrder = 1,
		Parent = pillRow,
	})
	Create.Text({
		Text = tostring(options.Title or "Key System") .. "  ·  Click to restore",
		Font = "SemiBold",
		TextSize = 12,
		Color = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = pillRow,
	})

	local controller = {
		Frame = root,
		Verified = false,
		Key = nil,
	}

	function controller:Close()
		if closed then
			return
		end
		closed = true
		if backdrop then
			Tween.Play(backdrop, { BackgroundTransparency = 1 }, Tween.Fast)
		end
		Transition.Unmount(container, 0.94, function()
			done = true
			maid:Clean()
		end)
	end

	function controller:Destroy()
		done = true
		closed = true
		maid:Clean()
	end

	function controller:Wait()
		while not done do
			task.wait()
		end
		return verified, finalKey
	end

	local function setMinimized(state)
		if closed then
			return
		end
		minimized = state == true
		if minimized then
			Tween.Play(backdrop, { BackgroundTransparency = 1 }, Tween.Fast)
			restorePill.Visible = true
			Transition.Unmount(container, 0.94, function()
				if minimized and container.Parent then
					container.Visible = false
				end
			end)
		else
			restorePill.Visible = false
			Tween.Play(backdrop, { BackgroundTransparency = Theme.Current.OverlayTransparency }, Tween.Fast)
			container.Visible = true
			Transition.Mount(container, 0.94)
		end
	end

	maid:Give(restorePill.Activated:Connect(function(input)
		Transition.Ripple(restorePill, input, "Accent")
		setMinimized(false)
	end))

	-- Responsive Left & Right Panes
	local leftPane = Create.New("Frame", {
		Name = "LeftPane",
		Position = UDim2.fromOffset(0, 0),
		Size = useWide and UDim2.new(0, 384, 1, 0) or UDim2.new(1, 0, 0, 296),
		BackgroundTransparency = 1,
		Padding = { 24, 24, 20, 24 },
		ZIndex = 2,
		Parent = mainCard,
	})

	if useWide then
		Create.New("Frame", {
			Name = "VerticalDivider",
			Position = UDim2.fromOffset(384, 22),
			Size = UDim2.new(0, 1, 1, -44),
			Theme = {
				BackgroundColor3 = "Divider",
				BackgroundTransparency = "DividerTransparency",
			},
			ZIndex = 2,
			Parent = mainCard,
		})
	end

	local rightPane = Create.New("Frame", {
		Name = "RightPane",
		Position = useWide and UDim2.fromOffset(385, 0) or UDim2.fromOffset(0, 296),
		Size = useWide and UDim2.new(1, -385, 1, 0) or UDim2.new(1, 0, 1, -296),
		BackgroundTransparency = 1,
		Padding = { 18, 20, 18, 20 },
		ZIndex = 2,
		Parent = mainCard,
	})

	-- ─── Left Column: Brand Header ────────────────────────────────────────────
	local header = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = leftPane,
	})
	Create.List(header, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 11,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local useBrandLogo = options.Icon == "bali-logo" or options.Icon == "bali"
	local iconBadge = Create.New("Frame", {
		Size = UDim2.fromOffset(40, 40),
		Corner = 11,
		Theme = { BackgroundColor3 = useBrandLogo and "TileHover" or "Accent" },
		BackgroundTransparency = useBrandLogo and 0.8 or 0.88,
		LayoutOrder = 1,
		Parent = header,
	})
	Create.Stroke(iconBadge, {
		Theme = { Color = useBrandLogo and "Stroke" or "Accent" },
		Transparency = useBrandLogo and 0.52 or 0.65,
		Thickness = 1,
	})
	Icons.Create(options.Icon or "key", {
		Size = UDim2.fromOffset(useBrandLogo and 26 or 20, useBrandLogo and 26 or 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = useBrandLogo and Color3.fromRGB(255, 255, 255) or "Accent",
		Parent = iconBadge,
	})

	local titleBlock = Create.New("Frame", {
		Size = UDim2.new(1, -110, 1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = header,
	})
	Create.List(titleBlock, { Gap = 2, VAlign = Enum.VerticalAlignment.Center })

	Create.Text({
		Text = tostring(options.Title or "Key Verification"),
		Font = "Bold",
		TextSize = 17,
		Color = "Text",
		Size = UDim2.new(1, 0, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
		Parent = titleBlock,
	})

	local subText = options.Note or options.Subtitle or "Key System"
	Create.Text({
		Text = tostring(subText),
		Font = "Regular",
		TextSize = 12,
		Color = "SubText",
		Size = UDim2.new(1, 0, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = titleBlock,
	})

	local verPill = Create.New("Frame", {
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Corner = 99,
		Theme = { BackgroundColor3 = "Tile" },
		BackgroundTransparency = 0.25,
		Padding = { 0, 9, 0, 9 },
		LayoutOrder = 3,
		Parent = header,
	})
	Create.Stroke(verPill, { Theme = { Color = "Accent" }, Transparency = 0.55 })
	Create.Text({
		Text = tostring(options.Version or "v1.0.0"),
		Font = "Bold",
		TextSize = 11,
		Color = "Accent",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = verPill,
	})

	Create.New("Frame", {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = leftPane,
	})

	-- ─── Left Column: License Key Input + Actions ─────────────────────────────
	local labelRow = Create.New("Frame", {
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Parent = leftPane,
	})
	Create.Text({
		Text = "License key",
		Font = "Medium",
		TextSize = 12,
		Color = "SubText",
		Size = UDim2.new(0.55, 0, 1, 0),
		Parent = labelRow,
	})
	local attemptsLabel = Create.Text({
		Text = attemptsLeft > 0 and (tostring(attemptsLeft) .. " attempts") or "",
		Font = "Medium",
		TextSize = 11,
		Color = "Muted",
		Size = UDim2.new(0.45, 0, 1, 0),
		Position = UDim2.fromScale(0.55, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = labelRow,
	})

	local field = Create.New("Frame", {
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 42),
		Corner = 10,
		Theme = { BackgroundColor3 = "Field" },
		Parent = leftPane,
	})
	local fieldStroke = Create.Stroke(field, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})

	Icons.Create("key", {
		Size = UDim2.fromOffset(15, 15),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 13, 0.5, 0),
		Color = "Muted",
		Parent = field,
	})

	local keyBox = Create.New("TextBox", {
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(1, -74, 1, 0),
		Text = "",
		PlaceholderText = "Paste your key here...",
		TextSize = 13,
		Font = "Regular",
		ClearTextOnFocus = false,
		Theme = {
			TextColor3 = "Text",
			PlaceholderColor3 = "Muted",
		},
		Parent = field,
	})

	local maskLabel = Create.Text({
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(1, -74, 1, 0),
		Text = "",
		Font = "Bold",
		TextSize = 14,
		Color = "Text",
		Visible = false,
		Parent = field,
	})

	local eyeBtn = Create.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		Text = "",
		AutoButtonColor = false,
		Corner = 7,
		Theme = { BackgroundColor3 = "Tile" },
		BackgroundTransparency = 0.45,
		Parent = field,
	})
	local eyeIcon = Icons.Create("eye", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "SubText",
		Parent = eyeBtn,
	})

	local function refreshMask()
		local txt = keyBox.Text or ""
		if masked and #txt > 0 then
			keyBox.TextTransparency = 1
			maskLabel.Text = string.rep("•", math.min(#txt, 40))
			maskLabel.Visible = true
		else
			keyBox.TextTransparency = 0
			maskLabel.Visible = false
		end
	end

	maid:Give(keyBox:GetPropertyChangedSignal("Text"):Connect(refreshMask))
	maid:Give(eyeBtn.Activated:Connect(function()
		masked = not masked
		Icons.SetColor(eyeIcon, masked and "Accent" or "SubText")
		refreshMask()
	end))

	maid:Give(keyBox.Focused:Connect(function()
		Theme.Bind(fieldStroke, { Color = "Accent" })
		Tween.Play(fieldStroke, { Transparency = 0.2 }, Tween.Fast)
	end))
	maid:Give(keyBox.FocusLost:Connect(function()
		Theme.Bind(fieldStroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
	end))

	local feedbackLabel = Create.Text({
		Position = UDim2.fromOffset(2, 140),
		Size = UDim2.new(1, -4, 0, 16),
		Text = "",
		Font = "Medium",
		TextSize = 11,
		Color = "Error",
		Visible = false,
		Parent = leftPane,
	})

	local function shakeError(msg)
		feedbackLabel.Text = tostring(msg or "Invalid key.")
		Theme.Bind(feedbackLabel, { TextColor3 = "Error" })
		feedbackLabel.Visible = true
		Theme.Bind(fieldStroke, { Color = "Error" })
		fieldStroke.Transparency = 0.2

		task.spawn(function()
			local offsets = { -9, 9, -6, 6, -3, 0 }
			for _, offset in ipairs(offsets) do
				if closed or not container.Parent then
					return
				end
				Tween.Play(container, { Position = UDim2.new(0.5, offset, 0.5, 0) }, 0.04, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
				task.wait(0.04)
			end
		end)
	end

	local keyLink = options.KeyUrl or options.GetKeyUrl or options.Link or options.KeyLink
	local hasGetKey = (keyLink ~= nil and keyLink ~= "") or type(options.OnGetKey) == "function"

	local btnRow = Create.New("Frame", {
		Position = UDim2.fromOffset(0, 164),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = leftPane,
	})
	Create.List(btnRow, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 10,
	})

	if hasGetKey then
		local getBtn = Create.New("TextButton", {
			Size = UDim2.new(0.45, -5, 1, 0),
			Text = "",
			AutoButtonColor = false,
			ClipsDescendants = true,
			Corner = 10,
			Theme = { BackgroundColor3 = "Tile", BackgroundTransparency = "TileTransparency" },
			LayoutOrder = 1,
			Parent = btnRow,
		})
		local getStroke = Create.Stroke(getBtn, {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
		})
		local getInner = Create.New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = getBtn,
		})
		Create.List(getInner, {
			Direction = Enum.FillDirection.Horizontal,
			Gap = 6,
			HAlign = Enum.HorizontalAlignment.Center,
			VAlign = Enum.VerticalAlignment.Center,
		})
		Icons.Create("copy", {
			Size = UDim2.fromOffset(14, 14),
			Color = "SubText",
			LayoutOrder = 1,
			Parent = getInner,
		})
		local getLabel = Create.Text({
			Text = "Get Key",
			Font = "Medium",
			TextSize = 13,
			Color = "Text",
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
			Parent = getInner,
		})
		Transition.Hover(getBtn, getBtn, "Tile", "TileHover", getStroke)
		maid:Give(getBtn.Activated:Connect(function(input)
			Transition.Ripple(getBtn, input, "Accent")
			if keyLink and keyLink ~= "" then
				Util.SetClipboard(keyLink)
			end
			if type(options.OnGetKey) == "function" then
				Util.Spawn(options.OnGetKey)
			end
			getLabel.Text = "Copied!"
			task.delay(1.8, function()
				if getLabel.Parent then
					getLabel.Text = "Get Key"
				end
			end)
		end))
	end

	local verifyBtn = Create.New("TextButton", {
		Size = hasGetKey and UDim2.new(0.55, -5, 1, 0) or UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
		Corner = 10,
		Theme = { BackgroundColor3 = "Accent" },
		LayoutOrder = 2,
		Parent = btnRow,
	})
	local verifyGrad = Instance.new("UIGradient")
	verifyGrad.Color = Theme.AccentSequence()
	verifyGrad.Rotation = 18
	verifyGrad.Parent = verifyBtn
	maid:Give(Theme.Changed:Connect(function(theme)
		verifyGrad.Color = Theme.AccentSequence(theme)
	end))

	local verifyInner = Create.New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = verifyBtn,
	})
	Create.List(verifyInner, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		HAlign = Enum.HorizontalAlignment.Center,
		VAlign = Enum.VerticalAlignment.Center,
	})
	Icons.Create("shield-check", {
		Size = UDim2.fromOffset(15, 15),
		Color = "AccentText",
		LayoutOrder = 1,
		Parent = verifyInner,
	})
	local verifyLabel = Create.Text({
		Text = "Verify Key",
		Font = "SemiBold",
		TextSize = 13,
		Color = "AccentText",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = verifyInner,
	})

	-- Remember key toggle + Need help link
	local remRow = Create.New("Frame", {
		Position = UDim2.fromOffset(0, 218),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = leftPane,
	})
	local remTrack = Create.New("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(34, 18),
		Text = "",
		AutoButtonColor = false,
		Corner = 99,
		Theme = { BackgroundColor3 = rememberKey and "Accent" or "ToggleOff" },
		Parent = remRow,
	})
	local remKnob = Create.New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, rememberKey and 18 or 2, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		Corner = 99,
		Theme = { BackgroundColor3 = "Knob" },
		Parent = remTrack,
	})
	Create.Text({
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Text = "Remember key",
		Font = "Medium",
		TextSize = 12,
		Color = "SubText",
		Parent = remRow,
	})
	maid:Give(remTrack.Activated:Connect(function()
		rememberKey = not rememberKey
		runtimeOpts.SaveKey = rememberKey
		Theme.Bind(remTrack, { BackgroundColor3 = rememberKey and "Accent" or "ToggleOff" })
		Tween.Spring(remKnob, { Position = UDim2.new(0, rememberKey and 18 or 2, 0.5, 0) }, Tween.Fast + 0.05)
	end))

	local helpBtn = Create.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(80, 26),
		Text = "Need help?",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Font = "SemiBold",
		TextSize = 12,
		Theme = { TextColor3 = "Accent" },
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = remRow,
	})

	-- Footer on left column
	local footer = Create.New("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = leftPane,
	})
	Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = footer,
	})
	local execName = Util.ExecutorName()
	Create.Text({
		Position = UDim2.fromOffset(0, 7),
		Size = UDim2.new(0.62, 0, 0, 18),
		Text = "Executor: " .. execName,
		Font = "Medium",
		TextSize = 11,
		Color = "Muted",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = footer,
	})
	Create.Text({
		Position = UDim2.new(0.62, 0, 0, 7),
		Size = UDim2.new(0.38, 0, 0, 18),
		Text = tostring(options.Version or "v1.0.0"),
		Font = "Medium",
		TextSize = 11,
		Color = "Muted",
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = footer,
	})

	-- ─── Right Column: Top Actions, Game Status Card, Discord Card, Info Card ─
	local topActions = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = rightPane,
	})
	Create.Text({
		Text = "Detected game",
		Font = "Medium",
		TextSize = 11,
		Color = "SubText",
		Size = UDim2.new(0.55, 0, 1, 0),
		Parent = topActions,
	})
	local actBtns = Create.New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(100, 28),
		BackgroundTransparency = 1,
		Parent = topActions,
	})
	Create.List(actBtns, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		HAlign = Enum.HorizontalAlignment.Right,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local function makeSmallAct(iconName, order)
		local btn = Create.New("TextButton", {
			Size = UDim2.fromOffset(26, 26),
			Text = "",
			AutoButtonColor = false,
			Corner = 7,
			Theme = { BackgroundColor3 = "Tile", BackgroundTransparency = "TileTransparency" },
			LayoutOrder = order,
			Parent = actBtns,
		})
		local st = Create.Stroke(btn, {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
		})
		local ico = Icons.Create(iconName, {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Color = "Text",
			Parent = btn,
		})
		Transition.Hover(btn, btn, "Tile", "TileHover", st)
		if iconName ~= "x" then
			maid:Give(btn.MouseEnter:Connect(function()
				Icons.SetColor(ico, "Accent")
			end))
			maid:Give(btn.MouseLeave:Connect(function()
				Icons.SetColor(ico, "Text")
			end))
		end
		return btn, ico
	end

	local infoIconBtn = makeSmallAct("info", 1)
	if options.Minimizable ~= false then
		local minIconBtn = makeSmallAct("minus", 2)
		maid:Give(minIconBtn.Activated:Connect(function()
			setMinimized(true)
		end))
	end
	if options.Closable ~= false then
		local closeIconBtn, xIco = makeSmallAct("x", 3)
		maid:Give(closeIconBtn.MouseEnter:Connect(function()
			Icons.SetColor(xIco, "Error")
		end))
		maid:Give(closeIconBtn.MouseLeave:Connect(function()
			Icons.SetColor(xIco, "Text")
		end))
		maid:Give(closeIconBtn.Activated:Connect(function()
			controller:Close()
			if type(options.OnCancel) == "function" then
				Util.Spawn(options.OnCancel)
			end
		end))
	end

	-- Detected Game Card
	local gameCard = Create.New("Frame", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 68),
		Corner = 12,
		Theme = { BackgroundColor3 = "Tile" },
		BackgroundTransparency = 0.25,
		Parent = rightPane,
	})
	Create.Stroke(gameCard, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })

	local gameIconBg = Create.New("Frame", {
		Position = UDim2.fromOffset(11, 13),
		Size = UDim2.fromOffset(42, 42),
		Corner = 10,
		Theme = { BackgroundColor3 = "Accent" },
		BackgroundTransparency = 0.85,
		ClipsDescendants = true,
		Parent = gameCard,
	})
	local gameIdStr = tostring(game.GameId or game.PlaceId or 0)
	Create.New("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "rbxthumb://type=GameIcon&id=" .. gameIdStr .. "&w=150&h=150",
		Parent = gameIconBg,
	})

	local gameNameLabel = Create.Text({
		Position = UDim2.fromOffset(63, 12),
		Size = UDim2.new(1, -73, 0, 18),
		Text = "Experience #" .. tostring(game.PlaceId or 0),
		Font = "SemiBold",
		TextSize = 13,
		Color = "Text",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = gameCard,
	})

	local supportedEntry = nil
	if type(options.SupportedGames) == "table" then
		supportedEntry = options.SupportedGames[game.PlaceId] or options.SupportedGames[game.GameId]
	else
		supportedEntry = options.DefaultSupported ~= false
	end
	local isSupported = supportedEntry ~= nil and supportedEntry ~= false
	local statusColorKey = isSupported and "Success" or "Error"
	local statusText = isSupported and "Supported" or "Not Supported"

	local statusWrap = Create.New("Frame", {
		Position = UDim2.fromOffset(63, 35),
		Size = UDim2.new(1, -73, 0, 22),
		BackgroundTransparency = 1,
		Parent = gameCard,
	})
	createPillBadge(statusWrap, "Tile", statusColorKey, statusColorKey, statusText, 11, 1)

	Util.Spawn(function()
		local name = type(supportedEntry) == "string" and supportedEntry or nil
		local ok, info = pcall(function()
			return Services.MarketplaceService:GetProductInfo(game.PlaceId)
		end)
		if ok and type(info) == "table" and info.Name then
			name = info.Name
		end
		if not closed and gameNameLabel.Parent and name then
			gameNameLabel.Text = tostring(name)
		end
	end)

	-- Discord Community Card
	local inviteCode = Util.ExtractInviteCode(options.DiscordInvite or "")
	local discordCard = Create.New("TextButton", {
		Position = UDim2.fromOffset(0, 112),
		Size = UDim2.new(1, 0, 0, 114),
		Text = "",
		AutoButtonColor = false,
		Corner = 12,
		Theme = { BackgroundColor3 = "Tile" },
		BackgroundTransparency = 0.25,
		Parent = rightPane,
	})
	local dcStroke = Create.Stroke(discordCard, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })
	Transition.Hover(discordCard, discordCard, "Tile", "TileHover", dcStroke)

	local dcBadge = Create.New("Frame", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(36, 36),
		Corner = 10,
		BackgroundColor3 = Color3.fromRGB(88, 101, 242),
		ClipsDescendants = true,
		Parent = discordCard,
	})
	local dcDefaultIco = Create.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 14),
		Corner = 6,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = dcBadge,
	})
	for _, ex in ipairs({ 6, 14 }) do
		Create.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(ex, 7),
			Size = UDim2.fromOffset(4, 5),
			Corner = 99,
			BackgroundColor3 = Color3.fromRGB(88, 101, 242),
			Parent = dcDefaultIco,
		})
	end
	local dcImg = Create.New("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		Parent = dcBadge,
	})

	local dcTitleLabel = Create.Text({
		Position = UDim2.fromOffset(58, 12),
		Size = UDim2.new(1, -68, 0, 17),
		Text = tostring(options.DiscordName or options.Title or "Community"),
		Font = "SemiBold",
		TextSize = 13,
		Color = "Text",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = discordCard,
	})
	Create.Text({
		Position = UDim2.fromOffset(58, 31),
		Size = UDim2.new(1, -68, 0, 16),
		Text = inviteCode ~= "" and ("discord.gg/" .. inviteCode) or "Community Server",
		Font = "Medium",
		TextSize = 12,
		Color = "SubText",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = discordCard,
	})
	Create.New("Frame", {
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.new(1, -24, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = discordCard,
	})

	local function makeStatCol(xScale, titleStr, dotColorKey)
		local valLbl = Create.Text({
			Position = UDim2.new(xScale, 12, 0, 65),
			Size = UDim2.new(0.5, -14, 0, 20),
			Text = "—",
			Font = "Bold",
			TextSize = 16,
			Color = "Text",
			Parent = discordCard,
		})
		local dot = Create.New("Frame", {
			Position = UDim2.new(xScale, 12, 0, 91),
			Size = UDim2.fromOffset(6, 6),
			Corner = 99,
			Theme = { BackgroundColor3 = dotColorKey },
			Parent = discordCard,
		})
		dot.BorderSizePixel = 0
		Create.Text({
			Position = UDim2.new(xScale, 23, 0, 86),
			Size = UDim2.new(0.5, -24, 0, 16),
			Text = titleStr,
			Font = "Regular",
			TextSize = 11,
			Color = "SubText",
			Parent = discordCard,
		})
		return valLbl
	end

	local dcOnlineLabel = makeStatCol(0, "Online", "Success")
	local dcOfflineLabel = makeStatCol(0.5, "Offline", "Muted")

	maid:Give(discordCard.Activated:Connect(function(input)
		if inviteCode ~= "" then
			Transition.Ripple(discordCard, input, "Accent")
			Util.SetClipboard("https://discord.gg/" .. inviteCode)
		end
	end))

	local function applyDiscordIcon(iconSrc)
		if closed or not iconSrc or iconSrc == "" then
			return
		end
		local str = tostring(iconSrc)
		if tonumber(str) then
			str = "rbxassetid://" .. str
		end
		if str:find("://") and not str:find("^https?://") then
			dcImg.Image = str
			dcImg.Visible = true
			if dcDefaultIco then
				dcDefaultIco.Visible = false
			end
			return
		end
		local getAsset = Util.Global("getcustomasset") or Util.Global("getsynasset")
		if type(getAsset) == "function" and Util.FS.Supported() then
			Util.Spawn(function()
				local hash = str:match("icons/%d+/([%w%-_]+)%.png") or "bali_discord"
				local path = (options.Folder or "Bali") .. "/discord_" .. hash .. ".png"
				if not Util.FS.IsFile(path) and str:find("^https?://") then
					local bytes = Util.HttpGet(str, false)
					if bytes and #bytes > 0 then
						Util.FS.MakeFolder(options.Folder or "Bali")
						Util.FS.Write(path, bytes)
					end
				end
				if not closed and Util.FS.IsFile(path) then
					local ok, asset = pcall(getAsset, path)
					if ok and asset and dcImg.Parent then
						dcImg.Image = asset
						dcImg.Visible = true
						if dcDefaultIco then
							dcDefaultIco.Visible = false
						end
					end
				end
			end)
		end
	end

	if options.DiscordIcon and options.DiscordIcon ~= "" then
		applyDiscordIcon(options.DiscordIcon)
	end

	if inviteCode ~= "" or (options.DiscordGuildId and options.DiscordGuildId ~= "") then
		Util.Spawn(function()
			local data = nil
			if inviteCode ~= "" then
				local urls = {
					"https://discord.com/api/v10/invites/" .. inviteCode .. "?with_counts=true&with_expiration=true",
					"https://discord.com/api/v9/invites/" .. inviteCode .. "?with_counts=true&with_expiration=true",
					"https://discordapp.com/api/v9/invites/" .. inviteCode .. "?with_counts=true&with_expiration=true",
				}
				for _, url in ipairs(urls) do
					local d, status = fetchJson(url)
					data = d
					if (data and (data.approximate_member_count ~= nil or data.approximate_presence_count ~= nil)) or status == 404 then
						break
					end
				end
			end
			if closed or not dcOnlineLabel.Parent then
				return
			end
			if type(data) == "table" and (data.approximate_member_count ~= nil or data.approximate_presence_count ~= nil) then
				local online = tonumber(data.approximate_presence_count) or 0
				local total = tonumber(data.approximate_member_count) or online
				dcOnlineLabel.Text = Util.FormatNumber(online)
				dcOfflineLabel.Text = Util.FormatNumber(math.max(total - online, 0))
				if data.guild and data.guild.name and (not options.DiscordName or options.DiscordName == "") then
					dcTitleLabel.Text = tostring(data.guild.name)
				end
				if (not options.DiscordIcon or options.DiscordIcon == "") and data.guild and data.guild.id and data.guild.icon then
					applyDiscordIcon("https://cdn.discordapp.com/icons/" .. tostring(data.guild.id) .. "/" .. tostring(data.guild.icon) .. ".png?size=128")
				end
			elseif options.DiscordGuildId and options.DiscordGuildId ~= "" then
				local w = fetchJson("https://discord.com/api/guilds/" .. tostring(options.DiscordGuildId) .. "/widget.json")
				if not closed and w and (w.presence_count ~= nil or type(w.members) == "table") then
					local online = tonumber(w.presence_count) or (type(w.members) == "table" and #w.members or 0)
					dcOnlineLabel.Text = Util.FormatNumber(online)
					dcOfflineLabel.Text = "—"
				else
					local fbOnline = tonumber(options.DiscordOnline)
					local fbTotal = tonumber(options.DiscordMembers)
					local fbOffline = tonumber(options.DiscordOffline)
					dcOnlineLabel.Text = fbOnline and Util.FormatNumber(fbOnline) or "—"
					if fbOffline then
						dcOfflineLabel.Text = Util.FormatNumber(fbOffline)
					elseif fbTotal and fbOnline then
						dcOfflineLabel.Text = Util.FormatNumber(math.max(fbTotal - fbOnline, 0))
					elseif fbTotal then
						dcOfflineLabel.Text = Util.FormatNumber(fbTotal)
					else
						dcOfflineLabel.Text = "—"
					end
				end
			else
				local fbOnline = tonumber(options.DiscordOnline)
				local fbTotal = tonumber(options.DiscordMembers)
				local fbOffline = tonumber(options.DiscordOffline)
				dcOnlineLabel.Text = fbOnline and Util.FormatNumber(fbOnline) or "—"
				if fbOffline then
					dcOfflineLabel.Text = Util.FormatNumber(fbOffline)
				elseif fbTotal and fbOnline then
					dcOfflineLabel.Text = Util.FormatNumber(math.max(fbTotal - fbOnline, 0))
				elseif fbTotal then
					dcOfflineLabel.Text = Util.FormatNumber(fbTotal)
				else
					dcOfflineLabel.Text = "—"
				end
			end
		end)
	end

	-- Information / Changelog Card (opens Slide-In Information Drawer)
	local infoCard = Create.New("TextButton", {
		Position = UDim2.fromOffset(0, 236),
		Size = UDim2.new(1, 0, 0, 74),
		Text = "",
		AutoButtonColor = false,
		Corner = 12,
		Theme = { BackgroundColor3 = "Tile" },
		BackgroundTransparency = 0.25,
		Visible = useWide,
		Parent = rightPane,
	})
	local infoCardStroke = Create.Stroke(infoCard, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })
	Transition.Hover(infoCard, infoCard, "Tile", "TileHover", infoCardStroke)

	local infoBadge = Create.New("Frame", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(34, 34),
		Corner = 9,
		Theme = { BackgroundColor3 = "Accent" },
		BackgroundTransparency = 0.85,
		Parent = infoCard,
	})
	Icons.Create("info", {
		Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "Accent",
		Parent = infoBadge,
	})
	Create.Text({
		Position = UDim2.fromOffset(55, 11),
		Size = UDim2.new(1, -82, 0, 17),
		Text = "Information",
		Font = "SemiBold",
		TextSize = 13,
		Color = "Text",
		Parent = infoCard,
	})
	Create.Text({
		Position = UDim2.fromOffset(55, 29),
		Size = UDim2.new(1, -82, 0, 15),
		Text = "Tap to view guide & updates",
		Font = "Regular",
		TextSize = 11,
		Color = "SubText",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = infoCard,
	})
	Icons.Create("chevron-right", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, -6),
		Size = UDim2.fromOffset(14, 14),
		Color = "SubText",
		Parent = infoCard,
	})
	Create.Text({
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.new(1, -24, 0, 14),
		Text = "What's new in " .. tostring(options.Version or "v1.0.0"),
		Font = "Medium",
		TextSize = 11,
		Color = "Accent",
		Parent = infoCard,
	})

	-- ─── Slide-In Information Drawer Overlay ──────────────────────────────────
	local infoOverlay = Create.New("TextButton", {
		Name = "InfoOverlay",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Theme = { BackgroundColor3 = "Overlay" },
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = mainCard,
	})
	local drawer = Create.New("Frame", {
		Name = "InfoDrawer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 340, 0, 10),
		Size = UDim2.new(0, math.min(320, cardW - 24), 1, -20),
		Corner = 13,
		Theme = { BackgroundColor3 = "Card" },
		BackgroundTransparency = 0,
		ZIndex = 21,
		Parent = infoOverlay,
	})
	Create.GlassStroke(drawer, 0.05)

	Create.Text({
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.new(1, -60, 0, 20),
		Text = "Information",
		Font = "Bold",
		TextSize = 15,
		Color = "Text",
		Parent = drawer,
	})
	local drawerClose = Create.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(26, 26),
		Text = "",
		AutoButtonColor = false,
		Corner = 7,
		Theme = { BackgroundColor3 = "Tile" },
		Parent = drawer,
	})
	Create.Stroke(drawerClose, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })
	Icons.Create("x", {
		Size = UDim2.fromOffset(13, 13),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "SubText",
		Parent = drawerClose,
	})

	local drawerScroll = Create.New("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Padding = { 4, 14, 10, 14 },
		Parent = drawer,
	})
	Create.List(drawerScroll, { Gap = 8 })

	local function addDrawerRow(labelText, valText, colorKey)
		local row = Create.New("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			Corner = 9,
			Theme = { BackgroundColor3 = "Tile" },
			BackgroundTransparency = 0.2,
			Padding = { 0, 10, 0, 10 },
			Parent = drawerScroll,
		})
		Create.Stroke(row, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })
		Create.Text({
			Text = labelText,
			Font = "Regular",
			TextSize = 12,
			Color = "SubText",
			Size = UDim2.new(0.5, 0, 1, 0),
			Parent = row,
		})
		Create.Text({
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			Text = tostring(valText),
			Font = "SemiBold",
			TextSize = 12,
			Color = colorKey or "Text",
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
	end

	Create.Text({
		Text = "SESSION STATUS",
		Font = "Bold",
		TextSize = 11,
		Color = "Accent",
		Size = UDim2.new(1, 0, 0, 18),
		Parent = drawerScroll,
	})
	addDrawerRow("Game Status", statusText, statusColorKey)
	addDrawerRow("Executor", execName)
	addDrawerRow("Place ID", tostring(game.PlaceId or 0))

	local changelogList = type(options.Changelog) == "table" and options.Changelog or {
		{ Version = tostring(options.Version or "v1.0.0"), Date = "Latest", Changes = { "Hardware-accelerated animations & Key System" } },
	}
	Create.Text({
		Text = "CHANGELOG",
		Font = "Bold",
		TextSize = 11,
		Color = "Accent",
		Size = UDim2.new(1, 0, 0, 20),
		Parent = drawerScroll,
	})
	for _, entry in ipairs(changelogList) do
		local cFrame = Create.New("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Corner = 10,
			Theme = { BackgroundColor3 = "Tile" },
			BackgroundTransparency = 0.2,
			Padding = { 9, 10, 9, 10 },
			Parent = drawerScroll,
		})
		Create.Stroke(cFrame, { Theme = { Color = "Stroke", Transparency = "StrokeTransparency" } })
		Create.List(cFrame, { Gap = 4 })
		Create.Text({
			Text = tostring(entry.Version or "Release") .. "  ·  " .. tostring(entry.Date or ""),
			Font = "SemiBold",
			TextSize = 11,
			Color = "Accent",
			Size = UDim2.new(1, 0, 0, 16),
			Parent = cFrame,
		})
		for _, ch in ipairs(entry.Changes or {}) do
			Create.Text({
				Text = "•  " .. tostring(ch),
				Font = "Regular",
				TextSize = 11,
				Color = "SubText",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				Parent = cFrame,
			})
		end
	end

	local infoOpen = false
	local function openInfoDrawer()
		if infoOpen then
			return
		end
		infoOpen = true
		infoOverlay.Visible = true
		Tween.Play(infoOverlay, { BackgroundTransparency = 0.45 }, Tween.Fast)
		drawer.Position = UDim2.new(1, 340, 0, 10)
		Tween.Spring(drawer, { Position = UDim2.new(1, -10, 0, 10) }, 0.26)
	end
	local function closeInfoDrawer()
		if not infoOpen then
			return
		end
		infoOpen = false
		Tween.Play(infoOverlay, { BackgroundTransparency = 1 }, Tween.Fast)
		Tween.Play(drawer, { Position = UDim2.new(1, 340, 0, 10) }, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		task.delay(0.2, function()
			if not infoOpen and infoOverlay.Parent then
				infoOverlay.Visible = false
			end
		end)
	end

	maid:Give(infoCard.Activated:Connect(openInfoDrawer))
	maid:Give(infoIconBtn.Activated:Connect(openInfoDrawer))
	maid:Give(helpBtn.Activated:Connect(openInfoDrawer))
	maid:Give(drawerClose.Activated:Connect(closeInfoDrawer))
	maid:Give(infoOverlay.Activated:Connect(closeInfoDrawer))

	-- ─── Animated Access Granted Overlay ──────────────────────────────────────
	local successView = Create.New("Frame", {
		Name = "SuccessOverlay",
		Size = UDim2.fromScale(1, 1),
		Theme = { BackgroundColor3 = "Card" },
		BackgroundTransparency = 0.02,
		Corner = 16,
		Visible = false,
		ZIndex = 30,
		Parent = mainCard,
	})
	local sCircle = Create.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -42),
		Size = UDim2.fromOffset(66, 66),
		Corner = 999,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = successView,
	})
	local sGrad = Instance.new("UIGradient")
	sGrad.Color = Theme.AccentSequence()
	sGrad.Rotation = 40
	sGrad.Parent = sCircle
	Icons.Create("check", {
		Size = UDim2.fromOffset(28, 28),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "AccentText",
		Parent = sCircle,
	})
	Create.Text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.fromOffset(320, 26),
		Text = "Access granted",
		Font = "Bold",
		TextSize = 20,
		Color = "Text",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = successView,
	})
	Create.Text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 34),
		Size = UDim2.fromOffset(340, 18),
		Text = "Welcome — preparing " .. tostring(options.Title or "Bali"),
		Font = "Regular",
		TextSize = 12,
		Color = "SubText",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = successView,
	})
	local sTrack = Create.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 66),
		Size = UDim2.fromOffset(220, 6),
		Corner = UDim.new(1, 0),
		Theme = { BackgroundColor3 = "Tile" },
		ClipsDescendants = true,
		Parent = successView,
	})
	local sFill = Create.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		Corner = UDim.new(1, 0),
		Theme = { BackgroundColor3 = "Accent" },
		Parent = sTrack,
	})

	-- ─── Submit / Verify Handler ──────────────────────────────────────────────
	local function submit(input)
		if busy or closed then
			return
		end
		if os.clock() < cooldownUntil then
			shakeError(string.format("Too many attempts. Wait %.0fs.", math.ceil(cooldownUntil - os.clock())))
			return
		end

		busy = true
		if input then
			Transition.Ripple(verifyBtn, input, "AccentText")
		end
		verifyLabel.Text = "Verifying..."
		local entered = Util.Trim(keyBox.Text)

		task.spawn(function()
			local ok, message = verifyKey(entered)
			busy = false
			if closed then
				return
			end
			if ok then
				verified = true
				finalKey = entered
				controller.Verified = true
				controller.Key = entered
				writeSavedKey(runtimeOpts, entered)
				verifyLabel.Text = "Verified"
				feedbackLabel.Text = tostring(message or "Access granted.")
				Theme.Bind(feedbackLabel, { TextColor3 = "Success" })
				feedbackLabel.Visible = true
				Theme.Bind(fieldStroke, { Color = "Success" })

				successView.Visible = true
				Tween.Play(sFill, { Size = UDim2.fromScale(1, 1) }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
				task.wait(0.38)
				controller:Close()
				if type(options.OnSuccess) == "function" then
					Util.Spawn(options.OnSuccess, entered)
				end
			else
				if (tonumber(options.MaxAttempts) or 0) > 0 then
					attemptsLeft = math.max(attemptsLeft - 1, 0)
					if attemptsLeft <= 0 then
						cooldownUntil = os.clock() + (tonumber(options.Cooldown) or 8)
						attemptsLeft = tonumber(options.MaxAttempts) or 5
						attemptsLabel.Text = "Cooldown..."
					else
						attemptsLabel.Text = tostring(attemptsLeft) .. " left"
					end
				end
				verifyLabel.Text = "Verify Key"
				shakeError(message)
			end
		end)
	end

	maid:Give(verifyBtn.Activated:Connect(submit))
	maid:Give(keyBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end))

	Transition.Mount(container, 0.94)

	if options.Yield then
		return controller:Wait()
	end
	return controller
end

return Loader
