---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local Config = {
	HubName        = "Bali",
	Subtitle       = "Key System",
	Version        = "v1.0.0",
	KeyLink        = "https://bali-ui.dev/getkey",
	DiscordName    = "Bali Community",
	DiscordInvite  = "e9CScDQSv",
	DiscordGuildId = "", -- Optional fallback Server ID for Discord widget JSON if invite expires
	DiscordIcon    = "", -- Server icon ("rbxassetid://..." or leave blank to auto-fetch from Discord)
	Keys           = { "BALI-2026-PRO", "BALI-FREE-KEY", "test" },
	ValidateKey    = nil, -- function(key) return true/false, "message" end  (custom API check)
	SupportedGames = {    -- PlaceId or GameId (universe) = name
		[2753915549] = "Blox Fruits",
		[4924922222] = "Brookhaven RP",
		[606849621]  = "Jailbreak",
	},
	RememberByDefault = true,
	FileName       = "BaliKey.txt",
	PrefsFile      = "BaliKeyPrefs.json",
	ToggleKey      = Enum.KeyCode.LeftControl,
	DefaultTheme   = "Dark",
	DefaultAccent  = 3,
	MaxAttempts    = 3,
	Cooldown       = 8,
	Changelog = {
		{ Version = "v1.0.0", Date = "Today", Changes = { "Bali v1.0.0 release" } },
	},
	OnSuccess = function(key)
		print("[Bali] Key verified:", key)
		-- loadstring(game:HttpGet("https://your.script/url.lua"))()
	end,
}

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local UIS                = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local HttpService        = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService         = game:GetService("GuiService")
local CoreGui            = game:GetService("CoreGui")
local LocalPlayer        = Players.LocalPlayer

local W, H = 640, 380
local UI = {}
local Conns = {}
local Alive = true

---------------------------------------------------------------------
-- THEME
---------------------------------------------------------------------
local Modes = {
	Dark = {
		Bg = Color3.fromRGB(14, 15, 17),   Bg2 = Color3.fromRGB(9, 10, 11),
		Panel = Color3.fromRGB(19, 20, 23), Card = Color3.fromRGB(23, 24, 28),
		CardHover = Color3.fromRGB(31, 33, 38), Input = Color3.fromRGB(18, 19, 22),
		Stroke = Color3.fromRGB(40, 42, 48), Divider = Color3.fromRGB(38, 40, 46),
		Text = Color3.fromRGB(241, 242, 245), SubText = Color3.fromRGB(150, 154, 165),
		Muted = Color3.fromRGB(96, 100, 112), Overlay = Color3.fromRGB(0, 0, 0),
	},
	Light = {
		Bg = Color3.fromRGB(247, 248, 251), Bg2 = Color3.fromRGB(233, 236, 242),
		Panel = Color3.fromRGB(255, 255, 255), Card = Color3.fromRGB(255, 255, 255),
		CardHover = Color3.fromRGB(240, 242, 247), Input = Color3.fromRGB(252, 252, 254),
		Stroke = Color3.fromRGB(222, 225, 232), Divider = Color3.fromRGB(226, 229, 236),
		Text = Color3.fromRGB(20, 22, 28), SubText = Color3.fromRGB(100, 106, 120),
		Muted = Color3.fromRGB(152, 157, 168), Overlay = Color3.fromRGB(20, 22, 28),
	},
}
local Accents = {
	{ Name = "Emerald", A = Color3.fromRGB(34, 197, 94),  D = Color3.fromRGB(21, 128, 61) },
	{ Name = "Azure",   A = Color3.fromRGB(59, 130, 246), D = Color3.fromRGB(29, 78, 216) },
	{ Name = "Violet",  A = Color3.fromRGB(139, 92, 246), D = Color3.fromRGB(109, 40, 217) },
	{ Name = "Rose",    A = Color3.fromRGB(244, 63, 94),  D = Color3.fromRGB(190, 18, 60) },
	{ Name = "Amber",   A = Color3.fromRGB(245, 158, 11), D = Color3.fromRGB(180, 83, 9) },
	{ Name = "Cyan",    A = Color3.fromRGB(6, 182, 212),  D = Color3.fromRGB(14, 116, 144) },
}

local State = { Mode = Config.DefaultTheme, Accent = Config.DefaultAccent }

local canFile = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
if canFile then
	pcall(function()
		if isfile(Config.PrefsFile) then
			local d = HttpService:JSONDecode(readfile(Config.PrefsFile))
			if Modes[d.Mode] then State.Mode = d.Mode end
			if Accents[d.Accent] then State.Accent = d.Accent end
		end
	end)
end
local function savePrefs()
	if canFile then pcall(function() writefile(Config.PrefsFile, HttpService:JSONEncode(State)) end) end
end

local function buildPalette()
	local m, a = Modes[State.Mode], Accents[State.Accent]
	local p = {}
	for k, v in pairs(m) do p[k] = v end
	p.Accent = a.A
	p.AccentDark = a.D
	p.AccentSoft = m.Card:Lerp(a.A, State.Mode == "Dark" and 0.16 or 0.12)
	p.AccentStroke = m.Stroke:Lerp(a.A, 0.55)
	p.White = Color3.new(1, 1, 1)
	p.Success = Color3.fromRGB(34, 197, 94)
	p.Error = Color3.fromRGB(239, 68, 68)
	p.Warning = Color3.fromRGB(245, 158, 11)
	p.Discord = Color3.fromRGB(88, 101, 242)
	return p
end
local P = buildPalette()
local Hooks = {}

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local R, M, S, B = Enum.FontWeight.Regular, Enum.FontWeight.Medium, Enum.FontWeight.SemiBold, Enum.FontWeight.Bold
local FONT = "rbxasset://fonts/families/GothamSSm.json"
local function F(w)
	local ok, f = pcall(function() return Font.new(FONT, w or R) end)
	if ok and f then return f end
	return Font.fromEnum(Enum.Font.Gotham)
end

local function create(class, props)
	local o = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function tween(o, props, t, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t or 0.25, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function conn(sig, fn)
	local c = sig:Connect(fn)
	table.insert(Conns, c)
	return c
end

local function onTheme(fn)
	table.insert(Hooks, fn)
	fn(P, true)
end

local function bind(obj, map)
	onTheme(function(p, instant)
		local goal = {}
		for prop, key in pairs(map) do goal[prop] = p[key] end
		if instant then
			for k, v in pairs(goal) do obj[k] = v end
		else
			tween(obj, goal, 0.4)
		end
	end)
end

local function applyTheme()
	P = buildPalette()
	for _, fn in ipairs(Hooks) do pcall(fn, P, false) end
	savePrefs()
end

local function corner(obj, r)
	return create("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = obj })
end

local function stroke(obj, key, th, tr)
	local s = create("UIStroke", { Thickness = th or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = obj })
	if key then bind(s, { Color = key }) end
	return s
end

local function pad(obj, l, r, t, b)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or l or 0),
		PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or t or 0), Parent = obj,
	})
end

local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function label(parent, text, size, weight, colorKey, extra)
	local l = create("TextLabel", {
		BackgroundTransparency = 1, Text = text or "", TextSize = size or 13, FontFace = F(weight),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.fromOffset(120, (size or 13) + 4), Parent = parent,
	})
	if extra then for k, v in pairs(extra) do l[k] = v end end
	if colorKey then bind(l, { TextColor3 = colorKey }) end
	return l
end

local function button(parent, props)
	props.Text = props.Text or ""
	props.AutoButtonColor = false
	props.BorderSizePixel = 0
	props.Parent = parent
	return create("TextButton", props)
end

local function comma(n)
	local s = tostring(math.floor(n + 0.5))
	local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if r:sub(1, 1) == "," then r = r:sub(2) end
	return r
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function ripple(btn, color)
	btn.MouseButton1Down:Connect(function()
		local m = UIS:GetMouseLocation() - GuiService:GetGuiInset()
		local abs, sz = btn.AbsolutePosition, btn.AbsoluteSize
		local scale = sz.X / math.max(btn.Size.X.Offset, 1)
		local x, y = (m.X - abs.X) / scale, (m.Y - abs.Y) / scale
		local r = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = color or Color3.new(1, 1, 1), BackgroundTransparency = 0.8, BorderSizePixel = 0, Parent = btn,
		})
		corner(r, 999)
		local d = math.max(btn.Size.X.Offset, btn.Size.Y.Offset) * 2.4
		tween(r, { Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1 }, 0.7)
		task.delay(0.7, function() r:Destroy() end)
	end)
end

local function pressable(btn, amount)
	local sc = create("UIScale", { Parent = btn })
	btn.MouseButton1Down:Connect(function() tween(sc, { Scale = amount or 0.965 }, 0.12) end)
	btn.MouseButton1Up:Connect(function() tween(sc, { Scale = 1 }, 0.3, Enum.EasingStyle.Back) end)
	btn.MouseLeave:Connect(function() tween(sc, { Scale = 1 }, 0.3, Enum.EasingStyle.Back) end)
	return sc
end

local function hoverBg(btn, normal, hover)
	btn.MouseEnter:Connect(function() tween(btn, { BackgroundColor3 = P[hover] }, 0.18) end)
	btn.MouseLeave:Connect(function() tween(btn, { BackgroundColor3 = P[normal] }, 0.25) end)
end

local function hGradient(obj, horizontal)
	return create("UIGradient", {
		Rotation = horizontal and 0 or 90,
		Transparency = NumberSequence.new({ kp(0, 1), kp(0.2, 0), kp(0.8, 0), kp(1, 1) }), Parent = obj,
	})
end

---------------------------------------------------------------------
-- ICONS (drawn with frames, no external assets needed)
---------------------------------------------------------------------
local function bar(parent, w, h, x, y, rot)
	local f = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		Rotation = rot or 0, BorderSizePixel = 0, Parent = parent,
	})
	corner(f, 99)
	return f
