--[[
	Bali UI · Core/Util
	Pure helpers: math, formatting, colors, safe calls, key names, executor shims.
]]

local Services = require("Core/Services")

local Util = {}

-- ─── Math ────────────────────────────────────────────────────────────────────

function Util.Clamp(value, min, max)
	if value < min then
		return min
	elseif value > max then
		return max
	end
	return value
end

function Util.Lerp(a, b, t)
	return a + (b - a) * t
end

-- Number of decimals implied by a step (0.25 -> 2, 1 -> 0, 0.1 -> 1)
function Util.Decimals(step)
	if not step or step >= 1 or step <= 0 then
		return 0
	end
	local text = string.format("%.6f", step):gsub("0+$", "")
	local dot = text:find("%.")
	return dot and (#text - dot) or 0
end

-- Snap a value to a step relative to min, then clamp
function Util.Snap(value, min, max, step)
	step = (step and step > 0) and step or 1
	local snapped = min + math.floor((value - min) / step + 0.5) * step
	local decimals = Util.Decimals(step)
	local factor = 10 ^ decimals
	snapped = math.floor(snapped * factor + 0.5) / factor
	return Util.Clamp(snapped, math.min(min, max), math.max(min, max))
end

function Util.FormatNumber(value, decimals)
	decimals = decimals or 0
	local text = string.format("%." .. decimals .. "f", value)
	local sign, int, frac = text:match("^([%-]?)(%d+)(%.?%d*)$")
	if not int then
		return text
	end
	int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. int .. frac
end

-- ─── Tables ──────────────────────────────────────────────────────────────────

function Util.Merge(defaults, overrides)
	local result = {}
	for key, value in pairs(defaults) do
		result[key] = value
	end
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			result[key] = value
		end
	end
	return result
end

-- Accepts a string shorthand ("Title") or an options table
function Util.Options(options, defaults, shorthandKey)
	if type(options) ~= "table" then
		options = { [shorthandKey or "Title"] = options }
	end
	return Util.Merge(defaults or {}, options)
end

function Util.Find(list, value)
	for index, item in ipairs(list) do
		if item == value then
			return index
		end
	end
	return nil
end

function Util.Copy(list)
	local result = {}
	for index, item in ipairs(list) do
		result[index] = item
	end
	return result
end

function Util.Count(dictionary)
	local count = 0
	for _ in pairs(dictionary) do
		count += 1
	end
	return count
end

-- ─── Strings ─────────────────────────────────────────────────────────────────

function Util.Trim(text)
	return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.RandomString(length)
	local chars = {}
	for index = 1, length or 12 do
		chars[index] = string.char(math.random(97, 122))
	end
	return table.concat(chars)
end

function Util.Matches(haystack, query)
	if not query or query == "" then
		return true
	end
	if not haystack then
		return false
	end
	return string.find(string.lower(tostring(haystack)), string.lower(query), 1, true) ~= nil
end

-- ─── Colors ──────────────────────────────────────────────────────────────────

function Util.ToHex(color)
	return string.format(
		"%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

function Util.FromHex(hex)
	hex = tostring(hex or ""):gsub("#", ""):gsub("%s", "")
	if #hex == 3 then
		hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
	end
	if #hex ~= 6 or hex:find("[^%x]") then
		return nil
	end
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end

function Util.LerpColor(a, b, t)
	return Color3.new(Util.Lerp(a.R, b.R, t), Util.Lerp(a.G, b.G, t), Util.Lerp(a.B, b.B, t))
end

function Util.Luminance(color)
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

-- ─── Safe execution ──────────────────────────────────────────────────────────

Util.ErrorHandler = nil -- set by the library to surface callback errors as toasts

function Util.SafeCall(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[Bali] Callback error: " .. tostring(result))
		if Util.ErrorHandler then
			pcall(Util.ErrorHandler, result)
		end
	end
	return ok, result
end

-- Fire a user callback without letting it yield or break UI code
function Util.Spawn(fn, ...)
	if type(fn) ~= "function" then
		return
	end
	task.spawn(Util.SafeCall, fn, ...)
end

-- ─── Input helpers ───────────────────────────────────────────────────────────

-- Mouse position in AbsolutePosition space (GUI inset removed)
function Util.MousePosition()
	local UserInputService = Services.UserInputService
	local location = UserInputService:GetMouseLocation()
	local inset = Services.GuiService:GetGuiInset()
	return Vector2.new(location.X - inset.X, location.Y - inset.Y)
end

function Util.IsPointer(input)
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

function Util.IsMove(input)
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch
end

function Util.IsTouchDevice()
	local UserInputService = Services.UserInputService
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local keyAliases = {
	LeftShift = "LShift",
	RightShift = "RShift",
	LeftControl = "LCtrl",
	RightControl = "RCtrl",
	LeftAlt = "LAlt",
	RightAlt = "RAlt",
	LeftSuper = "LCmd",
	RightSuper = "RCmd",
	Return = "Enter",
	Backspace = "Back",
	CapsLock = "Caps",
	PageUp = "PgUp",
	PageDown = "PgDn",
	Insert = "Ins",
	Delete = "Del",
	Escape = "Esc",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
	Zero = "0",
	MouseButton1 = "MB1",
	MouseButton2 = "MB2",
	MouseButton3 = "MB3",
	Minus = "-",
	Equals = "=",
	LeftBracket = "[",
	RightBracket = "]",
	Semicolon = ";",
	Quote = "'",
	Comma = ",",
	Period = ".",
	Slash = "/",
	BackSlash = "\\",
	Backquote = "`",
}

-- Converts an Enum.KeyCode / Enum.UserInputType (or its name) into a short label
function Util.KeyName(key)
	if key == nil then
		return "None"
	end
	local name = typeof(key) == "EnumItem" and key.Name or tostring(key)
	return keyAliases[name] or name
end

-- Resolves a string/EnumItem into an EnumItem (KeyCode or mouse UserInputType)
function Util.ResolveKey(key)
	if key == nil or key == "None" or key == "" then
		return nil
	end
	if typeof(key) == "EnumItem" then
		return key
	end
	local name = tostring(key)
	if name == "MB1" or name == "MouseButton1" then
		return Enum.UserInputType.MouseButton1
	elseif name == "MB2" or name == "MouseButton2" then
		return Enum.UserInputType.MouseButton2
	elseif name == "MB3" or name == "MouseButton3" then
		return Enum.UserInputType.MouseButton3
	end
	for alias, real in pairs(keyAliases) do
		if real == name then
			name = alias
			break
		end
	end
	local ok, item = pcall(function()
		return Enum.KeyCode[name]
	end)
	return ok and item or nil
end

-- ─── Executor shims ──────────────────────────────────────────────────────────

local env = (typeof(getgenv) == "function" and getgenv()) or _G
Util.Env = env

function Util.Global(name)
	local value = env[name]
	if value == nil then
		value = rawget(_G, name)
	end
	return value
end

function Util.SetClipboard(text)
	local fn = Util.Global("setclipboard") or Util.Global("toclipboard") or Util.Global("set_clipboard")
	if type(fn) == "function" then
		return (pcall(fn, tostring(text)))
	end
	return false
end

function Util.ExecutorName()
	local name = "Roblox Studio"
	pcall(function()
		local fn = Util.Global("identifyexecutor") or Util.Global("getexecutorname")
		if type(fn) == "function" then
			local res = fn()
			if res and tostring(res) ~= "" then
				name = tostring(res)
			end
		end
	end)
	return name
end

function Util.ExtractInviteCode(raw)
	local s = Util.Trim(tostring(raw or ""))
	s = s:gsub("%?.*$", ""):gsub("/+$", "")
	return s:match("([^/]+)$") or s
end

function Util.HttpGet(url, acceptJson)
	local headers = { ["User-Agent"] = "Mozilla/5.0" }
	if acceptJson ~= false then
		headers["Accept"] = "application/json"
	end
	local synTbl = Util.Global("syn")
	local httpTbl = Util.Global("http")
	local fluxusTbl = Util.Global("fluxus")
	local req = (type(synTbl) == "table" and synTbl.request)
		or (type(httpTbl) == "table" and httpTbl.request)
		or Util.Global("http_request")
		or Util.Global("request")
		or (type(fluxusTbl) == "table" and fluxusTbl.request)

	if type(req) == "function" then
		local ok, res = pcall(req, { Url = url, Method = "GET", Headers = headers })
		if ok and type(res) == "table" then
			local code = tonumber(res.StatusCode or res.status_code)
			if code and code >= 400 and code < 500 then
				return nil, code
			end
			if type(res.Body) == "string" and #res.Body > 0 then
				if (res.Success == nil or res.Success == true) and (not code or (code >= 200 and code < 300)) then
					return res.Body, code or 200
				end
			end
		end
	end

	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" and #body > 0 then
		return body, 200
	end
	return nil, 0
end

Util.FS = {
	Supported = function()
		return type(Util.Global("writefile")) == "function" and type(Util.Global("readfile")) == "function"
	end,
	Write = function(path, contents)
		local fn = Util.Global("writefile")
		return fn and (pcall(fn, path, contents)) or false
	end,
	Read = function(path)
		local fn = Util.Global("readfile")
		if not fn then
			return nil
		end
		local ok, result = pcall(fn, path)
		return ok and result or nil
	end,
	IsFile = function(path)
		local fn = Util.Global("isfile")
		if not fn then
			return false
		end
		local ok, result = pcall(fn, path)
		return ok and result == true
	end,
	IsFolder = function(path)
		local fn = Util.Global("isfolder")
		if not fn then
			return false
		end
		local ok, result = pcall(fn, path)
		return ok and result == true
	end,
	MakeFolder = function(path)
		local make = Util.Global("makefolder")
		if not make then
			return false
		end
		-- create each segment so nested paths work on every executor
		local current = ""
		for segment in string.gmatch(path, "[^/\\]+") do
			current = current == "" and segment or (current .. "/" .. segment)
			if not Util.FS.IsFolder(current) then
				pcall(make, current)
			end
		end
		return true
	end,
	List = function(path)
		local fn = Util.Global("listfiles")
		if not fn then
			return {}
		end
		local ok, result = pcall(fn, path)
		return (ok and type(result) == "table") and result or {}
	end,
	Delete = function(path)
		local fn = Util.Global("delfile")
		return fn and (pcall(fn, path)) or false
	end,
}

return Util
