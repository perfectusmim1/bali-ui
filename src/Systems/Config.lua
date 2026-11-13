--[[
	Bali UI · Systems/Config
	JSON profile manager with HttpService + pure-Lua JSON fallback, Color3 hex+alpha
	and Enum serialization, autoload support, and optional Theme/Accent/Font/Blur/Watermark sync.
]]

local Services = require("Core/Services")
local Util = require("Core/Util")
local Theme = require("Core/Theme")
local Tween = require("Core/Tween")
local Blur = require("Systems/Blur")
local Watermark = require("Systems/Watermark")
local KeybindList = require("Systems/KeybindList")

local Config = {}

local DEFAULT_FOLDER = "Bali/Configs"
local AUTOLOAD_FILE = "_autoload.txt"

local folder = DEFAULT_FOLDER
local registryRef = nil
local extrasRef = nil
local memoryStore = {}
local memoryAutoLoad = nil

-- ─── Pure-Lua JSON Encoder & Decoder ─────────────────────────────────────────

local encodeEscape = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function encodeString(str)
	local escaped = string.gsub(str, '[%z\1-\31"\\]', function(ch)
		return encodeEscape[ch] or string.format("\\u%04x", string.byte(ch))
	end)
	return '"' .. escaped .. '"'
end

local function isArrayTable(tbl)
	local count = 0
	local maxIndex = 0
	for k in pairs(tbl) do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false, 0
		end
		count += 1
		if k > maxIndex then
			maxIndex = k
		end
	end
	if count == 0 then
		return false, 0
	end
	return count == maxIndex, maxIndex
end

local function luaJsonEncode(val, seen)
	local kind = type(val)
	if val == nil then
		return "null"
	elseif kind == "boolean" then
		return val and "true" or "false"
	elseif kind == "number" then
		if val ~= val or val == math.huge or val == -math.huge then
			return "null"
		end
		return string.format("%.14g", val)
	elseif kind == "string" then
		return encodeString(val)
	elseif kind == "table" then
		seen = seen or {}
		if seen[val] then
			error("Circular reference in JSON encode")
		end
		seen[val] = true

		local isArr, len = isArrayTable(val)
		local out = {}
		if isArr then
			for idx = 1, len do
				out[idx] = luaJsonEncode(val[idx], seen)
			end
			seen[val] = nil
			return "[" .. table.concat(out, ",") .. "]"
		else
			local keys = {}
			for k in pairs(val) do
				if type(k) == "string" or type(k) == "number" then
					table.insert(keys, k)
				end
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in ipairs(keys) do
				table.insert(out, encodeString(tostring(k)) .. ":" .. luaJsonEncode(val[k], seen))
			end
			seen[val] = nil
			return "{" .. table.concat(out, ",") .. "}"
		end
	end
	return "null"
end

local function codepointToUtf8(cp)
	if cp <= 0x7F then
		return string.char(cp)
	elseif cp <= 0x7FF then
		return string.char(
			0xC0 + math.floor(cp / 64),
			0x80 + (cp % 64)
		)
	elseif cp <= 0xFFFF then
		return string.char(
			0xE0 + math.floor(cp / 4096),
			0x80 + (math.floor(cp / 64) % 64),
			0x80 + (cp % 64)
		)
	elseif cp <= 0x10FFFF then
		return string.char(
			0xF0 + math.floor(cp / 262144),
			0x80 + (math.floor(cp / 4096) % 64),
			0x80 + (math.floor(cp / 64) % 64),
			0x80 + (cp % 64)
		)
	end
	return "?"
end

