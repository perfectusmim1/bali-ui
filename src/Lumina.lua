--[[
	Lumina UI · Entry Point
	Obsidian glassmorphic UI suite for Roblox & Luau.
]]

local Assets = require("Core/Assets")
local Create = require("Core/Create")
local Icons = require("Core/Icons")
local Maid = require("Core/Maid")
local Services = require("Core/Services")
local Signal = require("Core/Signal")
local Theme = require("Core/Theme")
local Transition = require("Core/Transition")
local Tween = require("Core/Tween")
local Util = require("Core/Util")

local Blur = require("Systems/Blur")
local CommandPalette = require("Systems/CommandPalette")
local Config = require("Systems/Config")
local Input = require("Systems/Input")
local KeybindList = require("Systems/KeybindList")
local Notification = require("Systems/Notification")
local Tooltip = require("Systems/Tooltip")
local Watermark = require("Systems/Watermark")

local Dialog = require("Window/Dialog")
local Loader = require("Window/Loader")
local Window = require("Window/Window")

-- Clean up any previously loaded Lumina instance on script re-execution
local previousInstance = Util.Global("_LuminaInstance")
if type(previousInstance) == "table" and type(previousInstance.Destroy) == "function" then
	pcall(function()
		previousInstance:Destroy()
	end)
end

local Lumina = {
	Version = "1.0.0",

	-- Core modules
	Services = Services,
	Util = Util,
	Signal = Signal,
	Maid = Maid,
	Tween = Tween,
	Transition = Transition,
	Theme = Theme,
	Create = Create,
	Assets = Assets,
	Icons = Icons,

	-- Systems
	Input = Input,
	Tooltip = Tooltip,
	Notification = Notification,
	Blur = Blur,
	Watermark = Watermark,
	KeybindList = KeybindList,
	CommandPalette = CommandPalette,
	Config = Config,

	-- Window / Modal helpers
	Dialog = Dialog,
	Loader = Loader,
	Window = Window,

	Core = {
		Services = Services,
		Util = Util,
		Signal = Signal,
		Maid = Maid,
		Tween = Tween,
		Transition = Transition,
		Theme = Theme,
		Create = Create,
		Assets = Assets,
		Icons = Icons,
	},
	Systems = {
		Input = Input,
		Tooltip = Tooltip,
		Notification = Notification,
		Blur = Blur,
		Watermark = Watermark,
		KeybindList = KeybindList,
		CommandPalette = CommandPalette,
		Config = Config,
	},

	_maid = Maid.new(),
	_windows = {},
	_loaders = {},
	_screenGui = nil,
	_ownsScreenGui = true,
	_notifyLayer = nil,
	_notifyReady = false,
	_destroyed = false,
	_destroying = false,
}

if type(Util.Env) == "table" then
	Util.Env._LuminaInstance = Lumina
end

-- ─── Error Boundary & Safe Layer Helpers ─────────────────────────────────────

local handlingError = false
local lastErrorText = nil
local lastErrorAt = 0

local function handleRuntimeError(err)
	if handlingError or Lumina._destroyed then
		return
	end
	handlingError = true

	local message = tostring(err or "Unknown callback error")
	local now = os.clock()
	if message == lastErrorText and (now - lastErrorAt) < 1.2 then
		handlingError = false
		return
	end
	lastErrorText = message
	lastErrorAt = now

	pcall(function()
		Lumina:Notify({
			Type = "Error",
			Title = "Callback Error",
			Content = message,
			Duration = 5,
		})
	end)

	handlingError = false
end

Util.ErrorHandler = handleRuntimeError

local function getSafeGuiParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and typeof(hui) == "Instance" then
			return hui
		end
	end

	local okCore, coreGui = pcall(function()
		return Services.CoreGui
	end)
	if okCore and typeof(coreGui) == "Instance" then
		local canParent = pcall(function()
			local probe = Instance.new("Folder")
			probe.Name = "_LuminaProbe"
			probe.Parent = coreGui
			probe:Destroy()
		end)
		if canParent then
			return coreGui
		end
	end

	local okPlayer, localPlayer = pcall(function()
		return Services.Players.LocalPlayer
	end)
	if okPlayer and localPlayer then
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
		if playerGui then
			return playerGui
		end
	end

	return nil
end