end
local function box(parent, size, pos)
	return create("Frame", { Size = UDim2.fromOffset(size, size), Position = pos or UDim2.new(), BackgroundTransparency = 1, Parent = parent })
end
local function BG(f) return { f, "BackgroundColor3" } end

local Icons = {}
function Icons.Arrow(parent, pos)
	local c = box(parent, 16, pos)
	return c, {
		BG(bar(c, 12.5, 2, 7.8, 8)),
		BG(bar(c, 7.4, 2, 11.2, 5.4, 45)),
		BG(bar(c, 7.4, 2, 11.2, 10.6, -45)),
		BG(bar(c, 2.6, 2.6, 13.8, 8)),
	}
end
function Icons.Check(parent, pos)
	local c = box(parent, 16, pos)
	return c, {
		BG(bar(c, 6.4, 2, 4.5, 9.8, 45)),
		BG(bar(c, 11.2, 2, 10.1, 8.2, -46)),
		BG(bar(c, 2.6, 2.6, 6.5, 11.8)),
	}
end
function Icons.X(parent, pos)
	local c = box(parent, 16, pos)
	return c, { BG(bar(c, 12, 2, 8, 8, 45)), BG(bar(c, 12, 2, 8, 8, -45)) }
end
function Icons.Minus(parent, pos)
	local c = box(parent, 16, pos)
	return c, { BG(bar(c, 10, 2, 8, 8)) }
end
function Icons.Chevron(parent, pos)
	local c = box(parent, 16, pos)
	return c, {
		BG(bar(c, 7, 2, 7.9, 5.5, 45)),
		BG(bar(c, 7, 2, 7.9, 10.5, -45)),
		BG(bar(c, 2.6, 2.6, 10.4, 8)),
	}
end
function Icons.Key(parent, pos)
	local c = create("Frame", { Size = UDim2.fromOffset(20, 20), Position = pos or UDim2.new(), Rotation = -45, BackgroundTransparency = 1, Parent = parent })
	local ring = create("Frame", { Size = UDim2.fromOffset(7, 7), Position = UDim2.fromOffset(2, 6.5), BackgroundTransparency = 1, Parent = c })
	corner(ring, 99)
	local rs = create("UIStroke", { Thickness = 2, Parent = ring })
	local shaft = create("Frame", { Size = UDim2.fromOffset(10, 2), Position = UDim2.fromOffset(9.5, 9), BorderSizePixel = 0, Parent = c })
	local t1 = create("Frame", { Size = UDim2.fromOffset(2, 4), Position = UDim2.fromOffset(14.5, 10.5), BorderSizePixel = 0, Parent = c })
	local t2 = create("Frame", { Size = UDim2.fromOffset(2, 3), Position = UDim2.fromOffset(17.5, 10.5), BorderSizePixel = 0, Parent = c })
	return c, { { rs, "Color" }, BG(shaft), BG(t1), BG(t2) }
end
function Icons.Info(parent, pos)
	local c = box(parent, 16, pos)
	local ring = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(13, 13), BackgroundTransparency = 1, Parent = c })
	corner(ring, 99)
	local rs = create("UIStroke", { Thickness = 1.6, Parent = ring })
	return c, { { rs, "Color" }, BG(bar(c, 2, 2, 8, 4.8)), BG(bar(c, 2, 5, 8, 9.6)) }
end
function Icons.Eye(parent, pos)
	local c = create("Frame", { Size = UDim2.fromOffset(20, 16), Position = pos or UDim2.new(), BackgroundTransparency = 1, Parent = parent })
	local o = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(16, 10), BackgroundTransparency = 1, Parent = c })
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = o })
	local os_ = create("UIStroke", { Thickness = 1.5, Parent = o })
	local pupil = bar(c, 4, 4, 10, 8)
	local slash = bar(c, 20, 1.6, 10, 8, -38)
	return c, { { os_, "Color" }, BG(pupil), BG(slash) }, slash
end

local function paint(parts, color, t)
	for _, pt in ipairs(parts) do
		if t then tween(pt[1], { [pt[2]] = color }, t) else pt[1][pt[2]] = color end
	end
end
local function themedIcon(parts, key)
	local ref = { Key = key }
	onTheme(function(p, instant) paint(parts, p[ref.Key], (not instant) and 0.35 or nil) end)
	function ref.Set(k, t) ref.Key = k; paint(parts, P[k], t or 0.2) end
	return ref
end

---------------------------------------------------------------------
-- NETWORK / EXECUTOR
---------------------------------------------------------------------
local function extractInviteCode(raw)
	local s = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub("%?.*$", ""):gsub("/+$", "")
	return s:match("([^/]+)$") or s
end

local function httpGet(url, acceptJson)
	local headers = { ["User-Agent"] = "Mozilla/5.0" }
	if acceptJson ~= false then
		headers["Accept"] = "application/json"
	end
	local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
	if req then
		local ok, res = pcall(req, { Url = url, Method = "GET", Headers = headers })
		if ok and type(res) == "table" then
			local code = tonumber(res.StatusCode or res.status_code)
			if code and code >= 400 and code < 500 then
				return nil, code
			end
			if type(res.Body) == "string" and #res.Body > 0 then
				if (res.Success == nil or res.Success == true) and (not code or (code >= 200 and code < 300)) then
					return res.Body, code or 200
				end
			end
		end
	end
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok and type(body) == "string" and #body > 0 then
		return body, 200
	end
	return nil, 0
end

local ExecutorName = "Roblox Studio"
pcall(function()
	if identifyexecutor then ExecutorName = tostring((identifyexecutor())) end
end)

local function copy(text)
	local fn = setclipboard or toclipboard or (Clipboard and Clipboard.set)
	if fn then return pcall(fn, text) end
	return false
end

---------------------------------------------------------------------
-- ROOT GUI
---------------------------------------------------------------------
local GUI_NAME = "Bali_KeySystem"
for _, parent in ipairs({ CoreGui, LocalPlayer:FindFirstChildOfClass("PlayerGui") }) do
	pcall(function() local old = parent:FindFirstChild(GUI_NAME); if old then old:Destroy() end end)
end
pcall(function() if gethui then local old = gethui():FindFirstChild(GUI_NAME); if old then old:Destroy() end end end)

local Gui = create("ScreenGui", {
	Name = GUI_NAME, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ResetOnSpawn = false,
	IgnoreGuiInset = false, DisplayOrder = 999,
})
pcall(function() if syn and syn.protect_gui then syn.protect_gui(Gui) end end)
pcall(function() if gethui then Gui.Parent = gethui() end end)
if not Gui.Parent then pcall(function() Gui.Parent = CoreGui end) end
if not Gui.Parent then Gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

---------------------------------------------------------------------
-- TOOLTIP
---------------------------------------------------------------------
do
	local Tip = create("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), AnchorPoint = Vector2.new(0.5, 0),
		Visible = false, ZIndex = 100, FontFace = F(M), TextSize = 12, Text = "", BorderSizePixel = 0, Parent = Gui,
	})
	bind(Tip, { BackgroundColor3 = "Panel", TextColor3 = "Text" })
	corner(Tip, 7); pad(Tip, 9, 9, 0, 0)
	local ts = stroke(Tip, "Stroke")
	UI.Tooltip = function(btn, text)
		btn.MouseEnter:Connect(function()
			Tip.Text = type(text) == "function" and text() or text
			Tip.Position = UDim2.fromOffset(btn.AbsolutePosition.X + btn.AbsoluteSize.X / 2, btn.AbsolutePosition.Y + btn.AbsoluteSize.Y + 8)
			Tip.Visible = true
			Tip.TextTransparency, Tip.BackgroundTransparency, ts.Transparency = 1, 1, 1
			tween(Tip, { TextTransparency = 0, BackgroundTransparency = 0 }, 0.18)
			tween(ts, { Transparency = 0 }, 0.18)
		end)
		btn.MouseLeave:Connect(function() Tip.Visible = false end)
		btn.MouseButton1Click:Connect(function()
			if Tip.Visible then Tip.Text = type(text) == "function" and text() or text end
		end)
	end
end

