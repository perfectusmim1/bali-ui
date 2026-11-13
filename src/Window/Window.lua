--[[
	Lumina UI · Window/Window
	Main obsidian glassmorphic desktop/mobile window with collapsible sidebar,
	spotlight search pill, top breadcrumb & quick-action bar, popup manager,
	dialog & notification layers, and full system integration.
]]

local Assets = require("Core/Assets")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Maid = require("Core/Maid")
local Services = require("Core/Services")
local Signal = require("Core/Signal")
local Theme = require("Core/Theme")
local Transition = require("Core/Transition")
local Tween = require("Core/Tween")
local Util = require("Core/Util")

local Blur = require("Systems/Blur")
local CommandPalette = require("Systems/CommandPalette")
local Config = require("Systems/Config")
local Input = require("Systems/Input")
local KeybindList = require("Systems/KeybindList")
local Notification = require("Systems/Notification")
local Tooltip = require("Systems/Tooltip")
local Watermark = require("Systems/Watermark")

local Dialog = require("Window/Dialog")
local MobileButton = require("Window/MobileButton")
local Tab = require("Window/Tab")

local Window = {}
Window.__index = Window

local SIDEBAR_EXPANDED = 212
local SIDEBAR_COLLAPSED = 58
local TOPBAR_HEIGHT = 52
local POPUP_PAD = 8

local function getViewportSize(screenGui)
	if screenGui and screenGui:IsA("LayerCollector") and screenGui.AbsoluteSize.X > 0 and screenGui.AbsoluteSize.Y > 0 then
		return screenGui.AbsoluteSize
	end
	local cam = Services.Workspace.CurrentCamera
	local raw = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local ok, inset = pcall(function()
		return Services.GuiService:GetGuiInset()
	end)
	if ok and inset then
		return Vector2.new(raw.X - inset.X, raw.Y - inset.Y)
	end
	return raw
end

local function parseSizeVector(sizeOpt, defaultVec)
	if typeof(sizeOpt) == "Vector2" then
		return sizeOpt
	elseif typeof(sizeOpt) == "UDim2" then
		return Vector2.new(sizeOpt.X.Offset, sizeOpt.Y.Offset)
	end
	return defaultVec
end

