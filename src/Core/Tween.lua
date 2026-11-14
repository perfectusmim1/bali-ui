--[[
	Bali UI · Core/Tween
	Centralised tweening with cached TweenInfo, global speed and Reduce Motion support.
]]

local Services = require("Core/Services")

local Tween = {
	Speed = 1, -- global multiplier (Settings -> Animation Speed)
	Reduced = false, -- Reduce Motion: near-instant transitions

	-- Durations (snappy 120Hz Apple-style deceleration timings)
	Instant = 0.07,
	Fast = 0.14,
	Normal = 0.22,
	Smooth = 0.32,
	Slow = 0.45,
}

local infoCache = {}

local function getInfo(duration, style, direction, delayTime)
	local key = string.format("%.3f|%s|%s|%.3f", duration, style.Name, direction.Name, delayTime or 0)
	local info = infoCache[key]
	if not info then
		info = TweenInfo.new(duration, style, direction, 0, false, delayTime or 0)
		infoCache[key] = info
	end
	return info
end

local function scale(duration)
	if Tween.Reduced then
		return 0.01
	end
	return math.max((duration or Tween.Normal) * Tween.Speed, 0.01)
end

-- Tween.Play(instance, { Prop = value }, duration?, style?, direction?, delay?)
function Tween.Play(instance, properties, duration, style, direction, delayTime)
	local tween = Services.TweenService:Create(
		instance,
		getInfo(scale(duration), style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out, delayTime),
		properties
	)
	tween:Play()
	return tween
end

-- Crisp Apple-style fluid deceleration used for knobs, popovers, pills and panels (no overshoot)
function Tween.Spring(instance, properties, duration)
	return Tween.Play(instance, properties, duration or Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
end

function Tween.Linear(instance, properties, duration)
	-- linear tweens are used for timers; they ignore Reduce Motion so timing stays correct
	local tween = Services.TweenService:Create(
		instance,
		getInfo(math.max(duration, 0.01), Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		properties
	)
	tween:Play()
	return tween
end

-- Runs `callback` when the tween completes (or immediately for nil)
function Tween.Then(tween, callback)
	if not tween then
		callback()
		return
	end
	local connection
	connection = tween.Completed:Connect(function(state)
		connection:Disconnect()
		if state == Enum.PlaybackState.Completed then
			callback()
		end
	end)
end

-- Animates a number from -> to, calling onStep(value) each frame. Returns a cancel function.
function Tween.Number(from, to, duration, onStep, onDone)
	local holder = Instance.new("NumberValue")
	holder.Value = from
	local connection = holder:GetPropertyChangedSignal("Value"):Connect(function()
		onStep(holder.Value)
	end)
	local tween = Tween.Play(holder, { Value = to }, duration or Tween.Slow, Enum.EasingStyle.Quint)
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		holder:Destroy()
	end
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			onStep(to)
			if onDone then
				onDone()
			end
		end
		finish()
	end)
	return function()
		tween:Cancel()
		finish()
	end
end

return Tween
