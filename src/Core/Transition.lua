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

local function captureTransparency(frame)
	if frame:IsA("CanvasGroup") then
		local saved = frame:GetAttribute("_BaliRestGroupTrans")
		if saved == nil or not frame:GetAttribute("_BaliUnmounted") then
			saved = frame.GroupTransparency
			if saved >= 0.99 and frame:GetAttribute("_BaliRestGroupTrans") ~= nil then
				saved = frame:GetAttribute("_BaliRestGroupTrans")
			elseif saved >= 0.99 then
				saved = 0
			end
			frame:SetAttribute("_BaliRestGroupTrans", saved)
		end
		return "GroupTransparency", saved
	elseif frame:IsA("GuiObject") then
		local saved = frame:GetAttribute("_BaliRestBgTrans")
		if saved == nil or not frame:GetAttribute("_BaliUnmounted") then
			saved = frame.BackgroundTransparency
			frame:SetAttribute("_BaliRestBgTrans", saved)
		end
		return "BackgroundTransparency", saved
	end
	return nil, 1
end

local function captureStrokeTransparency(frame)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return nil, 1
	end
	local saved = stroke:GetAttribute("_BaliRestStrokeTrans")
	if saved == nil or not frame:GetAttribute("_BaliUnmounted") then
		saved = stroke.Transparency
		if saved >= 0.99 and stroke:GetAttribute("_BaliRestStrokeTrans") ~= nil then
			saved = stroke:GetAttribute("_BaliRestStrokeTrans")
		end
		stroke:SetAttribute("_BaliRestStrokeTrans", saved)
	end
	return stroke, saved
end

local function hasLayoutSiblingController(frame)
	local parent = frame and frame.Parent
	if not parent then
		return false
	end
	return parent:FindFirstChildOfClass("UIListLayout") ~= nil
		or parent:FindFirstChildOfClass("UIGridLayout") ~= nil
end