local function luaJsonDecode(str)
	if type(str) ~= "string" then
		error("Expected JSON string")
	end
	local len = #str
	local pos = 1

	local function skipWs()
		local _, nextPos = string.find(str, "^[ \t\r\n]+", pos)
		if nextPos then
			pos = nextPos + 1
		end
	end

	local parseValue

	local function parseString()
		pos += 1 -- skip opening quote
		local buf = {}
		while pos <= len do
			local byte = string.byte(str, pos)
			if byte == 34 then -- '"'
				pos += 1
				return table.concat(buf)
			elseif byte == 92 then -- '\'
				pos += 1
				local esc = string.sub(str, pos, pos)
				if esc == '"' or esc == "\\" or esc == "/" then
					table.insert(buf, esc)
					pos += 1
				elseif esc == "b" then
					table.insert(buf, "\b")
					pos += 1
				elseif esc == "f" then
					table.insert(buf, "\f")
					pos += 1
				elseif esc == "n" then
					table.insert(buf, "\n")
					pos += 1
				elseif esc == "r" then
					table.insert(buf, "\r")
					pos += 1
				elseif esc == "t" then
					table.insert(buf, "\t")
					pos += 1
				elseif esc == "u" then
					local hex = string.sub(str, pos + 1, pos + 4)
					if #hex < 4 or not string.match(hex, "^%x%x%x%x$") then
						error("Invalid unicode escape at position " .. pos)
					end
					local code = tonumber(hex, 16)
					pos += 5
					-- Handle UTF-16 surrogate pairs
					if code >= 0xD800 and code <= 0xDBFF and string.sub(str, pos, pos + 1) == "\\u" then
						local lowHex = string.sub(str, pos + 2, pos + 5)
						local low = string.match(lowHex, "^%x%x%x%x$") and tonumber(lowHex, 16)
						if low and low >= 0xDC00 and low <= 0xDFFF then
							code = 0x10000 + (code - 0xD800) * 1024 + (low - 0xDC00)
							pos += 6
						end
					end
					table.insert(buf, codepointToUtf8(code))
				else
					error("Invalid escape sequence at position " .. pos)
				end
			else
				local nextSpecial = string.find(str, '["\\]', pos)
				if not nextSpecial then
					error("Unterminated string")
				end
				table.insert(buf, string.sub(str, pos, nextSpecial - 1))
				pos = nextSpecial
			end
		end
		error("Unterminated string")
	end

	local function parseNumber()
		local numStr = string.match(str, "^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
		if not numStr or numStr == "" then
			error("Invalid number at position " .. pos)
		end
		local num = tonumber(numStr)
		if num == nil then
			error("Invalid number '" .. numStr .. "' at position " .. pos)
		end
		pos += #numStr
		return num
	end

	local function parseArray()
		pos += 1 -- skip '['
		local arr = {}
		skipWs()
		if string.sub(str, pos, pos) == "]" then
			pos += 1
			return arr
		end
		while pos <= len do
			table.insert(arr, parseValue())
			skipWs()
			local ch = string.sub(str, pos, pos)
			if ch == "]" then
				pos += 1
				return arr
			elseif ch ~= "," then
				error("Expected ',' or ']' in array at position " .. pos)
			end
			pos += 1
		end
		error("Unterminated array")
	end

	local function parseObject()
		pos += 1 -- skip '{'
		local obj = {}
		skipWs()
		if string.sub(str, pos, pos) == "}" then
			pos += 1
			return obj
		end
		while pos <= len do
			skipWs()
			if string.sub(str, pos, pos) ~= '"' then
				error("Expected string key at position " .. pos)
			end
			local key = parseString()
			skipWs()
			if string.sub(str, pos, pos) ~= ":" then
				error("Expected ':' after key at position " .. pos)
			end
			pos += 1
			obj[key] = parseValue()
			skipWs()
			local ch = string.sub(str, pos, pos)
			if ch == "}" then
				pos += 1
				return obj
			elseif ch ~= "," then
				error("Expected ',' or '}' in object at position " .. pos)
			end
			pos += 1
		end
		error("Unterminated object")
	end

	parseValue = function()
		skipWs()
		local ch = string.sub(str, pos, pos)
		if ch == '"' then
			return parseString()
		elseif ch == "{" then
			return parseObject()
		elseif ch == "[" then
			return parseArray()
		elseif ch == "t" and string.sub(str, pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif ch == "f" and string.sub(str, pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif ch == "n" and string.sub(str, pos, pos + 3) == "null" then
			pos += 4
			return nil
		elseif ch == "-" or (ch >= "0" and ch <= "9") then
			return parseNumber()
		end
		error("Unexpected token at position " .. pos)
	end

	local result = parseValue()
	skipWs()
	if pos <= len then
		error("Trailing characters at position " .. pos)
	end
	return result
end

function Config.JsonEncode(tbl)
	local ok, encoded = pcall(function()
		return Services.HttpService:JSONEncode(tbl)
	end)
	if ok and type(encoded) == "string" then
		return encoded
	end
	return luaJsonEncode(tbl)
end

function Config.JsonDecode(str)
	if type(str) ~= "string" or str == "" then
		return nil
	end
	local ok, decoded = pcall(function()
		return Services.HttpService:JSONDecode(str)
	end)
	if ok then
		return decoded
	end
	local fallbackOk, fallbackRes = pcall(luaJsonDecode, str)
	if fallbackOk then
		return fallbackRes
	end
	return nil
end

-- ─── Type Serialization ──────────────────────────────────────────────────────

local function serializeValue(value, extraAlpha)
	local rbxType = typeof(value)
	if rbxType == "Color3" then
		return {
			__type = "Color3",
			Hex = "#" .. Util.ToHex(value),
			Alpha = tonumber(extraAlpha) or 0,
		}
	elseif rbxType == "EnumItem" then
		return tostring(value)
	end

	local luaType = type(value)
	if luaType == "table" then
		local out = {}
		for k, v in pairs(value) do
			if type(k) == "string" or type(k) == "number" then
				local serialized = serializeValue(v)
				if serialized ~= nil then
					out[k] = serialized
				end
			end
		end
		return out
	elseif luaType == "string" or luaType == "number" or luaType == "boolean" then
		return value
	end
	return nil
end

local function resolveEnumString(str)
	local enumType, itemName = string.match(str, "^Enum%.([^%.]+)%.([^%.]+)$")
	if not enumType or not itemName then
		return nil
	end
	local ok, item = pcall(function()
		return Enum[enumType][itemName]
	end)
	return ok and item or nil
end

local function deserializeValue(value)
	local luaType = type(value)
	if luaType == "string" then
		if string.sub(value, 1, 5) == "Enum." then
			local resolved = resolveEnumString(value)
			if resolved then
				return resolved
			end
		end
		return value
	elseif luaType == "table" then
		if value.__type == "Color3" or (type(value.Hex) == "string" and value.Alpha ~= nil) then
			local color = Util.FromHex(value.Hex)
			return color or Color3.new(1, 1, 1), tonumber(value.Alpha) or 0
		end
		local out = {}
		for k, v in pairs(value) do
			local decoded = deserializeValue(v)
			out[k] = decoded
		end
		return out
	end
	return value
end

-- ─── Payload Building & Restoration ──────────────────────────────────────────

local function sanitizeName(name)
	if name == nil then
		return nil
	end
	local clean = Util.Trim(tostring(name))
	clean = string.gsub(clean, "%.json$", "")
	clean = string.gsub(clean, '[<>:"/\\|%?%*%.]+', "_")
	clean = Util.Trim(clean)
	if clean == "" or string.sub(clean, 1, 1) == "_" then
		return nil
	end
	return clean
end

local function ensureFolder()
	if Util.FS.Supported() then
		Util.FS.MakeFolder(folder)
	end
end

local function configPath(safeName)
	return folder .. "/" .. safeName .. ".json"
end

local function autoLoadPath()
	return folder .. "/" .. AUTOLOAD_FILE
end

local function collectPreferences()
	if not extrasRef then
		return nil
	end

	local prefs = {
		Theme = Theme.Name,
		Accent = Theme.AccentOverride and serializeValue(Theme.AccentOverride, 0) or false,
		Font = Theme.FontFamily,
		BackgroundTransparency = Theme.Overrides.BackgroundTransparency,
		AnimationSpeed = Tween.Speed,
		ReduceMotion = Tween.Reduced,
		BlurEnabled = Blur.IsEnabled(),
		BlurIntensity = Blur.GetIntensity(),
		WatermarkVisible = Watermark.IsVisible(),
		KeybindListVisible = KeybindList.IsVisible(),
	}

	if type(extrasRef) == "table" and type(extrasRef.Save) == "function" then
		local ok, custom = Util.SafeCall(extrasRef.Save)
		if ok and type(custom) == "table" then
			prefs.Custom = serializeValue(custom)
		end
	end

	return prefs
end

local function applyPreferences(prefs)
	if not extrasRef or type(prefs) ~= "table" then
		return
	end

	if type(prefs.Theme) == "string" and Theme.Presets[prefs.Theme] then
		Theme.Set(prefs.Theme, true)
	end

	if prefs.Accent == false then
		Theme.SetAccent(nil, true)
	elseif prefs.Accent ~= nil then
		local accentColor = deserializeValue(prefs.Accent)
		if typeof(accentColor) == "Color3" then
			Theme.SetAccent(accentColor, true)
		end
	end

	if type(prefs.Font) == "string" and Theme.Fonts[prefs.Font] then
		Theme.SetFont(prefs.Font)
	end

	if prefs.BackgroundTransparency ~= nil then
		Theme.SetValue("BackgroundTransparency", tonumber(prefs.BackgroundTransparency), true)
	end

	if type(prefs.AnimationSpeed) == "number" then
		Tween.Speed = Util.Clamp(prefs.AnimationSpeed, 0.1, 3)
	end
	if type(prefs.ReduceMotion) == "boolean" then
		Tween.Reduced = prefs.ReduceMotion
	end

	if type(prefs.BlurEnabled) == "boolean" then
		Blur.SetEnabled(prefs.BlurEnabled)
	end
	if type(prefs.BlurIntensity) == "number" then
		Blur.SetIntensity(prefs.BlurIntensity)
	end

	if type(prefs.WatermarkVisible) == "boolean" then
		Watermark.SetVisible(prefs.WatermarkVisible)
	end
	if type(prefs.KeybindListVisible) == "boolean" then
		KeybindList.SetVisible(prefs.KeybindListVisible)
	end

	if type(extrasRef) == "table" then
		if type(extrasRef.Load) == "function" and type(prefs.Custom) == "table" then
			Util.SafeCall(extrasRef.Load, deserializeValue(prefs.Custom))
		end
		if type(extrasRef.OnLoad) == "function" then
			Util.SafeCall(extrasRef.OnLoad, prefs)
		end
	end
end

local function collectFlags()
	local flags = {}
	if type(registryRef) ~= "table" then
		return flags
	end

	for flag, element in pairs(registryRef) do
		if type(element) == "table" and not element.IgnoreConfig then
			local opts = element.Options
			if not (type(opts) == "table" and opts.IgnoreConfig) then
				if element.Type == "ColorPicker" and type(element.Get) == "function" then
					local ok, color, alpha = pcall(element.Get, element)
					if ok and typeof(color) == "Color3" then
						flags[flag] = serializeValue(color, alpha or 0)
					end
				elseif element.Type == "Keybind" and type(element.Get) == "function" then
					local ok, key, mode = pcall(element.Get, element)
					if ok then
						flags[flag] = {
							__type = "Keybind",
							Key = key ~= nil and tostring(key) or "None",
							Mode = mode or "Toggle",
						}
					end
				elseif type(element.Get) == "function" then
					local ok, val, extra = pcall(element.Get, element)
					if ok then
						if typeof(val) == "Color3" then
							flags[flag] = serializeValue(val, extra or 0)
						elseif typeof(val) == "EnumItem" or (extra ~= nil and (extra == "Toggle" or extra == "Hold" or extra == "Always")) then
							flags[flag] = {
								__type = "Keybind",
								Key = val ~= nil and tostring(val) or "None",
								Mode = extra or "Toggle",
							}
						elseif val ~= nil then
							flags[flag] = serializeValue(val)
						end
					end
				elseif element.Value ~= nil then
					flags[flag] = serializeValue(element.Value)
				end
			end
		end
	end

	return flags
end

local function applyFlags(flags)
	if type(registryRef) ~= "table" or type(flags) ~= "table" then
		return
	end

	for flag, raw in pairs(flags) do
		local element = registryRef[flag]
		if type(element) == "table" and not element.IgnoreConfig then
			local opts = element.Options
			if not (type(opts) == "table" and opts.IgnoreConfig) and type(element.Set) == "function" then
				if type(raw) == "table" and raw.__type == "Keybind" then
					local key = nil
					if raw.Key ~= nil and raw.Key ~= "None" and raw.Key ~= "" then
						key = deserializeValue(raw.Key)
						if typeof(key) ~= "EnumItem" then
							key = Util.ResolveKey(raw.Key)
						end
					end
					pcall(element.Set, element, key, raw.Mode)
				elseif type(raw) == "table" and (raw.__type == "Color3" or type(raw.Hex) == "string") then
					local color, alpha = deserializeValue(raw)
					if typeof(color) == "Color3" then
						pcall(element.Set, element, color, alpha)
					end
				else
					local value = deserializeValue(raw)
					pcall(element.Set, element, value)
				end
			end
		end
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function Config.Init(folderName, registry, extras)
	folder = (type(folderName) == "string" and Util.Trim(folderName) ~= "") and Util.Trim(folderName) or DEFAULT_FOLDER
	registryRef = registry
	extrasRef = extras
	ensureFolder()
	return Config
end

function Config.Export()
	local payload = {
		Version = 1,
		Flags = collectFlags(),
	}
	local prefs = collectPreferences()
	if prefs then
		payload.Preferences = prefs
	end
	return Config.JsonEncode(payload)
end

function Config.Import(jsonStr)
	local decoded = Config.JsonDecode(jsonStr)
	if type(decoded) ~= "table" then
		return false, "Invalid JSON config payload"
	end

	if type(decoded.Flags) == "table" then
		applyFlags(decoded.Flags)
		if type(decoded.Preferences) == "table" then
			applyPreferences(decoded.Preferences)
		end
	else
		-- Support flat { Flag = Value } payloads
		applyFlags(decoded)
	end

	return true
end

function Config.Save(name)
	local safeName = sanitizeName(name)
	if not safeName then
		return false, "Invalid config name"
	end

	local json = Config.Export()
	memoryStore[safeName] = json

	if Util.FS.Supported() then
		ensureFolder()
		local ok = Util.FS.Write(configPath(safeName), json)
		if not ok then
			return false, "Failed to write config file"
		end
	end

	return true
end

function Config.Load(name)
	local safeName = sanitizeName(name)
	if not safeName then
		return false, "Invalid config name"
	end

	local raw = nil
	if Util.FS.Supported() and Util.FS.IsFile(configPath(safeName)) then
		raw = Util.FS.Read(configPath(safeName))
	end
	if not raw then
		raw = memoryStore[safeName]
	end
	if not raw then
		return false, "Config not found"
	end

	return Config.Import(raw)
end

function Config.Delete(name)
	local safeName = sanitizeName(name)
	if not safeName then
		return false, "Invalid config name"
	end

	memoryStore[safeName] = nil
	if memoryAutoLoad == safeName then
		memoryAutoLoad = nil
	end

	if Util.FS.Supported() then
		local path = configPath(safeName)
		if Util.FS.IsFile(path) then
			Util.FS.Delete(path)
		end
		if Config.GetAutoLoad() == safeName then
			Config.SetAutoLoad(nil)
		end
	end

	return true
end

function Config.List()
	local seen = {}
	local names = {}

	if Util.FS.Supported() then
		ensureFolder()
		for _, fullPath in ipairs(Util.FS.List(folder)) do
			local base = string.match(tostring(fullPath), "([^/\\]+)%.json$")
			if base and string.sub(base, 1, 1) ~= "_" and not seen[base] then
				seen[base] = true
				table.insert(names, base)
			end
		end
	end

	for name in pairs(memoryStore) do
		if not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end

	table.sort(names)
	return names
end

function Config.SetAutoLoad(name)
	if name == nil or name == "" or name == "None" then
		memoryAutoLoad = nil
		if Util.FS.Supported() and Util.FS.IsFile(autoLoadPath()) then
			Util.FS.Delete(autoLoadPath())
		end
		return true
	end

	local safeName = sanitizeName(name)
	if not safeName then
		return false, "Invalid config name"
	end

	memoryAutoLoad = safeName
	if Util.FS.Supported() then
		ensureFolder()
		Util.FS.Write(autoLoadPath(), safeName)
	end
	return true
end

function Config.GetAutoLoad()
	if Util.FS.Supported() and Util.FS.IsFile(autoLoadPath()) then
		local raw = Util.FS.Read(autoLoadPath())
		local safe = sanitizeName(raw)
		if safe then
			return safe
		end
	end
	return memoryAutoLoad
end

function Config.LoadAuto()
	local autoName = Config.GetAutoLoad()
	if not autoName then
		return false, "No autoload config set"
	end
	return Config.Load(autoName)
end

return Config
