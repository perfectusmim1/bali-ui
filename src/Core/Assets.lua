--[[
	Bali UI · Core/Assets
	Materialises the embedded PNG assets (icon atlas, glow, shadow, grain) via the executor
	file API + getcustomasset, verifies they load, and exposes graceful fallbacks.
]]

local Services = require("Core/Services")
local Util = require("Core/Util")
local Data = require("Generated/AssetData")

local Assets = {
	Loaded = false,
	Available = false, -- true when the custom image pipeline works on this executor
	Images = {},
	Folder = "Bali/Assets",
}

-- Fallbacks hosted on Roblox (used when custom assets are unavailable)
Assets.Fallback = {
	Shadow = { Image = "rbxassetid://6014261993", Slice = Rect.new(49, 49, 450, 450), Inset = 24 },
}

-- ─── Base64 ──────────────────────────────────────────────────────────────────

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local lookup = {}
for index = 1, #alphabet do
	lookup[string.byte(alphabet, index)] = index - 1
end

local function decodeLua(input)
	input = string.gsub(input, "[^%w%+/=]", "")
	local out = {}
	local chunk = {}
	local length = #input
	local byte = string.byte
	local char = string.char
	local floor = math.floor
	for index = 1, length, 4 do
		local a, b, c, d = byte(input, index, index + 3)
		local va, vb = lookup[a] or 0, lookup[b] or 0
		local vc, vd = lookup[c], lookup[d]
		local n = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
		local b1 = floor(n / 65536) % 256
		local b2 = floor(n / 256) % 256
		local b3 = n % 256
		if c == 61 or vc == nil then
			chunk[#chunk + 1] = char(b1)
		elseif d == 61 or vd == nil then
			chunk[#chunk + 1] = char(b1, b2)
		else
			chunk[#chunk + 1] = char(b1, b2, b3)
		end
		if #chunk >= 2048 then
			out[#out + 1] = table.concat(chunk)
			table.clear(chunk)
		end
	end
	out[#out + 1] = table.concat(chunk)
	return table.concat(out)
end

function Assets.Decode(input)
	local candidates = {}
	local crypt = Util.Global("crypt")
	if type(crypt) == "table" then
		table.insert(candidates, crypt.base64decode)
		table.insert(candidates, crypt.base64_decode)
		if type(crypt.base64) == "table" then
			table.insert(candidates, crypt.base64.decode)
		end
	end
	table.insert(candidates, Util.Global("base64_decode"))
	table.insert(candidates, Util.Global("base64decode"))
	for _, fn in ipairs(candidates) do
		if type(fn) == "function" then
			local ok, result = pcall(fn, input)
			-- PNG signature check guards against decoders that return something unexpected
			if ok and type(result) == "string" and string.sub(result, 2, 4) == "PNG" then
				return result
			end
		end
	end
	return decodeLua(input)
end

-- ─── Loading ─────────────────────────────────────────────────────────────────

local function getAssetFunction()
	return Util.Global("getcustomasset") or Util.Global("getsynasset")
end

local function verify(contentId)
	local ContentProvider = Services.ContentProvider
	local probe = Instance.new("ImageLabel")
	probe.Image = contentId
	local status = nil
	local done = false
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ probe }, function(_, fetchStatus)
				status = fetchStatus
			end)
		end)
		if not ok then
			status = nil
		end
		done = true
	end)
	local started = os.clock()
	while not done and os.clock() - started < 3 do
		task.wait()
	end
	probe:Destroy()
	-- Optimistic: only an explicit failure disables the custom image pipeline
	return status ~= Enum.AssetFetchStatus.Failure and status ~= Enum.AssetFetchStatus.TimedOut
end

function Assets.Load()
	if Assets.Loaded then
		return Assets.Available
	end
	Assets.Loaded = true

	local getAsset = getAssetFunction()
	if type(getAsset) ~= "function" or not Util.FS.Supported() then
		return false
	end

	local ok = pcall(function()
		Util.FS.MakeFolder(Assets.Folder)
		local sources = {
			Atlas = Data.Atlas.Data,
			Glow = Data.Glow,
			Shadow = Data.Shadow,
			Noise = Data.Noise,
			Glass = Data.Glass,
			Banner = Data.Banner,
		}
		for name, payload in pairs(sources) do
			local path = string.format("%s/%s_v%s.png", Assets.Folder, name, Data.Version)
			if not Util.FS.IsFile(path) then
				Util.FS.Write(path, Assets.Decode(payload))
			end
			local id = getAsset(path)
			if type(id) == "string" and id ~= "" then
				Assets.Images[name] = id
			end
		end
	end)

	if ok and Assets.Images.Atlas and verify(Assets.Images.Atlas) then
		Assets.Available = true
	else
		Assets.Images = {}
		Assets.Available = false
	end
	return Assets.Available
end

function Assets.Get(name)
	return Assets.Images[name]
end

-- Shadow descriptor { Image, Slice, Inset } (inset = transparent margin around the shape)
function Assets.Shadow()
	if Assets.Images.Shadow then
		return { Image = Assets.Images.Shadow, Slice = Rect.new(64, 64, 96, 96), Inset = 40 }
	end
	return Assets.Fallback.Shadow
end

Assets.Data = Data

return Assets
