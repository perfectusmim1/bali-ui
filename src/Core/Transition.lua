--[[
	Lumina UI · Core/Transition
	Reusable micro-interactions and mount/unmount animations respecting Tween.Speed and Tween.Reduced.
]]

local Services = require("Core/Services")
local Tween = require("Core/Tween")
local Theme = require("Core/Theme")
local Util = require("Core/Util")

local Transition = {}

local function getOrCreateScale(frame)
	local scale = frame:FindFirstChild("_LuminaScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end
	local existing = frame:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	scale = Instance.new("UIScale")
	scale.Name = "_LuminaScale"
	scale.Scale = 1
	scale.Parent = frame
	return scale
end

local function bumpAnimId(frame)
	local nextId = (frame:GetAttribute("_LuminaAnimId") or 0) + 1
	frame:SetAttribute("_LuminaAnimId", nextId)
	return nextId
end

local function captureTransparency(frame)
	if frame:IsA("CanvasGroup") then
		local saved = frame:GetAttribute("_LuminaRestGroupTrans")
		if saved == nil or not frame:GetAttribute("_LuminaUnmounted") then
			saved = frame.GroupTransparency
			if saved >= 0.99 and frame:GetAttribute("_LuminaRestGroupTrans") ~= nil then
				saved = frame:GetAttribute("_LuminaRestGroupTrans")
			elseif saved >= 0.99 then
				saved = 0
			end
			frame:SetAttribute("_LuminaRestGroupTrans", saved)
		end
		return "GroupTransparency", saved
	elseif frame:IsA("GuiObject") then
		local saved = frame:GetAttribute("_LuminaRestBgTrans")
		if saved == nil or not frame:GetAttribute("_LuminaUnmounted") then
			saved = frame.BackgroundTransparency
			frame:SetAttribute("_LuminaRestBgTrans", saved)
		end
		return "BackgroundTransparency", saved
	end
	return nil, 1
end

function Transition.Mount(frame, scaleFrom)
	if not frame then
		return nil
	end

	local animId = bumpAnimId(frame)
	local scale = getOrCreateScale(frame)
	local transProp, targetTrans = captureTransparency(frame)
	frame:SetAttribute("_LuminaUnmounted", false)
	frame.Visible = true

	if Tween.Reduced then
		scale.Scale = 1
		if transProp then
			frame[transProp] = targetTrans
		end
		return nil
	end

	scale.Scale = scaleFrom or 0.94
	local scaleTween = Tween.Spring(scale, { Scale = 1 }, Tween.Normal)

	if transProp and targetTrans < 1 then
		frame[transProp] = 1
		Tween.Play(frame, { [transProp] = targetTrans }, Tween.Fast, Enum.EasingStyle.Quad)
	end

	Tween.Then(scaleTween, function()
		if frame.Parent and frame:GetAttribute("_LuminaAnimId") == animId then
			scale.Scale = 1
		end
	end)

	return scaleTween
end

function Transition.Unmount(frame, scaleTo, onDone)
	if not frame then
		if onDone then
			Util.SafeCall(onDone)
		end
		return nil
	end

	local animId = bumpAnimId(frame)
	local scale = getOrCreateScale(frame)
	local transProp, restTrans = captureTransparency(frame)
	frame:SetAttribute("_LuminaUnmounted", true)

	if Tween.Reduced then
		scale.Scale = 1
		if transProp and restTrans < 1 then
			frame[transProp] = restTrans
		end
		if onDone then
			Util.SafeCall(onDone)
		else
			frame.Visible = false
		end
		return nil
	end

	local targetScale = scaleTo or 0.94
	local scaleTween = Tween.Play(scale, { Scale = targetScale }, Tween.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

	if transProp and restTrans < 1 then
		Tween.Play(frame, { [transProp] = 1 }, Tween.Fast, Enum.EasingStyle.Quad)
	end

	Tween.Then(scaleTween, function()
		if frame:GetAttribute("_LuminaAnimId") ~= animId then
			return
		end
		if onDone then
			Util.SafeCall(onDone)
		elseif frame.Parent then
			frame.Visible = false
		end
	end)

	return scaleTween
end

function Transition.Ripple(btn, inputOrPos, colorKey)
	if not btn or Tween.Reduced then
		return nil
	end

	local absPos = btn.AbsolutePosition
	local absSize = btn.AbsoluteSize
	if absSize.X <= 0 or absSize.Y <= 0 then
		return nil
	end

	local localX, localY
	if typeof(inputOrPos) == "Vector2" then
		localX = inputOrPos.X - absPos.X
		localY = inputOrPos.Y - absPos.Y
	elseif typeof(inputOrPos) == "InputObject" then
		localX = inputOrPos.Position.X - absPos.X
		localY = inputOrPos.Position.Y - absPos.Y
	else
		localX = absSize.X * 0.5
		localY = absSize.Y * 0.5
	end

	localX = Util.Clamp(localX, 0, absSize.X)
	localY = Util.Clamp(localY, 0, absSize.Y)

	local clip = btn:FindFirstChild("_LuminaRippleClip")
	if not clip then
		clip = Instance.new("Frame")
		clip.Name = "_LuminaRippleClip"
		clip.BackgroundTransparency = 1
		clip.BorderSizePixel = 0
		clip.Size = UDim2.fromScale(1, 1)
		clip.ClipsDescendants = true
		clip.ZIndex = btn.ZIndex + 1

		local sourceCorner = btn:FindFirstChildOfClass("UICorner")
		if sourceCorner then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = sourceCorner.CornerRadius
			corner.Parent = clip
		end
		clip.Parent = btn
	end

	local resolved = Theme.Resolve(colorKey or "Stroke")
	local color = typeof(resolved) == "Color3" and resolved or Theme.Current.Text

	local circle = Instance.new("Frame")
	circle.Name = "Ripple"
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromOffset(localX, localY)
	circle.Size = UDim2.fromOffset(0, 0)
	circle.BackgroundColor3 = color
	circle.BackgroundTransparency = 0.78
	circle.BorderSizePixel = 0
	circle.ZIndex = clip.ZIndex
	circle.Parent = clip

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle

	local maxSpan = math.max(absSize.X, absSize.Y) * 2.2
	local diameter = math.max(maxSpan, 36)
	local tween = Tween.Play(
		circle,
		{
			Size = UDim2.fromOffset(diameter, diameter),
			BackgroundTransparency = 1,
		},
		Tween.Smooth,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	Tween.Then(tween, function()
		if circle.Parent then
			circle:Destroy()
		end
		if clip.Parent and #clip:GetChildren() <= 1 then
			-- keep clip if only UICorner remains? Destroy empty clip to keep instance tree clean
			local hasRipple = false
			for _, child in ipairs(clip:GetChildren()) do
				if child:IsA("GuiObject") then
					hasRipple = true
					break
				end
			end
			if not hasRipple then
				clip:Destroy()
			end
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

function Transition.SlideFade(frame, offsetY)
	if not frame then
		return nil
	end

	local animId = bumpAnimId(frame)
	local yOffset = offsetY ~= nil and offsetY or 10
	local transProp, targetTrans = captureTransparency(frame)
	frame:SetAttribute("_LuminaUnmounted", false)
	frame.Visible = true

	local targetPos = frame:GetAttribute("_LuminaSlideTargetPos")
	if typeof(targetPos) ~= "UDim2" then
		targetPos = frame.Position
		frame:SetAttribute("_LuminaSlideTargetPos", targetPos)
	end

	local parentLayout = frame.Parent and (frame.Parent:FindFirstChildOfClass("UIListLayout") or frame.Parent:FindFirstChildOfClass("UIGridLayout"))
	if Tween.Reduced then
		if not parentLayout then
			frame.Position = targetPos
		end
		if transProp then
			frame[transProp] = targetTrans
		end
		return nil
	end

	local mainTween
	if not parentLayout then
		frame.Position = UDim2.new(
			targetPos.X.Scale,
			targetPos.X.Offset,
			targetPos.Y.Scale,
			targetPos.Y.Offset + yOffset
		)
		mainTween = Tween.Play(frame, { Position = targetPos }, Tween.Normal, Enum.EasingStyle.Quint)
	else
		local scale = getOrCreateScale(frame)
		scale.Scale = 0.96
		mainTween = Tween.Play(scale, { Scale = 1 }, Tween.Normal, Enum.EasingStyle.Quint)
	end

	if transProp and targetTrans < 1 then
		frame[transProp] = 1
		Tween.Play(frame, { [transProp] = targetTrans }, Tween.Fast, Enum.EasingStyle.Quad)
	end

	Tween.Then(mainTween, function()
		if frame.Parent and frame:GetAttribute("_LuminaAnimId") == animId then
			frame:SetAttribute("_LuminaSlideTargetPos", nil)
		end
	end)

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
