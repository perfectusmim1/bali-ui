--[[
	Lumina UI · Elements/Static
	Display elements: Label, Paragraph, Divider, Header, CodeBlock, Image, ProfileCard.
]]

local Services = require("Core/Services")
local Util = require("Core/Util")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Base = require("Elements/Base")

local Static = {}

-- ─── Label ───────────────────────────────────────────────────────────────────

local Label = {}
function Label.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Title")
	local element = Base.New("Label", parent, opts, ctx)

	local rowOpts = table.clone(opts)
	if rowOpts.IconBadge == nil then
		rowOpts.IconBadge = false
	end

	local row = Base.Row(parent, rowOpts, 0)
	element:BindUI(row)

	Create.List(row.Right, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		HAlign = Enum.HorizontalAlignment.Right,
		Gap = 6,
	})

	local valueText = opts.Value ~= nil and tostring(opts.Value) or (opts.Text ~= nil and tostring(opts.Text) or "")
	element.Value = valueText

	local valueLabel = Create.Text({
		Name = "Value",
		Text = valueText,
		Font = "Medium",
		TextSize = 12,
		Color = opts.ValueColor or "SubText",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 1,
		Visible = valueText ~= "",
		Parent = row.Right,
	})

	local badgeObj = nil
	if opts.Badge then
		local bText, bColor
		if type(opts.Badge) == "table" then
			bText = opts.Badge.Text or opts.Badge[1] or ""
			bColor = opts.Badge.Color or opts.Badge[2] or "Accent"
		else
			bText = tostring(opts.Badge)
			bColor = opts.BadgeColor or "Accent"
		end
		badgeObj = Base.Badge(row.Right, bText, bColor)
		badgeObj.Frame.LayoutOrder = 2
	end

	local copyBtn = nil
	local copyIcon = nil
	if opts.Copyable then
		copyBtn = Create.New("TextButton", {
			Name = "CopyButton",
			Size = UDim2.fromOffset(24, 24),
			Theme = { BackgroundColor3 = "Field" },
			Corner = 6,
			Stroke = {
				Theme = { Color = "Stroke" },
				Transparency = 0.86,
				Thickness = 1,
			},
			LayoutOrder = 3,
			ZIndex = 4,
			Parent = row.Right,
		})
		copyIcon = Icons.Create("copy", {
			Size = UDim2.fromOffset(13, 13),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = "SubText",
			Parent = copyBtn,
		})
		element.Maid:Give(Transition.Hover(copyBtn, copyBtn, "Field", "TileHover"))

		local copyToken = 0
		element.Maid:Give(copyBtn.Activated:Connect(function(inputObj)
			if element.Disabled or element.Locked then
				return
			end
			local toCopy = opts.CopyValue
			if toCopy == nil then
				toCopy = (element.Value ~= "" and element.Value) or element.Title
			end
			Util.SetClipboard(tostring(toCopy or ""))
			Transition.Ripple(copyBtn, inputObj, "Accent")

			copyToken += 1
			local myToken = copyToken
			if copyIcon then
				Icons.Set(copyIcon, "check")
				Icons.SetColor(copyIcon, "Success")
			end
			task.delay(1.5, function()
				if element._destroyed or copyToken ~= myToken then
					return
				end
				if copyIcon then
					Icons.Set(copyIcon, "copy")
					Icons.SetColor(copyIcon, "SubText")
				end
			end)
		end))
	end

	function element:SetText(s)
		self:SetTitle(s)
	end

	function element:SetValue(v)
		local text = v ~= nil and tostring(v) or ""
		self.Value = text
		valueLabel.Text = text
		valueLabel.Visible = (text ~= "")
	end

	function element:Get()
		return self.Value
	end

	function element:SetBadge(text, colorKey)
		if text == nil or text == "" then
			if badgeObj then
				badgeObj.Frame.Visible = false
			end
			return
		end
		if not badgeObj then
			badgeObj = Base.Badge(row.Right, text, colorKey or "Accent")
			badgeObj.Frame.LayoutOrder = 2
		else
			badgeObj.Frame.Visible = true
			badgeObj:SetText(text)
			if colorKey then
				badgeObj:SetColor(colorKey)
			end
		end
	end

	return element