local function createActionButton(parent, iconName, tooltipText, layoutOrder, maid)
	local btn = Create.New("TextButton", {
		Name = "Action_" .. tostring(iconName),
		Size = UDim2.fromOffset(30, 30),
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Corner = 8,
		Theme = {
			BackgroundColor3 = "Tile",
			BackgroundTransparency = "TileTransparency",
		},
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	local stroke = Create.Stroke(btn, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})
	local iconInst = Icons.Create(iconName, {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "SubText",
		Parent = btn,
	})
	maid:Give(Transition.Hover(btn, btn, "Tile", "TileHover", stroke))
	if tooltipText and tooltipText ~= "" then
		maid:Give(Tooltip.Bind(btn, tooltipText))
	end
	return btn, iconInst, stroke
end

function Window.new(screenGui, options)
	assert(typeof(screenGui) == "Instance", "[Lumina] Window.new expects a ScreenGui or LayerCollector")
	if not Assets.Loaded then
		pcall(Assets.Load)
	end

	options = Util.Options(options, {
		Title = "Lumina",
		Subtitle = nil,
		Version = nil,
		Icon = "sparkles",
		WelcomeSubtitle = nil,
		ShowUser = false,
		Size = UDim2.fromOffset(820, 540),
		MinSize = Vector2.new(460, 360),
		MaxSize = Vector2.new(1280, 900),
		SidebarWidth = SIDEBAR_EXPANDED,
		SidebarCollapsed = false,
		Theme = nil,
		Accent = nil,
		Font = nil,
		ToggleKey = Enum.KeyCode.RightShift,
		Blur = nil,
		BlurIntensity = nil,
		Watermark = nil,
		KeybindList = nil,
		NotificationPosition = "BottomRight",
		MobileButton = true,
		ConfigFolder = nil,
		Folder = nil,
		AutoLoadConfig = false,
		ConfirmClose = true,
		DestroyOnClose = false,
		OwnsScreenGui = false,
		OnClose = nil,
		OnDestroy = nil,
	}, "Title")

	if options.Theme and Theme.Presets[options.Theme] then
		Theme.Set(options.Theme, false)
	end
	if typeof(options.Accent) == "Color3" then
		Theme.SetAccent(options.Accent, false)
	end
	if options.Font and Theme.Fonts[options.Font] then
		Theme.SetFont(options.Font)
	end

	local maid = Maid.new()
	local windowId = Util.RandomString(8)

	-- Root ZIndex-isolated layers
	local mainLayer = Create.New("Frame", {
		Name = "LuminaMainLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = screenGui,
	})
	local hudLayer = Create.New("Frame", {
		Name = "LuminaHUDLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = screenGui,
	})
	local popupLayer = Create.New("Frame", {
		Name = "LuminaPopupLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 100,
		Parent = screenGui,
	})
	local dialogLayer = Create.New("Frame", {
		Name = "LuminaDialogLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 200,
		Parent = screenGui,
	})
	local notificationLayer = Create.New("Frame", {
		Name = "LuminaNotificationLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 300,
		Parent = screenGui,
	})

	maid:Give(mainLayer)
	maid:Give(hudLayer)
	maid:Give(popupLayer)
	maid:Give(dialogLayer)
	maid:Give(notificationLayer)

	-- Popup click-catcher backdrop inside PopupLayer
	local popupBackdrop = Create.New("TextButton", {
		Name = "PopupBackdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 1,
		Parent = popupLayer,
	})

	-- Compute initial viewport-clamped window dimensions
	local vp = getViewportSize(screenGui)
	local desiredSize = parseSizeVector(options.Size, Vector2.new(820, 540))
	local reqMin = parseSizeVector(options.MinSize, Vector2.new(460, 360))
	local reqMax = parseSizeVector(options.MaxSize, Vector2.new(1280, 900))

	local minW = math.min(reqMin.X, math.max(300, vp.X - 16))
	local minH = math.min(reqMin.Y, math.max(260, vp.Y - 16))
	local effectiveMin = Vector2.new(minW, minH)

	local initW = Util.Clamp(desiredSize.X, minW, math.max(minW, vp.X - 24))
	local initH = Util.Clamp(desiredSize.Y, minH, math.max(minH, vp.Y - 24))
	local startX = math.max(8, math.floor((vp.X - initW) * 0.5))
	local startY = math.max(8, math.floor((vp.Y - initH) * 0.5))

	-- Wrapper holds Shadow + clipped Main frame so Shadow tracks Drag/Resize/Mount seamlessly
	local mainWrapper = Create.New("Frame", {
		Name = "LuminaWindowWrapper",
		Position = UDim2.fromOffset(startX, startY),
		Size = UDim2.fromOffset(initW, initH),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = mainLayer,
	})

	local shadowDesc = Assets.Shadow()
	Create.New("ImageLabel", {
		Name = "WindowShadow",
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
		Parent = mainWrapper,
	})

	local main = Create.New("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		Theme = {
			BackgroundColor3 = "Background",
			BackgroundTransparency = "BackgroundTransparency",
		},
		Corner = 14,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = mainWrapper,
	})
	Create.GlassStroke(main, 0.04)

	-- Ambient obsidian glass radial blooms & grain
	local glowAsset = Assets.Get("Glow")
	if glowAsset and Assets.Available then
		Create.New("ImageLabel", {
			Name = "GlowTopLeft",
			Image = glowAsset,
			Size = UDim2.fromOffset(420, 420),
			Position = UDim2.fromOffset(-150, -150),
			BackgroundTransparency = 1,
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = main,
		})
		Create.New("ImageLabel", {
			Name = "GlowBottomRight",
			Image = glowAsset,
			AnchorPoint = Vector2.new(1, 1),
			Size = UDim2.fromOffset(420, 420),
			Position = UDim2.new(1, 160, 1, 160),
			BackgroundTransparency = 1,
			Theme = {
				ImageColor3 = "Accent2",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = main,
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
			Parent = main,
		})
	end

	-- ─── Left Sidebar ────────────────────────────────────────────────────────
	local expandedWidth = tonumber(options.SidebarWidth) or SIDEBAR_EXPANDED
	local isCollapsed = options.SidebarCollapsed == true or (initW < 580 and options.SidebarCollapsed ~= false)
	local startSidebarW = isCollapsed and SIDEBAR_COLLAPSED or expandedWidth

	local sidebar = Create.New("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, startSidebarW, 1, 0),
		Theme = {
			BackgroundColor3 = "Sidebar",
			BackgroundTransparency = "SidebarTransparency",
		},
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = main,
	})

	Create.New("Frame", {
		Name = "RightBorder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 1, 1, 0),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		ZIndex = 4,
		Parent = sidebar,
	})

	local sidebarTop = Create.New("Frame", {
		Name = "SidebarTop",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 10, 10, 8, 10 },
		ZIndex = 3,
		Parent = sidebar,
	})
	Create.List(sidebarTop, { Gap = 8 })

	-- Brand Row
	local brandRow = Create.New("Frame", {
		Name = "BrandRow",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = sidebarTop,
	})

	local brandBadge = Create.New("TextButton", {
		Name = "BrandBadge",
		Position = UDim2.fromOffset(3, 2),
		Size = UDim2.fromOffset(32, 32),
		Text = "",
		AutoButtonColor = false,
		Corner = 8,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = brandRow,
	})
	local brandGrad = Instance.new("UIGradient")
	brandGrad.Color = Theme.AccentSequence()
	brandGrad.Rotation = 35
	brandGrad.Parent = brandBadge
	maid:Give(Theme.Changed:Connect(function(theme)
		brandGrad.Color = Theme.AccentSequence(theme)
	end))

	Icons.Create(options.Icon or "sparkles", {
		Size = UDim2.fromOffset(17, 17),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "AccentText",
		Parent = brandBadge,
	})

	local brandText = Create.New("Frame", {
		Name = "BrandText",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -72, 1, 0),
		BackgroundTransparency = 1,
		Visible = not isCollapsed,
		Parent = brandRow,
	})
	Create.List(brandText, { Gap = 1, VAlign = Enum.VerticalAlignment.Center })

	local titleRow = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = brandText,
	})
	Create.List(titleRow, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local brandTitleLabel = Create.Text({
		Name = "Title",
		Text = tostring(options.Title or "Lumina"),
		Font = "Bold",
		TextSize = 14,
		Color = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
		Parent = titleRow,
	})

	local subtitleText = options.Subtitle or options.Version
	local brandSubLabel = Create.Text({
		Name = "Subtitle",
		Text = subtitleText and tostring(subtitleText) or "",
		Font = "Medium",
		TextSize = 10,
		Color = "Muted",
		Size = UDim2.new(1, 0, 0, 13),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = subtitleText ~= nil and tostring(subtitleText) ~= "",
		LayoutOrder = 2,
		Parent = brandText,
	})

	local collapseBtn = Create.New("TextButton", {
		Name = "CollapseButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		Text = "",
		AutoButtonColor = false,
		Corner = 7,
		Theme = { BackgroundColor3 = "Tile" },
		BackgroundTransparency = 1,
		Visible = not isCollapsed,
		Parent = brandRow,
	})
	local collapseStroke = Create.Stroke(collapseBtn, {
		Theme = { Color = "Stroke" },
		Transparency = 1,
	})
	Icons.Create("chevron-left", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "SubText",
		Parent = collapseBtn,
	})
	maid:Give(collapseBtn.MouseEnter:Connect(function()
		Tween.Play(collapseBtn, { BackgroundTransparency = Theme.Current.TileTransparency }, Tween.Instant)
		Tween.Play(collapseStroke, { Transparency = Theme.Current.StrokeTransparency }, Tween.Instant)
	end))
	maid:Give(collapseBtn.MouseLeave:Connect(function()
		Tween.Play(collapseBtn, { BackgroundTransparency = 1 }, Tween.Instant)
		Tween.Play(collapseStroke, { Transparency = 1 }, Tween.Instant)
	end))

	-- Optional Welcome / User block
	local welcomeCard
	local showWelcome = (options.WelcomeSubtitle ~= nil and options.WelcomeSubtitle ~= "") or options.ShowUser == true
	if showWelcome then
		local displayName = "Guest"
		pcall(function()
			local lp = Services.Players.LocalPlayer
			if lp then
				displayName = lp.DisplayName ~= "" and lp.DisplayName or lp.Name
			end
		end)
		local welcomeMainText = options.WelcomeSubtitle and tostring(options.WelcomeSubtitle)
			or ("Welcome Back, " .. displayName)

		welcomeCard = Create.New("Frame", {
			Name = "WelcomeBlock",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Corner = 9,
			Theme = {
				BackgroundColor3 = "Tile",
				BackgroundTransparency = "TileTransparency",
			},
			Padding = { 8, 9, 8, 9 },
			Visible = not isCollapsed,
			LayoutOrder = 2,
			Parent = sidebarTop,
		})
		Create.GlassStroke(welcomeCard, 0.02)
		Create.List(welcomeCard, {
			Direction = Enum.FillDirection.Horizontal,
			Gap = 8,
			VAlign = Enum.VerticalAlignment.Center,
		})

		local avatarWrap = Create.New("Frame", {
			Size = UDim2.fromOffset(26, 26),
			Corner = 999,
			Theme = { BackgroundColor3 = "Accent" },
			BackgroundTransparency = 0.85,
			ClipsDescendants = true,
			LayoutOrder = 1,
			Parent = welcomeCard,
		})
		local avatarFallback = Icons.Create("user", {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Color = "Accent",
			Parent = avatarWrap,
		})
		task.spawn(function()
			local lp = Services.Players.LocalPlayer
			if not lp then
				return
			end
			local ok, thumb, ready = pcall(function()
				return Services.Players:GetUserThumbnailAsync(
					lp.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size48x48
				)
			end)
			if ok and ready and type(thumb) == "string" and thumb ~= "" and avatarWrap.Parent then
				if avatarFallback then
					avatarFallback.Visible = false
				end
				Create.New("ImageLabel", {
					Size = UDim2.fromScale(1, 1),
					Image = thumb,
					BackgroundTransparency = 1,
					Corner = 999,
					Parent = avatarWrap,
				})
			end
		end)

		local userText = Create.New("Frame", {
			Size = UDim2.new(1, -34, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = welcomeCard,
		})
		Create.List(userText, { Gap = 1 })
		Create.Text({
			Text = "Workspace Active",
			Font = "Medium",
			TextSize = 10,
			Color = "Muted",
			Size = UDim2.new(1, 0, 0, 12),
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
			Parent = userText,
		})
		Create.Text({
			Text = welcomeMainText,
			Font = "SemiBold",
			TextSize = 11,
			Color = "Text",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 2,
			Parent = userText,
		})
	end

	-- Spotlight Search Pill
	local searchPill = Create.New("TextButton", {
		Name = "SpotlightPill",
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Corner = 9,
		Theme = { BackgroundColor3 = "Field" },
		LayoutOrder = 3,
		Parent = sidebarTop,
	})
	local searchStroke = Create.Stroke(searchPill, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})
	maid:Give(Transition.Hover(searchPill, searchPill, "Field", "FieldHover", searchStroke))

	Icons.Create("search", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Color = "SubText",
		Parent = searchPill,
	})

	local searchPlaceholder = Create.Text({
		Text = "Search...",
		Font = "Regular",
		TextSize = 12,
		Color = "Muted",
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -84, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = not isCollapsed,
		Parent = searchPill,
	})

	local shortcutChip = Create.New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(42, 18),
		Corner = 5,
		Theme = { BackgroundColor3 = "Tile", BackgroundTransparency = "TileTransparency" },
		Visible = not isCollapsed,
		Parent = searchPill,
	})
	Create.Text({
		Text = "Ctrl+K",
		Font = "SemiBold",
		TextSize = 10,
		Color = "Muted",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = shortcutChip,
	})

	maid:Give(searchPill.Activated:Connect(function(input)
		Transition.Ripple(searchPill, input, "Accent")
		CommandPalette.Open()
	end))
	maid:Give(Tooltip.Bind(searchPill, "Search commands & elements (Ctrl+K)"))

	-- Tab Scrolling Container (dynamically positioned right beneath SidebarTop)
	local tabScroll = Create.New("ScrollingFrame", {
		Name = "TabNavigation",
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 1, -108),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 2,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Theme = { ScrollBarImageColor3 = "Muted" },
		Padding = { 2, 8, 12, 8 },
		ZIndex = 3,
		Parent = sidebar,
	})
	Create.List(tabScroll, { Gap = 3 })

	local function syncTabScrollBounds()
		local topH = sidebarTop.AbsoluteSize.Y
		tabScroll.Position = UDim2.fromOffset(0, topH)
		tabScroll.Size = UDim2.new(1, 0, 1, -topH)
	end
	maid:Give(sidebarTop:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncTabScrollBounds))
	task.defer(syncTabScrollBounds)

	-- ─── Right Body Area & Top Header Bar ────────────────────────────────────
	local bodyArea = Create.New("Frame", {
		Name = "BodyArea",
		Position = UDim2.new(0, startSidebarW, 0, 0),
		Size = UDim2.new(1, -startSidebarW, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = main,
	})

	local topbar = Create.New("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = bodyArea,
	})

	Create.New("Frame", {
		Name = "BottomBorder",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = topbar,
	})

	-- Quick Action Glass Pills (Right)
	local actionsWrap = Create.New("Frame", {
		Name = "QuickActions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = topbar,
	})
	Create.List(actionsWrap, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local topSearchBtn = createActionButton(actionsWrap, "search", "Command Palette (Ctrl+K)", 1, maid)
	local themeBtn, themeIcon = createActionButton(
		actionsWrap,
		Theme.Current.Dark and "sun" or "moon",
		"Switch Light / Dark Theme",
		2,
		maid
	)
	local bellBtn = createActionButton(actionsWrap, "bell", "Notifications", 3, maid)
	local minBtn = createActionButton(actionsWrap, "minus", "Minimize Window", 4, maid)
	local closeBtn, closeIcon = createActionButton(actionsWrap, "x", "Close UI", 5, maid)

	-- Unread notification dot on Bell
	local unreadDot = Create.New("Frame", {
		Name = "UnreadDot",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(7, 7),
		Corner = 999,
		Theme = { BackgroundColor3 = "Accent" },
		Visible = Notification.UnreadCount > 0,
		ZIndex = 3,
		Parent = bellBtn,
	})

	-- Left Breadcrumb Trail
	local breadcrumbWrap = Create.New("Frame", {
		Name = "Breadcrumb",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -206, 1, 0),
		BackgroundTransparency = 1,
		Parent = topbar,
	})
	Create.List(breadcrumbWrap, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 8,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local expandBtn = Create.New("TextButton", {
		Name = "ExpandSidebarBtn",
		Size = UDim2.fromOffset(28, 28),
		Text = "",
		AutoButtonColor = false,
		Corner = 8,
		Theme = {
			BackgroundColor3 = "Tile",
			BackgroundTransparency = "TileTransparency",
		},
		Visible = isCollapsed,
		LayoutOrder = 1,
		Parent = breadcrumbWrap,
	})
	local expandStroke = Create.Stroke(expandBtn, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})
	Icons.Create("panel-left", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "SubText",
		Parent = expandBtn,
	})
	maid:Give(Transition.Hover(expandBtn, expandBtn, "Tile", "TileHover", expandStroke))
	maid:Give(Tooltip.Bind(expandBtn, "Expand Sidebar"))

	Icons.Create("home", {
		Size = UDim2.fromOffset(14, 14),
		Color = "Muted",
		LayoutOrder = 2,
		Parent = breadcrumbWrap,
	})

	local breadcrumbLabel = Create.Text({
		Name = "Trail",
		Text = tostring(options.Title or "Lumina"),
		Font = "Medium",
		TextSize = 12,
		Color = "SubText",
		Size = UDim2.new(1, isCollapsed and -60 or -26, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
		LayoutOrder = 3,
		Parent = breadcrumbWrap,
	})

	local pageContainer = Create.New("Frame", {
		Name = "PageContainer",
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = bodyArea,
	})

	-- Bottom-Right Resize Grip
	local resizeGrip = Create.New("Frame", {
		Name = "ResizeGrip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -4),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		ZIndex = 15,
		Parent = main,
	})
	Icons.Create("grip", {
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = "Muted",
		Parent = resizeGrip,
	})
	maid:Give(Tooltip.Bind(resizeGrip, "Drag to resize"))

	-- ─── Window Instance Table ───────────────────────────────────────────────
	local registry = {}
	local self = setmetatable({
		Title = tostring(options.Title or "Lumina"),
		Subtitle = subtitleText and tostring(subtitleText) or "",
		Icon = options.Icon or "sparkles",
		ScreenGui = screenGui,
		MainLayer = mainLayer,
		HUDLayer = hudLayer,
		PopupLayer = popupLayer,
		DialogLayer = dialogLayer,
		NotificationLayer = notificationLayer,
		MainWrapper = mainWrapper,
		Main = main,
		Sidebar = sidebar,
		BodyArea = bodyArea,
		PageContainer = pageContainer,
		Maid = maid,
		Tabs = {},
		ActiveTab = nil,
		Flags = registry,
		_registry = registry,
		_elements = {},
		_categories = {},
		_categoryCount = 0,
		_uncategorizedOrder = 0,
		_currentCategory = nil,
		_tabScroll = tabScroll,
		_sidebarExpandedWidth = expandedWidth,
		_sidebarCollapsed = isCollapsed,
		_visible = true,
		_destroyed = false,
		_activePopup = nil,
		_layoutChanged = Signal.new(),
		_configLoaded = Signal.new(),
		_lastDarkTheme = Theme.Current.Dark and Theme.Name or "Midnight",
		_configFolder = options.ConfigFolder or options.Folder or "Lumina",
		_notificationPosition = options.NotificationPosition or "BottomRight",
		_keybindListMode = (type(options.KeybindList) == "table" and options.KeybindList.Mode) or "ActiveOnly",
		_toggleKey = Util.ResolveKey(options.ToggleKey) or Enum.KeyCode.RightShift,
		_ownsScreenGui = options.OwnsScreenGui == true,
		_confirmClose = options.ConfirmClose ~= false,
		_destroyOnClose = options.DestroyOnClose == true,
		_onClose = options.OnClose,
		_onDestroy = options.OnDestroy,
		_brandTitleLabel = brandTitleLabel,
		_brandSubLabel = brandSubLabel,
		_brandText = brandText,
		_collapseBtn = collapseBtn,
		_expandBtn = expandBtn,
		_welcomeCard = welcomeCard,
		_searchPlaceholder = searchPlaceholder,
		_shortcutChip = shortcutChip,
		_breadcrumbLabel = breadcrumbLabel,
		_unreadDot = unreadDot,
	}, Window)

	maid:Give(self._layoutChanged)
	maid:Give(self._configLoaded)

	-- ─── Initialize Systems ──────────────────────────────────────────────────
	Input.Init()
	Tooltip.Init(popupLayer)
	Notification.Init(notificationLayer)
	Notification.SetPosition(self._notificationPosition)
	Watermark.Init(hudLayer)
	KeybindList.Init(hudLayer)
	CommandPalette.Init(popupLayer, self)

	if options.Blur ~= nil then
		Blur.SetEnabled(options.Blur == true)
	end
	if options.BlurIntensity ~= nil then
		Blur.SetIntensity(options.BlurIntensity)
	end
	Blur.SetOpen(true)

	if type(options.Watermark) == "table" then
		if options.Watermark.Title then
			Watermark.SetTitle(options.Watermark.Title)
		else
			Watermark.SetTitle(self.Title)
		end
		if options.Watermark.Text then
			Watermark.SetText(options.Watermark.Text)
		end
		if options.Watermark.Stats then
			Watermark.SetStats(options.Watermark.Stats)
		end
		Watermark.SetVisible(options.Watermark.Enabled ~= false)
	elseif options.Watermark == true then
		Watermark.SetTitle(self.Title)
		Watermark.SetVisible(true)
	end

	if type(options.KeybindList) == "table" then
		if options.KeybindList.Mode then
			KeybindList.SetMode(options.KeybindList.Mode)
		end
		KeybindList.SetVisible(options.KeybindList.Enabled ~= false)
	elseif options.KeybindList == true then
		KeybindList.SetVisible(true)
	end

	-- Surface callback errors as Notification toasts safely
	local handlingError = false
	Util.ErrorHandler = function(err)
		if handlingError or self._destroyed then
			return
		end
		handlingError = true
		pcall(function()
			self:Notify({
				Title = "Callback Error",
				Content = tostring(err),
				Type = "Error",
				Duration = 5,
			})
		end)
		handlingError = false
	end
	maid:Give(function()
		Util.ErrorHandler = nil
	end)

	-- Drag & Resize bindings
	local dragHandle = Input.BindDrag(topbar, mainWrapper, { Clamp = true, Padding = 8 })
	local resizeHandle = Input.BindResize(resizeGrip, mainWrapper, effectiveMin, reqMax, function(newSize)
		self._layoutChanged:Fire(newSize)
		if self.ActiveTab and self.ActiveTab._syncSubTabIndicator then
			self.ActiveTab:_syncSubTabIndicator(true)
		end
	end)
	maid:Give(dragHandle)
	maid:Give(resizeHandle)

	-- Keep window clamped inside viewport if viewport resizes
	maid:Give(screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local newVp = getViewportSize(screenGui)
		local curSize = mainWrapper.AbsoluteSize
		local maxW = math.max(effectiveMin.X, newVp.X - 16)
		local maxH = math.max(effectiveMin.Y, newVp.Y - 16)
		local clampedW = Util.Clamp(curSize.X, math.min(effectiveMin.X, maxW), maxW)
		local clampedH = Util.Clamp(curSize.Y, math.min(effectiveMin.Y, maxH), maxH)
		if clampedW ~= curSize.X or clampedH ~= curSize.Y then
			mainWrapper.Size = UDim2.fromOffset(clampedW, clampedH)
			self._layoutChanged:Fire(Vector2.new(clampedW, clampedH))
		end
		local posX = Util.Clamp(mainWrapper.Position.X.Offset, 8, math.max(8, newVp.X - clampedW - 8))
		local posY = Util.Clamp(mainWrapper.Position.Y.Offset, 8, math.max(8, newVp.Y - clampedH - 8))
		mainWrapper.Position = UDim2.fromOffset(posX, posY)
	end))

	-- Mobile Button
	local mobileOpts = type(options.MobileButton) == "table" and options.MobileButton or {
		Enabled = options.MobileButton ~= false,
		Title = self.Title,
		Icon = self.Icon,
	}
	mobileOpts.Title = mobileOpts.Title or self.Title
	mobileOpts.Icon = mobileOpts.Icon or self.Icon
	self._mobileButton = MobileButton.new(mainLayer, self, mobileOpts)
	maid:Give(self._mobileButton)

	-- Config initialization with live UI preferences extras
	-- Core Theme/Tween/Blur/Watermark/KeybindList preferences are handled directly by Systems/Config.
	self._configExtras = {
		Save = function()
			return {
				NotificationPosition = self._notificationPosition,
				ToggleKey = Util.KeyName(self._toggleKey),
				KeybindListMode = self._keybindListMode or "ActiveOnly",
				MobileButtonEnabled = self._mobileButton and self._mobileButton:IsEnabled() or false,
				SidebarCollapsed = self._sidebarCollapsed == true,
			}
		end,
		Load = function(custom)
			if type(custom) ~= "table" then
				return
			end
			if type(custom.NotificationPosition) == "string" then
				self._notificationPosition = custom.NotificationPosition
				Notification.SetPosition(custom.NotificationPosition)
			end
			if custom.ToggleKey then
				local resolved = Util.ResolveKey(custom.ToggleKey)
				if resolved then
					self:SetToggleKey(resolved)
				end
			end
			if type(custom.KeybindListMode) == "string" then
				self._keybindListMode = custom.KeybindListMode
				KeybindList.SetMode(custom.KeybindListMode)
			end
			if type(custom.MobileButtonEnabled) == "boolean" then
				self:SetMobileButtonEnabled(custom.MobileButtonEnabled)
			end
			if type(custom.SidebarCollapsed) == "boolean" and custom.SidebarCollapsed ~= self._sidebarCollapsed then
				self:ToggleSidebar()
			end
		end,
		OnLoad = function(prefs)
			if self._configLoaded then
				self._configLoaded:Fire(prefs)
			end
		end,
	}
	pcall(Config.Init, self._configFolder, self._registry, self._configExtras)

	-- ─── Popup Dismissal & Keyboard Shortcuts ────────────────────────────────
	maid:Give(popupBackdrop.Activated:Connect(function()
		self:ClosePopup()
	end))

	maid:Give(Services.UserInputService.InputBegan:Connect(function(input, processed)
		if self._destroyed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and self._activePopup then
			self:ClosePopup()
			return
		end
		if not processed and not Input.Capturing and Services.UserInputService:GetFocusedTextBox() == nil then
			if input.KeyCode == Enum.KeyCode.K then
				local uis = Services.UserInputService
				if uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl) then
					CommandPalette.Toggle()
				end
			end
		end
	end))

	self._toggleKeybind = Input.RegisterKeybind("LuminaToggleUI_" .. windowId, self._toggleKey, function()
		self:Toggle()
	end, "Toggle")
	maid:Give(self._toggleKeybind)

	-- ─── Topbar & Sidebar Actions ────────────────────────────────────────────
	maid:Give(collapseBtn.Activated:Connect(function()
		self:ToggleSidebar(true)
	end))
	maid:Give(expandBtn.Activated:Connect(function()
		self:ToggleSidebar(false)
	end))
	maid:Give(brandBadge.Activated:Connect(function()
		if self._sidebarCollapsed then
			self:ToggleSidebar(false)
		end
	end))

	maid:Give(topSearchBtn.Activated:Connect(function(input)
		Transition.Ripple(topSearchBtn, input, "Accent")
		CommandPalette.Open()
	end))

	maid:Give(Theme.Changed:Connect(function(theme)
		if theme.Dark then
			self._lastDarkTheme = Theme.Name
			Icons.Set(themeIcon, "sun")
		else
			Icons.Set(themeIcon, "moon")
		end
	end))

	maid:Give(themeBtn.Activated:Connect(function(input)
		Transition.Ripple(themeBtn, input, "Accent")
		if Theme.Current.Dark then
			Theme.Set("Light", true)
		else
			Theme.Set(self._lastDarkTheme or "Midnight", true)
		end
	end))

	maid:Give(Notification.Changed:Connect(function()
		if not self._destroyed then
			unreadDot.Visible = Notification.UnreadCount > 0
		end
	end))

	maid:Give(bellBtn.Activated:Connect(function(input)
		Transition.Ripple(bellBtn, input, "Accent")
		if self._activePopup and self._activePopup.Id == "NotificationHistory" then
			self:ClosePopup("NotificationHistory")
		else
			self:_openNotificationHistory(bellBtn)
		end
	end))

	maid:Give(minBtn.Activated:Connect(function(input)
		Transition.Ripple(minBtn, input, "Accent")
		self:SetVisible(false)
	end))

	maid:Give(closeBtn.MouseEnter:Connect(function()
		Icons.SetColor(closeIcon, "Error")
	end))
	maid:Give(closeBtn.MouseLeave:Connect(function()
		Icons.SetColor(closeIcon, "SubText")
	end))
	maid:Give(closeBtn.Activated:Connect(function(input)
		Transition.Ripple(closeBtn, input, "Error")
		if self._destroyOnClose and not self._confirmClose then
			self:Destroy()
			return
		end
		if not self._confirmClose then
			self:SetVisible(false)
			if type(self._onClose) == "function" then
				Util.Spawn(self._onClose)
			end
			return
		end
		self:Dialog({
			Title = "Unload " .. self.Title .. "?",
			Content = "This will close the workspace interface and clean up active HUD overlays.",
			Icon = "power",
			Buttons = {
				{ Title = "Cancel", Variant = "Default" },
				{
					Title = "Hide Instead",
					Variant = "Default",
					Callback = function()
						self:SetVisible(false)
					end,
				},
				{
					Title = "Unload",
					Variant = "Danger",
					Callback = function()
						self:Destroy()
					end,
				},
			},
		})
	end))

	Transition.Mount(mainWrapper, 0.94)
	if options.AutoLoadConfig then
		pcall(Config.LoadAuto)
	end

	return self
