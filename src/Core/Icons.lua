--[[
	Bali UI · Core/Icons
	Icon resolution: embedded Lucide atlas names, Roblox asset ids, or glyph fallbacks.
]]

local Assets = require("Core/Assets")
local Theme = require("Core/Theme")
local Create = require("Core/Create")

local Icons = {}

local glyphs = {
	check = "✓",
	x = "×",
	plus = "+",
	minus = "-",
	["chevron-right"] = "›",
	["chevron-left"] = "‹",
	["chevron-down"] = "›",
	["chevron-up"] = "›",
	search = "⌕",
	info = "i",
	["circle-check"] = "✓",
	["circle-x"] = "×",
	["triangle-alert"] = "!",
	["circle-alert"] = "!",
	["circle-help"] = "?",
	ellipsis = "•••",
	circle = "●",
}
local glyphRotation = { ["chevron-down"] = 90, ["chevron-up"] = -90 }

local function isAssetString(text)
	return string.find(text, "^rbxasset") ~= nil
		or string.find(text, "^rbxthumb") ~= nil
		or string.find(text, "^https?://") ~= nil
		or string.find(text, "^%d+$") ~= nil
end

-- Returns a descriptor table or nil when no icon was requested
function Icons.Resolve(icon)
	if icon == nil or icon == "" or icon == false then
		return nil
	end
	if type(icon) == "number" then
		return { Kind = "Asset", Image = "rbxassetid://" .. icon }
	end
	icon = tostring(icon)
	if isAssetString(icon) then
		if string.find(icon, "^%d+$") then
			icon = "rbxassetid://" .. icon
		end
		return { Kind = "Asset", Image = icon }
	end
	local key = string.lower(icon)
	local cell = Assets.Data.Icons[key]
	if cell and Assets.Available and Assets.Images.Atlas then
		local size = Assets.Data.Atlas.Cell
		return {
			Kind = "Atlas",
			Image = Assets.Images.Atlas,
			Offset = Vector2.new(cell[1], cell[2]),
			Size = Vector2.new(size, size),
		}
	end
	return {
		Kind = "Glyph",
		Text = glyphs[key] or string.upper(string.sub(icon, 1, 1)),
		Rotation = glyphRotation[key] or 0,
	}
end

function Icons.Exists(name)
	return type(name) == "string" and Assets.Data.Icons[string.lower(name)] ~= nil
end

function Icons.List()
	local names = {}
	for name in pairs(Assets.Data.Icons) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function colorProperty(instance)
	return instance:IsA("TextLabel") and "TextColor3" or "ImageColor3"
end

-- Icons.Create(icon, { Size, Position, AnchorPoint, Color = "SubText" | Color3, Transparency, ZIndex, Parent, Name })
function Icons.Create(icon, props)
	props = props or {}
	local descriptor = Icons.Resolve(icon)
	if not descriptor then
		return nil
	end

	local size = props.Size or UDim2.fromOffset(16, 16)
	local instance
	if descriptor.Kind == "Glyph" then
		instance = Create.New("TextLabel", {
			Name = props.Name or "Icon",
			Size = size,
			Text = descriptor.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextScaled = true,
			Rotation = descriptor.Rotation,
			TextTransparency = props.Transparency or 0,
			Font = "Bold",
		})
	else
		instance = Create.New("ImageLabel", {
			Name = props.Name or "Icon",
			Size = size,
			Image = descriptor.Image,
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = props.Transparency or 0,
		})
		if descriptor.Kind == "Atlas" then
			instance.ImageRectOffset = descriptor.Offset
			instance.ImageRectSize = descriptor.Size
		end
	end

	if props.Position then
		instance.Position = props.Position
	end
	if props.AnchorPoint then
		instance.AnchorPoint = props.AnchorPoint
	end
	if props.ZIndex then
		instance.ZIndex = props.ZIndex
	end
	if props.LayoutOrder then
		instance.LayoutOrder = props.LayoutOrder
	end

	local color = props.Color or "Text"
	if typeof(color) == "Color3" then
		instance[colorProperty(instance)] = color
	else
		Theme.Bind(instance, { [colorProperty(instance)] = color })
	end

	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

-- Swaps the icon of an existing icon instance (keeps size/colour)
function Icons.Set(instance, icon)
	if not instance then
		return
	end
	local descriptor = Icons.Resolve(icon)
	if instance:IsA("TextLabel") then
		instance.Text = descriptor and (descriptor.Text or string.upper(string.sub(tostring(icon), 1, 1))) or ""
		instance.Rotation = descriptor and descriptor.Rotation or 0
		return
	end
	if not descriptor or descriptor.Kind == "Glyph" then
		instance.Image = ""
		return
	end
	instance.Image = descriptor.Image
	if descriptor.Kind == "Atlas" then
		instance.ImageRectOffset = descriptor.Offset
		instance.ImageRectSize = descriptor.Size
	else
		instance.ImageRectOffset = Vector2.zero
		instance.ImageRectSize = Vector2.zero
	end
end

-- Rebinds the colour of an icon to another theme key (or a Color3)
function Icons.SetColor(instance, color, animate)
	if not instance then
		return
	end
	local property = colorProperty(instance)
	if typeof(color) == "Color3" then
		Theme.Unbind(instance, property)
		instance[property] = color
		return
	end
	Theme.Bind(instance, { [property] = color })
end

function Icons.ColorProperty(instance)
	return colorProperty(instance)
end

function Icons.TransparencyProperty(instance)
	return instance:IsA("TextLabel") and "TextTransparency" or "ImageTransparency"
end

return Icons
