--[[
	Bali UI · Core/Transition
	Reusable micro-interactions and mount/unmount animations respecting Tween.Speed and Tween.Reduced.
	Uses crisp layout-safe fades and slides without UIScale bitmap text blurring.
]]

local Services = require("Core/Services")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Util = require("Core/Util")

local Transition = {}

local function bumpAnimId(frame)
	local nextId = (frame:GetAttribute("_BaliAnimId") or 0) + 1
	frame:SetAttribute("_BaliAnimId", nextId)
	return nextId
end

function Transition.IsOverlayBlocking(guiObj)
	if not guiObj or typeof(guiObj) ~= "Instance" then
		return false
	end
	local cur = guiObj
	local screenGui = nil
	local inPopup = false
	local inDialog = false
	local inCmdPalette = false
	while cur do
		local name = cur.Name
		if name == "BaliDialogLayer" then
			inDialog = true
			screenGui = cur.Parent
		elseif name == "BaliCommandPaletteBackdrop" then
			inCmdPalette = true
		elseif name == "BaliPopupLayer" then
			inPopup = true
			screenGui = cur.Parent
		elseif (name == "BaliMainLayer" or name == "BaliHUDLayer") and not screenGui then
			screenGui = cur.Parent
		end
		if cur:IsA("ScreenGui") then
			screenGui = cur
			break
		end
		cur = cur.Parent
	end
	if not screenGui then
		return false
	end
	local dialogLayer = screenGui:FindFirstChild("BaliDialogLayer")
	if dialogLayer and dialogLayer.Visible ~= false then
		local dialogBackdrop = dialogLayer:FindFirstChild("DialogBackdrop")
		if dialogBackdrop and dialogBackdrop.Visible ~= false and dialogBackdrop.Active ~= false and not dialogBackdrop:GetAttribute("_BaliClosing") then
			return not inDialog
		end
	end
	local popupLayer = screenGui:FindFirstChild("BaliPopupLayer")
	if popupLayer and popupLayer.Visible ~= false then
		local cmdBackdrop = popupLayer:FindFirstChild("BaliCommandPaletteBackdrop")
		if cmdBackdrop and cmdBackdrop.Visible and cmdBackdrop.Active ~= false and not cmdBackdrop:GetAttribute("_BaliClosing") then
			return (not inCmdPalette) and (not inDialog)
		end
		local popupBackdrop = popupLayer:FindFirstChild("PopupBackdrop")
		if popupBackdrop and popupBackdrop.Visible and popupBackdrop.Active ~= false then
			return (not inPopup) and (not inDialog)
		end
	end
	return false
end

local function collectFadeEntries(root)
	if root:IsA("CanvasGroup") then
		local saved = root:GetAttribute("_BaliRestGroupTrans")
		if saved == nil or (not root:GetAttribute("_BaliUnmounted") and not root:GetAttribute("_BaliFadingIn")) then
			saved = root.GroupTransparency
			if saved >= 0.995 and root:GetAttribute("_BaliRestGroupTrans") ~= nil then
				saved = root:GetAttribute("_BaliRestGroupTrans")
			end
			root:SetAttribute("_BaliRestGroupTrans", saved)
		end
		if saved < 0.995 then
			return { { Inst = root, Prop = "GroupTransparency", Target = saved, IsContent = false } }
		end
		return {}
	end

	local refresh = not root:GetAttribute("_BaliUnmounted") and not root:GetAttribute("_BaliFadingIn")
	local entries = {}

	local function isForegroundContent(inst, prop)
		if prop == "TextTransparency" then
			return true
		end
		if prop == "ImageTransparency" then
			local n = inst.Name
			return inst ~= root
				and n ~= "Shadow"
				and n ~= "Glow"
				and n ~= "GlowTop"
				and n ~= "GlowBottom"
				and n ~= "GlowLeft"
				and n ~= "GlowRight"
				and n ~= "Noise"
				and n ~= "GlassSheen"
				and n ~= "Picture"
				and n ~= "WindowShadow"
				and n ~= "GlowTopLeft"
				and n ~= "GlowBottomRight"
		end
		return false
	end

	local function record(inst, prop, attrName)
		local val = inst:GetAttribute(attrName)
		if refresh or val == nil then
			local cur = inst[prop]
			if cur >= 0.995 and val ~= nil and not refresh then
				-- Keep earlier resting transparency if already fading out
				cur = val
			end
			val = cur
			inst:SetAttribute(attrName, val)
		end
		if val < 0.995 then
			table.insert(entries, {
				Inst = inst,
				Prop = prop,
				Target = val,
				IsContent = isForegroundContent(inst, prop),
			})
		end
	end

	local function scan(inst)
		if inst:IsA("GuiObject") then
			record(inst, "BackgroundTransparency", "_BaliRestBg")
		end
		if inst:IsA("ScrollingFrame") then
			record(inst, "ScrollBarImageTransparency", "_BaliRestBar")
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			record(inst, "TextTransparency", "_BaliRestTxt")
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			record(inst, "ImageTransparency", "_BaliRestImg")
		elseif inst:IsA("UIStroke") then
			record(inst, "Transparency", "_BaliRestStr")
		end
	end

	scan(root)
	for _, desc in ipairs(root:GetDescendants()) do
		if desc.Name ~= "_BaliRippleWash" then
			scan(desc)
		end
	end

	return entries
