--[[
	Lumina UI · Systems/Input
	Centralised input dispatcher: keybinds (Toggle/Hold/Always), key capture,
	viewport-clamped dragging, and smooth resizing for mouse and touch.
]]

local Services = require("Core/Services")
local Maid = require("Core/Maid")
local Util = require("Core/Util")

local Input = {
	Capturing = false,
}

local initialized = false
local rootMaid = Maid.new()
local keybinds = {} -- [id] = entry
local captureConn = nil
local captureCallback = nil
local captureToken = 0

local function getViewportBounds(instance)
	if instance then
		local layer = instance:FindFirstAncestorWhichIsA("LayerCollector")
		if layer and layer.AbsoluteSize.X > 0 and layer.AbsoluteSize.Y > 0 then
			return layer.AbsolutePosition, layer.AbsoluteSize
		end
	end
	local camera = Services.Workspace.CurrentCamera
	local rawSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local ok, inset = pcall(function()
		return Services.GuiService:GetGuiInset()
	end)
	if ok and inset then
		return Vector2.new(inset.X, inset.Y), Vector2.new(rawSize.X - inset.X, rawSize.Y - inset.Y)
	end
	return Vector2.zero, rawSize
end

local function matchesKey(key, input)
	if typeof(key) ~= "EnumItem" then
		return false
	end
	if key.EnumType == Enum.KeyCode then
		return input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode == key
	elseif key.EnumType == Enum.UserInputType then
		return input.UserInputType == key
	end
	return false
end

local function normalizeMode(mode)
	if mode == "Hold" or mode == "Always" or mode == "Toggle" then
		return mode
	end
	return "Toggle"
end

function Input.Init()
	if initialized then
		return Input
	end
	initialized = true

	local UIS = Services.UserInputService

	rootMaid:Give(UIS.InputBegan:Connect(function(input, gameProcessedEvent)
		if Input.Capturing or gameProcessedEvent or UIS:GetFocusedTextBox() ~= nil then
			return
		end

		for _, entry in pairs(keybinds) do
			if entry.Key and matchesKey(entry.Key, input) then
				if entry.Mode == "Toggle" then
					entry.Active = not entry.Active
					Util.Spawn(entry.Callback, entry.Active)
				elseif entry.Mode == "Hold" then
					if not entry.Active then
						entry.Active = true
						Util.Spawn(entry.Callback, true)
					end
				end
			end
		end
	end))

	rootMaid:Give(UIS.InputEnded:Connect(function(input)
		for _, entry in pairs(keybinds) do
			if entry.Mode == "Hold" and entry.Active and entry.Key and matchesKey(entry.Key, input) then
				entry.Active = false
				Util.Spawn(entry.Callback, false)
			end
		end
	end))

	return Input
end

function Input.RegisterKeybind(id, key, callback, mode)
	Input.Init()

	local bindId = id or Util.RandomString(8)
	if keybinds[bindId] then
		keybinds[bindId].Destroy()
	end

	local resolvedMode = normalizeMode(mode)
	local resolvedKey = Util.ResolveKey(key)

	local entry = {
		Id = bindId,
		Key = resolvedKey,
		Mode = resolvedMode,
		Active = resolvedMode == "Always",
		Callback = callback,
	}

	function entry.SetKey(arg1, arg2)
		local newKey = (arg1 == entry) and arg2 or arg1
		entry.Key = Util.ResolveKey(newKey)
		if entry.Key == nil and entry.Mode == "Hold" and entry.Active then
			entry.Active = false
			Util.Spawn(entry.Callback, false)
		end
	end

	function entry.SetMode(arg1, arg2)
		local newMode = (arg1 == entry) and arg2 or arg1
		local targetMode = normalizeMode(newMode)
		if entry.Mode == targetMode then
			return
		end
		entry.Mode = targetMode
		if targetMode == "Always" then
			if not entry.Active then
				entry.Active = true
				Util.Spawn(entry.Callback, true)
			end
		elseif targetMode == "Hold" and entry.Active then
			entry.Active = false
			Util.Spawn(entry.Callback, false)
		end
	end

	function entry.SetActive(arg1, arg2, arg3)
		local active, silent
		if arg1 == entry then
			active, silent = arg2, arg3
		else
			active, silent = arg1, arg2
		end
		local state = active == true
		if entry.Mode == "Always" then
			state = true
		end
		if entry.Active == state then
			return
		end
		entry.Active = state
		if not silent then
			Util.Spawn(entry.Callback, state)
		end
	end

	function entry.Destroy()
		if keybinds[bindId] == entry then
			keybinds[bindId] = nil
		end
	end

	keybinds[bindId] = entry
	return entry
end

