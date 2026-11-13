# Getting Started

**Bali** ships as modular Luau source (`src/`) and standalone single-file bundles (`dist/Bali.lua`, `dist/BaliExample.lua`) with zero runtime `loadstring` chains and automatic re-execution cleanup.

---

## Quickstart (Executor)

### Run the Interactive Showcase

Execute the prebuilt showcase script to preview every window container, telemetry chart, control variant, theme preset, key gate, and command palette live in Roblox:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/bali-ui/master/dist/BaliExample.lua"))()
```

### Build Your Own Interface

Load `dist/Bali.lua`, initialize a window, create tabs and sections, and bind interactive controls:

```lua
local Bali = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/bali-ui/master/dist/Bali.lua"))()

local window = Bali:CreateWindow({
	Title = "Bali Workspace",
	Subtitle = "v1.0.0",
	Icon = "sparkles",
	Theme = "Midnight",
	Blur = true,
	Watermark = true,
	KeybindList = true,
	ConfigFolder = "BaliWorkspace",
})

local overview = window:AddTab({
	Title = "Dashboard",
	Icon = "layout-dashboard",
	Category = "Overview",
	Badge = "Live",
})

local section = overview:AddSection({
	Title = "Automation",
	Subtitle = "Core runtime controls.",
	Icon = "zap",
	Side = "Left",
})

section:AddToggle({
	Title = "Live Telemetry",
	Description = "Stream workspace samples every second.",
	Default = true,
	Keybind = Enum.KeyCode.F,
	Flag = "LiveTelemetry",
	Callback = function(enabled)
		print("Telemetry:", enabled)
	end,
})

window:BuildSettingsTab({
	Title = "Settings",
	Icon = "settings",
	Category = "System",
})
```

---

## Roblox Studio Setup (`ModuleScript`)

Bali works inside Roblox Studio without executor-only APIs:

1. Copy the contents of [`dist/Bali.lua`](../dist/Bali.lua) into a `ModuleScript` (for example `ReplicatedStorage.Bali`).
2. Require and run it from any `LocalScript`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bali = require(ReplicatedStorage:WaitForChild("Bali"))

local window = Bali:CreateWindow({
	Title = "Studio Workspace",
	Theme = "Midnight",
	ShowUser = true,
})
```

---

## `ScreenGui` Hosting & Safe Re-Execution

Calling `Bali:CreateWindow()` resolves the highest-privilege GUI container automatically in order:

1. `gethui()` (when provided by the runtime)
2. `Services.CoreGui`
3. `LocalPlayer:FindFirstChildOfClass("PlayerGui")`

Each root `ScreenGui` is configured with:

- `Name = "BaliUI"`
- `IgnoreGuiInset = true`
- `ResetOnSpawn = false`
- `ZIndexBehavior = Enum.ZIndexBehavior.Sibling`
- `DisplayOrder = 100`

### Orphan & Duplicate Cleanup

Executing Bali multiple times in the same session automatically unloads the previous `_BaliInstance` global hook, sweeps leftover `BaliUI` / legacy `ScreenGui` instances and lighting blur effects, disconnects active `Maid` tasks, and recreates the fresh interface without overlapping windows or leaked event listeners.

You can also tear down everything manually at any time:

```lua
Bali:Unload()
-- or
Bali:Destroy()
```