---------------------------------------------------------------------
-- TOAST NOTIFICATIONS
---------------------------------------------------------------------
do
	local Holder = create("Frame", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, 310, 1, -32),
		BackgroundTransparency = 1, ZIndex = 50, Parent = Gui,
	})
	create("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = Holder })
	local order = 0

	UI.Notify = function(title, text, kind, dur)
		kind, dur = kind or "info", dur or 4
		order += 1
		local color = ({ success = P.Success, error = P.Error, warning = P.Warning, info = P.Accent })[kind] or P.Accent
		local outer = create("Frame", { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, LayoutOrder = order, Parent = Holder })
		local card = button(outer, {
			Size = UDim2.new(1, 0, 0, 74), Position = UDim2.new(1, 40, 0, 0), BackgroundColor3 = P.Panel, ClipsDescendants = true,
		})
		corner(card, 12)
		create("UIStroke", { Color = P.Stroke:Lerp(color, 0.28), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })

		-- Subtle ambient color glow behind the icon badge
		local cardGlow = create("Frame", { Position = UDim2.fromOffset(-20, -20), Size = UDim2.fromOffset(100, 100), BackgroundColor3 = color, BorderSizePixel = 0, Parent = card })
		corner(cardGlow, 999)
		create("UIGradient", { Transparency = NumberSequence.new({ kp(0, 0.88), kp(0.6, 0.96), kp(1, 1) }), Parent = cardGlow })

		local ib = create("Frame", { Position = UDim2.fromOffset(13, 15), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = P.Card:Lerp(color, 0.22), BorderSizePixel = 0, Parent = card })
		corner(ib, 10)
		create("UIStroke", { Color = color, Transparency = 0.65, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = ib })
		local builder = ({ success = Icons.Check, error = Icons.X, warning = Icons.Info, info = Icons.Info })[kind] or Icons.Info
		local _, parts = builder(ib, UDim2.fromOffset(10, 10))
		paint(parts, color)

		create("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(60, 13), Size = UDim2.new(1, -72, 0, 18), Text = title,
			FontFace = F(B), TextSize = 13.5, TextColor3 = P.Text, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = card,
		})
		create("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(60, 32), Size = UDim2.new(1, -72, 0, 26), Text = text or "",
			FontFace = F(R), TextSize = 12, TextColor3 = P.SubText, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card,
		})

		-- Bottom recessed progress bar track with clearance below text
		local progTrack = create("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -7), Size = UDim2.new(1, -28, 0, 2),
			BackgroundColor3 = P.Text, BackgroundTransparency = 0.92, BorderSizePixel = 0, ClipsDescendants = true, Parent = card,
		})
		corner(progTrack, 99)
		local prog = create("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0, Parent = progTrack,
		})
		corner(prog, 99)

		tween(outer, { Size = UDim2.new(1, 0, 0, 74) }, 0.25, Enum.EasingStyle.Quint)
		tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(prog, { Size = UDim2.fromScale(0, 1) }, dur, Enum.EasingStyle.Linear)

		card.MouseEnter:Connect(function() tween(card, { BackgroundColor3 = P.CardHover }, 0.15) end)
		card.MouseLeave:Connect(function() tween(card, { BackgroundColor3 = P.Panel }, 0.2) end)

		local gone = false
		local function dismiss()
			if gone then return end
			gone = true
			tween(card, { Position = UDim2.new(1, 40, 0, 0) }, 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.16, function()
				tween(outer, { Size = UDim2.new(1, 0, 0, 0) }, 0.16)
				task.delay(0.18, function() outer:Destroy() end)
			end)
		end
		card.MouseButton1Click:Connect(dismiss)
		task.delay(dur, dismiss)
	end
end
local Notify = UI.Notify

---------------------------------------------------------------------
-- WINDOW
---------------------------------------------------------------------
UI.Holder = create("Frame", {
	Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, Parent = Gui,
})
UI.Scale = create("UIScale", { Parent = UI.Holder })
UI.Main = create("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BorderSizePixel = 0,
	ClipsDescendants = true, ZIndex = 2, Parent = UI.Holder,
})
bind(UI.Main, { BackgroundColor3 = "Bg" })
corner(UI.Main, 16)
UI.Border = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = UI.Holder })
corner(UI.Border, 16)
UI.BorderStroke = stroke(UI.Border, "Stroke", 1, 1)

local Main = UI.Main
local Intro = {}

-- Background layers
do
	local fill = create("Frame", { Name = "BgFill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 1, Parent = Main })
	corner(fill, 16)
	local g = create("UIGradient", { Rotation = 90, Parent = fill })
	onTheme(function(p) g.Color = ColorSequence.new(p.Bg, p.Bg2) end)
	UI.BgFill = fill

	local orb = create("Frame", { Position = UDim2.fromOffset(440, -190), Size = UDim2.fromOffset(340, 340), BorderSizePixel = 0, ZIndex = 2, Parent = Main })
	corner(orb, 999)
	bind(orb, { BackgroundColor3 = "Accent" })
	UI.OrbGrad = create("UIGradient", { Transparency = NumberSequence.new({ kp(0, 1), kp(0.5, 0.9), kp(1, 1) }), Parent = orb })

	local glow = create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 160), BorderSizePixel = 0, ZIndex = 2, Parent = Main })
	bind(glow, { BackgroundColor3 = "Accent" })
	UI.GlowGrad = create("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({ kp(0, 0.8), kp(0.45, 0.94), kp(1, 1) }), Parent = glow })

	UI.FX = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 3, Parent = Main })
	UI.DragZone = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4, Parent = Main })
end

