--[[
	Bali UI · Elements/Input
	Obsidian glass text input with focus accent glow, numeric filtering,
	password mask toggle (eye/eye-off), clear button, and Live/Finished modes.
]]

local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Base = require("Elements/Base")

local Input = {}

local BULLET = "•"

local function splitUtf8(str)
	local chars = {}
	local ok = pcall(function()
		for _, cp in utf8.codes(str) do
			table.insert(chars, utf8.char(cp))
		end
	end)
	if not ok then
		for i = 1, #str do
			chars[i] = string.sub(str, i, i)
		end
	end
	return chars
end

local function countCharsBeforeByte(str, bytePos)
	if not bytePos or bytePos <= 1 then
		return 0
	end
	local count = 0
	local ok = pcall(function()
		for pos in utf8.codes(str) do
			if pos < bytePos then
				count += 1
			else
				break
			end
		end
	end)
	if not ok then
		return math.max(0, bytePos - 1)
	end
	return count
end

local function reconcileMasked(oldReal, displayedText, cursorBytePos)
	if displayedText == "" then
		return ""
	end
	local realChars = splitUtf8(oldReal)
	local dispChars = splitUtf8(displayedText)

	local p = 0
	while p < #dispChars and dispChars[p + 1] == BULLET do
		p += 1
	end

	local s = 0
	while (#dispChars - s) > p and dispChars[#dispChars - s] == BULLET do
		s += 1
	end

	if p + s == #dispChars then
		if #dispChars == #realChars then
			return oldReal
		elseif #dispChars < #realChars then
			local delCount = #realChars - #dispChars
			local k = countCharsBeforeByte(displayedText, cursorBytePos)
			if cursorBytePos == nil or cursorBytePos < 0 then
				k = #dispChars
			end
			k = Util.Clamp(k, 0, #dispChars)
			local head = k > 0 and table.concat(realChars, "", 1, k) or ""
			local tailStart = k + delCount + 1
			local tail = tailStart <= #realChars and table.concat(realChars, "", tailStart, #realChars) or ""
			return head .. tail
		else
			-- Extra bullets pasted/typed: keep oldReal
			return oldReal
		end
	end

	local mid = table.concat(dispChars, "", p + 1, #dispChars - s)
	local safeP = math.min(p, #realChars)
	local safeTailStart = math.max(safeP + 1, #realChars - s + 1)
	local head = safeP > 0 and table.concat(realChars, "", 1, safeP) or ""
	local tail = safeTailStart <= #realChars and table.concat(realChars, "", safeTailStart, #realChars) or ""
	return head .. mid .. tail
end

local function filterNumeric(text, allowDecimal)
	local out = {}
	local seenDot = false
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		if ch >= "0" and ch <= "9" then
			table.insert(out, ch)
		elseif ch == "-" and #out == 0 then
			table.insert(out, ch)
		elseif allowDecimal and ch == "." and not seenDot then
			seenDot = true
			table.insert(out, ch)
		end
	end
	return table.concat(out)
end

function Input.new(parent, opts, ctx)
	opts = Util.Options(opts, { Default = "" }, "Title")
	local element = Base.New("Input", parent, opts, ctx)

	local isNumeric = (opts.Numeric == true or opts.Integer == true)
	local allowDecimal = (opts.Integer ~= true)
	local isMaskFeature = (opts.Mask == true or opts.Password == true)
	local masked = isMaskFeature
	local clearable = (opts.Clearable == true)
	local isLive = (opts.Live == true)
	if opts.Finished == false then
		isLive = true
	end
	local maxLength = tonumber(opts.MaxLength)

	local realText = tostring(opts.Default or "")
	if isNumeric then
		realText = filterNumeric(realText, allowDecimal)
	end
	if maxLength and #realText > maxLength then
		realText = string.sub(realText, 1, maxLength)
	end
	element.Value = realText

	local card = Base.Card(parent, { Padding = 0 })

	local body = Create.New("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 10, 12, 12, 12 },
		ZIndex = 2,
		Parent = card.Frame,
	})

	Create.List(body, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 8,
	})

	local titleText = tostring(opts.Title or "")
	local descText = tostring(opts.Description or opts.Desc or "")

	local header = Create.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Visible = (titleText ~= "" or descText ~= "" or (opts.Icon ~= nil and opts.Icon ~= "")),
		Parent = body,
	})

	Create.List(header, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 8,
	})

	local iconWidth = 0
	if opts.Icon and opts.Icon ~= "" and opts.Icon ~= false then
		Icons.Create(opts.Icon, {
			Size = UDim2.fromOffset(17, 17),
			Color = opts.IconColor or "SubText",
			LayoutOrder = 1,
			Parent = header,
		})
		iconWidth = 17
	end

	local textCol = Create.New("Frame", {
		Name = "TextColumn",
		Size = UDim2.new(1, iconWidth > 0 and -(iconWidth + 8) or 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = header,
	})

	Create.List(textCol, {
		Direction = Enum.FillDirection.Vertical,
		Gap = 2,
	})

	local titleLabel = Create.Text({
		Name = "Title",
		Text = titleText,
		Font = "Medium",
		TextSize = 13,
		Color = "Text",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Visible = titleText ~= "",
		Parent = textCol,
	})

	local descLabel = Create.Text({
		Name = "Description",
		Text = descText,
		Font = "Regular",
		TextSize = 12,
		Color = "SubText",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Visible = descText ~= "",
		Parent = textCol,
	})

	-- Field container
	local multiline = (opts.Multiline == true)
	local boxHeight = multiline and (opts.Height or 76) or 36

	local fieldBox = Create.New("Frame", {
		Name = "FieldBox",
		Size = UDim2.new(1, 0, 0, boxHeight),
		Theme = { BackgroundColor3 = "Field" },
		Corner = 8,
		Padding = multiline and { 8, 10, 8, 10 } or { 0, 10, 0, 10 },
		LayoutOrder = 2,
		Parent = body,
	})

	local fieldStroke = Create.Stroke(fieldBox, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
		Thickness = 1,
	})

	Create.List(fieldBox, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = multiline and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center,
		Gap = 6,
	})

	local leadingIconWidth = 0
	if opts.BoxIcon and opts.BoxIcon ~= "" then
		Icons.Create(opts.BoxIcon, {
			Size = UDim2.fromOffset(15, 15),
			Color = "Muted",
			LayoutOrder = 1,
			Parent = fieldBox,
		})
		leadingIconWidth = 15 + 6
	end

	local function maskedString(s)
		local len = #splitUtf8(s)
		return string.rep(BULLET, len)
	end

	local textBox = Create.New("TextBox", {
		Name = "TextBox",
		Size = UDim2.new(1, -leadingIconWidth, 1, 0),
		BackgroundTransparency = 1,
		Text = masked and maskedString(realText) or realText,
		PlaceholderText = tostring(opts.Placeholder or "Enter value..."),
		TextSize = 13,
		Font = "Regular",
		Theme = {
			TextColor3 = "Text",
			PlaceholderColor3 = "Muted",
		},
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		MultiLine = multiline,
		TextWrapped = multiline,
		ClipsDescendants = true,
		ClearTextOnFocus = (opts.ClearOnFocus == true),
		LayoutOrder = 2,
		Parent = fieldBox,
	})

	local trailingWrap = Create.New("Frame", {
		Name = "Trailing",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = fieldBox,
	})

	Create.List(trailingWrap, {
		Direction = Enum.FillDirection.Horizontal,
		VAlign = Enum.VerticalAlignment.Center,
		Gap = 4,
	})

	local clearBtn, eyeBtn, eyeIcon

	if clearable then
		clearBtn = Create.New("TextButton", {
			Name = "ClearButton",
			Size = UDim2.fromOffset(22, 22),
			Theme = { BackgroundColor3 = "Tile" },
			BackgroundTransparency = 1,
			Corner = 6,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
			Visible = (realText ~= ""),
			ZIndex = 4,
			Parent = trailingWrap,
		})
		Icons.Create("x", {
			Size = UDim2.fromOffset(13, 13),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = "SubText",
			Parent = clearBtn,
		})
		element.Maid:Give(clearBtn.MouseEnter:Connect(function()
			clearBtn.BackgroundTransparency = 0.4
		end))
		element.Maid:Give(clearBtn.MouseLeave:Connect(function()
			clearBtn.BackgroundTransparency = 1
		end))
	end

	if isMaskFeature then
		eyeBtn = Create.New("TextButton", {
			Name = "MaskButton",
			Size = UDim2.fromOffset(22, 22),
			Theme = { BackgroundColor3 = "Tile" },
			BackgroundTransparency = 1,
			Corner = 6,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 2,
			ZIndex = 4,
			Parent = trailingWrap,
		})
		eyeIcon = Icons.Create(masked and "eye-off" or "eye", {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = "SubText",
			Parent = eyeBtn,
		})
		element.Maid:Give(eyeBtn.MouseEnter:Connect(function()
			eyeBtn.BackgroundTransparency = 0.4
		end))
		element.Maid:Give(eyeBtn.MouseLeave:Connect(function()
			eyeBtn.BackgroundTransparency = 1
		end))
	end

	local function syncBoxWidth()
		local trailingW = math.ceil(trailingWrap.AbsoluteSize.X)
		local extraGap = trailingW > 0 and (trailingW + 6) or 0
		textBox.Size = UDim2.new(1, -(leadingIconWidth + extraGap), 1, 0)
	end

	element.Maid:Give(trailingWrap:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncBoxWidth))
	task.defer(syncBoxWidth)

	local guard = false
	local focused = false
	local lastCommitted = realText

	local function syncTrailingState()
		if clearBtn then
			clearBtn.Visible = (realText ~= "") and not element.Disabled and not element.Locked
		end
		syncBoxWidth()
	end

	local function commit(val, enterPressed, forceFire)
		local nextVal = tostring(val or "")
		if isNumeric then
			nextVal = filterNumeric(nextVal, allowDecimal)
		end
		if maxLength and #nextVal > maxLength then
			nextVal = string.sub(nextVal, 1, maxLength)
		end

		local changed = (nextVal ~= lastCommitted)
		realText = nextVal
		lastCommitted = nextVal
		element.Value = realText

		guard = true
		textBox.Text = masked and maskedString(realText) or realText
		guard = false
		syncTrailingState()

		if changed or forceFire then
			element.Changed:Fire(realText, enterPressed)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, realText, enterPressed)
			end
		end
	end

	element.Maid:Give(textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if guard then
			return
		end
		local rawDisp = textBox.Text
		local nextReal
		if masked then
			nextReal = reconcileMasked(realText, rawDisp, textBox.CursorPosition)
		else
			nextReal = rawDisp
		end

		if isNumeric then
			nextReal = filterNumeric(nextReal, allowDecimal)
		end
		if maxLength and #nextReal > maxLength then
			nextReal = string.sub(nextReal, 1, maxLength)
		end

		realText = nextReal
		element.Value = realText

		local expectedDisp = masked and maskedString(realText) or realText
		if textBox.Text ~= expectedDisp then
			local pos = textBox.CursorPosition
			guard = true
			textBox.Text = expectedDisp
			if masked and pos > 0 then
				-- Keep cursor consistent with bullet byte length
				textBox.CursorPosition = math.min(#expectedDisp + 1, pos)
			end
			guard = false
		end

		syncTrailingState()

		if isLive and realText ~= lastCommitted then
			lastCommitted = realText
			element.Changed:Fire(realText, false)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, realText, false)
			end
		end
	end))

	element.Maid:Give(textBox.Focused:Connect(function()
		if element.Disabled or element.Locked then
			textBox:ReleaseFocus()
			return
		end
		focused = true
		Tween.Play(fieldStroke, {
			Color = Theme.Current.Accent,
			Transparency = 0.15,
			Thickness = 1.5,
		}, Tween.Fast, Enum.EasingStyle.Quad)
		Tween.Play(fieldBox, {
			BackgroundColor3 = Theme.Current.FieldHover,
		}, Tween.Fast, Enum.EasingStyle.Quad)
	end))

	element.Maid:Give(textBox.FocusLost:Connect(function(enterPressed)
		focused = false
		Tween.Play(fieldStroke, {
			Color = Theme.Current.Stroke,
			Transparency = Theme.Current.StrokeTransparency,
			Thickness = 1,
		}, Tween.Fast, Enum.EasingStyle.Quad)
		Tween.Play(fieldBox, {
			BackgroundColor3 = Theme.Current.Field,
		}, Tween.Fast, Enum.EasingStyle.Quad)

		if not isLive then
			if opts.EnterOnly and not enterPressed then
				return
			end
			commit(realText, enterPressed, enterPressed == true)
		end
	end))

	element.Maid:Give(Theme.Changed:Connect(function(t)
		if element._destroyed then
			return
		end
		if focused then
			fieldStroke.Color = t.Accent
			fieldBox.BackgroundColor3 = t.FieldHover
		end
	end))

	if clearBtn then
		element.Maid:Give(clearBtn.Activated:Connect(function(inputObj)
			if element.Disabled or element.Locked then
				return
			end
			Transition.Ripple(clearBtn, inputObj, "Accent")
			commit("", false, false)
		end))
	end

	if eyeBtn then
		element.Maid:Give(eyeBtn.Activated:Connect(function(inputObj)
			if element.Disabled or element.Locked then
				return
			end
			Transition.Ripple(eyeBtn, inputObj, "Accent")
			masked = not masked
			if eyeIcon then
				Icons.Set(eyeIcon, masked and "eye-off" or "eye")
			end
			guard = true
			textBox.Text = masked and maskedString(realText) or realText
			guard = false
		end))
	end

	function element:Set(str, silent)
		local nextVal = tostring(str or "")
		if isNumeric then
			nextVal = filterNumeric(nextVal, allowDecimal)
		end
		if maxLength and #nextVal > maxLength then
			nextVal = string.sub(nextVal, 1, maxLength)
		end
		local changed = (nextVal ~= realText)
		realText = nextVal
		lastCommitted = nextVal
		self.Value = realText
		guard = true
		textBox.Text = masked and maskedString(realText) or realText
		guard = false
		syncTrailingState()
		if changed and not silent then
			self.Changed:Fire(realText, false)
			if type(opts.Callback) == "function" then
				Util.Spawn(opts.Callback, realText, false)
			end
		end
	end

	function element:Get()
		return realText
	end

	function element:Focus()
		if not self.Disabled and not self.Locked then
			textBox:CaptureFocus()
		end
	end

	element._onDisabled = function(disabled)
		textBox.TextEditable = not disabled
		if disabled and textBox:IsFocused() then
			textBox:ReleaseFocus()
		end
		syncTrailingState()
	end

	card.TitleLabel = titleLabel
	card.DescLabel = descLabel
	function card:SetTitle(s)
		local txt = tostring(s or "")
		titleLabel.Text = txt
		titleLabel.Visible = (txt ~= "")
		header.Visible = (txt ~= "" or descLabel.Text ~= "" or iconWidth > 0)
	end
	function card:SetDesc(s)
		local txt = tostring(s or "")
		descLabel.Text = txt
		descLabel.Visible = (txt ~= "")
		header.Visible = (titleLabel.Text ~= "" or txt ~= "" or iconWidth > 0)
	end

	element:BindUI(card)
	return element
end

return Input