end

-- ─── Popup Manager ───────────────────────────────────────────────────────────

function Window:_positionPopup(frame, anchorGui)
	local layerPos = self.PopupLayer.AbsolutePosition
	local layerSize = self.PopupLayer.AbsoluteSize
	if layerSize.X <= 0 or layerSize.Y <= 0 then
		layerSize = getViewportSize(self.ScreenGui)
	end

	local frameSize = frame.AbsoluteSize
	local fw = frameSize.X > 0 and frameSize.X or frame.Size.X.Offset
	local fh = frameSize.Y > 0 and frameSize.Y or frame.Size.Y.Offset

	local x, y
	if anchorGui and typeof(anchorGui) == "Instance" and anchorGui.Parent then
		local anchorPos = anchorGui.AbsolutePosition - layerPos
		local anchorSize = anchorGui.AbsoluteSize
		x = anchorPos.X
		if x + fw > layerSize.X - POPUP_PAD then
			x = anchorPos.X + anchorSize.X - fw
		end
		y = anchorPos.Y + anchorSize.Y + 6
		if y + fh > layerSize.Y - POPUP_PAD then
			local aboveY = anchorPos.Y - fh - 6
			if aboveY >= POPUP_PAD then
				y = aboveY
			end
		end
	else
		x = (layerSize.X - fw) * 0.5
		y = (layerSize.Y - fh) * 0.5
	end

	x = Util.Clamp(x, POPUP_PAD, math.max(POPUP_PAD, layerSize.X - fw - POPUP_PAD))
	y = Util.Clamp(y, POPUP_PAD, math.max(POPUP_PAD, layerSize.Y - fh - POPUP_PAD))
	frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

