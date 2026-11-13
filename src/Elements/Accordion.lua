--[[
	Bali UI · Elements/Accordion
	Collapsible glass sub-container inside a Section with smooth expand/collapse animation
	and full Container attachment so all library elements can be nested cleanly.
]]

local Util = require("Core/Util")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Tween = require("Core/Tween")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Base = require("Elements/Base")
local Tooltip = require("Systems/Tooltip")

local Accordion = {}
Accordion.__index = Accordion

local function unwrapCard(cardParent, opts)
	local cardObj = Base.Card(cardParent, opts)
	if typeof(cardObj) == "Instance" then
		return cardObj, cardObj:FindFirstChildOfClass("UIStroke"), nil
	end
	return cardObj.Frame, cardObj.Stroke, cardObj
end

local function isDisabledOrLocked(self)
	return self.Disabled == true or self.Locked == true or self._disabled == true or self._locked == true
end

function Accordion.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Title = "Accordion",
		Description = nil,
		Icon = nil,
		Expanded = nil,
		Default = false,
		Callback = nil,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("Accordion", parent, opts, ctx)
	local cardParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local cardFrame, cardStroke, cardUI = unwrapCard(cardParent, opts)

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = cardFrame
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	cardFrame.ClipsDescendants = true
	Create.List(cardFrame, { Gap = 0 })

	local initialExpanded = false
	if opts.Expanded ~= nil then
		initialExpanded = opts.Expanded == true
	elseif opts.Opened ~= nil then
		initialExpanded = opts.Opened == true
	elseif opts.Default ~= nil then
		initialExpanded = opts.Default == true
	end

	local expanded = initialExpanded
	local animGen = 0

	self.Expanded = expanded
	self.Value = expanded
	self.Stroke = cardStroke

	-- Header row
	local headerBtn = Create.New("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Text = "",
		Padding = { 10, 12, 10, 12 },
		Theme = {
			BackgroundColor3 = "Tile",
			BackgroundTransparency = "TileTransparency",
		},
		Parent = cardFrame,
	})
	Transition.Hover(headerBtn, headerBtn, "Tile", "TileHover", cardStroke)

	local iconOffset = 0
	if opts.Icon then
		iconOffset = 24
		Icons.Create(opts.Icon, {
			Name = "Icon",
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = "Accent",
			Parent = headerBtn,
		})
	end

	local textCol = Create.New("Frame", {
		Name = "TextCol",
		Size = UDim2.new(1, -(iconOffset + 24), 0, 0),
		Position = UDim2.fromOffset(iconOffset, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = headerBtn,
	})
	Create.List(textCol, { Gap = 2 })

	local titleLabel = Create.Text({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = tostring(opts.Title or "Accordion"),
		TextSize = 13,
		Font = "SemiBold",
		TextWrapped = true,
		Color = "Text",
		LayoutOrder = 1,
		Parent = textCol,
	})

	local descText = opts.Description and tostring(opts.Description) or ""
	local descLabel = Create.Text({
		Name = "Description",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = descText,
		TextSize = 11,
		TextWrapped = true,
		Color = "SubText",
		Visible = descText ~= "",
		LayoutOrder = 2,
		Parent = textCol,
	})

	local chevron = Icons.Create("chevron-down", {
		Name = "Chevron",
		Size = UDim2.fromOffset(15, 15),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = "SubText",
		Parent = headerBtn,
	})
	local chevronBaseRot = chevron and chevron.Rotation or 0
	if chevron and expanded then
		chevron.Rotation = chevronBaseRot + 180
	end

	local divider = Create.New("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = 2,
		Visible = expanded,
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = cardFrame,
	})

	local bodyClip = Create.New("Frame", {
		Name = "BodyClip",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = expanded and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
		ClipsDescendants = true,
		BackgroundTransparency = 1,
		Visible = expanded,
		LayoutOrder = 3,
		Parent = cardFrame,
	})

	local bodyInner = Create.New("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Padding = { 8, 10, 10, 10 },
		Parent = bodyClip,
	})
	local innerLayout = Create.List(bodyInner, { Gap = 8 })

	self.Content = bodyInner
	self.Body = bodyInner
	self.TitleLabel = titleLabel
	self.DescLabel = descLabel

	if self.BindUI then
		self:BindUI({
			Frame = cardFrame,
			Stroke = cardStroke,
			TitleLabel = titleLabel,
			DescLabel = descLabel,
			LockOverlay = cardUI and cardUI.LockOverlay or nil,
			SetDisabled = cardUI and cardUI.SetDisabled or nil,
			Lock = cardUI and cardUI.Lock or nil,
			Unlock = cardUI and cardUI.Unlock or nil,
			Flash = cardUI and cardUI.Flash or nil,
		})
	end

	if opts.Tooltip and Tooltip and Tooltip.Bind then
		pcall(Tooltip.Bind, headerBtn, opts.Tooltip)
	end

	if ctx.AttachContainer then
		ctx.AttachContainer(self, bodyInner, ctx.Tab, ctx.Section)
	end

	local function animateState(targetExpanded)
		animGen += 1
		local myGen = animGen

		if chevron then
			Tween.Play(chevron, { Rotation = targetExpanded and (chevronBaseRot + 180) or chevronBaseRot }, Tween.Fast)
		end

		if targetExpanded then
			divider.Visible = true
			bodyClip.Visible = true
			bodyClip.AutomaticSize = Enum.AutomaticSize.None
			bodyClip.Size = UDim2.new(1, 0, 0, 0)

			local function runExpandTween()
				if animGen ~= myGen or not expanded then
					return
				end
				local targetH = math.max(18, innerLayout.AbsoluteContentSize.Y + 18)
				local tw = Tween.Play(bodyClip, { Size = UDim2.new(1, 0, 0, targetH) }, Tween.Normal)
				Tween.Then(tw, function()
					if animGen == myGen and expanded then
						bodyClip.AutomaticSize = Enum.AutomaticSize.Y
						bodyClip.Size = UDim2.new(1, 0, 0, 0)
					end
				end)
			end

			if innerLayout.AbsoluteContentSize.Y > 0 then
				runExpandTween()
			else
				task.defer(runExpandTween)
			end
		else
			local startH = bodyClip.AbsoluteSize.Y
			if startH <= 0 then
				startH = innerLayout.AbsoluteContentSize.Y + 18
			end
			bodyClip.AutomaticSize = Enum.AutomaticSize.None
			bodyClip.Size = UDim2.new(1, 0, 0, startH)

			local tw = Tween.Play(bodyClip, { Size = UDim2.new(1, 0, 0, 0) }, Tween.Fast)
			Tween.Then(tw, function()
				if animGen == myGen and not expanded then
					bodyClip.Visible = false
					divider.Visible = false
				end
			end)
		end
	end

	function self:SetExpanded(state, silent)
		local nextState = state == true
		if expanded == nextState then
			return
		end
		expanded = nextState
		self.Expanded = expanded
		self.Value = expanded
		animateState(expanded)

		if not silent then
			if opts.Callback then
				Util.Spawn(opts.Callback, expanded)
			end
			self.Changed:Fire(expanded)
		end
	end

	function self:Set(state, silent)
		self:SetExpanded(state, silent)
	end

	function self:Get()
		return expanded
	end

	function self:IsExpanded()
		return expanded
	end

	function self:Expand(silent)
		self:SetExpanded(true, silent)
	end

	function self:Collapse(silent)
		self:SetExpanded(false, silent)
	end

	function self:Toggle(silent)
		self:SetExpanded(not expanded, silent)
	end

	headerBtn.Activated:Connect(function()
		if isDisabledOrLocked(self) then
			return
		end
		Transition.Ripple(headerBtn, nil, "Accent")
		self:Toggle(false)
	end)

	local baseSetTitle = self.SetTitle
	function self:SetTitle(text)
		titleLabel.Text = tostring(text or "")
		if baseSetTitle then
			pcall(baseSetTitle, self, text)
		end
	end

	local baseSetDesc = self.SetDesc
	function self:SetDesc(text)
		local str = text and tostring(text) or ""
		descLabel.Text = str
		descLabel.Visible = str ~= ""
		if baseSetDesc then
			pcall(baseSetDesc, self, text)
		end
	end

	self.Maid:Give(function()
		animGen += 1
	end)

	return self
end

return Accordion