---------------------------------------------------------------------
-- LEFT SIDE
---------------------------------------------------------------------
do
	-- Logo
	local logo = create("Frame", { Position = UDim2.fromOffset(28, 28), Size = UDim2.fromOffset(46, 46), BorderSizePixel = 0, Parent = Main })
	bind(logo, { BackgroundColor3 = "AccentSoft" })
	corner(logo, 13)
	local ls = stroke(logo, "Accent", 1.5)
	UI.LogoGrad = create("UIGradient", { Transparency = NumberSequence.new({ kp(0, 0), kp(0.5, 0.9), kp(1, 0) }), Parent = ls })
	local dia = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 18), Rotation = 45, BackgroundTransparency = 1, Parent = logo })
	corner(dia, 5)
	stroke(dia, "Accent", 2.2)
	local core = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(7, 7), Rotation = 45, BorderSizePixel = 0, Parent = logo })
	corner(core, 2)
	bind(core, { BackgroundColor3 = "Accent" })
	UI.LogoDiamond, UI.LogoCore = dia, core
	table.insert(Intro, logo)

	-- Title row
	local row = create("Frame", { Position = UDim2.fromOffset(86, 27), Size = UDim2.fromOffset(260, 26), BackgroundTransparency = 1, Parent = Main })
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	label(row, Config.HubName, 22, B, "Text", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextTruncate = Enum.TextTruncate.None, LayoutOrder = 1 })
	local pill = create("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), BorderSizePixel = 0, LayoutOrder = 2, Parent = row })
	bind(pill, { BackgroundColor3 = "AccentSoft" })
	corner(pill, 99); pad(pill, 9, 9, 0, 0)
	label(pill, Config.Version, 10, B, "Accent", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextTruncate = Enum.TextTruncate.None })
	table.insert(Intro, row)

	local sub = label(Main, Config.Subtitle, 13, M, "SubText", { Position = UDim2.fromOffset(86, 54), Size = UDim2.fromOffset(250, 16) })
	table.insert(Intro, sub)

	-- License label + status
	local lic = label(Main, "License key", 12, M, "SubText", { Position = UDim2.fromOffset(30, 102), Size = UDim2.fromOffset(120, 16) })
	table.insert(Intro, lic)
	UI.Status = label(Main, "", 12, M, nil, { Position = UDim2.fromOffset(150, 102), Size = UDim2.fromOffset(202, 16), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = P.SubText })
	table.insert(Intro, UI.Status)

	-- Input
	local input = create("Frame", { Position = UDim2.fromOffset(28, 124), Size = UDim2.fromOffset(324, 50), BorderSizePixel = 0, Parent = Main })
	bind(input, { BackgroundColor3 = "Input" })
	corner(input, 12)
	UI.InputStroke = create("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = input })
	UI.InputStrokeKey = "Stroke"
	onTheme(function(p, instant)
		if instant then UI.InputStroke.Color = p[UI.InputStrokeKey] else tween(UI.InputStroke, { Color = p[UI.InputStrokeKey] }, 0.35) end
	end)
	local _, kparts = Icons.Key(input, UDim2.fromOffset(13, 15))
	UI.InputIcon = themedIcon(kparts, "Muted")

	UI.KeyBox = create("TextBox", {
		Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -92, 1, 0), BackgroundTransparency = 1, Text = "",
		PlaceholderText = "Paste your key here", ClearTextOnFocus = false, FontFace = F(M), TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true, Parent = input,
	})
	bind(UI.KeyBox, { TextColor3 = "Text", PlaceholderColor3 = "Muted" })
	UI.Mask = label(input, "", 16, B, "Text", { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -92, 1, 0), Visible = false })

	UI.EyeBtn = button(input, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, 0), Size = UDim2.fromOffset(32, 32), BackgroundTransparency = 1 })
	corner(UI.EyeBtn, 8)
	bind(UI.EyeBtn, { BackgroundColor3 = "CardHover" })
	local _, eparts, slash = Icons.Eye(UI.EyeBtn, UDim2.fromOffset(6, 8))
	UI.EyeIcon = themedIcon(eparts, "Muted")
	UI.EyeSlash = slash
	slash.Visible = false
	UI.EyeBtn.MouseEnter:Connect(function() tween(UI.EyeBtn, { BackgroundTransparency = 0 }, 0.15); UI.EyeIcon.Set("Text") end)
	UI.EyeBtn.MouseLeave:Connect(function() tween(UI.EyeBtn, { BackgroundTransparency = 1 }, 0.2); UI.EyeIcon.Set("Muted") end)
	UI.Input = input
	table.insert(Intro, input)

	-- Submit button
	local submit = button(Main, { Position = UDim2.fromOffset(28, 186), Size = UDim2.fromOffset(158, 48), BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true })
	corner(submit, 12)
	UI.SubmitGrad = create("UIGradient", { Rotation = 35, Parent = submit })
	UI.SubmitMode = "accent"
	local hoverOverlay = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = submit })
	local sheen = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 0, Parent = submit })
	UI.SheenGrad = create("UIGradient", { Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({ kp(0, 1), kp(0.42, 1), kp(0.5, 0.82), kp(0.58, 1), kp(1, 1) }), Parent = sheen })
	local content = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = submit })
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	local iconHolder = box(content, 16)
	iconHolder.LayoutOrder = 1
	local arrow, aparts = Icons.Arrow(iconHolder)
	local check, cparts = Icons.Check(iconHolder)
	check.Visible = false
	local spinner = create("Frame", { Size = UDim2.fromOffset(15, 15), Position = UDim2.fromOffset(0.5, 0.5), BackgroundTransparency = 1, Visible = false, Parent = iconHolder })
	corner(spinner, 99)
	local sps = create("UIStroke", { Thickness = 2, Color = Color3.new(1, 1, 1), Parent = spinner })
	UI.SpinGrad = create("UIGradient", { Transparency = NumberSequence.new({ kp(0, 0), kp(0.75, 1), kp(1, 1) }), Parent = sps })
	UI.SubmitLabel = label(content, "Submit", 14, S, nil, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2 })
	UI.SubmitIcons = { arrow = arrow, check = check, spinner = spinner }
	UI.SubmitParts = { aparts, cparts, { { sps, "Color" } } }
	UI.Submit = submit
	ripple(submit); pressable(submit)
	submit.MouseEnter:Connect(function() tween(hoverOverlay, { BackgroundTransparency = 0.9 }, 0.2) end)
	submit.MouseLeave:Connect(function() tween(hoverOverlay, { BackgroundTransparency = 1 }, 0.25) end)
	table.insert(Intro, submit)

	-- Get key button
	local getkey = button(Main, { Position = UDim2.fromOffset(194, 186), Size = UDim2.fromOffset(158, 48), ClipsDescendants = true })
	bind(getkey, { BackgroundColor3 = "Card" })
	corner(getkey, 12)
	local gks = stroke(getkey, "Stroke")
	local gcontent = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = getkey })
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = gcontent })
	local gih = box(gcontent, 20)
	gih.LayoutOrder = 1
	local gkIcon, gkparts = Icons.Key(gih)
	local gkCheck, gcparts = Icons.Check(gih, UDim2.fromOffset(2, 2))
	gkCheck.Visible = false
	UI.GetKeyIcon = themedIcon(gkparts, "Text")
	themedIcon(gcparts, "Success")
	UI.GetKeyIcons = { key = gkIcon, check = gkCheck }
	UI.GetKeyLabel = label(gcontent, "Get a key", 14, M, "Text", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2 })
	UI.GetKey = getkey
	ripple(getkey); pressable(getkey)
	getkey.MouseEnter:Connect(function() tween(getkey, { BackgroundColor3 = P.CardHover }, 0.18); tween(gks, { Color = P.AccentStroke }, 0.18) end)
	getkey.MouseLeave:Connect(function() tween(getkey, { BackgroundColor3 = P.Card }, 0.25); tween(gks, { Color = P.Stroke }, 0.25) end)
	table.insert(Intro, getkey)

	-- Remember toggle
	local rem = button(Main, { Position = UDim2.fromOffset(28, 246), Size = UDim2.fromOffset(170, 28), BackgroundTransparency = 1 })
	local track = create("Frame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(36, 20), BorderSizePixel = 0, Parent = rem })
	corner(track, 99)
	local knob = create("Frame", { Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track })
	corner(knob, 99)
	label(rem, "Remember key", 13, M, "SubText", { Position = UDim2.fromOffset(46, 4), Size = UDim2.fromOffset(120, 20) })
	UI.Remember = Config.RememberByDefault and canFile
	local function paintToggle(instant)
		local goalT = { BackgroundColor3 = UI.Remember and P.Accent or P.Stroke }
		local goalK = { Position = UI.Remember and UDim2.fromOffset(19, 3) or UDim2.fromOffset(3, 3) }
		if instant then track.BackgroundColor3 = goalT.BackgroundColor3; knob.Position = goalK.Position
		else tween(track, goalT, 0.25); tween(knob, goalK, 0.35, Enum.EasingStyle.Back) end
	end
	onTheme(function(_, instant) paintToggle(instant) end)
	rem.MouseButton1Click:Connect(function()
		if not canFile then
			Notify("Not supported", "Your executor does not support file saving.", "warning", 3)
			return
		end
		UI.Remember = not UI.Remember
		paintToggle(false)
	end)
	table.insert(Intro, rem)

	-- Help link
	local help = button(Main, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(352, 246), Size = UDim2.fromOffset(110, 28), BackgroundTransparency = 1, FontFace = F(S), TextSize = 13, Text = "Need help?", TextXAlignment = Enum.TextXAlignment.Right })
	bind(help, { TextColor3 = "Accent" })
	help.MouseEnter:Connect(function() tween(help, { TextTransparency = 0.35 }, 0.15) end)
	help.MouseLeave:Connect(function() tween(help, { TextTransparency = 0 }, 0.15) end)
	UI.Help = help
	table.insert(Intro, help)

	-- Footer
	local footer = create("Frame", { Position = UDim2.fromOffset(28, 306), Size = UDim2.fromOffset(324, 46), BackgroundTransparency = 1, Parent = Main })
	local av = create("ImageLabel", {
		Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(42, 42), BorderSizePixel = 0,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150", Parent = footer,
	})
	bind(av, { BackgroundColor3 = "Card" })
	corner(av, 99)
	stroke(av, "AccentStroke", 1.5)
	local online = create("Frame", { Position = UDim2.fromOffset(31, 33), Size = UDim2.fromOffset(11, 11), BorderSizePixel = 0, Parent = footer })
	corner(online, 99)
	bind(online, { BackgroundColor3 = "Success" })
	stroke(online, "Bg", 2)

	local hour = tonumber(os.date("%H")) or 12
	local greet = hour < 12 and "Good morning," or (hour < 18 and "Good afternoon," or "Good evening,")
	label(footer, greet, 12, R, "SubText", { Position = UDim2.fromOffset(54, 5), Size = UDim2.fromOffset(150, 16) })
	label(footer, LocalPlayer.DisplayName .. "!", 15, B, "Text", { Position = UDim2.fromOffset(54, 22), Size = UDim2.fromOffset(150, 19) })

	local ex = create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BorderSizePixel = 0, Parent = footer })
	bind(ex, { BackgroundColor3 = "Card" })
	corner(ex, 99); pad(ex, 9, 10, 0, 0)
	stroke(ex, "Stroke")
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ex })
	local exDot = create("Frame", { Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, LayoutOrder = 1, Parent = ex })
	corner(exDot, 99)
	bind(exDot, { BackgroundColor3 = "Accent" })
	label(ex, #ExecutorName > 14 and ExecutorName:sub(1, 13) .. "…" or ExecutorName, 11, S, "SubText", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2 })
	table.insert(Intro, footer)

	-- Vertical divider
	local div = create("Frame", { Position = UDim2.fromOffset(372, 28), Size = UDim2.fromOffset(1, 324), BorderSizePixel = 0, Parent = Main })
	bind(div, { BackgroundColor3 = "Divider" })
	hGradient(div, false)
end

---------------------------------------------------------------------
-- RIGHT SIDE
---------------------------------------------------------------------
local function card(pos, size)
	local c = button(Main, { Position = pos, Size = size, ClipsDescendants = true })
	bind(c, { BackgroundColor3 = "Card" })
	corner(c, 12)
	local s = stroke(c, "Stroke")
	c.MouseEnter:Connect(function() tween(c, { BackgroundColor3 = P.CardHover }, 0.18); tween(s, { Color = P.AccentStroke }, 0.18) end)
	c.MouseLeave:Connect(function() tween(c, { BackgroundColor3 = P.Card }, 0.25); tween(s, { Color = P.Stroke }, 0.25) end)
	pressable(c, 0.98)
	return c
end

do
	-- Top buttons
	local tb = create("Frame", { Position = UDim2.fromOffset(612 - 124, 20), Size = UDim2.fromOffset(124, 28), BackgroundTransparency = 1, Parent = Main })
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tb })
	local function topBtn(order)
		local b = button(tb, { Size = UDim2.fromOffset(28, 28), LayoutOrder = order })
		bind(b, { BackgroundColor3 = "Card" })
		corner(b, 8)
		stroke(b, "Stroke")
		pressable(b, 0.9)
		return b
	end

	-- Theme toggle (moon / sun)
	local themeBtn = topBtn(1)
	local ti = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, ClipsDescendants = true, Parent = themeBtn })
	local orb = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0, Parent = ti })
	corner(orb, 99)
	bind(orb, { BackgroundColor3 = "SubText" })
	local cutter = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(12, 4.5), Size = UDim2.fromOffset(10, 10), BorderSizePixel = 0, Parent = ti })
	corner(cutter, 99)
	local rays = {}
	for i = 0, 7 do
		local a = math.rad(i * 45)
		local r = bar(ti, 2, 2, 8 + math.cos(a) * 6.5, 8 + math.sin(a) * 6.5)
		r.BackgroundTransparency = 1
		table.insert(rays, r)
	end
	local themeHover = false
	onTheme(function(p, instant)
		local c = themeHover and p.CardHover or p.Card
		local dark = State.Mode == "Dark"
		local goals = {
			cutter = { BackgroundColor3 = c, Position = dark and UDim2.fromOffset(12, 4.5) or UDim2.fromOffset(22, -6) },
			orb = { Size = dark and UDim2.fromOffset(12, 12) or UDim2.fromOffset(7, 7) },
		}
		if instant then
			for k, v in pairs(goals.cutter) do cutter[k] = v end
			orb.Size = goals.orb.Size
		else
			tween(cutter, goals.cutter, 0.45)
			tween(orb, goals.orb, 0.45, Enum.EasingStyle.Back)
		end
		for i, r in ipairs(rays) do
			r.BackgroundColor3 = p.SubText
			if instant then r.BackgroundTransparency = dark and 1 or 0
			else task.delay(dark and 0 or i * 0.03, function() tween(r, { BackgroundTransparency = dark and 1 or 0 }, 0.25) end) end
		end
	end)
	themeBtn.MouseEnter:Connect(function() themeHover = true; tween(themeBtn, { BackgroundColor3 = P.CardHover }, 0.18); tween(cutter, { BackgroundColor3 = P.CardHover }, 0.18) end)
	themeBtn.MouseLeave:Connect(function() themeHover = false; tween(themeBtn, { BackgroundColor3 = P.Card }, 0.25); tween(cutter, { BackgroundColor3 = P.Card }, 0.25) end)
	themeBtn.MouseButton1Click:Connect(function()
		State.Mode = State.Mode == "Dark" and "Light" or "Dark"
		applyTheme()
		task.delay(0.05, function() themeBtn.BackgroundColor3 = P.CardHover; cutter.BackgroundColor3 = P.CardHover end)
	end)
	UI.Tooltip(themeBtn, function() return State.Mode == "Dark" and "Light mode" or "Dark mode" end)

	-- Accent cycler
	local accBtn = topBtn(2)
	local ring = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Parent = accBtn })
	corner(ring, 99)
	stroke(ring, "Accent", 1.5, 0.45)
	local dot = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(8, 8), BorderSizePixel = 0, Parent = accBtn })
	corner(dot, 99)
	bind(dot, { BackgroundColor3 = "Accent" })
	hoverBg(accBtn, "Card", "CardHover")
	accBtn.MouseButton1Click:Connect(function()
		State.Accent = State.Accent % #Accents + 1
		applyTheme()
		dot.Size = UDim2.fromOffset(2, 2)
		tween(dot, { Size = UDim2.fromOffset(8, 8) }, 0.45, Enum.EasingStyle.Back)
	end)
	UI.Tooltip(accBtn, function() return "Accent: " .. Accents[State.Accent].Name end)

	-- Minimize
	local minBtn = topBtn(3)
	local _, mparts = Icons.Minus(minBtn, UDim2.fromOffset(6, 6))
	local mi = themedIcon(mparts, "SubText")
	minBtn.MouseEnter:Connect(function() tween(minBtn, { BackgroundColor3 = P.CardHover }, 0.18); mi.Set("Text") end)
	minBtn.MouseLeave:Connect(function() tween(minBtn, { BackgroundColor3 = P.Card }, 0.25); mi.Set("SubText") end)
	UI.MinBtn = minBtn
	UI.Tooltip(minBtn, "Minimize (" .. Config.ToggleKey.Name .. ")")

	-- Close
	local closeBtn = topBtn(4)
	local _, xparts = Icons.X(closeBtn, UDim2.fromOffset(6, 6))
	local xi = themedIcon(xparts, "SubText")
	closeBtn.MouseEnter:Connect(function() tween(closeBtn, { BackgroundColor3 = P.Card:Lerp(P.Error, 0.22) }, 0.18); xi.Set("Error") end)
	closeBtn.MouseLeave:Connect(function() tween(closeBtn, { BackgroundColor3 = P.Card }, 0.25); xi.Set("SubText") end)
	UI.CloseBtn = closeBtn
	UI.Tooltip(closeBtn, "Close")
	table.insert(Intro, tb)

	-- Detected game
	local dl = label(Main, "Detected game", 12, M, "SubText", { Position = UDim2.fromOffset(393, 27), Size = UDim2.fromOffset(90, 14) })
	table.insert(Intro, dl)

	local gc = card(UDim2.fromOffset(392, 58), UDim2.fromOffset(220, 64))
	local iconBg = create("Frame", { Position = UDim2.fromOffset(11, 11), Size = UDim2.fromOffset(42, 42), BorderSizePixel = 0, Parent = gc })
	bind(iconBg, { BackgroundColor3 = "AccentSoft" })
	corner(iconBg, 10)
	label(iconBg, "?", 18, B, "Accent", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local gi = create("ImageLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150", Parent = iconBg,
	})
	corner(gi, 10)
	UI.GameName = label(gc, "Detecting...", 13, S, "Text", { Position = UDim2.fromOffset(64, 11), Size = UDim2.fromOffset(146, 18) })
	local stRow = create("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(64, 33),
		Size = UDim2.fromOffset(0, 19),
		BorderSizePixel = 0,
		Parent = gc,
	})
	corner(stRow, 99)
	pad(stRow, 7, 8, 0, 0)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = stRow,
	})
	UI.GameBadge = stRow
	UI.GameBadgeStroke = stroke(stRow, "Stroke", 1)
	UI.GameDot = create("Frame", { Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, LayoutOrder = 1, Parent = stRow })
	corner(UI.GameDot, 99)
	UI.GameStatus = label(stRow, "Checking...", 11, S, nil, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 2,
	})
	UI.GameCard = gc
	table.insert(Intro, gc)

	local rdiv = create("Frame", { Position = UDim2.fromOffset(392, 134), Size = UDim2.fromOffset(220, 1), BorderSizePixel = 0, Parent = Main })
	bind(rdiv, { BackgroundColor3 = "Divider" })
	hGradient(rdiv, true)
	table.insert(Intro, rdiv)

	-- Discord card
	local dc = card(UDim2.fromOffset(392, 146), UDim2.fromOffset(220, 116))
	local badge = create("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(36, 36), BorderSizePixel = 0, Parent = dc, ClipsDescendants = true })
	bind(badge, { BackgroundColor3 = "Discord" })
	corner(badge, 10)
	local body = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = badge })
	corner(body, 6)
	for _, x in ipairs({ 6, 14 }) do
		local e = bar(body, 3.5, 4.5, x, 7)
		e.BackgroundColor3 = P.Discord
	end
	local discordIcon = create("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Active = false,
		Parent = badge,
		Visible = false,
	})
	corner(discordIcon, 10)
	UI.DiscordBadge = badge
	UI.DiscordDefaultIcon = body
	UI.DiscordIcon = discordIcon
	local cleanInvite = extractInviteCode(Config.DiscordInvite)
	UI.DiscordName = label(dc, Config.DiscordName, 13, S, "Text", { Position = UDim2.fromOffset(58, 13), Size = UDim2.fromOffset(150, 18) })
	UI.DiscordSub = label(dc, cleanInvite ~= "" and ("discord.gg/" .. cleanInvite) or "discord.gg", 12, R, "SubText", { Position = UDim2.fromOffset(58, 31), Size = UDim2.fromOffset(150, 16) })
	local sep = create("Frame", { Position = UDim2.fromOffset(12, 60), Size = UDim2.new(1, -24, 0, 1), BorderSizePixel = 0, Parent = dc })
	bind(sep, { BackgroundColor3 = "Divider" })
	local function stat(x, text, dotKey)
		local n = label(dc, "—", 17, B, "Text", { Position = UDim2.fromOffset(x, 68), Size = UDim2.fromOffset(96, 20) })
		local d = create("Frame", { Position = UDim2.fromOffset(x + 1, 95), Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, Parent = dc })
		corner(d, 99)
		bind(d, { BackgroundColor3 = dotKey })
		label(dc, text, 12, R, "SubText", { Position = UDim2.fromOffset(x + 12, 90), Size = UDim2.fromOffset(80, 16) })
		return n
	end
	UI.Online = stat(12, "Online", "Success")
	UI.Offline = stat(112, "Offline", "Muted")
	UI.DiscordCard = dc
	table.insert(Intro, dc)

	-- Info card
	local ic = card(UDim2.fromOffset(392, 274), UDim2.fromOffset(220, 78))
	local ib = create("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(36, 36), BorderSizePixel = 0, Parent = ic })
	bind(ib, { BackgroundColor3 = "AccentSoft" })
	corner(ib, 10)
	local _, iparts = Icons.Info(ib, UDim2.fromOffset(10, 10))
	themedIcon(iparts, "Accent")
	label(ic, "Information", 13, S, "Text", { Position = UDim2.fromOffset(58, 13), Size = UDim2.fromOffset(120, 18) })
	label(ic, "Tap to view", 12, R, "SubText", { Position = UDim2.fromOffset(58, 31), Size = UDim2.fromOffset(120, 16) })
	local _, chparts = Icons.Chevron(ic, UDim2.fromOffset(192, 22))
	themedIcon(chparts, "Muted")
	local newRow = create("Frame", { Position = UDim2.fromOffset(12, 56), Size = UDim2.fromOffset(196, 14), BackgroundTransparency = 1, Parent = ic })
	local nd = create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 1, 0.5, 0), Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, Parent = newRow })
	corner(nd, 99)
	bind(nd, { BackgroundColor3 = "Accent" })
	UI.NewDot = nd
	label(newRow, "What's new in " .. Config.Version, 11, M, "Accent", { Position = UDim2.fromOffset(13, 0), Size = UDim2.new(1, -13, 1, 0) })
	UI.InfoCard = ic
	table.insert(Intro, ic)