end

-- ─── Paragraph ───────────────────────────────────────────────────────────────

local Paragraph = {}
function Paragraph.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Title")
	local element = Base.New("Paragraph", parent, opts, ctx)

	local card = Base.Card(parent, { Padding = 0 })
	local accentColor = opts.Color or "Accent"
	local showBar = (opts.AccentBar ~= false)

	if showBar then
		local bar = Create.New("Frame", {
			Name = "AccentBar",
			Size = UDim2.new(0, 3, 1, -18),
			Position = UDim2.fromOffset(10, 9),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Corner = UDim.new(1, 0),
			ZIndex = 3,
			Parent = card.Frame,
		})
		if typeof(accentColor) == "Color3" then
			bar.BackgroundColor3 = accentColor
		elseif accentColor ~= "Accent" then
			Theme.Bind(bar, { BackgroundColor3 = accentColor })
		else
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90
			grad.Color = Theme.AccentSequence()
			grad.Parent = bar
			element.Maid:Give(Theme.Changed:Connect(function(t)
				grad.Color = Theme.AccentSequence(t)
			end))
		end
	end

	local body = Create.New("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 12, 12, 12, showBar and 22 or 12 },
		ZIndex = 2,
		Parent = card.Frame,
	})

	Create.List(body, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 6,
	})

	local titleText = tostring(opts.Title or "")
	local contentText = tostring(opts.Content or opts.Description or opts.Desc or "")

	local header = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Visible = (titleText ~= "" or (opts.Icon ~= nil and opts.Icon ~= "")),
		Parent = body,
	})

	Create.List(header, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 10,
	})

	local iconWidth = 0
	if opts.Icon and opts.Icon ~= "" and opts.Icon ~= false then
		local badge = Base.IconBadge(header, opts.Icon, accentColor)
		badge.Frame.LayoutOrder = 1
		iconWidth = 30
	end

	local titleLabel = Create.Text({
		Name = "Title",
		Text = titleText,
		Font = "SemiBold",
		TextSize = 14,
		Color = "Text",
		TextWrapped = true,
		Size = UDim2.new(1, iconWidth > 0 and -(iconWidth + 10) or 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Visible = titleText ~= "",
		Parent = header,
	})

	local contentLabel = Create.Text({
		Name = "Content",
		Text = contentText,
		Font = "Regular",
		TextSize = 12,
		Color = "SubText",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Visible = contentText ~= "",
		Parent = body,
	})

	local tagsRow = Create.New("Frame", {
		Name = "Tags",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Visible = false,
		Parent = body,
	})

	Create.List(tagsRow, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		Wraps = true,
	})

	local function buildTags(tags)
		for _, child in ipairs(tagsRow:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if type(tags) ~= "table" or #tags == 0 then
			tagsRow.Visible = false
			return
		end
		tagsRow.Visible = true
		for idx, tag in ipairs(tags) do
			local tText, tColor
			if type(tag) == "table" then
				tText = tag.Text or tag[1] or ""
				tColor = tag.Color or tag[2] or "Accent"
			else
				tText = tostring(tag)
				tColor = "Accent"
			end
			local b = Base.Badge(tagsRow, tText, tColor)
			b.Frame.LayoutOrder = idx
		end
	end

	buildTags(opts.Tags)

	card.TitleLabel = titleLabel
	card.DescLabel = contentLabel

	function card:SetTitle(s)
		local txt = tostring(s or "")
		titleLabel.Text = txt
		titleLabel.Visible = (txt ~= "")
		header.Visible = (txt ~= "" or iconWidth > 0)
	end

	function card:SetDesc(s)
		local txt = tostring(s or "")
		contentLabel.Text = txt
		contentLabel.Visible = (txt ~= "")
	end

	element:BindUI(card)

	function element:SetContent(s)
		self:SetDesc(s)
	end

	function element:SetTags(tags)
		buildTags(tags)
	end

	return element
end

-- ─── Divider ─────────────────────────────────────────────────────────────────

local Divider = {}
function Divider.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Title")
	local element = Base.New("Divider", parent, opts, ctx)

	local labelText = tostring(opts.Title or opts.Text or "")
	local frame = Create.New("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { opts.Spacing or 4, 0, opts.Spacing or 4, 0 },
		Parent = parent,
	})

	Create.List(frame, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 8,
	})

	local leftLine = Create.New("Frame", {
		Name = "LeftLine",
		Size = labelText ~= "" and UDim2.new(0, 14, 0, 1) or UDim2.new(1, 0, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		LayoutOrder = 1,
		Parent = frame,
	})

	local titleLabel = Create.Text({
		Name = "Title",
		Text = labelText,
		Font = "SemiBold",
		TextSize = 11,
		Color = "Muted",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		Visible = labelText ~= "",
		Parent = frame,
	})

	local rightLine = Create.New("Frame", {
		Name = "RightLine",
		Size = UDim2.new(1, -30, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		LayoutOrder = 3,
		Visible = labelText ~= "",
		Parent = frame,
	})

	local function syncLines()
		local hasText = titleLabel.Text ~= ""
		titleLabel.Visible = hasText
		rightLine.Visible = hasText
		if hasText then
			leftLine.Size = UDim2.new(0, 14, 0, 1)
			local labelW = math.ceil(titleLabel.AbsoluteSize.X)
			rightLine.Size = UDim2.new(1, -(14 + 16 + labelW), 0, 1)
		else
			leftLine.Size = UDim2.new(1, 0, 0, 1)
		end
	end

	element.Maid:Give(titleLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncLines))
	task.defer(syncLines)

	element:BindUI({
		Frame = frame,
		TitleLabel = titleLabel,
		SetTitle = function(_, s)
			titleLabel.Text = tostring(s or "")
			syncLines()
		end,
	})

	return element
end

-- ─── Header ──────────────────────────────────────────────────────────────────

local Header = {}
function Header.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Title")
	local element = Base.New("Header", parent, opts, ctx)

	local uppercase = (opts.Uppercase ~= false)
	local rawTitle = tostring(opts.Title or "")

	local frame = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 6, 2, 2, 2 },
		Parent = parent,
	})

	Create.List(frame, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 6,
	})

	local iconWidth = 0
	if opts.Icon and opts.Icon ~= "" and opts.Icon ~= false then
		Icons.Create(opts.Icon, {
			Size = UDim2.fromOffset(14, 14),
			Color = opts.IconColor or "Accent",
			LayoutOrder = 1,
			Parent = frame,
		})
		iconWidth = 14
	end

	local titleLabel = Create.Text({
		Name = "Title",
		Text = uppercase and string.upper(rawTitle) or rawTitle,
		Font = "Bold",
		TextSize = 11,
		Color = opts.Color or "SubText",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = frame,
	})

	if opts.Badge then
		local bText, bColor
		if type(opts.Badge) == "table" then
			bText = opts.Badge.Text or opts.Badge[1] or ""
			bColor = opts.Badge.Color or opts.Badge[2] or "Accent"
		else
			bText = tostring(opts.Badge)
			bColor = "Accent"
		end
		local b = Base.Badge(frame, bText, bColor)
		b.Frame.LayoutOrder = 3
	end

	element:BindUI({
		Frame = frame,
		TitleLabel = titleLabel,
		SetTitle = function(_, s)
			local text = tostring(s or "")
			titleLabel.Text = uppercase and string.upper(text) or text
		end,
	})

	return element
