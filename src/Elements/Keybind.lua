--[[
	Lumina UI · Elements/Keybind
	Interactive keybind row with key capture pulse state, Mode pill & PopupLayer mode menu,
	Systems/Input integration, and Systems/KeybindList live synchronization.
]]

local Services = require("Core/Services")
local Util = require("Core/Util")
local Theme = require("Core/Theme")
local Create = require("Core/Create")
local Tween = require("Core/Tween")
local Assets = require("Core/Assets")
local Icons = require("Core/Icons")
local Transition = require("Core/Transition")
local Base = require("Elements/Base")
local Input = require("Systems/Input")
local KeybindList = require("Systems/KeybindList")
local Tooltip = require("Systems/Tooltip")

local Keybind = {}
Keybind.__index = Keybind

local MODES = { "Toggle", "Hold", "Always" }

local function normalizeMode(mode)
	if type(mode) == "string" then
		local lower = string.lower(mode)
		if lower == "toggle" then
			return "Toggle"
		elseif lower == "hold" then
			return "Hold"
		elseif lower == "always" then
			return "Always"
		end
	end
	return "Toggle"
end

local function resolveKeySafe(key)
	if type(key) == "string" then
		key = key:gsub("^Enum%.KeyCode%.", ""):gsub("^Enum%.UserInputType%.", "")
	end
	return Util.ResolveKey(key)
end

local function isDisabledOrLocked(self)
	return self.Disabled == true or self.Locked == true or self._disabled == true or self._locked == true
end