end

---------------------------------------------------------------------
-- INFO OVERLAY
---------------------------------------------------------------------
do
	local ov = button(Main, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 })
	bind(ov, { BackgroundColor3 = "Overlay" })
	local panel = button(ov, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 340, 0, 12), Size = UDim2.new(0, 318, 1, -24) })
	bind(panel, { BackgroundColor3 = "Panel" })
	corner(panel, 14)
	stroke(panel, "Stroke")
	label(panel, "Information", 16, B, "Text", { Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(220, 20) })
	label(panel, "Everything you need to know", 12, R, "SubText", { Position = UDim2.fromOffset(18, 37), Size = UDim2.fromOffset(220, 16) })
	local cb = button(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 16), Size = UDim2.fromOffset(28, 28) })
	bind(cb, { BackgroundColor3 = "Card" })
	corner(cb, 8)
	stroke(cb, "Stroke")
	local _, cparts = Icons.X(cb, UDim2.fromOffset(6, 6))
	themedIcon(cparts, "SubText")
	hoverBg(cb, "Card", "CardHover")
	pressable(cb, 0.9)

	local sc = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -70), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = panel,
	})
	bind(sc, { ScrollBarImageColor3 = "Stroke" })
	pad(sc, 16, 16, 4, 12)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sc })

	local order = 0
	local function nextOrder() order += 1; return order end
	local function section(text)
		label(sc, string.upper(text), 11, B, "Accent", { Size = UDim2.new(1, 0, 0, 22), TextYAlignment = Enum.TextYAlignment.Bottom, LayoutOrder = nextOrder() })
	end
	local function row(k, v)
		local f = create("Frame", { Size = UDim2.new(1, 0, 0, 36), BorderSizePixel = 0, LayoutOrder = nextOrder(), Parent = sc })
		bind(f, { BackgroundColor3 = "Card" })
		corner(f, 10)
		stroke(f, "Stroke")
		label(f, k, 12, R, "SubText", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 1, 0) })
		return label(f, v, 12, S, "Text", { Position = UDim2.new(0.45, 0, 0, 0), Size = UDim2.new(0.55, -12, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
	local function step(n, title, desc)
		local f = create("Frame", { Size = UDim2.new(1, 0, 0, 50), BorderSizePixel = 0, LayoutOrder = nextOrder(), Parent = sc })
		bind(f, { BackgroundColor3 = "Card" })
		corner(f, 10)
		stroke(f, "Stroke")
		local c = create("Frame", { Position = UDim2.fromOffset(12, 13), Size = UDim2.fromOffset(24, 24), BorderSizePixel = 0, Parent = f })
		bind(c, { BackgroundColor3 = "AccentSoft" })
		corner(c, 99)
		label(c, tostring(n), 12, B, "Accent", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		label(f, title, 13, S, "Text", { Position = UDim2.fromOffset(46, 8), Size = UDim2.new(1, -56, 0, 17) })
		label(f, desc, 11, R, "SubText", { Position = UDim2.fromOffset(46, 26), Size = UDim2.new(1, -56, 0, 15) })
	end

	section("How to get a key")
	step(1, "Press \"Get a key\"", "The link is copied to your clipboard")
	step(2, "Complete the checkpoints", "Open the link in your browser")
	step(3, "Paste & submit", "Your key is saved for next time")

	section("Session")
	row("Executor", ExecutorName)
	UI.InfoGame = row("Game status", "Checking...")
	row("Place ID", tostring(game.PlaceId))
	row("Server", #Players:GetPlayers() .. " / " .. Players.MaxPlayers .. " players")
	row("Toggle key", Config.ToggleKey.Name)

	section("Changelog")
	for i, entry in ipairs(Config.Changelog) do
		local f = create("Frame", { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), BorderSizePixel = 0, LayoutOrder = nextOrder(), Parent = sc })
		bind(f, { BackgroundColor3 = "Card" })
		corner(f, 10)
		stroke(f, i == 1 and "AccentStroke" or "Stroke")
		pad(f, 12, 12, 10, 12)
		create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
		local head = create("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 0, Parent = f })
		local vp = create("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), BorderSizePixel = 0, Parent = head })
		bind(vp, { BackgroundColor3 = "AccentSoft" })
		corner(vp, 99); pad(vp, 7, 7, 0, 0)
		label(vp, entry.Version, 10, B, "Accent", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextTruncate = Enum.TextTruncate.None })
		label(head, entry.Date, 11, R, "Muted", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Right })
		for j, ch in ipairs(entry.Changes) do
			label(f, "•  " .. ch, 12, R, "SubText", { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), TextWrapped = true, TextTruncate = Enum.TextTruncate.None, LayoutOrder = j })
		end
	end

	local open = false
	UI.OpenInfo = function()
		if open then return end
		open = true
		ov.Visible = true
		tween(ov, { BackgroundTransparency = State.Mode == "Dark" and 0.45 or 0.65 }, 0.2)
		panel.Position = UDim2.new(1, 340, 0, 12)
		tween(panel, { Position = UDim2.new(1, -12, 0, 12) }, 0.28, Enum.EasingStyle.Quint)
		tween(UI.NewDot, { BackgroundTransparency = 1 }, 0.2)
	end
	UI.CloseInfo = function()
		if not open then return end
		open = false
		tween(ov, { BackgroundTransparency = 1 }, 0.18)
		tween(panel, { Position = UDim2.new(1, 340, 0, 12) }, 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.22, function() if not open then ov.Visible = false end end)
	end
	ov.MouseButton1Click:Connect(UI.CloseInfo)
	cb.MouseButton1Click:Connect(UI.CloseInfo)
end

---------------------------------------------------------------------
-- SUCCESS VIEW
---------------------------------------------------------------------
do
	local sv = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 30, Parent = Main })
	bind(sv, { BackgroundColor3 = "Bg" })
	corner(sv, 16)
	local glow = create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 200), BorderSizePixel = 0, Parent = sv })
	bind(glow, { BackgroundColor3 = "Accent" })
	create("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({ kp(0, 0.75), kp(0.5, 0.93), kp(1, 1) }), Parent = glow })

	local halo = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -52), Size = UDim2.fromOffset(80, 80), BackgroundTransparency = 1, Parent = sv })
	corner(halo, 999)
	local hs = stroke(halo, "Accent", 2)
	local circle = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -52), Size = UDim2.fromOffset(80, 80), BorderSizePixel = 0, Parent = sv })
	corner(circle, 999)
	local cg = create("UIGradient", { Rotation = 45, Parent = circle })
	circle.BackgroundColor3 = Color3.new(1, 1, 1)
	onTheme(function(p) cg.Color = ColorSequence.new(p.Accent, p.AccentDark) end)
	local cscale = create("UIScale", { Scale = 0, Parent = circle })
	local ck = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Parent = circle })
	create("UIScale", { Scale = 2.4, Parent = ck })
	local _, cparts = Icons.Check(ck)
	paint(cparts, Color3.new(1, 1, 1))

	local title = label(sv, "Access granted", 22, B, "Text", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 4), Size = UDim2.fromOffset(400, 28), TextXAlignment = Enum.TextXAlignment.Center })
	local sub = label(sv, "Welcome, " .. LocalPlayer.DisplayName .. " — preparing " .. Config.HubName, 13, R, "SubText", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 34), Size = UDim2.fromOffset(400, 18), TextXAlignment = Enum.TextXAlignment.Center })
	local track = create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 68), Size = UDim2.fromOffset(240, 6), BorderSizePixel = 0, Parent = sv })
	bind(track, { BackgroundColor3 = "Card" })
	corner(track, 99)
	local fill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track })
	corner(fill, 99)
	local fg = create("UIGradient", { Parent = fill })
	onTheme(function(p) fg.Color = ColorSequence.new(p.AccentDark, p.Accent) end)
	local stepL = label(sv, "", 12, M, "Muted", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 82), Size = UDim2.fromOffset(300, 16), TextXAlignment = Enum.TextXAlignment.Center })

	UI.PlaySuccess = function(done)
		sv.Visible = true
		tween(sv, { BackgroundTransparency = 0 }, 0.2)
		task.wait(0.05)
		tween(cscale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
		task.spawn(function()
			for _ = 1, 2 do
				halo.Size = UDim2.fromOffset(80, 80); hs.Transparency = 0
				tween(halo, { Size = UDim2.fromOffset(140, 140) }, 0.6)
				tween(hs, { Transparency = 1 }, 0.6)
				task.wait(0.45)
			end
		end)
		local tp, sp = title.Position, sub.Position
		title.Position = tp + UDim2.fromOffset(0, 8); sub.Position = sp + UDim2.fromOffset(0, 8)
		tween(title, { Position = tp }, 0.3); task.wait(0.04); tween(sub, { Position = sp }, 0.3)
		local steps = { { "Validating key...", 0.45 }, { "Launching " .. Config.HubName .. "...", 1 } }
		for _, s in ipairs(steps) do
			stepL.Text = s[1]
			tween(fill, { Size = UDim2.fromScale(s[2], 1) }, 0.25, Enum.EasingStyle.Quart)
			task.wait(0.28)
		end
		task.wait(0.12)
		if done then done() end
	end
end

---------------------------------------------------------------------
-- MINIMIZED PILL
---------------------------------------------------------------------
do
	local pill = button(Gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -70), Size = UDim2.fromOffset(230, 46), Visible = false, ZIndex = 5 })
	bind(pill, { BackgroundColor3 = "Panel" })
	corner(pill, 14)
	stroke(pill, "Stroke")
	local lg = create("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(30, 30), BorderSizePixel = 0, Parent = pill })
	bind(lg, { BackgroundColor3 = "AccentSoft" })
	corner(lg, 9)
	local d = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 11), Rotation = 45, BackgroundTransparency = 1, Parent = lg })
	corner(d, 3)
	stroke(d, "Accent", 2)
	label(pill, Config.HubName .. " " .. Config.Subtitle, 13, B, "Text", { Position = UDim2.fromOffset(48, 7), Size = UDim2.fromOffset(170, 17) })
	label(pill, "Click to reopen  •  " .. Config.ToggleKey.Name, 11, R, "SubText", { Position = UDim2.fromOffset(48, 24), Size = UDim2.fromOffset(170, 15) })
	hoverBg(pill, "Panel", "CardHover")
	pressable(pill, 0.95)
	UI.Pill = pill
