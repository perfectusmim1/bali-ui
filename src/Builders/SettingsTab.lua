--[[
	Bali UI · Builders/SettingsTab
	Builds a comprehensive "Settings" tab (Category "System") covering Appearance,
	Interface & HUD, Config Manager, and Session & Diagnostics.
]]

local Assets = require("Core/Assets")
local Theme = require("Core/Theme")
local Tween = require("Core/Tween")
local Util = require("Core/Util")
local Blur = require("Systems/Blur")
local Config = require("Systems/Config")
local KeybindList = require("Systems/KeybindList")
local Notification = require("Systems/Notification")
local Watermark = require("Systems/Watermark")

local SettingsTab = {}

function SettingsTab.Build(window, options)
	assert(type(window) == "table", "[Bali] SettingsTab.Build expects a Window")
	options = Util.Options(options, {
		Title = "Settings",
		Icon = "settings",
		Category = "System",
	}, "Title")

	local tab = window:AddTab({
		Title = options.Title,
		Icon = options.Icon,
		Category = options.Category,
	})
	tab._isSettingsTab = true

	-- ─── Appearance (Left) ───────────────────────────────────────────────────
	local appearance = tab:AddSection({
		Title = "Appearance",
		Subtitle = "Themes, accent palette, glass opacity, and motion.",
		Icon = "palette",
		Side = "Left",
	})

	local syncingTheme = false
	local themeDropdown = appearance:AddDropdown({
		Title = "Theme Preset",
		Description = "Choose a built-in obsidian or light theme.",
		Icon = "palette",
		Values = Theme.Order,
		Default = Theme.Name,
		Callback = function(value)
			if syncingTheme or not value then
				return
			end
			Theme.Set(value, true)
		end,
	})

	local accentPicker = appearance:AddColorPicker({
		Title = "Accent Color",
		Description = "Override primary highlights, active pills, and gradients.",
		Icon = "sparkles",
		Default = Theme.Current.Accent,
		Presets = {
			Color3.fromRGB(214, 64, 236),
			Color3.fromRGB(59, 130, 246),
			Color3.fromRGB(45, 212, 191),
			Color3.fromRGB(52, 211, 153),
			Color3.fromRGB(251, 113, 133),
			Color3.fromRGB(251, 191, 36),
		},
		Callback = function(color)
			if syncingTheme or typeof(color) ~= "Color3" then
				return
			end
			Theme.SetAccent(color, true)
		end,
	})

	local fontDropdown = appearance:AddDropdown({
		Title = "Font Family",
		Description = "Live typography across headers, labels, and controls.",
		Icon = "type",
		Values = Theme.FontOrder,
		Default = Theme.FontFamily,
		Callback = function(value)
			if syncingTheme or not value then
				return
			end
			Theme.SetFont(value)
		end,
	})

	local transparencySlider = appearance:AddSlider({
		Title = "Window Transparency",
		Description = "Adjust obsidian glass surface opacity.",
		Icon = "eye",
		Min = 0,
		Max = 0.45,
		Step = 0.01,
		Default = Theme.Current.BackgroundTransparency,
		Callback = function(value)
			if syncingTheme then
				return
			end
			Theme.SetValue("BackgroundTransparency", value, false)
		end,
	})

	local blurToggle = appearance:AddToggle({
		Title = "Background Blur",
		Description = "Softly blurs the 3D scene behind the window.",
		Icon = "droplet",
		Default = Blur.IsEnabled(),
		Callback = function(state)
			Blur.SetEnabled(state)
			if not syncingTheme and not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	local blurSlider = appearance:AddSlider({
		Title = "Blur Intensity",
		Icon = "sliders",
		Min = 2,
		Max = 28,
		Step = 1,
		Default = Blur.GetIntensity(),
		Callback = function(value)
			Blur.SetIntensity(value)
			if not syncingTheme and not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	local reduceMotionToggle = appearance:AddToggle({
		Title = "Reduce Motion",
		Description = "Use instant transitions across popups and panels.",
		Icon = "zap",
		Default = Tween.Reduced,
		Callback = function(state)
			Tween.Reduced = state == true
			if not syncingTheme and not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	local speedSlider = appearance:AddSlider({
		Title = "Animation Speed",
		Icon = "gauge",
		Min = 0.25,
		Max = 2.0,
		Step = 0.05,
		Suffix = "x",
		Default = Tween.Speed,
		Callback = function(value)
			Tween.Speed = value
			if not syncingTheme and not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	tab.Maid:Give(Theme.Changed:Connect(function(theme)
		syncingTheme = true
		pcall(function()
			if themeDropdown and themeDropdown.Set then
				themeDropdown:Set(Theme.Name, true)
			end
			if accentPicker and accentPicker.Set then
				accentPicker:Set(theme.Accent, nil, true)
			end
			if fontDropdown and fontDropdown.Set then
				fontDropdown:Set(Theme.FontFamily, true)
			end
			if transparencySlider and transparencySlider.Set then
				transparencySlider:Set(theme.BackgroundTransparency, true)
			end
		end)
		syncingTheme = false
	end))

	-- ─── Interface & HUD (Right) ─────────────────────────────────────────────
	local hud = tab:AddSection({
		Title = "Interface & HUD",
		Subtitle = "Toggle keybind, floating overlays, and toast placement.",
		Icon = "monitor",
		Side = "Right",
	})

	local toggleKeybind = hud:AddKeybind({
		Title = "Toggle UI Keybind",
		Description = "Show or hide the main workspace window.",
		Icon = "keyboard",
		Default = window:GetToggleKey(),
		AllowMouse = false,
		SyncList = false,
		ChangedCallback = function(key)
			if syncingTheme then
				return
			end
			window:SetToggleKey(key)
		end,
	})

	local watermarkToggle = hud:AddToggle({
		Title = "Watermark HUD",
		Description = "Floating telemetry pill with FPS, ping, and clock.",
		Icon = "activity",
		Default = Watermark.IsVisible(),
		Callback = function(state)
			if syncingTheme then
				return
			end
			Watermark.SetVisible(state)
			if not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	local keybindListToggle = hud:AddToggle({
		Title = "Keybind List HUD",
		Description = "Floating panel displaying active keybinds.",
		Icon = "list",
		Default = KeybindList.IsVisible(),
		Callback = function(state)
			if syncingTheme then
				return
			end
			KeybindList.SetVisible(state)
			if not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	local keybindModeSeg = hud:AddSegmented({
		Title = "Keybind List Mode",
		Icon = "list-checks",
		Values = { "ActiveOnly", "All" },
		Default = window._keybindListMode or "ActiveOnly",
		Callback = function(mode)
			if syncingTheme then
				return
			end
			window._keybindListMode = mode
			KeybindList.SetMode(mode)
			if not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	local notifDropdown = hud:AddDropdown({
		Title = "Notification Position",
		Icon = "bell",
		Values = { "BottomRight", "TopRight", "BottomLeft", "TopLeft" },
		Default = window._notificationPosition or "BottomRight",
		Callback = function(pos)
			if syncingTheme then
				return
			end
			window._notificationPosition = pos
			Notification.SetPosition(pos)
			if not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	local notifDurationSlider = hud:AddSlider({
		Title = "Notification Duration",
		Description = "Default toast visibility window before auto-dismiss.",
		Icon = "clock",
		Min = 1,
		Max = 15,
		Step = 0.5,
		Rounding = 1,
		Suffix = "s",
		Default = Notification.GetDefaultDuration(),
		Callback = function(val)
			if syncingTheme then
				return
			end
			Notification.SetDefaultDuration(val)
			if not Config.IsLoading() then
				Config.TriggerAutoSave()
			end
		end,
	})

	local defaultMobileBtn = true
	if window._mobileButton then
		defaultMobileBtn = window._mobileButton:IsEnabled()
	end
	local mobileBtnToggle = hud:AddToggle({
		Title = "Mobile Floating Button",
		Description = "Show draggable pill when minimized or on touch devices.",
		Icon = "layers",
		Default = defaultMobileBtn,
		Callback = function(state)
			if syncingTheme then
				return
			end
			window:SetMobileButtonEnabled(state)
		end,
	})

	local mobileModeToggle = hud:AddToggle({
		Title = "Mobile Compact Mode",
		Description = "Single-column stacked layout with compact sidebar and padding.",
		Icon = "smartphone",
		Default = window.IsMobileMode and window:IsMobileMode() or false,
		Callback = function(state)
			if syncingTheme then
				return
			end
			if window.SetMobileMode then
				window:SetMobileMode(state)
			end
		end,
	})

	-- ─── Config Manager (Right) ──────────────────────────────────────────────
	local configSection = tab:AddSection({
		Title = "Config Manager",
		Subtitle = "Save, load, and share workspace presets.",
		Icon = "folder",
		Side = "Right",
	})

	local autoSaveToggle = configSection:AddToggle({
		Title = "Auto-Save Workspace",
		Description = "Automatically save & restore all control states without creating profiles.",
		Icon = "save",
		Default = Config.GetAutoSave(),
		Callback = function(state)
			if syncingTheme then
				return
			end
			Config.SetAutoSave(state)
		end,
	})

	local folderName = window._configFolder or "Bali"
	configSection:AddLabel({
		Title = "Config Folder",
		Value = folderName,
		Icon = "folder-open",
	})

	local profileInput = configSection:AddInput({
		Title = "Profile Name",
		Icon = "pencil",
		Placeholder = "e.g. default, legit...",
		Clearable = true,
	})

	local initialProfiles = {}
	pcall(function()
		initialProfiles = Config.List() or {}
	end)

	local profileDropdown = configSection:AddDropdown({
		Title = "Saved Profiles",
		Icon = "folder",
		Values = initialProfiles,
		AllowNull = true,
	})

	local autoLoadLabel = configSection:AddLabel({
		Title = "Auto-Load Profile",
		Value = (function()
			local ok, name = pcall(Config.GetAutoLoad)
			return (ok and name and name ~= "") and tostring(name) or "None"
		end)(),
		Icon = "sparkles",
	})

	local function resolveProfileName()
		local typed = Util.Trim(profileInput:Get() or "")
		if typed ~= "" then
			return typed
		end
		local selected = profileDropdown:Get()
		if type(selected) == "string" and selected ~= "" then
			return selected
		end
		return ""
	end

	local function refreshProfiles()
		local ok, list = pcall(Config.List)
		local profiles = (ok and type(list) == "table") and list or {}
		if profileDropdown.SetValues then
			profileDropdown:SetValues(profiles)
		elseif profileDropdown.Refresh then
			profileDropdown:Refresh(profiles)
		end
		local okAuto, autoName = pcall(Config.GetAutoLoad)
		if autoLoadLabel and autoLoadLabel.SetValue then
			autoLoadLabel:SetValue((okAuto and autoName and autoName ~= "") and tostring(autoName) or "None")
		end
	end

	local function syncSettingsVisuals()
		syncingTheme = true
		pcall(function()
			themeDropdown:Set(Theme.Name, true)
			accentPicker:Set(Theme.Current.Accent, nil, true)
			fontDropdown:Set(Theme.FontFamily, true)
			transparencySlider:Set(Theme.Current.BackgroundTransparency, true)
			blurToggle:Set(Blur.IsEnabled(), true)
			blurSlider:Set(Blur.GetIntensity(), true)
			reduceMotionToggle:Set(Tween.Reduced, true)
			speedSlider:Set(Tween.Speed, true)
			toggleKeybind:Set(window:GetToggleKey(), "Toggle", true)
			watermarkToggle:Set(Watermark.IsVisible(), true)
			keybindListToggle:Set(KeybindList.IsVisible(), true)
			keybindModeSeg:Set(window._keybindListMode or "ActiveOnly", true)
			notifDropdown:Set(window._notificationPosition or "BottomRight", true)
			notifDurationSlider:Set(Notification.GetDefaultDuration(), true)
			if window._mobileButton then
				mobileBtnToggle:Set(window._mobileButton:IsEnabled(), true)
			end
			if window.IsMobileMode then
				mobileModeToggle:Set(window:IsMobileMode(), true)
			end
			autoSaveToggle:Set(Config.GetAutoSave(), true)
		end)
		syncingTheme = false
	end

	if window._configLoaded then
		tab.Maid:Give(window._configLoaded:Connect(syncSettingsVisuals))
	end

	configSection:AddButtonGroup({
		Buttons = {
			{
				Title = "Save",
				Icon = "save",
				Variant = "Primary",
				Callback = function()
					local name = resolveProfileName()
					if name == "" then
						window:Notify({ Title = "Config", Content = "Enter or select a profile name.", Type = "Warning" })
						return
					end
					local ok = Config.Save(name)
					refreshProfiles()
					profileDropdown:Set(name, true)
					window:Notify({
						Title = ok and "Config Saved" or "Save Failed",
						Content = ok and ("Saved profile '" .. name .. "'.") or "File system is unavailable.",
						Type = ok and "Success" or "Error",
					})
				end,
			},
			{
				Title = "Load",
				Icon = "upload",
				Variant = "Default",
				Callback = function()
					local name = resolveProfileName()
					if name == "" then
						window:Notify({ Title = "Config", Content = "Select a profile to load.", Type = "Warning" })
						return
					end
					local ok = Config.Load(name)
					syncSettingsVisuals()
					window:Notify({
						Title = ok and "Config Loaded" or "Load Failed",
						Content = ok and ("Loaded profile '" .. name .. "'.") or ("Could not load '" .. name .. "'."),
						Type = ok and "Success" or "Error",
					})
				end,
			},
			{
				Title = "Delete",
				Icon = "trash",
				Variant = "Danger",
				Callback = function()
					local name = resolveProfileName()
					if name == "" then
						window:Notify({ Title = "Config", Content = "Select a profile to delete.", Type = "Warning" })
						return
					end
					local ok = Config.Delete(name)
					refreshProfiles()
					window:Notify({
						Title = ok and "Config Deleted" or "Delete Failed",
						Content = ok and ("Removed profile '" .. name .. "'.") or ("Could not delete '" .. name .. "'."),
						Type = ok and "Info" or "Error",
					})
				end,
			},
		},
	})

	configSection:AddButtonGroup({
		Buttons = {
			{
				Title = "Refresh",
				Icon = "refresh",
				Variant = "Default",
				Callback = function()
					refreshProfiles()
					window:Notify({ Title = "Config", Content = "Profile list refreshed.", Type = "Info", Duration = 2.5 })
				end,
			},
			{
				Title = "Set Auto-Load",
				Icon = "badge-check",
				Variant = "Default",
				Callback = function()
					local name = resolveProfileName()
					Config.SetAutoLoad(name ~= "" and name or nil)
					refreshProfiles()
					window:Notify({
						Title = "Auto-Load Updated",
						Content = name ~= "" and ("Auto-load set to '" .. name .. "'.") or "Auto-load cleared.",
						Type = "Success",
					})
				end,
			},
		},
	})

	local jsonInput = configSection:AddInput({
		Title = "JSON Import / Export",
		Icon = "code",
		Placeholder = "Paste exported JSON payload...",
		Clearable = true,
	})

	configSection:AddButtonGroup({
		Buttons = {
			{
				Title = "Export JSON",
				Icon = "copy",
				Variant = "Default",
				Callback = function()
					local ok, payload = pcall(Config.Export, true)
					if ok and type(payload) == "string" then
						jsonInput:Set(payload, true)
						local copied = Util.SetClipboard(payload)
						window:Notify({
							Title = "Config Exported",
							Content = copied and "JSON copied to clipboard." or "JSON placed into the input field.",
							Type = "Success",
						})
					else
						window:Notify({ Title = "Export Failed", Content = "Unable to serialize config.", Type = "Error" })
					end
				end,
			},
			{
				Title = "Import JSON",
				Icon = "download",
				Variant = "Primary",
				Callback = function()
					local payload = Util.Trim(jsonInput:Get() or "")
					if payload == "" then
						window:Notify({ Title = "Import Failed", Content = "Paste JSON into the field first.", Type = "Warning" })
						return
					end
					local ok, result = pcall(Config.Import, payload)
					if ok and result then
						syncSettingsVisuals()
						window:Notify({ Title = "Config Imported", Content = "Workspace values restored.", Type = "Success" })
					else
						window:Notify({ Title = "Import Failed", Content = "Invalid or malformed JSON.", Type = "Error" })
					end
				end,
			},
		},
	})

	-- ─── Session & Diagnostics (Left) ────────────────────────────────────────
	local session = tab:AddSection({
		Title = "Session & Diagnostics",
		Subtitle = "Runtime status, asset pipeline, and cleanup.",
		Icon = "cpu",
		Side = "Left",
	})

	local versionText = "v1.0.0 (Atlas v" .. tostring(Assets.Data and Assets.Data.Version or "4") .. ")"
	local assetStatus = Assets.Available and "Custom Atlas Loaded" or "Glyph Fallback"
	local fsStatus = Util.FS.Supported() and "Supported" or "In-Memory Only"
	local deviceKind = Util.IsTouchDevice() and "Touch / Mobile" or "Desktop"

	local diagLabel = session:AddParagraph({
		Title = "Bali Runtime",
		Content = string.format(
			"Library %s  •  Assets: %s\nFile System: %s  •  Input: %s\nRegistered Elements: %d  •  Flags: %d",
			versionText,
			assetStatus,
			fsStatus,
			deviceKind,
			#window._elements,
			Util.Count(window._registry)
		),
	})

	session:AddButtonGroup({
		Buttons = {
			{
				Title = "Refresh Stats",
				Icon = "activity",
				Variant = "Default",
				Callback = function()
					if diagLabel and diagLabel.SetDesc then
						diagLabel:SetDesc(string.format(
							"Library %s  •  Assets: %s\nFile System: %s  •  Input: %s\nRegistered Elements: %d  •  Flags: %d",
							versionText,
							assetStatus,
							fsStatus,
							deviceKind,
							#window._elements,
							Util.Count(window._registry)
						))
					end
				end,
			},
			{
				Title = "Unload UI",
				Icon = "power",
				Variant = "Danger",
				Callback = function()
					window:Dialog({
						Title = "Unload Bali UI?",
						Content = "This permanently destroys all windows, keybinds, HUD elements, and lighting blur.",
						Icon = "power",
						Buttons = {
							{ Title = "Cancel", Variant = "Default" },
							{
								Title = "Unload",
								Variant = "Danger",
								Callback = function()
									window:Destroy()
								end,
							},
						},
					})
				end,
			},
		},
	})

	return tab
end

return SettingsTab