end

local function invalidateCascadeTree(root)
	if not root then
		return
	end
	if root:IsA("ScrollingFrame") or root:GetAttribute("_BaliCascadeSeq") ~= nil then
		root:SetAttribute("_BaliCascadeSeq", (root:GetAttribute("_BaliCascadeSeq") or 0) + 1)
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("ScrollingFrame") or desc:GetAttribute("_BaliCascadeSeq") ~= nil then
			desc:SetAttribute("_BaliCascadeSeq", (desc:GetAttribute("_BaliCascadeSeq") or 0) + 1)
		end
	end
end

local function isAncestorHidden(inst, stopAt)
	local cur = inst
	while cur and cur ~= game do
		if cur:IsA("GuiObject") then
			if not cur.Visible or cur:GetAttribute("_BaliUnmounted") == true then
				return true
			end
		elseif cur:IsA("LayerCollector") then
			if not cur.Enabled then
				return true
			end
			break
		end
		if stopAt and cur == stopAt then
			break
		end
		cur = cur.Parent
	end
	return false
end

local function hasLayoutSiblingController(frame)
	local parent = frame and frame.Parent
	if not parent then
		return false
	end
	return parent:FindFirstChildOfClass("UIListLayout") ~= nil
		or parent:FindFirstChildOfClass("UIGridLayout") ~= nil
end