end

---------------------------------------------------------------------
-- LAYERING
---------------------------------------------------------------------
for _, c in ipairs(Main:GetChildren()) do
	if c:IsA("GuiObject") and c.ZIndex == 1 and c ~= UI.BgFill then c.ZIndex = 5 end
end

---------------------------------------------------------------------
-- LOGIC
---------------------------------------------------------------------
local busy, verified, cooling, minimized, closing = false, false, false, false, false
local attempts = 0
local baseScale = 1
local KeyHidden = false
local Focused = false

local function fitScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min((vp.X - 24) / W, (vp.Y - 60) / H), 0.45, 1)
end

local function setStatus(text, kind)
	local col = ({ error = P.Error, success = P.Success, warning = P.Warning })[kind] or P.SubText
	UI.Status.Text = text
	UI.Status.TextColor3 = col
	UI.Status.TextTransparency = 1
	tween(UI.Status, { TextTransparency = 0 }, 0.3)
end

local function setInputStroke(key)
	UI.InputStrokeKey = key
	tween(UI.InputStroke, { Color = P[key] }, 0.25)
end

local function applySubmitColor()
	local m = UI.SubmitMode
	local c1, c2, tc
	if m == "error" then c1, c2, tc = P.Error, P.Error:Lerp(Color3.new(0, 0, 0), 0.3), P.White
	elseif m == "disabled" then c1, c2, tc = P.CardHover, P.Card, P.SubText
	elseif m == "success" then c1, c2, tc = P.Success, P.Success:Lerp(Color3.new(0, 0, 0), 0.3), P.White
	else c1, c2, tc = P.Accent:Lerp(P.AccentDark, 0.3), P.AccentDark, P.White end
	UI.SubmitGrad.Color = ColorSequence.new(c1, c2)
	UI.SubmitLabel.TextColor3 = tc
	for _, parts in ipairs(UI.SubmitParts) do paint(parts, tc) end