function Input.CancelCapture()
	captureToken += 1
	local pending = captureCallback
	captureCallback = nil

	if captureConn then
		captureConn:Disconnect()
		captureConn = nil
	end
	Input.Capturing = false

	if pending then
		Util.Spawn(pending, nil, true)
	end
end

function Input.CaptureKey(onComplete, opts)
	Input.Init()
	if Input.Capturing then
		Input.CancelCapture()
	end

	opts = opts or {}
	local allowMouse = opts.AllowMouse ~= false
	captureToken += 1
	local myToken = captureToken
	local armed = false

	Input.Capturing = true
	captureCallback = onComplete

	local function finish(result, cancelled)
		if captureToken ~= myToken then
			return
		end
		captureToken += 1
		local cb = captureCallback
		captureCallback = nil
		if captureConn then
			captureConn:Disconnect()
			captureConn = nil
		end
		Input.Capturing = false
		if cb then
			Util.Spawn(cb, result, cancelled)
		end
	end

	-- Defer one frame so the click that opened key capture is not captured
	task.defer(function()
		if captureToken ~= myToken or not Input.Capturing then
			return
		end
		armed = true
	end)

	captureConn = Services.UserInputService.InputBegan:Connect(function(input)
		if not armed or captureToken ~= myToken then
			return
		end

		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Unknown then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				finish(nil, true)
			elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				finish(nil, false)
			else
				finish(input.KeyCode, false)
			end
		elseif allowMouse and (
			input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3
		) then
			finish(input.UserInputType, false)
		end
	end)
end

function Input.BindDrag(handle, target, opts)
	Input.Init()
	target = target or handle
	opts = opts or {}

	local shouldClamp = opts.Clamp ~= false
	local padding = opts.Padding ~= nil and opts.Padding or 8
	local threshold = opts.Threshold or 0
	local dragMaid = Maid.new()

	local dragging = false
	local movedPastThreshold = false
	local activeInput = nil
	local startPointer = Vector2.zero
	local startAbsPos = Vector2.zero

	local function isEnabled()
		if type(opts.Enabled) == "function" then
			return opts.Enabled() ~= false
		elseif opts.Enabled ~= nil then
			return opts.Enabled ~= false
		end
		return true
	end

	local function isMatchingMove(input)
		if not activeInput then
			return false
		end
		if activeInput.UserInputType == Enum.UserInputType.Touch then
			return input == activeInput
		end
		return input.UserInputType == Enum.UserInputType.MouseMovement
	end

	local function isMatchingEnd(input)
		if not activeInput then
			return false
		end
		if activeInput.UserInputType == Enum.UserInputType.Touch then
			return input == activeInput
		end
		return input.UserInputType == Enum.UserInputType.MouseButton1
	end

	local function stopDrag()
		if not dragging then
			return
		end
		dragging = false
		activeInput = nil
		if opts.OnEnd then
			Util.SafeCall(opts.OnEnd, movedPastThreshold)
		end
	end

	local function updatePosition(input)
		if not dragging or not target or not target.Parent then
			stopDrag()
			return
		end

		local current = Vector2.new(input.Position.X, input.Position.Y)
		local delta = current - startPointer
		if not movedPastThreshold then
			if delta.Magnitude < threshold then
				return
			end
			movedPastThreshold = true
			if opts.OnStart then
				Util.SafeCall(opts.OnStart)
			end
		end

		local desiredTopLeft = startAbsPos + delta
		local size = target.AbsoluteSize
		if shouldClamp then
			local vpOrigin, vpSize = getViewportBounds(target)
			local minX = vpOrigin.X + padding
			local minY = vpOrigin.Y + padding
			local maxX = math.max(minX, vpOrigin.X + vpSize.X - size.X - padding)
			local maxY = math.max(minY, vpOrigin.Y + vpSize.Y - size.Y - padding)
			desiredTopLeft = Vector2.new(
				Util.Clamp(desiredTopLeft.X, minX, maxX),
				Util.Clamp(desiredTopLeft.Y, minY, maxY)
			)
		end

		local parent = target.Parent
		local parentPos = (parent and parent:IsA("GuiBase2d")) and parent.AbsolutePosition or Vector2.zero
		local localTopLeft = desiredTopLeft - parentPos
		local anchorPos = localTopLeft + size * target.AnchorPoint
		target.Position = UDim2.fromOffset(math.round(anchorPos.X), math.round(anchorPos.Y))

		if opts.OnDrag then
			Util.SafeCall(opts.OnDrag, target.Position)
		end
	end

	dragMaid:Give(handle.InputBegan:Connect(function(input)
		if not isEnabled() or not Util.IsPointer(input) then
			return
		end
		dragging = true
		movedPastThreshold = threshold <= 0
		activeInput = input
		startPointer = Vector2.new(input.Position.X, input.Position.Y)
		startAbsPos = target.AbsolutePosition
		if movedPastThreshold and opts.OnStart then
			Util.SafeCall(opts.OnStart)
		end
	end))

	dragMaid:Give(Services.UserInputService.InputChanged:Connect(function(input)
		if dragging and isMatchingMove(input) then
			updatePosition(input)
		end
	end))

	dragMaid:Give(Services.UserInputService.InputEnded:Connect(function(input)
		if dragging and isMatchingEnd(input) then
			stopDrag()
		end
	end))

	dragMaid:Give(handle.Destroying:Connect(function()
		dragMaid:Clean()
	end))

	return {
		IsDragging = function()
			return dragging
		end,
		WasMoved = function()
			return movedPastThreshold
		end,
		Destroy = function()
			stopDrag()
			dragMaid:Clean()
		end,
	}
