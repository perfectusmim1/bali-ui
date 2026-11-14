# Themes & Config Persistence

Bali supports instant live re-theming without rebuilding UI trees, alongside built-in JSON configuration serialization and auto-loading.

---

## Built-in Themes (`Theme.Presets`)

Seven curated palettes ship out of the box (`Graphite` is default):

| Theme Preset | Surface Aesthetic | Primary Accent |
| :--- | :--- | :--- |
| **`Graphite`** *(Default)* | Matte charcoal titanium (`#111113`) | Sapphire (`#0A84FF`) |
| **`Midnight`** | Deep obsidian slate (`#0B0B0E`) | Electric Violet (`#D640EC`) |
| **`Ocean`** | Midnight navy obsidian (`#090C15`) | Cobalt Blue (`#3B82F6`) |
| **`Aurora`** | Deep teal void (`#080E0F`) | Luminous Cyan (`#2DD4BF`) |
| **`Sunset`** | Obsidian plum (`#0F0B0C`) | Warm Coral (`#FB7185`) |
| **`Emerald`** | Pine dark glass (`#090D0B`) | Emerald Mint (`#34D399`) |
| **`Light`** | Soft Apple light frosted surface (`#F2F2F7`) | Classic Blue (`#007AFF`) |

### Switching Themes, Accents & Fonts at Runtime

```lua
Bali:SetTheme("Ocean", true) -- second arg animates property transitions
Bali:SetAccent(Color3.fromRGB(59, 130, 246), true)
Bali:SetFont("Montserrat") -- "Montserrat" (Default) | "Gotham" | "Builder" | "Ubuntu" | "Nunito"
```

### Registering Custom Themes (`AddTheme`)

```lua
Bali:AddTheme("ObsidianAmber", {
	Dark = true,
	Accent = Color3.fromRGB(245, 158, 11),
	Accent2 = Color3.fromRGB(217, 119, 6),
	Background = Color3.fromRGB(10, 10, 12),
	Card = Color3.fromRGB(19, 19, 24),
})

Bali:SetTheme("ObsidianAmber", true)
```

---

## Configuration Manager (`Systems/Config`)

Any element created with `Flag = "UniqueId"` participates automatically in JSON save/load snapshots, along with theme, accent color, font family, HUD states, and animation speed preferences.

```lua
local Config = Bali.Config

Config.Save("production")
Config.Load("production")
Config.SetAutoLoad("production")

local jsonSnapshot = Config.Export()
Config.Import(jsonSnapshot)
```

Configs persist to the configured folder (`ConfigFolder`, default `"BaliConfigs"`) when executor filesystem APIs (`writefile`, `readfile`, `isfile`, `makefolder`, `listfiles`, `delfile`) are present, and fall back transparently to an in-memory store inside Roblox Studio so `Save` / `Load` / `Export` never error.

---

## Prebuilt Settings Tab (`window:BuildSettingsTab`)

Generate a full two-column Settings tab in a single call with live Theme switcher, Accent color picker, Font selector, Window opacity/Blur sliders, Toggle Key picker, HUD overlay switches (`Watermark`, `KeybindList`, `NotificationPosition`, `NotificationDuration`, `MobileButton`, `MobileCompactMode`), Animation Speed / Reduce Motion controls, JSON Config Profile & `AutoSave` manager, and Runtime Diagnostics (`Unload UI`):

```lua
window:BuildSettingsTab({
	Title = "Settings",
	Icon = "settings",
	Category = "System",
})
```
