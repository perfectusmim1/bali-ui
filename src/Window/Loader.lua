--[[
	Lumina UI · Window/Loader
	Glassmorphic LoadingScreen splash and KeySystem verification modal with
	Get Key clipboard copy, Check Key verification, error shake, and saved key support.
]]

local Assets = require("Core/Assets")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Maid = require("Core/Maid")
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
			BackgroundTransparency = "CardTransparency",
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
			Size = UDim2.fromOffset(280, 280),
			Position = UDim2.fromOffset(-100, -110),
			BackgroundTransparency = 1,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = card,
		})
		Create.New("ImageLabel", {
			Name = "GlowBottom",
			Image = glowAsset,
			AnchorPoint = Vector2.new(1, 1),
			Size = UDim2.fromOffset(260, 260),
			Position = UDim2.new(1, 110, 1, 110),
			BackgroundTransparency = 1,
			Theme = {
				ImageColor3 = "Accent2",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = card,
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
	assert(typeof(parentGui) == "Instance", "[Lumina] Loader.LoadingScreen expects a parentGui Instance")
	if not Assets.Loaded then
		pcall(Assets.Load)
	end

	options = Util.Options(options, {
		Title = "Lumina",
		Subtitle = "Preparing workspace...",
		Icon = "sparkles",
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

	local badge = Create.New("Frame", {
		Size = UDim2.fromOffset(40, 40),
		Corner = 11,
		Theme = { BackgroundColor3 = "Accent" },
		LayoutOrder = 1,
		Parent = header,
	})
	local badgeGrad = Instance.new("UIGradient")
	badgeGrad.Color = Theme.AccentSequence()
	badgeGrad.Rotation = 35
	badgeGrad.Parent = badge
	maid:Give(Theme.Changed:Connect(function(theme)
		badgeGrad.Color = Theme.AccentSequence(theme)
	end))

	local badgeIcon = Icons.Create(options.Icon or "sparkles", {
		Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "AccentText",
		Parent = badge,
	})
	if badgeIcon then
		local stopPulse = Transition.Pulse(badgeIcon, Icons.TransparencyProperty(badgeIcon), 0, 0.45, 0.9)
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
		Text = tostring(options.Title or "Lumina"),
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
		Size = UDim2.new(1, 0, 0, 6),
		Corner = 999,
		Theme = { BackgroundColor3 = "Field" },
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = progressBlock,
	})

	local fill = Create.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		Corner = 999,
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
	local folder = options.Folder or "Lumina"
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
	local folder = options.Folder or "Lumina"
	Util.FS.MakeFolder(folder)
	local path = options.SavePath or (folder .. "/" .. tostring(options.FileName or "key.txt"))
	Util.FS.Write(path, tostring(key))
end

function Loader.KeySystem(parentGui, options)
	assert(typeof(parentGui) == "Instance", "[Lumina] Loader.KeySystem expects a parentGui Instance")
	if not Assets.Loaded then
		pcall(Assets.Load)
	end

	options = Util.Options(options, {
		Title = "Key Verification",
		Subtitle = "Enter your access key to unlock this workspace.",
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
		Folder = "Lumina",
		FileName = "key.txt",
		SavePath = nil,
		Closable = true,
		Yield = false,
		OnSuccess = nil,
		OnCancel = nil,
	}, "Title")

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

	local savedValid = checkSavedKey(options, verifyKey)
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

	local root, backdrop, container, _, inner = createBackdropAndCard(parentGui, maid, 400, true)

	local header = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = inner,
	})

	local leftHeader = Create.New("Frame", {
		Size = UDim2.new(1, options.Closable ~= false and -32 or 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = header,
	})
	Create.List(leftHeader, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 10,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local iconBadge = Create.New("Frame", {
		Size = UDim2.fromOffset(36, 36),
		Corner = 10,
		Theme = { BackgroundColor3 = "Accent" },
		BackgroundTransparency = 0.86,
		LayoutOrder = 1,
		Parent = leftHeader,
	})
	Create.Stroke(iconBadge, { Theme = { Color = "Accent" }, Transparency = 0.72 })
	Icons.Create(options.Icon or "key", {
		Size = UDim2.fromOffset(17, 17),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "Accent",
		Parent = iconBadge,
	})

	local headerText = Create.New("Frame", {
		Size = UDim2.new(1, -46, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = leftHeader,
	})
	Create.List(headerText, { Gap = 2 })

	Create.Text({
		Text = tostring(options.Title or "Key Verification"),
		Font = "SemiBold",
		TextSize = 16,
		Color = "Text",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = headerText,
	})

	local subText = options.Note or options.Subtitle
	if subText and tostring(subText) ~= "" then
		Create.Text({
			Text = tostring(subText),
			Font = "Regular",
			TextSize = 12,
			Color = "SubText",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 2,
			Parent = headerText,
		})
	end

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

	if options.Closable ~= false then
		local closeBtn = Create.New("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(28, 28),
			Text = "",
			Corner = 8,
			Theme = { BackgroundColor3 = "Tile", BackgroundTransparency = "TileTransparency" },
			Parent = header,
		})
		local closeStroke = Create.Stroke(closeBtn, {
			Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
		})
		Icons.Create("x", {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Color = "SubText",
			Parent = closeBtn,
		})
		Transition.Hover(closeBtn, closeBtn, "Tile", "TileHover", closeStroke)
		maid:Give(closeBtn.Activated:Connect(function()
			controller:Close()
			if type(options.OnCancel) == "function" then
				Util.Spawn(options.OnCancel)
			end
		end))
	end

	-- Input Field
	local field = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		Corner = 9,
		Theme = { BackgroundColor3 = "Field" },
		LayoutOrder = 2,
		Parent = inner,
	})
	local fieldStroke = Create.Stroke(field, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})

	local keyBox = Create.New("TextBox", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Text = "",
		PlaceholderText = "Paste your key here...",
		TextSize = 13,
		Font = "Regular",
		Theme = {
			TextColor3 = "Text",
			PlaceholderColor3 = "Muted",
		},
		Parent = field,
	})

	maid:Give(keyBox.Focused:Connect(function()
		Theme.Bind(fieldStroke, { Color = "Accent" })
		Tween.Play(fieldStroke, { Transparency = 0.25 }, Tween.Fast)
	end))
	maid:Give(keyBox.FocusLost:Connect(function()
		Theme.Bind(fieldStroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
	end))

	local feedbackLabel = Create.Text({
		Text = "",
		Font = "Medium",
		TextSize = 12,
		Color = "Error",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Visible = false,
		LayoutOrder = 3,
		Parent = inner,
	})

	local function shakeError(msg)
		feedbackLabel.Text = tostring(msg or "Invalid key.")
		Theme.Bind(feedbackLabel, { TextColor3 = "Error" })
		feedbackLabel.Visible = true
		Theme.Bind(fieldStroke, { Color = "Error" })
		fieldStroke.Transparency = 0.25

		task.spawn(function()
			local offsets = { -10, 10, -7, 7, -3, 0 }
			for _, offset in ipairs(offsets) do
				if closed or not container.Parent then
					return
				end
				Tween.Play(container, { Position = UDim2.new(0.5, offset, 0.5, 0) }, 0.045, Enum.EasingStyle.Quad)
				task.wait(0.045)
			end
		end)
	end

	-- Action buttons row
	local keyLink = options.KeyUrl or options.GetKeyUrl or options.Link or options.KeyLink
	local hasGetKey = (keyLink ~= nil and keyLink ~= "") or type(options.OnGetKey) == "function"

	local btnRow = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = inner,
	})
	Create.List(btnRow, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 8,
	})

	if hasGetKey then
		local getBtn = Create.New("TextButton", {
			Size = UDim2.new(0.5, -4, 1, 0),
			Text = "",
			AutoButtonColor = false,
			ClipsDescendants = true,
			Corner = 9,
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
			getLabel.Text = "Copied Link!"
			task.delay(1.8, function()
				if getLabel.Parent then
					getLabel.Text = "Get Key"
				end
			end)
		end))
	end

	local verifyBtn = Create.New("TextButton", {
		Size = hasGetKey and UDim2.new(0.5, -4, 1, 0) or UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Corner = 9,
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
		Size = UDim2.fromOffset(14, 14),
		Color = "AccentText",
		LayoutOrder = 1,
		Parent = verifyInner,
	})
	local verifyLabel = Create.Text({
		Text = "Check Key",
		Font = "SemiBold",
		TextSize = 13,
		Color = "AccentText",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = verifyInner,
	})

	local function submit(input)
		if busy or closed then
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
				writeSavedKey(options, entered)
				verifyLabel.Text = "Verified"
				feedbackLabel.Text = tostring(message or "Access granted.")
				Theme.Bind(feedbackLabel, { TextColor3 = "Success" })
				feedbackLabel.Visible = true
				Theme.Bind(fieldStroke, { Color = "Success" })
				task.wait(0.35)
				controller:Close()
				if type(options.OnSuccess) == "function" then
					Util.Spawn(options.OnSuccess, entered)
				end
			else
				verifyLabel.Text = "Check Key"
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