end

-- ─── CodeBlock ───────────────────────────────────────────────────────────────

local CodeBlock = {}
function CodeBlock.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Code")
	local element = Base.New("CodeBlock", parent, opts, ctx)

	local currentCode = tostring(opts.Code or opts.Text or opts.Content or "")
	element.Value = currentCode

	local card = Base.Card(parent, {
		SurfaceKey = "Field",
		SurfaceTransparency = 0,
		Padding = 0,
	})
	card.Frame.ClipsDescendants = true

	local body = Create.New("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card.Frame,
	})

	Create.List(body, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 0,
	})

	local header = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		Padding = { 0, 8, 0, 12 },
		LayoutOrder = 1,
		Parent = body,
	})

	local headerLeft = Create.New("Frame", {
		Name = "Left",
		Size = UDim2.new(1, -84, 1, 0),
		BackgroundTransparency = 1,
		Parent = header,
	})

	Create.List(headerLeft, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 6,
	})

	Icons.Create(opts.Icon or "code", {
		Size = UDim2.fromOffset(14, 14),
		Color = "Accent",
		LayoutOrder = 1,
		Parent = headerLeft,
	})

	local titleText = tostring(opts.Title or opts.Language or "Code")
	local titleLabel = Create.Text({
		Name = "Title",
		Text = titleText,
		Font = "Medium",
		TextSize = 12,
		Color = "SubText",
		Size = UDim2.new(1, -22, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = headerLeft,
	})

	local copyBtn = Create.New("TextButton", {
		Name = "CopyButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Theme = { BackgroundColor3 = "Tile" },
		Corner = 6,
		Padding = { 0, 8, 0, 8 },
		Stroke = {
			Theme = { Color = "Stroke" },
			Transparency = 0.86,
			Thickness = 1,
		},
		ZIndex = 4,
		Parent = header,
	})

	Create.List(copyBtn, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 5,
	})

	local copyIcon = Icons.Create("copy", {
		Size = UDim2.fromOffset(12, 12),
		Color = "SubText",
		LayoutOrder = 1,
		Parent = copyBtn,
	})

	local copyLabel = Create.Text({
		Name = "Label",
		Text = "Copy",
		Font = "Medium",
		TextSize = 11,
		Color = "SubText",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		Parent = copyBtn,
	})

	element.Maid:Give(Transition.Hover(copyBtn, copyBtn, "Tile", "TileHover"))

	local sep = Create.New("Frame", {
		Name = "Separator",
		Size = UDim2.new(1, 0, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		LayoutOrder = 2,
		Parent = body,
	})

	local scroll = Create.New("ScrollingFrame", {
		Name = "CodeScroll",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		BackgroundTransparency = 1,
		Theme = { ScrollBarImageColor3 = "Muted" },
		LayoutOrder = 3,
		Parent = body,
	})

	local maxConstraint = Instance.new("UISizeConstraint")
	maxConstraint.MaxSize = Vector2.new(99999, opts.MaxHeight or 180)
	maxConstraint.Parent = scroll

	local codeRow = Create.New("Frame", {
		Name = "CodeRow",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Padding = { 10, 12, 10, 12 },
		Parent = scroll,
	})

	Create.List(codeRow, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Top,
		Gap = 10,
	})

	local showLines = (opts.LineNumbers ~= false)
	local lineCol = Create.New("TextLabel", {
		Name = "LineNumbers",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Text = "1",
		TextSize = 12,
		FontFace = Theme.Mono("Regular"),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		Theme = { TextColor3 = "Muted" },
		LayoutOrder = 1,
		Visible = showLines,
		Parent = codeRow,
	})

	local codeLabel = Create.New("TextLabel", {
		Name = "Code",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Text = currentCode,
		TextSize = 12,
		FontFace = Theme.Mono("Regular"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = opts.Wrap == true,
		RichText = false,
		Theme = { TextColor3 = "Text" },
		LayoutOrder = 2,
		Parent = codeRow,
	})

	local function refreshCode(src)
		currentCode = tostring(src or "")
		element.Value = currentCode
		codeLabel.Text = currentCode
		if showLines then
			local lineCount = select(2, string.gsub(currentCode, "\n", "")) + 1
			local nums = table.create(lineCount)
			for i = 1, lineCount do
				nums[i] = tostring(i)
			end
			lineCol.Text = table.concat(nums, "\n")
		end
	end

	refreshCode(currentCode)

	local copyToken = 0
	element.Maid:Give(copyBtn.Activated:Connect(function(inputObj)
		if element.Disabled or element.Locked then
			return
		end
		Util.SetClipboard(currentCode)
		Transition.Ripple(copyBtn, inputObj, "Accent")

		copyToken += 1
		local myToken = copyToken
		if copyIcon then
			Icons.Set(copyIcon, "check")
			Icons.SetColor(copyIcon, "Success")
		end
		Theme.Bind(copyLabel, { TextColor3 = "Success" })
		copyLabel.Text = "Copied!"

		task.delay(1.5, function()
			if element._destroyed or copyToken ~= myToken then
				return
			end
			if copyIcon then
				Icons.Set(copyIcon, "copy")
				Icons.SetColor(copyIcon, "SubText")
			end
			Theme.Bind(copyLabel, { TextColor3 = "SubText" })
			copyLabel.Text = "Copy"
		end)
	end))

	card.TitleLabel = titleLabel
	function card:SetTitle(s)
		titleLabel.Text = tostring(s or "")
	end

	element:BindUI(card)

	function element:SetCode(src)
		refreshCode(src)
	end
	element.SetText = element.SetCode

	function element:Get()
		return currentCode
	end

	return element
end

-- ─── Image ───────────────────────────────────────────────────────────────────

local Image = {}
function Image.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Image")
	local element = Base.New("Image", parent, opts, ctx)

	local card = Base.Card(parent, {
		Padding = 0,
		Corner = opts.Corner or 10,
	})
	card.Frame.ClipsDescendants = true

	local defaultHeight = opts.Height or 150
	local imgLabel = Create.New("ImageLabel", {
		Name = "Picture",
		Size = UDim2.new(1, 0, 0, defaultHeight),
		BackgroundTransparency = 1,
		ScaleType = opts.ScaleType or Enum.ScaleType.Crop,
		Parent = card.Frame,
	})

	local fallbackIcon = Icons.Create("image", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = "Muted",
		Visible = false,
		Parent = imgLabel,
	})

	local function applyImage(source)
		local resolved = Icons.Resolve(source)
		if resolved and resolved.Kind == "Asset" then
			imgLabel.Image = resolved.Image
			imgLabel.ImageRectOffset = Vector2.zero
			imgLabel.ImageRectSize = Vector2.zero
			if fallbackIcon then
				fallbackIcon.Visible = false
			end
		elseif resolved and resolved.Kind == "Atlas" then
			imgLabel.Image = resolved.Image
			imgLabel.ImageRectOffset = resolved.Offset
			imgLabel.ImageRectSize = resolved.Size
			if fallbackIcon then
				fallbackIcon.Visible = false
			end
		else
			imgLabel.Image = ""
			if fallbackIcon then
				fallbackIcon.Visible = true
			end
		end
	end

	applyImage(opts.Image)

	if opts.AspectRatio and opts.AspectRatio > 0 then
		local ratio = opts.AspectRatio
		local function updateAspect()
			local w = card.Frame.AbsoluteSize.X
			if w > 0 then
				imgLabel.Size = UDim2.new(1, 0, 0, math.max(48, math.floor(w / ratio)))
			end
		end
		element.Maid:Give(card.Frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateAspect))
		task.defer(updateAspect)
	end

	local titleText = tostring(opts.Title or "")
	local captionText = tostring(opts.Caption or opts.Description or opts.Desc or "")

	local scrim = Create.New("Frame", {
		Name = "CaptionOverlay",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.25,
		Padding = { 22, 12, 10, 12 },
		Visible = (titleText ~= "" or captionText ~= ""),
		ZIndex = 3,
		Parent = imgLabel,
	})

	local scrimGrad = Instance.new("UIGradient")
	scrimGrad.Rotation = 90
	scrimGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0.35),
		NumberSequenceKeypoint.new(1, 0.08),
	})
	scrimGrad.Parent = scrim

	Create.List(scrim, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 2,
	})

	local titleLabel = Create.Text({
		Name = "Title",
		Text = titleText,
		Font = "SemiBold",
		TextSize = 13,
		TextColor3 = Color3.fromRGB(250, 250, 255),
		Theme = {},
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Visible = titleText ~= "",
		ZIndex = 4,
		Parent = scrim,
	})

	local captionLabel = Create.Text({
		Name = "Caption",
		Text = captionText,
		Font = "Regular",
		TextSize = 11,
		TextColor3 = Color3.fromRGB(210, 210, 222),
		Theme = {},
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Visible = captionText ~= "",
		ZIndex = 4,
		Parent = scrim,
	})

	local function refreshScrim()
		scrim.Visible = (titleLabel.Text ~= "" or captionLabel.Text ~= "")
	end

	card.TitleLabel = titleLabel
	card.DescLabel = captionLabel
	function card:SetTitle(s)
		local txt = tostring(s or "")
		titleLabel.Text = txt
		titleLabel.Visible = (txt ~= "")
		refreshScrim()
	end
	function card:SetDesc(s)
		local txt = tostring(s or "")
		captionLabel.Text = txt
		captionLabel.Visible = (txt ~= "")
		refreshScrim()
	end

	element:BindUI(card)

	function element:SetImage(src)
		applyImage(src)
	end

	function element:SetCaption(s)
		self:SetDesc(s)
	end

	return element