function Window:OpenPopup(id, frame, anchorGui, onClose)
	if self._destroyed then
		return nil
	end
	self:ClosePopup()

	if typeof(frame) ~= "Instance" then
		return nil
	end

	local popupBackdrop = self.PopupLayer:FindFirstChild("PopupBackdrop")
	if popupBackdrop then
		popupBackdrop.Visible = true
	end

	frame.Parent = self.PopupLayer
	frame.ZIndex = math.max(frame.ZIndex, 10)
	frame.Visible = true

	self:_positionPopup(frame, anchorGui)
	local sizeConn = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self._activePopup and self._activePopup.Frame == frame then
			self:_positionPopup(frame, anchorGui)
		end
	end)

	self._activePopup = {
		Id = id,
		Frame = frame,
		Anchor = anchorGui,
		OnClose = onClose,
		SizeConn = sizeConn,
	}

	task.defer(function()
		if self._activePopup and self._activePopup.Frame == frame then
			self:_positionPopup(frame, anchorGui)
		end
	end)

	return self._activePopup
end

function Window:ClosePopup(id)
	local current = self._activePopup
	if not current then
		return
	end
	if id ~= nil and current.Id ~= id then
		return
	end

	self._activePopup = nil
	if current.SizeConn then
		pcall(function()
			current.SizeConn:Disconnect()
		end)
	end

	local popupBackdrop = self.PopupLayer:FindFirstChild("PopupBackdrop")
	if popupBackdrop then
		popupBackdrop.Visible = false
	end

	if type(current.OnClose) == "function" then
		Util.SafeCall(current.OnClose)
	elseif current.Frame and current.Frame.Parent then
		current.Frame.Visible = false
	end