function Lumina:_ensureScreenGui()
	if self._screenGui and self._screenGui.Parent then
		return self._screenGui
	end

	local parent = getSafeGuiParent()
	assert(typeof(parent) == "Instance", "[Lumina] Unable to locate gethui, CoreGui, or PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "LuminaUI"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100

	local parented = pcall(function()
		gui.Parent = parent
	end)
	if not parented or not gui.Parent then
		local okLp, lp = pcall(function()
			return Services.Players.LocalPlayer
		end)
		local pg = okLp and lp and lp:FindFirstChildOfClass("PlayerGui")
		if pg then
			gui.Parent = pg
		end
	end

	self._screenGui = gui
	self._ownsScreenGui = true
	return gui
end

function Lumina:_pruneLoaders()
	for index = #self._loaders, 1, -1 do
		local ctrl = self._loaders[index]
		if type(ctrl) ~= "table" or (ctrl.Frame ~= nil and not ctrl.Frame.Parent) then
			table.remove(self._loaders, index)
		end
	end
end

function Lumina:_destroyNotifyLayer()
	if self._notifyLayer then
		pcall(function()
			self._notifyLayer:Destroy()
		end)
		self._notifyLayer = nil
	end
end

function Lumina:_rearmState()
	self._destroyed = false
	Util.ErrorHandler = handleRuntimeError
	if type(Util.Env) == "table" then
		Util.Env._LuminaInstance = self
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function Lumina:CreateWindow(opts)
	self:_rearmState()

	local options = {}
	if type(opts) == "string" then
		options.Title = opts
	elseif type(opts) == "table" then
		for key, value in pairs(opts) do
			options[key] = value
		end
	end

	pcall(Assets.Load)
	Input.Init()

	local customGui = options.ScreenGui
	local screenGui = (typeof(customGui) == "Instance" and customGui) or self:_ensureScreenGui()
	options.ScreenGui = nil
	options.OwnsScreenGui = false

	-- Tear down any pre-window temporary notification host before Window takes over
	self:_destroyNotifyLayer()

	local userOnDestroy = options.OnDestroy
	local createdWindow
	options.OnDestroy = function()
		for i = #self._windows, 1, -1 do
			if self._windows[i] == createdWindow then
				table.remove(self._windows, i)
			end
		end

		if type(userOnDestroy) == "function" then
			Util.SafeCall(userOnDestroy)
		end

		if #self._windows == 0 then
			self._notifyReady = false
			self:_pruneLoaders()
			if not self._destroying and #self._loaders == 0 and self._ownsScreenGui and self._screenGui then
				pcall(function()
					self._screenGui:Destroy()
				end)
				self._screenGui = nil
			end
		else
			-- Keep error boundary active while other windows remain open
			Util.ErrorHandler = handleRuntimeError
		end
	end

	createdWindow = Window.new(screenGui, options)
	table.insert(self._windows, createdWindow)
	self._notifyReady = true

	-- Use Lumina's debounced, recursion-safe ErrorHandler on top of the active Window
	Util.ErrorHandler = handleRuntimeError

	return createdWindow
end

function Lumina:Notify(opts)
	if self._destroyed then
		return nil
	end

	if #self._windows == 0 and not self._notifyReady then
		local screenGui = self:_ensureScreenGui()
		local layer = Create.New("Frame", {
			Name = "LuminaNotifyHostLayer",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 300,
			Parent = screenGui,
		})
		self._notifyLayer = layer
		Notification.Init(layer)
		self._notifyReady = true
	end

	return Notification.Notify(opts)
end

function Lumina:KeySystem(opts)
	self:_rearmState()
	pcall(Assets.Load)
	Input.Init()

	local screenGui = self:_ensureScreenGui()
	local r1, r2 = Loader.KeySystem(screenGui, opts)
	if type(r1) == "table" and r1.Frame then
		table.insert(self._loaders, r1)
	end
	return r1, r2
end

function Lumina:LoadingScreen(opts)
	self:_rearmState()
	pcall(Assets.Load)

	local screenGui = self:_ensureScreenGui()
	local ctrl = Loader.LoadingScreen(screenGui, opts)
	if type(ctrl) == "table" and ctrl.Frame then
		table.insert(self._loaders, ctrl)
	end
	return ctrl
end

function Lumina:SetTheme(name, animate)
	return Theme.Set(name, animate)
end

function Lumina:AddTheme(name, tbl)
	return Theme.Add(name, tbl)
end

function Lumina:SetAccent(color, animate)
	return Theme.SetAccent(color, animate)
end

function Lumina:SetFont(family)
	return Theme.SetFont(family)
end

function Lumina:Destroy()
	if self._destroying then
		return
	end
	self._destroying = true
	self._destroyed = true

	for i = #self._loaders, 1, -1 do
		local ctrl = self._loaders[i]
		if type(ctrl) == "table" and type(ctrl.Destroy) == "function" then
			pcall(function()
				ctrl:Destroy()
			end)
		end
		self._loaders[i] = nil
	end

	local activeWindows = Util.Copy(self._windows)
	table.clear(self._windows)
	for _, win in ipairs(activeWindows) do
		if type(win) == "table" and type(win.Destroy) == "function" then
			pcall(function()
				win:Destroy()
			end)
		end
	end

	pcall(CommandPalette.Destroy)
	pcall(KeybindList.Destroy)
	pcall(Watermark.Destroy)
	pcall(Notification.Destroy)
	pcall(Tooltip.Destroy)
	pcall(Blur.Destroy)
	pcall(Input.Destroy)

	self:_destroyNotifyLayer()
	self._notifyReady = false

	if self._ownsScreenGui and self._screenGui then
		pcall(function()
			self._screenGui:Destroy()
		end)
	end
	self._screenGui = nil

	self._maid:Clean()

	if Util.ErrorHandler == handleRuntimeError then
		Util.ErrorHandler = nil
	end
	if type(Util.Env) == "table" and Util.Env._LuminaInstance == self then
		Util.Env._LuminaInstance = nil
	end

	self._destroying = false
end

function Lumina:Unload()
	return self:Destroy()
end

return Lumina