end

-- ─── ProfileCard ─────────────────────────────────────────────────────────────

local ProfileCard = {}
function ProfileCard.new(parent, opts, ctx)
	opts = Util.Options(opts, {}, "Title")
	local element = Base.New("ProfileCard", parent, opts, ctx)

	local localPlayer = Services.Players.LocalPlayer
	local userId = opts.UserId or (localPlayer and localPlayer.UserId) or 0
	local defaultTitle = localPlayer and ("Welcome Back, " .. localPlayer.DisplayName) or "Welcome Back"
	local defaultSub = localPlayer and ("@" .. localPlayer.Name) or "Guest"

	local titleText = tostring(opts.Title or defaultTitle)
	local subtitleText = tostring(opts.Subtitle or opts.Description or opts.Desc or defaultSub)
	local statusText = tostring(opts.Status or "Online")
	local statusColor = opts.StatusColor or "Success"

	element.Title = titleText
	element.Desc = subtitleText

	local card = Base.Card(parent, { Padding = 0 })
	card.Frame.ClipsDescendants = true

	if Assets.Get("Glow") then
		local glow = Create.New("ImageLabel", {
			Name = "Glow",
			Size = UDim2.fromOffset(180, 120),
			Position = UDim2.fromOffset(-36, -36),
			BackgroundTransparency = 1,
			Image = Assets.Get("Glow"),
			Theme = {
				ImageColor3 = "Accent",
				ImageTransparency = "GlowTransparency",
			},
			ZIndex = 1,
			Parent = card.Frame,
		})
	end

	local body = Create.New("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 12, 12, 12, 12 },
		ZIndex = 2,
		Parent = card.Frame,
	})

	Create.List(body, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 12,
	})

	local avatarWrap = Create.New("Frame", {
		Name = "Avatar",
		Size = UDim2.fromOffset(44, 44),
		Theme = { BackgroundColor3 = "Field" },
		Corner = UDim.new(1, 0),
		Stroke = {
			Theme = { Color = "Accent" },
			Transparency = 0.55,
			Thickness = 1.5,
		},
		LayoutOrder = 1,
		Parent = body,
	})

	local fallbackIcon = Icons.Create("user", {
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = "SubText",
		Parent = avatarWrap,
	})

	local avatarImg = Create.New("ImageLabel", {
		Name = "AvatarImage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Corner = UDim.new(1, 0),
		Visible = false,
		ZIndex = 2,
		Parent = avatarWrap,
	})

	local statusDot = Create.New("Frame", {
		Name = "StatusDot",
		Size = UDim2.fromOffset(10, 10),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Corner = UDim.new(1, 0),
		Theme = { BackgroundColor3 = statusColor },
		Stroke = {
			Theme = { Color = "Tile" },
			Transparency = 0,
			Thickness = 2,
		},
		ZIndex = 4,
		Parent = avatarWrap,
	})
	element.Maid:Give(Transition.Pulse(statusDot, "BackgroundTransparency", 0, 0.45, 1.8))

	if userId and userId > 0 then
		task.spawn(function()
			local ok, thumbUrl, isReady = pcall(function()
				return Services.Players:GetUserThumbnailAsync(
					userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
			end)
			if element._destroyed or not avatarImg.Parent then
				return
			end
			if ok and type(thumbUrl) == "string" and thumbUrl ~= "" then
				avatarImg.Image = thumbUrl
				avatarImg.Visible = true
				if fallbackIcon then
					fallbackIcon.Visible = false
				end
			end
		end)
	end

	local infoCol = Create.New("Frame", {
		Name = "Info",
		Size = UDim2.new(1, -(44 + 12), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = body,
	})

	Create.List(infoCol, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 3,
	})

	local titleLabel = Create.Text({
		Name = "Title",
		Text = titleText,
		Font = "SemiBold",
		TextSize = 14,
		Color = "Text",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = infoCol,
	})

	local subLabel = Create.Text({
		Name = "Subtitle",
		Text = subtitleText,
		Font = "Regular",
		TextSize = 12,
		Color = "SubText",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Visible = subtitleText ~= "",
		Parent = infoCol,
	})

	local badgeWrap = Create.New("Frame", {
		Name = "StatusWrap",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 2, 0, 0, 0 },
		LayoutOrder = 3,
		Visible = statusText ~= "",
		Parent = infoCol,
	})

	local statusBadge = Base.Badge(badgeWrap, statusText, statusColor)

	if opts.Button then
		local btnOpts = type(opts.Button) == "table" and opts.Button or { Title = tostring(opts.Button) }
		local pillBtn = Create.New("TextButton", {
			Name = "ActionButton",
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Theme = { BackgroundColor3 = "Field" },
			Corner = UDim.new(1, 0),
			Padding = { 0, 12, 0, 12 },
			Stroke = {
				Theme = { Color = "Stroke" },
				Transparency = 0.84,
				Thickness = 1,
			},
			LayoutOrder = 3,
			ZIndex = 4,
			Parent = body,
		})

		Create.List(pillBtn, {
			Direction = Enum.FillDirection.Horizontal,
			VAlign = Enum.VerticalAlignment.Center,
			Gap = 5,
		})

		if btnOpts.Icon then
			Icons.Create(btnOpts.Icon, {
				Size = UDim2.fromOffset(13, 13),
				Color = "Text",
				LayoutOrder = 1,
				Parent = pillBtn,
			})
		end

		Create.Text({
			Name = "Label",
			Text = tostring(btnOpts.Title or "Action"),
			Font = "Medium",
			TextSize = 12,
			Color = "Text",
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = 2,
			Parent = pillBtn,
		})

		element.Maid:Give(Transition.Hover(pillBtn, pillBtn, "Field", "TileHover"))
		element.Maid:Give(pillBtn.Activated:Connect(function(inputObj)
			if element.Disabled or element.Locked then
				return
			end
			Transition.Ripple(pillBtn, inputObj, "Accent")
			if type(btnOpts.Callback) == "function" then
				Util.Spawn(btnOpts.Callback)
			end
		end))

		local function syncInfoWidth()
			local btnW = math.ceil(pillBtn.AbsoluteSize.X)
			infoCol.Size = UDim2.new(1, -(44 + 12 + btnW + 12), 0, 0)
		end
		element.Maid:Give(pillBtn:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncInfoWidth))
		task.defer(syncInfoWidth)
	end

	card.TitleLabel = titleLabel
	card.DescLabel = subLabel
	function card:SetTitle(s)
		local txt = tostring(s or "")
		titleLabel.Text = txt
		titleLabel.Visible = (txt ~= "")
	end
	function card:SetDesc(s)
		local txt = tostring(s or "")
		subLabel.Text = txt
		subLabel.Visible = (txt ~= "")
	end

	element:BindUI(card)

	function element:SetStatus(text, colorKey)
		local txt = tostring(text or "")
		statusBadge:SetText(txt)
		badgeWrap.Visible = (txt ~= "")
		if colorKey then
			statusBadge:SetColor(colorKey)
			Theme.Bind(statusDot, { BackgroundColor3 = colorKey })
		end
	end

	return element
end

Static.Label = Label
Static.Paragraph = Paragraph
Static.Divider = Divider
Static.Header = Header
Static.CodeBlock = CodeBlock
Static.Image = Image
Static.ProfileCard = ProfileCard

return Static