function Transition.Mount(frame, _scaleFrom)
	if not frame then
		return nil
	end

	local animId = bumpAnimId(frame)
	local transProp, targetTrans = captureTransparency(frame)
	local stroke, targetStrokeTrans = captureStrokeTransparency(frame)
	local controlled = hasLayoutSiblingController(frame)

	local targetPos = frame:GetAttribute("_BaliMountTargetPos")
	if typeof(targetPos) ~= "UDim2" then
		targetPos = frame.Position
		frame:SetAttribute("_BaliMountTargetPos", targetPos)
	end

	frame:SetAttribute("_BaliUnmounted", false)
	frame.Visible = true

	if Tween.Reduced then
		if not controlled then
			frame.Position = targetPos
		end
		if transProp then
			frame[transProp] = targetTrans
		end
		if stroke then
			stroke.Transparency = targetStrokeTrans
		end
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
		mainTween = Tween.Play(frame, { Position = targetPos }, Tween.Normal, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	end

	if transProp and targetTrans < 1 then
		frame[transProp] = math.max(targetTrans, 0.92)
		local fadeTween = Tween.Play(frame, { [transProp] = targetTrans }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		mainTween = mainTween or fadeTween
	end

	if stroke and targetStrokeTrans < 1 then
		stroke.Transparency = 1
		local strokeTween = Tween.Play(stroke, { Transparency = targetStrokeTrans }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		mainTween = mainTween or strokeTween
	end

	if mainTween then
		Tween.Then(mainTween, function()
			if frame.Parent and frame:GetAttribute("_BaliAnimId") == animId then
				frame:SetAttribute("_BaliMountTargetPos", nil)
			end
		end)
	else
		frame:SetAttribute("_BaliMountTargetPos", nil)
	end

	return mainTween
end

function Transition.Unmount(frame, _scaleTo, onDone)
	if not frame then
		if onDone then
			Util.SafeCall(onDone)
		end
		return nil
	end

	local animId = bumpAnimId(frame)
	local transProp, restTrans = captureTransparency(frame)
	local stroke, restStrokeTrans = captureStrokeTransparency(frame)
	local controlled = hasLayoutSiblingController(frame)

	local targetPos = frame:GetAttribute("_BaliMountTargetPos")
	if typeof(targetPos) ~= "UDim2" then
		targetPos = frame.Position
		frame:SetAttribute("_BaliMountTargetPos", targetPos)
	end

	frame:SetAttribute("_BaliUnmounted", true)

	if Tween.Reduced then
		if not controlled then
			frame.Position = targetPos
		end
		if transProp and restTrans < 1 then
			frame[transProp] = restTrans
		end
		if stroke and restStrokeTrans < 1 then
			stroke.Transparency = restStrokeTrans
		end
		frame:SetAttribute("_BaliMountTargetPos", nil)
		if onDone then
			Util.SafeCall(onDone)
		else
			frame.Visible = false
		end
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
		}, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end

	if transProp and restTrans < 1 then
		local fadeTween = Tween.Play(frame, { [transProp] = 1 }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		mainTween = mainTween or fadeTween
	end

	if stroke and restStrokeTrans < 1 then
		Tween.Play(stroke, { Transparency = 1 }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	Tween.Then(mainTween, function()
		if frame:GetAttribute("_BaliAnimId") ~= animId then
			return
		end
		if frame.Parent and not controlled then
			frame.Position = targetPos
		end
		frame:SetAttribute("_BaliMountTargetPos", nil)
		if transProp and restTrans < 1 and frame.Parent then
			frame[transProp] = restTrans
		end
		if stroke and restStrokeTrans < 1 and stroke.Parent then
			stroke.Transparency = restStrokeTrans
		end
		if onDone then
			Util.SafeCall(onDone)
		elseif frame.Parent then
			frame.Visible = false
		end
	end)

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

	local existing = btn:FindFirstChild("_BaliRippleWash")
	if existing then
		existing:Destroy()
	end

	local resolved = Theme.Resolve(colorKey or "Stroke")
	local color = typeof(resolved) == "Color3" and resolved or Theme.Current.Text

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

	Tween.Play(grad, { Offset = Vector2.new(0.35, 0) }, Tween.Normal, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	local tween = Tween.Play(
		wash,
		{ BackgroundTransparency = 1 },
		Tween.Normal,
		Enum.EasingStyle.Quad,
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
				Tween.Play(surface, { BackgroundColor3 = targetColor }, Tween.Fast, Enum.EasingStyle.Quad)
			else
				surface.BackgroundColor3 = targetColor
			end
		end

		if strokeObj and strokeObj.Parent then
			local restTrans = resolveBaseStrokeTrans()
			if restTrans ~= nil then
				local targetTrans = isHover and math.max(restTrans - 0.08, 0) or restTrans
				if animate then
					Tween.Play(strokeObj, { Transparency = targetTrans }, Tween.Fast, Enum.EasingStyle.Quad)
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
		if cleaned or Util.IsTouchDevice() then
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
		if strokeObj and strokeObj.Parent then
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
	local yOffset = offsetY ~= nil and offsetY or 6
	local xOffset = offsetX or 0
	local transProp, targetTrans = captureTransparency(frame)
	frame:SetAttribute("_BaliUnmounted", false)
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
		if transProp then
			frame[transProp] = targetTrans
		end
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
		mainTween = Tween.Play(frame, { Position = targetPos }, Tween.Normal, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	end

	if transProp and targetTrans < 1 then
		frame[transProp] = math.min(1, math.max(targetTrans + 0.12, 0.92))
		local fadeTween = Tween.Play(frame, { [transProp] = targetTrans }, Tween.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		mainTween = mainTween or fadeTween
	end

	if mainTween then
		Tween.Then(mainTween, function()
			if frame.Parent and frame:GetAttribute("_BaliAnimId") == animId then
				frame:SetAttribute("_BaliSlideTargetPos", nil)
			end
		end)
	else
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

return Transition
