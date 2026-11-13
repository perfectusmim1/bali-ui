--[[
	Bali UI · Window/Section
	Obsidian glass card container inside a Tab/SubTab page with optional icon,
	subtitle, collapsible header, and attached element factory methods.
]]

local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Maid = require("Core/Maid")
local Theme = require("Core/Theme")
local Transition = require("Core/Transition")
local Tween = require("Core/Tween")
local Util = require("Core/Util")
local Container = require("Window/Container")

local Section = {}
Section.__index = Section

function Section.new(parent, options, tab, window, subTab)
	options = Util.Options(options, {
		Title = "",
		Subtitle = nil,
		Description = nil,
		Desc = nil,
		Icon = nil,
		Side = "Auto",
		Collapsible = false,
		DefaultOpen = true,
		LayoutOrder = 0,
	}, "Title")

	local subtitleText = options.Subtitle or options.Description or options.Desc
	local hasTitle = options.Title ~= nil and options.Title ~= ""
	local hasSubtitle = subtitleText ~= nil and subtitleText ~= ""
	local hasHeader = hasTitle or hasSubtitle or options.Icon ~= nil or options.Collapsible == true
	local isOpen = options.Open ~= nil and (options.Open ~= false) or (options.DefaultOpen ~= false)

	local maid = Maid.new()

	local card = Create.New("Frame", {
		Name = "Section_" .. (hasTitle and tostring(options.Title) or "Card"),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = options.LayoutOrder or 0,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = "CardTransparency",
		},
		Corner = 12,
		Padding = { 12, 12, 12, 12 },
		Parent = parent,
	})
	maid:Give(card)
	Create.GlassStroke(card, 0.03)
	Create.List(card, { Gap = 10 })

	local headerBtn
	local titleLabel
	local subtitleLabel
	local chevronIcon
	local chevronWrap
	local baseChevronRot = 0

	if hasHeader then
		headerBtn = Create.New("TextButton", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = "",
			Active = options.Collapsible == true,
			Selectable = false,
			LayoutOrder = 1,
			Parent = card,
		})

		local titleBlock = Create.New("Frame", {
			Name = "TitleBlock",
			Size = UDim2.new(1, options.Collapsible and -30 or 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = headerBtn,
		})
		Create.List(titleBlock, {
			Direction = Enum.FillDirection.Horizontal,
			Gap = 8,
			VAlign = Enum.VerticalAlignment.Center,
		})

		local hasIcon = false
		if options.Icon then
			local iconBadge = Create.New("Frame", {
				Name = "IconBadge",
				Size = UDim2.fromOffset(24, 24),
				Corner = 7,
				Theme = { BackgroundColor3 = "Accent" },
				BackgroundTransparency = 0.88,
				LayoutOrder = 1,
				Parent = titleBlock,
			})
			local iconInst = Icons.Create(options.Icon, {
				Size = UDim2.fromOffset(14, 14),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Color = "Accent",
				Parent = iconBadge,
			})
			if iconInst then
				hasIcon = true
			else
				iconBadge:Destroy()
			end
		end

		local textCol = Create.New("Frame", {
			Name = "TextColumn",
			Size = UDim2.new(1, hasIcon and -32 or 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = titleBlock,
		})
		Create.List(textCol, { Gap = 2 })

		titleLabel = Create.Text({
			Name = "Title",
			Text = options.Title or "",
			Font = "SemiBold",
			TextSize = 14,
			Color = "Text",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			Visible = hasTitle,
			LayoutOrder = 1,
			Parent = textCol,
		})

		subtitleLabel = Create.Text({
			Name = "Subtitle",
			Text = subtitleText or "",
			Font = "Regular",
			TextSize = 11,
			Color = "SubText",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			Visible = hasSubtitle,
			LayoutOrder = 2,
			Parent = textCol,
		})

		if options.Collapsible then
			chevronWrap = Create.New("Frame", {
				Name = "Chevron",
				Size = UDim2.fromOffset(22, 22),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Corner = 6,
				Theme = { BackgroundColor3 = "Tile" },
				BackgroundTransparency = 1,
				Parent = headerBtn,
			})
			chevronIcon = Icons.Create("chevron-down", {
				Size = UDim2.fromOffset(14, 14),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Color = "SubText",
				Parent = chevronWrap,
			})
			baseChevronRot = chevronIcon and chevronIcon.Rotation or 0
		end
	end

	local contentHolder = Create.New("Frame", {
		Name = "ContentHolder",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = isOpen,
		LayoutOrder = 2,
		Parent = card,
	})

	local content = Create.New("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = contentHolder,
	})
	local contentLayout = Create.List(content, { Gap = 8 })

	local self = setmetatable({
		Type = "Section",
		Title = options.Title or "",
		Subtitle = subtitleText or "",
		Icon = options.Icon,
		Side = options.Side or "Auto",
		Collapsible = options.Collapsible == true,
		Open = isOpen,
		Tab = tab,
		SubTab = subTab,
		Window = window,
		Maid = maid,
		Frame = card,
		_header = headerBtn,
		ContentHolder = contentHolder,
		Content = content,
		_contentLayout = contentLayout,
		_titleLabel = titleLabel,
		_subtitleLabel = subtitleLabel,
		_chevronIcon = chevronIcon,
		_baseChevronRot = baseChevronRot,
	}, Section)

	if chevronIcon and not isOpen then
		chevronIcon.Rotation = baseChevronRot - 90
	end

	if options.Collapsible and headerBtn then
		maid:Give(headerBtn.MouseEnter:Connect(function()
			if chevronWrap then
				Tween.Play(chevronWrap, { BackgroundTransparency = Theme.Current.TileTransparency }, Tween.Instant)
			end
			if chevronIcon then
				Icons.SetColor(chevronIcon, "Text")
			end
		end))
		maid:Give(headerBtn.MouseLeave:Connect(function()
			if chevronWrap then
				Tween.Play(chevronWrap, { BackgroundTransparency = 1 }, Tween.Instant)
			end
			if chevronIcon then
				Icons.SetColor(chevronIcon, "SubText")
			end
		end))
		maid:Give(headerBtn.Activated:Connect(function()
			self:SetOpen(not self.Open)
		end))
	end

	if tab and tab.Maid then
		tab.Maid:Give(self)
	end

	Container.Attach(self, content, tab, self, window, subTab)
	return self
end

function Section:SetTitle(text)
	self.Title = tostring(text or "")
	if self._titleLabel then
		self._titleLabel.Text = self.Title
		self._titleLabel.Visible = self.Title ~= ""
	end
end

function Section:SetSubtitle(text)
	self.Subtitle = tostring(text or "")
	if self._subtitleLabel then
		self._subtitleLabel.Text = self.Subtitle
		self._subtitleLabel.Visible = self.Subtitle ~= ""
	end
end

Section.SetDesc = Section.SetSubtitle

function Section:SetVisible(visible)
	if self.Frame then
		self.Frame.Visible = visible == true
	end
end

function Section:SetOpen(open, instant)
	open = open ~= false
	if self.Open == open and not instant then
		return
	end
	self.Open = open

	local holder = self.ContentHolder
	local content = self.Content
	local chevron = self._chevronIcon
	local targetRot = open and self._baseChevronRot or (self._baseChevronRot - 90)

	if self._sizeTween then
		pcall(function()
			self._sizeTween:Cancel()
		end)
		self._sizeTween = nil
	end

	if instant then
		if chevron then
			chevron.Rotation = targetRot
		end
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.Size = UDim2.new(1, 0, 0, 0)
		holder.Visible = open
		return
	end

	if chevron then
		Tween.Play(chevron, { Rotation = targetRot }, Tween.Fast)
	end

	if open then
		holder.Visible = true
		local targetHeight = math.max(content.AbsoluteSize.Y, self._contentLayout.AbsoluteContentSize.Y)
		holder.AutomaticSize = Enum.AutomaticSize.None
		holder.Size = UDim2.new(1, 0, 0, 0)
		local tween = Tween.Play(holder, { Size = UDim2.new(1, 0, 0, targetHeight) }, Tween.Normal)
		self._sizeTween = tween
		Tween.Then(tween, function()
			if self.Open then
				holder.AutomaticSize = Enum.AutomaticSize.Y
				holder.Size = UDim2.new(1, 0, 0, 0)
			end
		end)
	else
		local currentHeight = math.max(holder.AbsoluteSize.Y, content.AbsoluteSize.Y)
		holder.AutomaticSize = Enum.AutomaticSize.None
		holder.Size = UDim2.new(1, 0, 0, currentHeight)
		local tween = Tween.Play(holder, { Size = UDim2.new(1, 0, 0, 0) }, Tween.Fast)
		self._sizeTween = tween
		Tween.Then(tween, function()
			if not self.Open then
				holder.Visible = false
			end
		end)
	end
end

Section.SetExpanded = Section.SetOpen

function Section:Toggle()
	self:SetOpen(not self.Open)
end

function Section:Flash()
	if not self.Open then
		self:SetOpen(true, true)
	end
	if self.Frame then
		Transition.SlideFade(self.Frame, 4)
	end
end

function Section:Destroy()
	self.Maid:Clean()
end

return Section