end

-- ─── Notification History Popover ────────────────────────────────────────────

function Window:_openNotificationHistory(anchorBtn)
	local popMaid = Maid.new()

	local pop = Create.New("Frame", {
		Name = "NotificationPopover",
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Corner = 12,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency, 0.05)
			end,
		},
		Padding = 12,
		ZIndex = 20,
	})
	Create.GlassStroke(pop, 0.05)
	Create.List(pop, { Gap = 8 })
	popMaid:Give(pop)

	local header = Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = pop,
	})
	Create.Text({
		Text = "Notifications",
		Font = "SemiBold",
		TextSize = 13,
		Color = "Text",
		Size = UDim2.new(1, -66, 1, 0),
		Parent = header,
	})
	local clearBtn = Create.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(58, 22),
		Text = "Clear All",
		Font = "Medium",
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Corner = 6,
		Theme = {
			BackgroundColor3 = "Tile",
			BackgroundTransparency = "TileTransparency",
			TextColor3 = "SubText",
		},
		Parent = header,
	})
	popMaid:Give(Transition.Hover(clearBtn, clearBtn, "Tile", "TileHover"))

	Create.New("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "Divider", BackgroundTransparency = "DividerTransparency" },
		LayoutOrder = 2,
		Parent = pop,
	})

	local listScroll = Create.New("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 2,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Theme = { ScrollBarImageColor3 = "Muted" },
		LayoutOrder = 3,
		Parent = pop,
	})
	local maxConstraint = Instance.new("UISizeConstraint")
	maxConstraint.MaxSize = Vector2.new(300, 260)
	maxConstraint.Parent = listScroll
	Create.List(listScroll, { Gap = 6 })

	local TYPE_COLORS = {
		Info = "Info",
		Success = "Success",
		Warning = "Warning",
		Error = "Error",
		Accent = "Accent",
	}

	local function rebuildList()
		for _, child in ipairs(listScroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local history = Notification.History
		if #history == 0 then
			Create.Text({
				Text = "All caught up. No notifications yet.",
				Font = "Regular",
				TextSize = 12,
				Color = "Muted",
				Size = UDim2.new(1, 0, 0, 48),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = listScroll,
			})
			return
		end

		for index, entry in ipairs(history) do
			local item = Create.New("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Corner = 8,
				Theme = { BackgroundColor3 = "Tile", BackgroundTransparency = "TileTransparency" },
				Padding = { 8, 10, 8, 10 },
				LayoutOrder = index,
				Parent = listScroll,
			})
			Create.List(item, { Gap = 3 })

			local topLine = Create.New("Frame", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
				Parent = item,
			})
			local dot = Create.New("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(6, 6),
				Corner = 999,
				Theme = { BackgroundColor3 = TYPE_COLORS[entry.Type] or "Info" },
				Parent = topLine,
			})
			local _ = dot
			Create.Text({
				Text = tostring(entry.Title or "Notification"),
				Font = "SemiBold",
				TextSize = 12,
				Color = "Text",
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -54, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = topLine,
			})
			Create.Text({
				Text = tostring(entry.TimeText or ""),
				Font = "Regular",
				TextSize = 10,
				Color = "Muted",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 40, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = topLine,
			})

			if entry.Content and entry.Content ~= "" then
				Create.Text({
					Text = tostring(entry.Content),
					Font = "Regular",
					TextSize = 11,
					Color = "SubText",
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextWrapped = true,
					LayoutOrder = 2,
					Parent = item,
				})
			end
		end
	end

	rebuildList()
	Notification.MarkAllRead()

	popMaid:Give(clearBtn.Activated:Connect(function()
		Notification.ClearHistory()
		rebuildList()
	end))

	self:OpenPopup("NotificationHistory", pop, anchorBtn, function()
		Transition.Unmount(pop, 0.95, function()
			popMaid:Clean()
		end)
	end)
	Transition.Mount(pop, 0.95)