function Transition.Mount(frame, _scaleFrom, opts)
	if not frame then
		return nil
	end

	local noPos = type(opts) == "table" and opts.NoPositionTween == true
	local animId = bumpAnimId(frame)
	invalidateCascadeTree(frame)
	local entries = collectFadeEntries(frame)
	local controlled = noPos or hasLayoutSiblingController(frame)

	local targetPos = frame:GetAttribute("_BaliMountTargetPos")
	if typeof(targetPos) ~= "UDim2" then
		targetPos = frame.Position
		if not noPos then
			frame:SetAttribute("_BaliMountTargetPos", targetPos)
		end
	end

	frame:SetAttribute("_BaliUnmounted", false)
	frame:SetAttribute("_BaliFadingIn", true)
	frame.Visible = true

	if Tween.Reduced then
		if not controlled then
			frame.Position = targetPos
		end
		for _, entry in ipairs(entries) do
			if entry.Inst and entry.Inst.Parent then
				entry.Inst[entry.Prop] = entry.Target
			end
		end
		frame:SetAttribute("_BaliFadingIn", false)
		frame:SetAttribute("_BaliMountTargetPos", nil)
		return nil
	end

	local mainTween = nil
	if not controlled then
		frame.Position = UDim2.new(
			targetPos.X.Scale,
			targetPos.X.Offset,
			targetPos.Y.Scale,
			targetPos.Y.Offset + 8
		)
		mainTween = Tween.Play(frame, { Position = targetPos }, Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end

	for _, entry in ipairs(entries) do
		local inst = entry.Inst
		if inst and inst.Parent then
			inst[entry.Prop] = math.max(entry.Target, entry.IsContent and 0.94 or 0.88)
			local t = Tween.Play(
				inst,
				{ [entry.Prop] = entry.Target },
				entry.IsContent and Tween.Normal or Tween.Fast,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out
			)
			if not mainTween then
				mainTween = t
			end
		end
	end

	if mainTween then
		Tween.Then(mainTween, function()
			if frame.Parent and frame:GetAttribute("_BaliAnimId") == animId then
				frame:SetAttribute("_BaliFadingIn", false)
				frame:SetAttribute("_BaliMountTargetPos", nil)
			end
		end)
	else
		frame:SetAttribute("_BaliFadingIn", false)
		frame:SetAttribute("_BaliMountTargetPos", nil)
	end

	return mainTween
end

function Transition.Unmount(frame, _scaleTo, onDone, opts)
	if not frame then
		if onDone then
			Util.SafeCall(onDone)
		end
		return nil
	end

	local noPos = type(opts) == "table" and opts.NoPositionTween == true
	local animId = bumpAnimId(frame)
	invalidateCascadeTree(frame)
	local entries = collectFadeEntries(frame)
	local controlled = noPos or hasLayoutSiblingController(frame)

	local targetPos = frame:GetAttribute("_BaliMountTargetPos")
	if typeof(targetPos) ~= "UDim2" then
		targetPos = frame.Position
		if not noPos then
			frame:SetAttribute("_BaliMountTargetPos", targetPos)
		end
	end

	frame:SetAttribute("_BaliFadingIn", false)
	frame:SetAttribute("_BaliUnmounted", true)

	local function finishUnmount()
		if frame:GetAttribute("_BaliAnimId") ~= animId then
			return
		end
		if not onDone and frame.Parent then
			frame.Visible = false
		end
		if frame.Parent and not controlled then
			frame.Position = targetPos
		end
		frame:SetAttribute("_BaliMountTargetPos", nil)
		if onDone then
			Util.SafeCall(onDone)
		end
		if frame.Parent then
			frame:SetAttribute("_BaliUnmounted", false)
			-- Restore resting transparencies only after hiding/onDone so text never flashes back
			if not frame.Visible then
				for _, entry in ipairs(entries) do
					if entry.Inst and entry.Inst.Parent then
						entry.Inst[entry.Prop] = entry.Target
					end
				end
			end
		end
	end

	if Tween.Reduced then
		finishUnmount()
		return nil
	end

	local mainTween = nil
	if not controlled then
		mainTween = Tween.Play(frame, {
			Position = UDim2.new(
				targetPos.X.Scale,
				targetPos.X.Offset,
				targetPos.Y.Scale,
				targetPos.Y.Offset + 6
			),
		}, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end

	local contentDur = math.max(Tween.Fast * 0.58, 0.06)
	for _, entry in ipairs(entries) do
		local inst = entry.Inst
		if inst and inst.Parent then
			local dur = entry.IsContent and contentDur or Tween.Fast
			local style = Enum.EasingStyle.Quint
			local dir = Enum.EasingDirection.Out
			local t = Tween.Play(inst, { [entry.Prop] = 1 }, dur, style, dir)
			if not entry.IsContent then
				mainTween = t
			elseif not mainTween then
				mainTween = t
			end
		end
	end

	if mainTween then
		Tween.Then(mainTween, finishUnmount)
	else
		finishUnmount()
	end

	return mainTween
end

function Transition.Ripple(btn, _inputOrPos, colorKey)
	if not btn or Tween.Reduced then
		return nil
	end

	local absSize = btn.AbsoluteSize
	if absSize.X <= 0 or absSize.Y <= 0 then
		return nil
	end

	local hasLayoutController = btn:FindFirstChildOfClass("UIListLayout") ~= nil
		or btn:FindFirstChildOfClass("UIGridLayout") ~= nil
		or btn.AutomaticSize ~= Enum.AutomaticSize.None

	local resolved = Theme.Resolve(colorKey or "Stroke")
	local color = typeof(resolved) == "Color3" and resolved or Theme.Current.Text

	if hasLayoutController then
		-- Never inject a Scale(1,1) child inside layout-driven / AutomaticSize buttons (breaks size measurement).
		local strokeObj = btn:FindFirstChildOfClass("UIStroke")
		if strokeObj and strokeObj.Parent then
			local restTrans = btn:GetAttribute("_BaliRippleRestStrokeTrans")
			if restTrans == nil then
				restTrans = strokeObj.Transparency
				btn:SetAttribute("_BaliRippleRestStrokeTrans", restTrans)
			end
			local restColor = btn:GetAttribute("_BaliRippleRestStrokeColor")
			if typeof(restColor) ~= "Color3" then
				restColor = strokeObj.Color
				btn:SetAttribute("_BaliRippleRestStrokeColor", restColor)
			end
			strokeObj.Color = color
			strokeObj.Transparency = math.min(restTrans, 0.28)
			local tw = Tween.Play(strokeObj, { Color = restColor, Transparency = restTrans }, Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween.Then(tw, function()
				if btn.Parent then
					btn:SetAttribute("_BaliRippleRestStrokeTrans", nil)
					btn:SetAttribute("_BaliRippleRestStrokeColor", nil)
				end
			end)
			return tw
		end
		local restBg = btn:GetAttribute("_BaliRippleRestBgTrans")
		if restBg == nil then
			restBg = btn.BackgroundTransparency
			btn:SetAttribute("_BaliRippleRestBgTrans", restBg)
		end
		if restBg < 0.95 then
			btn.BackgroundTransparency = math.max(0, restBg - 0.14)
			local tw = Tween.Play(btn, { BackgroundTransparency = restBg }, Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween.Then(tw, function()
				if btn.Parent then
					btn:SetAttribute("_BaliRippleRestBgTrans", nil)
				end
			end)
			return tw
		end
		return nil
	end

	local existing = btn:FindFirstChild("_BaliRippleWash")
	if existing then
		existing:Destroy()
	end

	local wash = Instance.new("Frame")
	wash.Name = "_BaliRippleWash"
	wash.Position = UDim2.fromScale(0, 0)
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = color
	wash.BackgroundTransparency = 0.84
	wash.BorderSizePixel = 0
	wash.ZIndex = btn.ZIndex + 1

	local sourceCorner = btn:FindFirstChildOfClass("UICorner")
	if sourceCorner then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = sourceCorner.CornerRadius
		corner.Parent = wash
	end

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(color)
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	grad.Offset = Vector2.new(-0.35, 0)
	grad.Parent = wash

	wash.Parent = btn

	Tween.Play(grad, { Offset = Vector2.new(0.35, 0) }, Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local tween = Tween.Play(
		wash,
		{ BackgroundTransparency = 1 },
		Tween.Normal,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)

	Tween.Then(tween, function()
		if wash.Parent then
			wash:Destroy()
		end
	end)

	return tween
end

function Transition.Hover(hit, surface, normalKey, hoverKey, strokeObj)
	if not hit then
		return function() end
	end
	surface = surface or hit

	local hovered = false
	local cleaned = false
	local baseStrokeTrans = strokeObj and strokeObj.Transparency or nil

	local function resolveColor(key)
		local resolved = Theme.Resolve(key)
		return typeof(resolved) == "Color3" and resolved or nil
	end

	local function resolveBaseStrokeTrans()
		if not strokeObj then
			return nil
		end
		if baseStrokeTrans ~= nil then
			return baseStrokeTrans
		end
		return strokeObj.Transparency
	end

	local function applyHoverState(isHover, animate)
		local targetColor = resolveColor(isHover and hoverKey or normalKey)
		if targetColor then
			if animate then
				Tween.Play(surface, { BackgroundColor3 = targetColor }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			else
				surface.BackgroundColor3 = targetColor
			end
		end

		if strokeObj and strokeObj.Parent then
			local restTrans = resolveBaseStrokeTrans()
			if restTrans ~= nil then
				local targetTrans = isHover and math.max(restTrans - 0.08, 0) or restTrans
				if animate then
					Tween.Play(strokeObj, { Transparency = targetTrans }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
				else
					strokeObj.Transparency = targetTrans
				end
			end
		end
	end

	-- Bind resting color so theme switches keep the surface synchronized
	if type(normalKey) == "string" or type(normalKey) == "function" then
		Theme.Bind(surface, { BackgroundColor3 = normalKey })
	else
		applyHoverState(false, false)
	end

	local connections = {}

	table.insert(connections, hit.MouseEnter:Connect(function()
		if cleaned or Util.IsTouchDevice() or Transition.IsOverlayBlocking(hit) then
			return
		end
		if strokeObj and baseStrokeTrans == nil then
			baseStrokeTrans = strokeObj.Transparency
		end
		hovered = true
		applyHoverState(true, true)
	end))

	table.insert(connections, hit.MouseLeave:Connect(function()
		if cleaned then
			return
		end
		hovered = false
		applyHoverState(false, true)
	end))

	table.insert(connections, Theme.Changed:Connect(function()
		if cleaned then
			return
		end
		if strokeObj and strokeObj.Parent and not hovered then
			baseStrokeTrans = strokeObj.Transparency
		end
		if hovered then
			applyHoverState(true, false)
		end
	end))

	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		for _, conn in ipairs(connections) do
			pcall(function()
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				elseif type(conn) == "table" and type(conn.Disconnect) == "function" then
					conn.Disconnect()
				end
			end)
		end
		table.clear(connections)
	end

	table.insert(connections, hit.Destroying:Connect(cleanup))

	return cleanup
end

function Transition.SlideFade(frame, offsetY, offsetX)
	if not frame then
		return nil
	end

	local animId = bumpAnimId(frame)
	invalidateCascadeTree(frame)
	local yOffset = offsetY ~= nil and offsetY or 6
	local xOffset = offsetX or 0
	local entries = collectFadeEntries(frame)
	frame:SetAttribute("_BaliUnmounted", false)
	frame:SetAttribute("_BaliFadingIn", true)
	frame.Visible = true

	local targetPos = frame:GetAttribute("_BaliSlideTargetPos")
	if typeof(targetPos) ~= "UDim2" then
		targetPos = frame.Position
		frame:SetAttribute("_BaliSlideTargetPos", targetPos)
	end

	local parentLayout = hasLayoutSiblingController(frame)
	if Tween.Reduced then
		if not parentLayout then
			frame.Position = targetPos
		end
		for _, entry in ipairs(entries) do
			if entry.Inst and entry.Inst.Parent then
				entry.Inst[entry.Prop] = entry.Target
			end
		end
		frame:SetAttribute("_BaliFadingIn", false)
		frame:SetAttribute("_BaliSlideTargetPos", nil)
		return nil
	end

	local mainTween
	if not parentLayout then
		frame.Position = UDim2.new(
			targetPos.X.Scale,
			targetPos.X.Offset + xOffset,
			targetPos.Y.Scale,
			targetPos.Y.Offset + yOffset
		)
		mainTween = Tween.Play(frame, { Position = targetPos }, Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end

	for _, entry in ipairs(entries) do
		local inst = entry.Inst
		if inst and inst.Parent then
			inst[entry.Prop] = math.min(1, math.max(entry.Target + 0.12, 0.92))
			local fadeTween = Tween.Play(inst, { [entry.Prop] = entry.Target }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			if not mainTween then
				mainTween = fadeTween
			end
		end
	end

	if mainTween then
		Tween.Then(mainTween, function()
			if frame.Parent and frame:GetAttribute("_BaliAnimId") == animId then
				frame:SetAttribute("_BaliFadingIn", false)
				frame:SetAttribute("_BaliSlideTargetPos", nil)
			end
		end)
	else
		frame:SetAttribute("_BaliFadingIn", false)
		frame:SetAttribute("_BaliSlideTargetPos", nil)
	end

	return mainTween
end

function Transition.Pulse(inst, prop, fromVal, toVal, period)
	if not inst or not prop then
		return function() end
	end

	if Tween.Reduced then
		pcall(function()
			inst[prop] = toVal
		end)
		return function() end
	end

	pcall(function()
		inst[prop] = fromVal
	end)

	local halfPeriod = math.max(((period or 1.2) * 0.5) * Tween.Speed, 0.05)
	local info = TweenInfo.new(halfPeriod, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = Services.TweenService:Create(inst, info, { [prop] = toVal })
	tween:Play()

	local stopped = false
	local destroyConn

	local function stop()
		if stopped then
			return
		end
		stopped = true
		if destroyConn then
			destroyConn:Disconnect()
			destroyConn = nil
		end
		pcall(function()
			tween:Cancel()
		end)
		pcall(function()
			if inst.Parent then
				inst[prop] = fromVal
			end
		end)
	end

	local ok, conn = pcall(function()
		return inst.Destroying:Connect(stop)
	end)
	if ok then
		destroyConn = conn
	end

	return stop
end

-- Rayfield-inspired sequential staggered reveal inside ScrollingFrames / containers.
-- Never uses UIScale or mutates UIListLayout sibling sizes, keeping fonts razor sharp.
local function collectCascadeTargets(container, out, limit)
	for _, child in ipairs(container:GetChildren()) do
		if #out >= limit then
			return
		end
		if child:IsA("GuiObject") and child.Visible then
			local name = child.Name
			if name ~= "_BaliRippleWash" then
				if child:IsA("Frame") and (name == "ColumnRow" or name == "LeftColumn" or name == "RightColumn") then
					collectCascadeTargets(child, out, limit)
				else
					table.insert(out, child)
				end
			end
		end
	end
end

local function snapshotVisualProps(root)
	local refresh = not root:GetAttribute("_BaliCascading")
	local entries = {}
	local function addInst(inst)
		if inst:IsA("GuiObject") then
			if refresh or inst:GetAttribute("_BaliCascadeBg") == nil then
				local rest = inst:GetAttribute("_BaliRestBg")
				inst:SetAttribute("_BaliCascadeBg", rest ~= nil and rest or inst.BackgroundTransparency)
			end
			table.insert(entries, { Inst = inst, Prop = "BackgroundTransparency", Target = inst:GetAttribute("_BaliCascadeBg"), IsContent = false })
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			if refresh or inst:GetAttribute("_BaliCascadeTxt") == nil then
				local rest = inst:GetAttribute("_BaliRestTxt")
				inst:SetAttribute("_BaliCascadeTxt", rest ~= nil and rest or inst.TextTransparency)
			end
			table.insert(entries, { Inst = inst, Prop = "TextTransparency", Target = inst:GetAttribute("_BaliCascadeTxt"), IsContent = true })
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			if refresh or inst:GetAttribute("_BaliCascadeImg") == nil then
				local rest = inst:GetAttribute("_BaliRestImg")
				inst:SetAttribute("_BaliCascadeImg", rest ~= nil and rest or inst.ImageTransparency)
			end
			local n = inst.Name
			local isForeground = (n ~= "Shadow" and n ~= "WindowShadow" and n ~= "Glow" and n ~= "GlowTop" and n ~= "GlowBottom" and n ~= "GlowLeft" and n ~= "GlowRight" and n ~= "GlowTopLeft" and n ~= "GlowBottomRight" and n ~= "Noise" and n ~= "GlassSheen" and n ~= "Picture")
			table.insert(entries, { Inst = inst, Prop = "ImageTransparency", Target = inst:GetAttribute("_BaliCascadeImg"), IsContent = isForeground })
		elseif inst:IsA("UIStroke") then
			if refresh or inst:GetAttribute("_BaliCascadeStroke") == nil then
				local rest = inst:GetAttribute("_BaliRestStr")
				inst:SetAttribute("_BaliCascadeStroke", rest ~= nil and rest or inst.Transparency)
			end
			table.insert(entries, { Inst = inst, Prop = "Transparency", Target = inst:GetAttribute("_BaliCascadeStroke"), IsContent = false })
		end
	end

	addInst(root)
	for _, desc in ipairs(root:GetDescendants()) do
		if desc.Name ~= "_BaliRippleWash" then
			addInst(desc)
		end
	end
	return entries
end

function Transition.Cascade(container, stepDelay, maxItems, slideOffsetX)
	if not container then
		return nil
	end

	local seq = (container:GetAttribute("_BaliCascadeSeq") or 0) + 1
	container:SetAttribute("_BaliCascadeSeq", seq)

	if Tween.Reduced then
		return nil
	end

	if slideOffsetX and slideOffsetX ~= 0 and not hasLayoutSiblingController(container) then
		local restPos = container:GetAttribute("_BaliSlideTargetPos")
		if typeof(restPos) ~= "UDim2" then
			restPos = container.Position
			container:SetAttribute("_BaliSlideTargetPos", restPos)
		end
		container.Position = UDim2.new(
			restPos.X.Scale,
			restPos.X.Offset + slideOffsetX,
			restPos.Y.Scale,
			restPos.Y.Offset
		)
		local slideTw = Tween.Play(container, { Position = restPos }, Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		if slideTw then
			Tween.Then(slideTw, function()
				if container.Parent and container:GetAttribute("_BaliCascadeSeq") == seq then
					container:SetAttribute("_BaliSlideTargetPos", nil)
				end
			end)
		end
	end

	local targets = {}
	collectCascadeTargets(container, targets, maxItems or 14)
	if #targets == 0 then
		return nil
	end

	local step = stepDelay or 0.02
	for index, card in ipairs(targets) do
		local props = snapshotVisualProps(card)
		card:SetAttribute("_BaliCascading", true)
		for _, entry in ipairs(props) do
			if entry.Target < 1 then
				entry.Inst[entry.Prop] = math.max(entry.Target, entry.IsContent and 0.92 or 0.85)
			end
		end

		local delaySec = math.min((index - 1) * step, 0.22)
		local function reveal()
			if container:GetAttribute("_BaliCascadeSeq") ~= seq then
				if not container.Parent or isAncestorHidden(card) then
					card:SetAttribute("_BaliCascading", false)
					for _, entry in ipairs(props) do
						if entry.Inst.Parent and entry.Target < 1 then
							entry.Inst[entry.Prop] = entry.Target
						end
					end
				end
				return
			end
			card:SetAttribute("_BaliCascading", false)
			if not container.Parent or isAncestorHidden(card) then
				for _, entry in ipairs(props) do
					if entry.Inst.Parent and entry.Target < 1 then
						entry.Inst[entry.Prop] = entry.Target
					end
				end
				return
			end
			for _, entry in ipairs(props) do
				if entry.Inst.Parent and entry.Target < 1 then
					Tween.Play(
						entry.Inst,
						{ [entry.Prop] = entry.Target },
						entry.IsContent and Tween.Normal or Tween.Fast,
						Enum.EasingStyle.Quint,
						Enum.EasingDirection.Out
					)
				end
			end
		end

		if delaySec <= 0 then
			reveal()
		else
			task.delay(delaySec, reveal)
		end
	end

	return seq
end

function Transition.RestoreCascade(container)
	if not container then
		return
	end
	container:SetAttribute("_BaliCascadeSeq", (container:GetAttribute("_BaliCascadeSeq") or 0) + 1)
	local restPos = container:GetAttribute("_BaliSlideTargetPos")
	if typeof(restPos) == "UDim2" then
		container.Position = restPos
		container:SetAttribute("_BaliSlideTargetPos", nil)
	end
	local function restoreInst(inst)
		if inst:IsA("GuiObject") then
			if inst:GetAttribute("_BaliCascading") then
				inst:SetAttribute("_BaliCascading", false)
			end
			local bg = inst:GetAttribute("_BaliCascadeBg")
			if bg ~= nil then
				inst.BackgroundTransparency = bg
			end
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			local txt = inst:GetAttribute("_BaliCascadeTxt")
			if txt ~= nil then
				inst.TextTransparency = txt
			end
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			local img = inst:GetAttribute("_BaliCascadeImg")
			if img ~= nil then
				inst.ImageTransparency = img
			end
		elseif inst:IsA("UIStroke") then
			local str = inst:GetAttribute("_BaliCascadeStroke")
			if str ~= nil then
				inst.Transparency = str
			end
		end
	end
	restoreInst(container)
	for _, desc in ipairs(container:GetDescendants()) do
		restoreInst(desc)
	end
end

return Transition