function Keybind.new(parent, opts, ctx)
	opts = Util.Options(opts, {
		Title = "Keybind",
		Description = nil,
		Default = nil,
		Mode = "Toggle",
		AllowMouse = true,
		SyncList = true,
		Callback = nil,
		ChangedCallback = nil,
		Flag = nil,
		Tooltip = nil,
	}, "Title")
	ctx = ctx or {}

	local self = Base.New("Keybind", parent, opts, ctx)
	local rowParent = (typeof(self.Frame) == "Instance") and self.Frame or parent
	local rightWidth = 152
	local row = Base.Row(rowParent, opts, rightWidth)

	if typeof(self.Frame) ~= "Instance" then
		self.Frame = row.Frame
	else
		self.Frame.BackgroundTransparency = 1
		self.Frame.Size = UDim2.new(1, 0, 0, 0)
		self.Frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	if self.BindUI then
		self:BindUI(row)
	end

	self._row = row
	self.Row = row
	self.TitleLabel = row.TitleLabel
	self.DescLabel = row.DescLabel
	self.Stroke = row.Stroke
	self.LockOverlay = row.LockOverlay

	if opts.Tooltip and Tooltip and Tooltip.Bind then
		pcall(Tooltip.Bind, row.Frame, opts.Tooltip)
	end

	local bindId = "Keybind_" .. Util.RandomString(8)
	local currentTitle = tostring(opts.Title or "Keybind")
	local currentKey = resolveKeySafe(opts.Default)
	local currentMode = normalizeMode(opts.Mode)
	local allowMouse = opts.AllowMouse ~= false
	local syncList = opts.SyncList ~= false
	local activeState = currentMode == "Always"

	local listening = false
	local stopPulse = nil
	local modeOpen = false
	local modePopupId = "KeybindMode_" .. Util.RandomString(8)
	local modeOpenGen = 0

	self.Value = currentKey
	self.Mode = currentMode

	-- Right container holds Mode pill + Key chip aligned cleanly on right
	local controls = Create.New("Frame", {
		Name = "Controls",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = row.Right,
	})
	Create.List(controls, {
		Direction = Enum.FillDirection.Horizontal,
		Gap = 6,
		HAlign = Enum.HorizontalAlignment.Right,
		VAlign = Enum.VerticalAlignment.Center,
	})

	local modePill = Create.New("TextButton", {
		Name = "ModePill",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Text = "",
		Corner = 7,
		Padding = { 0, 8, 0, 8 },
		Theme = { BackgroundColor3 = "Field" },
		Parent = controls,
	})
	local modeStroke = Create.Stroke(modePill, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})
	local modeLabel = Create.Text({
		Name = "ModeText",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = currentMode,
		TextSize = 11,
		Font = "Medium",
		TextXAlignment = Enum.TextXAlignment.Center,
		Color = "SubText",
		Parent = modePill,
	})
	Transition.Hover(modePill, modePill, "Field", "FieldHover", modeStroke)

	local keyChip = Create.New("TextButton", {
		Name = "KeyChip",
		Size = UDim2.fromOffset(34, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Text = "",
		Corner = 7,
		Padding = { 0, 9, 0, 9 },
		Theme = { BackgroundColor3 = "Field" },
		Parent = controls,
	})
	local keyStroke = Create.Stroke(keyChip, {
		Theme = { Color = "Stroke", Transparency = "StrokeTransparency" },
	})
	local keyLabel = Create.Text({
		Name = "KeyText",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = Util.KeyName(currentKey),
		TextSize = 11,
		Font = "SemiBold",
		TextXAlignment = Enum.TextXAlignment.Center,
		Color = currentKey and "Text" or "Muted",
		Parent = keyChip,
	})
	Transition.Hover(keyChip, keyChip, "Field", "FieldHover", keyStroke)

	-- Floating Mode selection menu in PopupLayer
	local shadowInfo = Assets.Shadow()
	local shadowInset = shadowInfo.Inset or 24
	local modePopup = Create.New("Frame", {
		Name = modePopupId,
		Size = UDim2.fromOffset(122, 108),
		Visible = false,
		ZIndex = 110,
		Corner = 9,
		Theme = {
			BackgroundColor3 = "Card",
			BackgroundTransparency = function(t)
				return math.min(t.CardTransparency or 0.12, 0.04)
			end,
		},
	})
	Create.GlassStroke(modePopup, 0.06)

	Create.New("ImageLabel", {
		Name = "Shadow",
		Size = UDim2.new(1, shadowInset * 2, 1, shadowInset * 2),
		Position = UDim2.fromOffset(-shadowInset, -shadowInset),
		Image = shadowInfo.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = shadowInfo.Slice,
		ZIndex = 109,
		Theme = {
			ImageColor3 = "Shadow",
			ImageTransparency = "ShadowTransparency",
		},
		Parent = modePopup,
	})

	local modePopupInner = Create.New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 111,
		Padding = { 6, 6, 6, 6 },
		Parent = modePopup,
	})
	Create.List(modePopupInner, { Gap = 3 })

	local modeButtons = {}

	local function syncKeybindList()
		if not syncList or not KeybindList or not KeybindList.Update then
			return
		end
		KeybindList.Update(bindId, {
			Title = currentTitle,
			KeyName = Util.KeyName(currentKey),
			Mode = currentMode,
			Active = activeState,
		})
	end

	local function updateChipVisuals()
		if not listening then
			keyLabel.Text = Util.KeyName(currentKey)
			Theme.Bind(keyLabel, { TextColor3 = currentKey and "Text" or "Muted" })
			Theme.Bind(keyStroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
		end
		modeLabel.Text = currentMode
		for modeName, entry in pairs(modeButtons) do
			local active = modeName == currentMode
			Theme.Bind(entry.Button, {
				BackgroundColor3 = active and "Accent" or "TileHover",
				BackgroundTransparency = active and function() return 0.84 end or function() return entry.Hovered and 0.4 or 1 end,
			})
			Theme.Bind(entry.Label, {
				TextColor3 = active and "Text" or "SubText",
				FontFace = active and "@SemiBold" or "@Medium",
			})
			if entry.Check then
				entry.Check.Visible = active
			end
		end
	end

	local inputHandle
	local function onTriggered(active)
		activeState = active == true
		syncKeybindList()
		if opts.Callback then
			Util.Spawn(opts.Callback, activeState)
		end
	end

	if Input and Input.RegisterKeybind then
		inputHandle = Input.RegisterKeybind(bindId, currentKey, onTriggered, currentMode)
		if inputHandle and inputHandle.Active ~= nil then
			activeState = inputHandle.Active == true
		end
	end

	if syncList and KeybindList and KeybindList.Register then
		KeybindList.Register(bindId, {
			Title = currentTitle,
			KeyName = Util.KeyName(currentKey),
			Mode = currentMode,
			Active = activeState,
		})
	end

	local fallbackModeConn
	local function handleModeClosed()
		if not modeOpen then
			return
		end
		modeOpen = false
		modeOpenGen += 1
		local myGen = modeOpenGen
		if fallbackModeConn then
			fallbackModeConn:Disconnect()
			fallbackModeConn = nil
		end
		Transition.Unmount(modePopup, 0.94, function()
			if modeOpenGen == myGen and not modeOpen then
				modePopup.Visible = false
			end
		end)
	end

	local function closeModeMenu()
		if not modeOpen then
			return
		end
		handleModeClosed()
		if ctx.ClosePopup then
			ctx.ClosePopup(modePopupId)
		end
	end

	local function openModeMenu()
		if modeOpen or isDisabledOrLocked(self) then
			return
		end
		modeOpen = true
		modeOpenGen += 1
		modePopup.Visible = true
		if ctx.OpenPopup then
			if ctx.PopupLayer then
				modePopup.Parent = ctx.PopupLayer
			end
			ctx.OpenPopup(modePopupId, modePopup, modePill, handleModeClosed)
		else
			local layer = ctx.PopupLayer or row.Frame:FindFirstAncestorOfClass("ScreenGui")
			if layer then
				modePopup.Parent = layer
				local view = layer.AbsoluteSize
				local aPos, aSize = modePill.AbsolutePosition, modePill.AbsoluteSize
				local px = Util.Clamp(aPos.X + aSize.X - 122, 8, math.max(8, view.X - 130))
				local py = aPos.Y + aSize.Y + 6
				if py + 108 > view.Y - 8 then
					py = math.max(8, aPos.Y - 114)
				end
				modePopup.Position = UDim2.fromOffset(px, py)
				fallbackModeConn = Services.UserInputService.InputBegan:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Escape then
						closeModeMenu()
					elseif Util.IsPointer(input) then
						local pos = Util.MousePosition()
						local pPos, pSize = modePopup.AbsolutePosition, modePopup.AbsoluteSize
						if pos.X < pPos.X or pos.X > pPos.X + pSize.X or pos.Y < pPos.Y or pos.Y > pPos.Y + pSize.Y then
							closeModeMenu()
						end
					end
				end)
			end
		end
		Transition.Mount(modePopup, 0.94)
	end

	for index, modeName in ipairs(MODES) do
		local btn = Create.New("TextButton", {
			Name = "Mode_" .. modeName,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = index,
			ZIndex = 112,
			Corner = 6,
			Padding = { 0, 8, 0, 8 },
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "TileHover" },
			Parent = modePopupInner,
		})
		local lbl = Create.Text({
			Size = UDim2.new(1, -18, 1, 0),
			Text = modeName,
			TextSize = 12,
			Font = "Medium",
			Color = "SubText",
			ZIndex = 113,
			Parent = btn,
		})
		local chk = Icons.Create("check", {
			Size = UDim2.fromOffset(12, 12),
			Position = UDim2.new(1, 0, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = "Accent",
			ZIndex = 113,
			Parent = btn,
		})
		local entry = { Button = btn, Label = lbl, Check = chk, Hovered = false }
		btn.MouseEnter:Connect(function()
			entry.Hovered = true
			if currentMode ~= modeName then
				Theme.Bind(btn, { BackgroundColor3 = "TileHover", BackgroundTransparency = function() return 0.45 end })
			end
		end)
		btn.MouseLeave:Connect(function()
			entry.Hovered = false
			if currentMode ~= modeName then
				Theme.Bind(btn, { BackgroundColor3 = "TileHover", BackgroundTransparency = function() return 1 end })
			end
		end)
		btn.Activated:Connect(function()
			Transition.Ripple(btn, nil, "Accent")
			self:Set(currentKey, modeName, false)
			closeModeMenu()
		end)
		modeButtons[modeName] = entry
	end

	local function stopListening()
		if not listening then
			return
		end
		listening = false
		if stopPulse then
			pcall(stopPulse)
			stopPulse = nil
		end
		updateChipVisuals()
	end

	local function startListening()
		if isDisabledOrLocked(self) then
			return
		end
		closeModeMenu()
		listening = true
		keyLabel.Text = "Listening..."
		Theme.Bind(keyLabel, { TextColor3 = "Accent" })
		Theme.Bind(keyStroke, { Color = "Accent", Transparency = function() return 0.25 end })
		if stopPulse then
			pcall(stopPulse)
		end
		stopPulse = Transition.Pulse(keyStroke, "Transparency", 0.15, 0.72, 0.75)

		if Input and Input.CaptureKey then
			Input.CaptureKey(function(captured, cancelled)
				if not listening then
					return
				end
				if cancelled or captured == Enum.KeyCode.Escape then
					stopListening()
					return
				end
				if captured == nil or captured == Enum.KeyCode.Backspace or captured == Enum.KeyCode.Delete then
					stopListening()
					self:Set(nil, currentMode, false)
					return
				end
				if not allowMouse and typeof(captured) == "EnumItem" and captured.EnumType == Enum.UserInputType then
					-- Mouse binds disabled: keep waiting for a keyboard key
					stopListening()
					task.defer(startListening)
					return
				end
				stopListening()
				self:Set(captured, currentMode, false)
			end, { AllowMouse = allowMouse })
		end
	end

	local function cycleMode()
		if isDisabledOrLocked(self) then
			return
		end
		local idx = table.find(MODES, currentMode) or 1
		local nextMode = MODES[(idx % #MODES) + 1]
		self:Set(currentKey, nextMode, false)
	end

	keyChip.Activated:Connect(function()
		if isDisabledOrLocked(self) then
			return
		end
		Transition.Ripple(keyChip, nil, "Accent")
		if listening then
			if Input and Input.CancelCapture then
				Input.CancelCapture()
			end
			stopListening()
		else
			startListening()
		end
	end)

	modePill.Activated:Connect(function()
		if isDisabledOrLocked(self) then
			return
		end
		Transition.Ripple(modePill, nil, "Accent")
		if modeOpen then
			closeModeMenu()
		else
			openModeMenu()
		end
	end)

	-- Right-click cycles Mode quickly on both Mode pill and Key chip
	local function bindRightClick(btn)
		btn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and not isDisabledOrLocked(self) then
				closeModeMenu()
				cycleMode()
			end
		end)
	end
	bindRightClick(modePill)
	bindRightClick(keyChip)

	function self:Set(key, modeOrSilent, silentArg)
		local nextKey = key
		local nextMode = currentMode
		local silent = false

		if type(key) == "table" then
			nextKey = key.Key ~= nil and key.Key or key[1]
			if key.Mode ~= nil then
				nextMode = normalizeMode(key.Mode)
			end
		end
		if type(modeOrSilent) == "boolean" then
			silent = modeOrSilent
		elseif type(modeOrSilent) == "string" then
			nextMode = normalizeMode(modeOrSilent)
			silent = silentArg == true
		elseif silentArg ~= nil then
			silent = silentArg == true
		end

		currentKey = resolveKeySafe(nextKey)
		currentMode = nextMode
		self.Value = currentKey
		self.Mode = currentMode

		if inputHandle then
			if inputHandle.SetKey then
				inputHandle:SetKey(currentKey)
			end
			if inputHandle.SetMode then
				inputHandle:SetMode(currentMode)
			end
			activeState = inputHandle.Active == true or currentMode == "Always"
		else
			activeState = currentMode == "Always"
		end

		updateChipVisuals()
		syncKeybindList()

		if not silent then
			if opts.ChangedCallback then
				Util.Spawn(opts.ChangedCallback, currentKey, currentMode)
			end
			self.Changed:Fire(currentKey, currentMode)
		end
	end

	function self:Get()
		return currentKey, currentMode
	end

	function self:GetState()
		if currentMode == "Always" then
			return true
		end
		if inputHandle and inputHandle.Active ~= nil then
			return inputHandle.Active == true
		end
		return activeState
	end

	local baseSetTitle = self.SetTitle
	function self:SetTitle(text)
		currentTitle = tostring(text or "")
		if baseSetTitle then
			pcall(baseSetTitle, self, text)
		end
		if row.TitleLabel then
			row.TitleLabel.Text = currentTitle
		end
		syncKeybindList()
	end

	local baseSetDesc = self.SetDesc
	function self:SetDesc(text)
		if baseSetDesc then
			pcall(baseSetDesc, self, text)
		end
		if row.DescLabel then
			local str = text and tostring(text) or ""
			row.DescLabel.Text = str
			row.DescLabel.Visible = str ~= ""
		end
	end

	local baseSetDisabled = self.SetDisabled
	function self:SetDisabled(disabled)
		self.Disabled = disabled == true
		if disabled then
			closeModeMenu()
			if listening and Input and Input.CancelCapture then
				Input.CancelCapture()
			end
			stopListening()
		end
		if baseSetDisabled then
			pcall(baseSetDisabled, self, disabled)
		end
	end

	local baseLock = self.Lock
	function self:Lock(reason)
		self.Locked = true
		closeModeMenu()
		if listening and Input and Input.CancelCapture then
			Input.CancelCapture()
		end
		stopListening()
		if baseLock then
			pcall(baseLock, self, reason)
		end
	end

	local baseUnlock = self.Unlock
	function self:Unlock()
		self.Locked = false
		if baseUnlock then
			pcall(baseUnlock, self)
		end
	end

	self.Maid:Give(function()
		closeModeMenu()
		if listening and Input and Input.CancelCapture then
			Input.CancelCapture()
		end
		stopListening()
		if fallbackModeConn then
			fallbackModeConn:Disconnect()
			fallbackModeConn = nil
		end
		if inputHandle and inputHandle.Destroy then
			inputHandle:Destroy()
		end
		if syncList and KeybindList and KeybindList.Unregister then
			KeybindList.Unregister(bindId)
		end
		modePopup:Destroy()
	end)

	updateChipVisuals()
	return self
end

return Keybind
