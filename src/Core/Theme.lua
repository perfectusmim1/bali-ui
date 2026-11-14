--[[
	Bali UI · Core/Theme
	Theme presets, live re-theming through property bindings, accent overrides and typography.

	Binding values:
	  "Key"        -> Theme.Current[Key]
	  "@Weight"    -> Font face of the active family with that weight (Regular/Medium/SemiBold/Bold)
	  function(t)  -> computed from the active theme table
]]

local Tween = require("Core/Tween")
local Signal = require("Core/Signal")

local Theme = {}

local rgb = Color3.fromRGB

Theme.Fonts = {
	Gotham = "rbxasset://fonts/families/GothamSSm.json",
	Builder = "rbxasset://fonts/families/BuilderSans.json",
	Montserrat = "rbxasset://fonts/families/Montserrat.json",
	Ubuntu = "rbxasset://fonts/families/Ubuntu.json",
	Nunito = "rbxasset://fonts/families/Nunito.json",
	Mono = "rbxasset://fonts/families/RobotoMono.json",
}
Theme.FontOrder = { "Builder", "Gotham", "Montserrat", "Ubuntu", "Nunito" }
Theme.FontFamily = "Builder"

-- Base (dark) palette every preset inherits from
local Base = {
	Dark = true,
	Accent = rgb(214, 64, 236),
	Accent2 = rgb(124, 58, 237),
	AccentText = rgb(255, 255, 255),

	Background = rgb(11, 11, 14),
	BackgroundTransparency = 0.035,
	Sidebar = rgb(255, 255, 255),
	SidebarTransparency = 0.975,

	Card = rgb(20, 20, 25),
	CardTransparency = 0.12,
	Elevated = rgb(34, 34, 44),
	Tile = rgb(29, 29, 36),
	TileHover = rgb(37, 37, 46),
	TileTransparency = 0.2,
	Field = rgb(15, 15, 19),
	FieldHover = rgb(22, 22, 28),

	Stroke = rgb(255, 255, 255),
	StrokeTransparency = 0.89,
	Divider = rgb(255, 255, 255),
	DividerTransparency = 0.92,

	Text = rgb(246, 246, 250),
	SubText = rgb(184, 188, 206),
	Muted = rgb(140, 144, 162),

	ToggleOff = rgb(54, 54, 64),
	Knob = rgb(255, 255, 255),

	Success = rgb(52, 211, 153),
	Warning = rgb(251, 191, 36),
	Error = rgb(248, 113, 113),
	Info = rgb(96, 165, 250),

	Shadow = rgb(0, 0, 0),
	ShadowTransparency = 0.3,
	GlowTransparency = 0.84,
	Overlay = rgb(0, 0, 0),
	OverlayTransparency = 0.56,
	NoiseTransparency = 0.965,
}

local function computeAccentHover(theme)
	local target = (theme.Dark == false) and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
	return theme.Accent:Lerp(target, 0.14)
end

local function preset(overrides)
	local theme = table.clone(Base)
	for key, value in pairs(overrides) do
		theme[key] = value
	end
	if theme.AccentHover == nil then
		theme.AccentHover = computeAccentHover(theme)
	end
	return theme
end

