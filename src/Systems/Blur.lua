--[[
	Bali UI · Systems/Blur
	Safely manages a dedicated Lighting BlurEffect synchronized with UI open state.
]]

local Services = require("Core/Services")
local Tween = require("Core/Tween")
local Util = require("Core/Util")

local Blur = {}

local enabled = true
local intensity = 8
local isOpen = false
local blurEffect = nil
local activeTween = nil
local tweenToken = 0

local function getLighting()
	local ok, lighting = pcall(function()
		return Services.Lighting
	end)
	return ok and lighting or nil
end

local function ensureEffect()
	if blurEffect and blurEffect.Parent then
		return blurEffect
	end
	local lighting = getLighting()
	if not lighting then
		return nil
	end
	local legacy = lighting:FindFirstChild("LuminaBlur")
	if legacy and legacy:IsA("BlurEffect") then
		pcall(function()
			legacy:Destroy()
		end)
	end
	local existing = lighting:FindFirstChild("BaliBlur")
	if existing and existing:IsA("BlurEffect") then
		blurEffect = existing
		return blurEffect
	end
	local created
	pcall(function()
		created = Instance.new("BlurEffect")
		created.Name = "BaliBlur"
		created.Size = 0
		created.Enabled = false
		created.Parent = lighting
	end)
	blurEffect = created
	return blurEffect
end

local function sync()
	tweenToken += 1
	local myToken = tweenToken

	if activeTween then
		pcall(function()
			activeTween:Cancel()
		end)
		activeTween = nil
	end

	local shouldShow = enabled and isOpen and intensity > 0
	if shouldShow then
		local effect = ensureEffect()
		if not effect then
			return
		end
		effect.Enabled = true
		if Tween.Reduced then
			effect.Size = intensity
		else
			activeTween = Tween.Play(effect, { Size = intensity }, Tween.Normal, Enum.EasingStyle.Quad)
		end
	else
		if not blurEffect or not blurEffect.Parent then
			return
		end
		local effect = blurEffect
		if Tween.Reduced then
			effect.Size = 0
			effect.Enabled = false
		else
			local tween = Tween.Play(effect, { Size = 0 }, Tween.Fast, Enum.EasingStyle.Quad)
			activeTween = tween
			Tween.Then(tween, function()
				if tweenToken == myToken and effect.Parent then
					effect.Enabled = false
				end
			end)
		end
	end
end

function Blur.SetEnabled(state)
	enabled = state == true
	sync()
end

function Blur.SetIntensity(value)
	intensity = Util.Clamp(tonumber(value) or 0, 0, 56)
	sync()
end

function Blur.SetOpen(state)
	isOpen = state == true
	sync()
end

function Blur.IsEnabled()
	return enabled
end

function Blur.GetIntensity()
	return intensity
end

function Blur.Destroy()
	tweenToken += 1
	if activeTween then
		pcall(function()
			activeTween:Cancel()
		end)
		activeTween = nil
	end
	if blurEffect then
		pcall(function()
			blurEffect:Destroy()
		end)
		blurEffect = nil
	end
end

return Blur
