--[[
	Bali UI · Entry Point
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

-- Clean up any previously loaded Bali (or legacy Lumina) instance on script re-execution
for _, key in ipairs({ "_BaliInstance", "_LuminaInstance" }) do
	local previousInstance = Util.Global(key)
	if type(previousInstance) == "table" and type(previousInstance.Destroy) == "function" then
		pcall(function()
			previousInstance:Destroy()
		end)
	end
end

local Bali = {
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
	Util.Env._BaliInstance = Bali
end

-- ─── Error Boundary & Safe Layer Helpers ─────────────────────────────────────

local handlingError = false
local lastErrorText = nil
local lastErrorAt = 0

local function handleRuntimeError(err)
	if handlingError or Bali._destroyed then
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
		Bali:Notify({
			Type = "Error",
			Title = "Callback Error",
			Content = message,
			Duration = 5,
		})
	end)

	handlingError = false
end

Util.ErrorHandler = handleRuntimeError

local function getGuiContainers()
	local containers = {}
	local seen = {}
	local function pushContainer(inst)
		if typeof(inst) == "Instance" and not seen[inst] then
			seen[inst] = true
			table.insert(containers, inst)
		end
	end

	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok then
			pushContainer(hui)
		end
	end

	local okCore, coreGui = pcall(function()
		return Services.CoreGui
	end)
	if okCore and typeof(coreGui) == "Instance" then
		local canParent = pcall(function()
			local probe = Instance.new("Folder")
			probe.Name = "_BaliProbe"
			probe.Parent = coreGui
			probe:Destroy()
		end)
		if canParent then
			pushContainer(coreGui)
		end
	end

	local okPlayer, localPlayer = pcall(function()
		return Services.Players.LocalPlayer
	end)
	if okPlayer and localPlayer then
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
		pushContainer(playerGui)
	end

	return containers
end

local function getSafeGuiParent()
	local containers = getGuiContainers()
	return containers[1]
end

local function cleanupOrphanGuis(excludeGui)
	for _, container in ipairs(getGuiContainers()) do
		pcall(function()
			for _, child in ipairs(container:GetChildren()) do
				if child ~= excludeGui and child:IsA("LayerCollector") then
					if child.Name == "BaliUI" or child.Name == "LuminaUI" then
						child:Destroy()
					end
				end
			end
		end)
	end

	pcall(function()
		local lighting = Services.Lighting
		if lighting then
			for _, name in ipairs({ "BaliBlur", "LuminaBlur" }) do
				local fx = lighting:FindFirstChild(name)
				if fx then
					fx:Destroy()
				end
			end
		end
	end)
end

cleanupOrphanGuis(nil)

function Bali:_ensureScreenGui()
	if self._screenGui and self._screenGui.Parent then
		return self._screenGui
	end

	cleanupOrphanGuis(nil)

	local parent = getSafeGuiParent()
	assert(typeof(parent) == "Instance", "[Bali] Unable to locate gethui, CoreGui, or PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BaliUI"
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

function Bali:_pruneLoaders()
	for index = #self._loaders, 1, -1 do
		local ctrl = self._loaders[index]
		if type(ctrl) ~= "table" or (ctrl.Frame ~= nil and not ctrl.Frame.Parent) then
			table.remove(self._loaders, index)
		end
	end
end

function Bali:_destroyNotifyLayer()
	if self._notifyLayer then
		pcall(function()
			self._notifyLayer:Destroy()
		end)
		self._notifyLayer = nil
	end
end

function Bali:_rearmState()
	self._destroyed = false
	Util.ErrorHandler = handleRuntimeError
	if type(Util.Env) == "table" then
		Util.Env._BaliInstance = self
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function Bali:CreateWindow(opts)
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

	if type(options.KeySystem) == "table" and options.KeySystem.Enabled ~= false then
		local ksOpts = {}
		for k, v in pairs(options.KeySystem) do
			ksOpts[k] = v
		end
		ksOpts.Title = ksOpts.Title or options.Title or "Bali"
		if ksOpts.Yield == nil then
			ksOpts.Yield = true
		end
		local verified = self:KeySystem(ksOpts)
		if ksOpts.Yield and not verified then
			return nil
		end
	end

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

	-- Use Bali's debounced, recursion-safe ErrorHandler on top of the active Window
	Util.ErrorHandler = handleRuntimeError

	return createdWindow
end

function Bali:Notify(opts)
	if self._destroyed then
		return nil
	end

	if #self._windows == 0 and not self._notifyReady then
		local screenGui = self:_ensureScreenGui()
		local layer = Create.New("Frame", {
			Name = "BaliNotifyHostLayer",
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

function Bali:KeySystem(opts)
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

function Bali:LoadingScreen(opts)
	self:_rearmState()
	pcall(Assets.Load)

	local screenGui = self:_ensureScreenGui()
	local ctrl = Loader.LoadingScreen(screenGui, opts)
	if type(ctrl) == "table" and ctrl.Frame then
		table.insert(self._loaders, ctrl)
	end
	return ctrl
end

function Bali:SetTheme(name, animate)
	return Theme.Set(name, animate)
end

function Bali:AddTheme(name, tbl)
	return Theme.Add(name, tbl)
end

function Bali:SetAccent(color, animate)
	return Theme.SetAccent(color, animate)
end

function Bali:SetFont(family)
	return Theme.SetFont(family)
end

function Bali:SetAutoSave(enabled)
	return Config.SetAutoSave(enabled)
end

function Bali:GetAutoSave()
	return Config.GetAutoSave()
end

function Bali:SetNotificationDuration(seconds)
	return Notification.SetDefaultDuration(seconds)
end

function Bali:GetNotificationDuration()
	return Notification.GetDefaultDuration()
end

function Bali:Destroy()
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
				win:Destroy(true)
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
	cleanupOrphanGuis(nil)

	self._maid:Clean()

	if Util.ErrorHandler == handleRuntimeError then
		Util.ErrorHandler = nil
	end
	if type(Util.Env) == "table" and Util.Env._BaliInstance == self then
		Util.Env._BaliInstance = nil
	end

	self._destroying = false
end

function Bali:Unload()
	return self:Destroy()
end

return Bali