end

-- ─── Categories & Tabs ───────────────────────────────────────────────────────

function Window:AddCategory(name)
	name = tostring(name or "General")
	self._currentCategory = name
	if self._categories[name] then
		return self._categories[name]
	end

	self._categoryCount += 1
	local slotBase = self._categoryCount * 1000
	local header = Tab.CategoryHeader(self._tabScroll, name, slotBase)
	header:SetCompact(self._sidebarCollapsed, true)

	local record = {
		Name = name,
		SlotBase = slotBase,
		Count = 0,
		Header = header,
	}
	self._categories[name] = record
	return record
end

function Window:AddTab(options)
	options = Util.Options(options, { Title = "Tab", Category = nil }, "Title")
	local categoryName = options.Category or self._currentCategory

	local layoutOrder
	if categoryName and categoryName ~= "" then
		local cat = self:AddCategory(categoryName)
		cat.Count += 1
		layoutOrder = cat.SlotBase + cat.Count
		options.Category = categoryName
	else
		self._uncategorizedOrder += 1
		layoutOrder = self._uncategorizedOrder
	end
	options.LayoutOrder = layoutOrder

	local tab = Tab.new(self, options)
	table.insert(self.Tabs, tab)
	self.Maid:Give(tab)

	if #self.Tabs == 1 then
		self:SelectTab(tab, true)
	end
	return tab