end

function Input.BindResize(grip, target, minSize, maxSize, onResize)
	Input.Init()
	target = target or grip
	minSize = minSize or Vector2.new(460, 360)

	local resizeMaid = Maid.new()
	local resizing = false
	local activeInput = nil
	local startPointer = Vector2.zero
	local startSize = Vector2.zero
	local startAbsPos = Vector2.zero

	local function isMatchingMove(input)
		if not activeInput then
			return false
		end
		if activeInput.UserInputType == Enum.UserInputType.Touch then
			return input == activeInput
		end
		return input.UserInputType == Enum.UserInputType.MouseMovement
	end

	local function isMatchingEnd(input)
		if not activeInput then
			return false
		end
		if activeInput.UserInputType == Enum.UserInputType.Touch then
			return input == activeInput
		end
		return input.UserInputType == Enum.UserInputType.MouseButton1
	end

	local function stopResize()
		if not resizing then
			return
		end
		resizing = false
		activeInput = nil
	end

	local function updateSize(input)
		if not resizing or not target or not target.Parent then
			stopResize()
			return
		end

		local delta = Vector2.new(input.Position.X, input.Position.Y) - startPointer
		local vpOrigin, vpSize = getViewportBounds(target)
		local vpCapX = math.max(minSize.X, (vpOrigin.X + vpSize.X) - startAbsPos.X - 8)
		local vpCapY = math.max(minSize.Y, (vpOrigin.Y + vpSize.Y) - startAbsPos.Y - 8)

		local limitX = maxSize and math.min(maxSize.X, vpCapX) or vpCapX
		local limitY = maxSize and math.min(maxSize.Y, vpCapY) or vpCapY
		limitX = math.max(minSize.X, limitX)
		limitY = math.max(minSize.Y, limitY)

		local newW = math.round(Util.Clamp(startSize.X + delta.X, minSize.X, limitX))
		local newH = math.round(Util.Clamp(startSize.Y + delta.Y, minSize.Y, limitY))
		local newSize = Vector2.new(newW, newH)

		target.Size = UDim2.fromOffset(newW, newH)

		-- Keep top-left corner fixed regardless of AnchorPoint
		if target.AnchorPoint ~= Vector2.zero then
			local parent = target.Parent
			local parentPos = (parent and parent:IsA("GuiBase2d")) and parent.AbsolutePosition or Vector2.zero
			local localTopLeft = startAbsPos - parentPos
			local anchorPos = localTopLeft + newSize * target.AnchorPoint
			target.Position = UDim2.fromOffset(math.round(anchorPos.X), math.round(anchorPos.Y))
		end

		if onResize then
			Util.SafeCall(onResize, newSize)
		end
	end

	resizeMaid:Give(grip.InputBegan:Connect(function(input)
		if not Util.IsPointer(input) then
			return
		end
		resizing = true
		activeInput = input
		startPointer = Vector2.new(input.Position.X, input.Position.Y)
		startSize = target.AbsoluteSize
		startAbsPos = target.AbsolutePosition
	end))

	resizeMaid:Give(Services.UserInputService.InputChanged:Connect(function(input)
		if resizing and isMatchingMove(input) then
			updateSize(input)
		end
	end))

	resizeMaid:Give(Services.UserInputService.InputEnded:Connect(function(input)
		if resizing and isMatchingEnd(input) then
			stopResize()
		end
	end))

	resizeMaid:Give(grip.Destroying:Connect(function()
		resizeMaid:Clean()
	end))

	return {
		IsResizing = function()
			return resizing
		end,
		Destroy = function()
			stopResize()
			resizeMaid:Clean()
		end,
	}
end

function Input.Destroy()
	Input.CancelCapture()
	for _, entry in pairs(keybinds) do
		if type(entry.Destroy) == "function" then
			entry.Destroy()
		end
	end
	table.clear(keybinds)
	rootMaid:Clean()
	initialized = false
end

return Input