end
onTheme(function() applySubmitColor() end)

local function setSubmit(icon, text, mode)
	for name, obj in pairs(UI.SubmitIcons) do obj.Visible = (name == icon) end
	UI.SubmitLabel.Text = text
	UI.SubmitMode = mode or "accent"
	applySubmitColor()
end

local function updateMask()
	local t = UI.KeyBox.Text
	if KeyHidden and not Focused and #t > 0 then
		UI.Mask.Text = string.rep("•", math.min(#t, 24))
		UI.Mask.Visible = true
		UI.KeyBox.TextTransparency = 1
	else
		UI.Mask.Visible = false
		UI.KeyBox.TextTransparency = 0
	end
end



local function validate(key)
	if Config.ValidateKey then return Config.ValidateKey(key) end
	for _, k in ipairs(Config.Keys) do
		if k == key then return true end
	end
	return false, "Invalid key"
end

local function destroyAll()
	Alive = false
	for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
	Gui:Destroy()
end

local function closeUI(callback)
	if closing then return end
	closing = true
	UI.CloseInfo()
	tween(UI.Scale, { Scale = 0 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(UI.Holder, { Position = UDim2.new(0.5, 0, 0.5, 25) }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	tween(UI.BorderStroke, { Transparency = 1 }, 0.16)
	tween(UI.Pill, { Position = UDim2.new(0.5, 0, 0, -70) }, 0.2)
	task.delay(0.23, function()
		destroyAll()
		if callback then callback() end
	end)
end

local function showWindow()
	UI.Holder.Visible = true
	UI.Holder.Position = UDim2.fromScale(0.5, 0.5)
	UI.Scale.Scale = baseScale * 0.82
	tween(UI.Scale, { Scale = baseScale }, 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tween(UI.BorderStroke, { Transparency = 0 }, 0.2)
end

local function setMinimized(v)
	if v == minimized or closing then return end
	minimized = v
	if v then
		UI.CloseInfo()
		tween(UI.Scale, { Scale = baseScale * 0.75 }, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tween(UI.Holder, { Position = UDim2.new(0.5, 0, 0, -40) }, 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(UI.BorderStroke, { Transparency = 1 }, 0.15)
		task.delay(0.2, function() if minimized then UI.Holder.Visible = false end end)
		UI.Pill.Visible = true
		UI.Pill.Position = UDim2.new(0.5, 0, 0, -70)
		tween(UI.Pill, { Position = UDim2.new(0.5, 0, 0, 14) }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		UI.Holder.Position = UDim2.new(0.5, 0, 0, -30)
		UI.Scale.Scale = baseScale * 0.8
		UI.Holder.Visible = true
		tween(UI.Holder, { Position = UDim2.fromScale(0.5, 0.5) }, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(UI.Scale, { Scale = baseScale }, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(UI.BorderStroke, { Transparency = 0 }, 0.2)
		tween(UI.Pill, { Position = UDim2.new(0.5, 0, 0, -70) }, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.2, function() if not minimized then UI.Pill.Visible = false end end)
	end
end

local function startCooldown()
	cooling = true
	task.spawn(function()
		for i = Config.Cooldown, 1, -1 do
			if not Alive then return end
			setSubmit("arrow", "Wait " .. i .. "s", "disabled")
			task.wait(1)
		end
		cooling = false
		attempts = 0
		setSubmit("arrow", "Submit", "accent")
		setStatus("You can try again", "warning")
	end)
end

local function submit()
	if busy or verified or cooling or closing then return end
	local key = trim(UI.KeyBox.Text)
	if key == "" then
		setInputStroke("Error")
		setStatus("Please enter a key", "error")
		task.delay(1.4, function() if not Focused and not verified then setInputStroke("Stroke") end end)
		return
	end
	busy = true
	UI.KeyBox:ReleaseFocus()
	setSubmit("spinner", "Verifying...", "accent")
	setStatus("Checking your key...", nil)
	task.wait(0.35)
	local ok, valid, msg = pcall(validate, key)
	if not ok then valid, msg = false, "Validation error" end

	if valid then
		verified = true
		setSubmit("check", "Verified", "success")
		setInputStroke("Success")
		UI.InputIcon.Set("Success")
		setStatus("Key accepted", "success")
		if UI.Remember and canFile then pcall(writefile, Config.FileName, key) end
		Notify("Key verified", "Welcome to " .. Config.HubName .. "! Loading everything up.", "success", 3)
		task.wait(0.25)
		UI.PlaySuccess(function()
			closeUI(function() pcall(Config.OnSuccess, key) end)
		end)
	else
		attempts += 1
		busy = false
		setInputStroke("Error")
		UI.InputIcon.Set("Error")
		local left = Config.MaxAttempts - attempts
		setSubmit("arrow", "Invalid key", "error")
		if canFile then pcall(function() if isfile(Config.FileName) then delfile(Config.FileName) end end) end
		if left <= 0 then
			setStatus("Too many attempts", "error")
			Notify("Slow down", "Too many invalid attempts. Wait " .. Config.Cooldown .. " seconds.", "error", 4)
			task.wait(0.9)
			startCooldown()
		else
			setStatus((msg or "Invalid key") .. " • " .. left .. " left", "error")
			Notify("Invalid key", (msg or "That key is not valid.") .. " Press \"Get a key\" for a new one.", "error", 4)
			task.delay(1.4, function()
				if not verified and not cooling and not busy then setSubmit("arrow", "Submit", "accent") end
			end)
		end
		task.delay(1.6, function()
			if not verified and not Focused then setInputStroke("Stroke"); UI.InputIcon.Set("Muted") end
		end)
	end
end

---------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------
UI.Submit.MouseButton1Click:Connect(function() task.spawn(submit) end)

UI.KeyBox.Focused:Connect(function()
	Focused = true
	updateMask()
	if not verified then setInputStroke("Accent"); UI.InputIcon.Set("Accent") end
end)
UI.KeyBox.FocusLost:Connect(function(enter)
	Focused = false
	updateMask()
	if not verified then setInputStroke("Stroke"); UI.InputIcon.Set("Muted") end
	if enter then task.spawn(submit) end
end)
UI.KeyBox:GetPropertyChangedSignal("Text"):Connect(function()
	updateMask()
	if UI.Status.Text ~= "" and not busy and not verified and not cooling then
		tween(UI.Status, { TextTransparency = 1 }, 0.2)
	end
end)

UI.EyeBtn.MouseButton1Click:Connect(function()
	KeyHidden = not KeyHidden
	UI.EyeSlash.Visible = KeyHidden
	UI.EyeSlash.Size = UDim2.fromOffset(0, 1.6)
	tween(UI.EyeSlash, { Size = UDim2.fromOffset(20, 1.6) }, 0.25)
	updateMask()
end)

local copyBusy = false
UI.GetKey.MouseButton1Click:Connect(function()
	if copyBusy then return end
	copyBusy = true
	local ok = copy(Config.KeyLink)
	UI.GetKeyIcons.key.Visible = false
	UI.GetKeyIcons.check.Visible = true
	UI.GetKeyLabel.Text = ok and "Link copied!" or "See console"
	if ok then
		Notify("Link copied", "Paste it in your browser to get your key.", "success", 4)
	else
		print("[" .. Config.HubName .. "] Key link: " .. Config.KeyLink)
		Notify("Clipboard unavailable", "The key link was printed to the console (F9).", "warning", 5)
	end
	task.delay(2, function()
		if not Alive then return end
		UI.GetKeyIcons.key.Visible = true
		UI.GetKeyIcons.check.Visible = false
		UI.GetKeyLabel.Text = "Get a key"
		copyBusy = false
	end)
end)

UI.DiscordCard.MouseButton1Click:Connect(function()
	local link = "https://discord.gg/" .. Config.DiscordInvite
	if copy(link) then
		Notify("Invite copied", "Join " .. Config.DiscordName .. " for updates and free keys.", "info", 4)
	else
		print("[" .. Config.HubName .. "] Discord: " .. link)
		Notify("Discord", link, "info", 5)
	end
end)

UI.InfoCard.MouseButton1Click:Connect(function() UI.OpenInfo() end)
UI.Help.MouseButton1Click:Connect(function() UI.OpenInfo() end)
UI.GameCard.MouseButton1Click:Connect(function() UI.OpenInfo() end)
UI.MinBtn.MouseButton1Click:Connect(function() setMinimized(true) end)
UI.Pill.MouseButton1Click:Connect(function() setMinimized(false) end)
UI.CloseBtn.MouseButton1Click:Connect(function()
	closeUI()
end)

conn(UIS.InputBegan, function(input, gp)
	if gp then return end
	if input.KeyCode == Config.ToggleKey then setMinimized(not minimized) end
end)

-- Drag
do
	local dragging, dragStart, startPos, dragInput = false, nil, nil, nil
	UI.DragZone.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, UI.Holder.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UI.DragZone.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
	end)
	conn(UIS.InputChanged, function(input)
		if dragging and input == dragInput then
			local d = input.Position - dragStart
			tween(UI.Holder, { Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y) }, 0.14, Enum.EasingStyle.Quad)
		end
	end)
end

-- Viewport scaling
if workspace.CurrentCamera then
	conn(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
		baseScale = fitScale()
		if not minimized and not closing then tween(UI.Scale, { Scale = baseScale }, 0.25) end
	end)
end

-- Animations loop
conn(RunService.RenderStepped, function()
	if minimized then return end
	local t = os.clock()
	UI.LogoGrad.Rotation = (t * 110) % 360
	UI.LogoDiamond.Rotation = 45 + math.sin(t * 1.4) * 12
	UI.LogoCore.Size = UDim2.fromOffset(7 + math.sin(t * 2.6) * 1.2, 7 + math.sin(t * 2.6) * 1.2)
	UI.OrbGrad.Rotation = (t * 22) % 360
	UI.GlowGrad.Offset = Vector2.new(0, math.sin(t * 1.1) * 0.07)
	if UI.SubmitIcons.spinner.Visible then UI.SpinGrad.Rotation = (t * 420) % 360 end
end)

-- Sheen loop
task.spawn(function()
	while Alive do
		task.wait(3.2)
		if not Alive then break end
		if not minimized and not busy then
			UI.SheenGrad.Offset = Vector2.new(-1, 0)
			tween(UI.SheenGrad, { Offset = Vector2.new(1, 0) }, 1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end
end)

-- Particles
task.spawn(function()
	while Alive do
		if not minimized and UI.FX and UI.FX.Parent then
			local s = math.random(2, 4)
			local x = math.random(20, W - 20)
			local p = create("Frame", {
				Size = UDim2.fromOffset(s, s), Position = UDim2.fromOffset(x, H - 12), BackgroundColor3 = P.Accent,
				BackgroundTransparency = 1, BorderSizePixel = 0, Parent = UI.FX,
			})
			corner(p, 99)
			local dur = math.random(45, 85) / 10
			tween(p, { Position = UDim2.fromOffset(x + math.random(-40, 40), math.random(math.floor(H * 0.2), math.floor(H * 0.65))) }, dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			tween(p, { BackgroundTransparency = math.random(35, 65) / 100 }, dur * 0.3)
			task.delay(dur * 0.45, function() if p.Parent then tween(p, { BackgroundTransparency = 1 }, dur * 0.55) end end)
			task.delay(dur + 0.1, function() p:Destroy() end)
		end
		task.wait(0.3)
	end
end)

---------------------------------------------------------------------
-- DATA (game + discord)
---------------------------------------------------------------------
local gameSupported = Config.SupportedGames[game.PlaceId] or Config.SupportedGames[game.GameId]
local function paintGameStatus()
	if gameSupported then
		UI.GameDot.BackgroundColor3 = P.Success
		UI.GameStatus.TextColor3 = P.Success
		UI.GameStatus.Text = "Supported"
		if UI.GameBadge then
			UI.GameBadge.BackgroundColor3 = P.Card:Lerp(P.Success, State.Mode == "Dark" and 0.18 or 0.13)
		end
		if UI.GameBadgeStroke then
			UI.GameBadgeStroke.Color = P.Success
			UI.GameBadgeStroke.Transparency = 0.42
		end
		if UI.InfoGame then
			UI.InfoGame.Text = "Supported"
			UI.InfoGame.TextColor3 = P.Success
		end
	else
		UI.GameDot.BackgroundColor3 = P.Error
		UI.GameStatus.TextColor3 = P.Error
		UI.GameStatus.Text = "Not Supported"
		if UI.GameBadge then
			UI.GameBadge.BackgroundColor3 = P.Card:Lerp(P.Error, State.Mode == "Dark" and 0.18 or 0.13)
		end
		if UI.GameBadgeStroke then
			UI.GameBadgeStroke.Color = P.Error
			UI.GameBadgeStroke.Transparency = 0.42
		end
		if UI.InfoGame then
			UI.InfoGame.Text = "Not Supported"
			UI.InfoGame.TextColor3 = P.Error
		end
	end
end
onTheme(function() paintGameStatus() end)
paintGameStatus()

task.spawn(function()
	local name = type(gameSupported) == "string" and gameSupported or nil
	local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
	if ok and info and info.Name then name = info.Name end
	if Alive then UI.GameName.Text = name or "Unknown Experience" end
end)

local function countTo(lbl, target)
	local nv = Instance.new("NumberValue")
	nv.Value = tonumber((lbl.Text:gsub(",", ""))) or 0
	nv.Changed:Connect(function(v) lbl.Text = comma(v) end)
	local tw = tween(nv, { Value = target }, 1.6, Enum.EasingStyle.Quart)
	tw.Completed:Connect(function() lbl.Text = comma(target); nv:Destroy() end)
end

local function setDiscordIcon(icon)
	if not (Alive and UI.DiscordIcon and icon) then return end
	local iconStr = tostring(icon)
	if iconStr == "" then return end
	if tonumber(iconStr) then
		iconStr = "rbxassetid://" .. iconStr
	end
	if iconStr:find("://") and not iconStr:find("^https?://") then
		UI.DiscordIcon.Image = iconStr
		UI.DiscordIcon.Visible = true
		if UI.DiscordDefaultIcon then UI.DiscordDefaultIcon.Visible = false end
		return
	end
	task.spawn(function()
		local getAsset = getcustomasset or getsynasset
		if getAsset and typeof(writefile) == "function" and typeof(isfile) == "function" then
			local hash = iconStr:match("icons/%d+/([%w%-_]+)%.png") or iconStr:match("([^/?]+)%.png") or "server"
			local filename = "discord_icon_" .. hash .. ".png"
			local exists = false
			pcall(function() exists = isfile(filename) end)
			if not exists and iconStr:find("^https?://") then
				local bytes = httpGet(iconStr, false)
				if bytes and #bytes > 0 then
					pcall(writefile, filename, bytes)
					exists = true
				end
			end
			if exists and Alive then
				local ok, asset = pcall(getAsset, filename)
				if ok and asset and UI.DiscordIcon then
					UI.DiscordIcon.Image = asset
					UI.DiscordIcon.Visible = true
					if UI.DiscordDefaultIcon then UI.DiscordDefaultIcon.Visible = false end
				end
			end
		end
	end)
end

if Config.DiscordIcon and Config.DiscordIcon ~= "" then
	setDiscordIcon(Config.DiscordIcon)
end

local function fetchJson(url)
	local body, status = httpGet(url, true)
	if not body then return nil, status end
	local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
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

local function refreshDiscord()
	local code = extractInviteCode(Config.DiscordInvite)
	local data = nil
	if code ~= "" then
		local urls = {
			"https://discord.com/api/v10/invites/" .. code .. "?with_counts=true&with_expiration=true",
			"https://discord.com/api/v9/invites/" .. code .. "?with_counts=true&with_expiration=true",
			"https://discordapp.com/api/v9/invites/" .. code .. "?with_counts=true&with_expiration=true",
		}
		for _, url in ipairs(urls) do
			local d, status = fetchJson(url)
			data = d
			if (data and (data.approximate_member_count ~= nil or data.approximate_presence_count ~= nil)) or status == 404 then
				break
			end
		end
	end
	if not Alive then return false end

	if type(data) == "table" and (data.approximate_member_count ~= nil or data.approximate_presence_count ~= nil) then
		local online = tonumber(data.approximate_presence_count) or 0
		local total = tonumber(data.approximate_member_count) or online
		countTo(UI.Online, online)
		countTo(UI.Offline, math.max(total - online, 0))
		if data.guild and data.guild.name and Config.DiscordName == "" then UI.DiscordName.Text = data.guild.name end
		if (not Config.DiscordIcon or Config.DiscordIcon == "") and data.guild and data.guild.id and data.guild.icon then
			local guildId = tostring(data.guild.id)
			local iconHash = tostring(data.guild.icon)
			local iconUrl = "https://cdn.discordapp.com/icons/" .. guildId .. "/" .. iconHash .. ".png?size=128"
			setDiscordIcon(iconUrl)
		end
		return true
	end

	local guildId = tostring(Config.DiscordGuildId or ""):gsub("%s+", "")
	if guildId ~= "" then
		local w = fetchJson("https://discord.com/api/guilds/" .. guildId .. "/widget.json")
		if w and (w.presence_count ~= nil or type(w.members) == "table") then
			local online = tonumber(w.presence_count) or (type(w.members) == "table" and #w.members or 0)
			countTo(UI.Online, online)
			UI.Offline.Text = "—"
			if w.name and Config.DiscordName == "" then UI.DiscordName.Text = w.name end
			return true
		end
	end

	if UI.Online.Text == "—" or UI.Online.Text == "N/A" then
		local fbOnline = tonumber(Config.DiscordOnline)
		local fbOffline = tonumber(Config.DiscordOffline)
		if fbOnline then
			countTo(UI.Online, fbOnline)
		else
			UI.Online.Text = "—"
		end
		if fbOffline then
			countTo(UI.Offline, fbOffline)
		else
			UI.Offline.Text = "—"
		end
	end
	return false
end
task.spawn(function()
	local okFirst = refreshDiscord()
	if not okFirst and Alive then
		task.wait(5)
		if Alive then refreshDiscord() end
	end
	while Alive do
		task.wait(60)
		if Alive then refreshDiscord() end
	end
end)

---------------------------------------------------------------------
-- INTRO
---------------------------------------------------------------------
baseScale = fitScale()
for i, obj in ipairs(Intro) do
	local base = obj.Position
	obj.Position = base + UDim2.fromOffset(0, 8)
	task.delay(0.04 + i * 0.015, function()
		tween(obj, { Position = base }, 0.28, Enum.EasingStyle.Quint)
	end)
end
showWindow()

-- Saved key auto-login
task.delay(0.55, function()
	if not Alive then return end
	local saved
	if canFile then
		pcall(function() if isfile(Config.FileName) then saved = trim(readfile(Config.FileName)) end end)
	end
	if saved and saved ~= "" then
		UI.KeyBox.Text = saved
		KeyHidden = true
		UI.EyeSlash.Visible = true
		updateMask()
		Notify("Saved key found", "Checking your saved key automatically...", "info", 2.5)
		task.wait(0.3)
		submit()
	else
		Notify(Config.HubName .. " " .. Config.Subtitle, "Press " .. Config.ToggleKey.Name .. " to hide / show this window.", "info", 3.5)
	end
end)