end

function Window:SelectTab(tab, instant)
	if type(tab) == "string" then
		for _, candidate in ipairs(self.Tabs) do
			if candidate.Title == tab then
				tab = candidate
				break
			end
		end
	elseif type(tab) == "number" then
		tab = self.Tabs[tab]
	end
	if type(tab) ~= "table" or not tab.Page then
		return nil
	end

	if self.ActiveTab == tab and not instant then
		return tab
	end

	self:ClosePopup()
	for _, candidate in ipairs(self.Tabs) do
		candidate:_setActiveVisual(candidate == tab, instant == true)
	end
	self.ActiveTab = tab
	self:_updateBreadcrumb()
	return tab
end

function Window:_updateBreadcrumb()
	local parts = {}
	local tab = self.ActiveTab
	if tab then
		if tab.Category and tab.Category ~= "" then
			table.insert(parts, tab.Category)
		end
		table.insert(parts, tab.Title)
		if tab.ActiveSubTab and tab.ActiveSubTab.Title then
			table.insert(parts, tab.ActiveSubTab.Title)
		end
	else
		table.insert(parts, self.Title)
	end

	if #parts <= 1 then
		self._breadcrumbLabel.Text = parts[1] or self.Title
		return
	end

	local formatted = {}
	for index, part in ipairs(parts) do
		local safe = tostring(part):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		if index == #parts then
			table.insert(formatted, "<b>" .. safe .. "</b>")
		else
			table.insert(formatted, safe)
		end
	end
	self._breadcrumbLabel.Text = table.concat(formatted, "  /  ")