Theme.Presets = {
	Midnight = preset({}),
	Ocean = preset({
		Accent = rgb(59, 130, 246),
		Accent2 = rgb(99, 102, 241),
		Background = rgb(9, 12, 21),
		Card = rgb(16, 20, 33),
		Elevated = rgb(28, 35, 56),
		Tile = rgb(23, 29, 46),
		TileHover = rgb(30, 38, 59),
		Field = rgb(12, 15, 26),
		FieldHover = rgb(18, 23, 38),
		Text = rgb(240, 244, 252),
		SubText = rgb(176, 188, 216),
		Muted = rgb(134, 144, 172),
		ToggleOff = rgb(44, 52, 74),
	}),
	Graphite = preset({
		Accent = rgb(10, 132, 255),
		Accent2 = rgb(94, 92, 230),
		Background = rgb(17, 17, 19),
		Card = rgb(27, 27, 30),
		Elevated = rgb(44, 44, 50),
		Tile = rgb(38, 38, 42),
		TileHover = rgb(47, 47, 52),
		Field = rgb(21, 21, 23),
		FieldHover = rgb(28, 28, 31),
		Text = rgb(250, 250, 252),
		SubText = rgb(180, 182, 192),
		Muted = rgb(138, 140, 150),
		ToggleOff = rgb(58, 58, 62),
	}),
	Aurora = preset({
		Accent = rgb(45, 212, 191),
		Accent2 = rgb(56, 189, 248),
		Background = rgb(8, 14, 15),
		Card = rgb(14, 22, 24),
		Elevated = rgb(24, 38, 42),
		Tile = rgb(20, 32, 35),
		TileHover = rgb(26, 41, 45),
		Field = rgb(10, 17, 18),
		FieldHover = rgb(15, 24, 26),
		Text = rgb(236, 250, 248),
		SubText = rgb(170, 200, 198),
		Muted = rgb(128, 156, 154),
		ToggleOff = rgb(38, 54, 57),
	}),
	Sunset = preset({
		Accent = rgb(251, 113, 133),
		Accent2 = rgb(249, 115, 22),
		Background = rgb(15, 11, 12),
		Card = rgb(25, 18, 20),
		Elevated = rgb(42, 30, 34),
		Tile = rgb(36, 26, 29),
		TileHover = rgb(46, 33, 37),
		Field = rgb(18, 13, 15),
		FieldHover = rgb(26, 19, 21),
		Text = rgb(252, 242, 244),
		SubText = rgb(198, 174, 180),
		Muted = rgb(150, 130, 136),
		ToggleOff = rgb(60, 45, 49),
	}),
	Emerald = preset({
		Accent = rgb(52, 211, 153),
		Accent2 = rgb(16, 185, 129),
		Background = rgb(9, 13, 11),
		Card = rgb(15, 21, 18),
		Elevated = rgb(26, 37, 32),
		Tile = rgb(22, 31, 27),
		TileHover = rgb(29, 40, 35),
		Field = rgb(11, 16, 14),
		FieldHover = rgb(16, 23, 20),
		Text = rgb(238, 250, 244),
		SubText = rgb(168, 194, 182),
		Muted = rgb(126, 150, 140),
		ToggleOff = rgb(40, 54, 48),
	}),
	Light = preset({
		Dark = false,
		Accent = rgb(0, 122, 255),
		Accent2 = rgb(88, 86, 214),
		Background = rgb(242, 242, 247),
		BackgroundTransparency = 0.02,
		Sidebar = rgb(0, 0, 0),
		SidebarTransparency = 0.975,
		Card = rgb(255, 255, 255),
		CardTransparency = 0.05,
		Elevated = rgb(248, 248, 252),
		Tile = rgb(244, 244, 248),
		TileHover = rgb(234, 234, 240),
		TileTransparency = 0,
		Field = rgb(230, 230, 236),
		FieldHover = rgb(222, 222, 230),
		Stroke = rgb(0, 0, 0),
		StrokeTransparency = 0.9,
		Divider = rgb(0, 0, 0),
		DividerTransparency = 0.92,
		Text = rgb(22, 22, 26),
		SubText = rgb(98, 98, 108),
		Muted = rgb(150, 150, 160),
		ToggleOff = rgb(212, 212, 220),
		ShadowTransparency = 0.72,
		GlowTransparency = 0.9,
		OverlayTransparency = 0.6,
		NoiseTransparency = 0.98,
	}),
}
Theme.Order = { "Midnight", "Ocean", "Graphite", "Aurora", "Sunset", "Emerald", "Light" }

Theme.Name = "Midnight"
Theme.Current = table.clone(Theme.Presets.Midnight)
Theme.AccentOverride = nil
Theme.Overrides = {}
Theme.Changed = Signal.new()

local bindings = {} -- [Instance] = { [property] = key }
local destroyHooks = {}

function Theme.Font(weight)
	local family = Theme.Fonts[Theme.FontFamily] or Theme.Fonts.Gotham
	local enumWeight = Enum.FontWeight[weight or "Regular"] or Enum.FontWeight.Regular
	return Font.new(family, enumWeight, Enum.FontStyle.Normal)
end

function Theme.Mono(weight)
	return Font.new(Theme.Fonts.Mono, Enum.FontWeight[weight or "Regular"] or Enum.FontWeight.Regular)
end

