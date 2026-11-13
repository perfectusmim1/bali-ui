--[[
	Bali UI · Core/Create
	Declarative instance factory with theme bindings and layout shorthands.

	New("Frame", {
		Size = ..., Parent = ...,
		Theme = { BackgroundColor3 = "Card" },   -- live theme binding
		Font = "Medium",                         -- text: binds FontFace to the active family
		Corner = 10,                             -- UICorner radius (or UDim)
		Padding = 12 | { top, right, bottom, left },
		Stroke = { Theme = { Color = "Stroke" }, Transparency = 0.9, Thickness = 1 },
		Children = { ... },
	})
]]

local Theme = require("Core/Theme")

local Create = {}

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }
local IMAGE_CLASSES = { ImageLabel = true, ImageButton = true }
local GUI_CLASSES = {
	Frame = true,
	ScrollingFrame = true,
	CanvasGroup = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ViewportFrame = true,
}

local SPECIAL = { Theme = true, Font = true, Corner = true, Padding = true, Stroke = true, Children = true, Parent = true }

local function applyDefaults(instance, className)
	if GUI_CLASSES[className] then
		instance.BorderSizePixel = 0
	end
	if TEXT_CLASSES[className] then
		instance.BackgroundTransparency = 1
		instance.Text = ""
		instance.TextSize = 13
		instance.TextXAlignment = Enum.TextXAlignment.Left
		instance.TextColor3 = Theme.Current.Text
		instance.FontFace = Theme.Font("Regular")
		if className == "TextButton" then
			instance.AutoButtonColor = false
		elseif className == "TextBox" then
			instance.ClearTextOnFocus = false
		end
	elseif IMAGE_CLASSES[className] then
		instance.BackgroundTransparency = 1
		if className == "ImageButton" then
			instance.AutoButtonColor = false
		end
	end
end

function Create.Corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

function Create.Padding(parent, padding)
	local object = Instance.new("UIPadding")
	local top, right, bottom, left
	if type(padding) == "number" then
		top, right, bottom, left = padding, padding, padding, padding
	else
		top = padding[1] or 0
		right = padding[2] or top
		bottom = padding[3] or top
		left = padding[4] or right
	end
	object.PaddingTop = UDim.new(0, top)
	object.PaddingRight = UDim.new(0, right)
	object.PaddingBottom = UDim.new(0, bottom)
	object.PaddingLeft = UDim.new(0, left)
	object.Parent = parent
	return object
end

function Create.Stroke(parent, options)
	options = options or {}
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = options.Thickness or 1
	stroke.Transparency = options.Transparency or Theme.Current.StrokeTransparency
	stroke.Color = options.Color or Theme.Current.Stroke
	if options.Theme then
		Theme.Bind(stroke, options.Theme)
	end
	stroke.Parent = parent
	return stroke
end

-- Glass edge: a stroke whose top edge catches light and fades towards the bottom
function Create.GlassStroke(parent, strength)
	local stroke = Create.Stroke(parent, {
		Theme = {
			Color = "Stroke",
			Transparency = function(theme)
				return math.max(theme.StrokeTransparency - (strength or 0.04), 0)
			end,
		},
	})
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	gradient.Parent = stroke
	return stroke
end

function Create.List(parent, options)
	options = options or {}
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirection = options.Direction or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, options.Gap or 0)
	layout.HorizontalAlignment = options.HAlign or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = options.VAlign or Enum.VerticalAlignment.Top
	if options.Wraps then
		layout.Wraps = true
	end
	layout.Parent = parent
	return layout
end

function Create.New(className, props)
	local instance = Instance.new(className)
	applyDefaults(instance, className)
	props = props or {}

	for key, value in pairs(props) do
		if not SPECIAL[key] then
			instance[key] = value
		end
	end

	-- Ensure colored TextButtons default to opaque unless caller overrides transparency
	if className == "TextButton" and props.BackgroundTransparency == nil and (not props.Theme or props.Theme.BackgroundTransparency == nil) then
		if props.BackgroundColor3 ~= nil or (props.Theme and props.Theme.BackgroundColor3 ~= nil) then
			instance.BackgroundTransparency = 0
		end
	end

	if props.Font then
		Theme.Bind(instance, { FontFace = "@" .. props.Font })
	end
	if props.Theme then
		Theme.Bind(instance, props.Theme)
	end
	if props.Corner then
		Create.Corner(instance, props.Corner)
	end
	if props.Padding then
		Create.Padding(instance, props.Padding)
	end
	if props.Stroke then
		Create.Stroke(instance, props.Stroke)
	end
	if props.Children then
		for _, child in ipairs(props.Children) do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

-- Text shorthand: { Class = "TextLabel", Color = "SubText", Font = "Medium", ... }
function Create.Text(props)
	local className = props.Class or "TextLabel"
	props.Class = nil
	props.Theme = props.Theme or {}
	if props.Theme.TextColor3 == nil then
		props.Theme.TextColor3 = props.Color or "Text"
	end
	props.Color = nil
	props.Font = props.Font or "Regular"
	return Create.New(className, props)
end

return Create