end

-- ─── Window Controls & APIs ──────────────────────────────────────────────────

function Window:GetWidth()
	if self.MainWrapper and self.MainWrapper.AbsoluteSize.X > 0 then
		return self.MainWrapper.AbsoluteSize.X
	end
	return self.MainWrapper and self.MainWrapper.Size.X.Offset or 820
end

function Window:ToggleSidebar(collapsed)
	if collapsed == nil then
		collapsed = not self._sidebarCollapsed
	else
		collapsed = collapsed == true
	end
	if self._sidebarCollapsed == collapsed then
		return
	end
	self._sidebarCollapsed = collapsed

	local targetW = collapsed and SIDEBAR_COLLAPSED or self._sidebarExpandedWidth

	self._brandText.Visible = not collapsed
	self._collapseBtn.Visible = not collapsed
	self._expandBtn.Visible = collapsed
	self._searchPlaceholder.Visible = not collapsed
	self._shortcutChip.Visible = not collapsed
	if self._welcomeCard then
		self._welcomeCard.Visible = not collapsed
	end
	self._breadcrumbLabel.Size = UDim2.new(1, collapsed and -60 or -26, 0, 20)

	for _, cat in pairs(self._categories) do
		if cat.Header then
			cat.Header:SetCompact(collapsed, false)
		end
	end
	for _, tab in ipairs(self.Tabs) do
		tab:SetCompact(collapsed, false)
	end

	Tween.Play(self.Sidebar, { Size = UDim2.new(0, targetW, 1, 0) }, Tween.Normal)
	Tween.Play(self.BodyArea, {
		Position = UDim2.new(0, targetW, 0, 0),
		Size = UDim2.new(1, -targetW, 1, 0),
	}, Tween.Normal)
end

function Window:SetVisible(visible)
	visible = visible == true
	if self._destroyed or self._visible == visible then
		return
	end
	self._visible = visible

	Blur.SetOpen(visible)
	if not visible then
		self:ClosePopup()
		CommandPalette.Close()
		Transition.Unmount(self.MainWrapper, 0.95, function()
			if not self._visible and self.MainWrapper and self.MainWrapper.Parent then
				self.MainWrapper.Visible = false
			end
		end)
	else
		self.MainWrapper.Visible = true
		Transition.Mount(self.MainWrapper, 0.95)
	end

	if self._mobileButton then
		self._mobileButton:UpdateVisibility()
	end
end

function Window:IsVisible()
	return self._visible
end

function Window:Toggle()
	self:SetVisible(not self._visible)
end

function Window:SetToggleKey(key)
	local resolved = Util.ResolveKey(key)
	self._toggleKey = resolved
	if self._toggleKeybind then
		self._toggleKeybind.SetKey(resolved)
	end
end

function Window:GetToggleKey()
	return self._toggleKey
end

function Window:SetTitle(title)
	self.Title = tostring(title or "Lumina")
	self._brandTitleLabel.Text = self.Title
end

function Window:SetSubtitle(subtitle)
	self.Subtitle = tostring(subtitle or "")
	self._brandSubLabel.Text = self.Subtitle
	self._brandSubLabel.Visible = self.Subtitle ~= ""
end

function Window:SetMobileButtonEnabled(enabled)
	if self._mobileButton then
		self._mobileButton:SetEnabled(enabled == true)
	end
end

function Window:Dialog(options)
	return Dialog.Show(self.DialogLayer, options)
end

function Window:Notify(options)
	return Notification.Notify(options)
end

function Window:BuildSettingsTab(options)
	local SettingsTab = require("Builders/SettingsTab")
	return SettingsTab.Build(self, options)
end

function Window:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	if type(self._onDestroy) == "function" then
		Util.SafeCall(self._onDestroy)
	end

	CommandPalette.Destroy()
	KeybindList.Destroy()
	Watermark.Destroy()
	Notification.Destroy()
	Tooltip.Destroy()
	Blur.Destroy()
	Input.Destroy()

	self.Maid:Clean()
	table.clear(self.Tabs)
	table.clear(self._elements)
	table.clear(self._registry)

	if self._ownsScreenGui and self.ScreenGui and self.ScreenGui.Parent then
		self.ScreenGui:Destroy()
	end
end

return Window
