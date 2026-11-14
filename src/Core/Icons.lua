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
	if instance:IsA("TextLabel") then
		return "TextColor3"
	elseif instance:IsA("Frame") then
		return "BackgroundColor3"
	end
	return "ImageColor3"
end

-- Icons.Create(icon, { Size, Position, AnchorPoint, Color = "SubText" | Color3, Transparency, ZIndex, Parent, Name })
function Icons.Create(icon, props)
	props = props or {}
	local iconKey = type(icon) == "string" and string.lower(icon) or nil
	local descriptor = Icons.Resolve(icon)
	if not descriptor then
		return nil
	end

	local size = props.Size or UDim2.fromOffset(16, 16)
	local instance
	local barChild = nil
	if iconKey == "minus" then
		-- Crisp 2px vector bar avoids blurry/faint 1px atlas scaling on compact action buttons
		instance = Create.New("Frame", {
			Name = props.Name or "Icon",
			Size = size,
			BackgroundTransparency = 1,
		})
		local barW = math.max(9, math.floor((size.X.Offset or 14) * 0.72))
		barChild = Create.New("Frame", {
			Name = "MinusBar",
			Size = UDim2.fromOffset(barW, 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = props.Transparency or 0,
			Corner = 99,
			Parent = instance,
		})
	elseif descriptor.Kind == "Glyph" then
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
	local colorTarget = barChild or instance
	if typeof(color) == "Color3" then
		colorTarget[colorProperty(colorTarget)] = color
	else
		Theme.Bind(colorTarget, { [colorProperty(colorTarget)] = color })
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
	local target = instance:FindFirstChild("MinusBar") or instance
	local property = colorProperty(target)
	if typeof(color) == "Color3" then
		Theme.Unbind(target, property)
		target[property] = color
		return
	end
	Theme.Bind(target, { [property] = color })
end

function Icons.ColorProperty(instance)
	return colorProperty(instance)
end

function Icons.TransparencyProperty(instance)
	if instance:IsA("TextLabel") then
		return "TextTransparency"
	elseif instance:IsA("Frame") then
		return "BackgroundTransparency"
	end
	return "ImageTransparency"
end

return Icons
