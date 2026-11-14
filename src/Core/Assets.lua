--[[
	Bali UI · Core/Assets
	Materialises the embedded PNG assets (icon atlas, glow, shadow, grain) via the executor
	file API + getcustomasset, verifies they load, and exposes graceful fallbacks.
]]

local Util = require("Core/Util")
local Data = require("Generated/AssetData")

local Assets = {
	Loaded = false,
	Available = false, -- true when the custom image pipeline works on this executor
	FontsLoaded = false,
	Images = {},
	Fonts = {},
	Folder = "Bali/Assets",
	FontsFolder = "Bali/Fonts",
	OnFontsUpdated = nil,
}

-- Procedural shadow silhouette fallback is handled without external rbxassetid:// fetches
Assets.Fallback = {
	Shadow = { Image = "", Slice = Rect.new(49, 49, 450, 450), Inset = 24 },
}

-- Verified static-weight TTF mirrors served via HTTPS CDNs/proxies (never rbxassetid://)
local FONT_WEIGHT_META = {
	{ Name = "Regular", Weight = 400 },
	{ Name = "Medium", Weight = 500 },
	{ Name = "SemiBold", Weight = 600 },
	{ Name = "Bold", Weight = 700 },
}

local FONT_SOURCES = {
	Builder = {
		Regular = {
			"https://fonts.gstatic.com/s/plusjakartasans/v12/LDIbaomQNQcsA88c7O9yZ4KMCoOg4IA6-91aHEjcWuA_qU7NSg.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf",
		},
		Medium = {
			"https://fonts.gstatic.com/s/plusjakartasans/v12/LDIbaomQNQcsA88c7O9yZ4KMCoOg4IA6-91aHEjcWuA_m07NSg.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf",
		},
		SemiBold = {
			"https://fonts.gstatic.com/s/plusjakartasans/v12/LDIbaomQNQcsA88c7O9yZ4KMCoOg4IA6-91aHEjcWuA_d0nNSg.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf",
		},
		Bold = {
			"https://fonts.gstatic.com/s/plusjakartasans/v12/LDIbaomQNQcsA88c7O9yZ4KMCoOg4IA6-91aHEjcWuA_TknNSg.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf",
		},
	},
	Gotham = {
		Regular = {
			"https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfMZg.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf",
		},
		Medium = {
			"https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuI6fMZg.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf",
		},
		SemiBold = {
			"https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuGKYMZg.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf",
		},
		Bold = {
			"https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuFuYMZg.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf",
		},
	},
	Montserrat = {
		Regular = {
			"https://fonts.gstatic.com/s/montserrat/v31/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtr6Ew-.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/montserrat/Montserrat%5Bwght%5D.ttf",
		},
		Medium = {
			"https://fonts.gstatic.com/s/montserrat/v31/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtZ6Ew-.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/montserrat/Montserrat%5Bwght%5D.ttf",
		},
		SemiBold = {
			"https://fonts.gstatic.com/s/montserrat/v31/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCu170w-.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/montserrat/Montserrat%5Bwght%5D.ttf",
		},
		Bold = {
			"https://fonts.gstatic.com/s/montserrat/v31/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCuM70w-.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/montserrat/Montserrat%5Bwght%5D.ttf",
		},
	},
	Ubuntu = {
		Regular = {
			"https://fonts.gstatic.com/s/ubuntu/v21/4iCs6KVjbNBYlgo6eA.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ufl/ubuntu/Ubuntu-Regular.ttf",
		},
		Medium = {
			"https://fonts.gstatic.com/s/ubuntu/v21/4iCv6KVjbNBYlgoCjC3Ttw.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ufl/ubuntu/Ubuntu-Medium.ttf",
		},
		SemiBold = {
			"https://fonts.gstatic.com/s/ubuntu/v21/4iCv6KVjbNBYlgoCxCvTtw.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ufl/ubuntu/Ubuntu-Bold.ttf",
		},
		Bold = {
			"https://fonts.gstatic.com/s/ubuntu/v21/4iCv6KVjbNBYlgoCxCvTtw.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ufl/ubuntu/Ubuntu-Bold.ttf",
		},
	},
	Nunito = {
		Regular = {
			"https://fonts.gstatic.com/s/nunito/v32/XRXI3I6Li01BKofiOc5wtlZ2di8HDLshRTM.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/nunito/Nunito%5Bwght%5D.ttf",
		},
		Medium = {
			"https://fonts.gstatic.com/s/nunito/v32/XRXI3I6Li01BKofiOc5wtlZ2di8HDIkhRTM.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/nunito/Nunito%5Bwght%5D.ttf",
		},
		SemiBold = {
			"https://fonts.gstatic.com/s/nunito/v32/XRXI3I6Li01BKofiOc5wtlZ2di8HDGUmRTM.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/nunito/Nunito%5Bwght%5D.ttf",
		},
		Bold = {
			"https://fonts.gstatic.com/s/nunito/v32/XRXI3I6Li01BKofiOc5wtlZ2di8HDFwmRTM.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/nunito/Nunito%5Bwght%5D.ttf",
		},
	},
	Mono = {
		Regular = {
			"https://fonts.gstatic.com/s/robotomono/v31/L0xuDF4xlVMF-BfR8bXMIhJHg45mwgGEFl0_3vqPQw.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/robotomono/RobotoMono%5Bwght%5D.ttf",
		},
		Medium = {
			"https://fonts.gstatic.com/s/robotomono/v31/L0xuDF4xlVMF-BfR8bXMIhJHg45mwgGEFl0_7PqPQw.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/robotomono/RobotoMono%5Bwght%5D.ttf",
		},
		SemiBold = {
			"https://fonts.gstatic.com/s/robotomono/v31/L0xuDF4xlVMF-BfR8bXMIhJHg45mwgGEFl0_Of2PQw.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/robotomono/RobotoMono%5Bwght%5D.ttf",
		},
		Bold = {
			"https://fonts.gstatic.com/s/robotomono/v31/L0xuDF4xlVMF-BfR8bXMIhJHg45mwgGEFl0_Of2PQw.ttf",
			"https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/robotomono/RobotoMono%5Bwght%5D.ttf",
		},
	},
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

local function hasExecutorHttp()
	local synTbl = Util.Global("syn")
	local httpTbl = Util.Global("http")
	local fluxusTbl = Util.Global("fluxus")
	return type(type(synTbl) == "table" and synTbl.request) == "function"
		or type(type(httpTbl) == "table" and httpTbl.request) == "function"
		or type(Util.Global("http_request")) == "function"
		or type(Util.Global("request")) == "function"
		or type(type(fluxusTbl) == "table" and fluxusTbl.request) == "function"
end

local function isValidPngBytes(bytes)
	return type(bytes) == "string" and #bytes > 24 and string.sub(bytes, 1, 8) == "\137PNG\r\n\26\n"
end

local function isValidFontBytes(bytes)
	if type(bytes) ~= "string" or #bytes < 64 then
		return false
	end
	local sig = string.sub(bytes, 1, 4)
	return sig == "\000\001\000\000" or sig == "OTTO" or sig == "true" or sig == "ttcf"
end

local function verify(path, contentId)
	-- Validate local file presence and URI locally without ContentProvider:PreloadAsync (avoids PreloadAsync hooks)
	return type(contentId) == "string"
		and #contentId > 0
		and not string.find(contentId, "^rbxassetid://")
		and Util.FS.IsFile(path)
end

local function jsonStringEscape(str)
	local s = tostring(str or "")
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, '"', '\\"')
	return '"' .. s .. '"'
end

local function buildFontFamilyJson(familyName, faces)
	local items = {}
	for _, face in ipairs(faces) do
		table.insert(
			items,
			string.format(
				'{"name":%s,"weight":%d,"style":"normal","assetId":%s}',
				jsonStringEscape(face.name),
				face.weight,
				jsonStringEscape(face.assetId)
			)
		)
	end
	return string.format('{"name":%s,"faces":[%s]}', jsonStringEscape(familyName), table.concat(items, ","))
end

function Assets.MaterializeFontFamily(familyName, facesData)
	local getAsset = getAssetFunction()
	if type(getAsset) ~= "function" or not Util.FS.Supported() then
		return nil
	end

	Util.FS.MakeFolder(Assets.FontsFolder)
	local faceEntries = {}
	for _, meta in ipairs(FONT_WEIGHT_META) do
		local weightName = meta.Name
		local ttfPath = string.format("%s/%s_%s_v%s.ttf", Assets.FontsFolder, familyName, weightName, Data.Version)
		local provided = type(facesData) == "table" and facesData[weightName] or nil
		if isValidFontBytes(provided) then
			if not Util.FS.IsFile(ttfPath) then
				Util.FS.Write(ttfPath, provided)
			end
		end
		if Util.FS.IsFile(ttfPath) then
			local okId, ttfAsset = pcall(getAsset, ttfPath)
			if okId and type(ttfAsset) == "string" and ttfAsset ~= "" then
				table.insert(faceEntries, {
					name = weightName,
					weight = meta.Weight,
					assetId = ttfAsset,
				})
			end
		end
	end

	if #faceEntries == 0 then
		return nil
	end

	local jsonPath = string.format("%s/%s_v%s.json", Assets.FontsFolder, familyName, Data.Version)
	local jsonBody = buildFontFamilyJson(familyName, faceEntries)
	Util.FS.Write(jsonPath, jsonBody)

	local okFam, familyAsset = pcall(getAsset, jsonPath)
	if okFam and verify(jsonPath, familyAsset) then
		local okFont, testFont = pcall(function()
			return Font.new(familyAsset, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
		end)
		if okFont and testFont then
			Assets.Fonts[familyName] = familyAsset
			return familyAsset
		end
	end
	return nil
end

local function loadCachedFontsSync()
	local getAsset = getAssetFunction()
	if type(getAsset) ~= "function" or not Util.FS.Supported() then
		return false
	end
	local anyLoaded = false
	for familyName in pairs(FONT_SOURCES) do
		local jsonPath = string.format("%s/%s_v%s.json", Assets.FontsFolder, familyName, Data.Version)
		if Util.FS.IsFile(jsonPath) then
			-- Ensure at least Regular TTF also exists locally
			local regPath = string.format("%s/%s_Regular_v%s.ttf", Assets.FontsFolder, familyName, Data.Version)
			if Util.FS.IsFile(regPath) then
				-- Refresh JSON descriptors in case session custom-asset prefix changed
				local refreshed = Assets.MaterializeFontFamily(familyName, nil)
				if refreshed then
					anyLoaded = true
				end
			end
		end
	end
	return anyLoaded
end

local fontsHydrating = false
function Assets.LoadFontsAsync(priorityList)
	if fontsHydrating or not hasExecutorHttp() then
		return
	end
	local getAsset = getAssetFunction()
	if type(getAsset) ~= "function" or not Util.FS.Supported() then
		return
	end

	fontsHydrating = true
	Util.Spawn(function()
		pcall(function()
			Util.FS.MakeFolder(Assets.FontsFolder)
			local order = priorityList or { "Builder", "Gotham", "Mono", "Montserrat", "Ubuntu", "Nunito" }
			for _, familyName in ipairs(order) do
				if not Assets.Fonts[familyName] and FONT_SOURCES[familyName] then
					local facesData = {}
					local downloadedAny = false
					local weightUrls = FONT_SOURCES[familyName]
					for _, meta in ipairs(FONT_WEIGHT_META) do
						local weightName = meta.Name
						local ttfPath = string.format("%s/%s_%s_v%s.ttf", Assets.FontsFolder, familyName, weightName, Data.Version)
						if Util.FS.IsFile(ttfPath) then
							downloadedAny = true
						else
							local candidates = weightUrls[weightName]
							if type(candidates) == "table" then
								for _, url in ipairs(candidates) do
									local body = Util.HttpGet(url, false, true)
									if isValidFontBytes(body) then
										Util.FS.Write(ttfPath, body)
										facesData[weightName] = body
										downloadedAny = true
										break
									end
								end
							end
						end
					end
					if downloadedAny then
						local famAsset = Assets.MaterializeFontFamily(familyName, facesData)
						if famAsset and type(Assets.OnFontsUpdated) == "function" then
							pcall(Assets.OnFontsUpdated, familyName, famAsset)
						end
					end
				end
			end
			Assets.FontsLoaded = true
		end)
		fontsHydrating = false
	end)
end

function Assets.LoadFonts(syncOnly)
	loadCachedFontsSync()
	if not syncOnly then
		Assets.LoadFontsAsync()
	end
	return Assets.Fonts
end

function Assets.GetFontFamily(name)
	return Assets.Fonts[name]
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

	local atlasPath = string.format("%s/%s_v%s.png", Assets.Folder, "Atlas", Data.Version)
	local ok = pcall(function()
		Util.FS.MakeFolder(Assets.Folder)
		local sources = {
			Atlas = Data.Atlas.Data,
			Glow = Data.Glow,
			Shadow = Data.Shadow,
			Noise = Data.Noise,
			Glass = Data.Glass,
			Banner = Data.Banner,
			Logo = Data.Logo,
		}
		for name, payload in pairs(sources) do
			local path = string.format("%s/%s_v%s.png", Assets.Folder, name, Data.Version)
			if not Util.FS.IsFile(path) then
				local raw = Assets.Decode(payload)
				if isValidPngBytes(raw) then
					Util.FS.Write(path, raw)
				end
			end
			if Util.FS.IsFile(path) then
				local id = getAsset(path)
				if type(id) == "string" and id ~= "" then
					Assets.Images[name] = id
				end
			end
		end
	end)

	if ok and Assets.Images.Atlas and verify(atlasPath, Assets.Images.Atlas) then
		Assets.Available = true
	else
		Assets.Images = {}
		Assets.Available = false
	end

	-- Synchronously mount cached on-device fonts and hydrate any missing fonts via proxy CDN
	loadCachedFontsSync()
	Assets.LoadFontsAsync()

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
