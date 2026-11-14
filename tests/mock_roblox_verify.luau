--!nolint
--[[
	Bali UI · Runtime & Layout Verification Harness
	Executes dist/BaliExample.lua (Pass 1: Executor) and dist/Bali.lua (Pass 2: Studio)
	inside a realistic Mock Roblox Engine and checks runtime errors, warnings, APIs,
	interactive state, config serialization, layout overlap, re-execution, and cleanup.
]]

local origPrint = print
local origTypeof = typeof
local origWarn = warn
local origRequire = require

local capturedWarnings = {}
local testFailures = {}
local testPasses = 0

local function log(msg)
	origPrint(msg)
end

local function assertTrue(cond, msg)
	if cond then
		testPasses += 1
		return true
	end
	local err = "[FAIL] " .. tostring(msg)
	table.insert(testFailures, err)
	origPrint(err)
	return false
end

local function assertEq(actual, expected, msg)
	if actual == expected then
		testPasses += 1
		return true
	end
	local err = string.format("[FAIL] %s (expected %s, got %s)", tostring(msg), tostring(expected), tostring(actual))
	table.insert(testFailures, err)
	origPrint(err)
	return false
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Mock Roblox Engine
-- ══════════════════════════════════════════════════════════════════════════════

local typeTags = setmetatable({}, { __mode = "k" })
local function tagType(obj, typeName)
	typeTags[obj] = typeName
	return obj
end

local function mockTypeof(v)
	local tagged = typeTags[v]
	if tagged then
		return tagged
	end
	return origTypeof(v)
end

-- ─── Virtual Clock & Task Scheduler ──────────────────────────────────────────

local virtualClock = 100.0
local pendingTasks = {} -- { thread, wakeAt, args, cancelled }
local deferredQueue = {}

local function resumeThread(thread, ...)
	if coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, tag, arg = coroutine.resume(thread, ...)
	if not ok then
		local errMsg = debug.traceback(thread, tostring(tag))
		table.insert(testFailures, "[TASK ERROR] " .. errMsg)
		origPrint("[TASK ERROR] " .. errMsg)
		return
	end
	if coroutine.status(thread) == "suspended" and tag == "WAIT" then
		local delaySec = math.max(0.016, tonumber(arg) or 0.016)
		table.insert(pendingTasks, {
			thread = thread,
			wakeAt = virtualClock + delaySec,
			waitStart = virtualClock,
			cancelled = false,
		})
	end
end

local MockTask = {}

function MockTask.spawn(fn, ...)
	local co = coroutine.create(fn)
	resumeThread(co, ...)
	return co
end

function MockTask.defer(fn, ...)
	local args = table.pack(...)
	local srcLine, srcName = debug.info(fn, "ln")
	local co = coroutine.create(function()
		fn(table.unpack(args, 1, args.n))
	end)
	local entry = {
		thread = co,
		wakeAt = virtualClock,
		waitStart = virtualClock,
		cancelled = false,
		info = tostring(srcName) .. ":" .. tostring(srcLine),
	}
	table.insert(deferredQueue, entry)
	return co
end

function MockTask.delay(sec, fn, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		fn(table.unpack(args, 1, args.n))
	end)
	local entry = {
		thread = co,
		wakeAt = virtualClock + math.max(0, sec or 0),
		waitStart = virtualClock,
		cancelled = false,
	}
	table.insert(pendingTasks, entry)
	return co
end

function MockTask.wait(sec)
	local running = coroutine.running()
	if running then
		local elapsed = coroutine.yield("WAIT", sec or 0)
		return elapsed or (sec or 0.016)
	end
	virtualClock += (sec or 0.016)
	return sec or 0.016
end

function MockTask.cancel(thread)
	for _, entry in ipairs(pendingTasks) do
		if entry.thread == thread then
			entry.cancelled = true
		end
	end
	for _, entry in ipairs(deferredQueue) do
		if entry.thread == thread then
			entry.cancelled = true
		end
	end
	pcall(coroutine.close, thread)
end

-- Forward declare Services/RunService for stepping
local RunServiceRef = nil

local function flushDeferred(maxRounds)
	local rounds = 0
	while #deferredQueue > 0 and rounds < (maxRounds or 20) do
		rounds += 1
		local batch = deferredQueue
		deferredQueue = {}
		for _, entry in ipairs(batch) do
			if not entry.cancelled then
				resumeThread(entry.thread)
			end
		end
	end
end

local function stepClock(dt, fireFrames)
	dt = dt or 0.016
	local targetTime = virtualClock + dt
	local steps = fireFrames and math.max(1, math.floor(dt / 0.016 + 0.5)) or 1
	local stepDt = dt / steps

	for _ = 1, steps do
		virtualClock += stepDt
		flushDeferred(20)

		-- Run due tasks up to current virtualClock (bounded to avoid infinite loops)
		local safety = 0
		while safety < 200 do
			safety += 1
			local nextIdx = nil
			local earliest = math.huge
			for i, entry in ipairs(pendingTasks) do
				if not entry.cancelled and entry.wakeAt <= virtualClock and entry.wakeAt < earliest then
					earliest = entry.wakeAt
					nextIdx = i
				end
			end
			if not nextIdx then
				break
			end
			local entry = table.remove(pendingTasks, nextIdx)
			if not entry.cancelled then
				local elapsed = virtualClock - (entry.waitStart or virtualClock)
				resumeThread(entry.thread, elapsed)
				flushDeferred(10)
			end
		end

		if fireFrames and RunServiceRef then
			RunServiceRef.RenderStepped:Fire(stepDt)
			RunServiceRef.Heartbeat:Fire(stepDt)
			RunServiceRef.Stepped:Fire(virtualClock, stepDt)
			flushDeferred(10)
		end
	end
	virtualClock = targetTime
end

-- ─── Signal (RBXScriptSignal / RBXScriptConnection) ──────────────────────────

local function createSignal()
	local sig = { _listeners = {} }

	function sig:Connect(fn)
		local listener = { fn = fn, connected = true }
		table.insert(sig._listeners, listener)

		local conn = {}
		function conn:Disconnect()
			listener.connected = false
		end
		conn.Connected = true
		return tagType(conn, "RBXScriptConnection")
	end

	function sig:Once(fn)
		local conn
		conn = sig:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end

	function sig:Wait()
		local co = coroutine.running()
		local done = false
		local result
		sig:Once(function(...)
			done = true
			result = table.pack(...)
			if co then
				resumeThread(co, ...)
			end
		end)
		if co and not done then
			return coroutine.yield()
		end
		if result then
			return table.unpack(result, 1, result.n)
		end
		return nil
	end

	function sig:Fire(...)
		local snapshot = {}
		for _, l in ipairs(sig._listeners) do
			if l.connected then
				table.insert(snapshot, l)
			end
		end
		for _, l in ipairs(snapshot) do
			if l.connected then
				local ok, err = pcall(l.fn, ...)
				if not ok then
					table.insert(testFailures, "[SIGNAL ERROR] " .. tostring(err))
					origPrint("[SIGNAL ERROR] " .. tostring(err))
				end
			end
		end
	end

	return tagType(sig, "RBXScriptSignal")
end

-- ─── Roblox Value Types ──────────────────────────────────────────────────────

local Color3MT = {}
Color3MT.__index = Color3MT
function Color3MT.__eq(a, b)
	return mockTypeof(a) == "Color3" and mockTypeof(b) == "Color3"
		and math.abs(a.R - b.R) < 1e-4 and math.abs(a.G - b.G) < 1e-4 and math.abs(a.B - b.B) < 1e-4
end
function Color3MT.__tostring(c)
	return string.format("Color3(%g, %g, %g)", c.R, c.G, c.B)
end

local MockColor3 = {}

function MockColor3.new(r, g, b)
	local obj = setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3MT)
	return tagType(obj, "Color3")
end

function MockColor3.fromRGB(r, g, b)
	return MockColor3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

function MockColor3.fromHSV(h, s, v)
	h = (h or 0) % 1
	s = math.clamp(s or 0, 0, 1)
	v = math.clamp(v or 0, 0, 1)
	if s == 0 then
		return MockColor3.new(v, v, v)
	end
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then
		return MockColor3.new(v, t, p)
	elseif m == 1 then
		return MockColor3.new(q, v, p)
	elseif m == 2 then
		return MockColor3.new(p, v, t)
	elseif m == 3 then
		return MockColor3.new(p, q, v)
	elseif m == 4 then
		return MockColor3.new(t, p, v)
	else
		return MockColor3.new(v, p, q)
	end
end

function MockColor3.fromHex(hex)
	hex = tostring(hex or ""):gsub("#", "")
	if #hex == 3 then
		hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
	end
	local r = tonumber(hex:sub(1, 2), 16) or 0
	local g = tonumber(hex:sub(3, 4), 16) or 0
	local b = tonumber(hex:sub(5, 6), 16) or 0
	return MockColor3.fromRGB(r, g, b)
end

function Color3MT:ToHSV()
	local r, g, b = self.R, self.G, self.B
	local maxC = math.max(r, g, b)
	local minC = math.min(r, g, b)
	local d = maxC - minC
	local h = 0
	local s = maxC == 0 and 0 or (d / maxC)
	local v = maxC
	if d ~= 0 then
		if maxC == r then
			h = ((g - b) / d) % 6
		elseif maxC == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
		if h < 0 then
			h += 1
		end
	end
	return h, s, v
end
MockColor3.toHSV = Color3MT.ToHSV

function Color3MT:Lerp(goal, alpha)
	alpha = alpha or 0
	return MockColor3.new(
		self.R + (goal.R - self.R) * alpha,
		self.G + (goal.G - self.G) * alpha,
		self.B + (goal.B - self.B) * alpha
	)
end
MockColor3.Lerp = Color3MT.Lerp

function Color3MT:ToHex()
	return string.format(
		"%02x%02x%02x",
		math.floor(math.clamp(self.R, 0, 1) * 255 + 0.5),
		math.floor(math.clamp(self.G, 0, 1) * 255 + 0.5),
		math.floor(math.clamp(self.B, 0, 1) * 255 + 0.5)
	)
end

-- UDim
local UDimMT = {}
UDimMT.__index = UDimMT
function UDimMT.__add(a, b)
	return MockUDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
end
function UDimMT.__sub(a, b)
	return MockUDim.new(a.Scale - b.Scale, a.Offset - b.Offset)
end
function UDimMT.__eq(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
function UDimMT.__tostring(u)
	return string.format("UDim(%g, %g)", u.Scale, u.Offset)
end

MockUDim = {}
function MockUDim.new(scale, offset)
	return tagType(setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDimMT), "UDim")
end

-- UDim2
local UDim2MT = {}
UDim2MT.__index = UDim2MT
function UDim2MT.__add(a, b)
	return MockUDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
function UDim2MT.__sub(a, b)
	return MockUDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
function UDim2MT.__eq(a, b)
	return a.X == b.X and a.Y == b.Y