function Theme.Resolve(key)
	if type(key) == "function" then
		return key(Theme.Current)
	elseif type(key) == "string" then
		if string.sub(key, 1, 1) == "@" then
			return Theme.Font(string.sub(key, 2))
		end
		return Theme.Current[key]
	end
	return key
end

function Theme.Get(key)
	return Theme.Current[key]
end

-- Accent gradient used across the library
function Theme.AccentSequence(theme)
	theme = theme or Theme.Current
	return ColorSequence.new(theme.Accent, theme.Accent2)
end

local function apply(instance, map, animate)
	local tweenProps
	for property, key in pairs(map) do
		local value = Theme.Resolve(key)
		if value ~= nil then
			if animate and typeof(value) == "Color3" then
				tweenProps = tweenProps or {}
				tweenProps[property] = value
			else
				instance[property] = value
			end
		end
	end
	if tweenProps then
		Tween.Play(instance, tweenProps, Tween.Smooth, Enum.EasingStyle.Quad)
	end
end

-- Theme.Bind(instance, { BackgroundColor3 = "Card", TextColor3 = "Text", FontFace = "@Medium" })
function Theme.Bind(instance, map)
	local existing = bindings[instance]
	if existing then
		for property, key in pairs(map) do
			existing[property] = key
		end
	else
		bindings[instance] = table.clone(map)
		local ok, connection = pcall(function()
			return instance.Destroying:Connect(function()
				Theme.Unbind(instance)
			end)
		end)
		if ok then
			destroyHooks[instance] = connection
		end
	end
	local ok, err = pcall(apply, instance, map, false)
	if not ok then
		warn("[Bali] Theme bind failed: " .. tostring(err))
	end
	return instance
end

function Theme.Unbind(instance, property)
	if property then
		local map = bindings[instance]
		if map then
			map[property] = nil
		end
		return
	end
	bindings[instance] = nil
	local hook = destroyHooks[instance]
	if hook then
		destroyHooks[instance] = nil
		pcall(function()
			hook:Disconnect()
		end)
	end
end

local function refresh(animate)
	for instance, map in pairs(bindings) do
		local ok = pcall(apply, instance, map, animate)
		if not ok then
			bindings[instance] = nil
		end
	end
	Theme.Changed:Fire(Theme.Current)
end

function Theme.Set(name, animate)
	local source = Theme.Presets[name]
	if not source then
		warn("[Bali] Unknown theme: " .. tostring(name))
		return false
	end
	Theme.Name = name
	Theme.Current = table.clone(source)
	for key, value in pairs(Theme.Overrides) do
		Theme.Current[key] = value
	end
	if Theme.AccentOverride then
		Theme.Current.Accent = Theme.AccentOverride
		Theme.Current.Accent2 = Theme.AccentOverride:Lerp(source.Accent2, 0.45)
		Theme.Current.AccentHover = computeAccentHover(Theme.Current)
	end
	refresh(animate ~= false)
	return true
end

-- Registers (or replaces) a theme. Missing keys inherit from the dark base palette.
function Theme.Add(name, overrides)
	Theme.Presets[name] = preset(overrides or {})
	if not table.find(Theme.Order, name) then
		table.insert(Theme.Order, name)
	end
	return Theme.Presets[name]
end

function Theme.SetAccent(color, animate)
	Theme.AccentOverride = color
	local source = Theme.Presets[Theme.Name] or Base
	if color then
		Theme.Current.Accent = color
		Theme.Current.Accent2 = color:Lerp(source.Accent2, 0.45)
		Theme.Current.AccentHover = computeAccentHover(Theme.Current)
	else
		Theme.Current.Accent = source.Accent
		Theme.Current.Accent2 = source.Accent2
		Theme.Current.AccentHover = source.AccentHover or computeAccentHover(Theme.Current)
	end
	refresh(animate ~= false)
end

-- Live overrides of keys that survive theme switches (e.g. window transparency slider).
-- Pass nil to drop the override and restore the preset value.
function Theme.SetValue(key, value, animate)
	Theme.Overrides[key] = value
	if value == nil then
		local source = Theme.Presets[Theme.Name] or Base
		value = source[key]
	end
	Theme.Current[key] = value
	refresh(animate ~= false)
end

function Theme.SetFont(family)
	if not Theme.Fonts[family] then
		return false
	end
	Theme.FontFamily = family
	refresh(false)
	return true
end

return Theme