end
function UDim2MT.__tostring(u)
	return string.format("UDim2({%g, %g}, {%g, %g})", u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
end
function UDim2MT:Lerp(goal, alpha)
	return MockUDim2.new(
		self.X.Scale + (goal.X.Scale - self.X.Scale) * alpha,
		self.X.Offset + (goal.X.Offset - self.X.Offset) * alpha,
		self.Y.Scale + (goal.Y.Scale - self.Y.Scale) * alpha,
		self.Y.Offset + (goal.Y.Offset - self.Y.Offset) * alpha
	)
end

local MockUDim2 = {}
function MockUDim2.new(xs, xo, ys, yo)
	if mockTypeof(xs) == "UDim" and mockTypeof(xo) == "UDim" then
		local x, y = xs, xo
		return tagType(setmetatable({ X = x, Y = y, Width = x, Height = y }, UDim2MT), "UDim2")
	end
	local x = MockUDim.new(xs or 0, xo or 0)
	local y = MockUDim.new(ys or 0, yo or 0)
	return tagType(setmetatable({ X = x, Y = y, Width = x, Height = y }, UDim2MT), "UDim2")
end
function MockUDim2.fromOffset(x, y)
	return MockUDim2.new(0, x or 0, 0, y or 0)
end
function MockUDim2.fromScale(x, y)
	return MockUDim2.new(x or 0, 0, y or 0, 0)
end

-- Vector2
local Vector2MT = {}
Vector2MT.__index = function(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y)
		return m > 0 and MockVector2.new(t.X / m, t.Y / m) or MockVector2.zero
	end
	return Vector2MT[k]
end
function Vector2MT.__add(a, b)
	return MockVector2.new(a.X + b.X, a.Y + b.Y)
end
function Vector2MT.__sub(a, b)
	return MockVector2.new(a.X - b.X, a.Y - b.Y)
end
function Vector2MT.__mul(a, b)
	if type(a) == "number" then
		return MockVector2.new(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return MockVector2.new(a.X * b, a.Y * b)
	end
	return MockVector2.new(a.X * b.X, a.Y * b.Y)
end
function Vector2MT.__div(a, b)
	if type(b) == "number" then
		return MockVector2.new(a.X / b, a.Y / b)
	end
	return MockVector2.new(a.X / b.X, a.Y / b.Y)
end
function Vector2MT.__unm(a)
	return MockVector2.new(-a.X, -a.Y)
end
function Vector2MT.__eq(a, b)
	return a.X == b.X and a.Y == b.Y
end
function Vector2MT.__tostring(v)
	return string.format("Vector2(%g, %g)", v.X, v.Y)
end
function Vector2MT:Lerp(goal, alpha)
	return MockVector2.new(self.X + (goal.X - self.X) * alpha, self.Y + (goal.Y - self.Y) * alpha)
end

MockVector2 = {}
function MockVector2.new(x, y)
	return tagType(setmetatable({ X = x or 0, Y = y or 0 }, Vector2MT), "Vector2")
end
MockVector2.zero = MockVector2.new(0, 0)
MockVector2.one = MockVector2.new(1, 1)

-- Rect
local MockRect = {}
function MockRect.new(a, b, c, d)
	local minV, maxV
	if mockTypeof(a) == "Vector2" then
		minV, maxV = a, b
	else
		minV = MockVector2.new(a or 0, b or 0)
		maxV = MockVector2.new(c or 0, d or 0)
	end
	return tagType({
		Min = minV,
		Max = maxV,
		Width = maxV.X - minV.X,
		Height = maxV.Y - minV.Y,
	}, "Rect")
end

-- Enums
local MockEnum = {}
local function makeEnum(name, items)
	local enumType = {}
	local byName = {}
	for idx, itemName in ipairs(items) do
		local itemProps = {
			Name = itemName,
			Value = idx - 1,
			EnumType = enumType,
		}
		local item
		if type(newproxy) == "function" then
			item = newproxy(true)
			local mt = getmetatable(item)
			mt.__index = itemProps
			mt.__tostring = function()
				return "Enum." .. name .. "." .. itemName
			end
		else
			item = itemProps
		end
		byName[itemName] = tagType(item, "EnumItem")
	end
	function enumType:GetEnumItems()
		local out = {}
		for _, itemName in ipairs(items) do
			table.insert(out, byName[itemName])
		end
		return out
	end
	setmetatable(enumType, {
		__index = function(_, k)
			local item = byName[k]
			if not item then
				error(string.format("Invalid EnumItem '%s' on Enum.%s", tostring(k), name), 2)
			end
			return item
		end,
		__tostring = function()
			return "Enum." .. name
		end,
	})
	tagType(enumType, "Enum")
	MockEnum[name] = enumType
end

makeEnum("EasingStyle", { "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic" })
makeEnum("EasingDirection", { "In", "Out", "InOut" })
makeEnum("FontWeight", { "Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy" })
makeEnum("FontStyle", { "Normal", "Italic" })
makeEnum("ScaleType", { "Stretch", "Slice", "Tile", "Fit", "Crop" })
makeEnum("FillDirection", { "Horizontal", "Vertical" })
makeEnum("SortOrder", { "Name", "LayoutOrder" })
makeEnum("HorizontalAlignment", { "Center", "Left", "Right" })
makeEnum("VerticalAlignment", { "Center", "Top", "Bottom" })
makeEnum("AutomaticSize", { "None", "X", "Y", "XY" })
makeEnum("ScrollingDirection", { "X", "Y", "XY" })
makeEnum("TextXAlignment", { "Left", "Right", "Center" })
makeEnum("TextYAlignment", { "Top", "Center", "Bottom" })
makeEnum("TextTruncate", { "None", "AtEnd", "SplitWord" })
makeEnum("ApplyStrokeMode", { "Contextual", "Border" })
makeEnum("ZIndexBehavior", { "Global", "Sibling" })
makeEnum("UserInputType", {
	"MouseButton1", "MouseButton2", "MouseButton3", "MouseWheel", "MouseMovement",
	"Touch", "Keyboard", "Focus", "TextInput", "None",
})
makeEnum("KeyCode", {
	"Unknown", "Backspace", "Tab", "Clear", "Return", "Pause", "Escape", "Space",
	"QuotedDouble", "Hash", "Dollar", "Percent", "Ampersand", "Quote", "LeftParenthesis",
	"RightParenthesis", "Asterisk", "Plus", "Comma", "Minus", "Period", "Slash",
	"Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
	"Colon", "Semicolon", "LessThan", "Equals", "GreaterThan", "Question", "At",
	"LeftBracket", "BackSlash", "RightBracket", "Caret", "Underscore", "Backquote",
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
	"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
	"Delete", "Insert", "Home", "End", "PageUp", "PageDown",
	"Up", "Down", "Right", "Left",
	"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
	"NumLock", "CapsLock", "ScrollLock", "RightShift", "LeftShift",
	"RightControl", "LeftControl", "RightAlt", "LeftAlt", "RightSuper", "LeftSuper",
})
makeEnum("AssetFetchStatus", { "Success", "Failure", "None", "TimedOut", "Loading" })
makeEnum("PlaybackState", { "Begin", "Delayed", "Playing", "Paused", "Completed", "Cancelled" })
makeEnum("ThumbnailType", { "HeadShot", "AvatarBust", "AvatarThumbnail" })
makeEnum("ThumbnailSize", { "Size48x48", "Size60x60", "Size100x100", "Size150x150", "Size180x180", "Size352x352", "Size420x420" })

-- Font
local MockFont = {}
function MockFont.new(family, weight, style)
	return tagType({
		Family = family or "rbxasset://fonts/families/GothamSSm.json",
		Weight = weight or MockEnum.FontWeight.Regular,
		Style = style or MockEnum.FontStyle.Normal,
		Bold = (weight == MockEnum.FontWeight.Bold or weight == MockEnum.FontWeight.SemiBold),
	}, "Font")
end
function MockFont.fromName(name, weight, style)
	return MockFont.new("rbxasset://fonts/families/" .. tostring(name) .. ".json", weight, style)
end

-- ColorSequence / NumberSequence / TweenInfo
local MockColorSequenceKeypoint = {}
function MockColorSequenceKeypoint.new(t, c)
	return tagType({ Time = t, Value = c }, "ColorSequenceKeypoint")
end

local MockColorSequence = {}
function MockColorSequence.new(a, b)
	local kps
	if type(a) == "table" and mockTypeof(a) ~= "Color3" then
		kps = a
	elseif b ~= nil then
		kps = { MockColorSequenceKeypoint.new(0, a), MockColorSequenceKeypoint.new(1, b) }
	else
		kps = { MockColorSequenceKeypoint.new(0, a), MockColorSequenceKeypoint.new(1, a) }
	end
	return tagType({ Keypoints = kps }, "ColorSequence")
end

local MockNumberSequenceKeypoint = {}
function MockNumberSequenceKeypoint.new(t, v, env)
	return tagType({ Time = t, Value = v, Envelope = env or 0 }, "NumberSequenceKeypoint")
end

local MockNumberSequence = {}
function MockNumberSequence.new(a, b)
	local kps
	if type(a) == "table" then
		kps = a
	elseif b ~= nil then
		kps = { MockNumberSequenceKeypoint.new(0, a), MockNumberSequenceKeypoint.new(1, b) }
	else
		kps = { MockNumberSequenceKeypoint.new(0, a), MockNumberSequenceKeypoint.new(1, a) }
	end
	return tagType({ Keypoints = kps }, "NumberSequence")
end

local MockTweenInfo = {}
function MockTweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	return tagType({
		Time = time or 1,
		EasingStyle = style or MockEnum.EasingStyle.Quad,
		EasingDirection = direction or MockEnum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses == true,
		DelayTime = delayTime or 0,
	}, "TweenInfo")
end

-- ─── Instance DOM + Layout Engine ────────────────────────────────────────────

local VIEWPORT_SIZE = MockVector2.new(1280, 720)
local GUI_INSET = MockVector2.new(0, 36)

local GUI_CLASSES = {
	Frame = true,
	ScrollingFrame = true,
	CanvasGroup = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ViewportFrame = true,
}

local BUTTON_CLASSES = { TextButton = true, ImageButton = true }
local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local CLASS_PARENTS = {
	ScreenGui = { "LayerCollector", "GuiBase2d", "GuiBase", "Instance" },
	Frame = { "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	ScrollingFrame = { "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	CanvasGroup = { "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	TextLabel = { "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	TextButton = { "GuiButton", "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	TextBox = { "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	ImageLabel = { "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	ImageButton = { "GuiButton", "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	ViewportFrame = { "GuiObject", "GuiBase2d", "GuiBase", "Instance" },
	UIListLayout = { "UIGridStyleLayout", "UILayout", "UIComponent", "Instance" },
	UIGridLayout = { "UIGridStyleLayout", "UILayout", "UIComponent", "Instance" },
	UIPadding = { "UIComponent", "Instance" },
	UICorner = { "UIComponent", "Instance" },
	UIStroke = { "UIComponent", "Instance" },
	UIGradient = { "UIComponent", "Instance" },
	UIScale = { "UIComponent", "Instance" },
	UISizeConstraint = { "UIComponent", "Instance" },
	UIAspectRatioConstraint = { "UIComponent", "Instance" },
	NumberValue = { "ValueBase", "Instance" },
	BlurEffect = { "PostEffect", "Instance" },
}

local function isClassA(cls, target)
	if cls == target or target == "Instance" then
		return true
	end
	local list = CLASS_PARENTS[cls]
	if list then
		for _, p in ipairs(list) do
			if p == target then
				return true
			end
		end
	end
	return false
end

local function createDefaultProps(className)
	local p = {
		Name = className,
		ClassName = className,
		Archivable = true,
	}
	if className == "ScreenGui" then
		p.IgnoreGuiInset = false
		p.ResetOnSpawn = true
		p.Enabled = true
		p.DisplayOrder = 0
		p.ZIndexBehavior = MockEnum.ZIndexBehavior.Sibling
	elseif GUI_CLASSES[className] then
		p.Position = MockUDim2.new(0, 0, 0, 0)
		p.Size = MockUDim2.new(0, 0, 0, 0)
		p.AnchorPoint = MockVector2.zero
		p.AutomaticSize = MockEnum.AutomaticSize.None
		p.BackgroundColor3 = MockColor3.new(1, 1, 1)
		p.BackgroundTransparency = 0
		p.BorderSizePixel = 1
		p.BorderColor3 = MockColor3.new(0, 0, 0)
		p.ClipsDescendants = false
		p.LayoutOrder = 0
		p.Rotation = 0
		p.Visible = true
		p.ZIndex = 1
		p.Active = false
		p.Selectable = false
		if className == "CanvasGroup" then
			p.GroupTransparency = 0
			p.GroupColor3 = MockColor3.new(1, 1, 1)
		elseif className == "ScrollingFrame" then
			p.CanvasSize = MockUDim2.new(0, 0, 2, 0)
			p.CanvasPosition = MockVector2.zero
			p.AutomaticCanvasSize = MockEnum.AutomaticSize.None
			p.ScrollingDirection = MockEnum.ScrollingDirection.XY
			p.ScrollBarThickness = 12
			p.ScrollBarImageColor3 = MockColor3.new(0, 0, 0)
			p.ScrollBarImageTransparency = 0
			p.ScrollingEnabled = true
		end
		if TEXT_CLASSES[className] then
			p.Text = className
			p.TextColor3 = MockColor3.new(0, 0, 0)
			p.TextTransparency = 0
			p.TextSize = 14
			p.TextScaled = false
			p.TextWrapped = false
			p.TextTruncate = MockEnum.TextTruncate.None
			p.TextXAlignment = MockEnum.TextXAlignment.Center
			p.TextYAlignment = MockEnum.TextYAlignment.Center
			p.FontFace = MockFont.new()
			p.RichText = false
			p.LineHeight = 1
			if className == "TextBox" then
				p.PlaceholderText = ""
				p.PlaceholderColor3 = MockColor3.fromRGB(178, 178, 178)
				p.ClearTextOnFocus = true
				p.MultiLine = false
				p.TextEditable = true
			end
		end
		if BUTTON_CLASSES[className] then
			p.AutoButtonColor = true
			p.Active = true
			p.Selectable = true
		end
		if className == "ImageLabel" or className == "ImageButton" then
			p.Image = ""
			p.ImageColor3 = MockColor3.new(1, 1, 1)
			p.ImageTransparency = 0
			p.ImageRectOffset = MockVector2.zero
			p.ImageRectSize = MockVector2.zero
			p.ScaleType = MockEnum.ScaleType.Stretch
			p.SliceCenter = MockRect.new(0, 0, 0, 0)
			p.SliceScale = 1
			p.TileSize = MockUDim2.fromScale(1, 1)
		end
	elseif className == "UIListLayout" then
		p.FillDirection = MockEnum.FillDirection.Vertical
		p.HorizontalAlignment = MockEnum.HorizontalAlignment.Left
		p.VerticalAlignment = MockEnum.VerticalAlignment.Top
		p.SortOrder = MockEnum.SortOrder.LayoutOrder
		p.Padding = MockUDim.new(0, 0)
		p.Wraps = false
	elseif className == "UIGridLayout" then
		p.CellSize = MockUDim2.fromOffset(100, 100)
		p.CellPadding = MockUDim2.fromOffset(5, 5)
		p.FillDirection = MockEnum.FillDirection.Horizontal
		p.HorizontalAlignment = MockEnum.HorizontalAlignment.Left
		p.VerticalAlignment = MockEnum.VerticalAlignment.Top
		p.SortOrder = MockEnum.SortOrder.LayoutOrder
		p.FillDirectionMaxCells = 0
	elseif className == "UIPadding" then
		p.PaddingTop = MockUDim.new(0, 0)
		p.PaddingBottom = MockUDim.new(0, 0)
		p.PaddingLeft = MockUDim.new(0, 0)
		p.PaddingRight = MockUDim.new(0, 0)
	elseif className == "UICorner" then
		p.CornerRadius = MockUDim.new(0, 8)
	elseif className == "UIStroke" then
		p.Color = MockColor3.new(0, 0, 0)
		p.Thickness = 1
		p.Transparency = 0
		p.ApplyStrokeMode = MockEnum.ApplyStrokeMode.Contextual
		p.Enabled = true
	elseif className == "UIGradient" then
		p.Color = MockColorSequence.new(MockColor3.new(1, 1, 1))
		p.Transparency = MockNumberSequence.new(0)
		p.Rotation = 0
		p.Offset = MockVector2.zero
		p.Enabled = true
	elseif className == "UIScale" then
		p.Scale = 1
	elseif className == "UISizeConstraint" then
		p.MinSize = MockVector2.zero
		p.MaxSize = MockVector2.new(math.huge, math.huge)
	elseif className == "UIAspectRatioConstraint" then
		p.AspectRatio = 1
	elseif className == "NumberValue" then
		p.Value = 0
	elseif className == "BlurEffect" then
		p.Size = 24
		p.Enabled = true
	elseif className == "GetTextBoundsParams" then
		p.Text = ""
		p.Font = MockFont.new()
		p.Size = 14
		p.Width = 0
	end
	return p
end

local computeLayout

local function getChildOfClass(inst, cls)
	for _, ch in ipairs(inst._children) do
		if ch._className == cls then
			return ch
		end
	end
	return nil
end

local function computeTextSizeApprox(text, textSize, widthLimit, wrapped)
	text = tostring(text or "")
	if text == "" then
		return MockVector2.new(0, 0)
	end
	textSize = textSize or 14
	local charW = textSize * 0.52
	local lineH = math.ceil(textSize * 1.25)
	if not wrapped or not widthLimit or widthLimit <= 0 or widthLimit >= 1e6 then
		local lines = 1
		local maxChars = 0
		for line in (text .. "\n"):gmatch("(.-)\n") do
			maxChars = math.max(maxChars, #line)
			lines += 1
		end
		lines = math.max(1, lines - 1)
		return MockVector2.new(math.ceil(maxChars * charW), lines * lineH)
	end
	local charsPerLine = math.max(1, math.floor(widthLimit / charW))
	local totalLines = 0
	local maxLineW = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local len = #line
		if len == 0 then
			totalLines += 1
		else
			local wrappedLines = math.ceil(len / charsPerLine)
			totalLines += wrappedLines
			maxLineW = math.max(maxLineW, math.min(widthLimit, len * charW))
		end
	end
	return MockVector2.new(math.ceil(maxLineW), math.max(1, totalLines) * lineH)
end

local layoutDepth = 0

local function computePadding(inst, refSize)
	local pad = getChildOfClass(inst, "UIPadding")
	if not pad then
		return 0, 0, 0, 0
	end
	local p = pad._props
	local top = p.PaddingTop.Scale * refSize.Y + p.PaddingTop.Offset
	local bottom = p.PaddingBottom.Scale * refSize.Y + p.PaddingBottom.Offset
	local left = p.PaddingLeft.Scale * refSize.X + p.PaddingLeft.Offset
	local right = p.PaddingRight.Scale * refSize.X + p.PaddingRight.Offset
	return top, right, bottom, left
end

local function sortLayoutChildren(children, sortOrder)
	local list = {}
	for _, ch in ipairs(children) do
		if GUI_CLASSES[ch._className] and ch._props.Visible ~= false then
			table.insert(list, ch)
		end
	end
	if sortOrder == MockEnum.SortOrder.LayoutOrder then
		table.sort(list, function(a, b)
			local oa = a._props.LayoutOrder or 0
			local ob = b._props.LayoutOrder or 0
			if oa ~= ob then
				return oa < ob
			end
			return a._id < b._id
		end)
	else
		table.sort(list, function(a, b)
			if a._props.Name ~= b._props.Name then
				return tostring(a._props.Name) < tostring(b._props.Name)
			end
			return a._id < b._id
		end)
	end
	return list
end

local LAYOUT_PROPS = {
	Size = true,
	Position = true,
	AnchorPoint = true,
	AutomaticSize = true,
	Visible = true,
	LayoutOrder = true,
	Name = true,
	Text = true,
	TextSize = true,
	TextWrapped = true,
	PaddingTop = true,
	PaddingRight = true,
	PaddingBottom = true,
	PaddingLeft = true,
	Padding = true,
	FillDirection = true,
	SortOrder = true,
	CellSize = true,
	CellPadding = true,
	MinSize = true,
	MaxSize = true,
	Scale = true,
	CanvasPosition = true,
}

local function invalidateLayoutDown(inst)
	if not inst or inst._destroyed then
		return
	end
	if not inst._layoutValid and not inst._assignedListPos and not inst._listContentSize then
		return
	end
	inst._layoutValid = false
	inst._assignedListPos = nil
	inst._listContentSize = nil
	if inst._children then
		for _, ch in ipairs(inst._children) do
			invalidateLayoutDown(ch)
		end
	end
end

local function markLayoutDirty(inst)
	if not inst or inst._destroyed then
		return
	end
	local target = inst
	if not GUI_CLASSES[target._className] and target._className ~= "ScreenGui" then
		target = target._props and target._props.Parent
		if not target or target._destroyed then
			return
		end
	end
	invalidateLayoutDown(target)

	local p = target._props and target._props.Parent
	while p and not p._destroyed do
		if p._className == "ScreenGui" then
			break
		end
		if GUI_CLASSES[p._className] then
			local auto = p._props.AutomaticSize
			local hasLayout = getChildOfClass(p, "UIListLayout") ~= nil or getChildOfClass(p, "UIGridLayout") ~= nil
			if auto == MockEnum.AutomaticSize.None and not hasLayout then
				break
			end
			invalidateLayoutDown(p)
		end
		p = p._props and p._props.Parent
	end
end

local function layoutListChildren(parentInst, listLayout, innerPosX, innerPosY, innerW, innerH, depth)
	parentInst._computingListChildren = true
	local ordered = sortLayoutChildren(parentInst._children, listLayout._props.SortOrder)
	local isVert = listLayout._props.FillDirection == MockEnum.FillDirection.Vertical
	local gap = listLayout._props.Padding.Offset + listLayout._props.Padding.Scale * (isVert and math.max(innerH, 0) or math.max(innerW, 0))
	local cursorX = innerPosX
	local cursorY = innerPosY
	local totalMain = 0
	local maxCross = 0
	for idx, ch in ipairs(ordered) do
		ch._assignedListPos = MockVector2.new(cursorX, cursorY)
		local _, cAbsSize = computeLayout(ch, depth)
		if isVert then
			cursorY += cAbsSize.Y + gap
			totalMain += cAbsSize.Y + (idx > 1 and gap or 0)
			maxCross = math.max(maxCross, cAbsSize.X)
		else
			cursorX += cAbsSize.X + gap
			totalMain += cAbsSize.X + (idx > 1 and gap or 0)
			maxCross = math.max(maxCross, cAbsSize.Y)
		end
	end
	parentInst._listContentSize = isVert and MockVector2.new(maxCross, totalMain) or MockVector2.new(totalMain, maxCross)
	parentInst._computingListChildren = false
	return totalMain, maxCross
end

computeLayout = function(inst, depth)
	if not inst or inst._destroyed then
		return MockVector2.zero, MockVector2.zero, MockVector2.zero
	end
	if inst._className == "ScreenGui" then
		local pos = inst._props.IgnoreGuiInset and MockVector2.zero or MockVector2.new(GUI_INSET.X, GUI_INSET.Y)
		local size = inst._props.IgnoreGuiInset and VIEWPORT_SIZE or MockVector2.new(VIEWPORT_SIZE.X - GUI_INSET.X, VIEWPORT_SIZE.Y - GUI_INSET.Y)
		return pos, size, MockVector2.zero
	end
	if not GUI_CLASSES[inst._className] then
		return MockVector2.zero, MockVector2.zero, MockVector2.zero
	end
	if inst._layoutValid and inst._absPos and inst._absSize then
		return inst._absPos, inst._absSize, inst._autoSize or MockVector2.zero
	end
	if inst._layoutVisiting then
		return inst._prelimPos or MockVector2.zero, inst._prelimSize or MockVector2.zero, MockVector2.zero
	end

	depth = (depth or 0) + 1
	if depth > 256 then
		error("layout recursion depth exceeded at " .. tostring(inst._props and inst._props.Name), 2)
	end

	local parent = inst._props.Parent
	local parentPos = MockVector2.zero
	local parentSize = VIEWPORT_SIZE
	local padT, padR, padB, padL = 0, 0, 0, 0

	if parent and (parent._className == "ScreenGui" or GUI_CLASSES[parent._className]) then
		if parent._layoutVisiting then
			parentPos = parent._prelimPos or MockVector2.zero
			parentSize = parent._prelimSize or VIEWPORT_SIZE
		else
			parentPos, parentSize = computeLayout(parent, depth)
			if inst._layoutValid and inst._absPos and inst._absSize then
				return inst._absPos, inst._absSize, inst._autoSize or MockVector2.zero
			end
		end
		padT, padR, padB, padL = computePadding(parent, parentSize)
	end

	local canvasOffsetX = (parent and parent._className == "ScrollingFrame" and parent._props.CanvasPosition) and parent._props.CanvasPosition.X or 0
	local canvasOffsetY = (parent and parent._className == "ScrollingFrame" and parent._props.CanvasPosition) and parent._props.CanvasPosition.Y or 0
	local innerPos = MockVector2.new(parentPos.X + padL - canvasOffsetX, parentPos.Y + padT - canvasOffsetY)
	local innerSize = MockVector2.new(math.max(0, parentSize.X - padL - padR), math.max(0, parentSize.Y - padT - padB))

	if parent and GUI_CLASSES[parent._className] and not parent._computingListChildren and not inst._assignedListPos and inst._props.Visible ~= false then
		local pList = getChildOfClass(parent, "UIListLayout")
		if pList then
			layoutListChildren(parent, pList, innerPos.X, innerPos.Y, innerSize.X, innerSize.Y, depth)
			if inst._layoutValid and inst._absPos and inst._absSize then
				return inst._absPos, inst._absSize, inst._autoSize or MockVector2.zero
			end
		end
	end

	inst._layoutVisiting = true

	local sz = inst._props.Size
	local w = sz.X.Scale * innerSize.X + sz.X.Offset
	local h = sz.Y.Scale * innerSize.Y + sz.Y.Offset

	-- Apply UISizeConstraint
	local sizeConst = getChildOfClass(inst, "UISizeConstraint")
	if sizeConst then
		w = math.clamp(w, sizeConst._props.MinSize.X, sizeConst._props.MaxSize.X)
		h = math.clamp(h, sizeConst._props.MinSize.Y, sizeConst._props.MaxSize.Y)
	end

	local posProp = inst._props.Position
	local anchor = inst._props.AnchorPoint
	local prelimX, prelimY
	if inst._assignedListPos then
		prelimX = inst._assignedListPos.X
		prelimY = inst._assignedListPos.Y
	else
		prelimX = innerPos.X + posProp.X.Scale * innerSize.X + posProp.X.Offset - w * anchor.X
		prelimY = innerPos.Y + posProp.Y.Scale * innerSize.Y + posProp.Y.Offset - h * anchor.Y
	end
	inst._prelimPos = MockVector2.new(prelimX, prelimY)
	inst._prelimSize = MockVector2.new(w, h)
	local prelimW, prelimH = w, h

	-- Self padding & automatic size calculation
	local auto = inst._props.AutomaticSize
	local selfPadT, selfPadR, selfPadB, selfPadL = computePadding(inst, MockVector2.new(math.max(w, 0), math.max(h, 0)))

	local autoW, autoH = 0, 0
	if auto ~= MockEnum.AutomaticSize.None then
		if TEXT_CLASSES[inst._className] then
			local availW = (auto == MockEnum.AutomaticSize.Y) and math.max(0, w - selfPadL - selfPadR) or 1e6
			local tb = computeTextSizeApprox(inst._props.Text, inst._props.TextSize, availW, inst._props.TextWrapped)
			autoW = tb.X + selfPadL + selfPadR
			autoH = tb.Y + selfPadT + selfPadB
		end
		local listLayout = getChildOfClass(inst, "UIListLayout")
		local gridLayout = getChildOfClass(inst, "UIGridLayout")
		if listLayout then
			local selfInnerW = math.max(0, w - selfPadL - selfPadR)
			local selfInnerH = math.max(0, h - selfPadT - selfPadB)
			local isVert = listLayout._props.FillDirection == MockEnum.FillDirection.Vertical
			local totalMain, maxCross = layoutListChildren(inst, listLayout, prelimX + selfPadL, prelimY + selfPadT, selfInnerW, selfInnerH, depth)
			if isVert then
				autoW = math.max(autoW, maxCross + selfPadL + selfPadR)
				autoH = math.max(autoH, totalMain + selfPadT + selfPadB)
			else
				autoW = math.max(autoW, totalMain + selfPadL + selfPadR)
				autoH = math.max(autoH, maxCross + selfPadT + selfPadB)
			end
		elseif gridLayout then
			local ordered = sortLayoutChildren(inst._children, gridLayout._props.SortOrder)
			local cell = gridLayout._props.CellSize
			local pad = gridLayout._props.CellPadding
			local cw = cell.X.Scale * math.max(0, w - selfPadL - selfPadR) + cell.X.Offset
			local chH = cell.Y.Scale * math.max(0, h - selfPadT - selfPadB) + cell.Y.Offset
			local px = pad.X.Offset
			local py = pad.Y.Offset
			local cols = math.max(1, math.floor((math.max(w - selfPadL - selfPadR, cw) + px) / math.max(1, cw + px)))
			local rows = math.max(1, math.ceil(#ordered / cols))
			autoW = math.max(autoW, cols * cw + math.max(0, cols - 1) * px + selfPadL + selfPadR)
			autoH = math.max(autoH, rows * chH + math.max(0, rows - 1) * py + selfPadT + selfPadB)
		else
			for _, ch in ipairs(inst._children) do
				if GUI_CLASSES[ch._className] and ch._props.Visible ~= false then
					local _, cAbsSize = computeLayout(ch, depth)
					autoW = math.max(autoW, cAbsSize.X + selfPadL + selfPadR)
					autoH = math.max(autoH, cAbsSize.Y + selfPadT + selfPadB)
				end
			end
		end

		if auto == MockEnum.AutomaticSize.X or auto == MockEnum.AutomaticSize.XY then
			w = math.max(w, autoW)
		end
		if auto == MockEnum.AutomaticSize.Y or auto == MockEnum.AutomaticSize.XY then
			h = math.max(h, autoH)
		end
	end

	local uiScale = getChildOfClass(inst, "UIScale")
	if uiScale then
		local s = uiScale._props.Scale or 1
		w *= s
		h *= s
	end

	local absX, absY
	if inst._assignedListPos then
		absX = inst._assignedListPos.X
		absY = inst._assignedListPos.Y
	else
		absX = innerPos.X + posProp.X.Scale * innerSize.X + posProp.X.Offset - w * anchor.X
		absY = innerPos.Y + posProp.Y.Scale * innerSize.Y + posProp.Y.Offset - h * anchor.Y
	end

	inst._absPos = MockVector2.new(absX, absY)
	inst._absSize = MockVector2.new(w, h)
	inst._autoSize = MockVector2.new(autoW, autoH)
	inst._layoutValid = true
	inst._layoutVisiting = false

	-- Second pass for Scale/Position/Anchor children if AutomaticSize expanded the container
	local grewW = (auto == MockEnum.AutomaticSize.X or auto == MockEnum.AutomaticSize.XY) and math.abs(w - prelimW) > 0.01
	local grewH = (auto == MockEnum.AutomaticSize.Y or auto == MockEnum.AutomaticSize.XY) and math.abs(h - prelimH) > 0.01
	if grewW or grewH then
		for _, ch in ipairs(inst._children) do
			if GUI_CLASSES[ch._className] and ch._props.Visible ~= false then
				local p = ch._props
				local needsX = grewW and (p.Size.X.Scale ~= 0 or p.Position.X.Scale ~= 0 or p.AnchorPoint.X ~= 0)
				local needsY = grewH and (p.Size.Y.Scale ~= 0 or p.Position.Y.Scale ~= 0 or p.AnchorPoint.Y ~= 0)
				if needsX or needsY then
					invalidateLayoutDown(ch)
					computeLayout(ch, depth)
				end
			end
		end
	end

	return inst._absPos, inst._absSize, inst._autoSize
end

local nextInstanceId = 0
local focusedTextBox = nil
local MockInstance = {}

function MockInstance.new(className)
	nextInstanceId += 1
	local inst
	local props = createDefaultProps(className)
	local children = {}
	local attrs = {}
	local propSignals = {}
	local events = {
		Destroying = createSignal(),
		Changed = createSignal(),
		ChildAdded = createSignal(),
		ChildRemoved = createSignal(),
		AncestryChanged = createSignal(),
	}
	if GUI_CLASSES[className] then
		events.InputBegan = createSignal()
		events.InputChanged = createSignal()
		events.InputEnded = createSignal()
		events.MouseEnter = createSignal()
		events.MouseLeave = createSignal()
		events.MouseMoved = createSignal()
		events.MouseWheelForward = createSignal()
		events.MouseWheelBackward = createSignal()
	end
	if BUTTON_CLASSES[className] then
		events.MouseButton1Click = createSignal()
		events.MouseButton1Down = createSignal()
		events.MouseButton1Up = createSignal()
		events.MouseButton2Click = createSignal()
		events.MouseButton2Down = createSignal()
		events.Activated = createSignal()
	end
	if className == "TextBox" then
		events.Focused = createSignal()
		events.FocusLost = createSignal()
	end

	local methods = {}

	function methods:IsA(target)
		return isClassA(className, target)
	end

	function methods:GetChildren()
		local copy = {}
		for i, ch in ipairs(children) do
			copy[i] = ch
		end
		return copy
	end

	function methods:GetDescendants()
		local out = {}
		local function walk(node)
			for _, ch in ipairs(node._children) do
				table.insert(out, ch)
				walk(ch)
			end
		end
		walk(inst)
		return out
	end

	function methods:FindFirstChild(name, recursive)
		for _, ch in ipairs(children) do
			if ch._props.Name == name then
				return ch
			end
		end
		if recursive then
			for _, ch in ipairs(children) do
				local found = ch:FindFirstChild(name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end

	function methods:FindFirstChildOfClass(cls)
		for _, ch in ipairs(children) do
			if ch._className == cls then
				return ch
			end
		end
		return nil
	end

	function methods:FindFirstChildWhichIsA(cls, recursive)
		for _, ch in ipairs(children) do
			if ch:IsA(cls) then
				return ch
			end
		end
		if recursive then
			for _, ch in ipairs(children) do
				local found = ch:FindFirstChildWhichIsA(cls, true)
				if found then
					return found
				end
			end
		end
		return nil
	end

	function methods:FindFirstAncestor(name)
		local cur = props.Parent
		while cur do
			if cur._props.Name == name then
				return cur
			end
			cur = cur._props.Parent
		end
		return nil
	end

	function methods:FindFirstAncestorOfClass(cls)
		local cur = props.Parent
		while cur do
			if cur._className == cls then
				return cur
			end
			cur = cur._props.Parent
		end
		return nil
	end

	function methods:FindFirstAncestorWhichIsA(cls)
		local cur = props.Parent
		while cur do
			if cur:IsA(cls) then
				return cur
			end
			cur = cur._props.Parent
		end
		return nil
	end

	function methods:IsDescendantOf(ancestor)
		local cur = props.Parent
		while cur do
			if cur == ancestor then
				return true
			end
			cur = cur._props.Parent
		end
		return false
	end

	function methods:WaitForChild(name, _timeout)
		return inst:FindFirstChild(name)
	end

	function methods:GetPropertyChangedSignal(propName)
		if not propSignals[propName] then
			propSignals[propName] = createSignal()
		end
		return propSignals[propName]
	end

	function methods:GetAttribute(attrName)
		return attrs[attrName]
	end

	function methods:SetAttribute(attrName, value)
		attrs[attrName] = value
	end

	function methods:ClearAllChildren()
		for i = #children, 1, -1 do
			children[i]:Destroy()
		end
	end

	function methods:Clone()
		local copy = MockInstance.new(className)
		for k, v in pairs(props) do
			if k ~= "Parent" then
				copy[k] = v
			end
		end
		for k, v in pairs(attrs) do
			copy:SetAttribute(k, v)
		end
		for _, ch in ipairs(children) do
			local chCopy = ch:Clone()
			chCopy.Parent = copy
		end
		return copy
	end

	if className == "TextBox" then
		function methods:IsFocused()
			return focusedTextBox == inst
		end
		function methods:CaptureFocus()
			if focusedTextBox and focusedTextBox ~= inst then
				focusedTextBox:ReleaseFocus()
			end
			focusedTextBox = inst
			events.Focused:Fire()
		end
		function methods:ReleaseFocus(submitted)
			if focusedTextBox == inst then
				focusedTextBox = nil
				events.FocusLost:Fire(submitted == true, nil)
			end
		end
	end

	function methods:Destroy()
		if inst._destroyed then
			return
		end
		if focusedTextBox == inst then
			focusedTextBox = nil
		end
		inst._destroyed = true
		events.Destroying:Fire()
		for i = #children, 1, -1 do
			children[i]:Destroy()
		end
		inst.Parent = nil
		for _, sig in pairs(propSignals) do
			sig._listeners = {}
		end
		for _, sig in pairs(events) do
			sig._listeners = {}
		end
	end

	inst = {
		_id = nextInstanceId,
		_className = className,
		_props = props,
		_children = children,
		_attrs = attrs,
		_propSignals = propSignals,
		_events = events,
		_destroyed = false,
		_cachedAutoSize = nil,
	}

	setmetatable(inst, {
		__index = function(_, key)
			if methods[key] ~= nil then
				return methods[key]
			end
			if events[key] ~= nil then
				return events[key]
			end
			if key == "AbsolutePosition" then
				local p = computeLayout(inst)
				return p
			elseif key == "AbsoluteSize" then
				local _, s = computeLayout(inst)
				return s
			elseif key == "AbsoluteContentSize" then
				if className == "UIListLayout" or className == "UIGridLayout" then
					local p = props.Parent
					if p and GUI_CLASSES[p._className] then
						local pPos, pSize = computeLayout(p)
						if className == "UIListLayout" then
							if p._listContentSize then
								return p._listContentSize
							end
							local padT, padR, padB, padL = computePadding(p, pSize)
							local innerW = math.max(0, pSize.X - padL - padR)
							local innerH = math.max(0, pSize.Y - padT - padB)
							local totalMain, maxCross = layoutListChildren(p, inst, pPos.X + padL, pPos.Y + padT, innerW, innerH, 0)
							local isVert = props.FillDirection == MockEnum.FillDirection.Vertical
							return isVert and MockVector2.new(maxCross, totalMain) or MockVector2.new(totalMain, maxCross)
						else
							local padT, padR, padB, padL = computePadding(p, pSize)
							local innerW = math.max(0, pSize.X - padL - padR)
							local ordered = sortLayoutChildren(p._children, props.SortOrder)
							local cell = props.CellSize
							local pad = props.CellPadding
							local cw = cell.X.Scale * innerW + cell.X.Offset
							local chH = cell.Y.Scale * math.max(0, pSize.Y - padT - padB) + cell.Y.Offset
							local px, py = pad.X.Offset, pad.Y.Offset
							local cols = math.max(1, math.floor((math.max(innerW, cw) + px) / math.max(1, cw + px)))
							local rows = math.max(1, math.ceil(#ordered / cols))
							return MockVector2.new(cols * cw + math.max(0, cols - 1) * px, rows * chH + math.max(0, rows - 1) * py)
						end
					end
				end
				return MockVector2.zero
			elseif key == "AbsoluteWindowSize" then
				local _, s = computeLayout(inst)
				return s
			elseif key == "TextBounds" and TEXT_CLASSES[className] then
				local _, s = computeLayout(inst)
				return computeTextSizeApprox(props.Text, props.TextSize, s.X, props.TextWrapped)
			elseif key == "TextFits" then
				return true
			end
			if props[key] ~= nil then
				return props[key]
			end
			return nil
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local oldParent = props.Parent
				if oldParent == value then
					return
				end
				if oldParent and oldParent._children then
					markLayoutDirty(inst)
					for i, ch in ipairs(oldParent._children) do
						if ch == inst then
							table.remove(oldParent._children, i)
							break
						end
					end
					if oldParent._events and oldParent._events.ChildRemoved then
						oldParent._events.ChildRemoved:Fire(inst)
					end
				end
				if value and value._denyChildren then
					error("Unable to assign Parent to locked container " .. tostring(value._className), 2)
				end
				props.Parent = value
				if value and value._children then
					table.insert(value._children, inst)
					if value._events and value._events.ChildAdded then
						value._events.ChildAdded:Fire(inst)
					end
				end
				markLayoutDirty(inst)
				if propSignals.Parent then
					propSignals.Parent:Fire()
				end
				events.AncestryChanged:Fire(inst, value)
				events.Changed:Fire("Parent")
				return
			end

			local oldVal = props[key]
			props[key] = value
			if oldVal ~= value then
				if LAYOUT_PROPS[key] then
					markLayoutDirty(inst)
				end
				if propSignals[key] then
					propSignals[key]:Fire()
				end
				events.Changed:Fire(key)
			end
		end,
		__tostring = function()
			return tostring(props.Name or className)
		end,
	})

	return tagType(inst, "Instance")
end

-- ─── Mock Services ───────────────────────────────────────────────────────────

local keysDown = {}
local mockMouseLocation = MockVector2.new(640, 360)

local function buildServices(opts)
	opts = opts or {}
	local activeTweens = {}

	local TweenService = {
		Create = function(_, instance, tweenInfo, propTable)
			local state = MockEnum.PlaybackState.Begin
			local completedSig = createSignal()
			local pendingDefer = nil
			local tweenObj = {
				PlaybackState = state,
				Completed = completedSig,
				Instance = instance,
				TweenInfo = tweenInfo,
			}
			function tweenObj:Play()
				if pendingDefer then
					MockTask.cancel(pendingDefer)
					pendingDefer = nil
				end
				tweenObj.PlaybackState = MockEnum.PlaybackState.Playing
				if instance and not instance._destroyed then
					for k, v in pairs(propTable or {}) do
						local ok, err = pcall(function()
							instance[k] = v
						end)
						if not ok then
							table.insert(testFailures, string.format("[TWEEN ERROR] Failed setting %s on %s: %s", tostring(k), tostring(instance), tostring(err)))
						end
					end
				end
				pendingDefer = MockTask.defer(function()
					pendingDefer = nil
					if tweenObj.PlaybackState == MockEnum.PlaybackState.Playing then
						tweenObj.PlaybackState = MockEnum.PlaybackState.Completed
						completedSig:Fire(MockEnum.PlaybackState.Completed)
					end
				end)
			end
			function tweenObj:Cancel()
				if pendingDefer then
					MockTask.cancel(pendingDefer)
					pendingDefer = nil
				end
				if tweenObj.PlaybackState ~= MockEnum.PlaybackState.Completed then
					tweenObj.PlaybackState = MockEnum.PlaybackState.Cancelled
					completedSig:Fire(MockEnum.PlaybackState.Cancelled)
				end
			end
			function tweenObj:Pause()
				if pendingDefer then
					MockTask.cancel(pendingDefer)
					pendingDefer = nil
				end
				tweenObj.PlaybackState = MockEnum.PlaybackState.Paused
			end
			table.insert(activeTweens, tweenObj)
			return tweenObj
		end,
	}

	local UserInputService = {
		TouchEnabled = false,
		KeyboardEnabled = true,
		MouseEnabled = true,
		InputBegan = createSignal(),
		InputChanged = createSignal(),
		InputEnded = createSignal(),
		WindowFocused = createSignal(),
		WindowFocusReleased = createSignal(),
		GetMouseLocation = function()
			return mockMouseLocation
		end,
		GetFocusedTextBox = function()
			return focusedTextBox
		end,
		IsKeyDown = function(_, keyCode)
			return keysDown[keyCode] == true
		end,
	}

	local RunService = {
		RenderStepped = createSignal(),
		Heartbeat = createSignal(),
		Stepped = createSignal(),
		IsStudio = function()
			return opts.isStudio == true
		end,
		IsClient = function()
			return true
		end,
	}
	RunServiceRef = RunService

	local playerGui = MockInstance.new("Folder")
	playerGui.Name = "PlayerGui"

	local localPlayer = MockInstance.new("Folder")
	localPlayer.Name = "Tester"
	localPlayer._props.DisplayName = "TestUser"
	localPlayer._props.UserId = 1
	playerGui.Parent = localPlayer

	local Players = {
		LocalPlayer = localPlayer,
		MaxPlayers = 20,
		GetPlayers = function()
			return { localPlayer }
		end,
		GetUserThumbnailAsync = function(_, userId, _thumbType, _thumbSize)
			return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=48&h=48", true
		end,
	}

	local GuiService = {
		GetGuiInset = function()
			return GUI_INSET, GUI_INSET
		end,
	}

	-- Pure-Lua JSON for HttpService mock
	local function jsonEncode(val)
		local t = type(val)
		if val == nil then
			return "null"
		elseif t == "boolean" then
			return val and "true" or "false"
		elseif t == "number" then
			return string.format("%.14g", val)
		elseif t == "string" then
			local esc = val:gsub('[%z\1-\31"\\]', function(c)
				local m = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
				return m[c] or string.format("\\u%04x", string.byte(c))
			end)
			return '"' .. esc .. '"'
		elseif t == "table" then
			local n = #val
			local isArr = true
			local count = 0
			for k in pairs(val) do
				count += 1
				if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
					isArr = false
					break
				end
			end
			if count == 0 then
				return "{}"
			end
			local out = {}
			if isArr then
				for i = 1, n do
					out[i] = jsonEncode(val[i])
				end
				return "[" .. table.concat(out, ",") .. "]"
			else
				for k, v in pairs(val) do
					table.insert(out, jsonEncode(tostring(k)) .. ":" .. jsonEncode(v))
				end
				return "{" .. table.concat(out, ",") .. "}"
			end
		end
		return "null"
	end

	local function jsonDecode(str)
		local pos = 1
		local len = #str
		local function skipWs()
			local _, e = str:find("^[ \t\r\n]+", pos)
			if e then pos = e + 1 end
		end
		local parseVal
		local function parseStr()
			pos += 1
			local buf = {}
			while pos <= len do
				local c = str:sub(pos, pos)
				if c == '"' then
					pos += 1
					return table.concat(buf)
				elseif c == "\\" then
					pos += 1
					local e = str:sub(pos, pos)
					local m = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
					if m[e] then
						table.insert(buf, m[e])
						pos += 1
					elseif e == "u" then
						local code = tonumber(str:sub(pos + 1, pos + 4), 16) or 63
						table.insert(buf, code < 128 and string.char(code) or "?")
						pos += 5
					else
						error("Bad JSON escape")
					end
				else
					table.insert(buf, c)
					pos += 1
				end
			end
			error("Unterminated string")
		end
		parseVal = function()
			skipWs()
			local c = str:sub(pos, pos)
			if c == '"' then
				return parseStr()
			elseif c == "{" then
				pos += 1
				local obj = {}
				skipWs()
				if str:sub(pos, pos) == "}" then pos += 1; return obj end
				while true do
					skipWs()
					local k = parseStr()
					skipWs()
					assert(str:sub(pos, pos) == ":", "Expected ':'")
					pos += 1
					obj[k] = parseVal()
					skipWs()
					local sep = str:sub(pos, pos)
					pos += 1
					if sep == "}" then return obj end
					assert(sep == ",", "Expected ','")
				end
			elseif c == "[" then
				pos += 1
				local arr = {}
				skipWs()
				if str:sub(pos, pos) == "]" then pos += 1; return arr end
				while true do
					table.insert(arr, parseVal())
					skipWs()
					local sep = str:sub(pos, pos)
					pos += 1
					if sep == "]" then return arr end
					assert(sep == ",", "Expected ','")
				end
			elseif str:sub(pos, pos + 3) == "true" then pos += 4; return true
			elseif str:sub(pos, pos + 4) == "false" then pos += 5; return false
			elseif str:sub(pos, pos + 3) == "null" then pos += 4; return nil
			else
				local numStr = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
				assert(numStr and numStr ~= "", "Invalid JSON token at " .. pos)
				pos += #numStr
				return tonumber(numStr)
			end
		end
		return parseVal()
	end

	local HttpService = {
		JSONEncode = function(_, tbl)
			return jsonEncode(tbl)
		end,
		JSONDecode = function(_, str)
			return jsonDecode(str)
		end,
	}

	local Lighting = MockInstance.new("Folder")
	Lighting.Name = "Lighting"

	local TextService = {
		GetTextSize = function(_, text, textSize, _font, frameSize)
			return computeTextSizeApprox(text, textSize, frameSize and frameSize.X or 1e6, true)
		end,
		GetTextBoundsAsync = function(_, params)
			return computeTextSizeApprox(params.Text, params.Size, params.Width or 0, (params.Width or 0) > 0)
		end,
	}

	local ContentProvider = {
		PreloadAsync = function(_, instances, callback)
			if type(callback) == "function" then
				for _, inst in ipairs(instances or {}) do
					local id = (type(inst) == "table" and inst.Image) or tostring(inst)
					callback(id, MockEnum.AssetFetchStatus.Success)
				end
			end
		end,
	}

	local Stats = {
		Network = {
			ServerStatsItem = {
				["Data Ping"] = {
					GetValue = function()
						return 28
					end,
				},
			},
		},
	}

	local CoreGui = MockInstance.new("Folder")
	CoreGui.Name = "CoreGui"
	if opts.denyCoreGui then
		CoreGui._denyChildren = true
	end

	local Workspace = MockInstance.new("Folder")
	Workspace.Name = "Workspace"
	Workspace._props.CurrentCamera = {
		ViewportSize = VIEWPORT_SIZE,
	}

	local services = {
		TweenService = TweenService,
		UserInputService = UserInputService,
		RunService = RunService,
		Players = Players,
		GuiService = GuiService,
		HttpService = HttpService,
		Lighting = Lighting,
		TextService = TextService,
		ContentProvider = ContentProvider,
		Stats = Stats,
		CoreGui = CoreGui,
		Workspace = Workspace,
	}

	local gameObj = {
		PlaceId = 123456,
		GameId = 789012,
	}
	function gameObj:GetService(name)
		local svc = services[name]
		if not svc then
			error("[MockGame] Unknown service requested: " .. tostring(name), 2)
		end
		return svc
	end

	return gameObj, services, playerGui, CoreGui
end

-- ─── Install Globals Helper ──────────────────────────────────────────────────

local vfsFiles = {}
local vfsFolders = { [""] = true }
local mockClipboard = ""
local mockGenv = {}
local hiddenUI = MockInstance.new("Folder")
hiddenUI.Name = "HiddenUI"

local function normPath(p)
	return (tostring(p or ""):gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", ""))
end

local function makeBaseEnv()
	local base = {
		print = origPrint,
		pcall = pcall,
		xpcall = xpcall,
		error = error,
		assert = assert,
		type = type,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		select = select,
		tonumber = tonumber,
		tostring = tostring,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		getmetatable = getmetatable,
		setmetatable = setmetatable,
		getfenv = getfenv,
		setfenv = setfenv,
		loadstring = loadstring,
		require = origRequire,
		unpack = unpack,
		math = math,
		string = string,
		table = table,
		coroutine = coroutine,
		bit32 = bit32,
		utf8 = utf8,
		os = os,
		debug = debug,
		buffer = buffer,
	}
	base._G = {}
	return base
end

local function installEnvironment(mode)
	-- mode: "executor" | "studio"
	local env = makeBaseEnv()
	local gameObj, services, playerGui, coreGui = buildServices({
		isStudio = (mode == "studio"),
		denyCoreGui = (mode == "studio"),
	})

	local globals = {
		typeof = mockTypeof,
		Color3 = MockColor3,
		UDim = MockUDim,
		UDim2 = MockUDim2,
		Vector2 = MockVector2,
		Rect = MockRect,
		Font = MockFont,
		ColorSequence = MockColorSequence,
		ColorSequenceKeypoint = MockColorSequenceKeypoint,
		NumberSequence = MockNumberSequence,
		NumberSequenceKeypoint = MockNumberSequenceKeypoint,
		TweenInfo = MockTweenInfo,
		Enum = MockEnum,
		Instance = MockInstance,
		task = MockTask,
		tick = function()
			return virtualClock
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			local msg = table.concat(parts, " ")
			table.insert(capturedWarnings, msg)
			origWarn("[CAPTURED WARN] " .. msg)
		end,
		game = gameObj,
		workspace = services.Workspace,
	}

	if mode == "executor" then
		globals.gethui = function()
			return hiddenUI
		end
		globals.getgenv = function()
			return mockGenv
		end
		globals.cloneref = function(obj)
			return obj
		end
		globals.setclipboard = function(str)
			mockClipboard = tostring(str or "")
		end
		globals.getcustomasset = function(path)
			return "rbxasset://custom/" .. normPath(path)
		end
		globals.writefile = function(path, contents)
			local np = normPath(path)
			vfsFiles[np] = tostring(contents or "")
		end
		globals.readfile = function(path)
			local np = normPath(path)
			local data = vfsFiles[np]
			if data == nil then
				error("File not found: " .. np, 2)
			end
			return data
		end
		globals.isfile = function(path)
			return vfsFiles[normPath(path)] ~= nil
		end
		globals.isfolder = function(path)
			return vfsFolders[normPath(path)] == true
		end
		globals.makefolder = function(path)
			vfsFolders[normPath(path)] = true
		end
		globals.listfiles = function(path)
			local np = normPath(path)
			local prefix = np == "" and "" or (np .. "/")
			local out = {}
			for fPath in pairs(vfsFiles) do
				if fPath:sub(1, #prefix) == prefix then
					local rest = fPath:sub(#prefix + 1)
					if not rest:find("/") then
						table.insert(out, fPath)
					end
				end
			end
			table.sort(out)
			return out
		end
		globals.delfile = function(path)
			vfsFiles[normPath(path)] = nil
		end
	end

	for k, v in pairs(globals) do
		env[k] = v
	end

	return env, gameObj, services, playerGui, coreGui
end

local function runBundleFile(filePath, env, chunkName)
	if type(zune) == "table" and zune.fs and zune.luau then
		local src = zune.fs.readFileSync(filePath)
		local bc = zune.luau.compile(src)
		local fn = zune.luau.load(bc, {
			env = env,
			chunkname = chunkName or ("@" .. filePath),
		})
		return fn()
	else
		return origRequire("../" .. filePath:gsub("%.lua$", ""))
	end
end

local Color3 = MockColor3
local Enum = MockEnum

-- Helper to simulate input events on UserInputService and/or GuiObject
local function makeInputObj(userInputType, keyCode, position)
	return {
		UserInputType = userInputType or MockEnum.UserInputType.Keyboard,
		KeyCode = keyCode or MockEnum.KeyCode.Unknown,
		Position = position or MockVector2.new(0, 0),
		UserInputState = Enum.UserInputState and Enum.UserInputState.Begin or nil,
	}
end

local function fireKeyPress(services, keyCode, ctrlHeld)
	local UIS = services.UserInputService
	if ctrlHeld then
		keysDown[MockEnum.KeyCode.LeftControl] = true
	end
	local inp = makeInputObj(MockEnum.UserInputType.Keyboard, keyCode)
	UIS.InputBegan:Fire(inp, false)
	stepClock(0.02, true)
	UIS.InputEnded:Fire(inp, false)
	if ctrlHeld then
		keysDown[MockEnum.KeyCode.LeftControl] = nil
	end
	stepClock(0.02, true)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- PASS 1: EXECUTOR ENVIRONMENT (dist/BaliExample.lua)
-- ══════════════════════════════════════════════════════════════════════════════

log("=== PASS 1: EXECUTOR ENVIRONMENT (dist/BaliExample.lua) ===")
local env1, game1, services1, playerGui1, coreGui1 = installEnvironment("executor")

local okEx, exErr = xpcall(function()
	runBundleFile("dist/BaliExample.lua", env1, "@dist/BaliExample.lua")
end, debug.traceback)

assertTrue(okEx, "dist/BaliExample.lua executed without error: " .. tostring(exErr))
stepClock(0.2, true)

local Bali = mockGenv._BaliInstance
assertTrue(type(Bali) == "table", "Bali instance registered in getgenv()._BaliInstance")
assertTrue(#Bali._windows == 1, "One active Window mounted")

local window = Bali._windows[1]
assertTrue(window ~= nil, "Window object exists")
assertTrue(Bali._screenGui ~= nil and Bali._screenGui:IsA("ScreenGui"), "ScreenGui exists and is ScreenGui")
assertEq(Bali._screenGui.Parent, hiddenUI, "ScreenGui parented under gethui() HiddenUI")

-- Verify GUI tree structure
local screenGui = Bali._screenGui
assertTrue(screenGui:FindFirstChild("BaliMainLayer") ~= nil, "BaliMainLayer exists")
assertTrue(screenGui:FindFirstChild("BaliHUDLayer") ~= nil, "BaliHUDLayer exists")
assertTrue(screenGui:FindFirstChild("BaliPopupLayer") ~= nil, "BaliPopupLayer exists")
assertTrue(screenGui:FindFirstChild("BaliDialogLayer") ~= nil, "BaliDialogLayer exists")
assertTrue(screenGui:FindFirstChild("BaliNotificationLayer") ~= nil, "BaliNotificationLayer exists")
assertTrue(window.Sidebar ~= nil, "Sidebar exists")
assertTrue(window.BodyArea ~= nil, "BodyArea exists")
assertTrue(#window.Tabs >= 4, "Tabs populated (" .. tostring(#window.Tabs) .. ")")

-- Verify CreateWindow dictionary options survived option cloning
assertEq(window.Title, "Bali Suite", "Window.Title preserved from CreateWindow opts")
assertEq(window.Subtitle, "v1.0.0", "Window.Subtitle preserved from CreateWindow opts")
assertEq(window._configFolder, "BaliShowcase", "Window._configFolder preserved from CreateWindow opts")
assertEq(Bali.Blur.IsEnabled(), true, "Blur auto-enabled from CreateWindow opts")
assertEq(Bali.Blur.GetIntensity(), 12, "BlurIntensity=12 preserved from CreateWindow opts")
assertEq(Bali.Watermark.IsVisible(), true, "Watermark auto-enabled from CreateWindow opts")
assertEq(Bali.Theme.Name, "Graphite", "Default Theme.Name is Graphite")

-- Sidebar collapse / expand cycle
window:ToggleSidebar(true)
stepClock(0.25, true)
assertEq(window._sidebarCollapsed, true, "Window:ToggleSidebar(true) collapsed sidebar")
assertTrue(window.Sidebar.Size.X.Offset <= 80, "Collapsed sidebar width <= 80 (" .. tostring(window.Sidebar.Size.X.Offset) .. ")")
window:ToggleSidebar(false)
stepClock(0.25, true)
assertEq(window._sidebarCollapsed, false, "Window:ToggleSidebar(false) restored sidebar")

-- Mobile toggle pill & Window SetVisible cycle (Rayfield pill morph + restore cascade)
assertTrue(window._mobileButton ~= nil, "MobileButton initialized on Window")
window:SetVisible(false)
stepClock(0.25, true)
assertEq(window:IsVisible(), false, "Window:SetVisible(false) hides window")
assertEq(window._mobileButton.Frame.Visible, true, "MobileButton visible when window is hidden")
window:SetVisible(true)
stepClock(0.25, true)
assertEq(window:IsVisible(), true, "Window:SetVisible(true) restores window")
assertEq(window.Sidebar.Visible, true, "Window Sidebar restored after pill morph")
assertEq(window.BodyArea.Visible, true, "Window BodyArea restored after pill morph")

-- Popup Open / Close lifecycle for Dropdown and ColorPicker
local regFlags = window.Flags or window._registry
assertTrue(regFlags["Pickers_Strategy"] ~= nil, "Dropdown flag Pickers_Strategy exists")
assertTrue(regFlags["Pickers_Swatch"] ~= nil, "ColorPicker flag Pickers_Swatch exists")
window:SelectTab(window.Tabs[2], true)
stepClock(0.05, true)
regFlags["Pickers_Strategy"]:Open()
stepClock(0.15, true)
assertTrue(window._activePopup ~= nil, "Dropdown:Open() registers active popup")
regFlags["Pickers_Strategy"]:Close()
stepClock(0.15, true)
assertEq(window._activePopup, nil, "Dropdown:Close() clears active popup")

regFlags["Pickers_Swatch"]:Open()
stepClock(0.15, true)
assertTrue(window._activePopup ~= nil, "ColorPicker:Open() registers active popup")
regFlags["Pickers_Swatch"]:Close()
stepClock(0.15, true)
assertEq(window._activePopup, nil, "ColorPicker:Close() clears active popup")
window:SelectTab(window.Tabs[1], true)
stepClock(0.05, true)

-- LoadingScreen lifecycle
local loaderCtrl = Bali:LoadingScreen({
	Title = "Bali Boot",
	Subtitle = "Preparing modules...",
	Duration = 0.2,
	AutoClose = false,
})
stepClock(0.1, true)
assertTrue(loaderCtrl ~= nil and type(loaderCtrl.SetProgress) == "function", "LoadingScreen returns controller")
loaderCtrl:SetProgress(0.65, "Indexing icons...")
loaderCtrl:SetStatus("Almost ready")
stepClock(0.05, true)
loaderCtrl:Close()
stepClock(0.25, true)
loaderCtrl:Destroy()

-- KeySystem lifecycle (reject invalid key, Supported/Not Supported badges, verify valid demo key, invoke OnSuccess)
assertEq(Bali.Util.ExtractInviteCode("https://discord.gg/bali123?foo=bar"), "bali123", "ExtractInviteCode normalizes invite URL")
local unsupportedCtrl = Bali:KeySystem({
	Title = "Unsupported Check",
	Key = "X",
	SupportedGames = { [999999999] = "Other Game" },
})
stepClock(0.05, true)
local sawNotSupported = false
for _, desc in ipairs(unsupportedCtrl.Frame:GetDescendants()) do
	if desc:IsA("TextLabel") and desc.Text == "Not Supported" then
		sawNotSupported = true
		break
	end
end
assertTrue(sawNotSupported, "KeySystem renders Not Supported badge when game is not listed")
unsupportedCtrl:Destroy()

local verifiedKeyValue = nil
local keyCtrl = Bali:KeySystem({
	Title = "License Check",
	Subtitle = "Enter access key",
	Version = "v2.0",
	Key = "BALI-DEMO",
	SupportedGames = { [game1.PlaceId] = "Demo Place" },
	SaveKey = false,
	OnSuccess = function(entered)
		verifiedKeyValue = entered
	end,
})
stepClock(0.1, true)
assertTrue(keyCtrl ~= nil and keyCtrl.Frame ~= nil, "KeySystem returns controller with Frame")
local sawSupported = false
for _, desc in ipairs(keyCtrl.Frame:GetDescendants()) do
	if desc:IsA("TextLabel") and desc.Text == "Supported" then
		sawSupported = true
		break
	end
end
assertTrue(sawSupported, "KeySystem renders Supported badge when PlaceId matches SupportedGames")
local checkKeyBtn = nil
for _, desc in ipairs(keyCtrl.Frame:GetDescendants()) do
	if desc:IsA("TextButton") and desc.BackgroundTransparency == 0 then
		checkKeyBtn = desc
	end
end
assertTrue(checkKeyBtn ~= nil, "KeySystem action button renders opaque BackgroundTransparency == 0")
local keyBox = keyCtrl.Frame:FindFirstChildWhichIsA("TextBox", true)
assertTrue(keyBox ~= nil, "KeySystem TextBox found")
keyBox:CaptureFocus()
keyBox.Text = "WRONG-KEY"
keyBox:ReleaseFocus(true)
stepClock(0.2, true)
assertEq(keyCtrl.Verified, false, "KeySystem rejects invalid key")
keyBox:CaptureFocus()
keyBox.Text = "BALI-DEMO"
keyBox:ReleaseFocus(true)
stepClock(0.6, true)
assertEq(keyCtrl.Verified, true, "KeySystem verifies BALI-DEMO")
assertEq(verifiedKeyValue, "BALI-DEMO", "KeySystem triggers OnSuccess with verified key")
keyCtrl:Destroy()
stepClock(0.1, true)

-- 1. Switch between EVERY Tab and SubTab
log("--- Exercising Tabs & SubTabs ---")
for _, tab in ipairs(window.Tabs) do
	local okTab, errTab = pcall(function()
		tab:Select()
		stepClock(0.05, true)
		if tab.SubTabs then
			for _, sub in ipairs(tab.SubTabs) do
				sub:Select()
				stepClock(0.05, true)
			end
		end
	end)
	assertTrue(okTab, "Tab/SubTab select clean for " .. tostring(tab.Title) .. ": " .. tostring(errTab))
end

-- 2. Exercise Flag elements
log("--- Exercising Flagged Elements ---")
local flags = window.Flags or window._registry
assertTrue(flags["Dashboard_LiveStream"] ~= nil, "Flag Dashboard_LiveStream exists")
flags["Dashboard_LiveStream"]:Set(true)
assertEq(flags["Dashboard_LiveStream"]:Get(), true, "Toggle:Set(true)")
stepClock(1.6, true) -- lets background telemetry stream fire a tick!
flags["Dashboard_LiveStream"]:Set(false)
assertEq(flags["Dashboard_LiveStream"]:Get(), false, "Toggle:Set(false)")

flags["Controls_SmartAutomation"]:Set(false)
assertEq(flags["Controls_SmartAutomation"]:Get(), false, "Controls_SmartAutomation Toggle:Set(false)")
flags["Controls_SmartAutomation"]:Set(true)
assertEq(flags["Controls_SmartAutomation"]:Get(), true, "Controls_SmartAutomation Toggle:Set(true)")
do
	local togTrack = flags["Controls_SmartAutomation"].Frame:FindFirstChild("Track", true)
	local togKnob = togTrack and togTrack:FindFirstChild("Knob")
	local knobGlow = togKnob and togKnob:FindFirstChild("KnobGlow")
	assertTrue(togKnob ~= nil and knobGlow ~= nil, "Toggle Knob creates KnobGlow accent bloom")
end

flags["Controls_StrictValidation"]:Set(false)
assertEq(flags["Controls_StrictValidation"]:Get(), false, "Checkbox:Set(false)")
flags["Controls_StrictValidation"]:Set(true)
assertEq(flags["Controls_StrictValidation"]:Get(), true, "Checkbox:Set(true)")
do
	local cbBox = flags["Controls_StrictValidation"].Frame:FindFirstChild("CheckBox", true)
	local cbFill = cbBox and cbBox:FindFirstChild("InnerFill")
	local cbGlow = cbBox and cbBox:FindFirstChild("BoxGlow")
	assertTrue(cbBox ~= nil and cbFill ~= nil and cbGlow ~= nil, "Checkbox CheckBox creates InnerFill and BoxGlow")
end

flags["Controls_PollingHz"]:Set(180)
assertEq(flags["Controls_PollingHz"]:Get(), 180, "Slider:Set(180)")

flags["Controls_LatencyBand"]:Set(30, 140)
local band = flags["Controls_LatencyBand"]:Get()
assertEq(band.Min, 30, "RangeSlider:Set Min=30")
assertEq(band.Max, 140, "RangeSlider:Set Max=140")

flags["Controls_WorkerThreads"]:Set(12)
assertEq(flags["Controls_WorkerThreads"]:Get(), 12, "Stepper:Set(12)")

flags["Pickers_Strategy"]:Set("High Throughput")
assertEq(flags["Pickers_Strategy"]:Get(), "High Throughput", "Dropdown single Set")
do
	local stratTrigger = flags["Pickers_Strategy"].Frame:FindFirstChild("Trigger", true)
	local trigIcon = stratTrigger and stratTrigger:FindFirstChild("TriggerIcon")
	local trigRight = stratTrigger and stratTrigger:FindFirstChild("TriggerRightText")
	local trigBadge = stratTrigger and stratTrigger:FindFirstChild("TriggerBadge")
	assertTrue(trigIcon ~= nil and trigIcon.Visible == true, "Dropdown Trigger renders selected item TriggerIcon")
	assertTrue(trigRight ~= nil and trigRight.Visible == true and trigRight.Text == "10k/s", "Dropdown Trigger renders selected item TriggerRightText")
	flags["Pickers_Strategy"]:Set("Balanced")
	assertTrue(trigIcon ~= nil and trigIcon.Visible == true, "Dropdown Trigger updates TriggerIcon on selection change")
	assertTrue(trigBadge ~= nil and trigBadge.Visible == true, "Dropdown Trigger renders selected item TriggerBadge")
	local bTxt = trigBadge and trigBadge:FindFirstChild("BadgeText")
	assertEq(bTxt and bTxt.Text, "Auto", "Dropdown TriggerBadge displays badge text")
	flags["Pickers_Strategy"]:Set("High Throughput")
end

flags["Pickers_Clusters"]:Set({ "US-West (Oregon)", "AP-Northeast (Tokyo)" })
local multiVal = flags["Pickers_Clusters"]:Get()
assertTrue(type(multiVal) == "table" and #multiVal == 2, "Dropdown multi Set")
do
	local multiTrigger = flags["Pickers_Clusters"].Frame:FindFirstChild("Trigger", true)
	local mIcon = multiTrigger and multiTrigger:FindFirstChild("TriggerIcon")
	local mBadge = multiTrigger and multiTrigger:FindFirstChild("TriggerBadge")
	assertTrue(mIcon == nil or mIcon.Visible == false, "Multi-select hides single-item TriggerIcon when 2+ options active")
	assertTrue(mBadge == nil or mBadge.Visible == false, "Multi-select hides single-item TriggerBadge when 2+ options active")
end

flags["Pickers_SamplingWindow"]:Set("Burst")
assertEq(flags["Pickers_SamplingWindow"]:Get(), "Burst", "Segmented:Set('Burst')")

flags["Pickers_Alias"]:Set("Staging-Beta")
assertEq(flags["Pickers_Alias"]:Get(), "Staging-Beta", "Input:Set('Staging-Beta')")

flags["Pickers_Port"]:Set("9000")
assertEq(flags["Pickers_Port"]:Get(), "9000", "Numeric Input:Set('9000')")

local newColor = Color3.fromRGB(52, 211, 153)
flags["Pickers_Swatch"]:Set(newColor, 0.4)
local cpCol, cpAlpha = flags["Pickers_Swatch"]:Get()
assertTrue(cpCol == newColor and math.abs(cpAlpha - 0.4) < 0.05, "ColorPicker:Set(color, alpha)")

flags["Pickers_CaptureKey"]:Set(Enum.KeyCode.H, "Hold")
assertEq(flags["Pickers_CaptureKey"]:Get(), Enum.KeyCode.H, "Keybind:Set(Enum.KeyCode.H)")

local diagAcc = flags["Layout_DiagAccordion"]
assertTrue(diagAcc ~= nil, "Accordion flag exists")
diagAcc:Collapse()
assertEq(diagAcc:IsExpanded(), false, "Accordion:Collapse()")
diagAcc:Expand()
assertEq(diagAcc:IsExpanded(), true, "Accordion:Expand()")

-- Lock / Unlock check
local lockedSlider = flags["Controls_ProtectedGain"]
lockedSlider:Unlock()
lockedSlider:Set(80)
assertEq(lockedSlider:Get(), 80, "Unlocked slider Set(80)")
lockedSlider:Lock("Locked in test")

-- Exercise non-flagged elements from window._elements
log("--- Exercising Buttons, Sections, Analytics ---")
local testedTypes = {}
for _, entry in ipairs(window._elements) do
	local el = entry.Element
	if entry.Type == "Button" and not testedTypes.Button and el.Title == "Probe Latency" then
		testedTypes.Button = true
		el:Fire()
	elseif entry.Type == "StatCard" and not testedTypes.StatCard then
		testedTypes.StatCard = true
		el:SetValue(250000, 12.5)
	elseif entry.Type == "Chart" and not testedTypes.Chart then
		testedTypes.Chart = true
		el:SetPoints({ 10, 20, 30, 40 }, { "A", "B", "C", "D" })
		el:Push(55, "E")
	elseif entry.Type == "ProgressBar" and not testedTypes.ProgressBar then
		testedTypes.ProgressBar = true
		el:Set(77, 100, "77%")
	elseif entry.Type == "Table" and not testedTypes.Table then
		testedTypes.Table = true
		el:SetRows({
			{ Node = "test-node-1", Region = "Frankfurt", Latency = "11 ms", Status = { Text = "Optimal", Color = "Success", Badge = true } },
			{ Node = "test-node-2", Region = "Tokyo", Latency = "35 ms", Status = { Text = "Elevated", Color = "Warning", Badge = true } },
		})
	elseif entry.Type == "CardGrid" and not testedTypes.CardGrid then
		testedTypes.CardGrid = true
		el:SetActive("thu")
	end
end
assertTrue(testedTypes.Button, "Exercised Button:Fire()")
assertTrue(testedTypes.StatCard, "Exercised StatCard:SetValue()")
assertTrue(testedTypes.Chart, "Exercised Chart:SetPoints()/Push()")
assertTrue(testedTypes.ProgressBar, "Exercised ProgressBar:Set()")
assertTrue(testedTypes.Table, "Exercised Table:SetRows()")
assertTrue(testedTypes.CardGrid, "Exercised CardGrid:SetActive()")

-- Section SetOpen / Toggle
local firstTab = window.Tabs[1]
if firstTab and firstTab.Sections and firstTab.Sections[2] then
	local sec = firstTab.Sections[2]
	sec:SetOpen(false)
	assertEq(sec.Open, false, "Section:SetOpen(false)")
	sec:SetOpen(true)
	assertEq(sec.Open, true, "Section:SetOpen(true)")
end
stepClock(0.1, true)

-- 3. CommandPalette, Dialog, Notify, Theme, Watermark, KeybindList, Blur
log("--- Exercising Systems (CommandPalette, Dialog, Notify, Theme, HUD) ---")
Bali.CommandPalette.Open()
stepClock(0.05, true)
assertEq(Bali.CommandPalette.IsOpen(), true, "CommandPalette:Open()")
do
	local paletteRoot = screenGui:FindFirstChild("BaliCommandPaletteBackdrop", true)
	assertTrue(paletteRoot ~= nil, "CommandPalette backdrop mounted")
	assertEq(paletteRoot and paletteRoot:FindFirstChild("ActiveBar", true), nil, "CommandPalette rows do not create vertical ActiveBar")
end
-- Search via searchBox if present
local paletteBackdrop = screenGui:FindFirstChild("BaliPopupLayer"):FindFirstChild("CommandPaletteBackdrop")
if paletteBackdrop then
	local modal = paletteBackdrop:FindFirstChild("CommandPaletteModal")
	local searchBox = modal and modal:FindFirstChild("SearchBar", true)
	if searchBox and searchBox:IsA("TextBox") then
		searchBox.Text = "Polling"
		stepClock(0.05, true)
	end
end
Bali.CommandPalette.Close()
stepClock(0.05, true)
assertEq(Bali.CommandPalette.IsOpen(), false, "CommandPalette:Close()")

local dlg = window:Dialog({
	Title = "Verification Dialog",
	Content = "Testing modal mount and button action.",
	Buttons = {
		{ Title = "Close", Variant = "Primary" },
	},
})
stepClock(0.05, true)
assertTrue(dlg ~= nil, "Dialog created")
if dlg and dlg.Close then
	dlg:Close()
end
stepClock(0.05, true)

local actionClicked = false
local toast = Bali:Notify({
	Title = "Action Toast",
	Content = "Verify action callback and update.",
	Type = "Accent",
	Duration = 4,
	Actions = {
		{
			Title = "Run Action",
			Primary = true,
			Callback = function()
				actionClicked = true
			end,
		},
	},
})
assertTrue(toast ~= nil, "Notification created")
do
	local nLayer = screenGui:FindFirstChild("BaliNotificationLayer")
	local nStack = nLayer and nLayer:FindFirstChild("BaliNotificationStack")
	local firstCard = nStack and nStack:FindFirstChild("Card", true)
	assertTrue(firstCard ~= nil and firstCard:FindFirstChild("GlassSheen") ~= nil, "Notification Card has obsidian GlassSheen layer")
	assertTrue(firstCard ~= nil and firstCard:FindFirstChild("SurfaceGradient") ~= nil, "Notification Card has vertical SurfaceGradient layer")
	local firstIcon = firstCard and firstCard:FindFirstChild("IconBadge", true)
	assertTrue(firstIcon ~= nil and firstIcon.Size.X.Offset == 40, "Notification IconBadge uses 40x40 glass well")
	local firstTitle = firstCard and firstCard:FindFirstChild("Title", true)
	local firstDesc = firstCard and firstCard:FindFirstChild("Description", true)
	assertTrue(firstTitle ~= nil and firstTitle.TextSize == 15, "Notification Title uses TextSize=15")
	assertTrue(firstDesc ~= nil and firstDesc.TextSize == 13, "Notification Description uses TextSize=13")
	local firstTrack = firstCard and firstCard:FindFirstChild("ProgressTrack", true)
	assertTrue(firstTrack ~= nil and firstTrack.Size.Y.Offset == 2 and firstTrack.BackgroundTransparency > 0.6, "Notification ProgressTrack uses sleek 2px translucent rail")
	local toast2 = Bali:Notify({
		Title = "Second Toast",
		Content = "Spacing check",
		Type = "Info",
		Duration = 4,
	})
	local toasts = {}
	if nStack then
		for _, ch in ipairs(nStack:GetChildren()) do
			if ch:IsA("GuiObject") and string.sub(ch.Name, 1, 6) == "Toast_" and ch.Visible then
				table.insert(toasts, ch)
			end
		end
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
	end
	assertTrue(#toasts >= 2, "Two stacked toasts visible for gap assertion")
	if #toasts >= 2 then
		local tA, tB = toasts[1], toasts[2]
		local cA, cB = tA:FindFirstChild("Card", true), tB:FindFirstChild("Card", true)
		assertTrue(cA ~= nil and math.abs(tA.AbsoluteSize.Y - cA.AbsoluteSize.Y) <= 1, "Toast wrapper height matches Card height without Shadow inflation")
		assertTrue(cB ~= nil and math.abs(tB.AbsoluteSize.Y - cB.AbsoluteSize.Y) <= 1, "Second toast wrapper height matches Card height without Shadow inflation")
		local gapPx = math.abs(cB.AbsolutePosition.Y - (cA.AbsolutePosition.Y + cA.AbsoluteSize.Y))
		assertTrue(math.abs(gapPx - 8) <= 1, "Stacked notification gap is 8px (got " .. tostring(gapPx) .. ")")
	end
	if toast2 and toast2.Dismiss then
		toast2:Dismiss(true)
	end
end
if toast and toast.Update then
	toast:Update({ Title = "Action Toast Updated", Content = "Updated body" })
end
-- Trigger notification action button
local notifLayer = screenGui:FindFirstChild("BaliNotificationLayer")
if notifLayer then
	for _, desc in ipairs(notifLayer:GetDescendants()) do
		if desc:IsA("TextButton") and desc.Text == "Run Action" then
			desc.Activated:Fire()
			break
		end
	end
end
stepClock(0.05, true)
assertTrue(actionClicked, "Notification action button callback fired")
if toast and toast.Dismiss then
	toast:Dismiss()
end

-- Themes & Fonts
assertTrue(Bali.Theme.Set("Ocean", true), "Theme.Set('Ocean')")
stepClock(0.05, true)
assertTrue(Bali.Theme.Set("Light", true), "Theme.Set('Light')")
stepClock(0.05, true)
assertTrue(Bali.Theme.Set("Midnight", true), "Theme.Set('Midnight')")
stepClock(0.05, true)
Bali.Theme.SetAccent(Color3.fromRGB(59, 130, 246), true)
assertTrue(Bali.Theme.SetFont("Ubuntu"), "Theme.SetFont('Ubuntu')")
assertTrue(Bali.Theme.SetFont("Builder"), "Theme.SetFont('Builder')")

Bali.Watermark.SetVisible(true)
Bali.Watermark.SetTitle("Bali Verify")
Bali.Watermark.SetText("Running Tests")
Bali.Watermark.SetStats({ FPS = true, Ping = true, Time = true, Players = true })
stepClock(0.2, true)
assertEq(Bali.Watermark.IsVisible(), true, "Watermark visible")
local wmFrame = screenGui:FindFirstChild("BaliHUDLayer") and screenGui:FindFirstChild("BaliHUDLayer"):FindFirstChild("BaliWatermark")
assertTrue(wmFrame ~= nil and wmFrame.Position.Y.Offset >= 60, "Watermark clears Roblox TopBar (>= 60px Y)")

Bali.KeybindList.SetVisible(true)
Bali.KeybindList.SetMode("All")
assertEq(Bali.KeybindList.IsVisible(), true, "KeybindList visible")

Bali.Blur.SetEnabled(true)
Bali.Blur.SetIntensity(16)
assertEq(Bali.Blur.IsEnabled(), true, "Blur enabled")
assertEq(Bali.Blur.GetIntensity(), 16, "Blur intensity=16")

-- 4. Config Save / Mutate / Load / Assert / Export / Import / Delete
log("--- Exercising Config System ---")
assertTrue(Bali.Config.Save("test_profile"), "Config.Save('test_profile')")

flags["Controls_PollingHz"]:Set(45)
flags["Controls_SmartAutomation"]:Set(false)
flags["Pickers_Strategy"]:Set("Eco Saver")
flags["Pickers_Alias"]:Set("Mutated")
assertEq(flags["Controls_PollingHz"]:Get(), 45, "Mutated PollingHz to 45")

assertTrue(Bali.Config.Load("test_profile"), "Config.Load('test_profile')")
assertEq(flags["Controls_PollingHz"]:Get(), 180, "Restored PollingHz=180")
assertEq(flags["Controls_SmartAutomation"]:Get(), true, "Restored SmartAutomation=true")
assertEq(flags["Pickers_Strategy"]:Get(), "High Throughput", "Restored Strategy='High Throughput'")
assertEq(flags["Pickers_Alias"]:Get(), "Staging-Beta", "Restored Alias='Staging-Beta'")

local exportedJson = Bali.Config.Export()
assertTrue(type(exportedJson) == "string" and #exportedJson > 20, "Config.Export() returned JSON")
flags["Controls_PollingHz"]:Set(60)
assertTrue(Bali.Config.Import(exportedJson), "Config.Import(json) succeeded")
assertEq(flags["Controls_PollingHz"]:Get(), 180, "Config.Import restored PollingHz=180")
assertTrue(Bali.Config.Delete("test_profile"), "Config.Delete('test_profile') succeeded")

-- 5. Simulated InputBegan key presses
log("--- Exercising Simulated InputBegan Key Presses ---")
local visBefore = window:IsVisible()
fireKeyPress(services1, Enum.KeyCode.RightShift, false)
assertEq(window:IsVisible(), not visBefore, "RightShift toggled window visibility")
fireKeyPress(services1, Enum.KeyCode.RightShift, false)
assertEq(window:IsVisible(), visBefore, "RightShift restored window visibility")

-- Capture Trigger: verify Hold mode (active on InputBegan, inactive on InputEnded) then Toggle mode
local hHoldInp = makeInputObj(Enum.UserInputType.Keyboard, Enum.KeyCode.H)
services1.UserInputService.InputBegan:Fire(hHoldInp, false)
stepClock(0.02, true)
assertEq(flags["Pickers_CaptureKey"]:GetState(), true, "Keybind H (Hold) active while held")
services1.UserInputService.InputEnded:Fire(hHoldInp, false)
stepClock(0.02, true)
assertEq(flags["Pickers_CaptureKey"]:GetState(), false, "Keybind H (Hold) inactive after release")

flags["Pickers_CaptureKey"]:Set(Enum.KeyCode.H, "Toggle")
local hBefore = flags["Pickers_CaptureKey"]:GetState()
fireKeyPress(services1, Enum.KeyCode.H, false)
assertEq(flags["Pickers_CaptureKey"]:GetState(), not hBefore, "Keybind H toggled Capture Trigger state")

-- Ctrl+K -> Command Palette + Escape close
fireKeyPress(services1, Enum.KeyCode.K, true)
assertEq(Bali.CommandPalette.IsOpen(), true, "Ctrl+K opened CommandPalette")
fireKeyPress(services1, Enum.KeyCode.Escape, false)
assertEq(Bali.CommandPalette.IsOpen(), false, "Escape closed CommandPalette")

-- 6. Layout Sanity Check across entire ScreenGui tree
log("--- Running Layout Sanity Checks ---")
local autoScaleBad = {}
local negativeHeights = {}
local overlapIssues = {}

local function inspectTree(root)
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("GuiObject") and desc.Visible then
			if desc.AutomaticSize == Enum.AutomaticSize.Y or desc.AutomaticSize == Enum.AutomaticSize.XY then
				if desc.Size.Y.Scale ~= 0 then
					table.insert(autoScaleBad, string.format("%s (%s) has Size.Y.Scale=%g with AutomaticSize=%s", desc.GetFullName and desc:GetFullName() or desc.Name, desc._className, desc.Size.Y.Scale, desc.AutomaticSize.Name))
				end
			end
			local absSize = desc.AbsoluteSize
			if absSize.Y < 0 then
				table.insert(negativeHeights, string.format("%s has negative height %g", desc.Name, absSize.Y))
			end
			local list = desc:FindFirstChildOfClass("UIListLayout")
			if list and list.FillDirection == Enum.FillDirection.Vertical then
				local ordered = {}
				for _, ch in ipairs(desc:GetChildren()) do
					if ch:IsA("GuiObject") and ch.Visible then
						table.insert(ordered, ch)
					end
				end
				table.sort(ordered, function(a, b)
					if a.LayoutOrder ~= b.LayoutOrder then
						return a.LayoutOrder < b.LayoutOrder
					end
					return a._id < b._id
				end)
				for i = 1, #ordered - 1 do
					local cur = ordered[i]
					local nxt = ordered[i + 1]
					local curPos, curSize = cur.AbsolutePosition, cur.AbsoluteSize
					local nxtPos = nxt.AbsolutePosition
					if curPos.Y + curSize.Y > nxtPos.Y + 0.5 then
						table.insert(overlapIssues, string.format("In %s: %s (bottom=%.1f) overlaps %s (top=%.1f)", desc.Name, cur.Name, curPos.Y + curSize.Y, nxt.Name, nxtPos.Y))
					end
				end
			end
		end
	end
end

-- Check layout on each tab selected so pages are visible
for _, tab in ipairs(window.Tabs) do
	tab:Select()
	stepClock(0.05, true)
	inspectTree(screenGui)
end

assertEq(#autoScaleBad, 0, "Zero AutomaticSize.Y objects with Size.Y.Scale ~= 0" .. (#autoScaleBad > 0 and (" -> " .. autoScaleBad[1]) or ""))
assertEq(#negativeHeights, 0, "Zero negative computed heights" .. (#negativeHeights > 0 and (" -> " .. negativeHeights[1]) or ""))
assertEq(#overlapIssues, 0, "Zero vertical UIListLayout sibling overlaps" .. (#overlapIssues > 0 and (" -> " .. overlapIssues[1]) or ""))

-- Regression checks for Bali visual & layout fixes
local uiScaleCount = 0
for _, desc in ipairs(screenGui:GetDescendants()) do
	if desc:IsA("UIScale") then
		uiScaleCount += 1
	end
end
assertEq(uiScaleCount, 0, "Zero UIScale instances anywhere in UI tree")

regFlags["Pickers_Swatch"]:Open()
stepClock(0.15, true)
local popupLayer = screenGui:FindFirstChild("BaliPopupLayer")
local presetsFrame = popupLayer and popupLayer:FindFirstChild("Presets", true)
assertTrue(presetsFrame ~= nil and presetsFrame.Visible, "ColorPicker Presets frame opened in BaliPopupLayer")
if presetsFrame then
	local opaquePresets = 0
	for _, desc in ipairs(presetsFrame:GetDescendants()) do
		if desc:IsA("TextButton") and desc.BackgroundTransparency == 0 then
			opaquePresets += 1
		end
	end
	assertTrue(opaquePresets >= 6, "All 6 ColorPicker preset swatches have BackgroundTransparency == 0 (got " .. tostring(opaquePresets) .. ")")
end
regFlags["Pickers_Swatch"]:Close()
stepClock(0.15, true)

regFlags["Pickers_Clusters"]:Open()
stepClock(0.15, true)
local clustersPopup = window._activePopup and window._activePopup.Frame
local optionsScroll = clustersPopup and clustersPopup:FindFirstChild("OptionsScroll", true)
local scrollListLayout = optionsScroll and optionsScroll:FindFirstChildOfClass("UIListLayout")
assertTrue(
	optionsScroll ~= nil and scrollListLayout ~= nil and optionsScroll.Size.Y.Offset >= scrollListLayout.AbsoluteContentSize.Y + 6,
	"Edge Clusters Dropdown fits full content without clipping (size=" .. tostring(optionsScroll and optionsScroll.Size.Y.Offset) .. ", content=" .. tostring(scrollListLayout and scrollListLayout.AbsoluteContentSize.Y) .. ")"
)
local actionBar = clustersPopup and clustersPopup:FindFirstChild("ActionBar", true)
local selectAllBtn = actionBar and actionBar:FindFirstChild("SelectAll")
local clearActionBtn = actionBar and actionBar:FindFirstChild("Clear")
assertTrue(actionBar ~= nil and actionBar.Visible, "Multi-select Dropdown renders visible ActionBar")
assertTrue(selectAllBtn ~= nil and selectAllBtn.Visible and clearActionBtn ~= nil and clearActionBtn.Visible, "ActionBar displays SelectAll and Clear buttons")
if selectAllBtn and selectAllBtn.Activated then
	selectAllBtn.Activated:Fire()
	stepClock(0.05, true)
	assertEq(#regFlags["Pickers_Clusters"]:Get(), 6, "Dropdown SelectAll button selects all 6 Edge Clusters")
end
if clearActionBtn and clearActionBtn.Activated then
	clearActionBtn.Activated:Fire()
	stepClock(0.05, true)
	assertEq(#regFlags["Pickers_Clusters"]:Get(), 0, "Dropdown Clear button clears all Edge Clusters")
end
regFlags["Pickers_Clusters"]:SelectAll(true)
assertEq(#regFlags["Pickers_Clusters"]:Get(), 6, "Dropdown:SelectAll(silent) selects all 6 items programmatically")
regFlags["Pickers_Clusters"]:Clear(true)
assertEq(#regFlags["Pickers_Clusters"]:Get(), 0, "Dropdown:Clear(silent) clears selection programmatically")
regFlags["Pickers_Clusters"]:Set({ "US-East (Virginia)", "EU-Central (Frankfurt)" }, true)
regFlags["Pickers_Clusters"]:Close()
stepClock(0.15, true)

-- 6b. Stealth, On-Device Fonts & Key Security verification
log("--- Testing Stealth, On-Device Fonts & Key Security ---")
do
	assertEq(Bali.Assets.Available, true, "Assets pipeline succeeds locally in executor mode without PreloadAsync")
	assertTrue(services1.Lighting:FindFirstChild("BaliBlur") == nil, "Lighting never exposes static BaliBlur instance name")
	assertTrue(mockGenv._BaliBlurEffect == nil or mockGenv._BaliBlurEffect.Name ~= "BaliBlur", "BlurEffect uses randomized Name in Lighting")
	assertTrue(screenGui.Name ~= "BaliUI" and #screenGui.Name == 10, "Stealth ScreenGui uses randomized Name instead of static BaliUI")
	local sh = Bali.Assets.Shadow()
	assertTrue(sh ~= nil and not string.find(tostring(sh.Image), "rbxassetid://"), "Assets.Shadow never references foreign rbxassetid://")
	local blockedIcon = Bali.Icons.Resolve(123456)
	assertEq(blockedIcon and blockedIcon.Kind, "Glyph", "Icons.Resolve blocks numeric rbxassetid under StealthMode")
	local blockedStrIcon = Bali.Icons.Resolve("rbxassetid://6014261993")
	assertEq(blockedStrIcon and blockedStrIcon.Kind, "Glyph", "Icons.Resolve blocks explicit rbxassetid:// string under StealthMode")

	local fakeTtf = "\000\001\000\000" .. string.rep("F", 96)
	local customFontUri = Bali.Assets.MaterializeFontFamily("Gotham", {
		Regular = fakeTtf,
		Bold = fakeTtf,
	})
	assertTrue(type(customFontUri) == "string" and string.find(customFontUri, "^rbxasset://custom/Bali/Fonts/Gotham_v") ~= nil, "Assets.MaterializeFontFamily writes .ttf + .json and returns local getcustomasset URI")
	assertEq(Bali.Theme.GetFontAsset("Gotham"), customFontUri, "Theme.GetFontAsset resolves materialized on-device font when OnDeviceFonts=true")
	Bali:SetFont("Gotham")
	assertEq(Bali.Theme.Font("Bold").Family, customFontUri, "Theme.Font binds on-device custom font family URI")
	Bali:SetOnDeviceFonts(false)
	assertEq(Bali.Theme.GetFontAsset("Gotham"), "rbxasset://fonts/families/GothamSSm.json", "Theme.SetOnDeviceFonts(false) falls back cleanly to local rbxasset:// built-in font")
	Bali:SetOnDeviceFonts(true)
	Bali:SetFont("Builder")

	assertEq(Bali.Util.ConstantTimeEquals("KEY-1234", "KEY-1234"), true, "ConstantTimeEquals matches equal strings")
	assertEq(Bali.Util.ConstantTimeEquals("KEY-1234", "KEY-1235"), false, "ConstantTimeEquals rejects mismatched suffix")
	assertEq(Bali.Util.ConstantTimeEquals("KEY-123", "KEY-1234"), false, "ConstantTimeEquals rejects mismatched lengths")
	local h1 = Bali.Util.HashKey("SECRET-KEY", "SaltA")
	local h2 = Bali.Util.HashKey("SECRET-KEY", "SaltA")
	local h3 = Bali.Util.HashKey("SECRET-KEY", "SaltB")
	assertTrue(#h1 == 64 and h1 == h2 and h1 ~= h3, "Util.HashKey produces deterministic salted 64-hex digest")
	assertEq(Bali.Util.SanitizeKeyInput(" \n\t\rBALI-SAFE  ", 32), "BALI-SAFE", "Util.SanitizeKeyInput strips control chars and trims whitespace")
	local okInt = Bali.Util.VerifyIntegrity()
	assertEq(okInt, true, "Util.VerifyIntegrity passes on untampered primitives")

	vfsFiles["Bali/hash_verify_test.txt"] = "  BALI-HASH-99\n"
	local ksHashCtrl = Bali:KeySystem({
		Title = "HashAuth",
		KeyHashes = { Bali.Util.HashKey("BALI-HASH-99", "BaliTestSalt") },
		KeySalt = "BaliTestSalt",
		SaveKey = true,
		FileName = "hash_verify_test.txt",
		Yield = false,
	})
	assertTrue(ksHashCtrl ~= nil and ksHashCtrl.Verified == true and ksHashCtrl.Key == "BALI-HASH-99", "KeySystem verifies saved key via KeyHashes + KeySalt and ConstantTimeEquals")
	vfsFiles["Bali/hash_verify_test.txt"] = nil
end

-- 7. Re-execution safety: run dist/BaliExample.lua a SECOND time without destroying the first
log("--- Testing Re-execution Safety ---")
local firstBali = Bali
local firstScreenGui = screenGui
local okRe, reErr = xpcall(function()
	runBundleFile("dist/BaliExample.lua", env1, "@dist/BaliExample_rerun.lua")
end, debug.traceback)
assertTrue(okRe, "dist/BaliExample.lua re-executed cleanly without error: " .. tostring(reErr))
stepClock(0.15, true)
local BaliRerun = mockGenv._BaliInstance
assertTrue(type(BaliRerun) == "table" and BaliRerun ~= firstBali, "Re-execution replaced _BaliInstance")
assertTrue(firstScreenGui._destroyed or firstScreenGui.Parent == nil, "Previous ScreenGui destroyed on re-execution")
assertEq(#BaliRerun._windows, 1, "Re-executed instance has 1 active window")

local rerunScreenGui = BaliRerun._screenGui
BaliRerun:Destroy()
stepClock(0.1, true)
assertEq(#BaliRerun._windows, 0, "Zero active windows after Bali:Destroy()")
assertTrue(rerunScreenGui._destroyed or rerunScreenGui.Parent == nil, "ScreenGui destroyed after Bali:Destroy()")

-- ══════════════════════════════════════════════════════════════════════════════
-- PASS 2: ROBLOX STUDIO MODE (no executor globals)
-- ══════════════════════════════════════════════════════════════════════════════

log("=== PASS 2: ROBLOX STUDIO MODE (dist/Bali.lua) ===")
local env2, game2, services2, playerGui2, coreGui2 = installEnvironment("studio")

local okLib, Bali2 = xpcall(function()
	return runBundleFile("dist/Bali.lua", env2, "@dist/Bali.lua")
end, debug.traceback)
assertTrue(okLib and type(Bali2) == "table", "dist/Bali.lua loaded in Studio mode: " .. tostring(Bali2))

if okLib and type(Bali2) == "table" then
	assertEq(Bali2.Theme.Name, "Graphite", "Default Theme.Name is Graphite in Studio mode")
	local win2 = Bali2:CreateWindow({
		Title = "Studio Fallback Test",
		Subtitle = "No Executor Globals",
		ToggleKey = Enum.KeyCode.RightShift,
		ConfigFolder = "StudioTest",
	})
	assertTrue(win2 ~= nil, "Studio Window created")
	assertEq(Bali2._screenGui.Parent, playerGui2, "Studio ScreenGui fell back cleanly to PlayerGui")

	local tab = win2:AddTab({ Title = "All Elements", Icon = "layers" })
	local sub = tab:AddSubTab({ Title = "Core", Icon = "sliders" })
	do
		stepClock(0.05, true)
		local activePill = tab._subTabIndicator
		assertTrue(activePill ~= nil and activePill.Visible, "SubTabBar ActivePill is visible for first SubTab")
		assertTrue(activePill.Position.X.Offset >= 2, "SubTabBar ActivePill Position.X.Offset >= 2 prevents left stroke clipping (got " .. tostring(activePill.Position.X.Offset) .. ")")
		local pillStroke = activePill:FindFirstChildOfClass("UIStroke")
		assertTrue(pillStroke ~= nil and pillStroke:FindFirstChildOfClass("UIGradient") ~= nil, "SubTabBar ActivePill uses glass UIStroke with UIGradient")
	end
	local sec = sub:AddSection({ Title = "Controls", Side = "Full", Collapsible = true })

	sec:AddHeader({ Title = "Header" })
	sec:AddLabel({ Title = "Label", Value = "123", Badge = "OK" })
	sec:AddParagraph({ Title = "Paragraph", Content = "Body text", Tags = { "A", "B" } })
	sec:AddDivider({ Title = "Divider" })
	sec:AddCodeBlock({ Title = "Code", Code = "print('hi')" })
	sec:AddImage({ Title = "Img", Image = "rbxassetid://0", Height = 64 })
	sec:AddProfileCard({ Title = "User", Subtitle = "Sub" })
	sec:AddButton({ Title = "Btn", Callback = function() end })
	sec:AddButtonGroup({ Buttons = { { Title = "B1" }, { Title = "B2" } } })
	sec:AddToggle({ Title = "Tgl", Default = true, Flag = "S_Tgl" })
	sec:AddCheckbox({ Title = "Chk", Default = false, Flag = "S_Chk" })
	sec:AddSlider({ Title = "Sld", Min = 0, Max = 10, Default = 5, Flag = "S_Sld" })
	sec:AddRangeSlider({ Title = "Rng", Min = 0, Max = 10, Default = { Min = 2, Max = 7 }, Flag = "S_Rng" })
	sec:AddStepper({ Title = "Stp", Min = 1, Max = 5, Default = 2, Flag = "S_Stp" })
	sec:AddInput({ Title = "Inp", Default = "abc", Flag = "S_Inp" })
	sec:AddSegmented({ Title = "Seg", Values = { "X", "Y" }, Default = "X", Flag = "S_Seg" })
	sec:AddDropdown({ Title = "Drp", Values = { "One", "Two" }, Default = "One", Flag = "S_Drp" })
	sec:AddKeybind({ Title = "Key", Default = Enum.KeyCode.J, Flag = "S_Key" })
	sec:AddColorPicker({ Title = "Col", Default = Color3.fromRGB(255, 0, 0), Flag = "S_Col" })
	sec:AddStatCard({ Title = "Stat", Value = 42, Points = { 1, 2, 3 } })
	sec:AddChart({ Title = "Chart", Mode = "Line", Points = { 1, 2, 3 } })
	sec:AddProgressBar({ Title = "Prog", Value = 50, Max = 100 })
	local tbl2 = sec:AddTable({
		Title = "Tbl",
		Columns = { { Key = "A", Title = "A", Width = 0.5 }, { Key = "B", Title = "B", Width = 0.5 } },
		Rows = { { A = "1", B = "2" } },
	})
	local foundColScale = false
	for _, desc in ipairs(tbl2.Frame:GetDescendants()) do
		if desc:IsA("TextLabel") and desc.Text == "A" and desc.Size.X.Scale > 0.4 then
			foundColScale = true
		end
	end
	assertTrue(foundColScale, "Analytics Table fractional column Width uses Scale > 0.4")
	sec:AddCardGrid({
		Cards = { { Id = "c1", Title = "Card 1" } },
		Default = "c1",
	})
	local acc = sec:AddAccordion({ Title = "Acc", Expanded = true })
	acc:AddToggle({ Title = "Nested Toggle", Default = false })

	win2:BuildSettingsTab({ Category = "System" })

	win2:Notify({ Title = "Studio Toast", Content = "Working without executor globals", Type = "Info" })
	local d2 = win2:Dialog({ Title = "Studio Dialog", Content = "Confirm", Buttons = { { Title = "OK" } } })
	stepClock(0.05, true)
	if d2 and d2.Close then
		d2:Close()
	end

	-- Config fallback in Studio mode (in-memory)
	assertTrue(Bali2.Config.Save("studio_mem"), "Studio Config.Save in-memory fallback works")
	win2.Flags["S_Sld"]:Set(9)
	assertTrue(Bali2.Config.Load("studio_mem"), "Studio Config.Load in-memory fallback works")
	assertEq(win2.Flags["S_Sld"]:Get(), 5, "Studio Config restored S_Sld=5")

	-- V4 Features: AddBanner, Mobile Compact Mode, AutoSave (Named + Unnamed)
	local v4Tab = win2:AddTab({ Title = "VerifyV4", Icon = "sparkles" })
	local v4Sec = v4Tab:AddSection({ Title = "V4 Controls", Side = "Left" })
	local banner = v4Sec:AddBanner({
		Title = "Bali Obsidian Architecture",
		Caption = "4K Glassmorphic Backdrop & Vector Icon Atlas",
		Badge = "v4.0 HD",
		Icon = "sparkles",
		Overlay = true,
		Image = Bali2.Assets.Get("Banner") or "rbxassetid://0",
		Height = 148,
	})
	assertTrue(banner ~= nil, "AddBanner returns element handle")
	local unnamedTog = v4Sec:AddToggle({ Title = "Unnamed AutoSave Toggle", Default = false })
	local kbTog = v4Sec:AddToggle({ Title = "Keybind AutoSave", Default = false, Keybind = Enum.KeyCode.F })
	local v4Grid = v4Sec:AddCardGrid({
		Cards = {
			{ Id = "g_a", Title = "Alpha" },
			{ Id = "g_b", Title = "Beta" },
		},
		Default = "g_a",
	})
	local lateSeedTog = v4Sec:AddToggle({ Title = "Late Seed", Flag = "LateRestoreFlag", Default = false })

	assertTrue(Bali2.Theme.Resolve("Elevated") ~= nil, "Theme.Resolve('Elevated') returns Color3")

	local origMobile = win2:IsMobileMode()
	win2:SetMobileMode(true)
	assertTrue(win2:IsMobileMode(), "SetMobileMode(true) enables mobile mode")
	win2:SetMobileMode(false)
	assertTrue(not win2:IsMobileMode(), "SetMobileMode(false) disables mobile mode")
	win2:SetMobileMode(origMobile)

	Bali2:SetAutoSave(true)
	assertTrue(Bali2:GetAutoSave(), "GetAutoSave() reflects SetAutoSave(true)")
	unnamedTog:Set(true)
	kbTog:Set(true)
	kbTog:SetKeybind(Enum.KeyCode.G)
	v4Grid:Set("g_b")
	lateSeedTog:Set(true)
	win2.Flags["S_Sld"]:Set(7)

	assertTrue(Bali2.Config.Save("studio_kb_test"), "Config.Save('studio_kb_test') saves named + unnamed ToggleState")
	local exportedAll = Bali2.Config.Export(true)
	assertTrue(type(exportedAll) == "string" and #exportedAll > 20, "Config.Export(true) returns JSON string")

	local savedOk = Bali2.Config.SaveAutoSaveNow()
	assertTrue(savedOk, "Config.SaveAutoSaveNow() succeeds")
	unnamedTog:Set(false)
	kbTog:Set(false)
	kbTog:SetKeybind(Enum.KeyCode.H)
	v4Grid:Set("g_a")
	win2.Flags["S_Sld"]:Set(3)

	assertTrue(Bali2.Config.Load("studio_kb_test"), "Config.Load('studio_kb_test') succeeds")
	assertEq(kbTog:Get(), true, "Config.Load restored inline-keybind Toggle value")
	assertEq(kbTog:GetKeybind(), Enum.KeyCode.G, "Config.Load restored inline-keybind EnumKey")
	assertEq(v4Grid:Get(), "g_b", "Config.Load restored CardGrid active id")

	kbTog:Set(false)
	kbTog:SetKeybind(Enum.KeyCode.J)
	v4Grid:Set("g_a")
	assertTrue(Bali2.Config.Import(exportedAll), "Config.Import(exportedAll) restores ToggleState + CardGrid")
	assertEq(kbTog:Get(), true, "Config.Import restored inline-keybind Toggle value")
	assertEq(kbTog:GetKeybind(), Enum.KeyCode.G, "Config.Import restored inline-keybind EnumKey")
	assertEq(v4Grid:Get(), "g_b", "Config.Import restored CardGrid active id")

	unnamedTog:Set(false)
	kbTog:Set(false)
	kbTog:SetKeybind(Enum.KeyCode.K)
	v4Grid:Set("g_a")
	win2.Flags["S_Sld"]:Set(3)
	assertTrue(Bali2.Config.LoadAutoSave(), "Config.LoadAutoSave() restores workspace")
	assertTrue(Bali2.Config.HasLoadedAutoSave(), "Config.HasLoadedAutoSave() is true after LoadAutoSave()")
	assertEq(unnamedTog:Get(), true, "AutoSave restored unnamed toggle")
	assertEq(kbTog:Get(), true, "AutoSave restored inline-keybind Toggle value")
	assertEq(kbTog:GetKeybind(), Enum.KeyCode.G, "AutoSave restored inline-keybind EnumKey")
	assertEq(v4Grid:Get(), "g_b", "AutoSave restored CardGrid active id")
	assertEq(win2.Flags["S_Sld"]:Get(), 7, "AutoSave restored named flag S_Sld=7")

	local lateTog = v4Sec:AddToggle({ Title = "Late Flag Toggle", Flag = "LateRestoreFlag", Default = false })
	assertEq(lateTog:Get(), true, "Container restored late-registered element via TryApplyCachedAutoSave")

	-- Polish & Regression Fix Verifications (Step 8)
	local origNotifDur = Bali2:GetNotificationDuration()
	Bali2:SetNotificationDuration(8)
	assertEq(Bali2:GetNotificationDuration(), 8, "SetNotificationDuration updates default duration")
	Bali2:SetNotificationDuration(0.1)
	assertEq(Bali2:GetNotificationDuration(), 1, "SetNotificationDuration clamps lower bound to 1")
	Bali2:SetNotificationDuration(99)
	assertEq(Bali2:GetNotificationDuration(), 30, "SetNotificationDuration clamps upper bound to 30")
	Bali2:SetNotificationDuration(origNotifDur)

	local synCode = v4Sec:AddCodeBlock({
		Title = "Luau Quickstart",
		Language = "luau",
		Code = "local ok = true\nprint(win:GetWidth())",
	})
	local codeListInst = synCode.Frame:FindFirstChild("CodeList", true)
	assertTrue(codeListInst ~= nil, "CodeBlock renders CodeList container")
	local line1Row = codeListInst and codeListInst:FindFirstChild("Line_1")
	local line2Row = codeListInst and codeListInst:FindFirstChild("Line_2")
	assertTrue(line1Row ~= nil and line2Row ~= nil, "CodeBlock renders per-line Line_1 / Line_2 rows")
	local l1Code = line1Row and line1Row:FindFirstChild("Code")
	local l1Num = line1Row and line1Row:FindFirstChild("Num")
	assertTrue(l1Code ~= nil and l1Code.RichText == true and l1Code.TextSize == 12, "CodeBlock Line_1 uses RichText and crisp TextSize=12")
	assertTrue(l1Num ~= nil and l1Num.TextSize == 12 and l1Num.Text == "1", "CodeBlock Line_1 Num uses TextSize=12")
	assertTrue(string.find(l1Code.Text, '<font color="#C084FC">local</font>', 1, true) ~= nil, "CodeBlock highlights Luau keyword local")
	assertTrue(string.find(l1Code.Text, '<font color="#F472B6">true</font>', 1, true) ~= nil, "CodeBlock highlights boolean true")
	local l2Code = line2Row and line2Row:FindFirstChild("Code")
	assertTrue(string.find(l2Code.Text, '<font color="#7DD3FC">print</font>', 1, true) ~= nil, "CodeBlock highlights builtin print")
	assertTrue(string.find(l2Code.Text, '<font color="#93C5FD">GetWidth</font>', 1, true) ~= nil, "CodeBlock highlights member GetWidth")

	local bannerEl = v4Sec:AddBanner({
		Title = "Banner Corner",
		Caption = "Clipped inside CanvasGroup",
		Overlay = true,
		Image = "sparkles",
	})
	local picClip = bannerEl.Frame:FindFirstChild("PictureClip", true)
	assertTrue(picClip ~= nil and picClip:IsA("CanvasGroup"), "Banner wraps Picture inside CanvasGroup PictureClip")
	assertTrue(bannerEl.Frame:FindFirstChild("BorderOverlay", true) == nil, "Banner removes duplicate BorderOverlay")

	local snapCard = v4Sec:AddProfileCard({
		Title = "Dev",
		Subtitle = "Snapshot test",
		Button = { Title = "Sync Snapshot" },
	})
	local snapBtn = snapCard.Frame:FindFirstChild("ActionButton", true)
	assertTrue(snapBtn ~= nil, "ProfileCard creates ActionButton")
	Bali2.Transition.Ripple(snapBtn, nil, "Accent")
	assertTrue(snapBtn:FindFirstChild("_BaliRippleWash") == nil, "Ripple does not inject _BaliRippleWash inside layout button")

	local ddGate = v4Sec:AddDropdown({ Title = "Gate Drop", Values = { "Alpha", "Beta" }, Default = "Alpha" })
	local blockedSlider = v4Sec:AddSlider({ Title = "Blocked Slider", Min = 0, Max = 100, Default = 50 })
	assertEq(Bali2.Transition.IsOverlayBlocking(blockedSlider.Frame), false, "Slider unblocked when no overlay open")
	ddGate:Open()
	stepClock(0.05, true)
	assertEq(Bali2.Transition.IsOverlayBlocking(blockedSlider.Frame), true, "Slider blocked when Dropdown popup is open")
	local openPopup = nil
	for _, ch in ipairs(win2.PopupLayer:GetChildren()) do
		if ch.Name ~= "PopupBackdrop" and ch.Name ~= "BaliCommandPaletteBackdrop" and ch.Visible then
			openPopup = ch
		end
	end
	assertTrue(openPopup ~= nil and openPopup.Active == true, "Dropdown popup has Active=true")
	assertTrue(openPopup ~= nil and openPopup:FindFirstChild("InputSink") ~= nil, "Dropdown popup has InputSink")
	local opt1 = openPopup and openPopup:FindFirstChild("Opt_1", true)
	assertTrue(opt1 ~= nil and opt1.Size.Y.Offset == 28, "Single-line Dropdown option row uses compact 28px height")
	assertEq(Bali2.Transition.IsOverlayBlocking(opt1), false, "Dropdown option inside PopupLayer is not blocked by itself")
	ddGate:Close()
	stepClock(0.3, true)
	assertEq(Bali2.Transition.IsOverlayBlocking(blockedSlider.Frame), false, "Slider unblocked after Dropdown closes")

	win2.MainWrapper.Position = MockUDim2.fromOffset(100, 80)
	stepClock(0.02, true)
	Bali2.CommandPalette.Open()
	stepClock(0.05, true)
	local cpBackdrop = win2.PopupLayer:FindFirstChild("BaliCommandPaletteBackdrop")
	local cpModal = cpBackdrop and cpBackdrop:FindFirstChild("Modal")
	assertTrue(cpModal ~= nil and cpModal:FindFirstChild("InputSink") ~= nil, "CommandPalette Modal has InputSink")
	local expectedCpX = math.floor(100 + win2.MainWrapper.AbsoluteSize.X * 0.5)
	assertTrue(math.abs(cpModal.Position.X.Offset - expectedCpX) <= 2, "CommandPalette centers horizontally over MainWrapper")
	Bali2.CommandPalette.Close()
	stepClock(0.3, true)

	v4Tab:Select()
	local v4Scroll = v4Tab.Page:FindFirstChildOfClass("ScrollingFrame") or v4Sec.Frame.Parent
	Bali2.Transition.Cascade(v4Scroll, 0.05, 8)
	Bali2.Transition.RestoreCascade(v4Scroll)
	local lateTitleLbl = nil
	for _, d in ipairs(lateTog.Frame:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text == "Late Flag Toggle" then
			lateTitleLbl = d
			break
		end
	end
	assertTrue(lateTitleLbl ~= nil and lateTitleLbl.TextTransparency < 0.5, "RestoreCascade immediately restores dimmed text transparency")

	local chartHeaderEl = v4Sec:AddChart({ Title = "Hover Test", Values = { 10, 20, 30 }, Labels = { "1h", "2h", "3h" } })
	local chartRight = chartHeaderEl.Frame:FindFirstChild("PlotArea", true)
	assertTrue(chartRight ~= nil, "Chart PlotArea created")
	local tagVisible = false
	for _, d in ipairs(chartHeaderEl.Frame:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text == "3h" and d.Visible then
			tagVisible = true
		end
	end
	assertTrue(tagVisible, "Chart hoverTagLabel remains visible with steady height at idle")

	-- Regression: mid-cascade minimize + tab switch while morphing/hidden must not corrupt resting transparencies
	local regDashTab = win2:AddTab({ Title = "RegDash", Icon = "home" })
	local regDashSec = regDashTab:AddSection({ Title = "Dash Section", Side = "Full" })
	local regDashBtn = regDashSec:AddButton({ Title = "Dash Action", Callback = function() end })
	local regCtrlTab = win2:AddTab({ Title = "RegCtrl", Icon = "sliders" })
	local regCtrlSec = regCtrlTab:AddSection({ Title = "Ctrl Section", Side = "Full" })
	local regCtrlTog = regCtrlSec:AddToggle({ Title = "Ctrl Toggle", Default = true })

	regCtrlTab:Select()
	stepClock(0.01, true)
	win2:SetVisible(false)
	stepClock(0.05, true)
	regDashTab:Select()
	stepClock(0.35, true)
	win2:SetVisible(true)
	stepClock(0.5, true)
	regCtrlTab:Select()
	stepClock(0.5, true)

	local function findTitleOpacity(frame, titleText)
		for _, d in ipairs(frame:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == titleText then
				return d.TextTransparency
			end
		end
		return nil
	end
	local ctrlLblT = findTitleOpacity(regCtrlTog.Frame, "Ctrl Toggle")
	local ctrlSecBgT = regCtrlSec.Frame.BackgroundTransparency
	assertTrue(ctrlLblT ~= nil and ctrlLblT < 0.5, "Ctrl Toggle text restored cleanly after mid-cascade minimize + tab switch (T=" .. tostring(ctrlLblT) .. ")")
	assertTrue(ctrlSecBgT < 0.5, "Ctrl Section card background restored cleanly (T=" .. tostring(ctrlSecBgT) .. ")")

	regDashTab:Select()
	stepClock(0.5, true)
	local dashLblT = findTitleOpacity(regDashBtn.Frame, "Dash Action")
	local dashSecBgT = regDashSec.Frame.BackgroundTransparency
	assertTrue(dashLblT ~= nil and dashLblT < 0.5, "Dash Action text restored cleanly after switching during minimize (T=" .. tostring(dashLblT) .. ")")
	assertTrue(dashSecBgT < 0.5, "Dash Section card background restored cleanly (T=" .. tostring(dashSecBgT) .. ")")

	-- Regression: Tooltip Side='Right' on collapsed sidebar & single sidebar toggle button
	do
		assertTrue(win2.ScreenGui:FindFirstChild("ExpandSidebarBtn", true) == nil, "Duplicate ExpandSidebarBtn is not rendered in topbar breadcrumb")
		win2:ToggleSidebar(true)
		stepClock(0.3, true)
		local collapseBtnInst = win2.Sidebar:FindFirstChild("CollapseButton", true)
		local brandLogoInst = win2.Sidebar:FindFirstChild("BrandLogoIcon", true)
		local brandExpandInst = win2.Sidebar:FindFirstChild("BrandExpandIcon", true)
		assertTrue(collapseBtnInst ~= nil and not collapseBtnInst.Visible, "CollapseButton is hidden when sidebar is collapsed")
		assertTrue(brandLogoInst ~= nil and not brandLogoInst.Visible, "BrandLogoIcon is hidden when sidebar is collapsed")
		assertTrue(brandExpandInst ~= nil and brandExpandInst.Visible, "Single BrandExpandIcon is shown when sidebar is collapsed")
		Bali2.Tooltip.Show("Controls", regCtrlTab._button, "Right")
		local ttCard = win2.PopupLayer:FindFirstChild("BaliTooltip")
		assertTrue(ttCard ~= nil and ttCard.Visible, "BaliTooltip displayed for collapsed sidebar tab")
		local expectedMinX = regCtrlTab._button.AbsolutePosition.X + regCtrlTab._button.AbsoluteSize.X
		assertTrue(
			ttCard.AbsolutePosition.X >= expectedMinX,
			string.format("Collapsed sidebar tooltip placed to right of icon (ttX=%g >= btnRight=%g)", ttCard.AbsolutePosition.X, expectedMinX)
		)
		local posBefore = ttCard.Position
		ttCard.Size = MockUDim2.fromOffset(ttCard.Size.X.Offset, 30)
		ttCard:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		assertEq(ttCard.Position.X.Offset, posBefore.X.Offset, "Tooltip X position stays stable on AbsoluteSize update")
		Bali2.Tooltip.Hide()
		stepClock(0.2, true)
		-- Regression: re-showing tooltip after Hide() (duration 0.12s < 0.14s floor) must keep TextTransparency == 0
		Bali2.Tooltip.Show("Dashboard", regDashTab._button, "Right")
		stepClock(0.2, true)
		local ttLabel = ttCard and ttCard:FindFirstChild("Text")
		assertTrue(ttLabel ~= nil and ttLabel.Text == "Dashboard", "Re-shown tooltip updates Text")
		assertTrue(ttLabel ~= nil and ttLabel.TextTransparency < 0.05, "Re-shown tooltip text remains fully visible (T=" .. tostring(ttLabel and ttLabel.TextTransparency) .. ")")
		Bali2.Tooltip.Hide()
		stepClock(0.2, true)
		win2:ToggleSidebar(false)
		stepClock(0.3, true)
		assertTrue(collapseBtnInst ~= nil and collapseBtnInst.Visible, "CollapseButton is visible when sidebar is expanded")
		assertTrue(brandLogoInst ~= nil and brandLogoInst.Visible, "BrandLogoIcon is visible when sidebar is expanded")
		assertTrue(brandExpandInst ~= nil and not brandExpandInst.Visible, "BrandExpandIcon is hidden when sidebar is expanded")
	end

	-- Regression: Dropdown Mode='Inline' vs 'Popup' + CodeBlock & Paragraph explicit scrolling
	do
		local inlineDd = v4Sec:AddDropdown({
			Title = "Inline Mode Menu",
			Mode = "Inline",
			Values = { "Alpha", "Beta", "Gamma", "Delta" },
			Default = "Alpha",
		})
		assertEq(inlineDd:GetMode(), "Inline", "Dropdown Mode='Inline' reports GetMode() == 'Inline'")
		inlineDd:Open()
		stepClock(0.3, true)
		local inlineClip = inlineDd.Frame:FindFirstChild("InlineClip", true)
		assertTrue(inlineClip ~= nil and inlineClip.Visible and inlineClip.Size.Y.Offset > 0, "Inline Dropdown expands InlineClip downward inside card")
		assertEq(Bali2.Transition.IsOverlayBlocking(blockedSlider.Frame), false, "Inline Dropdown does not block sibling elements as overlay")
		inlineDd:Close()
		stepClock(0.3, true)
		assertTrue(inlineClip ~= nil and not inlineClip.Visible and inlineClip.Size.Y.Offset == 0, "Inline Dropdown collapses InlineClip back to 0 height on Close")

		inlineDd:SetMode("Popup")
		assertEq(inlineDd:GetMode(), "Popup", "Dropdown SetMode('Popup') switches back to floating Popup mode")
		inlineDd:Open()
		stepClock(0.1, true)
		assertEq(Bali2.Transition.IsOverlayBlocking(blockedSlider.Frame), true, "Dropdown switched to Popup opens in PopupLayer overlay")
		inlineDd:Close()
		stepClock(0.3, true)

		local longCodeLines = {}
		for i = 1, 16 do
			table.insert(longCodeLines, string.format("local line%d = %d", i, i))
		end
		local scrollCode = v4Sec:AddCodeBlock({
			Title = "Long Scrollable Code",
			Language = "luau",
			Code = table.concat(longCodeLines, "\n"),
			MaxHeight = 120,
		})
		local codeScroll = scrollCode.Frame:FindFirstChild("CodeScroll", true)
		assertTrue(codeScroll ~= nil and codeScroll:IsA("ScrollingFrame"), "CodeBlock creates CodeScroll ScrollingFrame")
		assertTrue(codeScroll.Size.Y.Offset == 120, "CodeScroll clamps explicit visible height to MaxHeight=120 (got " .. tostring(codeScroll.Size.Y.Offset) .. ")")
		assertTrue(codeScroll.CanvasSize.Y.Offset > codeScroll.Size.Y.Offset, "CodeScroll sets explicit CanvasSize.Y.Offset > Size.Y.Offset for vertical scrolling (canvas=" .. tostring(codeScroll.CanvasSize.Y.Offset) .. ")")
		assertEq(codeScroll.AutomaticCanvasSize, Enum.AutomaticSize.None, "CodeScroll uses explicit CanvasSize rather than AutomaticCanvasSize")

		local scrollPara = v4Sec:AddParagraph({
			Title = "Long Scrollable Paragraph",
			Content = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8",
			MaxHeight = 64,
		})
		local paraScroll = scrollPara.Frame:FindFirstChild("ParagraphScroll", true)
		assertTrue(paraScroll ~= nil and paraScroll:IsA("ScrollingFrame"), "Paragraph with MaxHeight creates ParagraphScroll ScrollingFrame")
		assertTrue(paraScroll.Size.Y.Offset <= 64 and paraScroll.CanvasSize.Y.Offset > paraScroll.Size.Y.Offset, "ParagraphScroll configures scrollable bounds when text exceeds MaxHeight")
	end

	-- Regression: UI/UX & Customization Enhancements (Typography, ButtonGroup fit, Badge contrast, Tint, Original Icons, Table checkboxes, Dropdown RightIcon + scroll-track, DestroyOnClose)
	;(function()
		assertEq(Bali2.Theme.FontFamily, "Montserrat", "Default Theme.FontFamily is Montserrat")
		assertEq(Bali2.Theme.Font("Regular").Weight, Enum.FontWeight.Medium, "Theme.Font('Regular') maps to Medium (500) for crisp legibility")

		local grpFit = v4Sec:AddButtonGroup({
			Buttons = {
				{ Title = "Equip Best", Variant = "Primary", Icon = "sparkles" },
				{ Title = "Fuse Safe", Color = MockColor3.fromRGB(16, 185, 129), Icon = "shield" },
				{ Title = "Unequip All", Variant = "Danger", Icon = "flame" },
			},
		})
		stepClock(0.05, true)
		local b1 = grpFit:GetButton(1)
		local lbl1 = b1 and b1.Label
		local c1 = lbl1 and lbl1:FindFirstChild("LabelConstraint")
		assertTrue(c1 ~= nil and c1:IsA("UISizeConstraint"), "ButtonGroup creates LabelConstraint UISizeConstraint on labels")
		if b1 and b1.Frame and c1 then
			b1.Frame.Size = MockUDim2.fromOffset(96, 34)
			b1.Frame:GetPropertyChangedSignal("AbsoluteSize"):Fire()
			stepClock(0.02, true)
			assertTrue(c1.MaxSize.X > 0 and c1.MaxSize.X < 96, "ButtonGroup LabelConstraint clamps MaxSize.X cleanly inside button width (" .. tostring(c1.MaxSize.X) .. ")")
		end

		local badgeBtn = v4Sec:AddButton({
			Title = "Equipped Gear",
			Variant = "Primary",
			Badge = "9 Passives",
			Color = MockColor3.fromRGB(37, 99, 235),
		})
		local badgePill = badgeBtn.Frame:FindFirstChild("Badge", true)
		local badgeLbl = badgePill and badgePill:FindFirstChild("Label")
		assertTrue(badgePill ~= nil and badgeLbl ~= nil, "Primary Button renders Badge pill and Label")
		if badgePill and badgeLbl then
			assertTrue(badgePill.BackgroundColor3 ~= badgeBtn.Frame.BackgroundColor3, "Primary Button badge pill contrasts against Primary button surface")
			assertEq(badgeLbl.TextColor3, Bali2.Theme.Current.AccentText, "Primary Button badge text uses high-contrast AccentText")
		end

		local tintedSec = win2.Tabs[1]:AddSection({
			Title = "Tinted Original Section",
			Icon = "sparkles",
			IconColor = "Original",
			Color = "#10B981",
		})
		local secBadge = tintedSec.Frame:FindFirstChild("IconBadge", true)
		local secIcon = secBadge and secBadge:FindFirstChild("Icon", true)
		assertTrue(secIcon ~= nil and secIcon:GetAttribute("_BaliOriginalColor") == true, "Section IconColor='Original' marks icon with _BaliOriginalColor attribute")
		if secIcon and secIcon:IsA("ImageLabel") then
			assertEq(secIcon.ImageColor3, MockColor3.new(1, 1, 1), "Section IconColor='Original' keeps untinted ImageColor3 (1,1,1)")
		end

		local worldTbl = tintedSec:AddTable({
			Title = "Worlds Overview",
			Selectable = true,
			Columns = {
				{ Key = "World", Title = "World", Width = 0.5 },
				{ Key = "Cost", Title = "Cost", Width = 0.5 },
			},
			Rows = {
				{ World = "1. Super Island", Cost = "80 Yen" },
				{ World = "2. Plant Town", Cost = "300 Yen" },
			},
			Action = { Title = "Travel", Icon = "navigation", Variant = "Primary" },
		})
		stepClock(0.05, true)
		local tblRow1 = worldTbl.Frame:FindFirstChild("Row_1", true)
		assertTrue(tblRow1 ~= nil and tblRow1:FindFirstChild("Checkbox") == nil, "Table with Action button omits row Checkbox by default")
		worldTbl:SetCheckboxes(true)
		stepClock(0.05, true)
		local tblRow1After = worldTbl.Frame:FindFirstChild("Row_1", true)
		assertTrue(tblRow1After ~= nil and tblRow1After:FindFirstChild("Checkbox") ~= nil, "Table:SetCheckboxes(true) enables row Checkbox dynamically")

		local ddYen = tintedSec:AddDropdown({
			Title = "Island Travel",
			Values = {
				{ Title = "1. Super Island", Icon = "globe", RightText = "80 Yen" },
				{ Title = "2. Crystal Cave", Icon = "sparkles", RightText = "500 Gems" },
			},
			Default = "1. Super Island",
		})
		stepClock(0.05, true)
		local yenTrig = ddYen.Frame:FindFirstChild("Trigger", true)
		local yenTrigRightIcon = yenTrig and yenTrig:FindFirstChild("TriggerRightIcon", true)
		assertTrue(yenTrigRightIcon ~= nil and yenTrigRightIcon.Visible, "Dropdown closed Trigger shows inferred RightIcon for '80 Yen'")
		local yenTrigIconChild = yenTrigRightIcon and yenTrigRightIcon:FindFirstChild("Icon")
		assertTrue(yenTrigIconChild ~= nil and (yenTrigIconChild:IsA("ImageLabel") or yenTrigIconChild:IsA("TextLabel")), "Dropdown TriggerRightIcon renders currency icon")
		if yenTrigIconChild then
			local iconCol = yenTrigIconChild:IsA("TextLabel") and yenTrigIconChild.TextColor3 or yenTrigIconChild.ImageColor3
			assertEq(iconCol, MockColor3.fromRGB(251, 191, 36), "Dropdown TriggerRightIcon '80 Yen' uses gold coin tint")
		end

		win2:SelectTab(win2.Tabs[1], true)
		stepClock(0.05, true)
		ddYen:Open()
		stepClock(0.1, true)
		local yenPopup = nil
		for _, ch in ipairs(win2.PopupLayer:GetChildren()) do
			if ch.Name ~= "PopupBackdrop" and ch.Name ~= "BaliCommandPaletteBackdrop" and ch.Visible then
				yenPopup = ch
			end
		end
		local optYen1 = yenPopup and yenPopup:FindFirstChild("Opt_1", true)
		assertTrue(optYen1 ~= nil and optYen1:FindFirstChild("RightIcon", true) ~= nil, "Dropdown popup Opt_1 creates inferred RightIcon for '80 Yen'")
		if yenPopup and yenTrig then
			local popPosBefore = yenPopup.Position
			local origMainPos = win2.MainWrapper.Position
			win2.MainWrapper.Position = MockUDim2.fromOffset(origMainPos.X.Offset + 40, origMainPos.Y.Offset + 25)
			yenTrig:GetPropertyChangedSignal("AbsolutePosition"):Fire()
			stepClock(0.02, true)
			assertTrue(yenPopup.Position.X.Offset ~= popPosBefore.X.Offset, "Dropdown open popup tracks trigger AbsolutePosition changes")
			local ancScroller = yenTrig:FindFirstAncestorOfClass("ScrollingFrame")
			if ancScroller then
				local origCanvas = ancScroller.CanvasPosition
				ancScroller.CanvasPosition = MockVector2.new(0, 5000)
				ancScroller:GetPropertyChangedSignal("CanvasPosition"):Fire()
				stepClock(0.25, true)
				assertTrue(win2._activePopup == nil, "Dropdown auto-closes when trigger scrolls outside ancestor ScrollingFrame viewport")
				ancScroller.CanvasPosition = origCanvas
			else
				ddYen:Close()
				stepClock(0.2, true)
			end
			win2.MainWrapper.Position = origMainPos
		end
	end)()

	-- Re-execution test in Studio mode
	local sg2 = Bali2._screenGui
	win2:Destroy()
	stepClock(0.3, true)
	assertTrue(sg2._destroyed or sg2.Parent == nil, "Studio ScreenGui destroyed cleanly on win2:Destroy()")

	-- Regression: Window DestroyOnClose=true default unloads on Close button instead of minimizing
	;(function()
		local closeFired = false
		local winClose = Bali2:CreateWindow({
			Title = "CloseUnloadTest",
			ConfirmClose = false,
			OnClose = function()
				closeFired = true
			end,
		})
		local sgClose = Bali2._screenGui
		local actionsWrap = winClose.Main and winClose.Main:FindFirstChild("QuickActions", true)
		local closeBtnInst = nil
		if actionsWrap then
			for _, ch in ipairs(actionsWrap:GetChildren()) do
				if ch:IsA("TextButton") and ch.LayoutOrder == 6 then
					closeBtnInst = ch
				end
			end
		end
		assertTrue(closeBtnInst ~= nil, "Window QuickActions contains Close button")
		if closeBtnInst then
			closeBtnInst.Activated:Fire()
			stepClock(0.35, true)
		end
		assertTrue(closeFired, "Window Close button invokes OnClose when ConfirmClose=false")
		assertTrue(winClose._destroyed == true and (sgClose._destroyed or sgClose.Parent == nil), "Window defaults to DestroyOnClose=true and unloads on Close")
	end)()

	-- Regression: Minimize cleanly unmounts MainWrapper even with pointer Hover/Leave mid-unmount & while minimized
	;(function()
		local prevReduced = Bali2.Tween.Reduced
		Bali2.Tween.Reduced = false
		local winMin = Bali2:CreateWindow({ Title = "MinGhostTest", ConfirmClose = false })
		local minTab = winMin:AddTab({ Title = "Main" })
		local minSec = minTab:AddSection({ Title = "Actions", Side = "Left" })
		local dBtn = minSec:AddButton({
			Title = "Reset Progress",
			Variant = "Danger",
			Callback = function() end,
		})
		local tBtn = minSec:AddToggle({ Title = "Auto Quest", Default = false })
		stepClock(0.2, true)

		local dHit = dBtn.Frame and dBtn.Frame:FindFirstChild("HitButton")
		local tHit = tBtn.Frame and tBtn.Frame:FindFirstChild("HitButton")
		assertTrue(dHit ~= nil and tHit ~= nil, "MinGhostTest Button and Toggle expose HitButton")

		local actionsWrap = winMin.Main and winMin.Main:FindFirstChild("QuickActions", true)
		local minBtnInst = nil
		if actionsWrap then
			for _, ch in ipairs(actionsWrap:GetChildren()) do
				if ch:IsA("TextButton") and ch.LayoutOrder == 5 then
					minBtnInst = ch
				end
			end
		end
		assertTrue(minBtnInst ~= nil, "Window QuickActions contains Minimize button")

		if minBtnInst and dHit and tHit then
			dHit.MouseEnter:Fire()
			minBtnInst.MouseEnter:Fire()
			minBtnInst.Activated:Fire()

			-- Mid-unmount before tween defers/timers settle
			assertTrue(Bali2.Transition.IsHiddenOrUnmounting(dBtn.Frame), "IsHiddenOrUnmounting returns true mid-unmount")
			minBtnInst.MouseLeave:Fire()
			dHit.MouseEnter:Fire()
			dHit.MouseLeave:Fire()
			tHit.MouseEnter:Fire()
			tHit.MouseLeave:Fire()

			stepClock(0.05, true)
			minBtnInst.MouseLeave:Fire()
			dHit.MouseEnter:Fire()
			dHit.MouseLeave:Fire()
			tHit.MouseEnter:Fire()
			tHit.MouseLeave:Fire()

			stepClock(0.3, true)
			assertEq(winMin:IsVisible(), false, "Window:IsVisible() is false after minimize")
			assertEq(winMin.MainWrapper.Visible, false, "MainWrapper.Visible is false after minimize even with hover/leave mid-unmount")

			-- Pointer moves while minimized must never re-show MainWrapper or restore ghost button/stroke visuals
			local bgTransWhileHidden = dBtn.Frame.BackgroundTransparency
			local tStroke = tBtn.Frame and tBtn.Frame:FindFirstChildOfClass("UIStroke")
			local strokeTransWhileHidden = tStroke and tStroke.Transparency
			dHit.MouseEnter:Fire()
			dHit.MouseLeave:Fire()
			tHit.MouseEnter:Fire()
			tHit.MouseLeave:Fire()
			stepClock(0.1, true)
			assertEq(winMin.MainWrapper.Visible, false, "MainWrapper.Visible remains false on pointer hover while minimized")
			assertEq(dBtn.Frame.BackgroundTransparency, bgTransWhileHidden, "Button BackgroundTransparency stays unchanged on ghost hover while minimized")
			if tStroke then
				assertEq(tStroke.Transparency, strokeTransWhileHidden, "Toggle UIStroke Transparency stays unchanged on ghost hover while minimized")
			end

			winMin:SetVisible(true)
			stepClock(0.3, true)
			assertEq(winMin:IsVisible(), true, "Window:IsVisible() is true after SetVisible(true)")
			assertEq(winMin.MainWrapper.Visible, true, "MainWrapper.Visible is true after SetVisible(true)")
			assertEq(winMin._morphing, false, "Window._morphing resets to false after restore")
			assertEq(Bali2.Transition.IsHiddenOrUnmounting(dBtn.Frame), false, "IsHiddenOrUnmounting returns false after restore")
		end

		winMin:Destroy()
		stepClock(0.15, true)
		Bali2.Tween.Reduced = prevReduced
	end)()

	-- CreateWindow with integrated KeySystem gate (non-blocking test)
	local winKey = Bali2:CreateWindow({
		Title = "KeyTest",
		KeySystem = {
			Title = "Bali Key Gate",
			Subtitle = "Verification",
			Keys = { "ValidKey" },
			SaveKey = false,
			Yield = false,
		},
	})
	assertTrue(winKey ~= nil, "CreateWindow with KeySystem(Yield=false) returns window/gate handle")
	if winKey and winKey.Destroy then
		winKey:Destroy()
		stepClock(0.1, true)
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Final Report
-- ══════════════════════════════════════════════════════════════════════════════

assertEq(#capturedWarnings, 0, "Zero warnings captured from Bali")
log(string.format("\n=== VERIFICATION SUMMARY: %d passed, %d failed, %d warnings ===", testPasses, #testFailures, #capturedWarnings))
if #capturedWarnings > 0 then
	for i, w in ipairs(capturedWarnings) do
		log(string.format("  WARN #%d: %s", i, w))
	end
end
if #testFailures > 0 then
	error("Verification failed with " .. tostring(#testFailures) .. " failure(s).")
end
